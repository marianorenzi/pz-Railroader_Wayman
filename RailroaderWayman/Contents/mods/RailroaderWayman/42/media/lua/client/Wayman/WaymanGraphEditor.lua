-- Standalone graph-editing window and controller. It owns an isolated draft,
-- edits edges/switch legs/node-block assignments, submits one atomic server
-- transaction, and updates shared visualization options without owning renderers.
require "Wayman/WaymanGraphData"
require "Wayman/WaymanGraphDisplay"
require "ISUI/ISButton"
require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISComboBox"
require "ISUI/ISLabel"
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTabPanel"
require "ISUI/ISTickBox"
require "ISUI/ISTextEntryBox"

RailroaderWaymanGraphEditor = RailroaderWaymanGraphEditor or {}
local Controller = RailroaderWaymanGraphEditor
local GraphData = RailroaderWaymanGraphData
local GraphDisplay = RailroaderWaymanGraphDisplay
local WORLD_DATA_KEY = "RailroaderWayman_World"
local SPACING = 10
local BUTTON_H = 25
local ROW_H = 28
local DISPLAY_GAP = 16

--- Resolves one Wayman UI translation.
local function tr(key, ...)
    return getText("UI_Wayman_" .. key, ...)
end

--- Returns deterministic alphabetical keys for edge selectors.
local function sortedKeys(values)
    local result = {}
    for key in pairs(values or {}) do table.insert(result, key) end
    table.sort(result)
    return result
end

--- Clears all options and selection state from a vanilla combo box.
local function clearCombo(combo)
    combo.options = {}
    combo.selected = 0
end

--- Safely returns selected combo data, including empty-combo handling.
local function comboData(combo)
    if not combo or combo.selected < 1 or not combo.options[combo.selected] then return nil end
    return combo:getOptionData(combo.selected)
end

--- Populates an edge selector and restores its requested selection.
local function fillEdgeCombo(combo, edges, includeEmpty, selected)
    clearCombo(combo)
    if includeEmpty then combo:addOptionWithData(tr("Unassigned"), false) end
    for _, edgeId in ipairs(sortedKeys(edges)) do combo:addOptionWithData(edgeId, edgeId) end
    if selected ~= nil then combo:setSelectedData(selected or false) end
end

local EdgeBlockList = ISScrollingListBox:derive("WaymanEdgeBlockList")

--- Creates the ordered edge-block list bound to its editor controller.
function EdgeBlockList:new(x, y, width, height, editor)
    local o = ISScrollingListBox.new(self, x, y, width, height)
    o.editor = editor
    o.itemheight = ROW_H
    o.dragItem = nil
    o.dragHandleWidth = 30
    o.removeWidth = 72
    o.invertWidth = 76
    o.doDrawItem = EdgeBlockList.doDrawItem
    return o
end

