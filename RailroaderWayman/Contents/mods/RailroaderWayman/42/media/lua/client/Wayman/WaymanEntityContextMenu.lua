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

            if candidate.defaults.kind == "turn" then
                updateInstance = candidate
                break
            elseif candidate.defaults.kind == "turnout" then
                local switch = EntityDescriptor.instanceDataValueOrDefault(candidate, "switch")
                local expectedX = switch and candidate.origin.x + switch.x
                local expectedY = switch and candidate.origin.y + switch.y
                local expectedZ = switch and candidate.origin.z + (switch.z or 0)
                if switch
                    and clickedSquare:getX() == expectedX
                    and clickedSquare:getY() == expectedY
                    and clickedSquare:getZ() == expectedZ then
                    updateInstance = candidate
                    break
                elseif switch then
                    log("not switch square; expected " .. tostring(expectedX) .. ","
                        .. tostring(expectedY) .. "," .. tostring(expectedZ))
                else
                    log("menu skipped: switch geometry is missing")
                end
            end
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
