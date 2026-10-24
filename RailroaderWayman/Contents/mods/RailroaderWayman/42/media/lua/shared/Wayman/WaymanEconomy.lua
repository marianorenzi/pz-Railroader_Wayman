-- Dismantling uses the currently loaded construction recipe. Only the authority
-- removes the physical entity or awards materials; no consumption history is kept.
require "Wayman/WaymanEntityDescriptor"
require "Moveables/ISMoveableSpriteProps"

RailroaderWaymanEconomy = RailroaderWaymanEconomy or {}
local Economy = RailroaderWaymanEconomy
local Descriptor = RailroaderWaymanEntityDescriptor
local dismantling = {} -- only held during the synchronous native removal

-- This deliberately accepts non-operative tracks too; geometry policy stays in
-- EntityDescriptor.describe(). Check the module to reject similarly named mods.
function Economy.describe(object)
    local master = Descriptor.getMaster(object)
    if not master or not master:getSquare() then return nil end
    local script = master:getEntityScript()
    local name = script and script:getName()
    local module = script and script:getModule()
    if not module or module:getName() ~= "RailroaderWayman" then return nil end
    local config = master:getSpriteConfig()
    local info = config and config:getObjectInfo()
    local component = info and info:getRecipe()
    local recipe = component and component:getCraftRecipe()
    if not recipe then return nil end
    return master, recipe, name
end

-- Native inputs already include the current costMultiplier. For alternatives,
-- return the first allowed item, once per required unit, never every alternative.
function Economy.materials(recipe)
    local materials = {}
    local inputs = recipe:getInputs()
    for index = 0, inputs:size() - 1 do
        local input = inputs:get(index)
        if not input:isKeep() then
            local items = input:getPossibleInputItems()
            if not items or items:size() == 0 then return nil, "recipe input has no recoverable item" end
            local fullType = items:get(0):getFullName()
            local qty = input:getIntAmount(fullType)
            materials[fullType] = (materials[fullType] or 0) + qty
        end
    end
    return materials
end

function Economy.dismantle(character, part, chance)
    if isClient() then return false, "server authority required" end
    local master, recipe = Economy.describe(part)
    if not master or part:getObjectIndex() < 0 or master:getObjectIndex() < 0 then
        return false, "missing entity"
    end
    if dismantling[master] then return false, "dismantling in progress" end
    local objects = ArrayList.new()
    if not master:getSpriteConfig():getAllMultiSquareObjects(objects) or objects:size() == 0 then
        return false, "entity is not fully loaded"
    end
    -- Reject any protected square in the footprint, not only the clicked tile.
    for index = 0, objects:size() - 1 do
        local safehouse = SafeHouse.isSafeHouse(objects:get(index):getSquare(), nil, false)
        if safehouse and not safehouse:playerAllowed(character) then return false, "protected safehouse" end
    end
    local materials, materialReason = Economy.materials(recipe)
    if not materials then return false, materialReason end
    local dropSquare = part:getSquare()
    -- The native safe removal gathers and removes the complete multi-square
    -- entity, in SP and on the server. Its normal events withdraw the graph.
    -- Guard only nested removal callbacks; nothing is written to object modData.
    dismantling[master] = true
    local removed, removeReason = pcall(function()
        master:getSquare():transmitRemoveItemFromSquare(master)
    end)
    dismantling[master] = nil
    if not removed then return false, tostring(removeReason) end
    if master:getObjectIndex() >= 0 then return false, "master was not removed" end

    -- Award once, only after the master is gone. Subsequent requests fail the
    -- physical existence check. AddWorldInventoryItem places items on the floor.
    local added = 0
    for fullType, qty in pairs(materials) do
        for _ = 1, qty do
            if ZombRand(100) < chance then
                dropSquare:AddWorldInventoryItem(fullType, 0.5, 0.5, 0)
                added = added + 1
            end
        end
    end
    return true, added
end

-- Keep vanilla's menu, cursor, tool checks, timed action and animation. Only
-- replace the material/removal step for Wayman entities; other objects delegate.
local vanillaScrapObject = ISMoveableSpriteProps.scrapObject
function ISMoveableSpriteProps:scrapObject(character)
    if not Economy.describe(self.object) then return vanillaScrapObject(self, character) end
    if isClient() then return end
    local result, chance = self:canScrapObject(character)
    if not result.canScrap then return end
    local ok, added = Economy.dismantle(character, self.object, chance)
    if not ok then return end
    self:scrapGiveXp(character)
    if added > 0 then self:playScrapSuccessSound(character) end
    self:scrapHaloNoteCheck(character, added)
end

return Economy
