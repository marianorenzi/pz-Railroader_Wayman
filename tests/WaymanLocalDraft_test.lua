-- Local journal, recovery, three-way merge and actual graph-window callbacks.
-- Match the Kahlua environment that raised the real runtime error.
next = nil
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/client/?.lua;" .. package.path
local actualRequire = require
local client, username, saveName = false, "alice", "test-save"
function isServer() return false end
function isClient() return client end
function getDebug() return true end
function getSpecificPlayer() return {getUsername=function() return username end} end
function getWorld() return {getWorld=function() return saveName end} end
function getCore() return {getGameMode=function() return "Sandbox" end} end
function getServerIP() return "127.0.0.1" end
function getServerPort() return 16261 end
function getServerName() return "test-server" end
function getTimestampMs() return 1234 end
local files, lastPath, failWrite, journalWrites = {}, nil, false, 0
function getFileReader(path)
    if not files[path] then return nil end
    local done = false
    return {readLine=function() if not done then done=true; return files[path] end end,close=function() end}
end
function getFileWriter(path)
    lastPath = path
    return {write=function(_, value)
        journalWrites = journalWrites + 1
        files[path] = failWrite and value:sub(1, 20) or value
        if failWrite then error("simulated interrupted write") end
    end,close=function() end}
end
local GD = require "Wayman/WaymanGraphData"
local Merge = require "Wayman/WaymanDraftMerge"
local function block(id, x)
    return {blockId=id..":nodes",owner=id,id="nodes",origin={x=0,y=0,z=0},nodes={{x=x,y=0,z=0}}}
