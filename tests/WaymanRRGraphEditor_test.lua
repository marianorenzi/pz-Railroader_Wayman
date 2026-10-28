-- Exercises the real turnout selector callbacks without constructing a PZ window.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local luaRoot = root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua"
package.path = luaRoot .. "/shared/?.lua;" .. package.path
local actualRequire = require
actualRequire("Wayman/WaymanRRGraph")
local windowClass
ISCollapsableWindowJoypad = {derive=function()
    windowClass = {}; windowClass.__index = windowClass
    return windowClass
end}
RailroaderWaymanGraphDisplay = {refresh=function() end}
WaymanLocalization = {ui=function(key) return key end}
function require(name)
    if name == "Wayman/WaymanGraphData" or name == "Wayman/WaymanRRGraph" then return actualRequire(name) end
end
RR = {API={edges=function()
    return {{id="main"},{id="other:line",prefix="other"},
        {id="wayman:main",prefix="wayman"},{id="wayman:old",prefix="wayman"}}
end}}
dofile(luaRoot .. "/client/Wayman/WaymanGraphEditor.lua")
local function combo()
    return {
        options={},selected=0,
        addOptionWithData=function(self,label,data) table.insert(self.options,{text=label,data=data}) end,
        setSelectedData=function(self,data)
            for i,option in ipairs(self.options) do if option.data == data then self.selected=i; return end end
            self.selected=0
        end,
        getOptionData=function(self,i) return self.options[i].data end,
    }
end
local legs={throat={edge="main",toward="start",external=true},through={edge="main",toward="end"},diverge={}}
local editor=setmetatable({
    draft=RailroaderWaymanGraphData.ensure({edges={main={{nodes={{x=1,y=1},{x=2,y=2}}}}},
        switches={{id="turnout_1",legs=legs}}}),
    switchCombo=combo(),edgeCombo=combo(),legControls={},
    statusLabel={setName=function() end},
}, windowClass)
editor.switchCombo:addOptionWithData("turnout_1","turnout_1")
editor.switchCombo:setSelectedData("turnout_1")
for _,name in ipairs({"throat","through","diverge"}) do
    local toward=combo()
    for _,value in ipairs({false,"start","end"}) do toward:addOptionWithData(tostring(value),value) end
    editor.legControls[name]={edge=combo(),toward=toward}
end
editor:onSwitchSelected()
local function selected(c) return c:getOptionData(c.selected) end
assert(selected(editor.legControls.throat.edge).id == "main")
assert(selected(editor.legControls.through.edge).id == "wayman:main")
local labels,other={}
for _,option in ipairs(editor.legControls.diverge.edge.options) do
    labels[option.text]=true
    if option.data and option.data.id == "other:line" then other=option.data end
end
assert(labels["rr:main"] and labels["wayman:main"] and labels["other:line"] and not labels["wayman:old"])
editor.legControls.diverge.edge:setSelectedData(other)
editor:onSwitchLegChanged(nil,"diverge")
assert(legs.diverge.edge == "other:line" and legs.diverge.external and legs.diverge.toward == "start")
editor.edgeCombo:addOptionWithData("main","main")
editor.edgeCombo:setSelectedData("main")
editor.refreshAll=function() end
editor:onDeleteEdge()
assert(legs.throat.edge == "main" and legs.throat.external, "deleting Wayman main removed RR main")
assert(legs.through.edge == nil and legs.diverge.edge == "other:line")
-- Export is an explicit user action and stays available outside debug mode.
function getDebug() return false end
ModData = {get=function() return editor.draft end}
local output, exported = print
print = function(message) exported = message end
editor:onExport()
print = output
assert(exported and exported:find("[RailroaderWayman] WORLD_DATA_JSON ",1,true) == 1,
    "explicit graph Export was disabled outside debug mode")
print("PASS: turnout labels include every prefix and preserve real external IDs")
print("PASS: native and local main stay distinct through selection and deletion")
print("PASS: explicit graph export remains available outside debug mode")