--- Draws one edge block with drag, node-count, invert, and remove affordances.
function EdgeBlockList:doDrawItem(y, item, alt)
    local block = item.item
    if self.selected == item.index then self:drawRect(0, y, self.width, item.height, 0.25, 0.2, 0.55, 0.8) end
    self:drawRectBorder(0, y, self.width, item.height, 0.35, 0.7, 0.7, 0.7)
    self:drawText("≡", 10, y + 5, 0.8, 0.8, 0.8, 1, UIFont.Small)
    self:drawText(block.blockId, 34, y + 5, 1, 1, 1, 1, UIFont.Small)
    self:drawText(tr("NodeCount", tostring(#(block.nodes or {}))), self.width - 235, y + 5,
        0.75, 0.75, 0.75, 1, UIFont.Small)
    if #(block.nodes or {}) > 1 then
        local text = block.invertNodes and tr("Normal") or tr("Invert")
        self:drawText(text, self.width - self.removeWidth - self.invertWidth + 6, y + 5,
            0.4, 0.85, 1, 1, UIFont.Small)
    end
    self:drawText(tr("Remove"), self.width - self.removeWidth + 8, y + 5,
        1, 0.45, 0.4, 1, UIFont.Small)
    return y + item.height
end

--- Selects a row or invokes its remove, invert, or drag-handle action.
function EdgeBlockList:onMouseDown(x, y)
    local row = self:rowAt(x, y)
    local item = row and self.items[row]
    if not item then return end
    self.selected = row
    local block = item.item
    if x >= self.width - self.removeWidth then
        self.editor:removeBlock(block)
    elseif x >= self.width - self.removeWidth - self.invertWidth and #(block.nodes or {}) > 1 then
        block.invertNodes = not block.invertNodes or nil
        self.editor:setDirty()
    elseif x <= self.dragHandleWidth then
        self.dragItem = item
    end
end

--- Completes drag-and-drop reordering and synchronizes the draft edge array.
function EdgeBlockList:onMouseUp(x, y)
    if self.dragItem then
        local target = self:rowAt(x, y)
        if target < 1 then target = #self.items end
        if target > #self.items then target = #self.items end
        local source
        for index, item in ipairs(self.items) do
            if item == self.dragItem then source = index break end
        end
        if source and target and source ~= target then
            local moved = table.remove(self.items, source)
            table.insert(self.items, target, moved)
            local blocks = self.editor:getSelectedEdgeBlocks()
            local reordered = {}
            for _, item in ipairs(self.items) do table.insert(reordered, item.item) end
            for index = #blocks, 1, -1 do table.remove(blocks, index) end
            for _, block in ipairs(reordered) do table.insert(blocks, block) end
            self.editor:setDirty()
        end
    end
    self.dragItem = nil
end

--- Cancels an active row drag when the pointer is released outside the list.
function EdgeBlockList:onMouseUpOutside(x, y)
    self.dragItem = nil
end

local SimpleBlockList = ISScrollingListBox:derive("WaymanSimpleBlockList")

--- Creates the selectable list used for currently available node blocks.
function SimpleBlockList:new(x, y, width, height, editor)
    local o = ISScrollingListBox.new(self, x, y, width, height)
    o.editor = editor
    o.itemheight = ROW_H
    o.doDrawItem = SimpleBlockList.doDrawItem
    return o
end

--- Selects an available block and exposes it to the map overlay highlight.
function SimpleBlockList:onMouseDown(x, y)
    ISScrollingListBox.onMouseDown(self, x, y)
    local item = self.items[self.selected]
    Controller.selectedAvailableBlockId = item and item.item.blockId or nil
end

--- Draws one available block row with technical ID and node count.
function SimpleBlockList:doDrawItem(y, item, alt)
    if self.selected == item.index then self:drawRect(0, y, self.width, item.height, 0.25, 0.2, 0.55, 0.8) end
    self:drawRectBorder(0, y, self.width, item.height, 0.35, 0.7, 0.7, 0.7)
    self:drawText(item.item.blockId, 8, y + 5, 1, 1, 1, 1, UIFont.Small)
    self:drawText(tr("NodeCount", tostring(#(item.item.nodes or {}))), self.width - 90, y + 5,
        0.75, 0.75, 0.75, 1, UIFont.Small)
    return y + item.height
end

local GraphEditor = ISCollapsableWindowJoypad:derive("WaymanGraphEditor")

--- Initializes the editor through the vanilla collapsible-window lifecycle.
function GraphEditor:initialise()
    ISCollapsableWindowJoypad.initialise(self)
end

--- Lays out display toggles in as few rows as the current width permits.
function GraphEditor:layoutDisplayControls()
    if not self.showEdgesTick then return end
    local controls = {
        self.showEdgesTick,
        self.showNodesTick,
        self.showSelectedEdgeTick,
        self.showHighlightsTick,
    }
    local x = SPACING
    local y = self.height - 92
    local right = self.width - SPACING
    for _, control in ipairs(controls) do
        local label = control.options and control.options[1] or ""
        local textWidth = getTextManager():MeasureStringX(control.font, label)
        local width = control.leftMargin + control.boxSize + control.textGap + textWidth + 8
        if x > SPACING and x + width > right then
            x = SPACING
            y = y + 28
        end
        control:setX(x)
        control:setY(y)
        control:setWidth(width)
        x = x + width + DISPLAY_GAP
    end
    self.lastDisplayLayoutWidth = self.width
    self.lastDisplayLayoutHeight = self.height
end

--- Keeps responsive footer controls synchronized with interactive resizing.
function GraphEditor:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    if self.lastDisplayLayoutWidth ~= self.width
        or self.lastDisplayLayoutHeight ~= self.height then
        self:layoutDisplayControls()
    end
end

--- Claims Escape while the visible editor has keyboard focus.
function GraphEditor:isKeyConsumed(key)
    return self:getIsVisible() and key == Keyboard.KEY_ESCAPE
end

--- Hides the editor on Escape while preserving its current draft.
function GraphEditor:onKeyRelease(key)
    if self:getIsVisible() and key == Keyboard.KEY_ESCAPE then self:close() end
end

--- Constructs, initializes, and attaches a consistently sized action button.
local function addButton(parent, x, y, width, text, target, callback)
    local button = ISButton:new(x, y, width, BUTTON_H, text, target, callback)
    button:initialise()
    parent:addChild(button)
    return button
end

--- Creates a transparent content panel for an editor tab.
local function newPanel(width, height)
    local panel = ISPanel:new(0, 0, width, height)
    panel:initialise()
    panel.background = false
    panel.border = false
    return panel
end

--- Builds the three tabs, static display controls, and transaction footer.
function GraphEditor:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local contentY = self:titleBarHeight() + SPACING
    local footerH = 96
    self.tabs = ISTabPanel:new(SPACING, contentY, self.width - SPACING * 2,
        self.height - contentY - footerH)
    self.tabs:initialise()
    self.tabs:setAnchorRight(true)
    self.tabs:setAnchorBottom(true)
    self:addChild(self.tabs)

    self.edgesPanel = newPanel(self.tabs.width, self.tabs.height - self.tabs.tabHeight)
    self.switchesPanel = newPanel(self.tabs.width, self.tabs.height - self.tabs.tabHeight)
    self.nodesPanel = newPanel(self.tabs.width, self.tabs.height - self.tabs.tabHeight)
    for _, panel in ipairs({ self.edgesPanel, self.switchesPanel, self.nodesPanel }) do
        panel:setAnchorRight(true)
        panel:setAnchorBottom(true)
    end
    self.tabs:addView(tr("Edges"), self.edgesPanel)
    self.tabs:addView(tr("Switches"), self.switchesPanel)
    self.tabs:addView(tr("AvailableNodes"), self.nodesPanel)

    self.edgeCombo = ISComboBox:new(0, 8, 300, BUTTON_H, self, self.onEdgeSelected)
    self.edgeCombo:initialise()
    self.edgesPanel:addChild(self.edgeCombo)
    self.newEdgeId = ISTextEntryBox:new("", 310, 8, 170, BUTTON_H)
    self.newEdgeId:initialise()
    self.newEdgeId:setPlaceholderText(tr("OptionalId"))
    self.newEdgeId:instantiate()
    self.newEdgeId:setTooltip(tr("OptionalIdTooltip"))
    self.edgesPanel:addChild(self.newEdgeId)
    self.newEdgeButton = addButton(self.edgesPanel, 490, 8, 80, tr("New"), self, self.onNewEdge)
    self.deleteEdgeButton = addButton(self.edgesPanel, 580, 8, 90, tr("Delete"), self, self.onDeleteEdge)
    self.edgeList = EdgeBlockList:new(0, 43, self.edgesPanel.width,
        self.edgesPanel.height - 43, self)
    self.edgeList:initialise()
    self.edgeList:setAnchorRight(true)
    self.edgeList:setAnchorBottom(true)
    self.edgesPanel:addChild(self.edgeList)

    self.switchCombo = ISComboBox:new(0, 8, 330, BUTTON_H, self, self.onSwitchSelected)
    self.switchCombo:initialise()
    self.switchesPanel:addChild(self.switchCombo)
    self.legControls = {}
    for index, legName in ipairs({ "throat", "through", "diverge" }) do
        local y = 50 + (index - 1) * 52
        local label = ISLabel:new(0, y + 5, 20, tr("Leg_" .. legName),
            1, 1, 1, 1, UIFont.Small, true)
        label:initialise()
        self.switchesPanel:addChild(label)
        local edgeCombo = ISComboBox:new(110, y, 280, BUTTON_H, self, self.onSwitchLegChanged, legName)
        edgeCombo:initialise()
        self.switchesPanel:addChild(edgeCombo)
        local towardCombo = ISComboBox:new(400, y, 150, BUTTON_H, self, self.onSwitchLegChanged, legName)
        towardCombo:initialise()
        towardCombo:addOptionWithData("—", false)
        towardCombo:addOptionWithData(tr("TowardStart"), "start")
        towardCombo:addOptionWithData(tr("TowardEnd"), "end")
        self.switchesPanel:addChild(towardCombo)
        self.legControls[legName] = { edge = edgeCombo, toward = towardCombo }
    end

    self.availableList = SimpleBlockList:new(0, 8, self.nodesPanel.width,
        self.nodesPanel.height - 51, self)
    self.availableList:initialise()
    self.availableList:setAnchorRight(true)
    self.availableList:setAnchorBottom(true)
    self.nodesPanel:addChild(self.availableList)
    self.assignEdgeCombo = ISComboBox:new(0, self.nodesPanel.height - 34, 330, BUTTON_H,
        self, self.onAssignEdgeSelected)
    self.assignEdgeCombo:initialise()
    self.assignEdgeCombo:setAnchorTop(false)
    self.assignEdgeCombo:setAnchorBottom(true)
    self.nodesPanel:addChild(self.assignEdgeCombo)
    self.assignButton = addButton(self.nodesPanel, 340, self.nodesPanel.height - 34,
        100, tr("Assign"), self, self.onAssign)
    self.assignButton:setAnchorTop(false)
    self.assignButton:setAnchorBottom(true)

    local displayOptions = GraphDisplay.getOptions()
    local tickY = self.height - 92
    self.showEdgesTick = ISTickBox:new(SPACING, tickY, 190, 28, "", self, self.onDisplayChanged)
    self.showEdgesTick:initialise()
    self.showEdgesTick:addOption(tr("ShowAllEdges"))
    self.showEdgesTick:setSelected(1, displayOptions.showAllEdges)
    self.showEdgesTick:setAnchorTop(false)
    self.showEdgesTick:setAnchorBottom(true)
    self:addChild(self.showEdgesTick)
    self.showNodesTick = ISTickBox:new(SPACING, tickY, 210, 28, "", self, self.onDisplayChanged)
    self.showNodesTick:initialise()
    self.showNodesTick:addOption(tr("ShowAvailableNodes"))
    self.showNodesTick:setSelected(1, displayOptions.showAvailableNodes)
    self.showNodesTick:setAnchorTop(false)
    self.showNodesTick:setAnchorBottom(true)
    self:addChild(self.showNodesTick)
    self.showSelectedEdgeTick = ISTickBox:new(SPACING, tickY, 210, 28, "",
        self, self.onDisplayChanged)
    self.showSelectedEdgeTick:initialise()
    self.showSelectedEdgeTick:addOption(tr("ShowSelectedEdge"))
    self.showSelectedEdgeTick:setSelected(1, displayOptions.showSelectedEdge)
    self.showSelectedEdgeTick:setAnchorTop(false)
    self.showSelectedEdgeTick:setAnchorBottom(true)
    self:addChild(self.showSelectedEdgeTick)
    self.showHighlightsTick = ISTickBox:new(SPACING, tickY, 250, 28, "",
        self, self.onDisplayChanged)
    self.showHighlightsTick:initialise()
    self.showHighlightsTick:addOption(tr("ShowNetworkHighlights"))
    self.showHighlightsTick:setSelected(1, displayOptions.showWorldHighlights)
    self.showHighlightsTick:setAnchorTop(false)
    self.showHighlightsTick:setAnchorBottom(true)
    self:addChild(self.showHighlightsTick)

    local actionY = self.height - self:resizeWidgetHeight() - BUTTON_H - 8
    self.exportButton = addButton(self, self.width - 410, actionY, 90,
        tr("Export"), self, self.onExport)
    self.exportButton:setAnchorLeft(false)
    self.exportButton:setAnchorRight(true)
    self.exportButton:setAnchorTop(false)
    self.exportButton:setAnchorBottom(true)
    self.reloadButton = addButton(self, self.width - 310, actionY, 90,
        tr("Reload"), self, self.onReload)
    self.reloadButton:setAnchorLeft(false)
    self.reloadButton:setAnchorRight(true)
    self.reloadButton:setAnchorTop(false)
    self.reloadButton:setAnchorBottom(true)
    self.acceptButton = addButton(self, self.width - 210, actionY, 90,
        tr("Accept"), self, self.onAccept)
    self.acceptButton:setAnchorLeft(false)
    self.acceptButton:setAnchorRight(true)
    self.acceptButton:setAnchorTop(false)
    self.acceptButton:setAnchorBottom(true)
    self.cancelButton = addButton(self, self.width - 110, actionY, 90,
        tr("Cancel"), self, self.onCancel)
    self.cancelButton:setAnchorLeft(false)
    self.cancelButton:setAnchorRight(true)
    self.cancelButton:setAnchorTop(false)
    self.cancelButton:setAnchorBottom(true)
    self.statusLabel = ISLabel:new(SPACING, actionY + 5, 20, "", 0.8, 0.8, 0.8, 1,
        UIFont.Small, true)
    self.statusLabel:initialise()
    self.statusLabel:setAnchorTop(false)
    self.statusLabel:setAnchorBottom(true)
    self:addChild(self.statusLabel)
    self:layoutDisplayControls()
    self:refreshAll()
end

--- Writes the last authoritative world-data snapshot to the game log.
function GraphEditor:onExport()
    local worldData = ModData.get(WORLD_DATA_KEY)
    if not worldData then
        self.statusLabel:setName(tr("StatusNoWorldData"))
        return
    end
    local json, reason = GraphData.worldDataToJSON(worldData)
    if not json then
        self.statusLabel:setName(tr("StatusExportFailed", tostring(reason)))
        return
    end
    print("[RailroaderWayman] WORLD_DATA_JSON " .. json)
    self.statusLabel:setName(tr("StatusExported"))
end

--- Returns the technical ID selected in the Edges tab.
function GraphEditor:getSelectedEdgeId()
    return comboData(self.edgeCombo)
end

--- Returns the mutable draft block array for the selected edge.
function GraphEditor:getSelectedEdgeBlocks()
    return self.draft.edges[self:getSelectedEdgeId()] or {}
end

--- Marks the shared editor draft as modified and updates footer status.
function GraphEditor:setDirty()
    self.dirty = true
    self.statusLabel:setName(tr("StatusUnsavedChanges"))
    GraphDisplay.refresh(self.draft)
end

--- Rebuilds every edge-dependent selector after graph structure changes.
function GraphEditor:refreshEdgeCombos(selected)
    fillEdgeCombo(self.edgeCombo, self.draft.edges, false, selected or self:getSelectedEdgeId())
    fillEdgeCombo(self.assignEdgeCombo, self.draft.edges, true, false)
    for _, controls in pairs(self.legControls or {}) do
        local prior = comboData(controls.edge)
        fillEdgeCombo(controls.edge, self.draft.edges, true, prior)
    end
    self.deleteEdgeButton:setEnable(self.edgeCombo:getOptionCount() > 0)
    self.assignButton:setEnable(comboData(self.assignEdgeCombo) ~= nil)
end

--- Rebuilds the ordered rows for the currently selected edge.
function GraphEditor:refreshEdgeList()
    self.edgeList:clear()
    for _, block in ipairs(self:getSelectedEdgeBlocks()) do self.edgeList:addItem(block.blockId, block) end
end

--- Rebuilds available-block rows and clears stale map selections.
function GraphEditor:refreshAvailable()
    self.availableList:clear()
    local selectedExists = false
    for _, block in ipairs(self.draft.availableNodes) do
        self.availableList:addItem(block.blockId, block)
        if block.blockId == Controller.selectedAvailableBlockId then selectedExists = true end
    end
    if not selectedExists then Controller.selectedAvailableBlockId = nil end
end

--- Rebuilds the switch selector while preserving the requested switch ID.
function GraphEditor:refreshSwitches(selected)
    clearCombo(self.switchCombo)
    for _, switch in ipairs(self.draft.switches) do
        self.switchCombo:addOptionWithData(switch.id, switch.id)
    end
    if selected then self.switchCombo:setSelectedData(selected) end
    self:onSwitchSelected()
end

--- Refreshes every tab from the current shared draft.
function GraphEditor:refreshAll()
    local edge = self:getSelectedEdgeId()
    self:refreshEdgeCombos(edge)
    self:refreshEdgeList()
    self:refreshAvailable()
    self:refreshSwitches(comboData(self.switchCombo))
end

--- Updates edge rows and map highlighting after selector changes.
function GraphEditor:onEdgeSelected(_combo)
    Controller.selectedEdgeId = self:getSelectedEdgeId()
    self:refreshEdgeList()
end

--- Creates an empty draft edge using a validated custom or generated ID.
function GraphEditor:onNewEdge()
    local id = self.newEdgeId:getText():match("^%s*(.-)%s*$")
    if id == "" then
        local candidate = self.draft.nextEdgeId or 1
        repeat
            id = "edge_" .. tostring(candidate)
            candidate = candidate + 1
        until not self.draft.edges[id]
    elseif not id:match("^[%w_.%-]+$") then
        self.statusLabel:setName(tr("StatusInvalidId"))
        return
    elseif self.draft.edges[id] then
        self.statusLabel:setName(tr("StatusEdgeExists", id))
        return
    end
    self.draft.edges[id] = {}
    self.newEdgeId:setText("")
    self:refreshEdgeCombos(id)
    self:onEdgeSelected()
    self:setDirty()
end

--- Deletes the selected draft edge and returns its blocks to availability.
function GraphEditor:onDeleteEdge()
    local edgeId = self:getSelectedEdgeId()
    local blocks = edgeId and self.draft.edges[edgeId]
    if not blocks then return end
    for _, block in ipairs(blocks) do
        block.invertNodes = nil
        table.insert(self.draft.availableNodes, block)
    end
    self.draft.edges[edgeId] = nil
    for _, switch in ipairs(self.draft.switches) do
        for _, legName in ipairs({ "throat", "through", "diverge" }) do
            if switch.legs[legName].edge == edgeId then switch.legs[legName] = {} end
        end
    end
    Controller.selectedEdgeId = nil
    self:refreshAll()
    self:setDirty()
end

--- Removes one indivisible block from its edge and restores availability.
function GraphEditor:removeBlock(block)
    local blocks = self:getSelectedEdgeBlocks()
    for index, candidate in ipairs(blocks) do
        if candidate == block then table.remove(blocks, index) break end
    end
    block.invertNodes = nil
    table.insert(self.draft.availableNodes, block)
    self:refreshEdgeList()
    self:refreshAvailable()
    self:setDirty()
end

--- Appends the selected available block to the chosen target edge.
function GraphEditor:onAssign()
    local item = self.availableList.items[self.availableList.selected]
    local edgeId = comboData(self.assignEdgeCombo)
    if not item or not edgeId then return end
    for index, block in ipairs(self.draft.availableNodes) do
        if block == item.item then table.remove(self.draft.availableNodes, index) break end
    end
    table.insert(self.draft.edges[edgeId], item.item)
    Controller.selectedAvailableBlockId = nil
    self.edgeCombo:setSelectedData(edgeId)
    self:onEdgeSelected()
    self:refreshAvailable()
    self:setDirty()
end

--- Enables assignment only while a real target edge is selected.
function GraphEditor:onAssignEdgeSelected()
    self.assignButton:setEnable(comboData(self.assignEdgeCombo) ~= nil)
end

--- Resolves the selected switch object from the draft switch list.
function GraphEditor:getSelectedSwitch()
    local id = comboData(self.switchCombo)
    for _, switch in ipairs(self.draft.switches) do if switch.id == id then return switch end end
end

--- Loads all three leg controls for the newly selected switch.
function GraphEditor:onSwitchSelected(_combo)
    local switch = self:getSelectedSwitch()
    self.updatingSwitch = true
    for legName, controls in pairs(self.legControls) do
        local leg = switch and switch.legs[legName] or {}
        fillEdgeCombo(controls.edge, self.draft.edges, true, leg.edge or false)
        controls.toward:setSelectedData(leg.toward or false)
    end
    self.updatingSwitch = false
end

--- Stores one switch leg while enforcing paired edge/toward values.
function GraphEditor:onSwitchLegChanged(_combo, legName)
    if self.updatingSwitch then return end
    local switch = self:getSelectedSwitch()
    local controls = self.legControls[legName]
    if not switch or not controls then return end
    local edge = comboData(controls.edge)
    local toward = comboData(controls.toward)
    if edge and not toward then
        toward = "start"
        self.updatingSwitch = true
        controls.toward:setSelectedData(toward)
        self.updatingSwitch = false
    elseif toward and not edge then
        toward = nil
        self.updatingSwitch = true
        controls.toward:setSelectedData(false)
        self.updatingSwitch = false
    end
    switch.legs[legName] = edge and toward and { edge = edge, toward = toward } or {}
    self:setDirty()
end

--- Updates local-only map and world-highlight visibility controls.
function GraphEditor:onDisplayChanged()
    GraphDisplay.setOptions({
        showAllEdges = self.showEdgesTick:isSelected(1),
        showAvailableNodes = self.showNodesTick:isSelected(1),
        showSelectedEdge = self.showSelectedEdgeTick:isSelected(1),
        showWorldHighlights = self.showHighlightsTick:isSelected(1),
    }, self.draft)
end

--- Validates locally and submits the complete draft as one server transaction.
function GraphEditor:onAccept()
    for _, blocks in pairs(self.draft.edges) do
        if #blocks == 0 then self.statusLabel:setName(tr("StatusEmptyEdge")) return end
    end
    local confirmed = ModData.get(WORLD_DATA_KEY)
    if confirmed then
        local valid, reason = GraphData.validateDraft(confirmed, self.draft)
        if not valid then self.statusLabel:setName(tr("StatusCannotSave", tostring(reason))) return end
    end
    self.statusLabel:setName(tr("StatusSaving"))
    self.awaitingSave = true
    if isClient() then
        local player = getSpecificPlayer(0) or getPlayer()
        sendClientCommand(player, "RailroaderWayman", "applyGraph", {
            revision = self.baseRevision,
            draft = self.draft,
        })
    else
        local ok, reason = RailroaderWaymanEntityRuntime.ApplyGraphDraft(self.draft, self.baseRevision)
        if not ok then
            self:onRejected(reason)
        else
            self:onWorldData(ModData.get(WORLD_DATA_KEY))
        end
    end
end

--- Discards the draft and requests a fresh authoritative graph snapshot.
function GraphEditor:onReload()
    self.reloadPending = true
    self.statusLabel:setName(tr("StatusReloading"))
    if isClient() then
        ModData.request(WORLD_DATA_KEY)
        return
    end
    self:onWorldData(ModData.get(WORLD_DATA_KEY))
end

--- Discards the local draft by closing the editor without submission.
function GraphEditor:onCancel()
    self:discardAndClose()
end

--- Hides the editor while retaining its draft for the next open action.
function GraphEditor:close()
    self:setVisible(false)
end

--- Explicitly discards the draft and destroys the singleton editor instance.
function GraphEditor:discardAndClose()
    self:setVisible(false)
    self:removeFromUIManager()
    if Controller.instance == self then Controller.instance = nil end
    GraphDisplay.refresh(ModData.get(WORLD_DATA_KEY))
end

--- Displays a server rejection and allows the user to continue editing.
function GraphEditor:onRejected(reason)
    self.awaitingSave = false
    self.statusLabel:setName(tr("StatusRejected", tostring(reason)))
end

--- Replaces a pending draft after authoritative save confirmation arrives.
function GraphEditor:onWorldData(data)
    if type(data) ~= "table" then
        if self.reloadPending then
            self.reloadPending = false
            self.statusLabel:setName(tr("StatusNoServerData"))
        end
        return
    end
    if not self.reloadPending and not self.awaitingSave then return end
    if self.awaitingSave and not self.reloadPending
        and (data.revision or 0) <= self.baseRevision then return end
    local wasReload = self.reloadPending
    self.reloadPending = false
    self.awaitingSave = false
    self.baseRevision = data.revision or 0
    self.draft = GraphData.copy(data)
    GraphDisplay.refresh(self.draft)
    self.dirty = false
    self.statusLabel:setName(wasReload and tr("StatusReloaded") or tr("StatusSaved"))
    self:refreshAll()
end

--- Constructs a resizable editor with an isolated copy of confirmed graph data.
function GraphEditor:new(x, y, width, height, data)
    local o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    o.title = tr("WindowTitle")
    o.resizable = true
    o.minimumWidth = 700
    o.minimumHeight = 420
    o.draft = GraphData.copy(GraphData.ensure(data or {}))
    o.baseRevision = o.draft.revision or 0
    o.tempCounter = 0
    o.dirty = false
    o:setWantKeyEvents(true)
    return o
end

--- Opens or focuses the singleton graph-editor window.
function Controller.open(data)
    if Controller.instance then
        Controller.instance:setVisible(true)
        Controller.instance:bringToTop()
        return Controller.instance
    end
    local width, height = 700, 560
    local x = math.max(0, (getCore():getScreenWidth() - width) / 2)
    local y = math.max(0, (getCore():getScreenHeight() - height) / 2)
    local editor = GraphEditor:new(x, y, width, height, data)
    editor:initialise()
    editor:addToUIManager()
    Controller.instance = editor
    return editor
end

--- Exposes read-only draft/selection/display state to the map renderer.
function Controller.getOverlayState(confirmedData)
    local editor = Controller.instance
    local options = GraphDisplay.getOptions()
    return {
        data = editor and editor.draft or confirmedData,
        selectedEdgeId = editor and editor:getSelectedEdgeId() or nil,
        selectedAvailableBlockId = editor and Controller.selectedAvailableBlockId or nil,
        showAllEdges = options.showAllEdges,
        showAvailableNodes = options.showAvailableNodes,
        showSelectedEdge = options.showSelectedEdge,
    }
end

--- Delivers authoritative global data to the active editor, when present.
function Controller.onWorldData(data)
    if Controller.instance then Controller.instance:onWorldData(data) end
end

--- Delivers an authoritative graph rejection to the active editor.
function Controller.onRejected(reason)
    if Controller.instance then Controller.instance:onRejected(reason) end
end

return Controller
