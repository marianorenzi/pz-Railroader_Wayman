local root = (debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/")) or "."
function require() end
local class, ui, queued = {}, nil, 0
class.__index = class
ISPanel = {
    derive=function() return class end,
    new=function(_, ...)
        ui=setmetatable({initialise=function() end,addToUIManager=function() end},class)
        return ui
    end,
}
function addAreaHighlightForPlayer() queued=queued+1 end
dofile(root .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/client/Wayman/WaymanWorldHighlights.lua")
RailroaderWaymanWorldHighlights.replaceGroup("test",{{x=1,y=2,z=0}})
ui:prerender(); assert(queued == 1)
local visible = true
ISWorldMap_instance = {getIsVisible=function() return visible end}
for _=1,1000 do ui:prerender() end
assert(queued == 1, "fullscreen map enqueued undrained highlights")
visible = false
ui:prerender(); assert(queued == 2)
print("PASS: world highlights suspend while the fullscreen map stops world rendering, and resume on close")
