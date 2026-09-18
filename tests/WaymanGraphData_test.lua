-- Standalone IDE test for authoritative graph draft validation.

local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local graphFile = root
    .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared/Wayman/WaymanGraphData.lua"

dofile(graphFile)
local GraphData = RailroaderWaymanGraphData

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function assertTrue(value, message)
    if not value then error(message or "expected true", 2) end
end

local a = { blockId = "turn_1:nodes", owner = "turn_1", id = "nodes",
    nodes = { { x = 1, y = 2 }, { x = 3, y = 4 } } }
local b = { blockId = "turnout_1:at", owner = "turnout_1", id = "at",
    nodes = { { x = 5, y = 6 } } }
local world = GraphData.ensure({
    availableNodes = { a, b },
    edges = {},
    switches = {
        { id = "turnout_1", owner = "turnout_1", at = { x = 5, y = 6 },
            legs = { throat = {}, through = {}, diverge = {} } },
    },
    revision = 4,
})

local draft = GraphData.copy(world)
draft.availableNodes = {}
draft.edges = { ["__new:1"] = { b, a } }
draft.edges["__new:1"][2].invertNodes = true
draft.switches[1].legs.throat = { edge = "__new:1", toward = "start" }

local normalized, reason = GraphData.validateDraft(world, draft)
assertTrue(normalized, reason)
assertEqual(normalized.revision, 5, "revision")
assertTrue(normalized.edges.edge_1, "temporary edge id was not allocated")
assertEqual(normalized.edges.edge_1[1].blockId, b.blockId, "block order")
assertTrue(normalized.edges.edge_1[2].invertNodes, "inversion")
assertEqual(normalized.switches[1].legs.throat.edge, "edge_1", "switch edge remap")
assertEqual(world.nextEdgeId, 1, "validation mutated source counter")

local named = GraphData.copy(draft)
named.edges = { patio_norte = named.edges["__new:1"] }
named.switches[1].legs.throat.edge = "patio_norte"
local namedResult, namedReason = GraphData.validateDraft(world, named)
assertTrue(namedResult, namedReason)
assertTrue(namedResult.edges.patio_norte, "custom edge id was not preserved")

local duplicate = GraphData.copy(draft)
table.insert(duplicate.availableNodes, duplicate.edges["__new:1"][1])
local rejected = GraphData.validateDraft(world, duplicate)
assertTrue(rejected == nil, "duplicate block was accepted")

local stale = GraphData.copy(draft)
stale.revision = 3
rejected = GraphData.validateDraft(world, stale)
assertTrue(rejected == nil, "stale draft was accepted")

local incompleteLeg = GraphData.copy(draft)
incompleteLeg.switches[1].legs.throat = { toward = "start" }
local incompleteResult, incompleteReason = GraphData.validateDraft(world, incompleteLeg)
assertTrue(incompleteResult == nil, "incomplete switch leg was accepted")
assertTrue(incompleteReason:find("turnout_1", 1, true), "error omitted switch id")
assertTrue(incompleteReason:find("throat", 1, true), "error omitted leg name")

local falseEmptyLeg = GraphData.copy(draft)
falseEmptyLeg.switches[1].legs.throat = { edge = false, toward = false }
local falseEmptyResult, falseEmptyReason = GraphData.validateDraft(world, falseEmptyLeg)
assertTrue(falseEmptyResult, falseEmptyReason)

local json, jsonReason = GraphData.worldDataToJSON({
    availableNodes = {},
    edges = { wayman = {} },
    switches = {},
    revision = 14,
})
assertTrue(json, jsonReason)
assertEqual(json,
    '{"availableNodes":[],"edges":{"wayman":[]},"revision":14,"switches":[]}',
    "compact deterministic JSON")
local decoded, decodeReason = GraphData.worldDataFromJSON(json)
assertTrue(decoded, decodeReason)
assertEqual(decoded.revision, 14, "decoded JSON revision")
assertEqual(#decoded.availableNodes, 0, "decoded availableNodes")
assertTrue(type(decoded.edges.wayman) == "table", "decoded edge blocks")
local malformed, malformedReason = GraphData.worldDataFromJSON('{"revision":14,}')
assertTrue(malformed == nil and malformedReason, "malformed JSON was accepted")

print("PASS: normalized atomic graph draft and remapped temporary edge id")
print("PASS: preserved a valid user-provided edge id")
print("PASS: rejected duplicate blocks and stale revisions")
print("PASS: diagnosed incomplete switch legs and normalized false empty values")
print("PASS: serialized and deserialized compact world-data JSON")
