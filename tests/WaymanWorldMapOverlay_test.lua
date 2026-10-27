-- Standalone IDE test for the client-side world-map overlay.

local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local clientFile = root
    .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/client/Wayman/WaymanWorldMapOverlay.lua"
local sharedRoot = root
    .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared/"

local handlers = {}
local registry = {}
local requests = {}

local function event(name)
    handlers[name] = {}
    return {
        Add = function(callback) table.insert(handlers[name], callback) end,
    }
end

Events = {
    OnGameStart = event("OnGameStart"),
    OnConnected = event("OnConnected"),
    OnReceiveGlobalModData = event("OnReceiveGlobalModData"),
    OnServerCommand = event("OnServerCommand"),
}

ModData = {
    get = function(key) return registry[key] end,
    remove = function(key) registry[key] = nil end,
    add = function(key, data) registry[key] = data end,
    request = function(key) table.insert(requests, key) end,
}

function isClient() return true end
function getText(key, value)
    if key == "UI_Wayman_MapEdge" then return "Edge: " .. value end
    if key == "UI_Wayman_MapNode" then return "Block: " .. value end
    if key == "UI_Wayman_TowardStart" then return "start" end
    if key == "UI_Wayman_TowardEnd" then return "end" end
    return key
end

local showArgs, allowMap, selectedTarget, raises = nil, true, nil, 0
ISWorldMap = {
    createChildren = function() end,
    render = function(self) self.originalRenderCount = self.originalRenderCount + 1 end,
    onMouseDown = function() return "vanilla click" end,
    ShowWorldMap = function(...)
        showArgs = { n = select("#", ...), ... }
        if allowMap then ISWorldMap_instance = { getIsVisible = function() return true end } end
        return "previous handler", nil, 42
    end,
}
ISWorldMap.__index = ISWorldMap

local overlayOverride
RailroaderWaymanGraphEditor = {
    onWorldData = function() end,
    onRejected = function() end,
    onResult = function(args) RailroaderWaymanGraphEditor.result=args end,
    selectFromMap = function(target) selectedTarget = target end,
    bringToTop = function() raises = raises + 1 end,
    getOverlayState = function(data)
        if overlayOverride then return overlayOverride end
        return {
            data = data,
            showAllEdges = true,
            showAvailableNodes = true,
            showSelectedEdge = true,
            selectedAvailableBlockId = "turn_1:nodes",
        }
    end,
}

RailroaderWaymanGraphDisplay = {
    refresh = function() end,
}

-- Snapshot transport is exercised with the real journal in WaymanRename_test;
-- this suite isolates drawing, vanilla forwarding and command dispatch.
RailroaderWaymanGraphSync = {
    current=function() return registry.RailroaderWayman_World end,
    receiveSnapshot=function(data)
        registry.RailroaderWayman_World=data
        return true
    end,
    receive=function(message)
        local current=registry.RailroaderWayman_World
        if not current or message.worldData.revision >= (current.revision or 0) then
            registry.RailroaderWayman_World=message.worldData
        end
        return true
    end,
}

local rrRegistrations = {}
RailroaderWaymanRRGraph = {
    register = function(data)
        table.insert(rrRegistrations, data)
        return true
    end,
}

function require(name)
    if name == "Wayman/WaymanGraphData" then return dofile(sharedRoot .. name .. ".lua") end
end

dofile(clientFile)

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

