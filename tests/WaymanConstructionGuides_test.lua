-- Actual cursor adapter and highlight renderer; installed vanilla render when
-- available. Engine drawing, world data and input APIs are supplied by the test.
next=nil
local root=debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/") or "."
local luaRoot=root.."/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path=luaRoot.."/shared/?.lua;"..luaRoot.."/client/?.lua;"..package.path
function isServer() return false end
function getText(key,distance)
    if key=="UI_Wayman_DistanceTiles" then return distance.." tiles" end
    if key=="UI_Wayman_NodeFacingMismatch" then return "Sentido incompatible (requiere "..distance..")" end
    if key=="UI_Wayman_NodeInsideEdge" then return "No es un extremo del edge" end
    if key=="UI_Wayman_NodeNoFacing" then return "Sin sentido de conexión declarado" end
    if key=="UI_Wayman_NodeFacingUsed" then return "Sentido ya ocupado por el edge ("..distance..")" end
    assert(key=="UI_Wayman_AvailableNoEdge");return "Disponible / sin edge"
end
local function event()
    local handlers={}
    return {Add=function(fn) handlers[#handlers+1]=fn end,
        fire=function(...) for _,fn in ipairs(handlers) do fn(...) end end}
end
Events={OnGameStart=event(),OnTick=event(),OnDisconnect=event()}
-- The compatible target is offscreen and beyond the former 256-tile search limit.
local world={revision=0,edges={edge_1={{blockId="turnout_1:at",nodes={{x=106,y=1105,z=0}},firstFacing="N"}}}}
ModData={get=function() return world end}
local drag={}
function getCell() return {getDrag=function(_,p) return drag[p] end} end
local class,ui={}
class.__index=class
ISPanel={derive=function() return class end,new=function()
    ui=setmetatable({initialise=function() end,addToUIManager=function() end},class);return ui
end}
package.preload["ISUI/ISPanel"]=function() return ISPanel end
local native=os.getenv("PZ_LUA_ROOT")
require "Wayman/WaymanGraphData"
require "Wayman/WaymanConnections"
local C=RailroaderWaymanConnections
local builds,queries=0,0
local build,find=C.index,C.find
C.index=function(...) builds=builds+1;return build(...) end
C.find=function(...) queries=queries+1;return find(...) end
-- Client scripts load before the vanilla server/BuildingObjects cursor.
-- Do not preload that dependency: doing so hid the real save-load failure.
assert(ISBuildIsoEntity==nil)
require "Wayman/WaymanConstructionGuides"
local G,H=RailroaderWaymanConstructionGuides,RailroaderWaymanWorldHighlights
assert(ISBuildIsoEntity==nil,"client loading tried to initialize the server cursor")
if native then
    ISBuildingObject={derive=function(_,name) local c={Type=name};c.__index=c;return c end}
    dofile(native.."/server/BuildingObjects/ISBuildIsoEntity.lua")
else
    ISBuildIsoEntity={render=function(self,_,_,_,sq) self:isValid(sq) end}
end
local vanillaRender=ISBuildIsoEntity.render
Events.OnGameStart.fire()
local hookedRender=ISBuildIsoEntity.render
assert(hookedRender~=vanillaRender,"game start did not install the cursor hook")
Events.OnGameStart.fire()
assert(ISBuildIsoEntity.render==hookedRender,"game start wrapped the cursor twice")
local entries,texts={},{}
function addAreaHighlightForPlayer(player,x,y,_,_,z,r,g,b)
    entries[#entries+1]={player=player,x=x,y=y,z=z,r=r,g=g,b=b}
end
UIFont={Small=1}
IsoUtils={XToScreen=function(x,y) return (x-y)*4+1000 end,YToScreen=function(x,y,z) return (x+y)*2-z*100 end}
IsoCamera={getOffX=function() return 0 end,getOffY=function() return 0 end,
    getScreenLeft=function() return 0 end,getScreenTop=function() return 0 end,
    getScreenWidth=function() return 3000 end,getScreenHeight=function() return 600 end}
function getCore() return {getZoom=function() return 1 end} end
function getTextManager() return {
    MeasureStringX=function(_,_,s) return #s*6 end,getFontHeight=function() return 14 end,
    DrawString=function(_,_,x,y,text,r)
        if r==1 then texts[#texts+1]={text=text,x=x,y=y} end
    end} end
local visible=false
ISWorldMap_instance={getIsVisible=function() return visible end}
local facing,name,validations="S","Left45DegTurn",0
-- SpriteConfig exposes face names in lowercase, even for `face S` in scripts.
local face={getFaceName=function() return string.lower(facing) end,getWidth=function() return 1 end,
    getHeight=function() return 1 end,getzLayers=function() return 1 end,getTileInfo=function() end}
local character={getPlayerNum=function() return 0 end}
local validity=function() validations=validations+1;return false end
local cursor=setmetatable({character=character,objectInfo={getScript=function() return {getName=function() return name end} end},
    getFace=function() return face end,ensureSquaresExist=function() end,isValid=validity,
    renderFloorGrid=function() end},{__index=ISBuildIsoEntity})
drag[0]=cursor
local function draw()
    entries,texts={},{}
    ui:prerender();ui:render()
end
local function tile(x,y,z)
    local found
    for _, entry in ipairs(entries) do
        if entry.x==x and entry.y==y and entry.z==(z or 0) then
            assert(not found,"construction submitted the same highlighted tile twice")
            found=entry
        end
    end
    return assert(found,"missing highlighted tile at "..x..","..y)
end
local function white(x,y,z)
    local entry=tile(x,y,z)
    assert(entry.r==1 and entry.g==1 and entry.b==1,"node highlight was obscured by a guide")
end
cursor:render(100,100,0,{})
assert(ui,"lowercase cursor facing did not create construction guides")
draw()
assert(#entries==18 and #texts==1 and texts[1].text=="turnout_1:at (edge_1) — 1000 tiles")
white(106,105);white(106,1105)
local labelX,labelY=texts[1].x,texts[1].y
assert(entries[1].x==106 and entries[1].y==106 and entries[1].g==1)
assert(entries[8].y==113 and entries[9].x==105 and entries[9].y==104 and entries[9].r==1)
for _=1,500 do cursor:render(100,100,0,{}) end
assert(builds==1 and queries==2 and validations==501 and cursor.isValid==validity,
    "stationary cursor repeated queries or changed vanilla validity")
visible=true;draw();assert(#entries==0 and #texts==0)
visible=false;draw();assert(#entries==18 and #texts==1)
for _,length in ipairs({5,10}) do
    G.visualLength=length;cursor:render(100,100,0,{});draw()
    assert(#entries==length*2+2 and entries[length].y==105+length)
    white(106,105);white(106,1105)
    assert(texts[1].x==labelX and texts[1].y==labelY,
        "changing guide length moved the label away from the ghost")
end
G.visualLength=8
-- Changing cursor position, face and height must invalidate only the ghost.
cursor:render(101,100,0,{});draw();assert(#texts==0 and entries[1].r==1 and builds==1)
facing="N";cursor:render(100,100,0,{});draw();assert(entries[1].x==102 and entries[1].y==102)
facing="S";cursor:render(100,100,1,{});draw();assert(#texts==0 and entries[1].z==1)
-- Confirmed revision/edge changes refresh the label even when the ghost stays still.
cursor:render(100,100,0,{})
world.edges.edge_2=world.edges.edge_1;world.edges.edge_1=nil;world.revision=1
cursor:render(100,100,0,{});draw()
assert(builds==2 and texts[1].text=="turnout_1:at (edge_2) — 1000 tiles")
world.availableNodes=world.edges.edge_2;world.edges={};world.revision=2
cursor:render(100,100,0,{});draw()
assert(texts[1].text=="turnout_1:at (Disponible / sin edge) — 1000 tiles")
world=assert(RailroaderWaymanGraphData.worldDataFromJSON(assert(RailroaderWaymanGraphData.worldDataToJSON(world))))
cursor:render(100,100,0,{});draw();assert(builds==4 and #texts==1)
-- A near incompatible node blocks the far compatible one.
world.availableNodes[#world.availableNodes+1]={blockId="wall",nodes={{x=106,y=107}},firstFacing="S"}
world.revision=3;cursor:render(100,100,0,{});draw()
assert(#entries==11 and entries[1].r==1 and #texts==1,
    "red guide continued past the first occupied coordinate")
white(106,105);white(106,107)
assert(texts[1].text=="wall (Disponible / sin edge) — 2 tiles — Sentido incompatible (requiere N)")
-- Shorten both colors at nearby cardinal/diagonal nodes, including an adjacent tile.
local wall=world.availableNodes[2]
local diagonal={blockId="diagonal",nodes={{x=105,y=104}}}
world.availableNodes[3]=diagonal
for _,compatible in ipairs({true,false}) do
    wall.firstFacing=compatible and "N" or "S"
    diagonal.firstFacing=compatible and "SE" or "NW"
    world.revision=world.revision+1;cursor:render(100,100,0,{});draw()
    assert(#entries==4,
        "nearby nodes did not stop cardinal and diagonal guides")
    white(106,105);white(106,107);white(105,104)
    assert(#texts==2)
    if compatible then
        assert(texts[1].y==labelY,"truncating the guide moved its label to the target")
        assert(texts[1].text=="wall (Disponible / sin edge) — 2 tiles")
        assert(texts[2].text=="diagonal (Disponible / sin edge) — 1 tiles")
    else
        assert(texts[1].text=="wall (Disponible / sin edge) — 2 tiles — Sentido incompatible (requiere N)")
        assert(texts[2].text=="diagonal (Disponible / sin edge) — 1 tiles — Sentido incompatible (requiere SE)")
    end
    assert((compatible and tile(106,106).g==1)
        or (not compatible and tile(106,106).r==1))
end
-- Correct facing alone is insufficient inside an edge; labels explain the blocker.
table.remove(world.availableNodes,2)
world.edges.edge_blocked={
    {blockId="head",nodes={{x=300,y=1000}}},wall,
    {blockId="tail",nodes={{x=400,y=1000}}},
}
wall.firstFacing="N"
world.revision=world.revision+1;cursor:render(100,100,0,{});draw()
assert(entries[1].r==1 and texts[1].text=="wall (edge_blocked) — 2 tiles — No es un extremo del edge")
world.edges.edge_blocked[2],world.edges.edge_blocked[3]=world.edges.edge_blocked[3],wall
world.revision=world.revision+1;cursor:render(100,100,0,{});draw()
assert(entries[1].g==1 and texts[1].text=="wall (edge_blocked) — 2 tiles")
local previous=world.edges.edge_blocked[2]
previous.nodes[1]={x=106,y=100}
world.revision=world.revision+1;cursor:render(100,100,0,{});draw()
assert(entries[1].r==1 and texts[1].text=="wall (edge_blocked) — 2 tiles — Sentido ya ocupado por el edge (N)")
previous.nodes[1]={x=106,y=120}
world.revision=world.revision+1;cursor:render(100,100,0,{});draw()
assert(entries[1].g==1 and texts[1].text=="wall (edge_blocked) — 2 tiles")
wall.firstFacing=nil
world.revision=world.revision+1;cursor:render(100,100,0,{});draw()
assert(entries[1].r==1 and texts[1].text=="wall (edge_blocked) — 2 tiles — Sin sentido de conexión declarado")
cursor:render(101,100,0,{});draw();assert(#texts==0,"stale blocker label survived without a node")
-- Public RR/addon endpoints use the turnout selector's filter, not saved drafts.
local catalogCalls,nodeCalls=0,0
local externalY=107
RR={API={
    edges=function(net,out)
        assert(net=="main");catalogCalls=catalogCalls+1
        out[1]={id="main"};out[2]={id="other:branch",prefix="other"}
        out[3]={id="wayman:copy",prefix="wayman"}
        return out
    end,
    edgeNodes=function(id,net,out)
        assert(net=="main");nodeCalls=nodeCalls+1
        assert(id~="wayman:copy","guides requested the published Wayman duplicate")
        if id=="main" then
            out[1]={x=300,y=300};out[2]={x=106,y=externalY,name="station",open=false}
        else
            out[1]={x=104,y=103};out[2]={x=500,y=500}
        end
        return out
    end,
}}
world={revision=20}
cursor:render(100,100,0,{});draw()
assert(#texts==2 and texts[1].text=="RR:station (main) — 2 tiles")
assert(texts[2].text=="RR:1 (other:branch) — 2 tiles")
assert(tile(106,106).g==1 and tile(105,104).g==1)
white(106,105);white(106,107);white(104,103)
local builtBefore,queriedBefore=builds,queries
local callsBefore=catalogCalls
for _=1,500 do cursor:render(100,100,0,{}) end
assert(builds==builtBefore and queries==queriedBefore and catalogCalls==callsBefore,
    "stationary render repeated public catalog reads")
for _=1,60 do Events.OnTick.fire() end
cursor:render(100,100,0,{})
assert(catalogCalls==callsBefore+1 and builds==builtBefore and queries==queriedBefore,
    "unchanged external poll invalidated the spatial index")
externalY=109
for _=1,60 do Events.OnTick.fire() end
cursor:render(100,100,0,{});draw()
assert(builds==builtBefore+1 and texts[1].text=="RR:station (main) — 4 tiles")
white(106,109)
RR=nil
for _=1,60 do Events.OnTick.fire() end
cursor:render(100,100,0,{});draw()
assert(#texts==0,"unavailable external catalog retained obsolete targets")
-- All physical ghost nodes are white, even inside a branch without its own exit.
name,facing="WyeTurnout","S"
cursor:render(100,100,0,{});draw()
white(106,105);white(106,104);white(106,103)
-- Coincident component nodes are submitted once; distinct ones all survive.
name,facing="SymmetricalCompactThreeWayTurnout","E"
cursor:render(100,100,0,{});draw()
white(103,105)
assert(#entries==25)
name,facing="SymmetricalThreeWayTurnout","S"
cursor:render(100,100,0,{});draw()
white(102,103);white(113,103);white(109,110)
white(109,109);white(109,107)
-- A target exactly at an exit remains ignored until the geometry stage.
name,facing="Left45DegTurn","S"
world={revision=21,availableNodes={{blockId="coincident",nodes={{x=106,y=105}},firstFacing="N"}}}
cursor:render(100,100,0,{});draw()
assert(#texts==0);white(106,105)
-- Labels at a shared point remain separate and do not overlap.
H.replaceGroup("labels",{},{{x=106,y=125,z=0,text="one"},{x=106,y=125,z=0,text="two"}})
draw();assert(#texts==2 and math.abs(texts[1].y-texts[2].y)>=14)
H.clearGroup("labels")
-- Tool replacement/cancel clears only this feature's group.
H.replaceGroup("other",{{x=1,y=2,z=0}})
drag[0]=nil;Events.OnTick.fire();draw();assert(#entries==1 and #texts==0)
drag[0]=cursor;cursor:render(100,100,0,{})
Events.OnDisconnect.fire();draw();assert(#entries==1 and #texts==0)
name="TrackSegment";cursor:render(100,100,0,{});draw();assert(#entries==1)
print("PASS: vanilla render/validity, cached ghost/index, bounded highlights and ghost labels for offscreen targets")
print("PASS: client load before the vanilla cursor, deferred startup and one-time hook installation")
print("PASS: face/Z/confirmed updates, blockers, label separation, fullscreen map, cancellation and disconnect")
print("PASS: green/red guides stop on nearby cardinal/diagonal nodes, including adjacent nodes")
print("PASS: labels stay at the ghost's guide start when length or target distance changes")
print("PASS: red guide labels identify blockers and explain facing, missing metadata and internal edge nodes")
print("PASS: endpoint guide color and occupied-facing reason update from the runtime edge direction")
print("PASS: white ghost/internal/component nodes and unlimited targets take precedence over guide tiles")
print("PASS: RR/addon endpoint labels, all-direction compatibility and active-only cached public polling")
