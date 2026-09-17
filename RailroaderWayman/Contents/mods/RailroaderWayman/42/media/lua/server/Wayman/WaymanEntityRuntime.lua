require "Wayman/WaymanEntityGeometry"

RailroaderWaymanEntityRuntime = RailroaderWaymanEntityRuntime or {}

local WORLD_DATA_KEY = "RailroaderWayman_World"
local OBJECT_DATA_KEY = "railroaderWayman"
local pending = {}

local function log(message)
    print("[RailroaderWayman] EntityRuntime: " .. message)
end

local function getMaster(object)
    if not object then return nil end
    return object:getMasterObject() or object
end

local function nextId(kind)
    local worldData = ModData.getOrCreate(WORLD_DATA_KEY)
    local counterKey = kind == "turnout" and "nextTurnoutId" or "nextTurnId"
    local value = worldData[counterKey] or 1
    worldData[counterKey] = value + 1
    return (kind == "turnout" and "turnout_" or "turn_") .. tostring(value)
end

local function initialize(object, requestedFacing)
    local master = getMaster(object)
    if not master or not master:getSquare() then
        log("initialization skipped: master or square is unavailable")
        return false
    end

    local entityScript = master:getEntityScript()
    local entityName = entityScript and entityScript:getName()
    local faces = entityName and RailroaderWaymanEntityGeometry[entityName]
    local spriteConfig = master:getSpriteConfig()
    local faceInfo = spriteConfig and spriteConfig:getFaceInfo()
    local facing = requestedFacing or (faceInfo and faceInfo:getFaceName())
    facing = facing and string.upper(facing)
    local geometry = faces and faces[facing]
    if not geometry then
        log("initialization skipped: no geometry for " .. tostring(entityName)
            .. " facing " .. tostring(facing))
        return true
    end

    local objectData = master:getModData()
    local waymanData = objectData[OBJECT_DATA_KEY]
    if waymanData and waymanData.id then
        log("already initialized: " .. tostring(waymanData.id))
        return true
    end

    -- Static geometry stays in WaymanEntityGeometry. Instance data starts with
    -- only its stable identifier; later edits may add geometry overrides here.
    waymanData = { id = nextId(geometry.kind) }
    objectData[OBJECT_DATA_KEY] = waymanData
    if isServer() then
        master:transmitModData()
    end
    log("assigned " .. tostring(waymanData.id) .. " to " .. tostring(entityName)
        .. " facing " .. tostring(facing) .. " at " .. tostring(master:getX())
        .. "," .. tostring(master:getY()) .. "," .. tostring(master:getZ()))
    return true
end

local function initializePending()
    if #pending == 0 then return end
    local queued = pending
    pending = {}
    for _, entry in ipairs(queued) do
        initialize(entry.object, entry.facing)
    end
end

function RailroaderWaymanEntityRuntime.OnCreate(params)
    -- Clients wait for the authoritative object's modData from SP/the server.
    if isClient() then
        log("OnCreate ignored on client")
        return
    end
    local object = params and params.thumpable
    if not object then
        log("OnCreate ignored: params.thumpable is nil")
        return
    end

    local spriteConfig = object:getSpriteConfig()
    if not spriteConfig or not spriteConfig:isMultiSquareMaster() then
        return
    end

    log("OnCreate queued facing " .. tostring(params.facing))
    table.insert(pending, {
        object = object,
        facing = params.facing and string.upper(params.facing) or nil,
    })
end

Events.OnTick.Add(initializePending)

log("loaded; authoritative=" .. tostring(not isClient()))
