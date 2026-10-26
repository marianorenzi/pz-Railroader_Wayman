-- Wayman's boundary to Railroader: publish only our contribution through RR.API.
-- Both registration and edge discovery use RR.API.
require "Wayman/WaymanGraphData"

RailroaderWaymanRRGraph = RailroaderWaymanRRGraph or {}
local RRGraph = RailroaderWaymanRRGraph
local GraphData = RailroaderWaymanGraphData
RRGraph.PREFIX = "wayman"
local OWN_PREFIX = RRGraph.PREFIX .. ":"

--- A node in absolute world coordinates, as accepted by RR.API.registerTrack.
---@class RailroaderNode
---@field x integer
---@field y integer
---@field z integer
---@field name string?
---@field open boolean?
---@field tags table<string,string|number|boolean>?

--- The switch's interaction tile and optional drawing metadata.
---@class RailroaderSwitchPlace
---@field x integer
---@field y integer
---@field z integer
---@field sprite string?
---@field sprites {sprite:string, dx:integer?, dy:integer?}[]? An empty list requests no drawing.

---@class RailroaderSwitchLeg
---@field edge string Exported edge ID; Wayman IDs include the wayman: prefix.
---@field toward 'start'|'end'

---@class RailroaderSwitch
---@field id string Exported switch ID, including the wayman: prefix.
---@field at RailroaderNode
---@field place RailroaderSwitchPlace?
---@field throat RailroaderSwitchLeg
---@field through RailroaderSwitchLeg
---@field diverge RailroaderSwitchLeg

--- Wayman's contribution to RR's main network; it has no independent origin.
---@class RailroaderGraph
---@field edges table<string,RailroaderNode[]> Keys are exported edge IDs.
---@field switches RailroaderSwitch[]

---@class WaymanRREdgeOption
---@field id string Real exported edge ID.
---@field label string Display label, including rr: for original RR edges.
---@field edge string Local draft ID for Wayman, real exported ID for external edges.
---@field external boolean? True for RR or another addon's edges; absent for Wayman.

--- Adds Wayman's prefix to a local draft ID.
---@param id string
---@return string
function RRGraph.ownId(id)
    return OWN_PREFIX .. id
end

