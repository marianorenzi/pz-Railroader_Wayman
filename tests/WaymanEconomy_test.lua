-- Economic lifecycle integration with the real authoritative entity runtime.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path = luaRoot .. "/shared/?.lua;" .. package.path
package.preload["Moveables/ISMoveableSpriteProps"] = function()
    ISMoveableSpriteProps = {scrapObject=function() return "vanilla" end}
end
local client, server, world = false, true, {}
function isClient() return client end
function isServer() return server end
function getDebug() return true end
function instanceof(object, class) return object.class == class end
ModData = {getOrCreate = function(key) world[key] = world[key] or {}; return world[key] end}
local events = {}
local function event(name)
    local handlers = {}
    events[name] = function(...) for _, h in ipairs(handlers) do h(...) end end
    return {Add=function(h) handlers[#handlers+1] = h end}
end
Events = {OnTick=event("tick"), OnObjectAboutToBeRemoved=event("removed"),
    OnClientCommand=event("command"), OnRailroaderRegisterTrack=event("restore"),
    LoadGridsquare=event("loaded")}
RR = {API = {edges=function() return {} end, registerTrack=function() return true end,
    unregisterTrack=function() return true end}}
ArrayList = {new=function()
    return {entries={}, size=function(self) return #self.entries end,
        get=function(self,i) return self.entries[i+1] end,
        add=function(self,o) self.entries[#self.entries+1]=o end}
end}
ItemTag = {HAMMER="hammer"}
local protected = false
SafeHouse = {isSafeHouse=function(square)
    if protected and square.protected then return {playerAllowed=function() return false end} end
end}
local hammer, dead, cheat = true, false, false
local px, py, pz = 100.5, 100.5, 0
local character = {getX=function() return px end,getY=function() return py end,getZ=function() return pz end,
    isDead=function() return dead end, isBuildCheat=function() return cheat end,
    getInventory=function() return {containsTagEval=function(_,tag,predicate)
        assert(tag==ItemTag.HAMMER)
        return hammer and predicate({isBroken=function() return false end})
    end} end}
local roll = 0
function ZombRand(max) assert(max==100); return roll end
local drops, dropSquares = {}, {}
local removalTargets = {}
local removalMode, beforeRemoval, lastRemovedMaster = "remove", nil, nil
local function square(x,y)
    local sq = {x=x,y=y,objects={}}
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return 0 end
    function sq:getObjects() local list=ArrayList.new();list.entries=self.objects;return list end
    function sq:AddWorldInventoryItem(fullType)
        assert(lastRemovedMaster and lastRemovedMaster.index==-1, "recovery happened before master removal")
        drops[fullType]=(drops[fullType] or 0)+1
        dropSquares[#dropSquares+1]=self
    end
    -- Match Build 42: the default safe removal removes all multi-square parts.
    function sq:transmitRemoveItemFromSquare(object)
        assert(object.index >= 0, "duplicate physical removal")
        removalTargets[#removalTargets+1]=object
        if removalMode=="error" then error("native removal failed") end
        if removalMode=="refuse" then return -1 end
        if beforeRemoval then beforeRemoval(object) end
        local master=object.parts[1]
        for _,part in ipairs(object.parts) do
            if part.index>=0 then events.removed(part);part.index=-1 end
        end
        lastRemovedMaster=master
        return 0
    end
    return sq
end

-- Stand-ins for currently loaded native CraftRecipe/InputScript objects.
local recipes = {}
local function setRecipe(name, materials)
    local inputs = ArrayList.new()
    inputs:add({isKeep=function() return true end,
        getPossibleInputItems=function() error("kept tools must not be recovered") end})
    for _,entry in ipairs(materials) do
        local choices = ArrayList.new()
        for _,fullType in ipairs(entry.items or {entry.item}) do
            choices:add({getFullName=function() return fullType end})
        end
        inputs:add({isKeep=function() return false end,
            getPossibleInputItems=function() return choices end,
            getIntAmount=function(_,fullType) assert(fullType==choices:get(0):getFullName());return entry.qty end})
    end
    recipes[name] = {getInputs=function() return inputs end}
end
setRecipe("TrackSegment",{{item="Base.Plank",qty=1},{item="Base.Nails",qty=1}})
setRecipe("SymmetricalThreeWayTurnout",{{item="Base.Plank",qty=3},{item="Base.Nails",qty=3}})
setRecipe("Left45DegTurn",{{item="Base.Plank",qty=4},{item="Base.RailroadSpike",qty=2},{item="Base.MetalBar",qty=1}})
setRecipe("Left45DegTurnout",{{item="Base.Plank",qty=6},{item="Base.RailroadSpike",qty=4},{item="Base.MetalBar",qty=2}})

local function physical(name, count, module)
    local objects, fullyLoaded = {}, true
    local config = {isMultiSquareMaster=function() return true end,
        isMultiSquareFullyLoaded=function() return fullyLoaded end,
        getObjectInfo=function() return {getRecipe=function() return {
            getCraftRecipe=function() return recipes[name] end} end} end,
        getAllMultiSquareObjects=function(_,list)
            if not fullyLoaded then return false end
            for _, o in ipairs(objects) do list:add(o) end
            return true
        end,
        getFaceInfo=function() return {getFaceName=function() return "N" end,
            getMasterX=function() return 0 end,getMasterY=function() return 0 end,getMasterZ=function() return 0 end} end}
    for i=1,count or 3 do
        local sq = square(100+(i-1)*5,100)
        local o={data={},index=0,square=sq,disabled=false,parts=objects}
        function o:getMasterObject() return objects[1] end
        function o:getSquare() return self.square end
        function o:getEntityScript() return {getName=function() return name end,
            getModule=function() return {getName=function() return module or "RailroaderWayman" end} end} end
        function o:getSpriteConfig() return config end
        function o:getObjectIndex() return self.index end
        function o:getModData() return self.data end
        function o:getX() return sq.x end
        function o:getY() return sq.y end
        function o:getZ() return 0 end
        function o:transmitModData() end
            sq.objects={o};objects[i]=o
    end
    return objects, function(value) fullyLoaded=value end
end

dofile(luaRoot.."/server/Wayman/WaymanEntityRuntime.lua")
require "Wayman/WaymanEconomy"
local E, R, GD = RailroaderWaymanEconomy, RailroaderWaymanEntityRuntime, RailroaderWaymanGraphData
local function build(name)
    local parts, setLoaded=physical(name)
    R.OnCreate({thumpable=parts[1],character=character,facing="N"})
    events.tick()
    assert(world.RailroaderWayman_Economy==nil, "construction created economic history")
    assert(parts[1].data.railroaderWaymanEconomy==nil, "construction saved economic metadata")
    return parts, setLoaded
end

local parts, setLoaded = build("Left45DegTurn")
local owner=parts[1].data.railroaderWayman.id
assert(owner and #world.RailroaderWayman_World.availableNodes==1)
R.OnCreate({thumpable=parts[1],character=character,facing="N"});events.tick()
assert(#world.RailroaderWayman_World.availableNodes==1, "replayed creation duplicated graph data")
assert(R.SaveGeometry(parts[1],{nodes={{x=1,y=1,z=0}}},"N"))

-- Unloaded pieces cannot be dismantled; loading does not retire or reward them.
setLoaded(false)
assert(not E.dismantle(character,parts[1],75))
assert(not parts[1].data.railroaderWaymanRemoved and next(drops)==nil)
parts[1].data=assert(GD.worldDataFromJSON(assert(GD.worldDataToJSON(parts[1].data))))
setLoaded(true);events.loaded(parts[1].square)
assert(not parts[1].data.railroaderWaymanRemoved)

-- Changing the loaded recipe changes recovery for an already built piece.
setRecipe("Left45DegTurn",{{item="Base.Plank",qty=9},{item="Base.Nails",qty=1}})
px=110.5 -- clicked slave is adjacent; master is ten tiles away
assert(E.dismantle(character,parts[3],75))
assert(parts[1].data.railroaderWaymanRemoved==nil, "dismantling wrote persistent state")
assert(drops["Base.Plank"]==9 and drops["Base.Nails"]==1)
assert(drops["Base.RailroadSpike"]==nil and drops["Base.MetalBar"]==nil)
assert(#world.RailroaderWayman_World.availableNodes==0)
for _,p in ipairs(parts) do assert(p.index==-1) end
assert(not E.dismantle(character,parts[2],75), "second player received another recovery")
assert(removalTargets[#removalTargets]==parts[1], "dismantling did not target the master")
assert(#removalTargets==1, "dismantling issued per-tile native removals")
for _,sq in ipairs(dropSquares) do assert(sq==parts[3].square, "material was not dropped on the clicked tile") end
assert(not E.dismantle(character,parts[1],75), "stale master request received another recovery")

-- Recipe amounts already include multipliers. Tools are never refunded.
for _,case in ipairs({{"TrackSegment",1,1},{"SymmetricalThreeWayTurnout",3,3},{"Left45DegTurnout",6,0}}) do
    px=100.5;drops={};roll=0
    local p=build(case[1])
    assert(E.dismantle(character,p[1],75))
    assert(drops["Base.Plank"]==case[2])
    assert((drops["Base.Nails"] or 0)==case[3])
    assert(drops["Base.Hammer"]==nil)
end
local none=build("TrackSegment")
drops={};roll=99
assert(E.dismantle(character,none[1],75) and next(drops)==nil)
-- Independent rolls permit partial recovery as well as full and zero recovery.
setRecipe("TrackSegment",{{item="Base.Plank",qty=4}})
local rollIndex=0
function ZombRand() rollIndex=rollIndex+1;return rollIndex%2==0 and 99 or 0 end
local partial=build("TrackSegment")
drops={};assert(E.dismantle(character,partial[1],75));assert(drops["Base.Plank"]==2)

-- Selectors/alternatives return one allowed type, not every possible choice.
setRecipe("TrackSegment",{{items={"Base.Plank","Base.LargePlank"},qty=2},{item="Base.Plank",qty=1}})
local alternatives=E.materials(recipes.TrackSegment)
assert(alternatives["Base.Plank"]==3 and alternatives["Base.LargePlank"]==nil)
setRecipe("TrackSegment",{{item="Base.Plank",qty=1},{item="Base.Nails",qty=1}})
function ZombRand() return 0 end
-- The same current-recipe rule applies to old, cheat-built and externally placed
-- pieces. No proof of prior expense or stored recipe is required.
for _,kind in ipairs({"legacy","cheat","external"}) do
    drops={};cheat=kind=="cheat"
    local p=physical("TrackSegment")
    if kind=="cheat" then R.OnCreate({thumpable=p[1],character=character,facing="N"});events.tick() end
    assert(E.dismantle(character,p[1],75))
    assert(drops["Base.Plank"]==1 and drops["Base.Nails"]==1)
end
cheat=false

-- Ordinary native destruction never awards recovery; queued actions see the missing master.
drops={}
local destroyed=build("TrackSegment")
destroyed[2].square:transmitRemoveItemFromSquare(destroyed[2])
assert(destroyed[1].index==-1 and next(drops)==nil)
assert(not E.dismantle(character,destroyed[1],75))

local target=build("TrackSegment")
protected=true;target[3].square.protected=true
assert(not E.dismantle(character,target[1],75));protected=false
-- Fail before removing any parts if a recipe cannot resolve a material.
local validRecipe=recipes.TrackSegment
setRecipe("TrackSegment",{{items={},qty=1}})
assert(not E.dismantle(character,target[1],75))
assert(target[1].index==0 and not target[1].data.railroaderWaymanRemoved)
recipes.TrackSegment=validRecipe
client=true
assert(not E.dismantle(character,target[1],75))
assert(not target[1].data.railroaderWaymanRemoved)
client=false;server=false -- same physical operation in SP
assert(E.dismantle(character,target[1],75))
-- Refused/failed native removals award nothing and release the temporary guard.
for _,mode in ipairs({"refuse","error"}) do
    local failed=physical("TrackSegment")
    drops={};removalMode=mode
    assert(not E.dismantle(character,failed[1],75))
    assert(failed[1].index==0 and next(drops)==nil and next(failed[1].data)==nil)
    removalMode="remove"
    assert(E.dismantle(character,failed[1],75))
    assert(drops["Base.Plank"]==1 and drops["Base.Nails"]==1)
end
-- Native OnObjectAboutToBeRemoved callbacks run before the object disappears.
-- A nested attempt there must not trigger a second removal/recovery.
local nested=physical("TrackSegment")
drops={}
beforeRemoval=function(object)
    assert(object==nested[1] and object.index==0)
    local ok,reason=E.dismantle(character,nested[3],75)
    assert(not ok and reason=="dismantling in progress")
    assert(next(drops)==nil, "materials awarded from a before-removal callback")
end
px=110.5
assert(E.dismantle(character,nested[3],75))
px=100.5
beforeRemoval=nil
assert(drops["Base.Plank"]==1 and drops["Base.Nails"]==1)
assert(next(nested[1].data)==nil, "dismantling modified master modData")
local foreign=physical("TrackSegment",1,"OtherMod")
assert(not E.describe(foreign[1]) and not E.dismantle(character,foreign[1],75))
assert(world.RailroaderWayman_Economy==nil, "dismantling created a ledger")
print("PASS: recovery from the current native recipe, including recipe changes and legacy/cheat pieces")
print("PASS: kept tools, multiplied amounts, alternatives, full/partial/zero recovery and graph withdrawal")
print("PASS: native whole-entity removal, ground recovery after master removal, chunks and duplicate requests")
