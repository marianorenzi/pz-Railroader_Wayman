-- Actual editor callbacks, and installed ISTextBox lifecycle when available.
local root=debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/") or "."
local luaRoot=root.."/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path=luaRoot.."/shared/?.lua;"..package.path
local GD=require "Wayman/WaymanGraphData"
local client=true
function isClient() return client end
function getTimestampMs() return 12345 end
function getSpecificPlayer() return {getUsername=function() return "alice" end} end
function getText(key) return key end
function getTexture() return {} end
function getJoypadData() return nil end
UIFont={Small=1,Medium=2}
Keyboard={KEY_ESCAPE=1,KEY_PERIOD=2}
function getTextManager() return {
    getFontHeight=function() return 14 end,
    MeasureStringX=function(_,_,text) return #text:gsub("[\128-\191]","")*7 end,
} end
function getCore() return {getKey=function() return Keyboard.KEY_PERIOD end} end
UIManager={setShowPausedMessage=function() end}
local UI={}
UI.__index=UI
function UI:derive() local c=setmetatable({},{__index=self});c.__index=c;return c end
function UI:new(x,y,width,height)
    return setmetatable({x=x or 0,y=y or 0,width=width or 100,height=height or 25,
        visible=true,backgroundColor={},options={}},self)
end
function UI:initialise() end
function UI:instantiate() end
function UI:addChild(child) child.parent=self end
function UI:setX(v) self.x=v end
function UI:setY(v) self.y=v end
function UI:setWidth(v) self.width=v end
function UI:setHeight(v) self.height=v end
function UI:getWidth() return self.width end
function UI:getHeight() return self.height end
function UI:getMouseX() return 300 end
function UI:getMouseY() return 100 end
function UI:getBottom() return self.y+self.height end
function UI:setEnable(v) self.enable=v end
function UI:setVisible(v) self.visible=v end
function UI:getIsVisible() return self.visible end
function UI:addToUIManager() self.added=true end
function UI:removeFromUIManager() self.added=false end
function UI:bringToTop() self.raised=true end
function UI:setTooltip(v) self.tooltip=v end
function UI:setWantKeyEvents() end
function UI:setAlwaysOnTop() end
function UI:setMaxLines() end
function UI:setMultipleLine() end
function UI:setClearButton() end
function UI:enableAcceptColor() end
function UI:enableCancelColor() end
function UI:setInitialColor() end
function UI:focus() self.focused=true end
function UI:unfocus() self.focused=false end
function UI:getText() return self.text end
function UI:getInternalText() return self.text end
function UI:setText(text)
    self.text=text
    if self.onTextChangeFunction then self.onTextChangeFunction() end
end
ISPanelJoypad=UI:derive()
ISButton=UI:derive()
function ISButton:new(x,y,w,h,title,target,callback)
    local o=UI.new(self,x,y,w,h);o.title=title;o.target=target;o.onclick=callback;return o
end
ISTextEntryBox=UI:derive()
function ISTextEntryBox:new(text,x,y,w,h) local o=UI.new(self,x,y,w,h);o.text=text;return o end
ISColorPicker=UI:derive()
ColorInfo={new=function() return {} end}
local native=os.getenv("PZ_LUA_ROOT")
if native then dofile(native.."/client/ISUI/ISTextBox.lua")
else
    ISTextBox=UI:derive()
    function ISTextBox:new(x,y,w,h,text,entry,target,callback)
        local o=UI.new(self,x,y,w,h);o.text=text;o.target=target;o.onclick=callback
        o.entry=ISTextEntryBox:new(entry,0,50,w,25)
        o.yes=ISButton:new(0,90,80,25,"OK");o.yes.internal="OK"
        o.no=ISButton:new(90,90,80,25,"Cancel");o.no.internal="CANCEL"
        return o
    end
    function ISTextBox:showErrorMessage(flag,text) self.showError=flag;self.errorMsg=text end
    function ISTextBox:destroy() self:setVisible(false);self:removeFromUIManager() end
    function ISTextBox:onClick(button) self.onclick(self.target,button);if not self.showError then self:destroy() end end
    function ISTextBox:setValidateFunction(_,fn) self.validateFunc=fn end
    function ISTextBox:setValidateTooltipText() end
