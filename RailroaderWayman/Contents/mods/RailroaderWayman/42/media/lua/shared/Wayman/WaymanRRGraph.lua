-- Railroader graph adapter for Wayman. It converts authoritative Wayman graph
-- data into RR's route and edge/switch definitions and owns the integration calls
-- that can later be replaced by Railroader's public additive API.
require "Wayman/WaymanGraphData"
require "Wayman/WaymanEntityGeometry"


RailroaderWaymanRRGraph = RailroaderWaymanRRGraph or {}
local RRGraph = RailroaderWaymanRRGraph
local GraphData = RailroaderWaymanGraphData
local EntityGeometry = RailroaderWaymanEntityGeometry
local NETWORK_ID = "wayman"
local RAILROADER_DEFAULT_ROUTE = "main"
local EPSILON = 1e-6

--- @class RailroaderNode
--- @field x number
--- @field y number
--- @field z number
--- @field name string?
--- @field open boolean?

--- @class RailroaderSwitchPlace
--- @field x number
--- @field y number
--- @field z number
--- @field sprite string?
--- @field sprites {sprite:string, dx:number, dy:number}[]?

--- @class RailroaderSwitchLeg
--- @field edge string
--- @field toward string

--- @class RailroaderSwitch
--- @field id string
--- @field at {x:number, y:number, z:number}
--- @field place RailroaderSwitchPlace?
--- @field throat RailroaderSwitchLeg
--- @field through RailroaderSwitchLeg
--- @field diverge RailroaderSwitchLeg

--- @class RailroaderRoute

--- @class RailroaderGraph
--- @field edges table<string,RailroaderNode[]>
--- @field switches RailroaderSwitch[]
--- @field origin {edge:string, toward:string, s:number?}

--- Deep-copies plain Railroader graph definitions without sharing nested state.
local function copyGraphValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copyGraphValue(key, seen)] = copyGraphValue(child, seen)
    end
    return result
end

--- Captures Railroader's unmodified main graph once for repeatable patch rebuilds.
local function backupMainGraph(TrackGraph)
    if RRGraph.originalMainGraph then
        return copyGraphValue(RRGraph.originalMainGraph)
    end
    local original = TrackGraph.defs and TrackGraph.defs[RAILROADER_DEFAULT_ROUTE]
    if type(original) ~= "table" then
        return nil, "RR main graph is unavailable"
    end
    RRGraph.originalMainGraph = {
        edges = copyGraphValue(original.edges or {}),
        switches = copyGraphValue(original.switches or {}),
        origin = copyGraphValue(original.origin
            or { edge = RAILROADER_DEFAULT_ROUTE, toward = "end" }),
    }
    return copyGraphValue(RRGraph.originalMainGraph)
end

--- Overlays switches by ID while keeping replaced RR switches in their original order.
local function mergeSwitches(original, patch)
    local merged = copyGraphValue(original or {})
    local indexById = {}
    for index, switch in ipairs(merged) do
        if switch.id then indexById[switch.id] = index end
    end
    for _, switch in ipairs(patch or {}) do
        local copied = copyGraphValue(switch)
        local index = switch.id and indexById[switch.id] or nil
        if index then
            merged[index] = copied
        else
            table.insert(merged, copied)
            if switch.id then indexById[switch.id] = #merged end
        end
    end
    return merged
end

--- Builds a fresh main graph from RR's backup plus the current Wayman definition.
local function mergeMainGraph(TrackGraph, patch)
    local merged, reason = backupMainGraph(TrackGraph)
    if not merged then return nil, reason end
    for edgeId, nodes in pairs(patch.edges or {}) do
        merged.edges[edgeId] = copyGraphValue(nodes)
    end
    merged.switches = mergeSwitches(merged.switches, patch.switches)
    -- merged.origin = copyGraphValue(patch.origin or merged.origin)
    return merged
end

--- Writes a deterministic graph snapshot to console.txt without blocking export.
local function logGraphJSON(label, graph)
    local json, reason = GraphData.worldDataToJSON(graph)
    if json then
        print("[RailroaderWayman] " .. label .. " " .. json)
    else
        print("[RailroaderWayman] " .. label .. "_ERROR " .. tostring(reason))
    end
