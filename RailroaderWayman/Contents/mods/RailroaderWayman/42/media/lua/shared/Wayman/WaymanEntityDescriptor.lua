-- Side-neutral entity inspection helpers. This module resolves multi-square
-- masters and derives script name, facing, trusted geometry defaults, and origin
-- for reuse by both authoritative server logic and client interaction code.
require "Wayman/WaymanEntityGeometry"

RailroaderWaymanEntityDescriptor = RailroaderWaymanEntityDescriptor or {}
local Descriptor = RailroaderWaymanEntityDescriptor
local Geometry = RailroaderWaymanEntityGeometry

--- Resolves any multi-square part to its authoritative master object.
function Descriptor.getMaster(object)
    if not object then return nil end
    return object:getMasterObject() or object
end

--- Describes a known rail entity without applying client- or server-specific policy.
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

return Descriptor
