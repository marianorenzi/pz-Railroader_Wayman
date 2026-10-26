-- Client adapter from the vanilla construction ghost to Wayman connection
-- guides. Geometry comes from the trusted face catalog; targets come from
-- confirmed world ModData and RR's public catalog, never unpublished drafts.
--
-- Connections owns geometry/search rules. This module caches query results and
-- replaces per-player groups; WorldHighlights owns per-frame drawing. Guides
-- are visual hints only and never change vanilla placement validation.
if isServer() then return end
require "Wayman/WaymanEntityGeometry"
require "Wayman/WaymanConnections"
require "Wayman/WaymanRRGraph"
require "Wayman/WaymanWorldHighlights"

---@class WaymanConstructionGuides
---@field visualLength number Requested draw length, rounded/clamped to 5-10 tiles; search is unbounded.
RailroaderWaymanConstructionGuides = {visualLength=8}
local Guides = RailroaderWaymanConstructionGuides
---@type WaymanConnections
local Connections = RailroaderWaymanConnections
local Highlights = RailroaderWaymanWorldHighlights
local Geometry = RailroaderWaymanEntityGeometry
local RRGraph = RailroaderWaymanRRGraph
local WORLD_KEY = "RailroaderWayman_World"
-- A stable fallback table avoids invalidating the index every frame before
-- confirmed ModData exists. It is read-only and shared by all local players.
local EMPTY = {}
local GREEN = {r=0.1,g=1,b=0.15,a=0.65}
local RED = {r=1,g=0.1,b=0.1,a=0.65}
local WHITE = {r=1,g=1,b=1,a=0.65}

--- Inputs of the last published highlight group for one local player.
---@class WaymanConstructionGuideState
---@field cursor ISBuildIsoEntity
---@field geometry WaymanConnectionGeometry Face-definition table, compared by identity.
---@field x number Placement origin X.
---@field y number Placement origin Y.
---@field z number Placement origin Z.
---@field world table Confirmed ModData table, compared by identity.
---@field revision integer Revision used to build the shared spatial index.
---@field length integer Effective visual length used to create the group.
---@field externalRevision integer Revision of the copied RR/addon endpoints.

---@type table<integer, WaymanConstructionGuideState>
local active = {}
-- One spatial index is shared by every local player's ghost. Table identity
-- catches replacement snapshots; revision catches in-place authoritative edits.
---@type table?, integer?, WaymanConnectionIndex?
local indexedWorld, indexedRevision, index
local indexedExternalRevision
local externalNodes, externalRevision, pollTicks = {}, 0, 0

--- RR has no public graph-change event/revision. Poll only during construction,
--- once per 60 ticks, and retain the index when copied endpoints are unchanged.
local function refreshExternalNodes()
    local nodes = RRGraph.externalEndpoints() or {}
    local same = #nodes==#externalNodes
    if same then
        for i, node in ipairs(nodes) do
            local old = externalNodes[i]
            if node.nodeId~=old.nodeId or node.nodeIndex~=old.nodeIndex or node.edgeId~=old.edgeId
                or node.x~=old.x or node.y~=old.y or node.z~=old.z then same=false; break end
        end
    end
    if not same then externalNodes,externalRevision = nodes,externalRevision+1 end
end

--- Keeps this player's construction guides separate from other highlight users.
---@param player integer Local player number, including split-screen players.
---@return string
local function groupId(player)
    return "construction:" .. tostring(player)
end

--- Resolves catalog geometry for the current script and physical face.
--- SpriteConfig returns lowercase face names; generated definitions use uppercase.
---@param cursor ISBuildIsoEntity
---@return WaymanConnectionGeometry? geometry Nil for an unsupported script/face.
---@return string name Entity script name used to identify the physical parent.
local function getGeometry(cursor)
    local name = cursor.objectInfo:getScript():getName()
    local faces = Geometry[name]
    local face = faces and cursor:getFace()
    return face and faces[string.upper(face:getFaceName())], name
end

--- Removes one player's highlights/labels and last-ghost cache, keeping the index.
---@param player integer Local player number.
function Guides.clear(player)
    active[player] = nil
    Highlights.clearGroup(groupId(player))
end

