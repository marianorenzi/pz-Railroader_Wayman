-- Side-neutral entity inspection helpers. This module resolves multi-square
-- masters and derives script name, facing, trusted geometry defaults, and origin
-- for reuse by both authoritative server logic and client interaction code.
require "Wayman/WaymanEntityGeometry"

RailroaderWaymanEntityDescriptor = RailroaderWaymanEntityDescriptor or {}
local Descriptor = RailroaderWaymanEntityDescriptor
local Geometry = RailroaderWaymanEntityGeometry

---@class WaymanEntityDescription
---@field master IsoObject multi-square master object
---@field entityName string entity script name
---@field facing string facing name (e.g. "N", "E", "S", "W")
---@field defaults table trusted geometry defaults for the entity and facing
---@field origin { x: number, y: number, z: number } world coordinates of the entity origin

---@class WaymanEntityInstance : WaymanEntityDescription
---@field data table entity Wayman modData namespace
---@field componentIndex integer? position in the physical entity's component definitions

--- Resolves any multi-square part to its authoritative master object.
---@param object IsoObject multi-square part or master object.
---@return IsoObject? # Returns the master object or nil if the input is invalid.
function Descriptor.getMaster(object)
    if not object then return nil end
    return object:getMasterObject() or object
end

--- Describes a known rail entity without applying client- or server-specific policy.
---@param object IsoObject multi-square part or master object.
---@param requestedFacing string? facing override for client-side inspection.
---@return WaymanEntityDescription?, string? # Returns nil and error message if the object is not a known rail entity or has no geometry.
function Descriptor.describe(object, requestedFacing)
    local master = Descriptor.getMaster(object)
    if not master or not master:getSquare() then return nil, "master or square is unavailable" end

    local entityScript = master:getEntityScript()
    local entityName = entityScript and entityScript:getName()
    local faces = entityName and Geometry[entityName]
    local spriteConfig = master:getSpriteConfig()
    local faceInfo = spriteConfig and spriteConfig:getFaceInfo()
    local facing = (faceInfo and faceInfo:getFaceName()) or requestedFacing
    facing = facing and string.upper(facing)
    local defaults = faces and faces[facing]
    if not defaults then
        return nil, "no geometry for " .. tostring(entityName) .. " facing " .. tostring(facing)
    end

    return {
        master = master,
        entityName = entityName,
        facing = facing,
        defaults = defaults,
        origin = {
            x = master:getX() - (faceInfo and faceInfo:getMasterX() or 0),
            y = master:getY() - (faceInfo and faceInfo:getMasterY() or 0),
            z = master:getZ() - (faceInfo and faceInfo:getMasterZ() or 0),
        },
    }
end

local OBJECT_DATA_KEY = "railroaderWayman"
--- Lists the independently editable logical instances on one physical entity.
---@param object IsoObject multi-square part or master object.
---@param requestedFacing string? facing override for client-side inspection.
---@return WaymanEntityInstance[]?, string?
function Descriptor.getInstances(object, requestedFacing)
    local description, err = Descriptor.describe(object, requestedFacing)
    if not description then return nil, err end

    local components = description.defaults.components
    if not components then
        description.data = Descriptor.instanceData(description)
        return { description }
    end
    local instances = {}
    for index, component in ipairs(components) do
        local defaults = {}
        for key, value in pairs(component) do defaults[key] = value end
        defaults.kind = component.type
        local instance = {
            master = description.master, entityName = description.entityName,
            facing = description.facing, origin = description.origin,
            defaults = defaults, componentIndex = index,
        }
        instance.data = Descriptor.instanceData(instance)
        table.insert(instances, instance)
    end
    return instances
end

--- Resolves a logical component by its persisted owner ID or definition position.
--- A compound entity requires an explicit selection; simple callers stay unchanged.
---@param object IsoObject
---@param requestedFacing string?
---@param selection string|integer?
---@return WaymanEntityInstance?, string?
function Descriptor.getInstance(object, requestedFacing, selection)
    local instances, err = Descriptor.getInstances(object, requestedFacing)
    if not instances then return nil, err end
    if selection == nil and #instances == 1 then return instances[1] end
    for index, instance in ipairs(instances) do
        if (type(selection) == "number" and index == selection)
            or (type(selection) == "string" and instance.data.id == selection) then
            return instance
        end
    end
    return nil, "component selection is missing or unknown"
end

--- Reads only this component's server-owned modData, preserving the legacy layout.
function Descriptor.instanceData(instance)
    local data = instance.master:getModData()[OBJECT_DATA_KEY] or {}
    if instance.componentIndex then
        return (data.components and data.components[instance.componentIndex]) or {}
    end
    return data
end

--- Replaces one component's overrides without overwriting its physical siblings.
function Descriptor.storeData(instance, saved)
    local modData = instance.master:getModData()
    if instance.componentIndex then
        local data = modData[OBJECT_DATA_KEY] or {}
        data.components = data.components or {}
        -- Explicit recovery may initialize a later component first. Keep a
        -- dense array so its position survives serialization and removal.
        for index = 1, instance.componentIndex do
            data.components[index] = data.components[index] or {}
        end
        saved.type = instance.defaults.kind
        data.components[instance.componentIndex] = saved
        modData[OBJECT_DATA_KEY] = data
    else
        modData[OBJECT_DATA_KEY] = saved
    end
    instance.data = saved
end

--- Fetches the instance mod data
--- @param instance WaymanEntityInstance
--- @param key string
--- @return any
--- @return boolean isDefault
function Descriptor.instanceDataValueOrDefault(instance, key)
    local override = instance.data[key]
    if override ~= nil then return override, false end
    return instance.defaults[key], true
end

return Descriptor
