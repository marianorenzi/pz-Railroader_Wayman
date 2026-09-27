-- Standalone graph-editing window and controller. It owns an isolated draft,
-- edits edges/switch legs/node-block assignments, submits one atomic server
-- transaction, and updates shared visualization options without owning renderers.
require "Wayman/WaymanGraphData"
require "Wayman/WaymanGraphDisplay"
require "Wayman/WaymanLocalization"
require "Wayman/WaymanNodeBlockTable"
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

--- Restores saved session bounds while keeping the window on the current screen.
local function windowBounds(state, defaultWidth, defaultHeight)
    state = state or {}
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local width = math.min(state.width or defaultWidth, screenWidth)
    local height = math.min(state.height or defaultHeight, screenHeight)
    local x = state.x or math.floor((screenWidth - width) / 2)
    local y = state.y or math.floor((screenHeight - height) / 2)
    x = math.max(0, math.min(x, screenWidth - width))
    y = math.max(0, math.min(y, screenHeight - height))
    return x, y, width, height
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
    if includeEmpty then combo:addOptionWithData(WaymanLocalization.ui("Unassigned"), false) end
    for _, edgeId in ipairs(sortedKeys(edges)) do combo:addOptionWithData(edgeId, edgeId) end
    if selected ~= nil then combo:setSelectedData(selected or false) end
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
end

--- Adaptative layour for node lists and actions.
function GraphEditor:layoutNodeLists()
    -- Update positions and sizes:
        -- edgeList.width, edgeList.height
        -- availableList.x, availableList.width, availableList.height
        -- assignButton, unassignButton, moveUpButton, moveDownButton, invertButton

    local buttonWidth = 120
    local availableWidth = self.edgesPanel.width - buttonWidth - SPACING * 2
    local listWidth = math.max(120, math.floor(availableWidth / 2))
    local listHeight = self.edgesPanel.height - 43

    -- edge node block lists
    self.edgeList:setWidth(listWidth)
    self.edgeList:setHeight(listHeight)

    -- buttons
    local buttonY = 43
    local buttonX = self.edgeList.x + listWidth + SPACING
    self.assignButton:setX(buttonX)
    self.assignButton:setY(buttonY)
    buttonY = buttonY + BUTTON_H + SPACING
    self.unassignButton:setX(buttonX)
    self.unassignButton:setY(buttonY)
    buttonY = buttonY + BUTTON_H + SPACING
    self.moveUpButton:setX(buttonX)
    self.moveUpButton:setY(buttonY)
    buttonY = buttonY + BUTTON_H + SPACING
    self.moveDownButton:setX(buttonX)
    self.moveDownButton:setY(buttonY)
    buttonY = buttonY + BUTTON_H + SPACING
    self.invertButton:setX(buttonX)
    self.invertButton:setY(buttonY)

    -- available node block list
    self.availableList:setX(self.assignButton.x + buttonWidth + SPACING)
    self.availableList:setWidth(listWidth)
    self.availableList:setHeight(listHeight)
end

--- Keeps responsive footer controls synchronized with interactive resizing.
function GraphEditor:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    if self.lastDisplayLayoutWidth ~= self.width or self.lastDisplayLayoutHeight ~= self.height then
        self:layoutDisplayControls()
        self:layoutNodeLists()

        self.lastDisplayLayoutWidth = self.width
        self.lastDisplayLayoutHeight = self.height
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

--- Selects a row through the NodeBlockTable's inner list and notifies its owner.
local function selectBlockAt(blockTable, index)
    local item = index and blockTable.data.items[index] or nil
    blockTable.data.selected = item and index or -1
    blockTable.data.block = item and item.item or nil
    blockTable.onBlockSelected(blockTable.data.block, blockTable.data.selected)
end

--- Clears a NodeBlockTable selection and synchronizes its action controls.
local function clearBlockSelection(blockTable)
    selectBlockAt(blockTable, nil)
end

--- Creates a transparent content panel for an editor tab.
local function newPanel(width, height)
    local panel = ISPanel:new(0, 0, width, height)
    panel:initialise()
    panel.background = false
    panel.border = false
    return panel
end

