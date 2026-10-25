-- Shared geometry and connection rules for authoritative registration and
-- client construction guides. This module never loads world squares or reads
-- editor drafts: callers supply geometry or a confirmed graph snapshot.
--
-- decorate() stamps trusted physical facings on canonical blocks. index()
-- derives edge endpoints and occupied facings on separate runtime candidates;
-- those derived fields never modify the saved graph. find() searches the index
-- and stops at the first occupied coordinate, even when it cannot connect.

---@alias WaymanConnectionFacing 'N'|'NE'|'E'|'SE'|'S'|'SW'|'W'|'NW'

--- Relevant fields of a relative face definition or one of its components.
---@class WaymanConnectionGeometry
---@field nodes WaymanNode[]? Turn nodes in their physical definition order.
---@field nodesFacing string? Comma-separated directions for the first/last turn nodes.
---@field at WaymanNode? Turnout throat and fallback for empty branch lists.
---@field throughNodes WaymanNode[]?
---@field divergingNodes WaymanNode[]?
---@field throatFacing WaymanConnectionFacing?
---@field throughFacing WaymanConnectionFacing?
---@field divergingFacing WaymanConnectionFacing?
---@field components WaymanConnectionGeometry[]? Logical pieces sharing one physical entity.

---@class WaymanConnectionExit
---@field x number Absolute world X.
---@field y number Absolute world Y.
---@field z number Absolute world Z.
---@field facing WaymanConnectionFacing Outward direction from the physical piece.

--- Runtime copy of one graph node; nodeIndex always refers to its original block.
---@class WaymanConnectionCandidate
---@field nodeId string Canonical blockId, also used in labels and tie-breaking.
---@field nodeIndex integer Index in block.nodes, independent of traversal inversion.
---@field edgeId string? Absent for an available block.
---@field physicalId string? Shared by all logical components of the same parent.
---@field x number Absolute world X.
---@field y number Absolute world Y.
---@field z number Absolute world Z.
---@field firstFacing WaymanConnectionFacing? Declared facing of physical node 1, if applicable.
---@field lastFacing WaymanConnectionFacing? Declared facing of the last physical node, if applicable.
---@field edgeEndpoint boolean? True only for the first/last candidate of an entire edge.
---@field usedFacing WaymanConnectionFacing? Direction occupied by the edge's distinct neighbor.

--- One occupied coordinate, with all coincident candidates in its numeric entries.
---@class WaymanConnectionPoint
---@field x number
---@field y number
---@field z number
---@field [integer] WaymanConnectionCandidate

--- index[axis][z][cross] is an ascending list of occupied coordinates on one line.
--- Axis/cross/position conventions are documented on linePosition().
---@alias WaymanConnectionIndex table<integer, table<number, table<number, WaymanConnectionPoint[]>>>

---@class WaymanConnections
local Connections = {}
RailroaderWaymanConnections = Connections

-- Each tuple is {stepX, stepY, oppositeFacing}. A ray travels in the first two
-- values; the destination must expose the third to face back toward the ghost.
Connections.directions = {
    N={0,-1,"S"}, NE={1,-1,"SW"}, E={1,0,"W"}, SE={1,1,"NW"},
    S={0,1,"N"}, SW={-1,1,"NE"}, W={-1,0,"E"}, NW={-1,-1,"SE"},
}
-- Only these definition-owned fields survive runtime geometry normalization.
Connections.facingFields = {"nodesFacing","throatFacing","throughFacing","divergingFacing"}

--- Identifies a physical parent independently of its logical owner/component IDs.
--- The ghost can exclude all nodes of a parent with the same script and origin.
---@param name string Entity script name used by the geometry catalog.
---@param origin WaymanNode Entity origin; missing Z is treated as zero.
---@return string physicalId
function Connections.physicalId(name, origin)
    return name .. ":" .. tostring(origin.x) .. ":" .. tostring(origin.y) .. ":" .. tostring(origin.z or 0)
