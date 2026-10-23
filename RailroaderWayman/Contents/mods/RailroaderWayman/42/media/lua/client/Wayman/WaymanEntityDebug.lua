-- Optional identity capture for test saves. Never run or store data on a server.
if isServer() then return end
if not getDebug() then return end

require "Wayman/WaymanGraphData"
require "Wayman/WaymanEntityDescriptor"
require "ISUI/ISWorldObjectContextMenu"

RailroaderWaymanEntityDebug = {}
local EntityDebug = RailroaderWaymanEntityDebug
local GraphData = RailroaderWaymanGraphData
local Descriptor = RailroaderWaymanEntityDescriptor
local WORLD_DATA_KEY = "RailroaderWayman_World"
local OBJECT_DATA_KEY = "railroaderWayman"
local clientData
local watching = false

---@class WaymanDebugEntityIdentity
---@field entityName string
---@field facing string

---@class WaymanEntityValidationDebugData
---@field enabled boolean
---@field entities table<string,WaymanDebugEntityIdentity>

--- Returns debug data without creating it until the user enables capture.
---@param create boolean?
---@return WaymanEntityValidationDebugData?
local function state(create)
    if isServer() then return nil end
    if not getDebug() then return nil end
    -- MP clients keep this inventory outside synchronized world ModData.
    if isClient() then
        if create and not clientData then clientData = { enabled = false, entities = {} } end
        return clientData
    end
    local worldData = create and ModData.getOrCreate(WORLD_DATA_KEY) or ModData.get(WORLD_DATA_KEY)
    if not worldData then return nil end
    if create then
        worldData.debug = worldData.debug or {}
        worldData.debug.entityValidation = worldData.debug.entityValidation
            or { enabled = false, entities = {} }
    end
    return worldData.debug and worldData.debug.entityValidation
end

---@return boolean
function EntityDebug.isEnabled()
    local data = state()
    return data ~= nil and data.enabled == true
end

--- Records only observed identity; geometry remains in Wayman's regular records.
---@param entity WaymanEntityDescription
---@param owner string
function EntityDebug.capture(entity, owner)
    if not EntityDebug.isEnabled() or type(owner) ~= "string" then return end
    state().entities[owner] = { entityName = entity.entityName, facing = entity.facing }
end

---@param owner string
function EntityDebug.remove(owner)
    local data = state()
    if data then data.entities[owner] = nil end
end

--- Owner lifetime comes from authority, never from whether a chunk is loaded.
function EntityDebug.onWorldData(worldData)
    local data = state()
    if not data then return end
    local owners = {}
    for _, block in ipairs(worldData.availableNodes or {}) do owners[block.owner] = true end
    for _, blocks in pairs(worldData.edges or {}) do
        for _, block in ipairs(blocks) do owners[block.owner] = true end
    end
    for _, switch in ipairs(worldData.switches or {}) do owners[switch.owner] = true end
    for owner in pairs(data.entities) do if not owners[owner] then data.entities[owner] = nil end end
end

--- Only registered owners can be linked to the existing graph export.
local function captureObject(object)
    local entity = Descriptor.describe(object)
    if not entity then return end
    local data = entity.master:getModData()[OBJECT_DATA_KEY]
    if data then EntityDebug.capture(entity, data.id) end
end

local function captureSquare(square, seen)
    if not EntityDebug.isEnabled() then return end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local master = Descriptor.getMaster(objects:get(index))
        if master and (not seen or not seen[master]) then
            if seen then seen[master] = true end
            captureObject(master)
        end
    end
end

--- Backfills identities from already loaded chunks, without loading other chunks.
function EntityDebug.captureLoaded()
    if not EntityDebug.isEnabled() then return end
    local cell = getCell()
    if not cell then return end
    local seen, chunks = {}, {}
    for playerNum = 0, getNumActivePlayers() - 1 do
        local map = cell:getChunkMap(playerNum)
        if map then
            local width = map:getWidthInTiles() / 10
            for cx = 0, width - 1 do
                for cy = 0, width - 1 do
                    local chunk = map:getChunk(cx, cy)
                    if chunk and not chunks[chunk] then
                        chunks[chunk] = true
                        for z = chunk:getMinLevel(), chunk:getMaxLevel() do
                            for x = 0, 9 do
                                for y = 0, 9 do
                                    local square = chunk:getGridSquare(x, y, z)
                                    if square then captureSquare(square, seen) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function onSquareLoaded(square)
    captureSquare(square)
end

--- Persists the opt-in in SP; MP state stays local to this client session.
---@param enabled boolean
function EntityDebug.setEnabled(enabled)
    if isServer() then return end
    if not getDebug() then return end
    local data = state(enabled)
    if not data then return end
    data.enabled = enabled == true
    if data.enabled then
        if not watching then Events.LoadGridsquare.Add(onSquareLoaded); watching = true end
        EntityDebug.captureLoaded()
    elseif watching then
        Events.LoadGridsquare.Remove(onSquareLoaded)
        watching = false
    end
end

--- Returns a diagnostic snapshot even when the draft cannot be registered in RR.
---@param draft WaymanGraphData
---@param baseRevision integer
---@param confirmed WaymanGraphData
---@return table?
function EntityDebug.export(draft, baseRevision, confirmed)
    if not EntityDebug.isEnabled() then return nil end
    EntityDebug.captureLoaded()
    local snapshot = GraphData.copy(draft)
    snapshot.debug = { entityValidation = GraphData.copy(state()) }
    snapshot.export = {
        source = "draft",
        baseRevision = baseRevision,
        confirmedRevision = confirmed.revision or 0,
    }
    return snapshot
end

local function toggleCapture()
    EntityDebug.setEnabled(not EntityDebug.isEnabled())
end

local function onContextMenu(_playerNum, context, _worldobjects, test)
    if isServer() or not getDebug() then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    local wayman = context:addOption("Wayman", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(wayman, menu)
    local debugOption = menu:addOption(getText("UI_Wayman_Debug"), nil, nil)
    local debugMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(debugOption, debugMenu)
    local option = debugMenu:addOption(getText("UI_Wayman_DebugEntityCapture"), nil, toggleCapture)
    debugMenu:setOptionChecked(option, EntityDebug.isEnabled())
end

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)
Events.OnGameStart.Add(function()
    if EntityDebug.isEnabled() then EntityDebug.setEnabled(true) end
end)

return EntityDebug
