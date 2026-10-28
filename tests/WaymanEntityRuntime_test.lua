-- Standalone IDE test. It stubs the Project Zomboid API and exercises the
-- real OnCreate handler plus its deferred OnTick initialization.

local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"

local worldData = {}
local tickHandlers = {}
local logs = {}
local worldTransmissions = 0

ModData = {
    getOrCreate = function(key)
        worldData[key] = worldData[key] or {}
        return worldData[key]
    end,
    transmit = function(key)
        assert(key == "RailroaderWayman_World")
        worldTransmissions = worldTransmissions + 1
    end,
}

Events = {
    OnTick = {
        Add = function(handler) table.insert(tickHandlers, handler) end,
    },
    OnRailroaderRegisterTrack = { Add = function(handler) Events.registerTrackHandler = handler end },
    OnObjectAboutToBeRemoved = { Add = function(handler) Events.removeHandler = handler end },
    OnClientCommand = { Add = function(handler) Events.commandHandler = handler end },
    LoadGridsquare = { Add = function(handler) Events.loadSquareHandler = handler end },
}

function isClient() return false end
function isServer() return true end

RR = {
    API = { edges = function() return {} end,
        registerTrack = function() return true end, unregisterTrack = function() return nil, "unknown" end },
}

local originalPrint = print
function print(message)
    table.insert(logs, tostring(message))
end

function require(name)
    return dofile(luaRoot .. "/shared/" .. name .. ".lua")
end

dofile(luaRoot .. "/server/Wayman/WaymanEntityRuntime.lua")

local function fail(message)
    error(message, 2)
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then fail(message or "expected true") end
end

local seed = 17091986
local function random(minimum, maximum)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return minimum + (seed % (maximum - minimum + 1))
end

local function mockObject(entityName, facing, origin)
    local objectData = {}
    local square = {}
    local masterOffset = {
        x = random(0, 8),
        y = random(0, 8),
        z = random(0, 2),
    }
    local faceInfo = {
        getFaceName = function() return facing end,
        getMasterX = function() return masterOffset.x end,
        getMasterY = function() return masterOffset.y end,
        getMasterZ = function() return masterOffset.z end,
    }
    local spriteConfig = {
        isMultiSquareMaster = function() return true end,
        getFaceInfo = function() return faceInfo end,
    }
    local object = {
        transmissions = 0,
        getMasterObject = function() return nil end,
        getSquare = function() return square end,
        getEntityScript = function()
            return { getName = function() return entityName end }
        end,
        getSpriteConfig = function() return spriteConfig end,
        getModData = function() return objectData end,
        getX = function() return origin.x + masterOffset.x end,
        getY = function() return origin.y + masterOffset.y end,
        getZ = function() return origin.z + masterOffset.z end,
        transmitModData = function(self) self.transmissions = self.transmissions + 1 end,
    }
    square.getObjects = function()
        return {size=function() return 1 end,get=function() return object end}
    end
    return object, objectData
end

local supported = {
    { "Left45DegCurve", { "N", "E", "S", "W" } },
    { "Right45DegCurve", { "N", "E", "S", "W" } },
    { "Curve90Deg", { "N", "E", "S", "W" } },
    { "Left45DegTurn", { "N", "S", "E", "W" } },
    { "Right45DegTurn", { "N", "S", "E", "W" } },
    { "Right45DegTurnoutDiag", { "N", "E", "S", "W" } },
    { "Right90DegTurnout", { "N", "E", "S", "W" } },
    { "WyeTurnout", { "N", "E", "S", "W" } },
    { "Right45DegTurnout", { "N", "E", "S", "W" } },
    { "Left45DegTurnout", { "N", "S", "E", "W" } },
    { "Left90DegTurnout", { "N", "E", "S", "W" } },
    { "Left45DegTurnoutDiag", { "N", "E", "S", "W" } },
}

local missingGeometry = {
    { "UnknownRailEntity", { "W", "E" } },
}

-- Exercise an explicitly empty list in addition to the absent-list cases in
-- the generated geometry. Both must fall back to the turnout's at node.
RailroaderWaymanEntityGeometry.Right45DegTurnoutDiag.N.throughNodes = {}

local created = {}
local expectedBlocks = 0
local expectedSwitches = 0
local skippedCount = 0

