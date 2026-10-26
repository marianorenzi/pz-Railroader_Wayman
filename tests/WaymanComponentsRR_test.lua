-- Real RR integration after the user manually configures a component's legs.
local beta = os.getenv("RAILROADER_LUA_ROOT")
if not beta then print("SKIP: set RAILROADER_LUA_ROOT to test component integration with Railroader"); return end
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path = luaRoot .. "/shared/?.lua;" .. beta .. "/shared/?.lua;" .. package.path
function isClient() return false end
function isServer() return false end
function getDebug() return true end
function save() end
require "Railroader/RR_Routes"
require "Railroader/RR_TrackGraph"
require "Railroader/RR_RealRoutes"
require "Railroader/RR_TrackReg"
require "Railroader/RR_API"
require "Wayman/WaymanEntityGeometry"
local at = RailroaderWaymanEntityGeometry.SymmetricalCompactThreeWayTurnout.W.components[1].at
local origin = {x=1986-at.x,y=6874-at.y}
local diverging = {{x=at.x,y=at.y-20,z=0},{x=at.x-20,y=at.y-40,z=0}}
local world, tick = {}, nil
ModData = {getOrCreate=function() return world end}
Events = {OnTick={Add=function(fn) tick=fn end},OnClientCommand={Add=function() end},
    OnObjectAboutToBeRemoved={Add=function() end},OnRailroaderRegisterTrack={Add=function() end}}
local master, data, square = nil, {}, nil
local info = {getFaceName=function() return "W" end,getMasterX=function() return 0 end,
    getMasterY=function() return 0 end,getMasterZ=function() return 0 end}
master = {getMasterObject=function() end,getModData=function() return data end,
    getSquare=function() return square end,getEntityScript=function()
        return {getName=function() return "SymmetricalCompactThreeWayTurnout" end}
    end,getSpriteConfig=function() return {getFaceInfo=function() return info end,
        isMultiSquareMaster=function() return true end} end,
    getX=function() return origin.x end,getY=function() return origin.y end,getZ=function() return 0 end,
    transmitModData=function() end}
square = {getObjects=function() return {size=function() return 1 end,get=function() return master end} end}
function getCell() return {getGridSquare=function() return square end} end
dofile(luaRoot .. "/server/Wayman/WaymanEntityRuntime.lua")
local runtime, GD = RailroaderWaymanEntityRuntime, RailroaderWaymanGraphData
runtime.OnCreate({thumpable=master}); tick()
local first, second, third = table.unpack(data.railroaderWayman.components)
assert(first.id == "turnout_1" and second.id == "turnout_2" and third.id == "turnout_3")
assert(#world.switches == 3 and GD.isEmpty(world.edges))

-- This explicit fixture represents the user's own node/edge/leg configuration.
assert(runtime.SaveGeometry(master,{divergingNodes=diverging},"W",1))
local draft, remaining = GD.copy(world), {}
draft.edges.branch = {}
for _, block in ipairs(draft.availableNodes) do
    if block.owner == first.id and (block.id == "at" or block.id == "diverge") then
        draft.edges.branch[#draft.edges.branch + 1] = block
    else remaining[#remaining + 1] = block end
end
draft.availableNodes = remaining
for _, logicalSwitch in ipairs(draft.switches) do
    if logicalSwitch.owner == first.id then
        logicalSwitch.legs = {throat={edge="main",toward="end",external=true},
            through={edge="main",toward="start",external=true},diverge={edge="branch",toward="end"}}
    end
end
assert(runtime.ApplyGraphDraft(draft,world.revision))
local overlay = RR.TrackGraph.overlay("main","wayman")
assert(#overlay.switches == 1 and overlay.switches[1].id == "wayman:"..first.id)
assert(#world.switches == 3, "unconfigured sibling switches were discarded")
RR.TrackGraph.setState("main","wayman:"..first.id,"reverse")
assert(runtime.SaveGeometry(master,{divergingNodes=diverging,
    switch={x=at.x-2,y=at.y+1,z=0}},"W",1))
assert(RR.API.switchState("main","wayman:"..first.id) == "reverse")
assert(#world.edges.branch == 2 and world.edges.branch[1].owner == first.id)
assert(data.railroaderWayman.components[2].id == second.id
    and data.railroaderWayman.components[3].id == third.id)
for _, dir in ipairs({1,-1}) do
    assert(RR.TrackGraph.buildThrough("main",{edge="wayman:branch",s=10,dir=dir}))
end
local exported = assert(GD.worldDataFromJSON(assert(GD.worldDataToJSON(world))))
assert(#exported.switches == 3 and exported.edges.branch[2].owner == first.id)
runtime.OnRemove(master)
assert(#world.availableNodes == 0 and #world.switches == 0 and GD.isEmpty(world.edges))
assert(RR.TrackGraph.overlay("main","wayman") == nil)
print("PASS: real RR preserves manually configured component legs, switch state and sibling identities")
print("PASS: relative placement, bidirectional native routes, export and complete physical withdrawal")
