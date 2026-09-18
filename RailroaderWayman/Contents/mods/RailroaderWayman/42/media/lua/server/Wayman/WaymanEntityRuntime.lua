-- Authoritative server runtime for Wayman rail entities. It resolves physical
-- multi-square entities, normalizes their relative geometry against trusted
-- defaults, maintains their absolute node blocks/switches in global ModData,
-- applies graph-editor transactions, and synchronizes accepted changes.
require "Wayman/WaymanEntityGeometry"
require "Wayman/WaymanEntityDescriptor"
require "Wayman/WaymanGraphData"

RailroaderWaymanEntityRuntime = RailroaderWaymanEntityRuntime or {}

local WORLD_DATA_KEY = "RailroaderWayman_World"
local OBJECT_DATA_KEY = "railroaderWayman"
local pending = {}
local GraphData = RailroaderWaymanGraphData
local EntityDescriptor = RailroaderWaymanEntityDescriptor

--- Writes a namespaced runtime diagnostic to the Project Zomboid log.
local function log(message)
    print("[RailroaderWayman] EntityRuntime: " .. message)
end

--- Allocates a persistent turn or turnout owner ID from global counters.
local function nextId(kind, worldData)
    worldData = GraphData.ensure(worldData or ModData.getOrCreate(WORLD_DATA_KEY))
    local counterKey = kind == "turnout" and "nextTurnoutId" or "nextTurnId"
    local value = worldData[counterKey] or 1
    worldData[counterKey] = value + 1
    return (kind == "turnout" and "turnout_" or "turn_") .. tostring(value)
end

--- Converts one entity-relative node into absolute world coordinates.
local function absoluteNode(origin, node)
    return {
        x = origin.x + node.x,
        y = origin.y + node.y,
        z = origin.z + (node.z or 0),
    }
end

--- Builds an indivisible global node block from relative entity geometry.
local function makeNodeBlock(owner, id, origin, relativeNodes)
    local nodes = {}
    for _, node in ipairs(relativeNodes) do
        table.insert(nodes, absoluteNode(origin, node))
    end
    return {
        blockId = owner .. ":" .. id,
        owner = owner,
        id = id,
        nodes = nodes,
    }
end

--- Uses a turnout branch list or falls back to its shared `at` node.
local function nodesOrAt(at, nodes)
    if nodes and #nodes > 0 then return nodes end
    return { at }
end

--- Builds a turn registration without mutating global graph state.
local function buildTurnRegistration(owner, geometry, origin)
    if not geometry.nodes or #geometry.nodes == 0 then
        return nil, "turn geometry has no nodes"
    end
    return { blocks = { makeNodeBlock(owner, "nodes", origin, geometry.nodes) } }
end

--- Builds a turnout registration without mutating global graph state.
local function buildTurnoutRegistration(owner, geometry, origin)
    if not geometry.at then return nil, "turnout geometry has no at node" end
    return {
        blocks = {
            makeNodeBlock(owner, "at", origin, { geometry.at }),
            makeNodeBlock(owner, "through", origin,
                nodesOrAt(geometry.at, geometry.throughNodes)),
            makeNodeBlock(owner, "diverge", origin,
                nodesOrAt(geometry.at, geometry.divergingNodes)),
        },
        switch = {
            id = owner,
            owner = owner,
            at = absoluteNode(origin, geometry.at),
            legs = {
                throat = {},
                through = {},
                diverge = {},
            },
        },
    }
end

local registrationBuilders = {
    turn = buildTurnRegistration,
    turnout = buildTurnoutRegistration,
}

--- Builds and appends one complete entity registration to staged graph data.
local function registerGeometry(worldData, owner, geometry, origin)
    GraphData.ensure(worldData)
    local builder = registrationBuilders[geometry.kind]
    if not builder then return false, "unsupported geometry kind " .. tostring(geometry.kind) end
    local registration, reason = builder(owner, geometry, origin)
    if not registration then return false, reason end

    for _, block in ipairs(registration.blocks) do
        table.insert(worldData.availableNodes, block)
    end
    if registration.switch then
        table.insert(worldData.switches, registration.switch)
    end
    worldData.revision = worldData.revision + 1
    return true
end