end
local base = GD.ensure({revision=1,availableNodes={block("a",0),block("b",10),block("c",20)}})
local localDraft, remote = GD.copy(base), GD.copy(base)
localDraft.edges.line = {table.remove(localDraft.availableNodes,1)}
remote.availableNodes[2].nodes[1].x = 11
table.remove(remote.availableNodes,3)
remote.availableNodes[#remote.availableNodes+1] = block("d",30)
remote.revision = 2
local merged, conflicts = Merge.merge(base,localDraft,remote)
assert(#conflicts == 0 and merged.edges.line[1].owner == "a")
assert(#merged.availableNodes == 2 and merged.availableNodes[1].nodes[1].x == 11)
assert(merged.availableNodes[2].owner == "d" and merged.revision == 2)
local left, right = GD.copy(base), GD.copy(base)
left.edges.left, right.edges.right = {table.remove(left.availableNodes,1)}, {table.remove(right.availableNodes,1)}
merged, conflicts = Merge.merge(base,left,right)
assert(#conflicts > 0 and merged.edges.left[1].owner == "a")

base = GD.ensure({revision=3,edges={line={block("a",0),block("b",10),block("c",20),block("d",30)}},
    switches={{id="s",owner="s",at={x=0,y=0},legs={throat={edge="line",toward="start"},through={},diverge={}}}}})
left, right = GD.copy(base), GD.copy(base)
left.edges.line[1],left.edges.line[2] = left.edges.line[2],left.edges.line[1]
right.edges.line[3],right.edges.line[4] = right.edges.line[4],right.edges.line[3]
merged, conflicts = Merge.merge(base,left,right)
assert(#conflicts == 0)
assert(merged.edges.line[1].owner == "b" and merged.edges.line[4].owner == "c")
left.switches[1].legs.throat = {edge="other",toward="start",external=true}
right.switches[1].legs.throat = {edge="line",toward="end"}
merged, conflicts = Merge.merge(base,left,right)
assert(#conflicts > 0 and merged.switches[1].legs.throat.edge == "other"
    and merged.switches[1].legs.throat.toward == "start", "leg pair was split")
right = GD.copy(base); right.edges.line = nil; right.availableNodes = GD.copy(base.edges.line)
merged, conflicts = Merge.merge(base,left,right)
assert(#conflicts > 0, "deletion versus reorder was not detected")

-- Concurrently assigning the same available blocks in opposite orders must
-- keep the exact pair identity in the conflict shown to the reviewer.
local orderBase = GD.ensure({revision=1,availableNodes={block("a",0),block("b",10)}})
local orderLocal, orderRemote = GD.copy(orderBase), GD.copy(orderBase)
orderLocal.edges.line = {orderLocal.availableNodes[1],orderLocal.availableNodes[2]}
orderRemote.edges.line = {orderRemote.availableNodes[2],orderRemote.availableNodes[1]}
orderLocal.availableNodes, orderRemote.availableNodes = {}, {}
local _, orderConflicts = Merge.merge(orderBase,orderLocal,orderRemote)
local pairConflict = false
for _, message in ipairs(orderConflicts) do
    if message:find("order line: a:nodes/b:nodes",1,true) then pairConflict = true end
end
assert(pairConflict, "concurrent order conflict lost its edge/block identifiers")

local function boot()
    package.loaded["Wayman/WaymanLocalDraft"] = nil
    return require "Wayman/WaymanLocalDraft"
end
local Drafts = boot()
local state = Drafts.open(base)
-- Revision fast paths must preserve local work and request correlation, while
-- avoiding a merge or journal rewrite for a repeated authority snapshot.
local previousSaveName, realMerge = saveName, Merge.merge
saveName = "revision-fast-paths"
local mergeCalls = 0
Merge.merge = function(...)
    mergeCalls = mergeCalls + 1
    return realMerge(...)
end
local function fresh()
    return {base=GD.copy(base),draft=GD.copy(base),geometry={},nodeDrafts={},conflicts={}}
end
local same = fresh()
same.draft.edges.line[1].invertNodes = true
same.geometry.a = {geometry={kind="turn",nodes={{x=9,y=0,z=0}}}}
same.nodeDrafts.b = {unregistered=false}
same.pending = {requestId="still-pending"}
same.conflicts, same.remote = {"existing conflict"}, GD.copy(base)
same.remote.revision = base.revision + 1
local oldDraft, oldGeometry, writes = same.draft, same.geometry, journalWrites
Drafts.rebase(same,GD.copy(base))
assert(mergeCalls == 0 and journalWrites == writes, "same revision repeated merge or disk write")
assert(same.draft == oldDraft and same.geometry == oldGeometry and same.nodeDrafts.b)
assert(same.draft.edges.line[1].invertNodes and same.pending.requestId == "still-pending")
assert(same.conflicts[1] == "existing conflict" and same.remote.revision == base.revision + 1)

local newer, clean = GD.copy(base), fresh()
newer.revision = base.revision + 1
newer.edges.line[1].nodes[1].x = 6
clean.pending = {requestId="unconfirmed"}
Drafts.rebase(clean,newer)
assert(mergeCalls == 0 and journalWrites == writes + 1, "clean newer graph went through the merge")
assert(clean.base.revision == newer.revision and clean.draft.edges.line[1].nodes[1].x == 6)
assert(clean.base ~= newer and clean.draft ~= newer and clean.base ~= clean.draft)
assert(not Drafts.changed(clean) and clean.pending.requestId == "unconfirmed")

local edited = fresh()
edited.draft.edges.line[1].invertNodes = true
Drafts.rebase(edited,newer)
assert(mergeCalls == 1 and edited.draft.edges.line[1].invertNodes,
    "newer authority snapshot discarded the local inversion")
assert(edited.base.revision == newer.revision and edited.draft.edges.line[1].nodes[1].x == 6)

local older, rollback = GD.copy(base), fresh()
older.revision = base.revision - 1
rollback.draft.edges.incomplete = {}
Drafts.rebase(rollback,older)
assert(mergeCalls == 1 and rollback.draft.edges.incomplete and #rollback.conflicts == 1)
assert(rollback.base.revision == base.revision and rollback.remote.revision == older.revision)

local retry = fresh()
failWrite = true
assert(not Drafts.save(retry) and retry.storageError)
failWrite, writes = false, journalWrites
Drafts.rebase(retry,GD.copy(base))
assert(not retry.storageError and journalWrites == writes + 1 and mergeCalls == 1,
    "equal revision prevented retrying a failed journal write")
assert(Drafts.reset(same,GD.copy(base)))
assert(not Drafts.changed(same) and not same.pending and not same.remote and #same.conflicts == 0,
    "explicit reload at the same revision did not discard local work")
Merge.merge, saveName = realMerge, previousSaveName

assert(not Drafts.changed(state), "opening a clean editor must work without global next")
state.geometry.pending = {}
assert(Drafts.changed(state), "staged geometry must mark the draft pending")
state.geometry.pending = nil
state.nodeDrafts.pending = {}
assert(Drafts.changed(state), "unstaged node changes must mark the draft pending")
state.nodeDrafts.pending = nil
state.draft.edges.incomplete = {}
assert(Drafts.save(state))
local goodPath = lastPath
state.draft.edges.newer = {}
failWrite = true
assert(not Drafts.save(state) and state.storageError)
failWrite = false
Drafts = boot(); state = Drafts.open(base)
assert(state.draft.edges.incomplete and not state.draft.edges.newer, "journal lost last complete write")
assert(files[goodPath])
username = "bob"
local bob = Drafts.open(base)
assert(bob.draft.edges.incomplete == nil)
assert(Drafts.save(bob))
assert(not Drafts.save(state), "old author's draft was written into another author's journal")
username, client = "alice", true
state = Drafts.open(base)
assert(state.draft.edges.incomplete == nil, "SP draft leaked into MP")
state.draft.edges.mp = {}; assert(Drafts.save(state))
client = false
state = Drafts.open(base)
assert(state.draft.edges.incomplete and not state.draft.edges.mp)
saveName = "another-save"
assert(Drafts.open(base).draft.edges.incomplete == nil)
saveName = "test-save"
state = Drafts.open(base)

-- Real callbacks: broadcasts do not acknowledge a pending submission; an ack
-- preserves edits made after sending, and only the matching request may clear it.
local windowClass
ISCollapsableWindowJoypad = {derive=function() windowClass={}; windowClass.__index=windowClass; return windowClass end}
RailroaderWaymanGraphDisplay = {refresh=function() end}
WaymanLocalization = {ui=function(key) return key end}
function require(name)
    if name == "Wayman/WaymanGraphData" or name == "Wayman/WaymanRRGraph" or name == "Wayman/WaymanLocalDraft" then return actualRequire(name) end
    return true
end
local world = GD.copy(base)
ModData = {get=function() return world end}
RR = {API={edges=function() return {} end}}
dofile(luaRoot .. "/client/Wayman/WaymanGraphEditor.lua")
RailroaderWaymanLocalDraft.reset(state,world)
local editor = setmetatable({localState=state,draft=state.draft,baseRevision=world.revision,
    statusLabel={setName=function() end},refreshAll=function() end},windowClass)
editor.draft.edges.line[1].invertNodes = true
editor:setDirty()
client = true
-- Use a matching MP identity for the live session.
state = RailroaderWaymanLocalDraft.open(world)
RailroaderWaymanLocalDraft.reset(state,world)
editor.localState,editor.draft = state,state.draft
editor.draft.edges.line[1].invertNodes = true
local sent
function sendClientCommand(_,_,command,args) assert(command == "applyGraph"); sent=args end
editor:onAccept()
assert(sent and state.pending and editor.awaitingSave)
world = GD.copy(world); world.revision = world.revision + 1
editor:onWorldData(world)
assert(state.pending and editor.awaitingSave and editor.draft.edges.line[1].invertNodes)
editor.draft.edges.line[2].invertNodes = true
editor:setDirty()
editor:onResult({requestId="someone-else",ok=true,worldData=world})
assert(state.pending and editor.draft.edges.line[2].invertNodes)
local accepted = GD.copy(sent.draft); accepted.revision = world.revision
editor:onResult({requestId=sent.requestId,ok=true,worldData=accepted})
assert(not state.pending and editor.draft.edges.line[2].invertNodes and editor.dirty)
assert(state.base.edges.line[1].invertNodes and not state.base.edges.line[2].invertNodes)
world = accepted
editor:onAccept()
local rejectedRequest = sent.requestId
editor:onResult({requestId=rejectedRequest,ok=false,reason="overlap",worldData=world})
assert(state.pending and state.pending.requestId == rejectedRequest and editor.dirty and not editor.awaitingSave)
Drafts = boot(); state = Drafts.open(accepted)
assert(state.draft.edges.line[2].invertNodes, "post-send work did not survive reconnect")

-- Exercise the node window's actual edit/stage/reopen callbacks. Edits must
-- reach the local journal before Apply, and never write the physical object.
client, saveName, world = false, "node-test", GD.copy(base)
local nodeClass
ISCollapsableWindowJoypad = {
    derive=function() nodeClass={}; nodeClass.__index=nodeClass; return nodeClass end,
    new=function(self) return setmetatable({setWantKeyEvents=function() end},self) end,
}
RailroaderWaymanWorldHighlights = {colors={},clearGroup=function() end}
Events = {OnServerCommand={Add=function() end},OnTick={Add=function() end},OnMouseDown={Add=function() end}}
local opened = 0
RailroaderWaymanGraphEditor = {open=function()
    opened=opened+1
    return {syncLocalState=function() end}
end}
function require(name)
    if name == "Wayman/WaymanEntityDescriptor" or name == "Wayman/WaymanLocalDraft" then return actualRequire(name) end
    return true
end
dofile(luaRoot .. "/client/Wayman/WaymanNodeEditor.lua")
local objectData = {railroaderWayman={id="a"}}
local physical = {getModData=function() return objectData end,getObjectIndex=function() return 0 end,
    getSquare=function() return {getX=function() return 10 end,getY=function() return 10 end,getZ=function() return 0 end} end}
local function instance()
    return {data={id="a"},master=physical,entityName="DebugTurn",facing="N",origin={x=0,y=0,z=0},
        defaults={kind="turn",nodes={{x=0,y=0,z=0}}}}
end
local node = nodeClass:new(0,0,700,500,instance(),0)
node.statusLabel={setName=function() end}
node.refreshNodeList=function() end
node.refreshBlockList=function() end
node.refreshHighlights=function() end
node.editingBlock,node.editingIndex,node.editingNode = node.blocks[1],1,node.blocks[1].nodes[1]
node:commitNodeEdit({getX=function() return 5 end,getY=function() return 0 end,getZ=function() return 0 end})
assert(node.localState.nodeDrafts.a.data.nodes[1].x == 5)
assert(objectData.railroaderWayman.nodes == nil and world.edges.line[1].nodes[1].x == 0)
local reopened = nodeClass:new(0,0,700,500,instance(),0)
assert(reopened.blocks[1].nodes[1].x == 5 and reopened.dirty)
node:onApply()
assert(opened == 1 and node.localState.geometry.a.modData.nodes[1].x == 5)
assert(node.localState.nodeDrafts.a == nil and objectData.railroaderWayman.nodes == nil)
reopened = nodeClass:new(0,0,700,500,instance(),0)
assert(reopened.blocks[1].nodes[1].x == 5 and not reopened.dirty)
-- Reload discards this staged geometry even when the graph revision is unchanged.
-- Other staged owners still need their previews after canonical geometry returns.
node.localState.geometry.b = {geometry={kind="turn",nodes={{x=12,y=0,z=0}}}}
Drafts.preview(node.localState)
local unchangedRevision = world.revision
node:onReload()
assert(world.revision == unchangedRevision and node.localState.geometry.a == nil)
assert(node.blocks[1].nodes[1].x == 0 and node.localState.draft.edges.line[1].nodes[1].x == 0,
    "same-revision node Reload retained discarded preview geometry")
assert(node.localState.geometry.b and node.localState.draft.edges.line[2].nodes[1].x == 12,
    "node Reload discarded another owner's staged geometry")
local missing = instance(); missing.data={}
local unregistered = nodeClass:new(0,0,700,500,missing,0)
unregistered.statusLabel={setName=function() end}
unregistered.refreshBlockList=function() end
unregistered.refreshHighlights=function() end
unregistered.blocks[1].nodes[1].x,unregistered.blocks[1].isDefault = 9,false
unregistered:setDirty()
local key = Drafts.nodeKey(missing)
assert(unregistered.localState.nodeDrafts[key].unregistered)
Drafts.rebase(unregistered.localState,world)
assert(unregistered.localState.nodeDrafts[key], "unregistered entity work was lost")
missing = instance(); missing.data={}
assert(nodeClass:new(0,0,700,500,missing,0).blocks[1].nodes[1].x == 9)
local debugFunction = getDebug
function getDebug() return false end
assert(RailroaderWaymanNodeEditor.open(instance(),0) == nil, "normal-mode UI exposed geometry editing")
getDebug = debugFunction

-- Physical deletion also drops staged and raw geometry; a stale journal cannot
-- bring the owner back through a merge.
local removed = GD.copy(world)
table.remove(removed.edges.line,1)
removed.revision = removed.revision + 1
Drafts.rebase(node.localState,removed)
assert(node.localState.geometry.a == nil and node.localState.nodeDrafts.a == nil)
for _, list in pairs(node.localState.draft.edges) do
    for _, b in ipairs(list) do assert(b.owner ~= "a") end
end
print("PASS: three-way geometry/deletion refresh, compatible order changes and atomic leg conflicts")
print("PASS: per-save/server/author journal, interrupted-write recovery and local incomplete drafts")
print("PASS: correlated acknowledgements, other-author broadcasts and preservation of post-send edits")
print("PASS: live node edits autosave before staging, restore on reopen and preview without mutating physical objects")
print("PASS: revision fast paths, pending/conflict preservation, storage retries and same-revision reloads")