for _, entity in ipairs(supported) do
    local entityName, facings = entity[1], entity[2]
    for _, facing in ipairs(facings) do
        local origin = { x = random(8000, 12000), y = random(7000, 11000), z = random(0, 2) }
        local object, objectData = mockObject(entityName, facing, origin)
        RailroaderWaymanEntityRuntime.OnCreate({ thumpable = object, facing = facing })
        local geometry = RailroaderWaymanEntityGeometry[entityName][facing]
        table.insert(created, {
            object = object,
            data = objectData,
            origin = origin,
            geometry = geometry,
        })
        expectedBlocks = expectedBlocks + (geometry.kind == "turnout" and 3 or 1)
        expectedSwitches = expectedSwitches + (geometry.kind == "turnout" and 1 or 0)
    end
end

for _, entity in ipairs(missingGeometry) do
    for _, facing in ipairs(entity[2]) do
        skippedCount = skippedCount + 1
        local origin = { x = random(8000, 12000), y = random(7000, 11000), z = random(0, 2) }
        local object, objectData = mockObject(entity[1], facing, origin)
        RailroaderWaymanEntityRuntime.OnCreate({ thumpable = object, facing = facing })
        table.insert(created, { object = object, data = objectData, skipped = true })
    end
end

assertEqual(#tickHandlers, 1, "runtime tick handler count")
tickHandlers[1]()

local result = worldData.RailroaderWayman_World
assertTrue(result, "global modData was not created")
assertTrue(result.entities == nil, "global modData must not contain entities")
assertEqual(#result.availableNodes, expectedBlocks, "available node block count")
assertEqual(#result.switches, expectedSwitches, "switch count")
assertEqual(worldTransmissions, #created - skippedCount, "global modData transmission count")

local registeredOnLoad
RailroaderWaymanRRGraph.register = function(data)
    registeredOnLoad = data
    return true
end
result.edges.wayman = { result.availableNodes[1], result.availableNodes[2] }
Events.registerTrackHandler()
assertTrue(registeredOnLoad == result, "saved graph was not registered during world-data load")
result.edges.wayman = nil

local function findBlock(owner, id)
    for _, block in ipairs(result.availableNodes) do
        if block.owner == owner and block.id == id then return block end
    end
end

local function findSwitch(owner)
    for _, switch in ipairs(result.switches) do
        if switch.owner == owner then return switch end
    end
end

local function assertRelativeNode(actual, relative, message)
    assertEqual(actual.x, relative.x, message .. " x")
    assertEqual(actual.y, relative.y, message .. " y")
    assertEqual(actual.z, relative.z or 0, message .. " z")
end

local function assertOrigin(actual, expected, message)
    assertEqual(actual.x, expected.x, message .. " x")
    assertEqual(actual.y, expected.y, message .. " y")
    assertEqual(actual.z, expected.z, message .. " z")
end

for _, entry in ipairs(created) do
    if entry.skipped then
        assertTrue(entry.data.railroaderWayman == nil, "missing geometry received an id")
        assertEqual(entry.object.transmissions, 0, "missing geometry was transmitted")
    else
        local owner = entry.data.railroaderWayman.id
        assertTrue(owner, "registered entity has no id")
        assertEqual(entry.object.transmissions, 1, "registered entity transmission count")
        if entry.geometry.kind == "turn" then
            local block = findBlock(owner, "nodes")
            assertTrue(block, "turn nodes block is missing")
            local first, last = entry.geometry.nodesFacing:match("^([^,]+),([^,]+)$")
            assertEqual(block.firstFacing, first, "first turn facing")
            assertEqual(block.lastFacing, last, "last turn facing")
            assertTrue(block.physicalId ~= nil, "physical parent is missing")
            assertOrigin(block.origin, entry.origin, owner .. ":nodes origin")
            assertEqual(#block.nodes, #entry.geometry.nodes, "turn node count")
            for index, node in ipairs(entry.geometry.nodes) do
                assertRelativeNode(block.nodes[index], node, owner .. ":nodes")
            end
        else
            local at = findBlock(owner, "at")
            local through = findBlock(owner, "through")
            local diverge = findBlock(owner, "diverge")
            local switch = findSwitch(owner)
            assertTrue(at and through and diverge, "turnout blocks are missing")
            assertEqual(at.firstFacing, entry.geometry.throatFacing, "throat facing")
            assertEqual(through.lastFacing, entry.geometry.throughFacing, "through facing")
            assertEqual(diverge.lastFacing, entry.geometry.divergingFacing, "diverge facing")
            assertTrue(at.physicalId == through.physicalId and at.physicalId == diverge.physicalId,
                "turnout groups have different physical parents")
            assertTrue(switch, "turnout switch is missing")
            local expectedThrough = entry.geometry.throughNodes
            if not expectedThrough or #expectedThrough == 0 then
                expectedThrough = { entry.geometry.at }
            end
            local expectedDiverge = entry.geometry.divergingNodes
            if not expectedDiverge or #expectedDiverge == 0 then
                expectedDiverge = { entry.geometry.at }
            end
            assertEqual(#through.nodes, #expectedThrough,
                "through node count")
            assertEqual(#diverge.nodes, #expectedDiverge,
                "diverge node count")
            assertOrigin(at.origin, entry.origin, owner .. ":at origin")
            assertRelativeNode(at.nodes[1], entry.geometry.at, owner .. ":at")
            for index, node in ipairs(expectedThrough) do
                assertRelativeNode(through.nodes[index], node, owner .. ":through")
            end
            for index, node in ipairs(expectedDiverge) do
                assertRelativeNode(diverge.nodes[index], node, owner .. ":diverge")
            end
            assertOrigin(switch.origin, entry.origin, owner .. " switch origin")
            assertRelativeNode(switch.at, entry.geometry.at, owner .. " switch at")
            assertTrue(switch.switch == nil, "visual switch position leaked to global modData")
        end
    end
end

local seenBlocks = {}
for _, block in ipairs(result.availableNodes) do
    assertTrue(not seenBlocks[block.blockId], "duplicate block " .. block.blockId)
    seenBlocks[block.blockId] = true
    assertTrue(#block.nodes > 0, "empty block " .. block.blockId)
    assertEqual(block.blockId, block.owner .. ":" .. block.id, "block identity")
end

for _, switch in ipairs(result.switches) do
    assertEqual(switch.id, switch.owner, "switch identity")
    assertTrue(switch.at and switch.at.x and switch.at.y and switch.at.z,
        "switch has no absolute at node")
    assertTrue(switch.legs.throat and switch.legs.through and switch.legs.diverge,
        "switch legs are incomplete")
end

local missingLogs = 0
for _, message in ipairs(logs) do
    if message:find("initialization skipped: no geometry", 1, true) then
        missingLogs = missingLogs + 1
    end
end
assertEqual(missingLogs, skippedCount, "missing geometry log count")

-- Replaying OnCreate for an initialized master must not duplicate global data.
local replay = created[1]
RailroaderWaymanEntityRuntime.OnCreate({ thumpable = replay.object, facing = "N" })
tickHandlers[1]()
assertEqual(#result.availableNodes, expectedBlocks, "idempotent available node count")
assertEqual(#result.switches, expectedSwitches, "idempotent switch count")
assertEqual(worldTransmissions, #created - skippedCount, "idempotent global transmission count")

local removedOwner = replay.data.railroaderWayman.id
local removedBlock = findBlock(removedOwner, "nodes")
for index, block in ipairs(result.availableNodes) do
    if block == removedBlock then table.remove(result.availableNodes, index) break end
end
result.edges.edge_for_removal_test = { removedBlock }
removedBlock.invertNodes = true

-- A pre-guide save is enriched on chunk load without rebuilding the edge.
removedBlock.firstFacing, removedBlock.lastFacing, removedBlock.physicalId = nil, nil, nil
replay.data.railroaderWayman.physicalId = nil
local beforeUpgrade, originalNodes = result.revision, removedBlock.nodes
Events.loadSquareHandler(replay.object:getSquare())
tickHandlers[1]()
assertEqual(result.revision, beforeUpgrade+1, "legacy metadata revision")
assertTrue(removedBlock.nodes==originalNodes and removedBlock.invertNodes,
    "metadata upgrade rebuilt/inverted geometry")
assertEqual(removedBlock.firstFacing,"N","legacy first facing")
assertEqual(removedBlock.lastFacing,"SE","legacy last facing")
local unchanged = result.revision
Events.loadSquareHandler(replay.object:getSquare())
tickHandlers[1]()
assertEqual(result.revision,unchanged,"upgraded chunk load repeated metadata work")

-- A manual update finds the existing owner, rejects malformed client geometry
-- in favor of server defaults, and preserves edge placement/inversion.
local revisionBeforeRecovery = result.revision
local ok, recoveredOwner = RailroaderWaymanEntityRuntime.SaveGeometry(replay.object, {
    id = removedOwner,
    nodes = { { x = "not-a-number", y = 999 } },
    nodesFacing = "W,E", physicalId = "forged",
}, "N")
assertTrue(ok, "existing entity recovery failed")
assertEqual(recoveredOwner, removedOwner, "existing owner changed during recovery")
assertEqual(result.revision, revisionBeforeRecovery + 1, "recovery revision")
assertEqual(#result.edges.edge_for_removal_test, 1, "recovery lost edge placement")
assertTrue(result.edges.edge_for_removal_test[1].invertNodes, "recovery lost inversion")
assertEqual(result.edges.edge_for_removal_test[1].firstFacing,"N","client changed first facing")
assertEqual(result.edges.edge_for_removal_test[1].lastFacing,"SE","client changed last facing")
assertRelativeNode(result.edges.edge_for_removal_test[1].nodes[1],
    replay.geometry.nodes[1], "server-default fallback")

-- A forged client ID cannot move or overwrite another physical entity's owner.
local protected = created[2]
local protectedOwner = protected.data.railroaderWayman.id
local protectedBlock = findBlock(protectedOwner, "nodes")
local protectedX = protectedBlock.nodes[1].x
local forgedOk, forgedOwner = RailroaderWaymanEntityRuntime.SaveGeometry(replay.object, {
    id = protectedOwner,
}, "N")
assertTrue(forgedOk, "server-owned identity update failed")
assertEqual(forgedOwner, removedOwner, "client replaced the server-owned entity id")
assertEqual(findBlock(protectedOwner, "nodes").nodes[1].x, protectedX,
    "forged id replaced another entity's graph data")

-- Non-finite client coordinates are rejected in favor of server defaults.
local infiniteOk = RailroaderWaymanEntityRuntime.SaveGeometry(replay.object, {
    nodes = { { x = math.huge, y = 0 / 0 } },
}, "N")
assertTrue(infiniteOk, "non-finite fallback update failed")
assertRelativeNode(result.edges.edge_for_removal_test[1].nodes[1],
    replay.geometry.nodes[1], "non-finite server-default fallback")

-- A failed staged rebuild leaves the authoritative graph untouched.
local originalDefaults = replay.geometry.nodes
local revisionBeforeFailedUpdate = result.revision
local blockBeforeFailedUpdate = result.edges.edge_for_removal_test[1]
replay.geometry.nodes = {}
local failedOk = RailroaderWaymanEntityRuntime.SaveGeometry(replay.object, {}, "N")
replay.geometry.nodes = originalDefaults
assertTrue(not failedOk, "invalid geometry unexpectedly registered")
assertEqual(result.revision, revisionBeforeFailedUpdate, "failed update changed revision")
assertTrue(result.edges.edge_for_removal_test[1] == blockBeforeFailedUpdate,
    "failed update mutated authoritative graph")

-- Simulate an entity whose OnCreate callback was missed entirely.
local missedObject, missedData = mockObject("Right45DegTurn", "E", { x = 9000, y = 9100, z = 0 })
local missedOk, missedOwner = RailroaderWaymanEntityRuntime.SaveGeometry(missedObject, {}, "E")
assertTrue(missedOk, "missed entity recovery failed")
assertTrue(missedOwner and missedData.railroaderWayman.id == missedOwner,
    "missed entity did not receive an id")
assertTrue(findBlock(missedOwner, "nodes"), "missed entity geometry was not registered")

local revisionBeforeRemoval = result.revision
local transmissionsBeforeRemoval = worldTransmissions
Events.removeHandler(replay.object)
assertTrue(findBlock(removedOwner, "nodes") == nil, "removed entity block remains registered")
assertTrue(result.edges.edge_for_removal_test == nil, "empty edge remains after entity removal")
assertEqual(result.revision, revisionBeforeRemoval + 1, "revision after entity removal")
assertEqual(worldTransmissions, transmissionsBeforeRemoval + 1, "removal transmission count")

print = originalPrint
originalPrint("PASS: registered " .. tostring(#created - skippedCount) .. " supported entity orientations")
originalPrint("PASS: skipped and logged " .. tostring(skippedCount) .. " unsupported entity orientations")
originalPrint("PASS: " .. tostring(#result.availableNodes) .. " availableNodes, "
    .. tostring(#result.switches) .. " switches, no entities collection")
originalPrint("PASS: removed entity data atomically")
originalPrint("PASS: recovered existing and missed entities with server-default fallback")

return result
