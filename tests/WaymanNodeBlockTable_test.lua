-- Real table presentation/click callbacks with lightweight vanilla UI surfaces.
local root = debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
function require() end
UIFont = {Small=1}
local words = {}
WaymanLocalization = {ui=function(key) return words[key] or key end}
function getTextManager() return {
    MeasureStringX=function(_, _, text) return #text:gsub("[\128-\191]", "") * 7 end,
} end
ISPanel = {}
function ISPanel:derive()
    local class = setmetatable({}, {__index=self}); class.__index=class; return class
end
function ISPanel:new(x,y,width,height)
    return setmetatable({x=x,y=y,width=width,height=height,texts={},items={}}, self)
end
function ISPanel:initialise() end
function ISPanel:addChild(child) child.parent=self end
function ISPanel:setWidth(value) self.width=value end
function ISPanel:setHeight(value) self.height=value end
function ISPanel:drawRect() end
function ISPanel:drawRectBorder() end
function ISPanel:drawText(text,x,y)
    self.texts[#self.texts+1]={text=text,x=x,y=y}
end
ISScrollingListBox = ISPanel:derive()
function ISScrollingListBox:onMouseDown() self.selected=1 end
function ISScrollingListBox:clear() self.items={}; self.selected=-1 end
function ISScrollingListBox:addItem(_, block, tooltip)
    self.items[#self.items+1]={item=block,tooltip=tooltip,index=#self.items+1,height=28}
end
dofile(luaRoot .. "/client/Wayman/WaymanNodeBlockTable.lua")
local block = {blockId="turnout_123456789:component:through",nodes={{x=1,y=1},{x=2,y=2}}}
local languages = {
    {Order="Order",Normal="Normal",Inverted="Inverted",BlockId="Block ID"},
    {Order="Orden",Normal="Normal",Inverted="Invertido",BlockId="ID de bloque"},
    {Order="Порядок",Normal="Обычно",Inverted="Обратный",BlockId="ID блока"},
}
for _, language in ipairs(languages) do
    words=language
    local tableUI = NodeBlockTable:new(0,0,270,250,"Blocks",{showOrder=true})
    assert(tableUI.showOrder and not tableUI.showDefault)
    tableUI:addItem(block.blockId,block)
    assert(tableUI.data.items[1].tooltip == block.blockId)
    for _, inverted in ipairs({false,true,false}) do
        block.invertNodes = inverted or nil
        tableUI.data.texts={}
        tableUI.data:doDrawItem(0,tableUI.data.items[1])
        local texts=tableUI.data.texts
        assert(#texts == 3 and texts[2].text == "2")
        assert(texts[3].text == words[inverted and "Inverted" or "Normal"])
        for i=2,3 do
            local previous=texts[i-1]
            assert(previous.x + getTextManager():MeasureStringX(1, previous.text) <= texts[i].x,
                "order/count/ID columns overlap at minimum editor width")
        end
        assert(texts[3].x + getTextManager():MeasureStringX(1,texts[3].text) <= 270-13)
    end
    block.invertNodes=true
    local reopened=NodeBlockTable:new(0,0,270,250,"Blocks",{showOrder=true})
    reopened:addItem(block.blockId,block)
    reopened.data:doDrawItem(0,reopened.data.items[1])
    assert(reopened.data.texts[3].text == words.Inverted, "recreated table ignored saved inversion")
    tableUI.header:render()
    assert(tableUI.header.texts[#tableUI.header.texts].text == words.Order)
    tableUI:setWidth(400); tableUI:setHeight(300)
    assert(tableUI.data.width == 400 and tableUI.header.width == 400 and tableUI.data.height == 244)
end

-- The entity editor keeps its existing Default presentation and click action.
local entityTable = NodeBlockTable:new(0,0,360,250,"Entity",{showDefault=true})
block.isDefault=true
entityTable:addItem(block.blockId,block)
entityTable.data:doDrawItem(0,entityTable.data.items[1])
assert(not entityTable.showOrder and entityTable.showDefault)
assert(#entityTable.data.texts == 3 and entityTable.data.texts[3].text == "X")
local defaultClicks, selected, ordinaryClicks=0,nil,0
entityTable.onDefaultClick=function(value) assert(value==block); defaultClicks=defaultClicks+1 end
entityTable.onBlockSelected=function(value) selected=value end
entityTable.onBlockClick=function() ordinaryClicks=ordinaryClicks+1 end
entityTable.data:onMouseDown(300,5)
assert(defaultClicks == 1 and selected == block and ordinaryClicks == 0)
entityTable.data:onMouseDown(10,5)
assert(defaultClicks == 1 and ordinaryClicks == 1)
local availableTable=NodeBlockTable:new(0,0,270,250,"Available")
availableTable:addItem(block.blockId,block)
availableTable.data:doDrawItem(0,availableTable.data.items[1])
assert(#availableTable.data.texts == 2 and not availableTable.showOrder)
print("PASS: EN/ES/RU order indicators render live inversion without column overlap")
print("PASS: recreated tables retain inversion; entity Default and available tables retain their behavior")
