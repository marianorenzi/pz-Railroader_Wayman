-- Real journals, synchronization ingress and graph-window acknowledgement paths.
next=nil
local root=debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/") or "."
local luaRoot=root.."/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path=luaRoot.."/shared/?.lua;"..luaRoot.."/client/?.lua;"..package.path
local actualRequire=require
local saveName,username="rename","alice"
local client=true
function isClient() return client end
function isServer() return false end
function getCore() return {getGameMode=function() return "Sandbox" end} end
function getWorld() return {getWorld=function() return saveName end} end
function getSpecificPlayer() return {getUsername=function() return username end} end
function getServerIP() return "server" end
function getServerName() return "test" end
function getServerPort() return 16261 end
local files,requests={},{}
function getFileReader(path)
    local value=files[path]
    if not value then return end
    return {readLine=function() local line=value; value=nil; return line end,close=function() end}
end
function getFileWriter(path) return {write=function(_,text) files[path]=text end,close=function() end} end
function sendClientCommand(_,_,command,args) requests[#requests+1]={command=command,args=args} end
Events={OnDisconnect={Add=function() end},OnConnected={Add=function() end}}
local registry={}
ModData={get=function(key) return registry[key] end,remove=function(key) registry[key]=nil end,
    add=function(key,data) registry[key]=data end}
local GD=actualRequire "Wayman/WaymanGraphData"
local Merge=actualRequire "Wayman/WaymanDraftMerge"
local Drafts=actualRequire "Wayman/WaymanLocalDraft"
local windowClass
ISCollapsableWindowJoypad={derive=function() windowClass={};windowClass.__index=windowClass;return windowClass end}
RailroaderWaymanGraphDisplay={refresh=function() end,getOptions=function()
    return {showAllEdges=true,showAvailableNodes=true,showSelectedEdge=true}
end}
WaymanLocalization={ui=function(key) return key end}
function require(name)
    if name=="Wayman/WaymanGraphDisplay" or name=="Wayman/WaymanLocalization" then return true end
    if name:find("Wayman/",1,true)==1 and name~="Wayman/WaymanNodeBlockTable" then return actualRequire(name) end
end
local function block(id,x)
    return {blockId=id..":nodes",owner=id,id="nodes",origin={x=0,y=0,z=0},
        nodes={{x=x,y=0,z=0},{x=x+5,y=0,z=0}}}
end
local base=GD.ensure({revision=10,edges={old={block("a",0),block("b",10)}},
    availableNodes={block("c",20)},switches={{id="s",legs={
        throat={edge="old",toward="start"},through={edge="old",toward="end",external=true},diverge={}}}}})
local operation={oldId="old",newId="new",fromRevision=10,revision=11,requestId="rename:1"}
local function renamed(data,old,new,rev)
    local result=GD.copy(data); assert(GD.renameEdge(result,old,new));result.revision=rev;return result
end
local function envelope(data,operations,floor)
    return {worldData=data,renames=operations or {},renameFloor=floor or 10}
end
local function boot(name)
    saveName=name; registry={};requests={}
    RailroaderWaymanGraphEditor=nil
    package.loaded["Wayman/WaymanGraphSync"]=nil
    local Sync=actualRequire "Wayman/WaymanGraphSync"
    local state=Drafts.open(base)
    dofile(luaRoot.."/client/Wayman/WaymanGraphEditor.lua")
    local selected="old"
    local editor=setmetatable({localState=state,draft=state.draft,baseRevision=10,
        statusLabel={setName=function() end},getSelectedEdgeId=function() return selected end,
        getIsVisible=function() return false end,
        refreshAll=function(_,value) if value then selected=value end end},windowClass)
    RailroaderWaymanGraphEditor.instance=editor
    assert(Sync.receive(envelope(base)))
    return Sync,state,editor,function() return selected end
end
local Sync,state,editor,selection=boot("pure")
state.draft.edges.old[2].invertNodes=true
state.draft.edges.old[1],state.draft.edges.old[2]=state.draft.edges.old[2],state.draft.edges.old[1]
state.draft.edges.old[3]=table.remove(state.draft.availableNodes,1)
state.draft.switches[1].legs.throat.toward="end"
state.geometry.a={geometry={kind="turn",nodes=GD.copy(state.draft.edges.old[2].nodes)}}
state.nodeDrafts.b={raw="keep"}
state.pending={requestId="wire:1",draft=GD.copy(state.draft),geometry={}}
state.remote=GD.copy(base)
state.conflictVersions={base=GD.copy(base),localDraft=GD.copy(state.draft)}
state.conflicts={"existing leg conflict"}
local array=state.draft.edges.old
local merge,merges=Merge.merge,0
Merge.merge=function(...) merges=merges+1;return merge(...) end
local confirmed=renamed(base,"old","new",11)
-- A raw snapshot must not merge/delete the old ID before its operation arrives.
Sync.receiveSnapshot(confirmed);Sync.receiveSnapshot(confirmed)
assert(#requests==1 and requests[1].command=="graphSync" and state.draft.edges.old==array)
assert(Sync.current().edges.old)
assert(Sync.receive(envelope(confirmed,{operation})))
assert(merges==0 and state.base.revision==11 and state.draft.revision==11)
assert(state.draft.edges.new==array and not state.draft.edges.old and selection()=="new")
assert(array[1].owner=="b" and array[1].invertNodes and array[3].owner=="c")
assert(state.draft.switches[1].legs.throat.toward=="end")
assert(state.draft.switches[1].legs.through.edge=="old" and state.draft.switches[1].legs.through.external)
assert(state.pending.requestId=="wire:1" and state.pending.draft.edges.new and state.pending.draft.revision==10)
assert(state.remote.edges.new and state.conflictVersions.base.edges.new and state.conflictVersions.localDraft.edges.new)
assert(state.nodeDrafts.b.raw=="keep" and state.geometry.a)
Sync.receive(envelope(confirmed,{operation}))
assert(state.draft.edges.new==array and merges==0, "duplicate rename repeated the merge")
assert(not Sync.receive(envelope(confirmed,{{oldId="old",newId="new",revision=99,fromRevision=98}})))
local getPlayerBefore=getSpecificPlayer
getSpecificPlayer=function() return nil end
function getPlayer() return nil end
local requestCount=#requests
Sync.request()
assert(#requests==requestCount,"connection requested sync before player creation")
getSpecificPlayer=getPlayerBefore

-- Transactional preflight protects an unrelated local target across every copy.
Sync,state,editor=boot("collision")
state.draft.edges.new={table.remove(state.draft.availableNodes,1)}
state.pending={requestId="wire",draft=GD.copy(state.draft),geometry={}}
local before=assert(GD.worldDataToJSON(state.draft))
Sync.receive(envelope(confirmed,{operation}))
assert(state.renameBlocked and state.base.edges.old and before==GD.worldDataToJSON(state.draft))
assert(Sync.current().edges.new and state.remote.edges.new and #state.conflicts==1)
editor:onResult({requestId="wire",ok=true,worldData=confirmed})
assert(state.renameBlocked and state.pending.acknowledged and before==GD.worldDataToJSON(state.draft))
assert(Drafts.resolveLocal(state) and not state.renameBlocked and not state.pending)

Sync,state,editor=boot("deleted-and-target-reused-locally")
state.draft.edges.old=nil
state.draft.edges.new={table.remove(state.draft.availableNodes,1)}
before=assert(GD.worldDataToJSON(state.draft))
Sync.receive(envelope(confirmed,{operation}))
assert(state.renameBlocked and before==GD.worldDataToJSON(state.draft),
    "a local target was conflated with the renamed edge after local deletion")

Sync,state,editor=boot("deleted-locally")
for _,value in ipairs(state.draft.edges.old) do state.draft.availableNodes[#state.draft.availableNodes+1]=value end
state.draft.edges.old=nil;state.draft.switches[1].legs.throat={}
Sync.receive(envelope(confirmed,{operation}))
assert(state.base.edges.new and not state.draft.edges.new and not state.draft.edges.old)
assert(#state.draft.availableNodes==3, "rename resurrected locally deleted edge")

-- Non-rename revisions are still merged; advancing the namespace cursor does
-- not claim those geometry/topology changes were already applied to the base.
Sync,state,editor=boot("gap-with-real-edit")
state.draft.edges.old[1].invertNodes=true
local changed=GD.copy(base);changed.revision=11;changed.edges.old[2].nodes[1].x=12
local after=renamed(changed,"old","new",12)
local second={oldId="old",newId="new",fromRevision=11,revision=12,requestId="r2"}
local count=merges
Sync.receive(envelope(after,{second}))
assert(merges==count+1 and state.base.revision==12 and state.draft.edges.new[1].invertNodes)
assert(state.draft.edges.new[2].nodes[1].x==12 and #state.conflicts==0)

Sync,state,editor=boot("source-is-a-different-local-creation")
state.base.edges.old=nil
state.draft.edges.old={table.remove(state.draft.availableNodes,1)}
before=assert(GD.worldDataToJSON(state.draft))
Sync.receive(envelope(after,{second}))
assert(state.renameBlocked and before==GD.worldDataToJSON(state.draft),
    "an unrelated local source was renamed as if it were the server edge")

-- The publish acknowledgement predates a rename but arrives after it. Its sent
-- baseline was renamed locally, while the actual wire payload remained unchanged.
Sync,state,editor=boot("late-ack")
state.draft.edges.old[1].invertNodes=true
local wire=GD.copy(state.draft)
state.pending={requestId="accepted",draft=GD.copy(wire),geometry={}}
state.draft.edges.old[2].invertNodes=true
local accepted=GD.copy(wire);accepted.revision=11
local latest=renamed(accepted,"old","new",12)
Sync.receive(envelope(latest,{second}))
assert(state.pending and wire.edges.old and state.pending.draft.edges.new)
editor:onResult({requestId="accepted",ok=true,worldData=accepted})
assert(not state.pending and state.base.revision==12 and #state.conflicts==0)
assert(state.base.edges.new[1].invertNodes and not state.base.edges.new[2].invertNodes)
assert(state.draft.edges.new[2].invertNodes and editor.dirty, "late ack lost post-send edits")
Sync.receive(envelope(accepted,{}))
assert(Sync.current().revision==12, "old result rolled global cache back")

-- Two more renames return to a reused original ID; duplicate/delayed events
-- cannot accidentally rename that new incarnation a second time.
local third={oldId="new",newId="third",fromRevision=12,revision=13,requestId="r3"}
local fourth={oldId="third",newId="old",fromRevision=13,revision=14,requestId="r4"}
local final=renamed(renamed(latest,"new","third",13),"third","old",14)
Sync.receive(envelope(final,{second,third,fourth}))
assert(state.draft.edges.old and not state.draft.edges.new and state.base.revision==14)
Sync.receive(envelope(latest,{second}));Sync.receive(envelope(final,{second,third,fourth}))
assert(state.draft.edges.old and state.base.revision==14)

-- No editor instance is needed: the shared journal is transformed and persisted.
Sync,state,editor=boot("no-editor")
state.draft.edges.old[1].invertNodes=true
RailroaderWaymanGraphEditor.instance=nil
Sync.receive(envelope(confirmed,{operation}))
assert(state.draft.edges.new[1].invertNodes and state.renameRevision==11)
assert(Drafts.save(state))
local serialized=assert(GD.worldDataToJSON(state))
assert(not serialized:find('"renames"',1,true), "journal persisted a rename history")
package.loaded["Wayman/WaymanLocalDraft"]=nil
Drafts=actualRequire "Wayman/WaymanLocalDraft"
local restored=Drafts.open(confirmed)
assert(restored.draft.edges.new[1].invertNodes and restored.renameRevision==11)

-- A server restart cannot replay a rename it no longer remembers. Preserve the
-- exact old draft and ask for explicit review, never guess from matching text.
Sync,state,editor=boot("missed-history")
state.draft.edges.old[1].invertNodes=true
before=assert(GD.worldDataToJSON(state.draft))
Sync.receive(envelope(confirmed,{},11))
assert(state.renameBlocked and state.remote.edges.new and state.base.revision==10)
assert(before==GD.worldDataToJSON(state.draft) and #state.conflicts==1)
assert(Drafts.resolveLocal(state) and state.base.revision==11 and state.draft.edges.old)
assert(Drafts.reset(state,confirmed) and state.draft.edges.new and not state.draft.edges.old)

-- Separate authors receive the same event but keep different local edits.
username="alice"
local firstSync,firstState=boot("two-authors")
firstState.draft.edges.old[1].invertNodes=true
firstSync.receive(envelope(confirmed,{operation}))
username="bob"
local secondSync,secondState=boot("two-authors")
secondState.draft.edges.old[2].invertNodes=true
secondSync.receive(envelope(confirmed,{operation}))
assert(firstState.draft.edges.new[1].invertNodes and not firstState.draft.edges.new[2].invertNodes)
assert(secondState.draft.edges.new[2].invertNodes and not secondState.draft.edges.new[1].invertNodes)

-- SP follows the same authority/envelope/journal path, including the immediate
-- callback during RenameEdge, without publishing any unrelated draft edit.
client=false
Sync,state,editor=boot("singleplayer")
function getTimestampMs() return 56789 end
ModData.getOrCreate=function(key) return registry[key] end
for _,name in ipairs({"OnTick","OnObjectAboutToBeRemoved","OnClientCommand"}) do
    Events[name]={Add=function() end}
end
RR={API={edges=function() return {} end,registerTrack=function() return true end,
    unregisterTrack=function() return true end}}
local saves=0
function save(flag) assert(flag);saves=saves+1 end
dofile(luaRoot.."/server/Wayman/WaymanEntityRuntime.lua")
state.draft.edges.old[1].invertNodes=true
assert(editor:renameEdge("old","single.player"))
assert(saves==1 and not editor.pendingRename and state.base.revision==11)
assert(Sync.current().edges["single.player"] and not Sync.current().edges["single.player"][1].invertNodes)
assert(state.draft.edges["single.player"][1].invertNodes and editor.dirty)
Merge.merge=merge
print("PASS: snapshot/event ordering, duplicate/malformed messages, chains and ID reuse preserve naming")
print("PASS: isolated rename bypasses merge and preserves every journal version, selections, raw/staged edits and pending request")
print("PASS: local collision/deletion, real concurrent edits and late correlated acknowledgements retain local work")
print("PASS: hidden/absent editor and persisted journal recovery; missing session history requires explicit reconciliation")
print("PASS: singleplayer authority, synchronous notification and request completion preserve unpublished edits")
