-- Standalone tests for the public registration boundary and turnout edge catalog.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
package.path = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared/?.lua;" .. package.path
require "Wayman/WaymanRRGraph"
local GD, graph = RailroaderWaymanGraphData, RailroaderWaymanRRGraph
local client, calls, reject, active = false, 0, false, nil
function isClient() return client end
RR = {
    API = {
        VERSION = 1,
        edges = function(net, out)
            assert(net == "main" and type(out) == "table")
            out[1], out[2] = {id="main"}, {id="yard"}
            out[3], out[4] = {id="other:line",prefix="other"}, {id="wayman:old",prefix="wayman"}
            out[5] = {id="other:loop",prefix="other",closed=true}
            return out
        end,
        registerTrack = function(prefix, definition)
            calls = calls + 1
            assert(prefix == "wayman")
            if reject then return nil, "legedge", "other:line" end
            active = definition
            return true
        end,
        unregisterTrack = function(prefix)
            calls = calls + 1
            assert(prefix == "wayman")
            if not active then return nil, "unknown" end
            active = nil
            return true
        end,
    },
}
local world = {
    edges = {
        main = {{origin={x=10,y=20}, nodes={
            {x=2,y=2,name="station",open=true,tags={["wayman:station"]="A"}},
            {x=6,y=6},
        }}},
        yard = {{invertNodes=true, nodes={{x=50,y=50},{x=55,y=55}}}},
    },
    switches = {{
        id="turnout_1", origin={x=10,y=20}, at={x=2,y=2}, place={x=0,y=0,
            sprites={{sprite="wayman_tile",dx=0,dy=1}}},
        legs={
            throat={edge="main",toward="start",external=true},
            through={edge="main",toward="end",external=true},
            diverge={edge="main",toward="end"},
        },
    }},
}
-- Normal registration must not pay for diagnostic JSON; debug still exposes
-- both complete snapshots. Explicit UI export is exercised by the editor suite.
local encode, output = GD.worldDataToJSON, print
local encoded, messages = 0, {}
GD.worldDataToJSON = function(...)
    encoded = encoded + 1
    return encode(...)
end
print = function(message) messages[#messages + 1] = message end
getDebug = nil
assert(graph.export(world) and encoded == 0 and #messages == 0)
function getDebug() return false end
assert(graph.export(world) and encoded == 0 and #messages == 0)
getDebug = function() return true end
assert(graph.export(world) and encoded == 2 and #messages == 2)
assert(messages[1]:find("GRAPH_BEFORE_EXPORT",1,true) and messages[2]:find("GRAPH_AFTER_EXPORT",1,true))
getDebug = function() return false end
GD.worldDataToJSON, print = encode, output

local def, reason = graph.export(world)
assert(def, reason)
assert(def.origin == nil and def.edges["wayman:main"][1].x == 12)
assert(def.edges["wayman:yard"][1].x == 55)
assert(def.switches[1].id == "wayman:turnout_1")
assert(def.switches[1].throat.edge == "main")
assert(def.switches[1].diverge.edge == "wayman:main")
assert(def.switches[1].place.x == 10 and def.switches[1].place.sprites[1].sprite == "wayman_tile")
local positionOnly = GD.copy(world)
positionOnly.switches[1].place.sprites = nil
local placed = assert(graph.export(positionOnly)).switches[1].place
assert(placed.x == 10 and type(placed.sprites) == "table" and #placed.sprites == 0)
assert(positionOnly.switches[1].place.sprites == nil, "export changed persisted placement metadata")
positionOnly.switches[1].place.sprite = "wayman_custom_tile"
assert(assert(graph.export(positionOnly)).switches[1].place.sprites == nil)
assert(def.edges["wayman:main"][1].name == "station" and def.edges["wayman:main"][1].open)
def.edges["wayman:main"][1].tags["wayman:station"] = "changed"
assert(world.edges.main[1].nodes[1].tags["wayman:station"] == "A")
local options = graph.edgeOptions(world.edges)
local byId = {}
for _, option in ipairs(options) do byId[option.id] = option end
assert(byId.main.label == "rr:main" and byId["wayman:main"].label == "wayman:main")
assert(byId["other:line"].label == "other:line" and not byId["wayman:old"])
assert(byId["other:loop"] and not byId["other:loop#a"])
assert(byId.main.external and not byId["wayman:main"].external)
local publicNodes={
    main={{x=1,y=1,name="station",open=false},{x=2,y=2},{x=3,y=3,name=""}},
    yard={{x=4,y=4,z=1}},
    ["other:line"]={{x=5,y=5},{x=6,y=6},{x=7,y=7,name="addon"}},
}
RR.API.edgeNodes=function(id,net,out)
    assert(net=="main" and id~="wayman:old" and id~="other:loop")
    return publicNodes[id]
end
local endpoints=assert(graph.externalEndpoints())
assert(#endpoints==5)
assert(endpoints[1].nodeId=="RR:station" and endpoints[1].nodeIndex==1)
assert(endpoints[2].nodeId=="RR:3" and endpoints[2].nodeIndex==3)
assert(endpoints[3].edgeId=="other:line" and endpoints[4].nodeId=="RR:addon")
assert(endpoints[5].edgeId=="yard" and endpoints[5].z==1)
publicNodes.main[1].x=999
assert(endpoints[1].x==1,"cached endpoints retained RR's reused row tables")
RR.API.edgeNodes=function() return nil,"unknown" end
assert(#assert(graph.externalEndpoints())==0)
RR.API.edgeNodes=nil
assert(#assert(graph.externalEndpoints())==0)
assert(graph.register(world))
local previous = active
reject = true
local ok, why, detail = graph.register(world)
assert(not ok and why == "legedge: other:line" and detail == "other:line" and active == previous)
reject = false
client = true
local before = calls
ok, why = graph.register(world)
assert(not ok and why == "client" and calls == before)
client = false

for _, case in ipairs({"grid","angle","repeat"}) do
    local invalid = GD.copy(world)
    local nodes = invalid.edges.main[1].nodes
    if case == "grid" then nodes[2].x = 6.5 end
    if case == "angle" then nodes[2].x = 7 end
    if case == "repeat" then nodes[2] = GD.copy(nodes[1]) end
    local result, errorMessage = graph.export(invalid)
    assert(not result and errorMessage:find(case, 1, true))
end
local incomplete = GD.copy(world)
incomplete.switches[1].legs.diverge = {}
assert(#assert(graph.export(incomplete)).switches == 0)
local missing = GD.copy(world)
missing.switches[1].legs.throat.edge = "absent"
assert(not graph.export(missing))
assert(graph.register({edges={},switches={}}) and active == nil)
assert(graph.register({edges={},switches={}}))
RR.API.registerTrack = nil
assert(not graph.register(world))
local internalReads = 0
RR.TrackGraph = {netEdges=function() internalReads=internalReads+1; error("internal catalog must never be read") end}
RR.API.edges = function() return nil,"unknown" end
local ownOnly, catalogReason = graph.edgeOptions({local_line={}})
assert(#ownOnly == 1 and ownOnly[1].label == "wayman:local_line" and catalogReason)
assert(internalReads == 0)
RR.API.edges = nil
assert(select(2,graph.externalEdges()))

print("PASS: public API, namespaced identities, absolute metadata and complete switches")
print("PASS: RR/addon/draft catalog, display-only rr: prefix and no duplicated Wayman overlay")
print("PASS: geometry validation, client authority, refusal details and empty withdrawal")
