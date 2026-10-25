-- Reusable client renderer for colored world-square highlights. Features own
-- independent named groups so context diagnostics, graph inspection, and future
-- entity editors can replace or clear their highlights without affecting others.
require "ISUI/ISPanel"

RailroaderWaymanWorldHighlights = RailroaderWaymanWorldHighlights or {}
local Highlights = RailroaderWaymanWorldHighlights

---@class WaymanHighlightEntry
---@field playerNum integer
---@field x integer
---@field y integer
---@field z integer
---@field color table?
---@field size table?

Highlights.colors = Highlights.colors or {
    at = { r = 1.0, g = 0.75, b = 0.05, a = 0.65 },
    switch = { r = 1.0, g = 0.10, b = 0.65, a = 0.65 },
    through = { r = 0.10, g = 1.0, b = 0.15, a = 0.65 },
    diverge = { r = 0.10, g = 0.45, b = 1.0, a = 0.65 },
    nodes = { r = 0.10, g = 0.90, b = 1.0, a = 0.65 },
}

local groups = {}
local labelGroups = {}
local highlightUI
local HighlightUI = ISPanel:derive("RailroaderWaymanWorldHighlightUI")

local function mapVisible()
    return (ISWorldMap_instance and ISWorldMap_instance:getIsVisible())
        or (ISWorldMap and ISWorldMap.instance and ISWorldMap.instance:getIsVisible())
end

--- Draws every active highlight group before the diagnostic UI renders.
function HighlightUI:prerender()
    -- The fullscreen map disables IsoWorld rendering, which also stops the
    -- engine from draining area highlights. Do not enqueue them in that state.
    if mapVisible() then return end
    for _, entries in pairs(groups) do
        for _, entry in ipairs(entries) do
            local color = entry.color or Highlights.colors.nodes
            addAreaHighlightForPlayer(
                entry.playerNum or 0,
                entry.x, entry.y,
                entry.x + 1, entry.y + 1,
                entry.z or 0,
                color.r, color.g, color.b, color.a
            )
        end
    end
end

-- Project only the few visible labels each frame; their text and target are
-- cached by the feature that owns the group. Stack overlapping label bounds.
function HighlightUI:render()
    if mapVisible() then return end
    local placed = {}
    for _, labels in pairs(labelGroups) do
        for _, label in ipairs(labels) do
            local p = label.playerNum or 0
            local zoom = getCore():getZoom(p)
            local left, top = IsoCamera.getScreenLeft(p), IsoCamera.getScreenTop(p)
            local right, bottom = left+IsoCamera.getScreenWidth(p), top+IsoCamera.getScreenHeight(p)
            local x = (IsoUtils.XToScreen(label.x+0.5,label.y+0.5,label.z,0)-IsoCamera.getOffX(p))/zoom+left
            local y = (IsoUtils.YToScreen(label.x+0.5,label.y+0.5,label.z,0)-IsoCamera.getOffY(p))/zoom+top
            local manager = getTextManager()
            label.width = label.width or manager:MeasureStringX(UIFont.Small,label.text)
            local height = manager:getFontHeight(UIFont.Small)
            x, y = x-label.width/2, y-height-8
            local i = 1
            while i<=#placed do
                local rect = placed[i]
                if x < rect.x+rect.w and x+label.width > rect.x
                    and y < rect.y+height and y+height > rect.y then
                    y, i = rect.y+height+2, 1
                else i=i+1 end
            end
            if x+label.width>=left and x<=right and y+height>=top and y<=bottom then
                manager:DrawString(UIFont.Small,x+1,y+1,label.text,0,0,0,1)
                manager:DrawString(UIFont.Small,x,y,label.text,1,1,1,1)
                placed[#placed+1] = {x=x,y=y,w=label.width}
            end
        end
    end
end

--- Creates the invisible UI element that owns world-square highlights.
function HighlightUI:new()
    local ui = ISPanel.new(self, -1000, -1000, 1, 1)
    ui.background = false
    ui.border = false
    return ui
end

--- Attaches the shared highlight renderer when the first group is installed.
local function ensureUI()
    if highlightUI then return end
    highlightUI = HighlightUI:new()
    highlightUI:initialise()
    highlightUI:addToUIManager()
end

--- Replaces one independently owned highlight group.
function Highlights.replaceGroup(groupId, entries, labels)
    if type(groupId) ~= "string" then return false end
    labelGroups[groupId] = labels and #labels>0 and labels or nil
    if type(entries) ~= "table" or #entries == 0 then
        groups[groupId] = nil
        if labelGroups[groupId] then ensureUI() end
        return true
    end
    groups[groupId] = entries
    ensureUI()
    return true
end

--- Clears one highlight group without affecting other features.
function Highlights.clearGroup(groupId)
    groups[groupId] = nil
    labelGroups[groupId] = nil
end

--- Clears every active world highlight group.
function Highlights.clearAll()
    groups = {}
    labelGroups = {}
end

--- Converts one relative geometry node into a visible world highlight entry.
--- @param instance WaymanEntityInstance
--- @param node WaymanNode
--- @param playerNum integer
--- @param color table?
--- @return WaymanHighlightEntry
function Highlights.highlightRelativeNodeEntry(instance, node, playerNum, color)
    local square = getCell():getGridSquare(
        instance.origin.x + node.x,
        instance.origin.y + node.y,
        instance.origin.z + (node.z or 0)
    )
    if not square or not square:getFloor() then return nil end
    return {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        playerNum = playerNum,
        color = color,
    }
end

return Highlights
