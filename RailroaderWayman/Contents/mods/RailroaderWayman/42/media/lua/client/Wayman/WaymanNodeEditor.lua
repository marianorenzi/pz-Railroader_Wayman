-- Editor for the relative geometry stored on one physical Wayman entity.
require "Wayman/WaymanEntityDescriptor"
require "Wayman/WaymanWorldHighlights"
require "Wayman/WaymanLocalization"
require "Wayman/WaymanNodeBlockTable"
require "Wayman/WaymanNodeTable"
require "ISUI/ISButton"
require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISLabel"
require "ISUI/ISPanel"

RailroaderWaymanNodeEditor = RailroaderWaymanNodeEditor or {}
local Controller = RailroaderWaymanNodeEditor
local Descriptor = RailroaderWaymanEntityDescriptor
local Highlights = RailroaderWaymanWorldHighlights
local OBJECT_DATA_KEY = "railroaderWayman"
local HIGHLIGHT_GROUP = "node-editor"
local HOVER_HIGHLIGHT_GROUP = "node-editor-hover"
local SPACING, BUTTON_H = 10, 25

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

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function addButton(parent, x, y, width, text, target, callback)
    local button = ISButton:new(x, y, width, BUTTON_H, text, target, callback)
    button:initialise()
    parent:addChild(button)
    return button
end

local function blockColor(id)
    if id == "at" then return Highlights.colors.at end
    if id == "switch" then return Highlights.colors.switch end
    if id == "throughNodes" then return Highlights.colors.through end
    if id == "divergingNodes" then return Highlights.colors.diverge end
    return Highlights.colors.nodes
end

local function colorWithAlpha(color, alpha)
    return { r = color.r, g = color.g, b = color.b, a = alpha }
end

--- Returns the loaded world square currently under the mouse cursor.
local function squareAtMouse(editor)
    local player = getSpecificPlayer(editor.playerNum) or getPlayer()
    if not player then return nil end
    local z = math.floor(player:getZ())
    local x = math.floor(screenToIsoX(editor.playerNum, getMouseX(), getMouseY(), z))
    local y = math.floor(screenToIsoY(editor.playerNum, getMouseX(), getMouseY(), z))
    return getCell():getGridSquare(x, y, z)
end

local function readBlocks(instance)
    local blocks = {}
    local function add(id, singleton)
        local value, isDefault = Descriptor.instanceDataValueOrDefault(instance, id)
        local nodes = singleton and (value and { copy(value) } or {}) or copy(value or {})
        table.insert(blocks, {
            blockId = id,
            nodes = nodes,
            singleton = singleton,
            isDefault = isDefault,
            origin = copy(instance.origin),
        })
    end
    if instance.defaults.kind == "turn" then
        add("nodes", false)
    else
        add("at", true)
        add("switch", true)
        add("throughNodes", false)
        add("divergingNodes", false)
    end
    return blocks
end

--- @class WaymanNodeEditor: ISCollapsableWindowJoypad
--- @field instance WaymanEntityInstance
--- @field playerNum integer
--- @field blocks WaymanNodeBlock[]
--- @field dirty boolean
local NodeEditor = ISCollapsableWindowJoypad:derive("WaymanNodeEditor")

function NodeEditor:updateTitle()
    local entityId = self.instance.data and self.instance.data.id
    if entityId == nil or tostring(entityId) == "" then
        entityId = WaymanLocalization.ui("EntityIdPlaceholder")
    end
    self.title = WaymanLocalization.ui("NodeEditorTitle") .. ": " .. tostring(entityId)
end

function NodeEditor:initialise()
    ISCollapsableWindowJoypad.initialise(self)
end

