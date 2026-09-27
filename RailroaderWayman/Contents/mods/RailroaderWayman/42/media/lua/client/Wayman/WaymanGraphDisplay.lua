-- Shared client presentation state for graph visualization. It stores the
-- editor's map/highlight options and translates graph snapshots into world
-- highlight groups without depending on an editor or map instance.
require "Wayman/WaymanWorldHighlights"

RailroaderWaymanGraphDisplay = RailroaderWaymanGraphDisplay or {}
local Display = RailroaderWaymanGraphDisplay
local WorldHighlights = RailroaderWaymanWorldHighlights
local INSPECTION_GROUP = "graph-inspection"

Display.options = Display.options or {
    showAllEdges = true,
    showAvailableNodes = true,
    showSelectedEdge = true,
    showWorldHighlights = false,
}

--- Rebuilds loaded-square highlights from the current graph view.
local function refreshWorldHighlights(data)
    if not Display.options.showWorldHighlights or type(data) ~= "table" then
        WorldHighlights.clearGroup(INSPECTION_GROUP)
        return
    end

    local entries = {}
    local blockColors = {
        at = WorldHighlights.colors.at,
        through = WorldHighlights.colors.through,
        diverge = WorldHighlights.colors.diverge,
    }
    local function addNode(node, color)
        if type(node) ~= "table" then return end
        local square = getCell():getGridSquare(node.x, node.y, node.z or 0)
        if not square or not square:getFloor() then return end
        table.insert(entries, {
            x = square:getX(), y = square:getY(), z = square:getZ(),
            playerNum = 0, color = color,
        })
    end
    for _, block in ipairs(data.availableNodes or {}) do
        local color = blockColors[block.id] or WorldHighlights.colors.nodes
        for _, node in ipairs(block.nodes or {}) do addNode(node, color) end
    end
    for _, blocks in pairs(data.edges or {}) do
        for _, block in ipairs(blocks or {}) do
            local color = blockColors[block.id] or WorldHighlights.colors.nodes
            for _, node in ipairs(block.nodes or {}) do addNode(node, color) end
        end
    end
    for _, switch in ipairs(data.switches or {}) do
        addNode(switch.at, WorldHighlights.colors.at)
    end
    WorldHighlights.replaceGroup(INSPECTION_GROUP, entries)
end

--- Applies display options without coupling the editor to a renderer instance.
function Display.setOptions(options, data)
    for key, value in pairs(options or {}) do
        if Display.options[key] ~= nil then Display.options[key] = value == true end
    end
    refreshWorldHighlights(data)
end

--- Refreshes graph inspection after draft or authoritative data changes.
function Display.refresh(data)
    refreshWorldHighlights(data)
end

--- Returns the persistent client-only graph display configuration.
function Display.getOptions()
    return Display.options
end

return Display
