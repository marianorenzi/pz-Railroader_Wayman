-- World-map adapter for Wayman's graph. It caches authoritative graph ModData,
-- renders configured node/edge overlays and hover labels, and adds the map button
-- that opens the otherwise map-independent graph editor.
require "Wayman/WaymanGraphData"
require "Wayman/WaymanGraphEditor"
require "Wayman/WaymanGraphSync"
require "ISUI/Maps/ISWorldMap"

local GraphData = RailroaderWaymanGraphData
local Editor = RailroaderWaymanGraphEditor
local Sync = RailroaderWaymanGraphSync
local WORLD_DATA_KEY = "RailroaderWayman_World"
local POINT_SIZE = 5
local POINT_BORDER = 1
local requestPending = false

--- Writes a namespaced world-map diagnostic to the game log.
local function log(message)
    print("[RailroaderWayman] WorldMapGraph: " .. message)
end

--- Installs freshly received authoritative graph data in the client cache.
local function storeWorldData(data)
    if type(data) ~= "table" then return false end
    local current = Sync.current()
    if current and (data.revision or 0) < (current.revision or 0) then return false end
    requestPending = false
    return Sync.receiveSnapshot(data)
end

--- Loads cached graph data and requests the authoritative multiplayer copy once.
local function requestWorldData()
    local localData = ModData.get(WORLD_DATA_KEY)
    if type(localData) == "table" then
        Sync.receiveSnapshot(localData)
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

local edgeColors = {}

--- Keeps similar edge IDs apart in hue and caches their stable RGB colors.
local function edgeColor(edgeId)
    if edgeColors[edgeId] then return edgeColors[edgeId] end
    local hash = 0
    for index = 1, #edgeId do hash = (hash * 33 + edgeId:byte(index)) % 2147483647 end
    local hue = (hash * 0.618033988749895 % 1) * 6
    local sector = math.floor(hue)
    local fraction = hue - sector
    local p, q, t = 0.15, 0.80 - 0.65 * fraction, 0.15 + 0.65 * fraction
    local colors = {
        { 0.80, t, p }, { q, 0.80, p }, { p, 0.80, t },
        { p, q, 0.80 }, { t, p, 0.80 }, { 0.80, p, q },
    }
    local value = colors[sector + 1]
    local color = { r = value[1], g = value[2], b = value[3] }
    edgeColors[edgeId] = color
    return color
end

--- Projects an absolute world node into two-dimensional map coordinates.
local function toUI(map, node)
    return map.mapAPI:worldToUIX(node.x, node.y), map.mapAPI:worldToUIY(node.x, node.y)
end

--- Draws one ordered edge polyline.
local function drawEdge(map, nodes, color, selected)
    for index = 2, #nodes do
        local x1, y1 = toUI(map, nodes[index - 1])
        local x2, y2 = toUI(map, nodes[index])
        map:drawLine(nil, x1, y1, x2, y2, selected and 4 or 2,
            selected and 1.0 or 0.75, color.r, color.g, color.b)
    end
end

--- Draws every node marker from an edge's ordered blocks.
local function drawEdgeNodes(map, nodes, color)
    for _, node in ipairs(nodes) do
        local x, y = toUI(map, node)
        drawPoint(map, x, y, color)
    end
end