-- Presentation is derived from actual visibility, without changing saved
-- display preferences or switching the closed editor back to confirmed data.
local Controller = RailroaderWaymanGraphEditor
local options = {showAllEdges=true, showAvailableNodes=true, showSelectedEdge=true}
RailroaderWaymanGraphDisplay.getOptions = function() return options end
local confirmed = {edges={}}
local state = Controller.getOverlayState(confirmed)
assert(not state.editorOpen and state.data == confirmed)
assert(state.showAllEdges and not state.showAvailableNodes and not state.showSelectedEdge)
local visible, order = true, {}
ISComboBox = {}
editor.getIsVisible = function() return visible end
editor.setVisible = function(_, value) visible = value end
editor.bringToTop = function() order[#order + 1] = "editor" end
Controller.instance = editor
Controller.selectedEdgeBlockId, Controller.selectedAvailableBlockId = "block", "available"
state = Controller.getOverlayState(confirmed)
assert(state.editorOpen and state.showAvailableNodes and state.showSelectedEdge)
assert(state.selectedEdgeId == "main" and state.selectedEdgeBlockId == "block"
    and state.selectedAvailableBlockId == "available")
Keyboard = {KEY_ESCAPE=1}
for _, close in ipairs({windowClass.close, windowClass.onCancel,
    function(window) window:onKeyRelease(Keyboard.KEY_ESCAPE) end}) do
    close(editor)
    state = Controller.getOverlayState(confirmed)
    assert(not state.editorOpen and state.data == editor.draft)
    assert(not state.showAvailableNodes and not state.showSelectedEdge and state.showAllEdges)
    assert(not state.selectedEdgeId and not state.selectedEdgeBlockId and not state.selectedAvailableBlockId)
    assert(options.showAvailableNodes and options.showSelectedEdge, "closing erased saved toggles")
    Controller.open(confirmed)
    state = Controller.getOverlayState(confirmed)
    assert(state.editorOpen and state.showAvailableNodes and state.showSelectedEdge)
    assert(state.selectedAvailableBlockId == "available" and state.data == editor.draft)
end
options.showAvailableNodes, options.showSelectedEdge = false, false
editor:close(); Controller.open(confirmed)
state = Controller.getOverlayState(confirmed)
assert(not state.showAvailableNodes and not state.showSelectedEdge, "reopening reset disabled toggles")

-- Existing vanilla popups stay above their parent; no focus setter is called.
editor.conflictModal = {getIsVisible=function() return true end,
    bringToTop=function() order[#order+1]="modal" end}
ISComboBox = {SharedPopup={parentCombo={expanded=true},getIsVisible=function() return true end,
    bringToTop=function() order[#order+1]="combo" end}}
order = {}
Controller.bringToTop()
assert(table.concat(order, ",") == "editor,modal,combo")
ISComboBox.SharedPopup.parentCombo.expanded = false
order = {}; Controller.bringToTop()
assert(table.concat(order, ",") == "editor,modal", "closed shared popup was raised")
editor:close(); order = {}; Controller.bringToTop()
assert(#order == 0, "hidden editor was raised")

-- Inversion acts on a whole multi-node block, never on canonical geometry.
local multi = {blockId="multi", nodes={{x=1,y=2},{x=3,y=4}}}
local single = {blockId="single", nodes={{x=5,y=6}}}
local current, dirtyCount = multi, 0
editor.getSelectedEdgeBlock = function() return current, 1 end
editor.setDirty = function() dirtyCount=dirtyCount+1 end
editor:onInvert()
assert(multi.invertNodes and dirtyCount == 1)
assert(multi.nodes[1].x == 1 and multi.nodes[2].x == 3)
editor:onInvert()
assert(not multi.invertNodes and dirtyCount == 2)
current = single; editor:onInvert()
assert(not single.invertNodes and dirtyCount == 2, "single-node inversion changed draft")
print("PASS: hidden/absent editor masks helpers and selections, and reopening preserves preferences/draft")
print("PASS: raising the editor preserves popup order without touching keyboard focus")
print("PASS: inversion is reversible, preserves node geometry and ignores one-node blocks")
