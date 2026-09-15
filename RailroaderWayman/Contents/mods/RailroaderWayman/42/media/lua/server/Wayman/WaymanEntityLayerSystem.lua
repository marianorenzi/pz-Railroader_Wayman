require "Wayman/WaymanEntityLayerDefinitions"

RailroaderWaymanEntityLayers = RailroaderWaymanEntityLayers or {}

local pending = {}

local function getMaster(object)
    if not object then return nil end
    return object:getMasterObject() or object
end

local function addOverlay(square, spriteName)
    -- This overload resolves the registered IsoSprite by tile name. The
    -- two-argument overload treats the string as a texture page and creates a
    -- transient sprite that cannot be restored reliably from the save.
    local object = IsoObject.new(getCell(), square, spriteName)
    square:AddTileObject(object)
    if isServer() then
        object:transmitCompleteItemToClients()
    end
    triggerEvent("OnObjectAdded", object)
end

local function removeOverlay(square, spriteName)
    local objects = square:getObjects()
    for index = objects:size() - 1, 0, -1 do
        local object = objects:get(index)
        if object:getSpriteName() == spriteName and object:getEntityScript() == nil then
            square:transmitRemoveItemFromSquare(object)
            return
        end
    end
end

local function applyAt(originX, originY, originZ, facing, definitionName, remove)
    local definition = RailroaderWaymanEntityLayers.Definitions[definitionName]
    local facingDefinition = definition and definition[facing]
    if not facingDefinition then
        print("[RailroaderWayman] Missing visual layers for " .. tostring(definitionName)
            .. " facing " .. tostring(facing))
        return
    end

    local operation = remove and "Removing" or "Applying"
    print("[RailroaderWayman] " .. operation .. " visual layers for " .. tostring(definitionName)
        .. "(" .. tostring(originX) .. "," .. tostring(originY) .. ") facing " .. tostring(facing))

    for _, layer in ipairs(facingDefinition.layers) do
        for rowIndex, row in ipairs(layer.rows) do
            for columnIndex, spriteName in ipairs(row) do
                if spriteName then
                    local offsetX = columnIndex - 1
                    local offsetY = rowIndex - 1
                    local square = getCell():getGridSquare(
                        originX + offsetX,
                        originY + offsetY,
                        originZ
                    )
                    if square then
                        if remove then
                            removeOverlay(square, spriteName)
                        else
                            addOverlay(square, spriteName)
                        end
                        square:RecalcAllWithNeighbours(true)
                    else
                        print("[RailroaderWayman] Missing overlay square at offset "
                            .. offsetX .. "," .. offsetY)
                    end
                end
            end
        end
    end
end

local function applyPendingLayers()
    if #pending == 0 then return end

    local queued = pending
    pending = {}
    local applied = {}

    for _, entry in ipairs(queued) do
        local object = entry.object
        if object and object:getSquare() then
            local anchor = getMaster(object)
            local spriteConfig = anchor and anchor:getSpriteConfig()
            local faceInfo = spriteConfig and spriteConfig:getFaceInfo()
            if anchor and faceInfo then
                local originX = anchor:getX() - faceInfo:getMasterX()
                local originY = anchor:getY() - faceInfo:getMasterY()
                local originZ = anchor:getZ() - faceInfo:getMasterZ()
                local key = entry.definitionName .. ":" .. entry.facing .. ":"
                    .. originX .. ":" .. originY .. ":" .. originZ

                if not applied[key] then
                    applied[key] = true
                    applyAt(originX, originY, originZ, entry.facing, entry.definitionName, false)
                end
            end
        end
    end
end

Events.OnTick.Add(applyPendingLayers)

local function findDefinitionForEntity(entityName)
    return RailroaderWaymanEntityLayers.Definitions[entityName] and entityName or nil
end

function RailroaderWaymanEntityLayers.OnCreate(params)
    local object = params and params.thumpable
    if not object then return end

    local anchor = getMaster(object)
    local entityScript = anchor and anchor:getEntityScript()
    local definitionName = entityScript and findDefinitionForEntity(entityScript:getName())
    if not definitionName then return end

    table.insert(pending, {
        object = object,
        facing = params.facing and string.upper(params.facing),
        definitionName = definitionName,
    })
end

local function onObjectAboutToBeRemoved(object)
    if not object then return end

    local spriteConfig = object:getSpriteConfig()
    if not spriteConfig or not spriteConfig:isMultiSquareMaster() then return end

    local anchor = object

    local entityScript = anchor:getEntityScript()
    local definitionName = entityScript and findDefinitionForEntity(entityScript:getName())
    if not definitionName then return end

    local faceInfo = spriteConfig:getFaceInfo()
    if not faceInfo then return end

    local originX = anchor:getX() - faceInfo:getMasterX()
    local originY = anchor:getY() - faceInfo:getMasterY()
    local originZ = anchor:getZ() - faceInfo:getMasterZ()
    local facing = string.upper(faceInfo:getFaceName())

    applyAt(originX, originY, originZ, facing, definitionName, true)
end

Events.OnObjectAboutToBeRemoved.Add(onObjectAboutToBeRemoved)
