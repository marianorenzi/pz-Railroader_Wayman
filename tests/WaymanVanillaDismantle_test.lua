-- Real Build 42 menu, moveable props/definitions and timed action; engine/UI APIs
-- are stubbed. The build-contract test checks the actual generated tile flags.
local native = os.getenv("PZ_LUA_ROOT")
if not native then print("SKIP: set PZ_LUA_ROOT for the installed vanilla Lua files");return end
local source=debug.getinfo(1,"S").source:sub(2)
local root=source:match("^(.*)/tests/") or "."
local shared=root.."/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared"
package.path=shared.."/?.lua;"..native.."/shared/?.lua;"..native.."/client/?.lua;"..package.path
local client, server=false,true
function isClient() return client end
function isServer() return server end
function getDebug() return false end
function getText(key) return key end
function getTexture(name) return name end
function instanceof(o,class) return o and o.classes and o.classes[class] or false end
function string.contains(s,sub) return s:find(sub,1,true)~=nil end
local function enum() return setmetatable({}, {__index=function(_,k) return k end}) end
Perks, ItemTag, IsoFlagType, IsoPropertyType, IsoObjectType=enum(),enum(),enum(),enum(),enum()
PerkFactory={getPerkName=function(k) return k end}
IsoGridSquare={ignoreBlockingSprites={add=function() end}}
IsoThumpable={GetBreakFurnitureSound=function() return "Break" end}
local color={getR=function() return 1 end,getG=function() return 1 end,getB=function() return 1 end}
function getCore() return {getGoodHighlitedColor=function() return color end,getBadHighlitedColor=function() return color end} end
Events=setmetatable({}, {__index=function() return {Add=function() end} end})
local function list(entries)
    return {size=function() return #entries end,get=function(_,i) return entries[i+1] end,
        contains=function(_,o) for _,v in ipairs(entries) do if v==o then return true end end;return false end,
        add=function(_,o) entries[#entries+1]=o end}
end
ArrayList={new=function() return list({}) end}
local tagTypes={HAMMER="Base.Hammer",SAW="Base.Saw",SCREWDRIVER="Base.Screwdriver"}
local manager={FindItem=function(_,name) return {getDisplayName=function() return name end} end,
    getItemsTag=function(_,tag)
        return list({{getFullName=function() return tagTypes[tag] or "Base."..tag end}})
    end}
ScriptManager={instance=manager}
function getScriptManager() return manager end
require "Moveables/ISMoveableDefinitions"
ISMoveableDefinitions.load()
require "Moveables/ISMoveableSpriteProps"
local originalScrap=ISMoveableSpriteProps.scrapObject
local originalCanScrap=ISMoveableSpriteProps.canScrapObject
local originalWalk=ISMoveableSpriteProps.walkToAndEquip
local originalTime=ISMoveableSpriteProps.getScrapActionTime
-- Tooltip drawing is outside this headless test; all selection/tool/action logic
-- below uses the unchanged installed vanilla implementations.
ISMoveableSpriteProps.getInfoPanelDescription=function() return {} end
ISBaseTimedAction={}
function ISBaseTimedAction:derive(name) local c={Type=name};c.__index=c;setmetatable(c,{__index=self});return c end
function ISBaseTimedAction:new(character) return setmetatable({character=character},{__index=self}) end
function ISBaseTimedAction:setActionAnim(anim) self.anim=anim end
function ISBaseTimedAction:setOverrideHandModels() end
function ISBaseTimedAction:stop() self.stopped=true end
package.preload["TimedActions/ISBaseTimedAction"]=function() return ISBaseTimedAction end
require "Moveables/ISMoveablesAction"
local originalComplete=ISMoveablesAction.complete
local originalMenu
require "ISUI/ISDisassembleMenu"
originalMenu=ISDisassembleMenu.createMenu
require "Wayman/WaymanEconomy"
assert(ISDisassembleMenu.createMenu==originalMenu and ISMoveablesAction.complete==originalComplete)
assert(ISMoveableSpriteProps.canScrapObject==originalCanScrap)
assert(ISMoveableSpriteProps.walkToAndEquip==originalWalk and ISMoveableSpriteProps.getScrapActionTime==originalTime)
local props={CanScrap="true",Material="Wood",CustomName="Wayman_TrackSegment"}
local properties={has=function(_,key) return props[key]~=nil end,get=function(_,key) return props[key] end}
local sprite={getName=function() return "railroader_wayman_tracks_01_31" end,getProperties=function() return properties end}
local hasHammer,hasSaw=true,true
local tools={Hammer={getType=function() return "Hammer" end},Saw={getType=function() return "Saw" end}}
local inv={getFirstTypeRecurse=function(_,name)
    if name=="Base.Hammer" and hasHammer then return tools.Hammer end
    if name=="Base.Saw" and hasSaw then return tools.Saw end
end}
local sq,master,slave
local drops,removals,xp={},0,0
sq={getX=function() return 100 end,getY=function() return 100 end,getZ=function() return 0 end,
    isAdjacentTo=function() return true end,isSomethingTo=function() return false end,
    getObjects=function() return list(slave and slave.index>=0 and {slave} or {}) end,
    AddWorldInventoryItem=function(_,item)
        assert(master.index==-1,"materials spawned before master removal")
        drops[item]=(drops[item] or 0)+1
    end,
    transmitRemoveItemFromSquare=function(_,object)
        assert(object==master,"completion did not remove the physical master")
        removals=removals+1;master.index=-1;slave.index=-1
    end}
local character={classes={IsoGameCharacter=true},getPlayerNum=function() return 0 end,
    getInventory=function() return inv end,getPerkLevel=function() return 4 end,
    isMovablesCheat=function() return false end,isTimedActionInstant=function() return false end,
    getSquare=function() return sq end,isSittingOnFurniture=function() return false end,
    getPrimaryHandItem=function() return tools.Hammer end,getSecondaryHandItem=function() return tools.Saw end,
    hasEquippedTag=function(_,tag) return tag==ItemTag.HAMMER end,
    transmitHaloNote=function() end}
local input={isKeep=function() return false end,getIntAmount=function() return 3 end,
    getPossibleInputItems=function() return list({{getFullName=function() return "Base.MetalBar" end}}) end}
local config={getObjectInfo=function() return {getRecipe=function() return {getCraftRecipe=function()
    return {getInputs=function() return list({input}) end} end} end} end,
    getAllMultiSquareObjects=function(_,items) items:add(master);items:add(slave);return true end}
local function object(index)
    return {index=index,classes={IsoThumpable=true},getSprite=function() return sprite end,
        getProperties=function() return properties end,getMasterObject=function() return master end,
        getObjectIndex=function(self) return self.index end,getSquare=function() return sq end,
        getEntityScript=function() return {getName=function() return "TrackSegment" end,
            getModule=function() return {getName=function() return "RailroaderWayman" end} end} end,
        getSpriteConfig=function() return config end,getRenderYOffset=function() return 0 end,
        isObjectNoContainerOrEmpty=function() return true end,isDoor=function() return false end,isDoorFrame=function() return false end,
        isFloor=function() return false end,isWindow=function() return false end,getZ=function() return 0 end,hasProperty=function() return false end,
        isDismantable=function() error("CanScrap tile property must bypass the fallback") end,
        getProperty=function() return nil end,getType=function() return "none" end,
        setHighlightColor=function() end,setHighlighted=function() end}
end
master=object(0);slave=object(1)
SafeHouse={isSafeHouse=function() return nil end}
function ZombRand() return 0 end
function addXp() xp=xp+1 end
SandboxVars={LevelForDismantleXPCutoff=10}
Translator={getMoveableDisplayName=function(name) return name end}
local function context()
    return {options={},player=0,addOption=function(self,label,target,callback,...)
        local o={label=label,target=target,callback=callback,args={...}};self.options[#self.options+1]=o;return o
    end,addSubMenu=function(_,option,sub) option.sub=sub end}
end
ISContextMenu={getNew=context}
ISToolTip={GetFont=function() return 1 end,new=function()
    return {initialise=function() end,setVisible=function() end,setTexture=function() end}
end}
function getTextManager() return {MeasureStringX=function() return 0 end} end
local ctx=context()
ISDisassembleMenu.createMenu({slave},ctx,character)
assert(#ctx.options==1 and ctx.options[1].label=="ContextMenu_Disassemble")
local option=ctx.options[1].sub.options[1]
assert(option and not option.notAvailable and option.label=="Wayman_TrackSegment")
local move=ISMoveableSpriteProps.fromObject(slave)
assert(move:canScrapObject(character).canScrap)
hasSaw=false
assert(not move:canScrapObject(character).canScrap,"vanilla saw requirement was bypassed")
hasSaw=true;hasHammer=false
assert(not move:canScrapObject(character).canScrap,"vanilla hammer requirement was bypassed")
hasHammer=true
local queued,walked,equipped=nil,0,0
ISTimedActionQueue={add=function(action) queued=action end}
luautils={walkAdj=function() walked=walked+1;return true end}
ISWorldObjectContextMenu={equip=function() equipped=equipped+1 end}
ISInventoryPage={OnObjectHighlighted=function() end}
option.callback(option.target,option.args[1])
assert(queued and queued.Type=="ISMoveablesAction" and walked>0 and equipped==2)
assert(queued.maxTime==880,"vanilla duration was replaced")
assert(queued:isValid())
queued:start();assert(queued.anim=="Build","vanilla animation was replaced")
client=true;assert(queued:complete() and removals==0 and next(drops)==nil)
client=false;assert(queued:complete())
assert(removals==1 and drops["Base.MetalBar"]==3 and drops["Base.Plank"]==nil and xp==1)
assert(not queued:isValid(),"stale vanilla action remained valid")
assert(queued:complete() and removals==1 and drops["Base.MetalBar"]==3)
-- Recovery uses the same skill chance returned by native canScrapObject.
master.index=0;slave.index=1;drops={}
local skillChance=move:canScrapObject(character)
local _,chance=move:canScrapObject(character)
assert(chance==57)
function ZombRand() return chance end
assert(queued:complete() and next(drops)==nil)
master.index=0;slave.index=1
function ZombRand() return chance-1 end
assert(queued:complete() and drops["Base.MetalBar"]==3)
-- Non-Wayman objects still take the original native scrap implementation.
local usedNative=false
local foreign=setmetatable({object={getSprite=function() return sprite end,getMasterObject=function() return nil end,getSquare=function() return sq end,
    getEntityScript=function() return {getName=function() return "Chair" end,getModule=function() return {getName=function() return "Base" end} end} end},
    canScrapObject=function() usedNative=true;return {canScrap=false} end,
    transmitPlaySound=function() end,scrapHaloNoteCheck=function() end}, {__index=ISMoveableSpriteProps})
foreign:scrapObject(character);assert(usedNative and originalScrap~=ISMoveableSpriteProps.scrapObject)
print("PASS: installed vanilla Disassemble menu, walking/equipment, tool checks, timed action and animation")
print("PASS: only Wayman completion adapts current-recipe recovery; native cursor/XP, ground drops and MP authority")
