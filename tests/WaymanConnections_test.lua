-- Geometry, first-wall search, ties and persisted canonical metadata.
next = nil
local root = debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/") or "."
package.path = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared/?.lua;" .. package.path
require "Wayman/WaymanGraphData"
require "Wayman/WaymanConnections"
require "Wayman/WaymanEntityGeometry"
local C, GD = RailroaderWaymanConnections, RailroaderWaymanGraphData
local origin = {x=100,y=100,z=0}
local function block(id,x,y,facing,z)
    return {blockId=id,owner=id,id="nodes",nodes={{x=x,y=y,z=z or 0}},firstFacing=facing}
end
local function find(blocks,facing,edges,excluded)
    return C.find(C.index({availableNodes=blocks,edges=edges or {}}),origin,facing,excluded)
end
for facing,d in pairs(C.directions) do
    local x,y = 100+d[1]*1000,100+d[2]*1000
    local target = block("target",x,y,d[3])
    assert(find({target},facing).nodeId=="target")
    assert(not find({block("back",100-d[1]*2,100-d[2]*2,d[3])},facing))
    assert(not find({block("height",x,y,d[3],1)},facing))
    assert(not find({block("off",x+(d[2]~=0 and 1 or 0),y+(d[2]==0 and 1 or 0),d[3])},facing))
    local wall = block("wall",100+d[1]*2,100+d[2]*2,facing)
    local found, point, blocked, reason = find({wall,target},facing)
    assert(not found and point.x==wall.nodes[1].x,"search went through an incompatible wall")
    assert(blocked.nodeId=="wall" and reason=="UI_Wayman_NodeFacingMismatch")
    wall.firstFacing=nil
    assert(not find({wall,target},facing),"missing facing was transparent")
    local compatible = block("compatible",wall.nodes[1].x,wall.nodes[1].y,d[3])
    assert(find({wall,compatible,target},facing).nodeId=="compatible")
    assert(find({compatible,wall,target},facing).nodeId=="compatible")
    -- Tie resolution uses identity, never available/edge membership or input order.
    local a,b = block("a",x,y,d[3]),block("b",x,y,d[3])
    assert(find({b},facing,{edge_1={a}}).nodeId=="a")
    assert(find({a},facing,{edge_1={b}}).nodeId=="a")
    a.firstFacing,b.firstFacing=facing,facing
    local _,_,blockedA=find({b},facing,{edge_1={a}})
    local _,_,blockedB=find({a},facing,{edge_1={b}})
    assert(blockedA.nodeId=="a" and blockedB.nodeId=="a","blocker label depends on index order")
    a.physicalId,b.physicalId="self","self"
    assert(find({a,b,target},facing,nil,"self").nodeId=="target")
    -- External endpoints accept every approach, regardless of open/facing/edge use.
    local external={nodeId="RR:1",nodeIndex=1,edgeId="main",external=true,
        x=x,y=y,z=0,firstFacing=facing,usedFacing=d[3]}
    assert(C.find(C.index({}, {external}),origin,facing)==external)
    local closer=block("wall",100+d[1]*2,100+d[2]*2,facing)
    local hit,_,node=C.find(C.index({availableNodes={closer}},{external}),origin,facing)
    assert(not hit and node.nodeId=="wall","external target bypassed a closer blocker")
    local other={nodeId="RR:1",nodeIndex=1,edgeId="addon:edge",external=true,x=x,y=y,z=0}
    assert(C.find(C.index({},{external,other}),origin,facing).edgeId=="addon:edge")
    assert(C.find(C.index({},{other,external}),origin,facing).edgeId=="addon:edge")
end

-- Edge endpoints follow block order/inversion; physical facing associations stay fixed.
local head={blockId="head",nodes={{x=10,y=0},{x=20,y=0}},firstFacing="N",lastFacing="N"}
local middle=block("middle",30,0,"N")
local tail={blockId="tail",nodes={{x=40,y=0},{x=50,y=0}},firstFacing="N",lastFacing="N"}
local edgeWorld={edges={edge_1={head,middle,tail}}}
for _,inverted in ipairs({false,true}) do
    head.invertNodes,tail.invertNodes=inverted,inverted
    local eligible=inverted and {[20]=true,[40]=true} or {[10]=true,[50]=true}
    local indexed=C.index(edgeWorld)
    for _,x in ipairs({10,20,30,40,50}) do
        local target,point,node,reason=C.find(indexed,{x=x,y=-1,z=0},"S")
        assert(point.x==x and node.x==x)
        assert((target~=nil)==(eligible[x]==true),"internal edge node accepted or endpoint rejected")
        assert(reason==(not eligible[x] and "UI_Wayman_NodeInsideEdge" or nil))
    end
end
edgeWorld.availableNodes={block("available",30,0,"N")}
assert(C.find(C.index(edgeWorld),{x=30,y=-1,z=0},"S").nodeId=="available",
    "internal edge node hid a compatible available node at the same point")

