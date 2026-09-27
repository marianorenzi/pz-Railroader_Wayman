require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "Wayman/WaymanLocalization"

local ROW_H = 28

---@class WaymanNodeHeader : ISPanel
---@field title string
local NodeHeader = ISPanel:derive("WaymanNodeHeader")

function NodeHeader:new(x, y, width, height, title)
    local o = ISPanel.new(self, x, y, width, height)
    o.title = title
    return o
end

function NodeHeader:render()
    -- title
    local w = getTextManager():MeasureStringX(UIFont.Small, self.title)
    local titleX = math.max(0, math.floor((self.width - w) / 2))
    self:drawText(self.title, titleX, 3, 1, 1, 1, 1, UIFont.Small)
    -- x,y,z
    local axisW = math.floor(self.width / 3)
    local axisX = 8
    self:drawText("X", axisX, 3 + ROW_H, 1, 1, 1, 1, UIFont.Small)
    axisX = axisX + axisW
    self:drawText("Y", axisX, 3 + ROW_H, 1, 1, 1, 1, UIFont.Small)
    axisX = axisX + axisW
    self:drawText("Z", axisX, 3 + ROW_H, 1, 1, 1, 1, UIFont.Small)
end

---------------------------------------------------------------------------------------------
---@class WaymanNodeList : ISScrollingListBox
---@field block WaymanNodeBlock?
local NodeList = ISScrollingListBox:derive("WaymanNodeList")

--- Creates the selectable list used for node blocks.
function NodeList:new(x, y, width, height)
    local o = ISScrollingListBox.new(self, x, y, width, height)
    o.itemheight = ROW_H
    o.selected = -1
    o.block = nil
    o.drawBorder = false
    o.mouseOverHighlightColor = {r = 0, g = 0, b = 0, a = 0}
    o.doDrawItem = NodeList.doDrawItem
    return o
end

--- Selects an node block.
function NodeList:onMouseDown(x, y)
    ISScrollingListBox.onMouseDown(self, x, y)
    if self.selected == -1 then return end

    local item = self.items[self.selected]
    local block = item and item.item or nil
    if not item or not block then return end

    if self.block ~= block then
        self.block = block 
        self.parent.onNodeSelected(self.block, self.selected)
    end

    self.parent.onNodeClick(self.block)
end

--- Sends a double-click event if it's a valid block.
function NodeList:onMouseDoubleClick(x, y)
    ISScrollingListBox.onMouseDoubleClick(self, x, y)
    local row = self:rowAt(x, y)
    local item = row and self.items[row]
    local block = item and item.item or nil
    if not item or not block then return end

    self.parent.onNodeDoubleClick(block)
end

--- Draws one node block row with technical ID and node count.
function NodeList:doDrawItem(y, item, alt)
    if self.selected == item.index then
        self:drawRect(0, y, self.width, item.height, 0.25, 0.2, 0.55, 0.8)
    end
    self:drawRectBorder(0, y, self.width, item.height, 0.35, 0.7, 0.7, 0.7)
    -- x,y,z
    local axisW = math.floor(self.width / 3)
    local axisX = 8
    self:drawText(tostring(item.item.x), axisX, y + 5, 1, 1, 1, 1, UIFont.Small)
    axisX = axisX + axisW
    self:drawText(tostring(item.item.y), axisX, y + 5, 1, 1, 1, 1, UIFont.Small)
    axisX = axisX + axisW
    self:drawText(tostring(item.item.z or 0), axisX, y + 5, 1, 1, 1, 1, UIFont.Small)

    return y + item.height
end

---------------------------------------------------------------------------------------------
---@class WaymanNodeTable : ISPanel
---@field header WaymanNodeHeader
---@field data WaymanNodeList
NodeTable = ISPanel:derive("WaymanNodeTable")
function NodeTable:new(x, y, width, height, title)
    local o = ISPanel.new(self, x, y, width, height)

    -- events
    o.onNodeSelected = function(block, index) end
    o.onNodeClick = function(block) end
    o.onNodeDoubleClick = function(block) end
    
    o.header = NodeHeader:new(0, 0, width, ROW_H*2, title)
    o.header:initialise()
    o.header.background = true
    o:addChild(o.header)

    o.data = NodeList:new(0, ROW_H*2, width, height - ROW_H * 2)
    o.data:initialise()
    o:addChild(o.data)

    return o
end

function NodeTable:initialise()
    ISPanel.initialise(self)
end

function NodeTable:setWidth(width)
    ISPanel.setWidth(self, width)
    self.header:setWidth(width)
    self.data:setWidth(width)
end

function NodeTable:setHeight(height)
    ISPanel.setHeight(self, height)
    -- self.header:setHeight(ROW_H)
    self.data:setHeight(math.max(0, height - ROW_H * 2))
end

function NodeTable:getSelectedNode()
    return self.data.block, self.data.selected
end

function NodeTable:getNodes()
    return self.data.items
end

function NodeTable:clear()
    self.data:clear()
    self.data.block = nil
end

--- 
--- @param name string
--- @param item WaymanNode
function NodeTable:addItem(name, item, tooltip)
    self.data:addItem(name, item, tooltip)
end
