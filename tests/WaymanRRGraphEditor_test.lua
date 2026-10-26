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