function NodeEditor:layoutNodeLists()
    if not self.nodeBlockList then return end
    local buttonWidth = 90
    local usableWidth = self.nodePanel.width - buttonWidth - SPACING * 2
    local listWidth = math.max(140, math.floor(usableWidth * 0.7))
    local listHeight = math.max(100, self.nodePanel.height - 55)
    self.nodeBlockList:setWidth(listWidth)
    self.nodeBlockList:setHeight(listHeight)
    local buttonX, buttonY = listWidth + SPACING, 43
    for _, button in ipairs({
        self.addButton,
        self.removeButton,
        self.moveUpButton,
        self.moveDownButton,
        self.editNodeButton,
    }) do
        button:setX(buttonX)
        button:setY(buttonY)
        button:setWidth(buttonWidth)
        buttonY = buttonY + BUTTON_H + SPACING
    end
    self.nodeList:setX(buttonX + buttonWidth + SPACING)
    self.nodeList:setWidth(self.nodePanel.width - buttonX - buttonWidth - SPACING)
    self.nodeList:setHeight(listHeight)
end

function NodeEditor:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    if self.layoutWidth ~= self.width or self.layoutHeight ~= self.height then
        self.nodePanel:setWidth(self.width)
        self.nodePanel:setHeight(self.height - self.nodePanel.y - 50)
        self:layoutNodeLists()
        self.layoutWidth, self.layoutHeight = self.width, self.height
    end
end

function NodeEditor:isKeyConsumed(key)
    return self:getIsVisible() and key == Keyboard.KEY_ESCAPE
end

function NodeEditor:onKeyRelease(key)
    if not self:getIsVisible() or key ~= Keyboard.KEY_ESCAPE then return end
    if self.editingNode then
        self:cancelNodeEditing()
    else
        self:close()
    end
end

function NodeEditor:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local contentY = self:titleBarHeight() + SPACING
    self.nodePanel = ISPanel:new(0, contentY, self.width, self.height - contentY - 50)
    self.nodePanel:initialise()
    self.nodePanel.background, self.nodePanel.border = false, false
    self.nodePanel:setAnchorRight(true)
    self.nodePanel:setAnchorBottom(true)
    self:addChild(self.nodePanel)

    self.nodeBlockList = NodeBlockTable:new(0, 43, 250, self.nodePanel.height - 55,
        WaymanLocalization.ui("NodeBlocks"), { showDefault = true })
    self.nodeBlockList:initialise()
    self.nodeBlockList.onBlockSelected = function(block)
        self.selectedBlock = block
        self:refreshNodeList()
    end
    self.nodeBlockList.onDefaultClick = function(block) self:onRestoreDefault(block) end
    self.nodePanel:addChild(self.nodeBlockList)

    self.addButton = addButton(self.nodePanel, 0, 0, 90, WaymanLocalization.ui("Add"), self, self.onAdd)
    self.removeButton = addButton(self.nodePanel, 0, 0, 90, WaymanLocalization.ui("Remove"), self, self.onRemove)
    self.moveUpButton = addButton(self.nodePanel, 0, 0, 90, WaymanLocalization.ui("MoveUp"), self, self.onMoveUp)
    self.moveDownButton = addButton(self.nodePanel, 0, 0, 90, WaymanLocalization.ui("MoveDown"), self, self.onMoveDown)
    self.editNodeButton = addButton(self.nodePanel, 0, 0, 90,
        WaymanLocalization.ui("EditNode"), self, self.onEditNode)

    self.nodeList = NodeTable:new(0, 43, 250, self.nodePanel.height - 55, WaymanLocalization.ui("Nodes"))
    self.nodeList:initialise()
    self.nodeList.onNodeSelected = function() self:updateButtons() end
    self.nodePanel:addChild(self.nodeList)

    local actionY = self.height - self:resizeWidgetHeight() - BUTTON_H - 8
    self.reloadButton = addButton(self, self.width - 310, actionY, 90,
        WaymanLocalization.ui("Reload"), self, self.onReload)
    self.applyButton = addButton(self, self.width - 210, actionY, 90,
        WaymanLocalization.ui("Apply"), self, self.onApply)
    self.closeButton = addButton(self, self.width - 110, actionY, 90,
        WaymanLocalization.ui("Cancel"), self, self.close)
    for _, button in ipairs({ self.reloadButton, self.applyButton, self.closeButton }) do
        button:setAnchorLeft(false)
        button:setAnchorRight(true)
        button:setAnchorTop(false)
        button:setAnchorBottom(true)
    end
    self.statusLabel = ISLabel:new(SPACING, actionY + 5, 20, "", 0.8, 0.8, 0.8, 1,
        UIFont.Small, true)
    self.statusLabel:initialise()
    self.statusLabel:setAnchorTop(false)
    self.statusLabel:setAnchorBottom(true)
    self:addChild(self.statusLabel)
    self:layoutNodeLists()
    self:refreshAll()
