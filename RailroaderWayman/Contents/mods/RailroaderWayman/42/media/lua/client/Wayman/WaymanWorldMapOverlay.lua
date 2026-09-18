-- World-map adapter for Wayman's graph. It caches authoritative graph ModData,
-- renders configured node/edge overlays and hover labels, and adds the map button
-- that opens the otherwise map-independent graph editor.
require "Wayman/WaymanGraphData"
require "Wayman/WaymanGraphEditor"
require "Wayman/WaymanGraphDisplay"
require "Wayman/WaymanRRGraph"
require "ISUI/Maps/ISWorldMap"

local GraphData = RailroaderWaymanGraphData
local Editor = RailroaderWaymanGraphEditor
local GraphDisplay = RailroaderWaymanGraphDisplay
local RRGraph = RailroaderWaymanRRGraph
local WORLD_DATA_KEY = "RailroaderWayman_World"
local POINT_SIZE = 5
local POINT_BORDER = 1
local worldData
local requestPending = false

--- Writes a namespaced world-map diagnostic to the game log.
local function log(message)
    print("[RailroaderWayman] WorldMapGraph: " .. message)
end

--- Rebuilds RR's runtime-only route and graph registries from persistent world data.
local function registerRRGraph(data)
    if type(data.edges) ~= "table" or type(data.edges.wayman) ~= "table" then return end
    local registered, reason = RRGraph.register(data)
    if not registered then
        log("RR route/graph registration failed: " .. tostring(reason))
        return
    end
    log("registered RR route/graph at revision " .. tostring(data.revision))
end

--- Installs freshly received authoritative graph data in the client cache.
local function storeWorldData(data)
    if type(data) ~= "table" then return false end
    worldData = GraphData.ensure(data)
    requestPending = false
    ModData.remove(WORLD_DATA_KEY)
    ModData.add(WORLD_DATA_KEY, data)
    Editor.onWorldData(data)
    GraphDisplay.refresh(data)
    registerRRGraph(data)
    return true
end

--- Loads cached graph data and requests the authoritative multiplayer copy once.
local function requestWorldData()
    local localData = ModData.get(WORLD_DATA_KEY)
    if type(localData) == "table" then
        worldData = GraphData.ensure(localData)
        registerRRGraph(worldData)
    end
    if isClient() and not requestPending then
        requestPending = true
        ModData.request(WORLD_DATA_KEY)
    end
end

--- Handles global ModData responses for the Wayman world-data key.
local function onReceiveGlobalModData(key, data)
    if key ~= WORLD_DATA_KEY then return end
    if not storeWorldData(data) then
        requestPending = false
        log("received no data for " .. WORLD_DATA_KEY)
        return
    end
    log("received graph revision " .. tostring(data.revision))
end

--- Draws a bordered graph-node marker when it falls inside the map viewport.
local function drawPoint(map, x, y, color)
    if x < 0 or y < 0 or x > map:getWidth() or y > map:getHeight() then return end
    local outerSize = POINT_SIZE + POINT_BORDER * 2
    map:drawRect(x - outerSize / 2, y - outerSize / 2, outerSize, outerSize,
        0.90, 0.05, 0.05, 0.05)
    map:drawRect(x - POINT_SIZE / 2, y - POINT_SIZE / 2, POINT_SIZE, POINT_SIZE,
        1.00, color.r, color.g, color.b)
end

--- Derives a stable muted RGB color from an edge's technical ID.
local function edgeColor(edgeId)
    local hash = 0
    for index = 1, #edgeId do hash = (hash * 33 + edgeId:byte(index)) % 360 end
    local sector = math.floor(hash / 60)
    local fraction = (hash % 60) / 60
    local p, q = 0.25, 0.85 - 0.60 * fraction
    local colors = {
        { 0.85, q, p }, { q, 0.85, p }, { p, 0.85, q },
        { p, q, 0.85 }, { q, p, 0.85 }, { 0.85, p, q },
    }
    local value = colors[sector + 1]
    return { r = value[1], g = value[2], b = value[3] }
end

--- Projects an absolute world node into two-dimensional map coordinates.
local function toUI(map, node)
    return map.mapAPI:worldToUIX(node.x, node.y), map.mapAPI:worldToUIY(node.x, node.y)
end

--- Draws one ordered edge polyline and selected-node markers.
local function drawEdge(map, blocks, color, selected)
    local nodes = GraphData.getOrderedNodes(blocks)
    for index = 2, #nodes do
        local x1, y1 = toUI(map, nodes[index - 1])
        local x2, y2 = toUI(map, nodes[index])
        map:drawLine(nil, x1, y1, x2, y2, selected and 4 or 2,
            selected and 1.0 or 0.75, color.r, color.g, color.b)
    end
    if selected then
        for _, node in ipairs(nodes) do
            local x, y = toUI(map, node)
            drawPoint(map, x, y, color)
        end
    end
end