handlers.OnGameStart[1]()
handlers.OnConnected[1]()
assertEqual(#requests, 1, "duplicate data request prevention")
assertEqual(requests[1], "RailroaderWayman_World", "requested key")

handlers.OnReceiveGlobalModData[1]("OtherMod", { availableNodes = {} })
assertEqual(registry.OtherMod, nil, "unrelated global data")

local data = {
    availableNodes = {
        { blockId = "turn_1:nodes", nodes = {
            { x = 10, y = 20, z = 0 }, { x = 30, y = 40, z = 0 },
        } },
        { blockId = "turn_2:nodes", nodes = { { x = 50, y = 80, z = 1 } } },
    },
    edges = {
        edge_1 = {
            { blockId = "turn_1:nodes", nodes = {
                { x = 5, y = 6 }, { x = 7, y = 9 },
            } },
        },
    },
    switches = {},
}
handlers.OnReceiveGlobalModData[1]("RailroaderWayman_World", data)
assertEqual(registry.RailroaderWayman_World, data, "received data registration")
assertEqual(#rrRegistrations, 0, "data without wayman edge must not register RR")

data.edges.wayman = data.edges.edge_1
handlers.OnReceiveGlobalModData[1]("RailroaderWayman_World", data)
assertEqual(#rrRegistrations, 0, "client must never register the Railroader graph")
data.edges.wayman = nil

local mouseX, mouseY = 1000, 1000
local map = setmetatable({
    originalRenderCount = 0,
    rectangles = {},
    lines = {},
    texts = {},
    mapAPI = {
        worldToUIX = function(_, x, _) return x * 2 end,
        worldToUIY = function(_, _, y) return y * 3 end,
    },
    getWidth = function() return 200 end,
    getHeight = function() return 200 end,
    getMouseX = function() return mouseX end,
    getMouseY = function() return mouseY end,
    drawRect = function(self, x, y, width, height, alpha, red, green, blue)
        table.insert(self.rectangles, {
            x = x, y = y, width = width, height = height,
            alpha = alpha, red = red, green = green, blue = blue,
        })
    end,
    drawLine = function(self, texture, x1, y1, x2, y2, thickness, alpha, red, green, blue)
        table.insert(self.lines, { x1 = x1, y1 = y1, x2 = x2, y2 = y2, thickness = thickness })
    end,
    drawRectBorder = function() end,
    drawText = function(self, text, x, y)
        self.hoverText = text
        self.texts[#self.texts + 1] = {text = text, x = x, y = y}
    end,
}, ISWorldMap)

map:render()
assertEqual(map.originalRenderCount, 1, "original map render call")
-- The third node maps below the visible map, so only two points are drawn.
assertEqual(#map.rectangles, 4, "visible point rectangle count")
assertEqual(map.rectangles[2].x, 17.5, "first point x")
assertEqual(map.rectangles[2].y, 57.5, "first point y")
assertEqual(map.rectangles[2].red, 1.0, "selected available block red")
assertEqual(map.rectangles[2].blue, 0.85, "selected available block blue")
assertEqual(map.rectangles[4].x, 57.5, "second point x")
assertEqual(map.rectangles[4].y, 117.5, "second point y")
assertEqual(#map.lines, 1, "edge segment count")
assertEqual(map.lines[1].x1, 10, "edge start x")
assertEqual(map.lines[1].y2, 27, "edge end y")

UIFont = { Small = "Small" }
function getTextManager()
    return {
        MeasureStringX = function(_, _, text) return #text * 7 end,
        getFontHeight = function() return 12 end,
    }
end
mouseX, mouseY = 10, 18
map:render()
assertEqual(map.hoverText, "Edge: edge_1", "edge hover identifier")

handlers.OnReceiveGlobalModData[1]("RailroaderWayman_World", false)
handlers.OnConnected[1]()
assertEqual(#requests, 2, "retry after false response")

-- A correlated result may arrive before the ModData broadcast.
local acknowledged = RailroaderWaymanGraphData.copy(data)
acknowledged.revision = 2
handlers.OnServerCommand[1]("RailroaderWayman","graphResult",{
    requestId="own:1",ok=true,worldData=acknowledged,
})
assertEqual(registry.RailroaderWayman_World.revision, 2, "ack did not refresh authoritative cache")
assertEqual(RailroaderWaymanGraphEditor.result.requestId, "own:1", "ack lost its request identity")
handlers.OnReceiveGlobalModData[1]("RailroaderWayman_World",data)
assertEqual(registry.RailroaderWayman_World.revision, 2, "late broadcast rolled revision backwards")

-- Opening delegates to the previous handler once, preserving nil returns and
-- all arguments, and only raises an editor which was already open.
overlayOverride = { editorOpen = true }
local a, b, c = ISWorldMap.ShowWorldMap(0, nil, 120, 18)
assertEqual(a, "previous handler"); assertEqual(b, nil); assertEqual(c, 42)
assertEqual(showArgs.n, 4); assertEqual(showArgs[3], 120); assertEqual(showArgs[4], 18)
assertEqual(raises, 1, "first map creation must raise visible editor")
ISWorldMap.ShowWorldMap(1)
assertEqual(raises, 2, "map reopening must raise visible editor")
overlayOverride.editorOpen = false
ISWorldMap.ShowWorldMap(0)
assertEqual(raises, 2, "map must not open a hidden editor")
overlayOverride.editorOpen, allowMap, ISWorldMap_instance = true, false, nil
ISWorldMap.ShowWorldMap(0)
assertEqual(raises, 2, "denied map opening must not raise editor")

local GD = RailroaderWaymanGraphData
local graph = {edges = {line = {
    {blockId="A", nodes={{x=10,y=10},{x=20,y=10}}},
    {blockId="B", invertNodes=true, nodes={{x=30,y=10},{x=40,y=10}}},
}}, availableNodes = {{blockId="available", nodes={{x=80,y=50}}}}}
overlayOverride = {data=graph, editorOpen=true, showAllEdges=false,
    showAvailableNodes=false, showSelectedEdge=true, selectedEdgeId="line",
    selectedEdgeBlockId="B", selectedAvailableBlockId="available"}
local function render()
    map.rectangles, map.lines, map.texts, map.hoverText = {}, {}, {}, nil
    map:render()
end
local function markerCount()
    local count = 0
    for _, rect in ipairs(map.rectangles) do if rect.width == 5 then count = count + 1 end end
    return count
end
local function labelLinks()
    local links = {}
    for _, line in ipairs(map.lines) do
        if line.thickness == 1 then links[#links + 1] = line end
    end
    return links
end
local function checkLabels(expectedX)
    assertEqual(#map.texts, #expectedX, "one label per visible traversal node")
    local links = labelLinks()
    for index, x in ipairs(expectedX) do
        assertEqual(links[index].x1, x, "index coordinate must follow exported traversal")
        assert(map.texts[index].text:match("^" .. index .. "%D") or map.texts[index].text == tostring(index))
    end
end
mouseX, mouseY = 1000, 1000
local before = assert(GD.worldDataToJSON(graph))
render()
checkLabels({20,40,80,60}) -- 1:A1, 2:A2, 3:B2, 4:B1
assertEqual(map.texts[1].text, "1 (start)")
assertEqual(map.texts[4].text, "4 (end)")
assertEqual(markerCount(), 6, "four edge points and two selected-block points")
assertEqual(GD.worldDataToJSON(graph), before, "rendering must never persist indices or UI data")

-- Reorder/invert the actual arrays; no stored numbering needs updating.
graph.edges.line[2].invertNodes = nil
render(); checkLabels({20,40,60,80})
graph.edges.line[1], graph.edges.line[2] = graph.edges.line[2], graph.edges.line[1]
render(); checkLabels({60,80,20,40})

-- Assigned curved blocks contribute all interior nodes; removing the block
-- removes those labels and restores the endpoint, without cached indices.
local curve = {blockId="curve", nodes={{x=30,y=20},{x=40,y=30},{x=50,y=30}}}
graph.edges.line[3] = curve
render(); checkLabels({60,80,20,40,60,80,100})
assertEqual(map.texts[7].text, "7 (end)")
graph.edges.line[3] = nil
render(); checkLabels({60,80,20,40})
local projectionX, projectionY = map.mapAPI.worldToUIX, map.mapAPI.worldToUIY
map.mapAPI.worldToUIX = function(_, x) return x * 3 + 5 end
map.mapAPI.worldToUIY = function(_, _, y) return y * 2 + 5 end
render(); checkLabels({95,125,35,65})
map.mapAPI.worldToUIX, map.mapAPI.worldToUIY = projectionX, projectionY

-- Selected-edge drawing flattens only that edge, once for line/points/labels.
graph.edges.unrelated = {{blockId="unrelated", nodes={{x=1,y=1},{x=2,y=2}}}}
local orderedNodes, traversals = GD.getOrderedNodes, 0
GD.getOrderedNodes = function(blocks)
    assert(blocks == graph.edges.line, "labels traversed another edge")
    traversals = traversals + 1
    return orderedNodes(blocks)
end
map.isMouseOver = function() return false end
render()
assertEqual(traversals, 1, "selected edge flattened repeatedly for numbering")
GD.getOrderedNodes, map.isMouseOver, graph.edges.unrelated = orderedNodes, nil, nil

-- Endpoint labels sharing a marker (and dense nearby nodes) stay separate,
-- inside the viewport. An offscreen node still consumes its global index.
graph.edges.line = {{blockId="loop", nodes={
    {x=0,y=0},{x=1,y=0},{x=1,y=0},{x=100,y=200/3},{x=0,y=0},
}}}
render()
assertEqual(#map.texts, 5)
assertEqual(map.texts[1].text, "1 (start)"); assertEqual(map.texts[5].text, "5 (end)")
for i, label in ipairs(map.texts) do
    local width, height = #label.text * 7 + 8, 16
    local x, y = label.x - 4, label.y - 2
    assert(x >= 0 and y >= 0 and x + width <= 200 and y + height <= 200, "label outside viewport")
    for j = 1, i - 1 do
        local other = map.texts[j]
        local ox, oy = other.x - 4, other.y - 2
        assert(x + width <= ox or ox + #other.text * 7 + 8 <= x
            or y + height <= oy or oy + height <= y, "coincident labels overlap")
    end
end
graph.edges.line[1].nodes[1].x = -1
render()
assertEqual(#map.texts, 4); assertEqual(map.texts[1].text, "2", "viewport culling reset node indices")
graph.edges.line = {{blockId="single", nodes={{x=50,y=50}}}}
render(); assertEqual(map.texts[1].text, "1 (start/end)")

-- Even stale selections cannot expose hidden points, tooltips or block hits.
overlayOverride.showSelectedEdge = false
overlayOverride.showAllEdges = true
overlayOverride.selectedAvailableBlockId = "available"
mouseX, mouseY = 160, 150
render()
assertEqual(markerCount(), 0); assertEqual(#map.texts, 0)
selectedTarget = nil
assertEqual(map:onMouseDown(mouseX, mouseY), "vanilla click")
assertEqual(selectedTarget, nil, "hidden selected available block remained clickable")
graph.edges.line[1].nodes[2] = {x=80,y=50}
render()
assertEqual(map.hoverText, "Edge: line", "Show all edges must keep normal line tooltips")
map:onMouseDown(mouseX, mouseY)
assertEqual(selectedTarget.kind, "edge", "hidden block stole normal edge hit")
assertEqual(map.lines[1].thickness, 2, "hidden selected edge kept emphasis")
overlayOverride.showAllEdges = false
render(); assertEqual(#map.lines, 0); assertEqual(#map.texts, 0)
overlayOverride.showAvailableNodes = true
render(); assertEqual(markerCount(), 1); assertEqual(map.hoverText, "Block: available")
map:onMouseDown(mouseX, mouseY)
assertEqual(selectedTarget.kind, "availableBlock")
overlayOverride.showAvailableNodes = false
overlayOverride.showSelectedEdge = true
render()
assertEqual(map.hoverText, "Block: single", "selected edge block tooltip")
map:onMouseDown(mouseX, mouseY)
assertEqual(selectedTarget.kind, "edgeBlock")

print("PASS: requested and registered global modData")
print("PASS: rendered 2 visible availableNodes points and culled 1 off-map point")
print("PASS: rendered an edge segment")
print("PASS: identified an edge segment on hover")
print("PASS: map opening preserves arguments/returns and raises only an already visible editor")
print("PASS: global traversal indices follow inversion/reorder, including interior and coincident nodes")
print("PASS: hidden layers have no point tooltip/hit; Show all edges retains normal lines and hits")
