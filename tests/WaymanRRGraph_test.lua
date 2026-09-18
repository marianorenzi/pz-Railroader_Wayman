-- Standalone IDE test for Wayman-to-Railroader graph conversion and registration.

local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local shared = root
    .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared/?.lua"
package.path = shared .. ";" .. package.path

dofile(root
    .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared/Wayman/WaymanGraphData.lua")
dofile(root
    .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared/Wayman/WaymanRRGraph.lua")

local RRGraph = RailroaderWaymanRRGraph

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local world = {
    availableNodes = {
        { blockId = "turnout_1:through", owner = "turnout_1", id = "through",
            nodes = { { x = 12, y = 22 } } },
    },
    edges = {
        wayman = {
            { blockId = "turn_1:nodes", invertNodes = true, nodes = {
                { x = 1, y = 1 }, { x = 2, y = 2 },
            } },
            { blockId = "turnout_1:at", owner = "turnout_1", id = "at",
                nodes = { { x = 12, y = 22 } } },
        },
        diverge = {
            { blockId = "turnout_1:diverge", owner = "turnout_1", id = "diverge",
                nodes = { { x = 16, y = 26 } } },
            { blockId = "turn_2:nodes", nodes = { { x = 20, y = 30 } } },
        },
    },
    switches = {
        {
            id = "turnout_1",
            owner = "turnout_1",
            at = { x = 12, y = 22 },
            legs = {
                throat = { edge = "wayman", toward = "start" },
                through = { edge = "wayman", toward = "end" },
                diverge = { edge = "diverge", toward = "end" },
            },
        },
    },
}

local definition, reason = RRGraph.export(world)
assert(definition, reason)
assertEqual(definition.origin.edge, "wayman", "default origin edge")
assertEqual(definition.origin.toward, "end", "default origin direction")
assertEqual(definition.edges.wayman[1].x, 2, "inverted first node")
assertEqual(definition.edges.wayman[2].x, 1, "inverted second node")
assertEqual(definition.edges.wayman[3].x, 12, "following block node")
assertEqual(definition.switches[1].throat.edge, "wayman", "RR throat leg")
assertEqual(definition.switches[1].place.x, 10, "static place x")
assertEqual(definition.switches[1].place.y, 20, "static place y")

local registeredRouteId, registeredRoute
package.loaded["Railroader/RR_Routes"] = nil
package.preload["Railroader/RR_Routes"] = function()
    return {
        register = function(id, value)
            registeredRouteId, registeredRoute = id, value
            return value
        end,
    }
end

local registeredId, registeredDefinition
package.loaded["Railroader/RR_TrackGraph"] = nil
package.preload["Railroader/RR_TrackGraph"] = function()
    return {
        register = function(id, value)
            registeredId, registeredDefinition = id, value
            return value
        end,
    }
end
local registered, registerReason = RRGraph.register(world)
assert(registered, registerReason)
assertEqual(registeredRouteId, "wayman", "RR route id")
assertEqual(registeredRoute.looped, false, "RR route is not looped")
assertEqual(registeredRoute.nodes, registeredDefinition.edges.wayman,
    "RR route uses the exported wayman edge")
assertEqual(registeredId, "wayman", "RR network id")
assertEqual(registeredDefinition.edges.wayman[1].x, 2, "registered definition")

print("PASS: exported ordered/inverted Wayman nodes in RR graph format")
print("PASS: registered the wayman route and graph through the replaceable integration boundary")