--- Broadcasts authoritative Wayman world data when running as a server.
local function transmitWorldData()
    if isServer() and ModData.transmit then ModData.transmit(WORLD_DATA_KEY) end
end

--- Removes all graph records owned by an entity, optionally preserving update state.
local function removeOwner(owner, suppressNotification, preserveEmptyEdges, targetWorldData)
    if not owner then return false end
    local worldData = GraphData.ensure(targetWorldData or ModData.getOrCreate(WORLD_DATA_KEY))
    local removed = false
    local available = {}
    for _, block in ipairs(worldData.availableNodes) do
        if block.owner == owner then removed = true else table.insert(available, block) end
    end
    worldData.availableNodes = available

    local removedEdges = {}
    for edgeId, blocks in pairs(worldData.edges) do
        local kept = {}
        for _, block in ipairs(blocks) do
            if block.owner == owner then removed = true else table.insert(kept, block) end
        end
        if #kept == 0 and not preserveEmptyEdges then
            removedEdges[edgeId] = true
            worldData.edges[edgeId] = nil
        else
            worldData.edges[edgeId] = kept
        end
    end

    local switches = {}
    for _, switch in ipairs(worldData.switches) do
        if switch.owner == owner then
            removed = true
        else
            for _, legName in ipairs({ "throat", "through", "diverge" }) do
                local leg = switch.legs and switch.legs[legName]
                if leg and removedEdges[leg.edge] then switch.legs[legName] = {} end
            end
            table.insert(switches, switch)
        end
    end
    worldData.switches = switches
    if removed and not suppressNotification then
        worldData.revision = worldData.revision + 1
        transmitWorldData()
        log("removed global graph data for " .. tostring(owner)
            .. " at revision " .. tostring(worldData.revision))
    end
    return removed
end

--- Checks that a submitted relative node contains finite-compatible numeric fields.
local function validNode(node)
    local function finite(value)
        return type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge
    end
    return type(node) == "table" and finite(node.x) and finite(node.y)
        and (node.z == nil or finite(node.z))
end

--- Validates staged graph invariants before replacing authoritative collections.
local function validateGraphState(worldData)
    local seenBlocks = {}
    local function validateBlock(block)
        if type(block) ~= "table" or type(block.blockId) ~= "string"
            or type(block.owner) ~= "string" or type(block.id) ~= "string" then
            return false, "invalid node block"
        end
        if seenBlocks[block.blockId] then return false, "duplicate node block " .. block.blockId end
        if type(block.nodes) ~= "table" or #block.nodes == 0 then
            return false, "empty node block " .. block.blockId
        end
        for _, node in ipairs(block.nodes) do
            if not validNode(node) then return false, "invalid node in " .. block.blockId end
        end
        seenBlocks[block.blockId] = true
        return true
    end

    for _, block in ipairs(worldData.availableNodes or {}) do
        local ok, reason = validateBlock(block)
        if not ok then return false, reason end
    end
    for edgeId, blocks in pairs(worldData.edges or {}) do
        if type(edgeId) ~= "string" or type(blocks) ~= "table" or #blocks == 0 then
            return false, "invalid or empty edge " .. tostring(edgeId)
        end
        for _, block in ipairs(blocks) do
            local ok, reason = validateBlock(block)
            if not ok then return false, reason end
        end
    end

    local seenSwitches = {}
    for _, switch in ipairs(worldData.switches or {}) do
        if type(switch) ~= "table" or type(switch.id) ~= "string" or seenSwitches[switch.id]
            or not validNode(switch.at) then
            return false, "invalid or duplicate switch " .. tostring(switch and switch.id)
        end
        seenSwitches[switch.id] = true
        for _, legName in ipairs({ "throat", "through", "diverge" }) do
            local leg = switch.legs and switch.legs[legName] or {}
            if (leg.edge == nil) ~= (leg.toward == nil) then
                return false, "incomplete " .. legName .. " leg on " .. switch.id
            end
            if leg.edge and not worldData.edges[leg.edge] then
                return false, "switch " .. switch.id .. " references missing edge " .. leg.edge
            end
            if leg.toward and leg.toward ~= "start" and leg.toward ~= "end" then
                return false, "invalid toward on " .. switch.id
            end
        end
    end
    return true
end

