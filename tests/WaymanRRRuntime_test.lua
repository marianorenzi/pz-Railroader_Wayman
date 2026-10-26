-- Exercises authoritative commits and restore/geometry/removal lifecycle with a public API double.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path = luaRoot .. "/shared/?.lua;" .. package.path
local world, broadcasts, client, server, refuse, active = {}, 0, false, true, false, nil
local saves, savedByServer = {}, {}
function save(doCharacters)
    assert(doCharacters and not client, "only the authority may request a world save")
    saves[#saves + 1] = RailroaderWaymanGraphData.copy(world)
    savedByServer[#saves] = server
end
ModData = {
    getOrCreate = function() return world end,
    transmit = function() broadcasts = broadcasts + 1 end,
}
function isClient() return client end
function isServer() return server end
local restore
Events = {
    OnTick={Add=function() end}, OnClientCommand={Add=function() end},
    OnObjectAboutToBeRemoved={Add=function() end},
    OnRailroaderRegisterTrack={Add=function(fn) restore=fn end},
}
local registered = 0
RR = {
    API={
        edges=function() return {{id="main"},{id="line"},{id="other:branch",prefix="other"}} end,
        registerTrack=function(prefix, def)
            assert(prefix == "wayman")
            registered = registered + 1
            if refuse then return nil,"overlap","wayman:line" end
            active = def
            return true
        end,
        unregisterTrack=function()
            if refuse then return nil,"failed" end
            active = nil
            return true
        end,
    },
}
dofile(luaRoot .. "/server/Wayman/WaymanEntityRuntime.lua")
local GD, runtime = RailroaderWaymanGraphData, RailroaderWaymanEntityRuntime
local block = {blockId="turn_1:nodes",owner="turn_1",id="nodes",origin={x=100,y=100},
    nodes={{x=0,y=0},{x=10,y=10}}}
world = GD.ensure({availableNodes={block},edges={},switches={}})
local draft = GD.copy(world)
draft.availableNodes = {}
draft.edges.line = {GD.copy(block)}
refuse = true
local ok, why = runtime.ApplyGraphDraft(draft, 0)
assert(not ok and why == "overlap: wayman:line")
assert(world.revision == 0 and world.edges.line == nil and broadcasts == 0 and active == nil)
assert(#saves == 0, "RR rejection requested a world save")
refuse = false
assert(runtime.ApplyGraphDraft(draft, 0))
assert(world.revision == 1 and broadcasts == 1 and active.edges["wayman:line"])
assert(#saves == 1 and savedByServer[1] and saves[1].revision == 1 and saves[1].edges.line,
    "accepted server graph was not committed before requesting a save")
assert(not runtime.ApplyGraphDraft(draft, 0))
client = true
assert(not runtime.ApplyGraphDraft(draft, 1))
local before = registered
restore()
assert(registered == before)
client = false
restore()
assert(registered == before + 1, "load must restore any edge name, without requiring wayman")
assert(#saves == 1, "stale/client publications or restoration requested another save")

-- Exercise the same entry points in SP as on the dedicated-server path.
server = false
restore()
assert(#saves == 1, "restoration requested another world save")
refuse = true
assert(not runtime.ApplyGraphDraft(GD.copy(world), world.revision))
assert(#saves == 1, "rejected singleplayer publication requested a save")
refuse = false
assert(runtime.ApplyGraphDraft(GD.copy(world), world.revision))
assert(#saves == 2 and not savedByServer[2] and saves[2].revision == world.revision and saves[2].edges.line,
    "accepted singleplayer graph was not committed before the world save")
local modData = {railroaderWayman={id="turn_1"}}
local entity = {getModData=function() return modData end,transmitModData=function() end}
RailroaderWaymanEntityDescriptor.describe = function()
    return {master=entity,origin={x=100,y=100},entityName="test",facing="N",
        defaults={kind="turn",nodes={{x=0,y=0},{x=10,y=10}}}}
end
RailroaderWaymanEntityDescriptor.getMaster = function(object) return object end
refuse = true
local previous, revision = active, world.revision
assert(not runtime.SaveGeometry(entity, {nodes={{x=0,y=0},{x=20,y=20}}}, "N"))
assert(world.revision == revision and modData.railroaderWayman.nodes == nil and active == previous)
refuse = false
assert(runtime.SaveGeometry(entity, {nodes={{x=0,y=0},{x=20,y=20}}}, "N"))
assert(world.revision == revision + 1 and active.edges["wayman:line"][2].x == 120)
local changed = modData.railroaderWayman.nodes
assert(changed[2].x == 20)

refuse = true
world.switches = {{id="turnout_2",owner="turnout_2",at={x=100,y=100},
    legs={throat={edge="line",toward="start",external=true},through={},diverge={}}}}
runtime.OnRemove(entity)
assert(world.edges.line == nil and active and world.rrSync.pending)
refuse = false
assert(runtime.ApplyGraphDraft(GD.copy(world),world.revision))
assert(world.edges.line == nil and active == nil)
assert(world.rrSync == nil)
assert(#saves == 3 and saves[3].edges.line == nil and saves[3].rrSync == nil,
    "accepted withdrawal was not persisted after clearing pending RR synchronization")
assert(world.switches[1].legs.throat.edge == "line", "removal confused local and external line")
refuse = true
local publications = registered
assert(runtime.SaveGeometry(entity, {nodes={{x=0,y=0},{x=5,y=5}}}, "N"))
assert(registered == publications and active == nil, "unassigned construction republished the graph")
refuse = false
world.availableNodes = {}
world.edges.line = {
    {blockId="turn_1:nodes",owner="turn_1",id="nodes",nodes={{x=100,y=100}}},
    {blockId="turn_2:nodes",owner="turn_2",id="nodes",nodes={{x=110,y=110}}},
}
assert(RailroaderWaymanRRGraph.register(world))
local lastGraph, lastRevision = active, world.revision
runtime.OnRemove(entity)
assert(active == lastGraph and world.revision == lastRevision + 1 and #world.edges.line == 1)
assert(world.edges.line[1].owner == "turn_2" and world.rrSync.pending)
print("PASS: physical removal always cleans WorldData and marks an RR refusal for repair")
print("PASS: rejected editor/geometry publications preserve confirmed state")
print("PASS: authoritative commits, arbitrary edge restore, SP/server paths and empty withdrawal")
print("PASS: accepted SP/server publications request a save; rejections, restores and clients do not")
