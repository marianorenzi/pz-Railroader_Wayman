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
local EPSILON = 1e-6

--- Copies a graph node into RR's plain absolute-coordinate representation.
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
    if not block or #(block.nodes or {}) ~= #expected then return false end
    for index, node in ipairs(block.nodes) do
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
function RRGraph.export(worldData)
    if type(worldData) ~= "table" then return nil, "world data must be a table" end
    local definition = { edges = {}, switches = {} }
    for edgeId, blocks in pairs(worldData.edges or {}) do
        local nodes = GraphData.getOrderedNodes(blocks)
        if #nodes < 2 then return nil, "edge " .. tostring(edgeId) .. " has fewer than two nodes" end
        definition.edges[edgeId] = {}
        for _, node in ipairs(nodes) do
            table.insert(definition.edges[edgeId], copyNode(node))
        end
    end

    for _, switch in ipairs(worldData.switches or {}) do
        local legs = switch.legs or {}
        local throat = copyLeg(legs.throat)
        local through = copyLeg(legs.through)
        local diverge = copyLeg(legs.diverge)
        local configured = throat or through or diverge
        if configured and not (switch.id and switch.at and throat and through and diverge) then
            return nil, "switch " .. tostring(switch.id) .. " is incomplete"
        end
        if configured then
            local place, placeReason = resolveStaticPlace(worldData, switch)
            if not place then return nil, placeReason end
            table.insert(definition.switches, {
                id = switch.id,
                at = copyNode(switch.at),
                throat = throat,
                through = through,
                diverge = diverge,
                place = place,
            })
        end
    end

    local origin = worldData.origin or { edge = NETWORK_ID, toward = "end" }
    if type(origin) ~= "table" or not definition.edges[origin.edge] then
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
    return definition
end

--- Registers the primary route and current graph through RR's replaceable integration boundary.
function RRGraph.register(worldData)
    local definition, reason = RRGraph.export(worldData)
    if not definition then return false, reason end
    local waymanNodes = definition.edges[NETWORK_ID]
    if not waymanNodes then return false, "RR route requires edge " .. NETWORK_ID end

    local okRoutes, Routes = pcall(require, "Railroader/RR_Routes")
    if not okRoutes or not Routes or not Routes.register then
        return false, "RR.Routes is unavailable"
    end
    local okTrackGraph, TrackGraph = pcall(require, "Railroader/RR_TrackGraph")
    if not okTrackGraph or not TrackGraph or not TrackGraph.register then
        return false, "RR.TrackGraph is unavailable"
    end

    local okRouteRegister, routeResult = pcall(Routes.register, NETWORK_ID, {
        looped = false,
        nodes = waymanNodes,
    })
    if not okRouteRegister then return false, tostring(routeResult) end
    local okRegister, result = pcall(TrackGraph.register, NETWORK_ID, definition)
    if not okRegister then return false, tostring(result) end
    return true, result
end

return RRGraph
