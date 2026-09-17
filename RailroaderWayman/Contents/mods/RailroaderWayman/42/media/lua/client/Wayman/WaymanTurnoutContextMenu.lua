require "Wayman/WaymanEntityGeometry"
require "ISUI/ISPanel"
require "ISUI/ISWorldObjectContextMenu"

local Geometry = RailroaderWaymanEntityGeometry
local OBJECT_DATA_KEY = "railroaderWayman"
local activeHighlights = {}
local clearAt = 0
local highlightUI

local AT_COLOR = { r = 1.0, g = 0.75, b = 0.05, a = 0.65 }
local SWITCH_COLOR = { r = 1.0, g = 0.10, b = 0.65, a = 0.65 }
local THROUGH_COLOR = { r = 0.10, g = 1.0, b = 0.15, a = 0.65 }
local DIVERGING_COLOR = { r = 0.10, g = 0.45, b = 1.0, a = 0.65 }

local HighlightUI = ISPanel:derive("RailroaderWaymanNodeHighlightUI")

function HighlightUI:prerender()
    for _, entry in ipairs(activeHighlights) do
        local color = entry.color
        addAreaHighlightForPlayer(
            entry.playerNum,
            entry.x, entry.y,
            entry.x + 1, entry.y + 1,
            entry.z,
            color.r, color.g, color.b, color.a
        )
    end
end

function HighlightUI:new()
    local ui = ISPanel.new(self, -1000, -1000, 1, 1)
    ui.background = false
    ui.border = false
    return ui
end

local function ensureHighlightUI()
    if highlightUI then return end
    highlightUI = HighlightUI:new()
    highlightUI:initialise()
    highlightUI:addToUIManager()
end

local function log(message)
    print("[RailroaderWayman] TurnoutMenu: " .. message)
end

local function getMaster(object)
    if not object then return nil end
    return object:getMasterObject() or object
end

local function getInstance(object)
    local master = getMaster(object)
    if not master then return nil end
    local entityScript = master:getEntityScript()
    local entityName = entityScript and entityScript:getName()
    local faces = entityName and Geometry[entityName]
    local spriteConfig = master:getSpriteConfig()
    local faceInfo = spriteConfig and spriteConfig:getFaceInfo()
    local facing = faceInfo and string.upper(faceInfo:getFaceName())
    local defaults = faces and faces[facing]
    if not defaults or defaults.kind ~= "turnout" then return nil end

    local data = master:getModData()[OBJECT_DATA_KEY]
    if not data or not data.id then return nil end

    return {
        master = master,
        defaults = defaults,
        data = data,
        originX = master:getX() - faceInfo:getMasterX(),
        originY = master:getY() - faceInfo:getMasterY(),
        originZ = master:getZ() - faceInfo:getMasterZ(),
    }
end

local function value(instance, key)
    local override = instance.data[key]
    if override ~= nil then return override end
    return instance.defaults[key]
end

local function clearHighlights()
    activeHighlights = {}
    clearAt = 0
    if highlightUI then
        highlightUI:setVisible(false)
        highlightUI:removeFromUIManager()
        highlightUI = nil
    end
end

local function highlightNode(instance, node, playerNum, color)
    local square = getCell():getGridSquare(
        instance.originX + node.x,
        instance.originY + node.y,
        instance.originZ + (node.z or 0)
    )
    if not square or not square:getFloor() then return end
    table.insert(activeHighlights, {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        playerNum = playerNum,
        color = color,
    })
end

local function showNodes(_worldobjects, playerNum, instance)
    clearHighlights()
    local at = value(instance, "at")
    local switch = value(instance, "switch")
    if at then highlightNode(instance, at, playerNum, AT_COLOR) end
    if switch then highlightNode(instance, switch, playerNum, SWITCH_COLOR) end
    for _, node in ipairs(value(instance, "throughNodes") or {}) do
        highlightNode(instance, node, playerNum, THROUGH_COLOR)
    end
    for _, node in ipairs(value(instance, "divergingNodes") or {}) do
        highlightNode(instance, node, playerNum, DIVERGING_COLOR)
    end
    ensureHighlightUI()
    -- Keep the diagnostic visible long enough to inspect, without leaving the
    -- floor highlighted for the rest of the session.
    clearAt = getTimestampMs() + 10000
    log("showing nodes for " .. tostring(instance.data.id)
        .. ": at=" .. tostring(at ~= nil)
        .. ", switch=" .. tostring(switch ~= nil)
        .. ", through=" .. tostring(#(value(instance, "throughNodes") or {}))
        .. ", diverging=" .. tostring(#(value(instance, "divergingNodes") or {})))
end

local function onTick()
    if clearAt > 0 and getTimestampMs() >= clearAt then clearHighlights() end
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    local clickedSquare
    for _, object in ipairs(worldobjects) do
        clickedSquare = object:getSquare()
        if clickedSquare then break end
    end
    if not clickedSquare then return end

    local instance
    local objects = clickedSquare:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local master = getMaster(object)
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
            local switch = value(candidate, "switch")
            local expectedX = switch and candidate.originX + switch.x
            local expectedY = switch and candidate.originY + switch.y
            local expectedZ = switch and candidate.originZ + (switch.z or 0)
            if switch
                and clickedSquare:getX() == expectedX
                and clickedSquare:getY() == expectedY
                and clickedSquare:getZ() == expectedZ then
                instance = candidate
                break
            elseif switch then
                log("not switch square; expected " .. tostring(expectedX) .. ","
                    .. tostring(expectedY) .. "," .. tostring(expectedZ))
            else
                log("menu skipped: switch geometry is missing")
            end
        elseif knownEntity then
            log("menu skipped: geometry/facing or railroaderWayman.id is missing")
        end
    end
    if not instance then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    context:addOption("Mostrar nodos", worldobjects, showNodes, playerNum, instance)
    log("added 'Mostrar nodos' for " .. tostring(instance.data.id))
end

Events.OnTick.Add(onTick)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

log("loaded")