-- Left45DegTurn:S exposes S/NW at one node. An edge going NW consumes only NW.
local turnGeometry=RailroaderWaymanEntityGeometry.Left45DegTurn.S
local turn={blockId="turn_1:nodes",id="nodes",origin=origin,nodes=GD.copy(turnGeometry.nodes)}
C.decorate(turn,turnGeometry,"physical_turn")
local northwest=block("northwest",96,95,"SE")
local duplicate=block("z_duplicate",106,105,nil)
local function checkTurn(blocks,freeFacing,usedFacing)
    local snapshot={edges={edge_1=blocks}}
    local before=assert(GD.worldDataToJSON(snapshot))
    local indexed=C.index(snapshot)
    local approaches={S={{x=106,y=110,z=0},"N"},NW={{x=101,y=100,z=0},"SE"}}
    local free,used=approaches[freeFacing],approaches[usedFacing]
    assert(C.find(indexed,free[1],free[2]).nodeId==turn.blockId)
    local target,_,node,reason=C.find(indexed,used[1],used[2])
    assert(not target and node.nodeId==turn.blockId and reason=="UI_Wayman_NodeFacingUsed",
        "edge endpoint accepted a facing already occupied by that edge")
    assert(GD.worldDataToJSON(snapshot)==before,"index persisted runtime facing usage")
end
for _,inverted in ipairs({false,true}) do
    turn.invertNodes=inverted
    checkTurn({turn,northwest},"S","NW")
    checkTurn({northwest,turn},"S","NW")
    checkTurn({turn,duplicate,northwest},"S","NW")
    checkTurn({northwest,duplicate,turn},"S","NW")
end
checkTurn({turn,block("south",106,115,"N")},"NW","S")
local availableTurn=C.index({availableNodes={turn}})
assert(C.find(availableTurn,{x=106,y=110,z=0},"N"))
assert(C.find(availableTurn,{x=101,y=100,z=0},"SE"))

local geometry = {nodesFacing="N,SE",nodes={{x=0,y=0},{x=1,y=1},{x=2,y=2}}}
local exits = C.exits(geometry,origin)
assert(#exits==2 and exits[1].x==100 and exits[1].facing=="N"
    and exits[2].x==102 and exits[2].facing=="SE")
local canonical = {blockId="turn_1:nodes",owner="turn_1",id="nodes",
    origin=origin,nodes=geometry.nodes,invertNodes=true}
C.decorate(canonical,geometry,"physical")
local ix = C.index({availableNodes={canonical}})
assert(C.find(ix,{x=100,y=95,z=0},"S").nodeIndex==1)
assert(C.find(ix,{x=105,y=105,z=0},"NW").nodeIndex==3)
assert(not C.find(ix,{x=101,y=95,z=0},"S"),"intermediate inherited an exit")
local singleton = C.exits({nodesFacing="S,NW",nodes={{x=0,y=0}}},origin)
assert(#singleton==2 and singleton[1].x==singleton[2].x and singleton[1].y==singleton[2].y)

local turnout = {at={x=0,y=0},throatFacing="N",throughFacing="S",divergingFacing="SE",
    throughNodes={{x=0,y=1},{x=0,y=2}},divergingNodes={}}
exits=C.exits(turnout,origin)
assert(#exits==3 and exits[2].y==102 and exits[3].x==100 and exits[3].facing=="SE")
local fallback = {blockId="turnout_1:diverge",id="diverge",nodes={turnout.at}}
C.decorate(fallback,turnout,"parent")
assert(fallback.lastFacing=="SE" and not fallback.firstFacing)
local unknown = C.exits({nodes={{x=0,y=0}}},origin)
assert(#unknown==0)
local compound = RailroaderWaymanEntityGeometry.SymmetricalCompactThreeWayTurnout.E
exits=C.exits(compound,origin)
assert(#exits==3 and exits[1].facing=="N" and exits[2].facing=="E" and exits[3].facing=="S")

-- Canonicalization ignores forged client direction/parent fields.
local world=GD.ensure({availableNodes={canonical}})
local draft=GD.copy(world)
draft.availableNodes[1].firstFacing="S";draft.availableNodes[1].physicalId="forged"
local normalized=assert(GD.validateDraft(world,draft,{}))
assert(normalized.availableNodes[1].firstFacing=="N"
    and normalized.availableNodes[1].lastFacing=="SE"
    and normalized.availableNodes[1].physicalId=="physical")
local saved=assert(GD.worldDataFromJSON(assert(GD.worldDataToJSON(normalized))))
assert(saved.availableNodes[1].firstFacing=="N" and saved.availableNodes[1].physicalId=="physical")

-- Exact rays with fractional editor coordinates must also stop at a wall.
assert(find({block("fraction",100,100.5,"N")},"S").nodeId=="fraction")
assert(not find({block("fraction",100,100.5,"S"),block("far",100,104,"N")},"S"))
-- One index for a large graph, reused by all repeated queries.
local large={}
for i=1,20000 do large[i]=block("unrelated_"..i,1000+i,2000,"N") end
large[#large+1]=block("near",100,110,"N")
local built=C.index({availableNodes=large})
for _=1,1000 do assert(C.find(built,origin,"S").nodeId=="near") end
print("PASS: eight unbounded rays, first walls, same-point candidates, ties, endpoints, compounds and trusted persistence")
print("PASS: fractional alignment and repeated queries against 20,001 indexed nodes")
print("PASS: incompatible node reasons, stable blocker labels, edge endpoints/inversion and available nodes")
print("PASS: runtime free endpoint facings, reversed edges, coincident nodes and unchanged saved data")
