-- Registers and handles the configurable keyboard shortcut that toggles the
-- singleton Wayman graph editor independently of the world map.
require "Wayman/WaymanGraphEditor"

local Editor = RailroaderWaymanGraphEditor
local WORLD_DATA_KEY = "RailroaderWayman_World"
local BINDING_ID = "wayman_toggle_graph_editor"

table.insert(keyBinding, { value = "[RailroaderWayman]" })
table.insert(keyBinding, { value = BINDING_ID, key = Keyboard.KEY_PERIOD })

--- Toggles the singleton graph editor from the configured global key binding.
local function onKeyPressed(key)
    if key ~= getCore():getKey(BINDING_ID) then return end
    if ISChat and ISChat.focused then return end
    if Editor.instance and Editor.instance.newEdgeId
        and Editor.instance.newEdgeId:isFocused() then return end
    if Editor.instance and Editor.instance:getIsVisible() then
        Editor.instance:close()
        return
    end
    local data = ModData.get(WORLD_DATA_KEY) or {
        availableNodes = {}, edges = {}, switches = {}, revision = 0,
    }
    Editor.open(data)
end

Events.OnKeyPressed.Add(onKeyPressed)