end

function NodeEditor:updateButtons()
    local block = self.selectedBlock
    local _, index = self.nodeList:getSelectedNode()
    local count = block and #block.nodes or 0
    local canChangeCount = block and block.blockId ~= "at" and block.blockId ~= "switch"
    local editing = self.editingNode ~= nil
    self.addButton:setEnable(not editing and canChangeCount == true)
    self.removeButton:setEnable(not editing and canChangeCount == true and index ~= nil and index > 0)
    self.moveUpButton:setEnable(not editing and index ~= nil and index > 1)
    self.moveDownButton:setEnable(not editing and index ~= nil and index > 0 and index < count)
    self.editNodeButton:setEnable(not editing and index ~= nil and index > 0)
    if self.reloadButton then self.reloadButton:setEnable(not editing) end
    if self.applyButton then self.applyButton:setEnable(not editing) end
end

function NodeEditor:refreshBlockList(selectedId)
    selectedId = selectedId or (self.selectedBlock and self.selectedBlock.blockId)
    self.nodeBlockList:clear()
    self.nodeBlockList.data.selected = -1
    self.selectedBlock = nil
    for index, block in ipairs(self.blocks) do
        self.nodeBlockList:addItem(block.blockId, block)
        if block.blockId == selectedId then
            self.nodeBlockList.data.selected = index
            self.nodeBlockList.data.block = block
            self.selectedBlock = block
        end
    end
    if not self.selectedBlock then
        self.selectedBlock = self.blocks[1]
        self.nodeBlockList.data.selected = self.selectedBlock and 1 or -1
        self.nodeBlockList.data.block = self.selectedBlock
    end
end

function NodeEditor:refreshNodeList(selectedIndex)
    self.nodeList:clear()
    self.nodeList.data.selected = -1
    for index, node in ipairs((self.selectedBlock and self.selectedBlock.nodes) or {}) do
        self.nodeList:addItem(tostring(index), node)
    end
    if selectedIndex and self.selectedBlock and self.selectedBlock.nodes[selectedIndex] then
        self.nodeList.data.selected = selectedIndex
        self.nodeList.data.block = self.selectedBlock.nodes[selectedIndex]
    end
    self:updateButtons()
end

function NodeEditor:refreshHighlights()
    local entries = {}
    local editingEntry
    for _, block in ipairs(self.blocks) do
        for index, node in ipairs(block.nodes) do
            local color = blockColor(block.blockId)
            local isEditing = self.editingBlock == block and self.editingIndex == index
            if isEditing then
                color = colorWithAlpha(color, 1)
            end
            local entry = Highlights.highlightRelativeNodeEntry(
                self.instance, node, self.playerNum, color)
            if isEditing then
                editingEntry = entry
            elseif entry then
                table.insert(entries, entry)
            end
        end
    end
    if editingEntry then table.insert(entries, editingEntry) end
    Highlights.replaceGroup(HIGHLIGHT_GROUP, entries)
end

function NodeEditor:refreshAll()
    self:refreshBlockList()
    self:refreshNodeList()
    self:refreshHighlights()
end

function NodeEditor:setDirty()
    self.dirty = true
    self.statusLabel:setName(WaymanLocalization.ui("StatusUnsavedChanges"))
    self:refreshBlockList()
    self:refreshHighlights()
end