end

--- Converts a relative switch interaction place while retaining RR sprite metadata.
local function absolutePlace(origin, place)
    local result = GraphData.getAbsoluteNode(origin, place)
    if not result then return nil end
    result.sprite = place.sprite
    if type(place.sprites) == "table" then
        result.sprites = copyGraphValue(place.sprites)
    end
    return result
end

--- Copies a graph node into RR's plain absolute-coordinate representation.
--- @param node WaymanNode
--- @return WaymanNode
local function copyNode(node)
    return { x = node.x, y = node.y, z = node.z or 0 }
end

--- Copies a complete Wayman switch leg into RR's direct leg representation.
local function copyLeg(leg)
    if type(leg) ~= "table" or not leg.edge or not leg.toward then return nil end
    return { edge = leg.edge, toward = leg.toward }
end

--- Finds one canonical owner block regardless of its current graph placement.
local function findOwnerBlock(worldData, owner, blockId)
    for _, block in ipairs(worldData.availableNodes or {}) do
        if block.owner == owner and block.id == blockId then return block end
    end
    for _, blocks in pairs(worldData.edges or {}) do
        for _, block in ipairs(blocks) do
            if block.owner == owner and block.id == blockId then return block end
        end
    end
end

--- Compares absolute block nodes with one static list relative to its turnout at.
local function matchesRelativeNodes(block, absoluteAt, staticAt, staticNodes)
    local expected = staticNodes
    if not expected or #expected == 0 then expected = { staticAt } end
    local nodes = GraphData.getAbsoluteNodes(block)
    if not block or #nodes ~= #expected then return false end
    for index, node in ipairs(nodes) do
        local relative = expected[index]
        if math.abs((node.x - absoluteAt.x) - (relative.x - staticAt.x)) > EPSILON
            or math.abs((node.y - absoluteAt.y) - (relative.y - staticAt.y)) > EPSILON
            or math.abs(((node.z or 0) - (absoluteAt.z or 0))
                - ((relative.z or 0) - (staticAt.z or 0))) > EPSILON then
            return false
        end
    end
    return true
end

--- Resolves RR's interaction place from the matching static turnout geometry.
local function resolveStaticPlace(worldData, switch)
    local throughBlock = findOwnerBlock(worldData, switch.owner, "through")
    local divergeBlock = findOwnerBlock(worldData, switch.owner, "diverge")
    local resolved
    for _, faces in pairs(EntityGeometry) do
        for _, geometry in pairs(faces) do
            if geometry.kind == "turnout" and geometry.at and geometry.switch
                and matchesRelativeNodes(throughBlock, switch.at, geometry.at,
                    geometry.throughNodes)
                and matchesRelativeNodes(divergeBlock, switch.at, geometry.at,
                    geometry.divergingNodes) then
                local candidate = {
                    x = switch.at.x + geometry.switch.x - geometry.at.x,
                    y = switch.at.y + geometry.switch.y - geometry.at.y,
                    z = (switch.at.z or 0) + (geometry.switch.z or 0) - (geometry.at.z or 0),
                }
                if resolved and (math.abs(resolved.x - candidate.x) > EPSILON
                    or math.abs(resolved.y - candidate.y) > EPSILON
                    or math.abs(resolved.z - candidate.z) > EPSILON) then
                    return nil, "static turnout geometry is ambiguous for " .. tostring(switch.id)
                end
                resolved = candidate
            end
        end
    end
    if not resolved then
        return nil, "static turnout geometry was not found for " .. tostring(switch.id)
    end
    return resolved
end

