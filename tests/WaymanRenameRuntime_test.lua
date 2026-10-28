-- The authoritative rename command, save/broadcast ordering and real RR boundary.
next=nil
local root=debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/") or "."
local luaRoot=root.."/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path=luaRoot.."/shared/?.lua;"..package.path
local client,server,refuse=false,true,false
function isClient() return client end
function isServer() return server end
local beta=os.getenv("RAILROADER_LUA_ROOT")
if beta then
    package.path=beta.."/shared/?.lua;"..package.path
    require "Railroader/RR_Routes"; require "Railroader/RR_TrackGraph"
    require "Railroader/RR_RealRoutes"; require "Railroader/RR_TrackReg"; require "Railroader/RR_API"
else
    RR={API={edges=function() return {} end,registerTrack=function() return true end,
        unregisterTrack=function() return true end}}
end
local GD=require "Wayman/WaymanGraphData"
require "Wayman/WaymanRRGraph"
local RRGraph=RailroaderWaymanRRGraph
local register,registered=RRGraph.register,0
RRGraph.register=function(data)
    registered=registered+1
    if refuse then return false,"RR refused rename" end
    return register(data)
end
local world=GD.ensure({revision=10,edges={old={
    {blockId="a:nodes",owner="a",id="nodes",origin={x=30000,y=30000,z=0},
        nodes={{x=0,y=0},{x=20,y=0}}},
    {blockId="b:nodes",owner="b",id="nodes",origin={x=30000,y=30000,z=0},
        invertNodes=true,nodes={{x=60,y=0},{x=40,y=0}}},
}},switches={{id="s",legs={throat={edge="old",toward="end"},
    through={edge="old",external=true,toward="start"},diverge={}}}}})
local onCommand,saves,messages,broadcasts=nil,{},{},0
ModData={getOrCreate=function() return world end,transmit=function() broadcasts=broadcasts+1 end}
Events={OnTick={Add=function() end},OnObjectAboutToBeRemoved={Add=function() end},
    OnClientCommand={Add=function(fn) onCommand=fn end}}
function save(flag) assert(flag); saves[#saves+1]=GD.copy(world) end
function sendServerCommand(...)
    local values={...}
    local command,args
    if #values==3 then command,args=values[2],values[3]
    else command,args=values[3],values[4] end
    if command=="rename" then
        assert(#saves>0 and saves[#saves].revision==args.worldData.revision,
            "rename notification preceded the authoritative save")
    end
    messages[#messages+1]={command=command,args=args}
end
dofile(luaRoot.."/server/Wayman/WaymanEntityRuntime.lua")
local runtime=RailroaderWaymanEntityRuntime
assert(runtime.GraphSync().renameFloor==10)
local before=assert(GD.worldDataToJSON(world))
for _, id in ipairs({"", "bad name", "other:edge"}) do
    assert(not runtime.RenameEdge("old",id,10,"invalid:"..id))
end
assert(not runtime.RenameEdge("missing","new",10,"missing"))
assert(not runtime.RenameEdge("old","new",9,"stale"))
client=true; assert(not runtime.RenameEdge("old","new",10,"client")); client=false
assert(before==GD.worldDataToJSON(world) and #saves==0 and registered==0)
local same,operation=runtime.RenameEdge("old","old",10,"same")
assert(same and not operation.changed and world.revision==10 and #saves==0 and registered==0)
refuse=true
assert(not runtime.RenameEdge("old","new",10,"refused"))
assert(before==GD.worldDataToJSON(world) and #saves==0 and broadcasts==0)
refuse=false
local blocks,first=world.edges.old,world.edges.old[1]
local player={getUsername=function() return "alice" end}
onCommand("RailroaderWayman","rename",player,{oldId="old",newId="new",revision=10,requestId="rename:1"})
assert(world.revision==11 and world.edges.new==blocks and blocks[1]==first and not world.edges.old)
assert(blocks[2].invertNodes and blocks[2].nodes[1].x==60)
assert(world.switches[1].legs.throat.edge=="new" and world.switches[1].legs.throat.toward=="end")
assert(world.switches[1].legs.through.edge=="old" and world.switches[1].legs.through.external)
assert(#saves==1 and broadcasts==1)
local event=messages[#messages-1]
assert(event.command=="rename" and event.args.operation.fromRevision==10 and event.args.operation.revision==11)
assert(messages[#messages].command=="renameResult" and messages[#messages].args.ok)
assert(event.args.worldData.edges.new and #event.args.renames==1 and event.args.renameFloor==10)
assert(not world.renames and not world.renameFloor and not world.displayName)
onCommand("RailroaderWayman","rename",player,{oldId="old",newId="new",revision=10,requestId="rename:1"})
assert(messages[#messages].args.ok and #saves==1 and world.revision==11, "duplicate request changed revision")
onCommand("RailroaderWayman","rename",player,{oldId="old",newId="different",revision=10,requestId="rename:2"})
assert(not messages[#messages].args.ok and world.revision==11)
world.edges.taken={}
assert(not runtime.RenameEdge("new","taken",11,"collision"))
assert(world.edges.new==blocks and world.edges.taken)
world.edges.taken=nil
assert(runtime.RenameEdge("new","third",11,"rename:3",player))
assert(runtime.RenameEdge("third","old",12,"rename:4",player))
assert(world.edges.old==blocks and world.revision==13 and #runtime.GraphSync().renames==3)
onCommand("RailroaderWayman","graphSync",player,{})
assert(messages[#messages].command=="graphSync" and #messages[#messages].args.renames==3)
-- A new server session has no persisted rename history; the saved graph stands alone.
dofile(luaRoot.."/server/Wayman/WaymanEntityRuntime.lua")
assert(runtime.GraphSync().renameFloor==13 and #runtime.GraphSync().renames==0)
print("PASS: literal atomic rename preserves arrays, own legs, inversion and external homonyms")
print("PASS: RR refusal/stale/client/invalid/colliding requests do not commit; saves precede notifications")
print("PASS: one revision per rename, idempotent requests, concurrent refusal, chains and session-only history")
if beta then print("PASS: rename registered against the installed unmodified Railroader modules") end