--- Tests whether an exported ID belongs to Wayman.
---@param id any
---@return boolean
function RRGraph.isOwnId(id)
    return type(id) == "string" and id:sub(1, #OWN_PREFIX) == OWN_PREFIX
end

--- Copies public catalog IDs immediately; RR may reuse its returned row tables.
---@return table<string,boolean>? edges Set of external IDs, excluding Wayman's contribution.
---@return string? reason
function RRGraph.externalEdges()
    local api = RR and RR.API
    if not api or type(api.edges) ~= "function" then
        return nil, "Railroader edge catalog is unavailable"
    end
    local ok, edges = pcall(api.edges, "main", {})
    if not ok or type(edges) ~= "table" then
        return nil, "Railroader edge catalog is unavailable"
    end
    local result = {}
    for _, edge in ipairs(edges) do
        if type(edge) == "table" and type(edge.id) == "string"
            and edge.prefix ~= RRGraph.PREFIX and not RRGraph.isOwnId(edge.id) then
            result[edge.id] = true
        end
    end
    return result
end

--- Each option's ID is the real exported ID; rr: is only a display label.
---@param edges table<string,WaymanNodeBlock[]>? Current draft's local edges.
---@return WaymanRREdgeOption[] options
---@return string? reason External catalog error; local options remain available.
function RRGraph.edgeOptions(edges)
    local external, reason = RRGraph.externalEdges()
    local options = {}
    for id in pairs(external or {}) do
        table.insert(options, {
            id = id, label = id:find(":", 1, true) and id or "rr:" .. id,
            edge = id, external = true,
        })
    end
    for id in pairs(edges or {}) do
        table.insert(options, { id = RRGraph.ownId(id), label = RRGraph.ownId(id), edge = id })
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    return options, reason
end

local function localId(id)
    return type(id) == "string" and id:match("^[%w_.%-]+$") ~= nil
end

local function grid(node)
    local function integer(value)
        return type(value) == "number" and value == math.floor(value)
            and value > -1e7 and value < 1e7
    end
    return node and integer(node.x) and integer(node.y) and integer(node.z or 0)
end

local function logGraphJSON(label, graph)
    -- Guard serialization too: a quiet print alone would still encode the graph.
    -- The editor's explicit Export action has its own unrestricted JSON output.
    if not (getDebug and getDebug()) then return end
    local json, reason = GraphData.worldDataToJSON(graph)
    print("[RailroaderWayman] " .. label .. (json and (" " .. json) or ("_ERROR " .. tostring(reason))))
end

--- Exports ordered absolute nodes and complete switches; incomplete switches stay editable.
---@param graphData WaymanGraphData
---@return RailroaderGraph? definition
---@return string? reason
function RRGraph.export(graphData)
    if type(graphData) ~= "table" then return nil, "world data must be a table" end
    logGraphJSON("GRAPH_BEFORE_EXPORT", graphData)
    local definition = { edges = {}, switches = {} }
    for edgeId, blocks in pairs(graphData.edges or {}) do
        if not localId(edgeId) then return nil, "invalid Wayman edge id " .. tostring(edgeId) end
        local nodes = GraphData.getOrderedNodes(blocks)
        if #nodes < 2 then return nil, "edge " .. edgeId .. " has fewer than two nodes" end
        for index, node in ipairs(nodes) do
            if not grid(node) then return nil, "grid: " .. edgeId .. " node " .. index end
            if index > 1 then
                local dx, dy = node.x - nodes[index - 1].x, node.y - nodes[index - 1].y
                if dx == 0 and dy == 0 then return nil, "repeat: " .. edgeId .. " node " .. index end
                if dx ~= 0 and dy ~= 0 and math.abs(dx) ~= math.abs(dy) then
                    return nil, "angle: " .. edgeId .. " node " .. index
                end
            end
        end
        definition.edges[RRGraph.ownId(edgeId)] = nodes
    end

    local external, catalogReason
    for _, switch in ipairs(graphData.switches or {}) do
        local legs = switch.legs or {}
        local complete = true
        for _, name in ipairs({ "throat", "through", "diverge" }) do
            if not legs[name] or not legs[name].edge or not legs[name].toward then complete = false end
        end
        if complete then
            if not localId(switch.id) then return nil, "invalid Wayman switch id " .. tostring(switch.id) end
            local at = GraphData.getAbsoluteNode(switch.origin, switch.at)
            if not grid(at) then return nil, "grid: switch " .. switch.id end
            local place = GraphData.getAbsoluteNode(switch.origin, switch.place)
            if not grid(place) then return nil, "missing or invalid switch place: " .. switch.id end
            place.sprite = switch.place.sprite
            -- Wayman already builds these tiles. An empty list requests no extra
            -- drawing while keeping place valid for RR's exact-tile interaction.
            place.sprites = GraphData.copy(switch.place.sprites)
            if place.sprite == nil and place.sprites == nil then place.sprites = {} end
            local exported = { id = RRGraph.ownId(switch.id), at = at, place = place }
            local ownLeg = false
            for _, name in ipairs({ "throat", "through", "diverge" }) do
                local leg = legs[name]
                if leg.toward ~= "start" and leg.toward ~= "end" then
                    return nil, "invalid toward: " .. switch.id .. " " .. name
                end
                local edge
                if leg.external ~= true and graphData.edges[leg.edge] then
                    edge = RRGraph.ownId(leg.edge)
                    ownLeg = true
                else
                    if not external then external, catalogReason = RRGraph.externalEdges() end
                    if not external then return nil, catalogReason end
                    if not external[leg.edge] then return nil, "unknown external edge: " .. tostring(leg.edge) end
                    edge = leg.edge
                end
                exported[name] = { edge = edge, toward = leg.toward }
            end
            if not ownLeg then return nil, "noleg: switch " .. switch.id end
            table.insert(definition.switches, exported)
        end
    end
    logGraphJSON("GRAPH_AFTER_EXPORT", definition)
    return definition
end

--- RR validates before replacing our prefix; a rejection leaves its last graph intact.
---@param graphData WaymanGraphData
---@return boolean accepted
---@return string? reason Formatted error, including RR's detail when available.
---@return string? detail Original RR detail, when supplied on rejection.
function RRGraph.register(graphData)
    if isClient and isClient() then return false, "client" end
    local api = RR and RR.API
    if not api or type(api.registerTrack) ~= "function" or type(api.unregisterTrack) ~= "function" then
        return false, "Railroader track registration API is unavailable"
    end
    local definition, reason = RRGraph.export(graphData)
    if not definition then return false, reason end
    local empty = true
    for _ in pairs(definition.edges) do empty = false; break end
    local ok, accepted, why, detail
    if empty then
        ok, accepted, why = pcall(api.unregisterTrack, RRGraph.PREFIX)
    else
        ok, accepted, why, detail = pcall(api.registerTrack, RRGraph.PREFIX, definition)
    end
    if not ok then return false, tostring(accepted) end
    if accepted or (empty and why == "unknown") then return true end
    return false, tostring(why or "failed") .. (detail and (": " .. tostring(detail)) or ""), detail
end

return RRGraph
