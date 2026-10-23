-- Client context-menu integration for physical Wayman rail entities.
require "Wayman/WaymanEntityDescriptor"
require "Wayman/WaymanNodeEditor"
require "ISUI/ISWorldObjectContextMenu"

local EntityDescriptor = RailroaderWaymanEntityDescriptor
local NodeEditor = RailroaderWaymanNodeEditor

--- Writes a namespaced context-menu diagnostic to the game log.
local function log(message)
    print("[RailroaderWayman] EntityMenu: " .. message)
end

--- Opens the geometry editor for the entity selected by the context menu.
local function editRailEntity(_worldobjects, playerNum, instance)
    NodeEditor.open(instance, playerNum)
end

--- Adds diagnostic and recovery actions for eligible clicked rail tiles.
local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if not getDebug() then return end
    local clickedSquare
    for _, object in ipairs(worldobjects) do
        clickedSquare = object:getSquare()
        if clickedSquare then break end
    end
    if not clickedSquare then return end

    local updateInstance
    local objects = clickedSquare:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local candidate = EntityDescriptor.getInstance(object)
        if candidate then
            log("candidate " .. tostring(candidate.entityName)
                .. " facing " .. tostring(candidate.facing)
                .. " at clicked square " .. tostring(clickedSquare:getX()) .. ","
                .. tostring(clickedSquare:getY()) .. "," .. tostring(clickedSquare:getZ())
                .. "; id=" .. tostring(candidate.data.id))

            -- Debug geometry inspection is available on every tile of the
            -- entity, even after moving its physical switch interaction point.
            updateInstance = candidate
            break
        end
    end
    if not updateInstance then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    if updateInstance then
        context:addOption(getText("UI_Wayman_ContextEditNodes"), worldobjects, editRailEntity, playerNum, updateInstance)
        log("added 'EditNodes' ContextMenu option for " .. tostring(updateInstance.data.id))
    end
end

--- Logs the authoritative result of a manual entity update request.
local function onServerCommand(module, command, args)
    if module ~= "RailroaderWayman" or command ~= "railEntityUpdated" then return end
    if args and args.ok then
        log("server updated " .. tostring(args.id))
    else
        log("server update failed: " .. tostring(args and args.reason))
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnServerCommand.Add(onServerCommand)

log("loaded")