--- Converts authoritative Wayman data into one RR TrackGraph definition.
--- @param graphData WaymanGraphData
--- @return RailroaderGraph?,string?
function RRGraph.export(graphData)
    if type(graphData) ~= "table" then return nil, "world data must be a table" end
    logGraphJSON("GRAPH_BEFORE_EXPORT", graphData)
    local definition = { edges = {}, switches = {} }

    -- edges
    for edgeId, blocks in pairs(graphData.edges or {}) do
        local nodes = GraphData.getOrderedNodes(blocks)
        if #nodes < 2 then return nil, "edge " .. tostring(edgeId) .. " has fewer than two nodes" end
        definition.edges[edgeId] = {}
        for _, node in ipairs(nodes) do
            table.insert(definition.edges[edgeId], copyNode(node))
        end
    end

    -- switches
    for _, switch in ipairs(graphData.switches or {}) do
        local absoluteAt = switch.at and GraphData.getAbsoluteNode(switch.origin, switch.at)
        local legs = switch.legs or {}
        local throat = copyLeg(legs.throat)
        local through = copyLeg(legs.through)
        local diverge = copyLeg(legs.diverge)
        local configured = throat or through or diverge
        if configured and not (switch.id and absoluteAt and throat and through and diverge) then
            return nil, "switch " .. tostring(switch.id) .. " is incomplete"
        end
        if configured then
            local exportSwitch = GraphData.copy(switch)
            exportSwitch.at = absoluteAt
            local place = switch.place and absolutePlace(switch.origin, switch.place)
            local placeReason
            if not place then
                place, placeReason = resolveStaticPlace(graphData, exportSwitch)
            end
            if not place then return nil, placeReason end
            table.insert(definition.switches, {
                id = switch.id,
                at = copyNode(absoluteAt),
                throat = throat,
                through = through,
                diverge = diverge,
                place = place,
            })
        end
    end

    -- origin
    local origin = graphData.origin or { edge = NETWORK_ID, toward = "end" }
    if type(origin) ~= "table"
        or (origin.edge ~= RAILROADER_DEFAULT_ROUTE and not definition.edges[origin.edge]) then
        return nil, "RR origin references missing edge " .. tostring(origin and origin.edge)
    end
    if origin.toward ~= "start" and origin.toward ~= "end" then
        return nil, "RR origin toward must be start or end"
    end
    definition.origin = {
        edge = origin.edge,
        toward = origin.toward,
        s = origin.s,
    }
    logGraphJSON("GRAPH_AFTER_EXPORT", definition)
    return definition
end

--- Registers the primary route and current graph through RR's replaceable integration boundary.
---@param graphData WaymanGraphData
function RRGraph.register(graphData)
    -- export mod graph data into Railroader Graph
    local definition, reason = RRGraph.export(graphData)
    if not definition then return false, reason end

    -- origin route/network name
    local originName = definition.origin.edge or NETWORK_ID

    -- check route dependency
    local okRoutes, Routes = pcall(require, "Railroader/RR_Routes")
    if not okRoutes or not Routes or not Routes.register then
        return false, "RR.Routes is unavailable"
    end

    -- check graph dependency
    local okTrackGraph, TrackGraph = pcall(require, "Railroader/RR_TrackGraph")
    if not okTrackGraph or not TrackGraph or not TrackGraph.register then
        return false, "RR.TrackGraph is unavailable"
    end

    -- register or patch graph network
    if originName == RAILROADER_DEFAULT_ROUTE then
        -- patch "main" graph, use existing "main" route
        local merged, mergeReason = mergeMainGraph(TrackGraph, definition)
        if not merged then return false, mergeReason end
        local okRegister, result = pcall(TrackGraph.register,
            RAILROADER_DEFAULT_ROUTE, merged)
        if not okRegister then return false, tostring(result) end
        return true, result
    else
        -- recover nodes and register route
        local routeNodes = definition.edges[originName]
        if not routeNodes then return false, "RR origin edge not found:" .. originName end

        local okRouteRegister, routeResult = pcall(Routes.register, originName, {
            looped = true,
            nodes = routeNodes,
        })
        if not okRouteRegister then return false, tostring(routeResult) end

        -- register graph
        local okRegister, result = pcall(TrackGraph.register, NETWORK_ID, definition)
        if not okRegister then return false, tostring(result) end
        return true, result
    end

end

return RRGraph
