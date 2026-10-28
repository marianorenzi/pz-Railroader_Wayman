-- Independent component identities, lifecycle, physical selection and local drafts.
next = nil -- Match the game's Kahlua environment.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path = luaRoot .. "/shared/?.lua;" .. luaRoot .. "/client/?.lua;" .. package.path
local actualRequire, originalPrint = require, print
local world, squares, client, server, refuse = {}, {}, false, true, false
local broadcasts, saves, publications, replies = 0, 0, 0, {}
function isClient() return client end
function isServer() return server end
function getDebug() return true end
function save() saves = saves + 1 end
ModData = {getOrCreate=function() return world end, get=function() return world end,
    transmit=function() broadcasts = broadcasts + 1 end}
local function event()
    local handlers = {}
    return {Add=function(fn) handlers[#handlers + 1] = fn end,
        fire=function(...) for _, fn in ipairs(handlers) do fn(...) end end}
end
Events = {OnTick=event(), OnClientCommand=event(), OnObjectAboutToBeRemoved=event(),
    OnRailroaderRegisterTrack=event(), OnServerCommand=event(),
    OnFillWorldObjectContextMenu=event(), OnMouseDown=event()}
RR = {API={edges=function() return {{id="main"}} end,
    registerTrack=function()
        publications = publications + 1
        if refuse then return nil, "refused" end
        return true
    end, unregisterTrack=function()
        if refuse then return nil, "refused" end
        return true
    end}}
function sendServerCommand(_, _, command, args) replies[#replies + 1] = {command=command,args=args} end
function getCell() return {getGridSquare=function(_, x, y, z) return squares[x..":"..y..":"..z] end} end
function print() end
dofile(luaRoot .. "/server/Wayman/WaymanEntityRuntime.lua")
local GD, Descriptor, runtime = RailroaderWaymanGraphData, RailroaderWaymanEntityDescriptor, RailroaderWaymanEntityRuntime
local function json(data) return assert(GD.worldDataToJSON(data)) end
local function reload(data) return assert(GD.worldDataFromJSON(json(data))) end
local function object(name, facing, origin)
    local data, master, square = {}, nil, nil
    local x, y, z = origin.x + 1, origin.y + 2, origin.z
    local info = {getFaceName=function() return facing end, getMasterX=function() return 1 end,
        getMasterY=function() return 2 end, getMasterZ=function() return 0 end}
    master = {getMasterObject=function() end, getSquare=function() return square end,
        getEntityScript=function() return {getName=function() return name end} end,
        getSpriteConfig=function() return {getFaceInfo=function() return info end,
            isMultiSquareMaster=function() return true end} end,
        getModData=function() return data end, transmitModData=function() end,
        getX=function() return x end, getY=function() return y end, getZ=function() return z end,
        getObjectIndex=function() return 0 end}
    square = {getX=function() return x end, getY=function() return y end,getZ=function() return z end,
        getObjects=function() return {size=function() return 1 end,get=function() return master end} end}
    squares[x..":"..y..":"..z] = square
    return master, data
end
local function block(owner, group)
    for _, entry in ipairs(world.availableNodes) do
        if entry.owner == owner and entry.id == group then return entry end
    end
    for _, entries in pairs(world.edges) do
        for _, entry in ipairs(entries) do
            if entry.owner == owner and entry.id == group then return entry end
        end
    end
end
local function switch(owner)
    for _, entry in ipairs(world.switches) do if entry.owner == owner then return entry end end
end
local function construct(master)
    runtime.OnCreate({thumpable=master})
    Events.OnTick.fire()
end

local created, ids = {}, {}
for _, name in ipairs({"SymmetricalCompactThreeWayTurnout", "SymmetricalThreeWayTurnout"}) do
    for facing, geometry in pairs(RailroaderWaymanEntityGeometry[name]) do
        local origin = {x=1000 + #created * 100,y=2000,z=1}
        local master, data = object(name, facing, origin)
        construct(master)
        assert(not data.railroaderWayman.id and #data.railroaderWayman.components == 3)
        local instances = assert(Descriptor.getInstances(master))
        for i, component in ipairs(data.railroaderWayman.components) do
            local owner = component.id
            assert(owner:match("^turnout_%d+$") and not ids[owner] and component.type == "turnout")
            ids[owner] = true
            assert(Descriptor.getInstance(master, nil, owner).componentIndex == i)
            assert(instances[i].defaults.kind == "turnout")
            for _, group in ipairs({"at", "through", "diverge"}) do
                local entry = assert(block(owner, group))
                assert(entry.blockId == owner..":"..group)
                local componentGeometry = geometry.components[i]
                local expected = group == "through" and componentGeometry.throughNodes
                    or group == "diverge" and componentGeometry.divergingNodes or nil
                if not expected or #expected == 0 then expected = {componentGeometry.at} end
                assert(#entry.nodes == #expected)
                for index, node in ipairs(expected) do
                    assert(entry.nodes[index].x == node.x and entry.nodes[index].y == node.y)
                    local absolute = GD.getAbsoluteNode(entry.origin, entry.nodes[index])
                    assert(absolute.x == origin.x + node.x)
                    assert(absolute.y == origin.y + node.y and absolute.z == 1)
                end
            end
            local logicalSwitch = assert(switch(owner))
            assert(logicalSwitch.place.x == geometry.components[i].switch.x)
            assert(logicalSwitch.place.y == geometry.components[i].switch.y)
            for _, leg in pairs(logicalSwitch.legs) do assert(GD.isEmpty(leg)) end
        end
        created[#created + 1] = {master=master,data=data,origin=origin}
    end
end
assert(#created == 8 and #world.availableNodes == 72 and #world.switches == 24)
assert(GD.isEmpty(world.edges), "constructing components invented connections")
assert(world.nextTurnoutId == 25 and publications == 0)
assert(not runtime.SaveGeometry(created[1].master, {}), "compound recovery needs a component selection")

-- Persist physical modData and WorldData independently, as on save/chunk reload.
world = GD.ensure(reload(world))
local snapshot, transmissions = json(world), broadcasts
for _, entry in ipairs(created) do
    entry.data.railroaderWayman = reload(entry.data.railroaderWayman)
    construct(entry.master)
end
assert(snapshot == json(world) and broadcasts == transmissions, "reload duplicated component identities")

-- Shared coordinates and mixed supported types still have separate identities.
RailroaderWaymanEntityGeometry.MixedComponents = {N={components={
    {type="turn",nodes={{x=0,y=0,z=0},{x=0,y=10,z=0}}},
    {type="turnout",at={x=0,y=0,z=0},switch={x=0,y=0,z=0}},
}}}
local mixed, mixedData = object("MixedComponents","N",{x=3000,y=3000,z=0})
construct(mixed)
assert(mixedData.railroaderWayman.components[1].id == "turn_1")
assert(mixedData.railroaderWayman.components[2].id == "turnout_25")
assert(block("turn_1","nodes") and block("turnout_25","at"))

local entry = created[1]
local first, second, third = table.unpack(entry.data.railroaderWayman.components)
local siblings = json({first, third})
local replacement = {id=first.id,at={x=20,y=20,z=0},switch={x=1,y=1,z=0}}
assert(runtime.SaveGeometry(entry.master,replacement,nil,2))
assert(entry.data.railroaderWayman.components[2].id == second.id, "client selected another owner")
assert(json({entry.data.railroaderWayman.components[1],entry.data.railroaderWayman.components[3]}) == siblings)
assert(block(second.id,"at").nodes[1].x == 20 and block(first.id,"at").nodes[1].x ~= 20)

-- The graph editor finds multiple component IDs on the same physical master.
local edits = {}
for _, index in ipairs({1, 3}) do
    local component = entry.data.railroaderWayman.components[index]
    edits[component.id] = {x=entry.master:getX(),y=entry.master:getY(),z=entry.master:getZ(),
        entityName="SymmetricalCompactThreeWayTurnout",facing=Descriptor.describe(entry.master).facing,
        modData={id=component.id,switch={x=index,y=index,z=0}}}
end
local before, beforeObject = json(world), json(entry.data)
refuse = true
assert(not runtime.ApplyGraphDraft(GD.copy(world),world.revision,edits))
assert(json(world) == before and json(entry.data) == beforeObject, "RR rejection changed components")
refuse = false
assert(runtime.ApplyGraphDraft(GD.copy(world),world.revision,edits))
assert(entry.data.railroaderWayman.components[1].switch.x == 1)
assert(entry.data.railroaderWayman.components[3].switch.x == 3)
assert(entry.data.railroaderWayman.components[2].at.x == 20 and saves == 1)
edits[first.id].modData.id = second.id
assert(not runtime.ApplyGraphDraft(GD.copy(world),world.revision,edits))

-- A debug click exposes every independently editable component, including on child tiles.
local selected, nodeClass
local function menu()
    return {options={},addOption=function(self,label,target,fn,...)
        local option={label=label,target=target,fn=fn,args={...}}
        self.options[#self.options + 1] = option
        return option
    end,addSubMenu=function(_,option,submenu) option.submenu=submenu end}
end
ISContextMenu = {getNew=function() return menu() end}
ISWorldObjectContextMenu = {setTest=function() return true end}
function getText(key) return key end
RailroaderWaymanNodeEditor = {open=function(instance) selected=instance end}
function require(name)
    if name == "Wayman/WaymanEntityDescriptor" then return actualRequire(name) end
    return true
end
dofile(luaRoot .. "/client/Wayman/WaymanEntityContextMenu.lua")
local context = menu()
local child = {getMasterObject=function() return entry.master end,
    getSquare=function() return entry.master:getSquare() end}
assert(Descriptor.getInstance(child,nil,second.id).data.id == second.id)
Events.OnFillWorldObjectContextMenu.fire(0,context,{child},false)
assert(#context.options == 1 and #context.options[1].submenu.options == 3)
for _, option in ipairs(context.options[1].submenu.options) do
    option.fn(option.target,table.unpack(option.args))
    assert(selected.data.id == option.label)
end

-- The actual node editor stages/reloads the selected component only.
server = false
actualRequire("Wayman/WaymanDraftMerge")
local files = {}
function getSpecificPlayer() return {getUsername=function() return "component-test" end} end
function getWorld() return {getWorld=function() return "components" end} end
function getCore() return {getGameMode=function() return "Sandbox" end} end
function getServerIP() return "127.0.0.1" end
function getServerPort() return 16261 end
function getServerName() return "component-test" end
function getFileReader(path)
    if not files[path] then return nil end
    local done = false
    return {readLine=function() if not done then done=true;return files[path] end end,close=function() end}
end
function getFileWriter(path)
    return {write=function(_,value) files[path]=value end,close=function() end}
end
function require(name)
    if name == "Wayman/WaymanEntityDescriptor" or name == "Wayman/WaymanLocalDraft" then return actualRequire(name) end
    return true
end
ISCollapsableWindowJoypad = {derive=function() nodeClass={};nodeClass.__index=nodeClass;return nodeClass end,
    new=function(self) return setmetatable({setWantKeyEvents=function() end},self) end}
RailroaderWaymanGraphEditor = {open=function() return {syncLocalState=function() end} end}
RailroaderWaymanWorldHighlights = {colors={},clearGroup=function() end}
WaymanLocalization = {ui=function(key) return key end}
dofile(luaRoot .. "/client/Wayman/WaymanNodeEditor.lua")
local Drafts = RailroaderWaymanLocalDraft
local function editor(index)
    local node = nodeClass:new(0,0,700,500,Descriptor.getInstance(entry.master,nil,index),0)
    node.statusLabel={setName=function() end}
    node.refreshAll=function() end
    node.refreshBlockList=function() end
    node.refreshHighlights=function() end
    return node
end
local node = editor(2)
node.blocks[1].nodes[1].x, node.blocks[1].isDefault = 21, false
node:setDirty()
assert(node.localState.nodeDrafts[second.id] and not node.localState.nodeDrafts[first.id])
node:onApply()
assert(node.localState.geometry[second.id].modData.at.x == 21)
assert(entry.data.railroaderWayman.components[2].at.x == 20, "local editor mutated physical modData")
assert(editor(2).blocks[1].nodes[1].x == 21 and editor(1).blocks[1].nodes[1].x ~= 21)
node:onReload()
assert(node.blocks[1].nodes[1].x == 20 and node.instance.data.id == second.id)
local a, b = Descriptor.getInstance(entry.master,nil,1), Descriptor.getInstance(entry.master,nil,2)
a.data,b.data = {},{}
assert(Drafts.nodeKey(a) ~= Drafts.nodeKey(b), "unregistered component journals collide")

-- MP recovery carries the component selection and tolerates acknowledgement
-- arriving before physical modData. A later component may be recovered first.
local missed, missedData = object("SymmetricalCompactThreeWayTurnout","W",{x=4000,y=4000,z=0})
local recovery = nodeClass:new(0,0,700,500,Descriptor.getInstance(missed,nil,2),0)
recovery.statusLabel={setName=function() end}
recovery.refreshAll=function() end
local request
function getTimestampMs() return 1234 end
function sendClientCommand(_,_,command,args)
    assert(command == "updateRailEntity")
    request = args
end
client = true
recovery:onApply()
assert(request and request.componentIndex == 2 and missedData.railroaderWayman == nil)
client, server = false, true
Events.OnClientCommand.fire("RailroaderWayman","updateRailEntity",nil,request)
local reply = replies[#replies]
assert(reply.command == "railEntityUpdated" and reply.args.ok)
local recoveredId = reply.args.id
assert(missedData.railroaderWayman.components[2].id == recoveredId)
local received = reload(missedData.railroaderWayman)
assert(received.components[2].id == recoveredId, "partial recovery lost its array position")
missedData.railroaderWayman = nil
client, server = true, false
recovery:onSaveResult(true,recoveredId)
assert(recovery.instance.data.id == recoveredId)
missedData.railroaderWayman = received
recovery:onReload()
assert(recovery.instance.data.id == recoveredId)
client, server = false, true
construct(missed)
assert(#missedData.railroaderWayman.components == 3
    and missedData.railroaderWayman.components[2].id == recoveredId)
runtime.OnRemove(missed)
assert(not block(recoveredId,"at"), "partial recovery leaked a component on removal")

-- A client can neither create identities nor remove the server's components.
client = true
local untouched = json(world)
construct(entry.master)
assert(not runtime.SaveGeometry(entry.master,{},nil,1))
runtime.OnRemove(entry.master)
assert(untouched == json(world))
client, server = false, true
runtime.OnRemove(entry.master)
for _, component in ipairs(entry.data.railroaderWayman.components) do
    assert(not block(component.id,"at") and not switch(component.id))
end
assert(block("turn_1","nodes") and block("turnout_25","at"), "removal affected another physical entity")
local exported = reload(world)
assert(#exported.switches == #world.switches and #exported.availableNodes == #world.availableNodes)
assert(GD.isEmpty(world.edges), "component editing created connections")
print = originalPrint
print("PASS: all eight compound faces register three independent server-owned turnouts without connections")
print("PASS: stable serialized identities, relative geometry, mixed types and coincident coordinates")
print("PASS: component selection, isolated node drafts and coordinated updates preserve sibling state")
print("PASS: MP recovery selects the component and handles acknowledgement before physical modData")
print("PASS: authority, RR rejection, export and complete removal of physical component registrations")