--- Labels only the selected traversal. Indices are array positions, never graph
--- attributes. Screen rows keep coincident/nearby labels apart and in the viewport.
local function drawNodeLabels(map, nodes)
    local manager = getTextManager()
    local height = manager:getFontHeight(UIFont.Small) + 4
    local step = height + 3
    local right, bottom = map:getWidth() - 2, map:getHeight() - 2
    local lastRow = math.floor((bottom - height - 2) / step)
    if lastRow < 0 then return end
    local rows, labels = {}, {}
    for index, node in ipairs(nodes) do
        local nodeX, nodeY = toUI(map, node)
        if nodeX >= 0 and nodeY >= 0 and nodeX <= map:getWidth() and nodeY <= map:getHeight() then
            local text = tostring(index)
            local endpoint
            if index == 1 then endpoint = getText("UI_Wayman_TowardStart") end
            if index == #nodes then
                local ending = getText("UI_Wayman_TowardEnd")
                endpoint = endpoint and endpoint .. "/" .. ending or ending
            end
            if endpoint then text = text .. " (" .. endpoint .. ")" end
            local width = manager:MeasureStringX(UIFont.Small, text) + 8
            if width <= right - 2 then
                local wantedX, wantedY = nodeX + 8, nodeY + 8
                local bestX, bestY, bestRow, bestSlot, bestDistance
                for row = 0, lastRow do
                    local y = 2 + row * step
                    local dy = y - wantedY
                    if not bestDistance or dy * dy <= bestDistance then
                        local occupied = rows[row] or {}
                        local left = 2
                        for slot = 1, #occupied + 1 do
                            local limit = occupied[slot] and occupied[slot].x - 3 or right
                            if limit - left >= width then
                                local x = math.max(left, math.min(wantedX, limit - width))
                                local distance = (x - wantedX) ^ 2 + dy * dy
                                if not bestDistance or distance < bestDistance then
                                    bestX, bestY, bestRow, bestSlot, bestDistance = x, y, row, slot, distance
                                end
                            end
                            if occupied[slot] then left = occupied[slot].x + occupied[slot].width + 3 end
                        end
                    end
                end
                -- At densities exceeding the viewport's label capacity, retain
                -- the index at its clamped anchor rather than silently dropping it.
                local label = { text = text, width = width, nodeX = nodeX, nodeY = nodeY,
                    x = bestX or math.max(2, math.min(wantedX, right - width)),
                    y = bestY or math.max(2, math.min(wantedY, bottom - height)) }
                if bestRow then
                    rows[bestRow] = rows[bestRow] or {}
                    table.insert(rows[bestRow], bestSlot, label)
                end
                labels[#labels + 1] = label
            end
        end
    end
    -- Connect displaced labels to their markers before drawing opaque labels.
    for _, label in ipairs(labels) do
        local x = math.max(label.x, math.min(label.nodeX, label.x + label.width))
        local y = math.max(label.y, math.min(label.nodeY, label.y + height))
        map:drawLine(nil, label.nodeX, label.nodeY, x, y, 1, 0.8, 0, 0, 0)
    end
    for _, label in ipairs(labels) do
        map:drawRect(label.x, label.y, label.width, height, 0.95, 0.05, 0.05, 0.05)
        map:drawRectBorder(label.x, label.y, label.width, height, 0.9, 1, 0.85, 0.1)
        map:drawText(label.text, label.x + 4, label.y + 2, 1, 1, 1, 1, UIFont.Small)
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

--- Finds the topmost visible node block or edge under the map cursor.
local function graphHit(map, data, state, mouseX, mouseY)
    if map.isMouseOver and not map:isMouseOver() then return nil end
    mouseX, mouseY = mouseX or map:getMouseX(), mouseY or map:getMouseY()
    local bestLabel, bestTarget, bestDistance, bestPriority = nil, nil, 64, -1

    for edgeId, blocks in pairs(data.edges or {}) do
        local visible = state.showAllEdges
            or (state.showSelectedEdge and edgeId == state.selectedEdgeId)
        if visible then
            local nodes = GraphData.getOrderedNodes(blocks)
            for index = 2, #nodes do
                local x1, y1 = toUI(map, nodes[index - 1])
                local x2, y2 = toUI(map, nodes[index])
                local distance = pointSegmentDistanceSquared(mouseX, mouseY, x1, y1, x2, y2)
                if distance <= 64
                    and (bestPriority < 0 or (bestPriority == 0 and distance <= bestDistance)) then
                    bestLabel, bestDistance, bestPriority =
                        getText("UI_Wayman_MapEdge", edgeId), distance, 0
                    bestTarget = { kind = "edge", edgeId = edgeId }
                end
            end
        end
    end

    local selectedAvailableBlock
    local function inspectBlock(block, priority, kind, edgeId)
        for _, node in ipairs(GraphData.getAbsoluteNodes(block)) do
            local x, y = toUI(map, node)
            local dx, dy = mouseX - x, mouseY - y
            local distance = dx * dx + dy * dy
            if distance <= 64
                and (priority > bestPriority
                    or (priority == bestPriority and distance <= bestDistance)) then
                bestLabel = getText("UI_Wayman_MapNode", block.blockId)
                bestDistance, bestPriority = distance, priority
                bestTarget = { kind = kind, edgeId = edgeId, blockId = block.blockId }
            end
        end
    end

    -- Node markers have priority over edge segments.
    for _, block in ipairs(data.availableNodes or {}) do
        if state.showAvailableNodes and block.blockId == state.selectedAvailableBlockId then
            selectedAvailableBlock = block
        elseif state.showAvailableNodes then
            inspectBlock(block, 1, "availableBlock")
        end
    end

    -- Selected-edge nodes are visible markers and must expose their block tooltip.
    local selectedEdgeBlock
    if state.showSelectedEdge and state.selectedEdgeId and data.edges then
        for _, block in ipairs(data.edges[state.selectedEdgeId] or {}) do
            if block.blockId == state.selectedEdgeBlockId then
                selectedEdgeBlock = block
            else
                inspectBlock(block, 2, "edgeBlock", state.selectedEdgeId)
            end
        end
    end

    if selectedEdgeBlock then inspectBlock(selectedEdgeBlock, 3, "edgeBlock", state.selectedEdgeId) end
    if selectedAvailableBlock then inspectBlock(selectedAvailableBlock, 4, "availableBlock") end

    return bestLabel, mouseX, mouseY, bestTarget
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
    local confirmed = Sync.current()
    local state = Editor.getOverlayState(confirmed)
    local data = state.data
    if type(data) ~= "table" then return end
    local selectedEdgeBlocks
    local selectedEdgeNodes
    local selectedEdgeBlock
    if state.showAllEdges then
        for edgeId, blocks in pairs(data.edges or {}) do
            if edgeId ~= state.selectedEdgeId or not state.showSelectedEdge then
                drawEdge(map, GraphData.getOrderedNodes(blocks), edgeColor(edgeId), false)
            end
        end
    end
    if state.showSelectedEdge and state.selectedEdgeId
        and data.edges and data.edges[state.selectedEdgeId] then
        selectedEdgeBlocks = data.edges[state.selectedEdgeId]
        selectedEdgeNodes = GraphData.getOrderedNodes(selectedEdgeBlocks)
        drawEdge(map, selectedEdgeNodes, { r = 1.0, g = 0.85, b = 0.1 }, true)
        for _, block in ipairs(selectedEdgeBlocks) do
            if block.blockId == state.selectedEdgeBlockId then selectedEdgeBlock = block break end
        end
    end

    local selectedBlock
    for _, block in ipairs(data.availableNodes or {}) do
        local selected = state.showAvailableNodes and block.blockId == state.selectedAvailableBlockId
        if selected then
            selectedBlock = block
        elseif state.showAvailableNodes then
            for _, node in ipairs(GraphData.getAbsoluteNodes(block)) do
                local x, y = toUI(map, node)
                drawPoint(map, x, y, { r = 0.10, g = 0.90, b = 1.00 })
            end
        end
    end

    -- Selected-edge nodes sit above normal available nodes.
    if selectedEdgeNodes then
        drawEdgeNodes(map, selectedEdgeNodes, { r = 1.0, g = 0.85, b = 0.1 })
    end

    if selectedEdgeBlock then
        for _, node in ipairs(GraphData.getAbsoluteNodes(selectedEdgeBlock)) do
            local x, y = toUI(map, node)
            drawPoint(map, x, y, { r = 1.00, g = 0.20, b = 0.85 })
        end
    end

    -- Available selection remains topmost when both selections overlap.
    if selectedBlock then
        for _, node in ipairs(GraphData.getAbsoluteNodes(selectedBlock)) do
            local x, y = toUI(map, node)
            drawPoint(map, x, y, { r = 1.00, g = 0.20, b = 0.85 })
        end
    end
    if selectedEdgeNodes then drawNodeLabels(map, selectedEdgeNodes) end
    drawHoverLabel(map, graphHit(map, data, state))
end

--- Opens the singleton graph editor using the latest client graph snapshot.
local function openEditor(_map)
    local data = Sync.current() or {
        availableNodes = {}, edges = {}, switches = {}, revision = 0,
    }
    Editor.open(data)
end

local originalShowWorldMap = ISWorldMap.ShowWorldMap
--- Raise an already open editor after vanilla adds the map, including its first
--- creation. Forward every argument and return value of the previous handler.
function ISWorldMap.ShowWorldMap(...)
    local wasOpen = Editor.getOverlayState().editorOpen
    local function afterShow(...)
        if wasOpen and ISWorldMap_instance and ISWorldMap_instance:getIsVisible() then
            Editor.bringToTop()
        end
        return ...
    end
    return afterShow(originalShowWorldMap(...))
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

local originalOnMouseDown = ISWorldMap.onMouseDown
--- Selects clicked graph elements and keeps the graph editor above the map.
function ISWorldMap:onMouseDown(x, y)
    local result = originalOnMouseDown(self, x, y)
    local confirmed = Sync.current()
    local state = Editor.getOverlayState(confirmed)
    if type(state.data) == "table" then
        local _, _, _, target = graphHit(self, state.data, state, x, y)
        if target then
            Editor.selectFromMap(target)
        else
            Editor.bringToTop()
        end
    else
        Editor.bringToTop()
    end
    return result
end

--- Forwards server-side graph rejection messages to the active editor.
local function onServerCommand(module, command, args)
    if module ~= "RailroaderWayman" then return end
    if command == "graphSync" or command == "rename" or command == "renameResult" then
        if not Sync.receive(args) then return end
        if command == "renameResult" then Editor.onRenameResult(args) end
        return
    end
    if module == "RailroaderWayman" and command == "graphResult" then
        if not Sync.receive(args) then return end
        Editor.onResult(args or {})
        return
    end
    if module == "RailroaderWayman" and command == "graphRejected" then
        Editor.onRejected(args and args.reason or getText("UI_Wayman_UnknownServerError"))
    end
end

Events.OnGameStart.Add(requestWorldData)
Events.OnConnected.Add(requestWorldData)
Events.OnConnected.Add(function()
    if Editor.instance then
        Editor.instance.awaitingSave, Editor.instance.pendingRename = false, nil
    end
end)
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
Events.OnServerCommand.Add(onServerCommand)

log("loaded")