-- New nodes use the player's current square, relative to the entity origin.
function NodeEditor:onAdd()
    local block = self.selectedBlock
    if not block or block.blockId == "at" or block.blockId == "switch" then return end
    local player = getSpecificPlayer(self.playerNum) or getPlayer()
    local square = player and player:getSquare()
    if not square then return end
    table.insert(block.nodes, {
        x = square:getX() - self.instance.origin.x,
        y = square:getY() - self.instance.origin.y,
        z = square:getZ() - self.instance.origin.z,
    })
    block.isDefault = false
    self:refreshNodeList(#block.nodes)
    self:setDirty()
end

function NodeEditor:onRemove()
    local block = self.selectedBlock
    local _, index = self.nodeList:getSelectedNode()
    if not block or block.blockId == "at" or block.blockId == "switch"
        or not index or index < 1 or index > #block.nodes then return end
    table.remove(block.nodes, index)
    block.isDefault = false
    self:refreshNodeList(math.min(index, #block.nodes))
    self:setDirty()
end

function NodeEditor:moveSelected(offset)
    local block = self.selectedBlock
    local _, index = self.nodeList:getSelectedNode()
    local target = index and index + offset
    if not block or not index or target < 1 or target > #block.nodes then return end
    block.nodes[index], block.nodes[target] = block.nodes[target], block.nodes[index]
    block.isDefault = false
    self:refreshNodeList(target)
    self:setDirty()
end

function NodeEditor:onMoveUp() self:moveSelected(-1) end
function NodeEditor:onMoveDown() self:moveSelected(1) end

--- Starts world-square selection for the currently selected node.
function NodeEditor:onEditNode()
    local node, index = self.nodeList:getSelectedNode()
    if not self.selectedBlock or not node or not index or index < 1 then return end
    self.editingNode = node
    self.editingBlock = self.selectedBlock
    self.editingIndex = index
    self:updateButtons()
    self:refreshHighlights()
    self:updateNodeEditHover()
end

--- Restores normal highlights without changing the node.
function NodeEditor:cancelNodeEditing()
    self.editingNode = nil
    self.editingBlock = nil
    self.editingIndex = nil
    Highlights.clearGroup(HOVER_HIGHLIGHT_GROUP)
    self:updateButtons()
    self:refreshHighlights()
end

--- Highlights the world square under the cursor while editing a node.
function NodeEditor:updateNodeEditHover()
    if not self.editingNode or not self:getIsVisible() then
        Highlights.clearGroup(HOVER_HIGHLIGHT_GROUP)
        return
    end
    local mouseX, mouseY = getMouseX(), getMouseY()
    if mouseX >= self.x and mouseX <= self.x + self.width
        and mouseY >= self.y and mouseY <= self.y + self.height then
        Highlights.clearGroup(HOVER_HIGHLIGHT_GROUP)
        return
    end
    local square = squareAtMouse(self)
    if not square then
        Highlights.clearGroup(HOVER_HIGHLIGHT_GROUP)
        return
    end
    Highlights.replaceGroup(HOVER_HIGHLIGHT_GROUP, {
        {
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            playerNum = self.playerNum,
            color = colorWithAlpha(blockColor(self.editingBlock.blockId), 0.8),
        },
    })
end

--- Commits the selected world square as coordinates relative to the block origin.
function NodeEditor:commitNodeEdit(square)
    local block, index = self.editingBlock, self.editingIndex
    local origin = block and block.origin
    if not block or not origin or not index or not block.nodes[index] then return end
    block.nodes[index] = {
        x = square:getX() - origin.x,
        y = square:getY() - origin.y,
        z = square:getZ() - origin.z,
    }
    block.isDefault = false
    self.editingNode = nil
    self.editingBlock = nil
    self.editingIndex = nil
    Highlights.clearGroup(HOVER_HIGHLIGHT_GROUP)
    self:refreshNodeList(index)
    self:setDirty()
end

function NodeEditor:onRestoreDefault(block)
    if not block or block.isDefault then return end
    local value = self.instance.defaults[block.blockId]
    block.nodes = block.singleton and (value and { copy(value) } or {}) or copy(value or {})
    block.isDefault = true
    self:refreshNodeList()
    self:setDirty()
end

function NodeEditor:submittedData()
    local data = { id = self.instance.data.id }
    for _, block in ipairs(self.blocks) do
        if not block.isDefault then
            data[block.blockId] = block.singleton and copy(block.nodes[1]) or copy(block.nodes)
        end
    end
    return data
end

-- Uses the same updateRailEntity command and SaveGeometry path as the context action.
function NodeEditor:onApply()
    local master = self.instance.master
    local square = master and master:getSquare()
    if not square then return end
    local args = {
        x = square:getX(), y = square:getY(), z = square:getZ(),
        objectIndex = master:getObjectIndex(),
        facing = self.instance.facing,
        modData = self:submittedData(),
    }
    self.statusLabel:setName(WaymanLocalization.ui("StatusSaving"))
    self.awaitingSave = true
    if isClient() then
        sendClientCommand(getSpecificPlayer(self.playerNum) or getPlayer(),
            "RailroaderWayman", "updateRailEntity", args)
    elseif RailroaderWaymanEntityRuntime then
        local ok, result = RailroaderWaymanEntityRuntime.SaveGeometry(master, args.modData, args.facing)
        self:onSaveResult(ok, result)
    end
end

-- Reload is deliberately local: the object modData is the authoritative source requested here.
function NodeEditor:onReload()
    if self.editingNode then self:cancelNodeEditing() end
    self.instance.data = self.instance.master:getModData()[OBJECT_DATA_KEY] or {}
    self.blocks = readBlocks(self.instance)
    self.selectedBlock = nil
    self.dirty = false
    self:updateTitle()
    self.statusLabel:setName(WaymanLocalization.ui("StatusReloaded"))
    self:refreshAll()
end

function NodeEditor:onSaveResult(ok, reason)
    if not self.awaitingSave then return end
    self.awaitingSave = false
    if ok then
        self.instance.data = self.instance.master:getModData()[OBJECT_DATA_KEY] or {}
        self.blocks = readBlocks(self.instance)
        self.selectedBlock = nil
        self.dirty = false
        self:updateTitle()
        self:refreshAll()
        self.statusLabel:setName(WaymanLocalization.ui("StatusSaved"))
    else
        self.statusLabel:setName(WaymanLocalization.ui("StatusRejected", tostring(reason)))
    end
end

function NodeEditor:close()
    Controller.windowState = {
        x = self.x,
        y = self.y,
        width = self.width,
        height = self.height,
    }
    Highlights.clearGroup(HIGHLIGHT_GROUP)
    Highlights.clearGroup(HOVER_HIGHLIGHT_GROUP)
    self:setVisible(false)
    self:removeFromUIManager()
    if Controller.instance == self then Controller.instance = nil end
end

--- 
--- @param x number
--- @param y number
--- @param width number
--- @param height number
--- @param instance WaymanEntityInstance
--- @param playerNum integer
function NodeEditor:new(x, y, width, height, instance, playerNum)
    local o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    o.resizable = true
    o.minimumWidth, o.minimumHeight = 620, 380
    o.instance = instance
    o.playerNum = playerNum or 0
    o.blocks = readBlocks(instance)
    o.dirty = false
    o:updateTitle()
    o:setWantKeyEvents(true)
    return o
end

--- 
--- @param instance WaymanEntityInstance
--- @param playerNum integer
function Controller.open(instance, playerNum)
    if Controller.instance then Controller.instance:close() end
    local x, y, width, height = windowBounds(Controller.windowState, 700, 500)
    local editor = NodeEditor:new(x, y, width, height, instance, playerNum)
    editor:initialise()
    editor:addToUIManager()
    Controller.instance = editor
    return editor
end

local function onServerCommand(module, command, args)
    if module == "RailroaderWayman" and command == "railEntityUpdated" and Controller.instance then
        Controller.instance:onSaveResult(args and args.ok, args and (args.reason or args.id))
    end
end

local function onTick()
    local editor = Controller.instance
    if editor and editor.editingNode then editor:updateNodeEditHover() end
end

local function onMouseDown()
    local editor = Controller.instance
    if not editor or not editor.editingNode or not editor:getIsVisible() then return end
    local mouseX, mouseY = getMouseX(), getMouseY()
    if mouseX >= editor.x and mouseX <= editor.x + editor.width
        and mouseY >= editor.y and mouseY <= editor.y + editor.height then return end
    local square = squareAtMouse(editor)
    if square then editor:commitNodeEdit(square) end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(onTick)
Events.OnMouseDown.Add(onMouseDown)
return Controller