--- Computes squared screen distance from a point to a finite line segment.
local function pointSegmentDistanceSquared(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared == 0 then
        dx, dy = px - x1, py - y1
        return dx * dx + dy * dy
    end
    local t = ((px - x1) * dx + (py - y1) * dy) / lengthSquared
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local nearestX, nearestY = x1 + t * dx, y1 + t * dy
    dx, dy = px - nearestX, py - nearestY
    return dx * dx + dy * dy
end

--- Finds the nearest visible node block or edge under the map cursor.
local function hoveredIdentifier(map, data, state)
    if map.isMouseOver and not map:isMouseOver() then return nil end
    local mouseX, mouseY = map:getMouseX(), map:getMouseY()
    local bestLabel, bestDistance = nil, 64

    for _, block in ipairs(data.availableNodes or {}) do
        local visible = state.showAvailableNodes or block.blockId == state.selectedAvailableBlockId
        if visible then
            for _, node in ipairs(block.nodes or {}) do
                local x, y = toUI(map, node)
                local dx, dy = mouseX - x, mouseY - y
                local distance = dx * dx + dy * dy
                if distance <= bestDistance then
                    bestLabel, bestDistance = getText("UI_Wayman_MapNode", block.blockId), distance
                end
            end
        end
    end

    for edgeId, blocks in pairs(data.edges or {}) do
        local visible = state.showAllEdges
            or (state.showSelectedEdge and edgeId == state.selectedEdgeId)
        if visible then
            local nodes = GraphData.getOrderedNodes(blocks)
            for index = 2, #nodes do
                local x1, y1 = toUI(map, nodes[index - 1])
                local x2, y2 = toUI(map, nodes[index])
                local distance = pointSegmentDistanceSquared(mouseX, mouseY, x1, y1, x2, y2)
                if distance <= bestDistance then
                    bestLabel, bestDistance = getText("UI_Wayman_MapEdge", edgeId), distance
                end
            end
        end
    end
    return bestLabel, mouseX, mouseY
end

--- Draws a viewport-clamped identifier tooltip beside the map cursor.
local function drawHoverLabel(map, text, mouseX, mouseY)
    if not text then return end
    local width = getTextManager():MeasureStringX(UIFont.Small, text) + 12
    local height = getTextManager():getFontHeight(UIFont.Small) + 8
    local x, y = mouseX + 12, mouseY + 12
    if x + width > map:getWidth() then x = mouseX - width - 12 end
    if y + height > map:getHeight() then y = mouseY - height - 12 end
    map:drawRect(x, y, width, height, 0.90, 0.05, 0.05, 0.05)
    map:drawRectBorder(x, y, width, height, 0.80, 0.8, 0.8, 0.8)
    map:drawText(text, x + 6, y + 4, 1, 1, 1, 1, UIFont.Small)
end

--- Renders confirmed or draft graph layers according to editor display state.
local function drawGraph(map)
    if not map.mapAPI then return end
    local confirmed = worldData or ModData.get(WORLD_DATA_KEY)
    local state = Editor.getOverlayState(confirmed)
    local data = state.data
    if type(data) ~= "table" then return end
    if state.showAllEdges then
        for edgeId, blocks in pairs(data.edges or {}) do
            if edgeId ~= state.selectedEdgeId or not state.showSelectedEdge then
                drawEdge(map, blocks, edgeColor(edgeId), false)
            end
        end
    end
    if state.showSelectedEdge and state.selectedEdgeId
        and data.edges and data.edges[state.selectedEdgeId] then
        drawEdge(map, data.edges[state.selectedEdgeId], { r = 1.0, g = 0.85, b = 0.1 }, true)
    end
    for _, block in ipairs(data.availableNodes or {}) do
        local selected = block.blockId == state.selectedAvailableBlockId
        if state.showAvailableNodes or selected then
            for _, node in ipairs(block.nodes or {}) do
                local x, y = toUI(map, node)
                local color = selected and { r = 1.00, g = 0.20, b = 0.85 }
                    or { r = 0.10, g = 0.90, b = 1.00 }
                drawPoint(map, x, y, color)
            end
        end
    end
    drawHoverLabel(map, hoveredIdentifier(map, data, state))
end

--- Opens the singleton graph editor using the latest client graph snapshot.
local function openEditor(_map)
    local data = worldData or ModData.get(WORLD_DATA_KEY) or {
        availableNodes = {}, edges = {}, switches = {}, revision = 0,
    }
    Editor.open(data)
end

local originalCreateChildren = ISWorldMap.createChildren
--- Extends vanilla map controls with the Wayman graph-editor button.
function ISWorldMap:createChildren()
    originalCreateChildren(self)
    local size = self.closeBtn and self.closeBtn.height or 48
    self.waymanGraphBtn = ISButton:new(self.closeBtn:getRight() + 10, 0,
        size, size, "G", self, openEditor)
    self.waymanGraphBtn:initialise()
    self.waymanGraphBtn.tooltip = getText("UI_Wayman_MapButtonTooltip")
    self.buttonPanel:addChild(self.waymanGraphBtn)
    self.buttonPanel:shrinkWrap(0, 0, nil)
    self.buttonPanel:setX(self.width - 10 - self.buttonPanel.width)
    if self.buttonPanel.joypadButtons then table.insert(self.buttonPanel.joypadButtons, self.waymanGraphBtn) end
    if self.buttonPanel.allJoypadButtons then table.insert(self.buttonPanel.allJoypadButtons, self.waymanGraphBtn) end
end

local originalRender = ISWorldMap.render
--- Extends vanilla map rendering with Wayman graph overlays.
function ISWorldMap:render()
    originalRender(self)
    drawGraph(self)
end

--- Forwards server-side graph rejection messages to the active editor.
local function onServerCommand(module, command, args)
    if module == "RailroaderWayman" and command == "graphRejected" then
        Editor.onRejected(args and args.reason or getText("UI_Wayman_UnknownServerError"))
    end
end

Events.OnGameStart.Add(requestWorldData)
Events.OnConnected.Add(requestWorldData)
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
Events.OnServerCommand.Add(onServerCommand)

log("loaded")