--- Copies a valid relative node into the normalized geometry format.
local function copyNode(node)
    if not validNode(node) then return nil end
    return { x = node.x, y = node.y, z = node.z or 0 }
end

--- Normalizes an untrusted node list, falling back as a whole to server defaults.
local function normalizeNodeList(value, fallback, allowEmpty)
    -- An absent list, or a disallowed empty list, selects the trusted default.
    local source = value
    if type(source) ~= "table" or (#source == 0 and not allowEmpty) then source = fallback end
    if type(source) ~= "table" then return {} end

    -- Never keep a partially valid client list: one invalid node replaces the
    -- complete supplied list with its server-owned fallback.
    local result = {}
    for _, node in ipairs(source) do
        local copied = copyNode(node)
        if not copied then
            if source ~= fallback then return normalizeNodeList(fallback, {}, allowEmpty) end
            return {}
        end
        table.insert(result, copied)
    end
    return result
end

--- Produces normalized turn geometry from untrusted overrides and defaults.
local function effectiveTurnGeometry(defaults, supplied)
    return { kind = "turn", nodes = normalizeNodeList(supplied.nodes, defaults.nodes, false) }
end

--- Produces normalized turnout geometry from untrusted overrides and defaults.
local function effectiveTurnoutGeometry(defaults, supplied)
    return {
        kind = "turnout",
        at = copyNode(supplied.at) or copyNode(defaults.at),
        switch = copyNode(supplied.switch) or copyNode(defaults.switch),
        throughNodes = normalizeNodeList(supplied.throughNodes, defaults.throughNodes, true),
        divergingNodes = normalizeNodeList(supplied.divergingNodes, defaults.divergingNodes, true),
    }
end

local effectiveGeometryBuilders = {
    turn = effectiveTurnGeometry,
    turnout = effectiveTurnoutGeometry,
}

--- Produces server-approved geometry through the handler for its entity kind.
local function effectiveGeometry(defaults, supplied)
    supplied = type(supplied) == "table" and supplied or {}
    local builder = effectiveGeometryBuilders[defaults.kind]
    if not builder then return nil, "unsupported geometry kind " .. tostring(defaults.kind) end
    return builder(defaults, supplied)
end

--- Reports whether an owner is represented anywhere in the global graph state.
local function ownerExists(worldData, owner)
    if not owner then return false end
    for _, block in ipairs(worldData.availableNodes) do if block.owner == owner then return true end end
    for _, blocks in pairs(worldData.edges) do
        for _, block in ipairs(blocks) do if block.owner == owner then return true end end
    end
    for _, switch in ipairs(worldData.switches) do if switch.owner == owner then return true end end
    return false
end

--- Captures edge positions, inversions, and switch legs before geometry replacement.
local function capturePlacement(worldData, owner)
    local result = { blocks = {}, legs = nil }
    for _, block in ipairs(worldData.availableNodes) do
        if block.owner == owner then result.blocks[block.id] = { available = true } end
    end
    for edgeId, blocks in pairs(worldData.edges) do
        for index, block in ipairs(blocks) do
            if block.owner == owner then
                result.blocks[block.id] = {
                    edgeId = edgeId,
                    index = index,
                    invertNodes = block.invertNodes == true,
                }
            end
        end
    end
    for _, switch in ipairs(worldData.switches) do
        if switch.owner == owner then result.legs = GraphData.copy(switch.legs) break end
    end
    return result
end

--- Restores graph membership and switch configuration after rebuilding geometry.
local function restorePlacement(worldData, owner, placement)
    for index = #worldData.availableNodes, 1, -1 do
        local block = worldData.availableNodes[index]
        local target = block.owner == owner and placement.blocks[block.id]
        if target and target.edgeId and worldData.edges[target.edgeId] then
            table.remove(worldData.availableNodes, index)
            block.invertNodes = target.invertNodes or nil
            local edge = worldData.edges[target.edgeId]
            table.insert(edge, math.min(target.index or (#edge + 1), #edge + 1), block)
        end
    end
    if placement.legs then
        for _, switch in ipairs(worldData.switches) do
            if switch.owner == owner then switch.legs = placement.legs break end
        end
    end
end

--- Recovers or updates an entity using server defaults and authoritative registration.
function RailroaderWaymanEntityRuntime.SaveGeometry(object, submittedData, requestedFacing)
    if isClient() then return false, "server authority required" end
    -- Resolve the physical object and its trusted geometry definition.
    local entity, reason = EntityDescriptor.describe(object, requestedFacing)
    if not entity then
        log("geometry update skipped: " .. tostring(reason))
        return false, reason
    end

    local worldData = GraphData.ensure(ModData.getOrCreate(WORLD_DATA_KEY))
    local objectData = entity.master:getModData()
    local serverData = objectData[OBJECT_DATA_KEY]
    submittedData = type(submittedData) == "table" and submittedData or {}

    -- Identity is server-owned. Client modData may supply geometry overrides,
    -- but it cannot select another entity's owner ID.
    local serverId = serverData and serverData.id
    local owner = ownerExists(worldData, serverId) and serverId or nil

    -- Stage removal, rebuilding, and placement restoration on an isolated copy.
    -- The authoritative graph remains untouched if any phase fails.
    local staged = GraphData.copy(worldData)
    local placement
    if owner then
        placement = capturePlacement(staged, owner)
        removeOwner(owner, true, true, staged)
    else
        owner = nextId(entity.defaults.kind, staged)
        placement = { blocks = {} }
    end

    -- Normalize untrusted fields, build canonical absolute records, and restore
    -- the entity's prior edge position/inversion and switch legs.
    local geometry, geometryReason = effectiveGeometry(entity.defaults, submittedData)
    if not geometry then return false, geometryReason end
    local registered, registerReason = registerGeometry(staged, owner, geometry, entity.origin)
    if not registered then
        log("geometry update skipped: " .. tostring(registerReason))
        return false, registerReason
    end
    restorePlacement(staged, owner, placement)

    local valid, validationReason = validateGraphState(staged)
    if not valid then
        log("geometry update skipped: " .. tostring(validationReason))
        return false, validationReason
    end

    -- Commit the staged collections only after the replacement is complete.
    worldData.availableNodes = staged.availableNodes
    worldData.edges = staged.edges
    worldData.switches = staged.switches
    worldData.nextTurnId = staged.nextTurnId
    worldData.nextTurnoutId = staged.nextTurnoutId
    worldData.revision = staged.revision

    -- Persist relative geometry on the physical entity so it can be recovered
    -- independently of loaded squares and reconstructed with a fresh origin.
    local saved = { id = owner }
    if geometry.kind == "turn" then
        saved.nodes = GraphData.copy(geometry.nodes)
    else
        saved.at = GraphData.copy(geometry.at)
        saved.switch = GraphData.copy(geometry.switch)
        saved.throughNodes = GraphData.copy(geometry.throughNodes)
        saved.divergingNodes = GraphData.copy(geometry.divergingNodes)
    end
    objectData[OBJECT_DATA_KEY] = saved
    if isServer() then entity.master:transmitModData() end
    transmitWorldData()
    log("saved geometry for " .. tostring(owner) .. " from " .. tostring(entity.entityName)
        .. " facing " .. tostring(entity.facing)
        .. " at revision " .. tostring(worldData.revision))
    return true, owner
end

--- Performs deferred OnCreate initialization unless the owner is already registered.
local function initialize(object, requestedFacing)
    local entity, reason = EntityDescriptor.describe(object, requestedFacing)
    if not entity then
        log("initialization skipped: " .. tostring(reason))
        return false
    end
    local objectData = entity.master:getModData()
    local waymanData = objectData[OBJECT_DATA_KEY]
    local worldData = GraphData.ensure(ModData.getOrCreate(WORLD_DATA_KEY))
    if waymanData and ownerExists(worldData, waymanData.id) then
        log("already initialized: " .. tostring(waymanData.id))
        return true
    end
    return RailroaderWaymanEntityRuntime.SaveGeometry(
        entity.master, waymanData, entity.facing)
end

--- Handles physical entity removal and atomically removes all owned graph data.
function RailroaderWaymanEntityRuntime.OnRemove(object)
    if isClient() then return end
    local master = EntityDescriptor.getMaster(object)
    if not master then return end
    for index = #pending, 1, -1 do
        if EntityDescriptor.getMaster(pending[index].object) == master then table.remove(pending, index) end
    end
    local data = master:getModData()[OBJECT_DATA_KEY]
    if data and data.id then removeOwner(data.id) end
end

--- Applies a validated graph-editor transaction to authoritative global state.
function RailroaderWaymanEntityRuntime.ApplyGraphDraft(draft, baseRevision)
    local worldData = GraphData.ensure(ModData.getOrCreate(WORLD_DATA_KEY))
    if type(draft) == "table" then draft.revision = baseRevision end
    local normalized, reason = GraphData.validateDraft(worldData, draft)
    if not normalized then
        log("graph update rejected: " .. tostring(reason))
        return false, reason
    end
    worldData.availableNodes = normalized.availableNodes
    worldData.edges = normalized.edges
    worldData.switches = normalized.switches
    worldData.nextEdgeId = normalized.nextEdgeId
    worldData.revision = normalized.revision
    transmitWorldData()
    log("graph update accepted at revision " .. tostring(worldData.revision))
    return true
end

--- Locates and verifies the server-side rail entity referenced by a client command.
local function findCommandObject(args)
    if type(args) ~= "table" then return nil end
    if type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number" then
        return nil
    end
    local square = getCell():getGridSquare(args.x, args.y, args.z)
    if not square then return nil end
    local objects = square:getObjects()
    local index = tonumber(args.objectIndex)
    if index and index >= 0 and index < objects:size() then
        local object = objects:get(index)
        local master = EntityDescriptor.getMaster(object)
        local script = master and master:getEntityScript()
        if script and RailroaderWaymanEntityGeometry[script:getName()] then return master end
    end
    for objectIndex = 0, objects:size() - 1 do
        local master = EntityDescriptor.getMaster(objects:get(objectIndex))
        local script = master and master:getEntityScript()
        if script and RailroaderWaymanEntityGeometry[script:getName()] then
            local data = master:getModData()[OBJECT_DATA_KEY]
            if not args.modData or not args.modData.id or (data and data.id == args.modData.id) then
                return master
            end
        end
    end
    return nil
end

--- Dispatches graph edits and manual entity-recovery commands from clients.
local function onClientCommand(module, command, player, args)
    if module ~= "RailroaderWayman" then return end
    if command == "applyGraph" then
        local ok, reason = RailroaderWaymanEntityRuntime.ApplyGraphDraft(
            args and args.draft, args and args.revision)
        if not ok and sendServerCommand then
            sendServerCommand(player, "RailroaderWayman", "graphRejected", {
                reason = reason,
            })
        end
    elseif command == "updateRailEntity" then
        local object = findCommandObject(args)
        local ok, result
        if object then
            ok, result = RailroaderWaymanEntityRuntime.SaveGeometry(
                object, args and args.modData, args and args.facing)
        else
            ok, result = false, "rail entity not found on server"
        end
        if sendServerCommand then
            sendServerCommand(player, "RailroaderWayman", "railEntityUpdated", {
                ok = ok,
                id = ok and result or nil,
                reason = ok and nil or result,
            })
        end
    end
end

--- Drains the deferred creation queue after multi-square objects finish setup.
local function initializePending()
    if #pending == 0 then return end
    local queued = pending
    pending = {}
    for _, entry in ipairs(queued) do
        initialize(entry.object, entry.facing)
    end
end

--- Queues authoritative initialization for a newly built multi-square entity.
function RailroaderWaymanEntityRuntime.OnCreate(params)
    -- Clients wait for the authoritative object's modData from SP/the server.
    if isClient() then
        log("OnCreate ignored on client")
        return
    end
    local object = params and params.thumpable
    if not object then
        log("OnCreate ignored: params.thumpable is nil")
        return
    end

    local spriteConfig = object:getSpriteConfig()
    if not spriteConfig or not spriteConfig:isMultiSquareMaster() then
        return
    end

    log("OnCreate queued facing " .. tostring(params.facing))
    table.insert(pending, {
        object = object,
        facing = params.facing and string.upper(params.facing) or nil,
    })
end

Events.OnTick.Add(initializePending)
Events.OnObjectAboutToBeRemoved.Add(RailroaderWaymanEntityRuntime.OnRemove)
Events.OnClientCommand.Add(onClientCommand)

log("loaded; authoritative=" .. tostring(not isClient()))
