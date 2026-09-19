require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "Wayman/WaymanLocalization"

local ROW_H = 28

---@class WaymanNodeBlockHeader : ISPanel
---@field title string
local NodeBlockHeader = ISPanel:derive("WaymanNodeBlockHeader")

function NodeBlockHeader:new(x, y, width, height, title)
    local o = ISPanel.new(self, x, y, width, height)
    o.title = title
    return o
end

function NodeBlockHeader:render()
    local w = getTextManager():MeasureStringX(UIFont.Small, self.title)
    local titleX = math.max(0, math.floor((self.width - w) / 2))
    self:drawText(self.title, titleX, 3, 1, 1, 1, 1, UIFont.Small)
    self:drawText(WaymanLocalization.ui("BlockId"), 8, 3 + ROW_H, 1, 1, 1, 1, UIFont.Small)
    local t = WaymanLocalization.ui("NrNodes")
    w = getTextManager():MeasureStringX(UIFont.Small, t)
    self:drawText(t, self.width - w - 2, 3 + ROW_H, 1, 1, 1, 1, UIFont.Small)
end

---------------------------------------------------------------------------------------------
---@class WaymanNodeBlockList : ISScrollingListBox
---@field block any
local NodeBlockList = ISScrollingListBox:derive("WaymanNodeBlockList")

--- Creates the selectable list used for node blocks.
function NodeBlockList:new(x, y, width, height)
    local o = ISScrollingListBox.new(self, x, y, width, height)
    o.itemheight = ROW_H
    o.selected = -1
    o.block = nil
    o.drawBorder = false
    o.mouseOverHighlightColor = {r = 0, g = 0, b = 0, a = 0}
    o.doDrawItem = NodeBlockList.doDrawItem
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
    self:drawText(tostring(#(item.item.nodes or {})), self.width - 25, y + 5, 0.75, 0.75, 0.75, 1, UIFont.Small)

    return y + item.height
end

---------------------------------------------------------------------------------------------
---@class WaymanNodeBlockTable : ISPanel
---@field header WaymanNodeBlockHeader
---@field data WaymanNodeBlockList
NodeBlockTable = ISPanel:derive("WaymanNodeBlockTable")
function NodeBlockTable:new(x, y, width, height, title)
    local o = ISPanel.new(self, x, y, width, height)

    -- events
    o.onBlockSelected = function(block, index) end
    o.onBlockClick = function(block) end
    o.onBlockDoubleClick = function(block) end
    
    o.header = NodeBlockHeader:new(0, 0, width, ROW_H*2, title)
    o.header:initialise()
    o.header.background = true
    o:addChild(o.header)

    o.data = NodeBlockList:new(0, ROW_H*2, width, height - ROW_H * 2)
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