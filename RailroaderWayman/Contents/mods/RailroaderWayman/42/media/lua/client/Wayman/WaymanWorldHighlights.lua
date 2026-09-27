-- Reusable client renderer for colored world-square highlights. Features own
-- independent named groups so context diagnostics, graph inspection, and future
-- entity editors can replace or clear their highlights without affecting others.
require "ISUI/ISPanel"

RailroaderWaymanWorldHighlights = RailroaderWaymanWorldHighlights or {}
local Highlights = RailroaderWaymanWorldHighlights

Highlights.colors = Highlights.colors or {
    at = { r = 1.0, g = 0.75, b = 0.05, a = 0.65 },
    switch = { r = 1.0, g = 0.10, b = 0.65, a = 0.65 },
    through = { r = 0.10, g = 1.0, b = 0.15, a = 0.65 },
    diverge = { r = 0.10, g = 0.45, b = 1.0, a = 0.65 },
    nodes = { r = 0.10, g = 0.90, b = 1.0, a = 0.65 },
}

local groups = {}
local highlightUI
local HighlightUI = ISPanel:derive("RailroaderWaymanWorldHighlightUI")

--- Draws every active highlight group before the diagnostic UI renders.
function HighlightUI:prerender()
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
function Highlights.replaceGroup(groupId, entries)
    if type(groupId) ~= "string" then return false end
    if type(entries) ~= "table" or #entries == 0 then
        groups[groupId] = nil
        return true
    end
    groups[groupId] = entries
    ensureUI()
    return true
end

--- Clears one highlight group without affecting other features.
function Highlights.clearGroup(groupId)
    groups[groupId] = nil
end

--- Clears every active world highlight group.
function Highlights.clearAll()
    groups = {}
end

return Highlights
