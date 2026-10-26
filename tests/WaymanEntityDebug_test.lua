-- Tests debug opt-in, persistence, unloaded chunks, Export and server isolation.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path = luaRoot .. "/shared/?.lua;" .. package.path
local actualRequire, actualPrint = require, print
local server, client, debugMode = false, false, true
local world, creates, loaded = {}, 0, true
function isServer() return server end
function isClient() return client end
function getDebug() return debugMode end
function getText(key) return key end
ModData = {
    get = function(key) assert(key == "RailroaderWayman_World"); return world end,
    getOrCreate = function(key)
        assert(key == "RailroaderWayman_World")
        creates = creates + 1
        return world
    end,
    transmit = function() assert(world.debug == nil, "server transmitted debug data") end,
}
function require(name)
    if name:sub(1, 5) == "ISUI/" then return true end
    return actualRequire(name)
end
local function event()
    local handlers = {}
    return {
        handlers = handlers,
        Add = function(fn) handlers[#handlers + 1] = fn end,
        Remove = function(fn)
            for i = #handlers, 1, -1 do if handlers[i] == fn then table.remove(handlers, i) end end
        end,
        fire = function(...)
            for _, fn in ipairs(handlers) do fn(...) end
        end,
    }
end
local function boot()
    RailroaderWaymanEntityDebug = nil
    Events = {
        OnFillWorldObjectContextMenu = event(), OnGameStart = event(), LoadGridsquare = event(),
        OnTick = event(), OnRailroaderRegisterTrack = event(),
        OnObjectAboutToBeRemoved = event(), OnClientCommand = event(),
    }
    dofile(luaRoot .. "/client/Wayman/WaymanEntityDebug.lua")
    return RailroaderWaymanEntityDebug
end

server = true
assert(boot() == nil and creates == 0 and next(world) == nil)
assert(#Events.OnFillWorldObjectContextMenu.handlers == 0 and #Events.OnGameStart.handlers == 0)
server, debugMode = false, false
assert(boot() == nil and creates == 0 and next(world) == nil)
assert(#Events.LoadGridsquare.handlers == 0)
debugMode = true
local capture = boot()
assert(not capture.isEnabled() and world.debug == nil)
capture.setEnabled(false)
capture.capture({entityName="ignored",facing="N"}, "turn_1")
assert(creates == 0 and #Events.LoadGridsquare.handlers == 0)

local data = {railroaderWayman={id="turn_1"}}
local square, object
local face = {
    getFaceName=function() return "N" end,
    getMasterX=function() return 1 end, getMasterY=function() return 2 end,
    getMasterZ=function() return 0 end,
}
object = {
    getMasterObject=function() return nil end,
    getSquare=function() return square end,
    getEntityScript=function() return {getName=function() return "Left45DegTurn" end} end,
    getSpriteConfig=function()
        return {getFaceInfo=function() return face end, isMultiSquareMaster=function() return true end}
    end,
    getModData=function() return data end,
    getX=function() return 101 end, getY=function() return 202 end, getZ=function() return 0 end,
    transmitModData=function() end,
}
local child = {getMasterObject=function() return object end}
square = {getObjects=function()
    return {size=function() return 2 end,get=function(_, index) return index == 0 and object or child end}
end}
local chunk = {
    getMinLevel=function() return 0 end,getMaxLevel=function() return 0 end,
    getGridSquare=function(_, x, y) if loaded and x == 0 and y == 0 then return square end end,
}
local map = {getWidthInTiles=function() return 10 end,getChunk=function() return chunk end}
function getNumActivePlayers() return 2 end
function getCell() return {getChunkMap=function() return map end} end
local function context()
    return {
        options={},
        addOption=function(self, label, target, fn)
            local option={label=label,target=target,fn=fn}
            table.insert(self.options,option)
            return option
        end,
        addSubMenu=function(_, option, menu) option.menu=menu end,
        setOptionChecked=function(_, option, checked) option.checked=checked end,
    }
end
ISContextMenu = {getNew=function() return context() end}
local menu = context()
Events.OnFillWorldObjectContextMenu.fire(0,menu,{},false)
local option = menu.options[1].menu.options[1].menu.options[1]
assert(not option.checked and world.debug == nil)
option.fn()
local identities = world.debug.entityValidation.entities
assert(world.debug.entityValidation.enabled and #Events.LoadGridsquare.handlers == 1)
assert(identities.turn_1.entityName == "Left45DegTurn" and identities.turn_1.facing == "N")
capture.setEnabled(true)
assert(#Events.LoadGridsquare.handlers == 1, "capture installed duplicate observers")

local GD = RailroaderWaymanGraphData
world = GD.ensure(assert(GD.worldDataFromJSON(assert(GD.worldDataToJSON(world)))))
loaded = false
capture = boot()
Events.OnGameStart.fire()
assert(capture.isEnabled() and #Events.LoadGridsquare.handlers == 1)
assert(world.debug.entityValidation.entities.turn_1.facing == "N", "unloaded identity was lost")
capture.setEnabled(false)
assert(#Events.LoadGridsquare.handlers == 0 and world.debug.entityValidation.entities.turn_1)
capture.capture({entityName="changed",facing="S"},"turn_1")
assert(world.debug.entityValidation.entities.turn_1.facing == "N")
capture.setEnabled(true)

-- Execute the actual Export callback; the invalid/unsaved draft must still export.
local windowClass
ISCollapsableWindowJoypad = {derive=function()
    windowClass = {}; windowClass.__index = windowClass; return windowClass
end}
RailroaderWaymanGraphDisplay = {refresh=function() end}
WaymanLocalization = {ui=function(key) return key end}
function require(name)
    if name == "Wayman/WaymanGraphData" or name == "Wayman/WaymanRRGraph" or name == "Wayman/WaymanConnections"
        or name == "Wayman/WaymanEntityDescriptor" then return actualRequire(name) end
    return true
end
dofile(luaRoot .. "/client/Wayman/WaymanGraphEditor.lua")
world.revision = 4
local editor = setmetatable({draft=GD.ensure({edges={unsaved={
    {owner="turn_1",blockId="turn_1:nodes",nodes={{x=1,y=2},{x=3,y=7}}},
}}}),baseRevision=2,statusLabel={setName=function() end}},windowClass)
local exported
function print(line)
    local json = line:match("^%[RailroaderWayman%] WORLD_DATA_JSON (.*)$")
    if json then exported=assert(GD.worldDataFromJSON(json)) end
end
editor:onExport()
assert(exported.edges.unsaved and exported.debug.entityValidation.entities.turn_1.entityName == "Left45DegTurn")
assert(exported.export.source == "draft" and exported.export.baseRevision == 2 and exported.export.confirmedRevision == 4)
assert(editor.draft.debug == nil and world.edges.unsaved == nil)
capture.setEnabled(false)
editor:onExport()
assert(exported.debug == nil and exported.export == nil and exported.edges.unsaved == nil)
assert(world.debug.entityValidation.entities.turn_1, "normal Export modified stored metadata")
debugMode = false
capture.setEnabled(true)
assert(not capture.isEnabled() and #Events.LoadGridsquare.handlers == 0)

-- MP capture stays in memory; outgoing graph drafts never carry debug fields.
debugMode, client, loaded, world, creates = true, true, true, GD.ensure({}), 0
capture = boot()
capture.setEnabled(true)
assert(world.debug == nil and creates == 0)
assert(capture.export(editor.draft,2,world).debug.entityValidation.entities.turn_1.facing == "N")
local validateDraft = GD.validateDraft
GD.validateDraft = function() return {} end
RR = {API={edges=function() return {} end}}
function getSpecificPlayer() return {} end
function getPlayer() return {} end
local sent
function sendClientCommand(_,module,command,args)
    assert(module == "RailroaderWayman" and command == "applyGraph")
    sent = args
end
editor.draft.debug = {entityValidation={enabled=true,entities={}}}
editor:onAccept()
assert(sent and sent.draft.debug == nil and editor.draft.debug ~= nil and world.debug == nil)
GD.validateDraft = validateDraft

-- Capture follows successful SP runtime commits, and remains absent on a server.
client, loaded, world = false, false, GD.ensure({})
capture = boot()
capture.setEnabled(true)
dofile(luaRoot .. "/server/Wayman/WaymanEntityRuntime.lua")
local runtime = RailroaderWaymanEntityRuntime
assert(runtime.SaveGeometry(object,{},"N"))
local owner = data.railroaderWayman.id
assert(world.debug.entityValidation.entities[owner].entityName == "Left45DegTurn")
world.debug.entityValidation.entities[owner] = nil
runtime.OnCreate({thumpable=object,facing="N"})
Events.OnTick.fire()
assert(world.debug.entityValidation.entities[owner].facing == "N", "existing owner was not captured")
runtime.OnRemove(object)
assert(world.debug.entityValidation.entities[owner] == nil)
server, world = true, GD.ensure({})
capture.capture = function() error("server called identity capture") end
capture.remove = function() error("server called debug removal") end
assert(runtime.SaveGeometry(object,{},"N"))
runtime.OnRemove(object)
assert(world.debug == nil)
print = actualPrint
print("PASS: opt-in context menu, SP persistence, unloaded chunks and debug-disabled isolation")
print("PASS: Export includes draft identities/revisions without changing the draft or saved graph")
print("PASS: runtime identity lifecycle, dedicated-server exclusion and local-only MP diagnostics")
