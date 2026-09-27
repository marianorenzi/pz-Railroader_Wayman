require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "Wayman/WaymanLocalization"

local ROW_H = 28
local DEFAULT_W = 100
local COUNT_W = 52

---@class WaymanNodeBlockHeader : ISPanel
---@field title string
local NodeBlockHeader = ISPanel:derive("WaymanNodeBlockHeader")

function NodeBlockHeader:new(x, y, width, height, title, showDefault)
    local o = ISPanel.new(self, x, y, width, height)
    o.title = title
    o.showDefault = showDefault == true
    return o
end

function NodeBlockHeader:render()
    local w = getTextManager():MeasureStringX(UIFont.Small, self.title)
    local titleX = math.max(0, math.floor((self.width - w) / 2))
    self:drawText(self.title, titleX, 3, 1, 1, 1, 1, UIFont.Small)
    self:drawText(WaymanLocalization.ui("BlockId"), 8, 3 + ROW_H, 1, 1, 1, 1, UIFont.Small)
    local t = WaymanLocalization.ui("NrNodes")
    w = getTextManager():MeasureStringX(UIFont.Small, t)
    local countRight = self.showDefault and (self.width - DEFAULT_W) or self.width
    self:drawText(t, countRight - COUNT_W + math.max(0, (COUNT_W - w) / 2),
        3 + ROW_H, 1, 1, 1, 1, UIFont.Small)
    if self.showDefault then
        t = WaymanLocalization.ui("Default")
        w = getTextManager():MeasureStringX(UIFont.Small, t)
        self:drawText(t, self.width - DEFAULT_W + math.max(0, (DEFAULT_W - w) / 2),
            3 + ROW_H, 1, 1, 1, 1, UIFont.Small)
    end
end

---------------------------------------------------------------------------------------------
---@class WaymanNodeBlockList : ISScrollingListBox
---@field block any
local NodeBlockList = ISScrollingListBox:derive("WaymanNodeBlockList")

--- Creates the selectable list used for node blocks.
function NodeBlockList:new(x, y, width, height, showDefault)
    local o = ISScrollingListBox.new(self, x, y, width, height)
    o.itemheight = ROW_H
    o.selected = -1
    o.block = nil
    o.drawBorder = false
    o.mouseOverHighlightColor = {r = 0, g = 0, b = 0, a = 0}
    o.doDrawItem = NodeBlockList.doDrawItem
    o.showDefault = showDefault == true
    return o
end

--- Selects an node block.
function NodeBlockList:onMouseDown(x, y)
    ISScrollingListBox.onMouseDown(self, x, y)
    if self.selected == -1 then return end

    local item = self.items[self.selected]
    local block = item and item.item or nil
    if not item or not block then return end

    if self.block ~= block then
        self.block = block
        self.parent.onBlockSelected(self.block, self.selected)
    end

    if self.showDefault and x >= self.width - DEFAULT_W then
        self.parent.onDefaultClick(self.block, self.selected)
        return
    end

    self.parent.onBlockClick(self.block)
end

--- Sends a double-click event if it's a valid block.
function NodeBlockList:onMouseDoubleClick(x, y)
    ISScrollingListBox.onMouseDoubleClick(self, x, y)
    local row = self:rowAt(x, y)
    local item = row and self.items[row]
    local block = item and item.item or nil
    if not item or not block then return end

    self.parent.onBlockDoubleClick(block)
end

--- Draws one node block row with technical ID and node count.
function NodeBlockList:doDrawItem(y, item, alt)
    if self.selected == item.index then
        self:drawRect(0, y, self.width, item.height, 0.25, 0.2, 0.55, 0.8)
    end
    self:drawRectBorder(0, y, self.width, item.height, 0.35, 0.7, 0.7, 0.7)
    self:drawText(item.item.blockId, 8, y + 5, 1, 1, 1, 1, UIFont.Small)
    local count = tostring(#(item.item.nodes or {}))
    local countW = getTextManager():MeasureStringX(UIFont.Small, count)
    local countRight = self.showDefault and (self.width - DEFAULT_W) or self.width
    self:drawText(count, countRight - COUNT_W + math.max(0, (COUNT_W - countW) / 2),
        y + 5, 0.75, 0.75, 0.75, 1, UIFont.Small)
    if self.showDefault then
        local boxSize = 14
        local boxX = self.width - DEFAULT_W + math.floor((DEFAULT_W - boxSize) / 2)
        local boxY = y + math.floor((item.height - boxSize) / 2)
        self:drawRectBorder(boxX, boxY, boxSize, boxSize, 1, 0.8, 0.8, 0.8)
        if item.item.isDefault then
            self:drawText("X", boxX + 3, boxY - 2, 0.2, 1, 0.2, 1, UIFont.Small)
        end
    end

    return y + item.height
end

---------------------------------------------------------------------------------------------
---@class WaymanNodeBlockTable : ISPanel
---@field header WaymanNodeBlockHeader
---@field data WaymanNodeBlockList
NodeBlockTable = ISPanel:derive("WaymanNodeBlockTable")
---@param options { showDefault: boolean }?
function NodeBlockTable:new(x, y, width, height, title, options)
    local o = ISPanel.new(self, x, y, width, height)
    options = options or {}
    o.showDefault = options.showDefault == true

    -- events
    o.onBlockSelected = function(block, index) end
    o.onBlockClick = function(block) end
    o.onBlockDoubleClick = function(block) end
    o.onDefaultClick = function(block, index) end
    
    o.header = NodeBlockHeader:new(0, 0, width, ROW_H*2, title, o.showDefault)
    o.header:initialise()
    o.header.background = true
    o:addChild(o.header)

    o.data = NodeBlockList:new(0, ROW_H*2, width, height - ROW_H * 2, o.showDefault)
    o.data:initialise()
    o:addChild(o.data)

    return o
end

function NodeBlockTable:initialise()
    ISPanel.initialise(self)
    -- self.header:initialise()
    -- self.data:initialise()
end

function NodeBlockTable:setWidth(width)
    ISPanel.setWidth(self, width)
    self.header:setWidth(width)
    self.data:setWidth(width)
end

function NodeBlockTable:setHeight(height)
    ISPanel.setHeight(self, height)
    -- self.header:setHeight(ROW_H)
    self.data:setHeight(math.max(0, height - ROW_H * 2))
end

-- function NodeBlockTable:setX(x)
--     ISPanel.setX(self, x)
--     self.header:setX(x)
--     self.data:setX(x)
-- end

-- function NodeBlockTable:setY(y)
--     ISPanel.setY(self, y)
--     self.header:setY(y)
--     self.data:setY(y + ROW_H)
-- end

function NodeBlockTable:getSelectedBlock()
    return self.data.block, self.data.selected
end

function NodeBlockTable:getBlocks()
    return self.data.items
end

function NodeBlockTable:clear()
    self.data:clear()
    self.data.block = nil
end

function NodeBlockTable:addItem(name, item, tooltip)
    self.data:addItem(name, item, tooltip)
end