function GraphEditor:createEdgePanel()
    -- Edges panel
    self.edgeCombo = ISComboBox:new(0, 8, 300, BUTTON_H, self, self.onEdgeSelected)
    self.edgeCombo:initialise()
    self.edgesPanel:addChild(self.edgeCombo)
    self.newEdgeId = ISTextEntryBox:new("", self.edgeCombo.width + SPACING, 8, 170, BUTTON_H)
    self.newEdgeId:initialise()
    self.newEdgeId:setPlaceholderText(WaymanLocalization.ui("OptionalId"))
    self.newEdgeId:instantiate()
    self.newEdgeId:setTooltip(WaymanLocalization.ui("OptionalIdTooltip"))
    self.edgesPanel:addChild(self.newEdgeId)
    self.newEdgeButton = addButton(self.edgesPanel, self.newEdgeId.x + self.newEdgeId.width + SPACING, 8, 80, WaymanLocalization.ui("New"), self, self.onNewEdge)
    self.deleteEdgeButton = addButton(self.edgesPanel, self.newEdgeButton.x + self.newEdgeButton.width + SPACING, 8, 90, WaymanLocalization.ui("Delete"), self, self.onDeleteEdge)

    local buttonWidth = 120
    local availableWidth = self.edgesPanel.width - buttonWidth - SPACING * 2
    local listWidth = math.max(120, math.floor(availableWidth / 2))
    local listHeight = self.edgesPanel.height - 43
    -- Edge node block list
    self.edgeList = NodeBlockTable:new(0, 43, listWidth, listHeight, WaymanLocalization.ui("EdgeBlocks"))
    self.edgeList:initialise()
    self.edgeList.onBlockSelected = function(block, index) 
        self.unassignButton:setEnable(block ~= nil)
        self.moveUpButton:setEnable(block ~= nil and index > 1)
        self.moveDownButton:setEnable(block ~= nil and index < #(self.edgeList:getBlocks()))
        self.invertButton:setEnable(block and #(block.nodes or {}) > 1)
    end
    self.edgesPanel:addChild(self.edgeList)

    -- Edge node operation buttons
    local buttonY = 43
    local buttonX = self.edgeList.x + listWidth + SPACING
    self.assignButton = addButton(self.edgesPanel, buttonX, buttonY, buttonWidth, WaymanLocalization.ui("Assign"), self, self.onAssign)
    self.assignButton:setEnable(false)
    buttonY = buttonY + BUTTON_H + SPACING
    self.unassignButton = addButton(self.edgesPanel, buttonX, buttonY, buttonWidth, WaymanLocalization.ui("Unassign"), self, self.onUnassign)
    self.unassignButton:setEnable(false)
    buttonY = buttonY + BUTTON_H + SPACING
    self.moveUpButton = addButton(self.edgesPanel, buttonX, buttonY, buttonWidth, WaymanLocalization.ui("MoveUp"), self, self.onMoveUp)
    self.moveUpButton:setEnable(false)
    buttonY = buttonY + BUTTON_H + SPACING
    self.moveDownButton = addButton(self.edgesPanel, buttonX, buttonY, buttonWidth, WaymanLocalization.ui("MoveDown"), self, self.onMoveDown)
    self.moveDownButton:setEnable(false)
    buttonY = buttonY + BUTTON_H + SPACING
    self.invertButton = addButton(self.edgesPanel, buttonX, buttonY, buttonWidth, WaymanLocalization.ui("Invert"), self, self.onInvert)
    self.invertButton:setEnable(false)

    -- Available node block list
    self.availableList = NodeBlockTable:new(self.assignButton.x + buttonWidth + SPACING, 43, listWidth, listHeight, WaymanLocalization.ui("AvailableBlocks"))
    self.availableList:initialise()
    self.availableList.onBlockSelected = function(block) 
        self.assignButton:setEnable(block ~= nil)
        Controller.selectedAvailableBlockId = block and block.blockId or nil
    end
    self.edgesPanel:addChild(self.availableList)

    -- Update positions
    self:layoutNodeLists()
end

--- Builds the three tabs, static display controls, and transaction footer.
function GraphEditor:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local contentY = self:titleBarHeight() + SPACING
    local footerH = 96

    -- Tabs
    self.tabs = ISTabPanel:new(SPACING, contentY, self.width - SPACING * 2,
        self.height - contentY - footerH)
    self.tabs:initialise()
    self.tabs:setAnchorRight(true)
    self.tabs:setAnchorBottom(true)
    self:addChild(self.tabs)

    -- Tab content panels
    self.edgesPanel = newPanel(self.tabs.width, self.tabs.height - self.tabs.tabHeight)
    self.switchesPanel = newPanel(self.tabs.width, self.tabs.height - self.tabs.tabHeight)
    for _, panel in ipairs({ self.edgesPanel, self.switchesPanel }) do
        panel:setAnchorRight(true)
        panel:setAnchorBottom(true)
    end
    self.tabs:addView(WaymanLocalization.ui("Edges"), self.edgesPanel)
    self.tabs:addView(WaymanLocalization.ui("Switches"), self.switchesPanel)

    -- Edge panel
    self:createEdgePanel()

    -- Switches panel
    self.switchCombo = ISComboBox:new(0, 8, 330, BUTTON_H, self, self.onSwitchSelected)
    self.switchCombo:initialise()
    self.switchesPanel:addChild(self.switchCombo)
    self.legControls = {}
    for index, legName in ipairs({ "throat", "through", "diverge" }) do
        local y = 50 + (index - 1) * 52
        local label = ISLabel:new(0, y + 5, 20, WaymanLocalization.ui("Leg_" .. legName),
            1, 1, 1, 1, UIFont.Small, true)
        label:initialise()
        self.switchesPanel:addChild(label)
        local edgeCombo = ISComboBox:new(110, y, 280, BUTTON_H, self, self.onSwitchLegChanged, legName)
        edgeCombo:initialise()
        self.switchesPanel:addChild(edgeCombo)
        local towardCombo = ISComboBox:new(400, y, 150, BUTTON_H, self, self.onSwitchLegChanged, legName)
        towardCombo:initialise()
        towardCombo:addOptionWithData("—", false)
        towardCombo:addOptionWithData(WaymanLocalization.ui("TowardStart"), "start")
        towardCombo:addOptionWithData(WaymanLocalization.ui("TowardEnd"), "end")
        self.switchesPanel:addChild(towardCombo)
        self.legControls[legName] = { edge = edgeCombo, toward = towardCombo }
    end

    -- Footer controls
    local displayOptions = GraphDisplay.getOptions()
    local tickY = self.height - 92
    self.showEdgesTick = ISTickBox:new(SPACING, tickY, 190, 28, "", self, self.onDisplayChanged)
    self.showEdgesTick:initialise()
    self.showEdgesTick:addOption(WaymanLocalization.ui("ShowAllEdges"))
    self.showEdgesTick:setSelected(1, displayOptions.showAllEdges)
    self.showEdgesTick:setAnchorTop(false)
    self.showEdgesTick:setAnchorBottom(true)
    self:addChild(self.showEdgesTick)
    self.showNodesTick = ISTickBox:new(SPACING, tickY, 210, 28, "", self, self.onDisplayChanged)
    self.showNodesTick:initialise()
    self.showNodesTick:addOption(WaymanLocalization.ui("ShowAvailableNodes"))
    self.showNodesTick:setSelected(1, displayOptions.showAvailableNodes)
    self.showNodesTick:setAnchorTop(false)
    self.showNodesTick:setAnchorBottom(true)
    self:addChild(self.showNodesTick)
    self.showSelectedEdgeTick = ISTickBox:new(SPACING, tickY, 210, 28, "",
        self, self.onDisplayChanged)
    self.showSelectedEdgeTick:initialise()
    self.showSelectedEdgeTick:addOption(WaymanLocalization.ui("ShowSelectedEdge"))
    self.showSelectedEdgeTick:setSelected(1, displayOptions.showSelectedEdge)
    self.showSelectedEdgeTick:setAnchorTop(false)
    self.showSelectedEdgeTick:setAnchorBottom(true)
    self:addChild(self.showSelectedEdgeTick)
    self.showHighlightsTick = ISTickBox:new(SPACING, tickY, 250, 28, "",
        self, self.onDisplayChanged)
    self.showHighlightsTick:initialise()
    self.showHighlightsTick:addOption(WaymanLocalization.ui("ShowNetworkHighlights"))
    self.showHighlightsTick:setSelected(1, displayOptions.showWorldHighlights)
    self.showHighlightsTick:setAnchorTop(false)
    self.showHighlightsTick:setAnchorBottom(true)
    self:addChild(self.showHighlightsTick)

    -- Footer buttons and status
    local actionY = self.height - self:resizeWidgetHeight() - BUTTON_H - 8
    self.exportButton = addButton(self, self.width - 410, actionY, 90,
        WaymanLocalization.ui("Export"), self, self.onExport)
    self.exportButton:setAnchorLeft(false)
    self.exportButton:setAnchorRight(true)
    self.exportButton:setAnchorTop(false)
    self.exportButton:setAnchorBottom(true)
    self.reloadButton = addButton(self, self.width - 310, actionY, 90,
        WaymanLocalization.ui("Reload"), self, self.onReload)
    self.reloadButton:setAnchorLeft(false)
    self.reloadButton:setAnchorRight(true)
    self.reloadButton:setAnchorTop(false)
    self.reloadButton:setAnchorBottom(true)
    self.acceptButton = addButton(self, self.width - 210, actionY, 90,
        WaymanLocalization.ui("Accept"), self, self.onAccept)
    self.acceptButton:setAnchorLeft(false)
    self.acceptButton:setAnchorRight(true)
    self.acceptButton:setAnchorTop(false)
    self.acceptButton:setAnchorBottom(true)
    self.cancelButton = addButton(self, self.width - 110, actionY, 90,
        WaymanLocalization.ui("Cancel"), self, self.onCancel)
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
        self.statusLabel:setName(WaymanLocalization.ui("StatusNoWorldData"))
        return
    end
    local json, reason = GraphData.worldDataToJSON(worldData)
    if not json then
        self.statusLabel:setName(WaymanLocalization.ui("StatusExportFailed", tostring(reason)))
        return
    end
    print("[RailroaderWayman] WORLD_DATA_JSON " .. json)
    self.statusLabel:setName(WaymanLocalization.ui("StatusExported"))
end

--- Returns the technical ID selected in the Edges tab.
function GraphEditor:getSelectedEdgeId()
    return comboData(self.edgeCombo)
end

--- Returns the mutable draft block array for the selected edge.
function GraphEditor:getSelectedEdgeBlocks()
    return self.draft.edges[self:getSelectedEdgeId()] or {}
end

--- Returns the selected mutable draft node block and its index for the selected edge.
function GraphEditor:getSelectedEdgeBlock()
    local block, index = self.edgeList:getSelectedBlock()
    if not block or not index or index < 1 then return nil, nil end

    local blocks = self:getSelectedEdgeBlocks()

    -- Verifies that the item still belongs to the selected edge.
    if blocks[index] ~= block then return nil, nil end

    return block, index
end

--- Marks the shared editor draft as modified and updates footer status.
function GraphEditor:setDirty()
    self.dirty = true
    self.statusLabel:setName(WaymanLocalization.ui("StatusUnsavedChanges"))
    GraphDisplay.refresh(self.draft)
end

--- Rebuilds every edge-dependent selector after graph structure changes.
function GraphEditor:refreshEdgeCombos(selected)
    fillEdgeCombo(self.edgeCombo, self.draft.edges, false, selected or self:getSelectedEdgeId())
    for _, controls in pairs(self.legControls or {}) do
        local prior = comboData(controls.edge)
        fillEdgeCombo(controls.edge, self.draft.edges, true, prior)
    end
    self.deleteEdgeButton:setEnable(self.edgeCombo:getOptionCount() > 0)
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
        self.statusLabel:setName(WaymanLocalization.ui("StatusInvalidId"))
        return
    elseif self.draft.edges[id] then
        self.statusLabel:setName(WaymanLocalization.ui("StatusEdgeExists", id))
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

--- Appends the selected available block to the chosen target edge.
function GraphEditor:onAssign()
    local block = self.availableList:getSelectedBlock()
    local edgeId = self:getSelectedEdgeId()
    local blocks = self.draft.edges[edgeId]
    if not block or not edgeId or not blocks then return end

    local availableIndex
    for index, availableBlock in ipairs(self.draft.availableNodes) do
        if availableBlock == block then
            availableIndex = index
            break
        end
    end

    if not availableIndex then return end

    table.remove(self.draft.availableNodes, availableIndex)
    table.insert(blocks, block)
    
    Controller.selectedAvailableBlockId = nil
    clearBlockSelection(self.availableList)
    self:refreshEdgeList()
    self:refreshAvailable()
    self:setDirty()
end

--- Removes the selected edge node block from the edge.
function GraphEditor:onUnassign()
    local block, index = self:getSelectedEdgeBlock()
    local blocks = self:getSelectedEdgeBlocks()
    if not block or not index or index < 1 or index > #blocks then return end

    table.remove(blocks, index)
    block.invertNodes = nil
    table.insert(self.draft.availableNodes, block)

    clearBlockSelection(self.edgeList)
    self:refreshEdgeList()
    self:refreshAvailable()
    self:setDirty()
end

--- Moves up the selected edge node block.
function GraphEditor:onMoveUp()
    local block, index = self:getSelectedEdgeBlock()
    local blocks = self:getSelectedEdgeBlocks()

    if not block or not index or index <= 1 then return end

    blocks[index], blocks[index - 1] = blocks[index - 1], blocks[index]

    self:refreshEdgeList()
    selectBlockAt(self.edgeList, index - 1)
    self:setDirty()
end

--- Moves down the selected edge node block.
function GraphEditor:onMoveDown()
    local block, index = self:getSelectedEdgeBlock()
    local blocks = self:getSelectedEdgeBlocks()

    if not block or not index or index >= #blocks then return end

    blocks[index], blocks[index + 1] = blocks[index + 1], blocks[index]

    self:refreshEdgeList()
    selectBlockAt(self.edgeList, index + 1)
    self:setDirty()
end

--- Inverts the selected edge node block.
function GraphEditor:onInvert()
    local block, index = self:getSelectedEdgeBlock()
    if not index or not block or #block.nodes <= 1 then return end

    block.invertNodes = not block.invertNodes or nil
    self:setDirty()
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
        if #blocks == 0 then self.statusLabel:setName(WaymanLocalization.ui("StatusEmptyEdge")) return end
    end
    local confirmed = ModData.get(WORLD_DATA_KEY)
    if confirmed then
        local valid, reason = GraphData.validateDraft(confirmed, self.draft)
        if not valid then self.statusLabel:setName(WaymanLocalization.ui("StatusCannotSave", tostring(reason))) return end
    end
    self.statusLabel:setName(WaymanLocalization.ui("StatusSaving"))
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
    self.statusLabel:setName(WaymanLocalization.ui("StatusReloading"))
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
    self:saveWindowState()
    self:setVisible(false)
end

--- Remembers this editor's bounds for the remainder of the game session.
function GraphEditor:saveWindowState()
    Controller.windowState = {
        x = self.x,
        y = self.y,
        width = self.width,
        height = self.height,
    }
end

--- Explicitly discards the draft and destroys the singleton editor instance.
function GraphEditor:discardAndClose()
    self:saveWindowState()
    self:setVisible(false)
    self:removeFromUIManager()
    if Controller.instance == self then Controller.instance = nil end
    GraphDisplay.refresh(ModData.get(WORLD_DATA_KEY))
end

--- Displays a server rejection and allows the user to continue editing.
function GraphEditor:onRejected(reason)
    self.awaitingSave = false
    self.statusLabel:setName(WaymanLocalization.ui("StatusRejected", tostring(reason)))
end

--- Replaces a pending draft after authoritative save confirmation arrives.
function GraphEditor:onWorldData(data)
    if type(data) ~= "table" then
        if self.reloadPending then
            self.reloadPending = false
            self.statusLabel:setName(WaymanLocalization.ui("StatusNoServerData"))
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
    self.statusLabel:setName(wasReload and WaymanLocalization.ui("StatusReloaded") or WaymanLocalization.ui("StatusSaved"))
    self:refreshAll()
end

--- Constructs a resizable editor with an isolated copy of confirmed graph data.
function GraphEditor:new(x, y, width, height, data)
    local o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    o.title = WaymanLocalization.ui("WindowTitle")
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
    local x, y, width, height = windowBounds(Controller.windowState, 700, 560)
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