end
ISComboBox=UI:derive()
function ISComboBox:new(...) local o=UI.new(self,...);o.selected=0;return o end
function ISComboBox:addOptionWithData(text,data)
    self.options[#self.options+1]={text=text,data=data}
    if self.selected==0 then self.selected=1 end
end
function ISComboBox:setSelectedData(data)
    for i,v in ipairs(self.options) do if v.data==data then self.selected=i;return end end
    self.selected=0
end
function ISComboBox:getOptionData(i) return self.options[i].data end
function ISComboBox:getOptionCount() return #self.options end
NodeBlockTable=UI:derive()
function NodeBlockTable:new(x,y,w,h,title,options)
    local o=UI.new(self,x,y,w,h);o.data=UI:new();o.data.items={};o.tableOptions=options;return o
end
function NodeBlockTable:clear() self.data.items={} end
function NodeBlockTable:addItem(name,item) self.data.items[#self.data.items+1]={name=name,item=item} end
function NodeBlockTable:getBlocks() return self.data.items end
ISCollapsableWindowJoypad=UI:derive()
local status
RailroaderWaymanGraphDisplay={refresh=function() end,getOptions=function() return {} end}
RailroaderWaymanLocalDraft={save=function() return true end,changed=function() return true end,
    renamedId=function(id) return id end,rebase=function() end,current=function() end}
local confirmed,requests={},{}
RailroaderWaymanGraphSync={ready=function() return true end,current=function() return confirmed end,
    request=function() end,receive=function() return true end}
ModData={get=function() return confirmed end,request=function() end}
function sendClientCommand(_,_,command,args) requests[#requests+1]={command=command,args=args} end
local textValues={}
WaymanLocalization={ui=function(key,...) return textValues["UI_Wayman_"..key] or key end}
function require() end
dofile(luaRoot.."/client/Wayman/WaymanGraphEditor.lua")
local Controller=RailroaderWaymanGraphEditor
local function window()
    -- The real window class is returned by the already-loaded controller's
    -- derive call. Capture it by loading once more with the same UI base.
    local class
    ISCollapsableWindowJoypad.derive=function(self) class=UI.derive(self);return class end
    dofile(luaRoot.."/client/Wayman/WaymanGraphEditor.lua")
    local editor=UI.new(class,20,20,700,560)
    editor.edgesPanel=UI:new(0,0,680,400)
    editor.draft=GD.ensure({edges={old={}}})
    editor.switchCombo=ISComboBox:new()
    editor.legControls={}
    editor.statusLabel={setName=function(_,value) status=value end}
    editor:createEdgePanel()
    editor:refreshAll()
    Controller.instance=editor
    return editor
end
for _,locale in ipairs({"EN","ES","RU"}) do
    local file=assert(io.open(luaRoot.."/shared/Translate/"..locale.."/UI.json"))
    textValues=assert(GD.worldDataFromJSON(file:read("*a")));file:close()
    local editor=window()
    assert(not editor.newEdgeId and editor.edgeList.tableOptions.showOrder)
    local previous=editor.edgeCombo
    for _,button in ipairs({editor.newEdgeButton,editor.renameEdgeButton,editor.deleteEdgeButton}) do
        assert(previous.x+previous.width <= button.x,"edge header controls overlap at minimum width")
        assert(button.x+button.width <= 680)
        previous=button
    end
end
local editor=window()
editor:onNewEdge()
local popup=editor.edgePopup
assert(popup and popup.entry.focused)
editor:onNewEdge();assert(editor.edgePopup==popup,"opened a second popup")
popup.entry:setText("bad name");popup.entry:onCommandEntered()
assert(editor.edgePopup==popup and popup.showError and popup.entry:getText()=="bad name")
popup.entry:setText("old");popup.entry:onCommandEntered()
assert(editor.edgePopup==popup and popup.showError and editor.draft.edges.old)
popup.entry:setText("");popup.entry:onCommandEntered()
assert(not editor.edgePopup and editor.draft.edges.edge_1 and not popup:getIsVisible())
editor:onNewEdge();popup=editor.edgePopup
popup.entry:setText("cancelled");popup:onClick(popup.no)
assert(not editor.edgePopup and not editor.draft.edges.cancelled)
editor:onNewEdge();popup=editor.edgePopup
popup.entry:setText("linea.1")
local toggle
keyBinding={}
Events={OnKeyPressed={Add=function(fn) toggle=fn end}}
dofile(luaRoot.."/client/Wayman/WaymanGraphKeybind.lua")
toggle(Keyboard.KEY_PERIOD)
assert(editor.edgePopup==popup and editor:getIsVisible() and popup.entry:getText()=="linea.1")
popup.entry:onCommandEntered()
assert(editor.draft.edges["linea.1"] and not editor.edgePopup)

editor.edgeCombo:setSelectedData("old")
editor:onRenameEdge();popup=editor.edgePopup
assert(popup.entry:getText()=="old")
popup.entry:setText(" edge_1 ");popup.entry:onCommandEntered()
assert(popup.showError and editor.draft.edges.old and editor.edgePopup==popup)
popup.entry:setText("old");popup.entry:onCommandEntered()
assert(not editor.edgePopup and editor.draft.edges.old and #requests==0)
editor:onRenameEdge();popup=editor.edgePopup
popup.entry:setText("renamed.local");popup.entry:onCommandEntered()
assert(not editor.edgePopup and editor.draft.edges["renamed.local"] and not editor.draft.edges.old and #requests==0)
editor:onRenameEdge();popup=editor.edgePopup
popup.entry.onOtherKey(popup.entry,Keyboard.KEY_ESCAPE)
editor:onKeyRelease(Keyboard.KEY_ESCAPE)
assert(not editor.edgePopup and editor:getIsVisible(),"Escape closed the editor below the dialog")
editor:onKeyPress(Keyboard.KEY_ESCAPE);editor:onKeyRelease(Keyboard.KEY_ESCAPE)
assert(not editor:getIsVisible())
editor:setVisible(true)
editor:onNewEdge();editor:onReload();assert(not editor.edgePopup)
editor.reloadPending=nil

-- A stale dialog cannot recreate an edge which was removed while open.
editor:onRenameEdge();popup=editor.edgePopup
editor.draft.edges[popup.edgeId]=nil
popup.entry:setText("resurrected");popup.entry:onCommandEntered()
assert(popup.showError and not editor.draft.edges.resurrected)
editor:closeEdgePopup()

editor=window()
confirmed=GD.copy(editor.draft);confirmed.revision=5
editor.localState={base=GD.copy(confirmed),draft=editor.draft,conflicts={}}
editor.baseRevision=5
editor:onRenameEdge();popup=editor.edgePopup
popup.entry:setText("server.name");popup.entry:onCommandEntered()
assert(#requests==1 and requests[1].command=="rename" and requests[1].args.revision==5)
assert(popup.pending and editor.pendingRename and editor.draft.edges.old and not editor.renameEdgeButton.enable)
popup.entry:onCommandEntered();assert(#requests==1)
local requestId=editor.pendingRename.requestId
editor:onRenameResult({requestId="other",ok=true});assert(editor.pendingRename)
editor:onRenameResult({requestId=requestId,ok=false,reason="graph revision changed"})
assert(not editor.pendingRename and editor.edgePopup==popup and not popup.pending and popup.entry:getText()=="server.name")
popup.entry:onCommandEntered()
assert(#requests==2 and editor.pendingRename.requestId~=requestId)
GD.renameEdge(editor.draft,"old","server.name")
editor:refreshEdgeCombos("server.name")
editor:onRenameResult({requestId=editor.pendingRename.requestId,ok=true})
assert(not editor.edgePopup and not editor.pendingRename and editor.renameEdgeButton.enable)
editor:onNewEdge();editor:close();assert(not editor.edgePopup)
print("PASS: New/Rename popups preserve invalid input, generate IDs, cancel, reject collisions and recheck removed selections")
print("PASS: period typing, Enter, Escape, one popup per editor, close/Reload cleanup and EN/ES/RU minimum-width controls")
print("PASS: confirmed rename waits for a correlated server response without optimistic mutation or duplicate submission")
if native then print("PASS: exercised installed vanilla ISTextBox initialisation, error/OK/cancel and destruction") end