--- Refreshes a ghost's guides after vanilla renders it at the supplied origin.
--- A stationary ghost with unchanged inputs reuses its group and label text.
--- This method performs no world-square scan, graph mutation, or placement check.
---@param cursor ISBuildIsoEntity
---@param x number Placement origin X, not the entity's master-tile offset.
---@param y number Placement origin Y.
---@param z number Placement origin Z.
function Guides.update(cursor, x, y, z)
    local player = cursor.character:getPlayerNum()
    local geometry, name = getGeometry(cursor)
    if not geometry then Guides.clear(player); return end
    local world = ModData.get(WORLD_KEY) or EMPTY
    local revision = world.revision or 0
    local length = math.max(5,math.min(10,math.floor(Guides.visualLength)))
    local state = active[player]
    if not state or indexedWorld~=world or indexedRevision~=revision then refreshExternalNodes() end
    -- Pose/face/length changes invalidate this player's group. Only confirmed
    -- world or external endpoint changes rebuild the shared graph index.
    if state and state.cursor==cursor and state.geometry==geometry
        and state.x==x and state.y==y and state.z==z and state.world==world
        and state.revision==revision and state.length==length
        and state.externalRevision==externalRevision then return end
    if indexedWorld~=world or indexedRevision~=revision or indexedExternalRevision~=externalRevision then
        index = Connections.index(world,externalNodes)
        indexedWorld, indexedRevision, indexedExternalRevision = world, revision, externalRevision
    end
    local origin = {x=x,y=y,z=z}
    -- Exclude every logical component of an existing parent at the same origin,
    -- rather than treating its sibling owners as possible connection targets.
    local physicalId = Connections.physicalId(name,origin)
    local entries, labels, whites, whiteTiles = {}, {}, {}, {}
    local function isWhite(node)
        local plane = whiteTiles[node.z]
        return plane and plane[node.x] and plane[node.x][node.y]
    end
    local function addWhite(node)
        if isWhite(node) then return end
        whiteTiles[node.z] = whiteTiles[node.z] or {}
        local plane = whiteTiles[node.z]
        plane[node.x] = plane[node.x] or {}
        plane[node.x][node.y] = true
        whites[#whites+1] = {playerNum=player,x=node.x,y=node.y,z=node.z,color=WHITE}
    end
    for _, node in ipairs(Connections.nodes(geometry,origin)) do addWhite(node) end
    for _, exit in ipairs(Connections.exits(geometry,origin)) do
        -- find() stops at the first occupied coordinate, including blockers.
        -- target controls color; point/node/reason also describe a red blocker.
        -- No point means a red guide without a target label.
        local target, point, node, reason = Connections.find(index,exit,exit.facing,physicalId)
        -- One tile per destination, even beyond the short guide or offscreen.
        -- No camera/zoom/world-square checks are needed to submit a highlight.
        if point then addWhite(point) end
        local color = target and GREEN or RED
        local direction = Connections.directions[exit.facing]
        -- Grid-step distance counts a diagonal as one tile. Visual length only
        -- caps drawing: a farther node still determines color and label text.
        -- Fractional diagnostic distances round up to whole highlight steps.
        local distance = point and math.max(math.abs(point.x-exit.x),math.abs(point.y-exit.y))
        local steps = distance and math.min(length,math.ceil(distance)) or length
        for step=1,steps do
            entries[#entries+1] = {playerNum=player,x=exit.x+direction[1]*step,
                y=exit.y+direction[2]*step,z=exit.z,color=color}
        end
        if node then
            -- Anchor labels beside the ghost's exit, even for offscreen targets.
            -- A missing edge ID denotes an available node; incompatibility keys
            -- describe the blocker and receive the facing it would need to expose.
            labels[#labels+1] = {playerNum=player,x=exit.x+direction[1]*0.5,
                y=exit.y+direction[2]*0.5,z=exit.z,
                text=node.nodeId .. " (" .. (node.edgeId or getText("UI_Wayman_AvailableNoEdge"))
                    .. ") — " .. getText("UI_Wayman_DistanceTiles",string.format("%g",distance))
                    .. (reason and " — " .. getText(reason,direction[3]) or "")}
        end
    end
    -- Resolve intersections after every guide: no colored tile may obscure a
    -- ghost node or target belonging to another exit of this same ghost.
    local colored = entries
    entries = {}
    for _, entry in ipairs(colored) do
        if not isWhite(entry) then entries[#entries+1] = entry end
    end
    for _, entry in ipairs(whites) do entries[#entries+1] = entry end
    -- Publish a complete replacement so old exits and labels cannot survive a
    -- move/rotation. The renderer projects/draws this cached group each frame.
    Highlights.replaceGroup(groupId(player),entries,labels)
    active[player] = {cursor=cursor,geometry=geometry,x=x,y=y,z=z,world=world,
        revision=revision,length=length,externalRevision=externalRevision}
end

-- The vanilla cursor belongs to server/BuildingObjects, loaded after client
-- scripts. Install once after the complete Lua load instead of requiring it here.
local hooked = false
Events.OnGameStart.Add(function()
    if hooked then return end
    local render = ISBuildIsoEntity.render
    function ISBuildIsoEntity:render(x,y,z,square)
        -- Keep vanilla rendering/validity behavior and its return value. Guides
        -- also describe invalid placements; compatibility never gates building.
        local result = render(self,x,y,z,square)
        Guides.update(self,x,y,z)
        return result
    end
    hooked = true
end)

-- Cancellation/tool changes stop rendering the old ghost. Check only active
-- local cursors, rather than scanning world objects or graph nodes.
Events.OnTick.Add(function()
    local cell = getCell()
    local hasActive = false
    for player, state in pairs(active) do
        if not cell or cell:getDrag(player)~=state.cursor then Guides.clear(player)
        else hasActive = true end
    end
    pollTicks = hasActive and pollTicks+1 or 0
    if pollTicks>=60 then pollTicks=0; refreshExternalNodes() end
end)
-- Drop references to the previous world's snapshot/index and all local ghosts;
-- unrelated highlight groups remain owned by their respective features.
Events.OnDisconnect.Add(function()
    for player in pairs(active) do Guides.clear(player) end
    indexedWorld, indexedRevision, index = nil, nil, nil
    indexedExternalRevision = nil
    externalNodes, externalRevision, pollTicks = {}, 0, 0
end)

return Guides
