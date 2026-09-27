-- Client context-menu integration for physical Wayman rail entities. It resolves
-- clicked multi-square parts, exposes manual server recovery/update actions, and
-- requests short-lived diagnostic highlights for turnout geometry.
require "Wayman/WaymanEntityGeometry"
require "Wayman/WaymanEntityDescriptor"
require "Wayman/WaymanWorldHighlights"
require "ISUI/ISWorldObjectContextMenu"

local Geometry = RailroaderWaymanEntityGeometry
local EntityDescriptor = RailroaderWaymanEntityDescriptor
local WorldHighlights = RailroaderWaymanWorldHighlights
local OBJECT_DATA_KEY = "railroaderWayman"
local clearAt = 0
local HIGHLIGHT_GROUP = "entity-context-menu"

--- Writes a namespaced context-menu diagnostic to the game log.
local function log(message)
    print("[RailroaderWayman] EntityMenu: " .. message)
end

--- Describes a known turn or turnout instance using local overrides and defaults.
local function getInstance(object)
    local descriptor = EntityDescriptor.describe(object)
    if not descriptor then return nil end

    local data = descriptor.master:getModData()[OBJECT_DATA_KEY] or {}

    return {
        master = descriptor.master,
        defaults = descriptor.defaults,
        data = data,
        facing = descriptor.facing,
        originX = descriptor.origin.x,
        originY = descriptor.origin.y,
        originZ = descriptor.origin.z,
    }
end

--- Reads a geometry override and falls back to the generated entity default.
local function value(instance, key)
    local override = instance.data[key]
    if override ~= nil then return override end
    return instance.defaults[key]
end

--- Removes all active diagnostic highlights and their UI renderer.
local function clearHighlights()
    clearAt = 0
    WorldHighlights.clearGroup(HIGHLIGHT_GROUP)
end

--- Converts one relative geometry node into a visible world highlight entry.
local function highlightEntry(instance, node, playerNum, color)
    local square = getCell():getGridSquare(
        instance.originX + node.x,
        instance.originY + node.y,
        instance.originZ + (node.z or 0)
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

--- Highlights turnout geometry around the selected entity for ten seconds.
local function showNodes(_worldobjects, playerNum, instance)
    clearHighlights()
    local entries = {}
    local function add(node, color)
        if not node then return end
        local entry = highlightEntry(instance, node, playerNum, color)
        if entry then table.insert(entries, entry) end
    end
    local at = value(instance, "at")
    local switch = value(instance, "switch")
    add(at, WorldHighlights.colors.at)
    add(switch, WorldHighlights.colors.switch)
    for _, node in ipairs(value(instance, "throughNodes") or {}) do
        add(node, WorldHighlights.colors.through)
    end
    for _, node in ipairs(value(instance, "divergingNodes") or {}) do
        add(node, WorldHighlights.colors.diverge)
    end
    WorldHighlights.replaceGroup(HIGHLIGHT_GROUP, entries)
    -- Keep the diagnostic visible long enough to inspect, without leaving the
    -- floor highlighted for the rest of the session.
    clearAt = getTimestampMs() + 10000
    log("showing nodes for " .. tostring(instance.data.id)
        .. ": at=" .. tostring(at ~= nil)
        .. ", switch=" .. tostring(switch ~= nil)
        .. ", through=" .. tostring(#(value(instance, "throughNodes") or {}))
        .. ", diverging=" .. tostring(#(value(instance, "divergingNodes") or {})))
end

--- Copies the entity modData namespace before sending it to the server.
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

--- Requests authoritative recovery or geometry refresh for one physical entity.
local function updateRailEntity(_worldobjects, playerNum, instance)
    local master = instance.master
    local square = master:getSquare()
    if not square then
        log("update skipped: master square is unavailable")
        return
    end
    local args = {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = master:getObjectIndex(),
        facing = instance.facing,
        modData = copy(master:getModData()[OBJECT_DATA_KEY] or {}),
    }
    local player = getSpecificPlayer(playerNum)
    if isClient() then
        sendClientCommand(player, "RailroaderWayman", "updateRailEntity", args)
        log("requested server update for id=" .. tostring(args.modData.id))
    elseif RailroaderWaymanEntityRuntime then
        local ok, result = RailroaderWaymanEntityRuntime.SaveGeometry(
            master, args.modData, args.facing)
        log(ok and ("updated " .. tostring(result)) or ("update failed: " .. tostring(result)))
    end
end

--- Expires temporary node highlights after their diagnostic timeout.
local function onTick()
    if clearAt > 0 and getTimestampMs() >= clearAt then clearHighlights() end
end

--- Adds diagnostic and recovery actions for eligible clicked rail tiles.
local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    local clickedSquare
    for _, object in ipairs(worldobjects) do
        clickedSquare = object:getSquare()
        if clickedSquare then break end
    end
    if not clickedSquare then return end

    local showInstance
    local updateInstance
    local objects = clickedSquare:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local master = EntityDescriptor.getMaster(object)
        local entityScript = master and master:getEntityScript()
        local entityName = entityScript and entityScript:getName()
        local knownEntity = entityName and Geometry[entityName]
        if knownEntity then
            local spriteConfig = master:getSpriteConfig()
            local faceInfo = spriteConfig and spriteConfig:getFaceInfo()
            local facing = faceInfo and string.upper(faceInfo:getFaceName())
            local data = master:getModData()[OBJECT_DATA_KEY]
            log("candidate " .. tostring(entityName) .. " facing " .. tostring(facing)
                .. " at clicked square " .. tostring(clickedSquare:getX()) .. ","
                .. tostring(clickedSquare:getY()) .. "," .. tostring(clickedSquare:getZ())
                .. "; id=" .. tostring(data and data.id))
        end

        local candidate = getInstance(object)
        if candidate then
            if candidate.defaults.kind == "turn" then
                updateInstance = updateInstance or candidate
            elseif candidate.defaults.kind == "turnout" then
                local switch = value(candidate, "switch")
                local expectedX = switch and candidate.originX + switch.x
                local expectedY = switch and candidate.originY + switch.y
                local expectedZ = switch and candidate.originZ + (switch.z or 0)
                if switch
                    and clickedSquare:getX() == expectedX
                    and clickedSquare:getY() == expectedY
                    and clickedSquare:getZ() == expectedZ then
                    showInstance = candidate
                    updateInstance = candidate
                    break
                elseif switch then
                    log("not switch square; expected " .. tostring(expectedX) .. ","
                        .. tostring(expectedY) .. "," .. tostring(expectedZ))
                else
                    log("menu skipped: switch geometry is missing")
                end
            end
        elseif knownEntity then
            log("menu skipped: geometry/facing is missing")
        end
    end
    if not showInstance and not updateInstance then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    if showInstance then
        context:addOption(getText("UI_Wayman_ContextShowNodes"), worldobjects,
            showNodes, playerNum, showInstance)
    end
    if updateInstance then
        context:addOption(getText("UI_Wayman_ContextUpdateEntity"), worldobjects, updateRailEntity,
            playerNum, updateInstance)
        log("added 'Update rail entity' for " .. tostring(updateInstance.data.id))
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

Events.OnTick.Add(onTick)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnServerCommand.Add(onServerCommand)

log("loaded")
