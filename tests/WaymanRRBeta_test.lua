-- Integration test using the actual beta modules, without the Project Zomboid engine.
-- RAILROADER_LUA_ROOT=/path/to/42/media/lua lua tests/WaymanRRBeta_test.lua
local beta = os.getenv("RAILROADER_LUA_ROOT")
if not beta then print("SKIP: set RAILROADER_LUA_ROOT to test the Railroader beta"); return end
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
package.path = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared/?.lua;"
    .. beta .. "/shared/?.lua;" .. package.path
local client = false
function isClient() return client end
function isServer() return false end
require "Railroader/RR_Routes"
require "Railroader/RR_TrackGraph"
require "Railroader/RR_RealRoutes"
require "Railroader/RR_TrackReg"
require "Railroader/RR_API"
require "Wayman/WaymanRRGraph"
local graph, GD = RailroaderWaymanRRGraph, RailroaderWaymanGraphData
local base = RR.TrackGraph.defs.main.base
local world = {
    edges = { branch = {{nodes={
        {x=1986,y=6874,z=0}, {x=1986,y=6854,z=0}, {x=1966,y=6834,z=0},
    }}} },
    switches = {{id="turnout_1",at={x=1986,y=6874},place={x=1984,y=6874,
        sprites={{sprite="wayman_test",dx=0,dy=1}}}, legs={
        throat={edge="main",toward="end",external=true},
        through={edge="main",toward="start",external=true},
        diverge={edge="branch",toward="end"},
    }}},
}
assert(graph.register(world))
assert(RR.TrackGraph.defs.main.base == base, "registration replaced Railroader's base")
local overlay = RR.TrackGraph.overlay("main", "wayman")
assert(overlay.switches[1].place.x == 1984)
assert(overlay.switches[1].place.sprites[1].dy == 1)
local public = {}
for _, edge in ipairs(assert(RR.API.edges("main", {}))) do public[edge.id] = edge end
assert(public.main and public.main.prefix == nil)
assert(public["wayman:branch"].prefix == "wayman" and public["wayman:branch"].nodes == 3)
local nodes = assert(RR.API.edgeNodes("wayman:branch", "main", {}))
assert(nodes[1].x == 1986 and nodes[3].y == 6834)
nodes[1].x = 0
assert(RR.API.edgeNodes("wayman:branch", "main", {})[1].x == 1986)
local unknown, unknownReason = RR.API.edgeNodes("absent", "main")
assert(not unknown and unknownReason == "unknown")
RR.TrackGraph.setState("main", "wayman:turnout_1", "reverse")
assert(graph.register(world))
assert(RR.API.switchState("main", "wayman:turnout_1") == "reverse")
for _, dir in ipairs({1,-1}) do
    local route, distance = RR.TrackGraph.buildThrough("main", {edge="wayman:branch",s=10,dir=dir})
    assert(route and distance and route.length > 20, "could not build route in both directions")
end
assert(RR.API.registerTrack("other", {edges={
    ["other:line"]={{x=1986,y=6874},{x=1966,y=6854}},
    ["other:loop"]={{x=30000,y=30000},{x=30020,y=30000},{x=30020,y=30020},
        {x=30000,y=30020},{x=30000,y=30000}},
}}))
local closedCount = 0
for _, edge in ipairs(assert(RR.API.edges("main", {}))) do
    assert(not edge.id:find("#", 1, true), "public catalog leaked an internal closed-edge half")
    if edge.id == "other:loop" then assert(edge.closed and edge.nodes == 5); closedCount = closedCount + 1 end
end
assert(closedCount == 1)
local closedNodes, closedReason = RR.API.edgeNodes("other:loop", "main")
assert(not closedNodes and closedReason == "closed")
local external = assert(graph.externalEdges())
assert(external.main and external["other:line"] and external["other:loop"] and not external["wayman:branch"])
local endpointCounts={}
local mainNodes=assert(RR.API.edgeNodes("main","main",{}))
for _, node in ipairs(assert(graph.externalEndpoints())) do
    assert(not graph.isOwnId(node.edgeId) and node.edgeId~="other:loop")
    endpointCounts[node.edgeId]=(endpointCounts[node.edgeId] or 0)+1
    assert(node.external and node.nodeId:sub(1,3)=="RR:")
    if node.edgeId=="main" then
        local source=mainNodes[node.nodeIndex]
        assert(node.nodeIndex==1 or node.nodeIndex==#mainNodes)
        assert(node.x==source.x and node.y==source.y and node.z==(source.z or 0))
    end
end
assert(endpointCounts.main==2 and endpointCounts["other:line"]==2)
local invalid = GD.copy(world)
invalid.switches[1].legs.throat.edge = "other:line"
local previous = RR.TrackGraph.overlay("main", "wayman")
local ok, why = graph.register(invalid)
assert(not ok and why:find("legedge",1,true))
assert(RR.TrackGraph.overlay("main", "wayman") == previous)
print("KNOWN RR LIMIT: legs to another add-on are rejected; previous Wayman graph retained")
client = true
assert(not graph.register(world))
client = false
assert(graph.register({edges={},switches={}}))
assert(RR.TrackGraph.overlay("main", "wayman") == nil)
assert(RR.TrackGraph.overlay("main", "other") ~= nil)
assert(graph.register(world))
assert(RR.API.switchState("main", "wayman:turnout_1") == "reverse")
local explicit = assert(graph.export(world))
explicit.switches[1].place.sprite = "single_sprite"
assert(RR.API.registerTrack("wayman", explicit))
local place = RR.TrackGraph.overlay("main", "wayman").switches[1].place
assert(place.sprite == "single_sprite" and place.sprites[1].sprite == "wayman_test")
explicit.switches[1].place.sprites[1].dy = 99
assert(place.sprites[1].dy == 1, "RR must own its normalized placement metadata")
for _, case in ipairs({"grid", "far", "sprites"}) do
    local invalidPlace = assert(graph.export(world))
    if case == "grid" then invalidPlace.switches[1].place.x = 1.5 end
    if case == "far" then invalidPlace.switches[1].place.x = 1995 end
    if case == "sprites" then
        for i=1,9 do invalidPlace.switches[1].place.sprites[i] = {sprite="test"} end
    end
    local accepted, reason = RR.API.registerTrack("wayman", invalidPlace)
    assert(not accepted and reason == "place")
end
local positionOnly = GD.copy(world)
positionOnly.switches[1].place.sprites = nil
local raw = assert(graph.export(positionOnly))
raw.switches[1].place.sprites = nil
local accepted, reason = RR.API.registerTrack("wayman", raw)
assert(not accepted and reason == "place", "RR 3.0f requires explicit placement metadata")
assert(graph.register(positionOnly))
local existingTile = RR.TrackGraph.overlay("main", "wayman").switches[1].place
assert(existingTile.x == 1984 and #existingTile.sprites == 0)
print("PASS: 3.0f public edge catalog, detached geometry and closed-edge identities")
print("PASS: public RR/addon endpoint copies, original indices and Wayman/closed-edge exclusion")
print("PASS: native switch.place preservation, validation and position-only Wayman interaction")
print("PASS: beta registration/replacement/withdrawal, stable switch state and bidirectional routes")
print("PASS: base and other overlays preserved; rejected registrations are atomic")
