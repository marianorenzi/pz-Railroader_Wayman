-- One ingress for snapshots and rename operations. Metadata travels alongside
-- snapshots, never inside synchronized world data or RR's graph definition.
if isServer() then return end
require "Wayman/WaymanGraphData"
require "Wayman/WaymanLocalDraft"
RailroaderWaymanGraphSync = {}
local Sync = RailroaderWaymanGraphSync
local GD, Drafts = RailroaderWaymanGraphData, RailroaderWaymanLocalDraft
local KEY = "RailroaderWayman_World"
local confirmed, context, requested
Drafts.renameSyncEnabled = true

function Sync.current() return confirmed or ModData.get(KEY) end

--- Validate the operation envelope before allowing it to transform any journal.
function Sync.receive(message)
    if type(message) ~= "table" or type(message.worldData) ~= "table"
        or type(message.renames) ~= "table" or type(message.renameFloor) ~= "number" then return false end
    local data = message.worldData
    local revision, previous = data.revision or 0, message.renameFloor
    if previous < 0 or previous > revision then return false end
    for _, operation in ipairs(message.renames) do
        if type(operation) ~= "table" or type(operation.oldId) ~= "string" or type(operation.newId) ~= "string"
            or GD.edgeId(operation.oldId) ~= operation.oldId
            or GD.edgeId(operation.newId) ~= operation.newId
            or type(operation.fromRevision) ~= "number" or type(operation.revision) ~= "number"
            or operation.revision ~= operation.fromRevision + 1
            or operation.fromRevision < previous or operation.revision > revision then return false end
        previous = operation.revision
    end
    requested = nil
    if context and revision < context.revision then return true end
    context = {renames=GD.copy(message.renames),renameFloor=message.renameFloor,revision=revision}
    Drafts.setRenameContext(context)
    confirmed = GD.ensure(GD.copy(data))
    ModData.remove(KEY)
    ModData.add(KEY, confirmed)
    if RailroaderWaymanGraphEditor then RailroaderWaymanGraphEditor.onWorldData(confirmed) end
    if RailroaderWaymanGraphDisplay then
        local editor = RailroaderWaymanGraphEditor
        RailroaderWaymanGraphDisplay.refresh(editor and editor.getOverlayState(confirmed).data or confirmed)
    end
    return true
end

function Sync.request()
    if isClient() then
        if requested then return end
        local player = getSpecificPlayer(0) or getPlayer()
        -- OnConnected can precede player creation. OnGameStart retries safely.
        if not player then return end
        requested = true
        sendClientCommand(player, "RailroaderWayman", "graphSync", {})
    elseif RailroaderWaymanEntityRuntime then
        Sync.receive(RailroaderWaymanEntityRuntime.GraphSync())
    end
end

--- A bare broadcast cannot establish which revisions were renames. Ask for the
--- operation envelope before exposing a newer snapshot to any editor/rebase.
function Sync.receiveSnapshot(data)
    if type(data) ~= "table" then return false end
    local editor = RailroaderWaymanGraphEditor and RailroaderWaymanGraphEditor.instance
    local state = Drafts.current()
    if not context or (data.revision or 0) > context.revision
        or (editor and editor.reloadPending) or (state and state.renameWaiting) then Sync.request() end
    return true
end

function Sync.ready()
    local state = Drafts.current()
    return context ~= nil and not (state and state.renameWaiting)
end

if Events.OnDisconnect then Events.OnDisconnect.Add(function()
    confirmed, context, requested = nil, nil, nil
    Drafts.setRenameContext(nil)
end) end
if Events.OnConnected then Events.OnConnected.Add(function() requested = nil; Sync.request() end) end
if Events.OnGameStart then Events.OnGameStart.Add(Sync.request) end
return Sync
