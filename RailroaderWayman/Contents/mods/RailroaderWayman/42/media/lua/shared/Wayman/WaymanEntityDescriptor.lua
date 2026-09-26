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
--- Describes a known rail entity without applying client- or server-specific policy.
---@param object IsoObject multi-square part or master object.
---@param requestedFacing string? facing override for client-side inspection.
---@return WaymanEntityInstance?, string? # Returns nil and error message if the object is not a known rail entity or has no geometry.
function Descriptor.getInstance(object, requestedFacing)
    local description, err = Descriptor.describe(object, requestedFacing)
    if not description then return nil, err end

    description.data = description.master:getModData()[OBJECT_DATA_KEY] or {}
    return description
end

return Descriptor
