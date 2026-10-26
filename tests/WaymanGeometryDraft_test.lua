-- Coordinated geometry, using the actual public RR beta when available.
next = nil -- Project Zomboid/Kahlua does not expose Lua's global next.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path = luaRoot .. "/shared/?.lua;" .. package.path
local beta = os.getenv("RAILROADER_LUA_ROOT")
local server, client, debugMode = false, false, true
function isClient() return client end
function isServer() return server end
function getDebug() return debugMode end
if beta then
    package.path = beta .. "/shared/?.lua;" .. package.path
    require "Railroader/RR_Routes"
    require "Railroader/RR_TrackGraph"
    require "Railroader/RR_RealRoutes"
    require "Railroader/RR_TrackReg"
    require "Railroader/RR_API"
else
    RR = {API={edges=function() return {} end,registerTrack=function() return true end,
        unregisterTrack=function() return true end}}
end
require "Wayman/WaymanEntityGeometry"
RailroaderWaymanEntityGeometry.DebugTurn = {N={kind="turn",nodes={{x=0,y=0,z=0}}}}
local world, commands, broadcasts, saves = {}, {}, 0, {}
ModData = {getOrCreate=function() return world end,transmit=function() broadcasts=broadcasts+1 end}
local onCommand
Events = {
    OnTick={Add=function() end},OnRailroaderRegisterTrack={Add=function() end},
    OnObjectAboutToBeRemoved={Add=function() end},OnClientCommand={Add=function(fn) onCommand=fn end},
}
function sendServerCommand(_,module,command,args)
    assert(module == "RailroaderWayman" and command == "graphResult")
    if args.ok then
        assert(#saves > 0 and saves[#saves].server
            and saves[#saves].world.revision == args.worldData.revision,
            "publication acknowledged before requesting the authoritative server save")
    end
    commands[#commands+1] = args
end
local squares = {}
function getCell() return {getGridSquare=function(_,x,y) return squares[x..","..y] end} end
local function object(owner,x,y,nodes)
    local data = {railroaderWayman={id=owner,nodes=nodes}}
    local face = {getFaceName=function() return "N" end,getMasterX=function() return 0 end,
        getMasterY=function() return 0 end,getMasterZ=function() return 0 end}
    local master, square
    master = {getMasterObject=function() end,getSquare=function() return square end,
        getEntityScript=function() return {getName=function() return "DebugTurn" end} end,
        getSpriteConfig=function() return {getFaceInfo=function() return face end} end,
        getX=function() return x end,getY=function() return y end,getZ=function() return 0 end,
        getModData=function() return data end,transmitModData=function() end}
    square = {getObjects=function() return {size=function() return 1 end,get=function() return master end} end}
    squares[x..","..y] = square
    return master, data
end
local n7 = {{x=0,y=8,z=0},{x=0,y=0,z=0}}
local n6 = {{x=0,y=0,z=0},{x=-9,y=0,z=0}}
local o7,d7 = object("turn_7",30047,36842,n7)
local o6,d6 = object("turn_6",30039,36834,n6)
dofile(luaRoot .. "/server/Wayman/WaymanEntityRuntime.lua")
local GD, runtime = RailroaderWaymanGraphData, RailroaderWaymanEntityRuntime
function save(doCharacters)
    assert(doCharacters and not client)
    saves[#saves + 1] = {world=GD.copy(world), first=GD.copy(d7.railroaderWayman), second=GD.copy(d6.railroaderWayman),server=server}
end
world = GD.ensure({revision=10,edges={line={
    {blockId="turn_7:nodes",owner="turn_7",id="nodes",origin={x=30047,y=36842,z=0},nodes=n7},
    {blockId="turn_6:nodes",owner="turn_6",id="nodes",origin={x=30039,y=36834,z=0},nodes=n6},
}}})
assert(RailroaderWaymanRRGraph.register(world))
local edits = {turn_7={x=30047,y=36842,z=0,entityName="DebugTurn",facing="N",
    modData={id="turn_7",nodes={{x=0,y=8,z=0},{x=0,y=-2,z=0}}}}}
local ok, why = runtime.ApplyGraphDraft(GD.copy(world),10,edits)
assert(not ok and why:match("angle") and world.revision == 10 and d7.railroaderWayman.nodes[2].y == 0)
assert(#saves == 0, "invalid intermediate geometry requested a save")
edits.turn_6 = {x=30039,y=36834,z=0,entityName="DebugTurn",facing="N",
    modData={id="turn_6",nodes={{x=2,y=0,z=0},{x=-9,y=0,z=0}}}}
assert(runtime.ApplyGraphDraft(GD.copy(world),10,edits))
assert(world.revision == 11 and d7.railroaderWayman.nodes[2].y == -2 and d6.railroaderWayman.nodes[1].x == 2)
assert(world.edges.line[1].nodes[2].y == -2 and world.edges.line[2].nodes[1].x == 2)
assert(#saves == 1 and saves[1].world.revision == 11
    and saves[1].world.edges.line[1].nodes[2].y == -2
    and saves[1].first.nodes[2].y == -2 and saves[1].second.nodes[1].x == 2,
    "world save ran before the complete graph and physical geometry were committed")
local snapshot = assert(GD.worldDataToJSON(world))
assert(not runtime.ApplyGraphDraft(GD.copy(world),10,edits))
assert(snapshot == GD.worldDataToJSON(world), "stale publication mutated canonical state")
assert(#saves == 1, "stale publication requested another save")
server, debugMode = true, false
local normal = {getAccessLevel=function() return "None" end}
assert(not runtime.ApplyGraphDraft(GD.copy(world),11,edits,normal))
local admin = {getAccessLevel=function() return "Admin" end}
edits.turn_6.modData.id = "turn_7"
assert(not runtime.ApplyGraphDraft(GD.copy(world),11,edits,admin))
edits.turn_6.modData.id = "turn_6"
local square6 = squares["30039,36834"]; squares["30039,36834"] = nil
assert(not runtime.ApplyGraphDraft(GD.copy(world),11,edits,admin))
squares["30039,36834"] = square6
onCommand("RailroaderWayman","applyGraph",admin,{draft=GD.copy(world),revision=11,geometryEdits=edits,requestId="alice:123"})
assert(commands[#commands].ok and commands[#commands].requestId == "alice:123" and broadcasts == 1)
assert(#saves == 2 and saves[2].server and saves[2].world.revision == 12
    and saves[2].first.nodes[2].y == -2 and saves[2].second.nodes[1].x == 2,
    "MP publication did not request a save after committing the full transaction")
onCommand("RailroaderWayman","applyGraph",admin,{draft=GD.copy(world),revision=11,requestId="alice:124"})
assert(not commands[#commands].ok and commands[#commands].requestId == "alice:124"
    and commands[#commands].worldData.revision == 12)
assert(#saves == 2, "rejected MP publication requested another save")
assert(runtime.ApplyGraphDraft(GD.copy(world),12,{},normal),
    "topology publication with an empty geometry table must work without global next")
assert(world.revision == 13)
assert(#saves == 3 and saves[3].server and saves[3].world.revision == 13,
    "accepted topology-only server publication did not request a save")
print("PASS: coordinated geometry publishes atomically; invalid intermediate and stale edits leave objects untouched")
print("PASS: SP/server saves follow the complete commit; the MP acknowledgement follows the save request")
print("PASS: authoritative owner/physical identity, unloaded-entity refusal, debug/admin checks and correlated MP results")
if beta then print("PASS: coordinated geometry accepted by unmodified local Railroader beta") end