end

--- Adds persisted connection metadata using the authority's trusted definition.
--- Facings stay attached to physical node indices; invertNodes only changes edge
--- traversal. A singleton turn can therefore expose both facings at one point.
---@param block WaymanNodeBlock Canonical block to mutate during registration/enrichment.
---@param geometry WaymanConnectionGeometry Relative geometry for this logical component.
---@param physicalId string Identity shared by the complete physical parent.
function Connections.decorate(block, geometry, physicalId)
    block.physicalId = physicalId
    if block.id == "nodes" then
        block.firstFacing, block.lastFacing = (geometry.nodesFacing or ""):match("^([^,]+),([^,]+)$")
    elseif block.id == "at" then block.firstFacing = geometry.throatFacing
    elseif block.id == "through" then block.lastFacing = geometry.throughFacing
    elseif block.id == "diverge" then block.lastFacing = geometry.divergingFacing end
end

--- Collects the ghost's declared exits as absolute positions and outward facings.
--- Turns use their first/last nodes; turnouts use at and the last node of each
--- branch, falling back to at for an empty branch. Missing/unknown facings omit
--- an exit. Compound definitions declare only exits of the complete parent;
--- this helper does not infer links between components or persist ghost IDs.
---@param geometry WaymanConnectionGeometry Face definition, optionally containing components.
---@param origin WaymanNode Placement origin; missing Z is treated as zero.
---@return WaymanConnectionExit[] exits
function Connections.exits(geometry, origin)
    local exits = {}
    --- Converts one declared relative terminal, ignoring undeclared directions.
    ---@param node WaymanNode?
    ---@param facing WaymanConnectionFacing?
    local function add(node, facing)
        if not node or not Connections.directions[facing] then return end
        exits[#exits+1] = {x=origin.x+node.x, y=origin.y+node.y,
            z=(origin.z or 0)+(node.z or 0), facing=facing}
    end
    for _, part in ipairs(geometry.components or {geometry}) do
        if part.nodes then
            local first, last = (part.nodesFacing or ""):match("^([^,]+),([^,]+)$")
            add(part.nodes[1], first)
            add(part.nodes[#part.nodes], last)
        else
            local through, diverge = part.throughNodes or {}, part.divergingNodes or {}
            add(part.at, part.throatFacing)
            add(through[#through] or part.at, part.throughFacing)
            add(diverge[#diverge] or part.at, part.divergingFacing)
        end
    end
    return exits
end

--- Maps XY onto a line key (cross) and an increasing coordinate along that line.
--- The four line families cover opposite pairs of the eight compass directions:
---   axis 1: x constant,   position y (N/S)
---   axis 2: y constant,   position x (E/W)
---   axis 3: x-y constant, position x (NW/SE)
---   axis 4: x+y constant, position x (NE/SW)
--- Numeric keys preserve exact alignment, including fractional editor nodes;
--- there is no rounding, tolerance, or scan of the tiles between indexed nodes.
---@param axis integer Line family, 1 through 4.
---@param x number Absolute world X.
---@param y number Absolute world Y.
---@return number cross Line key within one Z plane.
---@return number position Coordinate used to sort/search that line.
local function linePosition(axis, x, y)
    if axis == 1 then return x, y end
    if axis == 2 then return y, x end
    if axis == 3 then return x-y, x end
    return x+y, x
end

--- Compares coordinates rather than identities when skipping coincident nodes.
---@param a WaymanConnectionCandidate
---@param b WaymanConnectionCandidate
---@return boolean
local function samePoint(a,b)
    return a.x==b.x and a.y==b.y and a.z==b.z
end

--- Marks an edge terminal and derives the facing occupied by its own edge.
--- Cross product zero means collinear; positive dot product means the neighbor
--- lies ahead in that direction. A missing neighbor or different Z leaves the
--- terminal without an occupied facing. Only runtime candidates are mutated.
---@param node WaymanConnectionCandidate First or last candidate of the entire edge.
---@param neighbor WaymanConnectionCandidate? Nearest distinct coordinate inward along the edge.
local function markEndpoint(node,neighbor)
    node.edgeEndpoint = true
    if not neighbor or neighbor.z~=node.z then return end
    local dx,dy = neighbor.x-node.x, neighbor.y-node.y
    for facing,d in pairs(Connections.directions) do
        if dx*d[2]==dy*d[1] and dx*d[1]+dy*d[2]>0 then
            node.usedFacing = facing
            return
        end
    end
end

--- Builds a runtime spatial index without changing the supplied graph.
--- All available and edge nodes are indexed, including internal nodes without
--- facings: they still stop a ray. Coincident nodes share a point but retain
--- separate candidates, so any eligible candidate at that point can connect.
--- The caller owns caching/invalidation; construction guides reuse this result
--- until the confirmed world table or its revision changes.
---@param world WaymanGraphData Confirmed graph; absent collections are treated as empty.
---@return WaymanConnectionIndex index Four sorted line families, separated by Z.
function Connections.index(world)
    local index = {{},{},{},{}}
    -- Deduplicate coordinates across blocks and line families. Every family
    -- references the same point/candidates, including endpoint flags set later.
    local points = {}
    --- Adds candidates in edge traversal order while preserving physical indices.
    ---@param block WaymanNodeBlock
    ---@param edgeId string? Nil means the block is available, outside any edge.
    ---@param ends table? Shared endpoint accumulator for all blocks of one edge.
    local function addBlock(block, edgeId, ends)
        local origin = block.origin or {}
        local nodes = block.nodes or {}
        for position=1,#nodes do
            -- Invert traversal, not the association between facings and nodes.
            local nodeIndex = block.invertNodes and #nodes-position+1 or position
            local node = nodes[nodeIndex]
            local x, y, z = (origin.x or 0)+node.x, (origin.y or 0)+node.y,
                (origin.z or 0)+(node.z or 0)
            points[z] = points[z] or {}
            points[z][x] = points[z][x] or {}
            local point = points[z][x][y]
            if not point then
                point = {x=x,y=y,z=z}
                points[z][x][y] = point
                for axis=1,4 do
                    local cross = linePosition(axis,x,y)
                    index[axis][z] = index[axis][z] or {}
                    local plane = index[axis][z]
                    plane[cross] = plane[cross] or {}
                    plane[cross][#plane[cross]+1] = point
                end
            end
            local candidate = {
                nodeId=block.blockId, nodeIndex=nodeIndex, edgeId=edgeId,
                physicalId=block.physicalId, x=x,y=y,z=z,
                firstFacing=nodeIndex==1 and block.firstFacing or nil,
                lastFacing=nodeIndex==#block.nodes and block.lastFacing or nil,
            }
            point[#point+1] = candidate
            if ends then
                -- Keep the first/last candidates and their inward neighbors.
                -- Coincident coordinates do not consume a direction or hide the
                -- next distinct neighbor, even across a block boundary.
                ends.first = ends.first or candidate
                if not ends.next and not samePoint(ends.first,candidate) then ends.next=candidate end
                if ends.last and not samePoint(ends.last,candidate) then ends.prev=ends.last end
                ends.last = candidate
            end
        end
    end
    for _, block in ipairs(world.availableNodes or {}) do addBlock(block) end
    for edge, blocks in pairs(world.edges or {}) do
        -- Endpoints belong to the complete ordered edge, not to each block.
        local ends = {}
        for _, block in ipairs(blocks) do addBlock(block,edge,ends) end
        if ends.first then
            markEndpoint(ends.first,ends.next)
            markEndpoint(ends.last,ends.prev)
        end
    end
    -- A ray only needs its one sorted line. Sorting happens during index build;
    -- moving the cursor then uses binary search instead of revisiting the graph.
    for axis, planes in ipairs(index) do
        local coordinate = axis==1 and "y" or "x"
        local function less(a,b) return a[coordinate]<b[coordinate] end
        for _, plane in pairs(planes) do
            for _, line in pairs(plane) do
                table.sort(line,less)
            end
        end
    end
    return index
end

--- Searches an unbounded ray, strictly ahead of origin and on the same Z plane.
--- The first coordinate with a non-excluded candidate stops the search, even if
--- every candidate there is incompatible. A point containing only the excluded
--- physical parent is skipped. Returned point/candidates belong to the cached
--- index and should be treated as read-only.
---@param index WaymanConnectionIndex
---@param origin WaymanNode Ray start; nodes exactly at this coordinate are skipped.
---@param facing WaymanConnectionFacing Outward ray direction.
---@param excludedPhysicalId string? Ignore all logical components of this parent.
---@return WaymanConnectionCandidate? target Compatible candidate, or nil for a blocker/no point.
---@return WaymanConnectionPoint? point First occupied coordinate after exclusions, even if blocked.
---@return WaymanConnectionCandidate? node Representative candidate for the target/blocker label.
---@return string? reason UI localization key explaining incompatibility; nil on a match/no point.
function Connections.find(index, origin, facing, excludedPhysicalId)
    local d = Connections.directions[facing]
    if not d then return nil end
    local axis = d[1]==0 and 1 or (d[2]==0 and 2 or (d[1]==d[2] and 3 or 4))
    local cross, position = linePosition(axis,origin.x,origin.y)
    local plane = index[axis][origin.z or 0]
    local line = plane and plane[cross]
    if not line then return nil end
    local sign = axis==1 and d[2] or d[1]
    local coordinate = axis==1 and "y" or "x"
    -- Positive rays use the first position > origin; negative rays take the
    -- predecessor of the first position >= origin. Both exclude the origin
    -- itself, with no arbitrary maximum distance or tile-by-tile iteration.
    local lo, hi = 1, #line+1
    while lo < hi do
        local mid = math.floor((lo+hi)/2)
        if line[mid][coordinate] < position or (sign==1 and line[mid][coordinate]==position) then
            lo=mid+1
        else hi=mid end
    end
    local i = sign==1 and lo or lo-1
    while i>=1 and i<=#line do
        local best, bestReason, bestCompatible
        for _, candidate in ipairs(line[i]) do
            if not excludedPhysicalId or candidate.physicalId~=excludedPhysicalId then
                local reason
                -- An available node or entire-edge endpoint must expose the
                -- opposite physical facing, and that facing must remain free.
                -- Internal edge nodes block the ray regardless of their facing.
                if candidate.edgeId and not candidate.edgeEndpoint then
                    reason = "UI_Wayman_NodeInsideEdge"
                elseif not candidate.firstFacing and not candidate.lastFacing then
                    reason = "UI_Wayman_NodeNoFacing"
                elseif candidate.firstFacing~=d[3] and candidate.lastFacing~=d[3] then
                    reason = "UI_Wayman_NodeFacingMismatch"
                elseif candidate.usedFacing==d[3] then
                    reason = "UI_Wayman_NodeFacingUsed"
                end
                local compatible = reason==nil
                -- Prefer any compatible candidate at this point. Within the
                -- same compatibility class, block ID then physical node index
                -- provide deterministic labels, independent of insertion order.
                if not best or (compatible and not bestCompatible)
                    or (compatible==bestCompatible and (candidate.nodeId<best.nodeId
                        or (candidate.nodeId==best.nodeId and candidate.nodeIndex<best.nodeIndex))) then
                    best, bestReason, bestCompatible = candidate, reason, compatible
                end
            end
        end
        if best then return bestCompatible and best or nil, line[i], best, bestReason end
        -- Continue only when every candidate here belonged to the excluded
        -- parent. An incompatible non-excluded node already returned above.
        i=i+sign
    end
end

return Connections
