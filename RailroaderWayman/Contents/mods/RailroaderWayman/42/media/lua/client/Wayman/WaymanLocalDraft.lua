-- Local, per-world/per-author journal. Never stored in synchronized ModData.
if isServer() then return end
require "Wayman/WaymanGraphData"
require "Wayman/WaymanDraftMerge"
RailroaderWaymanLocalDraft = {}
local Drafts, GD, Merge = RailroaderWaymanLocalDraft, RailroaderWaymanGraphData, RailroaderWaymanDraftMerge
local session, sessionKey

local function identity()
    local player = getSpecificPlayer and getSpecificPlayer(0) or (getPlayer and getPlayer())
    local author = player and player:getUsername()
    local world = getWorld and getWorld()
    local save = world and world:getWorld()
    if not author or not save or save == "" then return nil, "world/author unavailable" end
    local mode = tostring(getCore():getGameMode() or "")
    local source = isClient() and {"MP", tostring(getServerIP() or ""), tostring(getServerPort() or ""),
        tostring(getServerName() or ""), save, author} or {"SP", mode, save, author}
    local key = assert(GD.worldDataToJSON({identity=source}))
    -- Encode every byte; replacing punctuation would conflate different servers/authors.
    local encoded = key:gsub(".", function(c) return string.format("%02x", string.byte(c)) end)
    local parts = {}
    for i = 1, #encoded, 96 do parts[#parts + 1] = encoded:sub(i, i + 95) end
    return key, "RailroaderWayman/drafts/" .. table.concat(parts, "/") .. "/draft"
end

local function read(path)
    local reader
    local ok, result = pcall(function()
        reader = getFileReader(path, false)
        if not reader then return nil end
        local lines = {}
        while true do
            local line = reader:readLine()
            if line == nil then break end
            lines[#lines + 1] = line
        end
        return GD.worldDataFromJSON(table.concat(lines, "\n"))
    end)
    if reader then pcall(function() reader:close() end) end
    if ok then return result end
end

function Drafts.save(state)
    local key, path = identity()
    if not key then state.storageError = path; return false, path end
    if state.key and state.key ~= key then state.storageError = "draft belongs to another world/author"; return false, state.storageError end
    local sequence = (state.sequence or 0) + 1
    local record = GD.copy(state)
    record.storageError, record.sequence, record.key, record.format = nil, sequence, key, 1
    local json, reason = GD.worldDataToJSON(record)
    if not json then state.storageError = reason; return false, reason end
    local writer
    local ok, err = pcall(function()
        writer = getFileWriter(path .. "." .. tostring(sequence % 2) .. ".json", true, false)
        if not writer then error("cannot open local draft journal") end
        writer:write(json)
        writer:close()
        writer = nil
        local check = read(path .. "." .. tostring(sequence % 2) .. ".json")
        if not check or check.sequence ~= sequence or check.key ~= key
            or not Merge.equal(check, record) then error("local draft verification failed") end
    end)
    if writer then pcall(function() writer:close() end) end
    if not ok then state.storageError = tostring(err); return false, state.storageError end
    state.sequence, state.storageError = sequence, nil
    return true
end

local function blocks(data)
    local result = {}
    for _, block in ipairs(data.availableNodes) do result[block.blockId] = block end
    for _, list in pairs(data.edges) do
        for _, block in ipairs(list) do result[block.blockId] = block end
    end
    return result
end

function Drafts.ownerGeometry(data, owner)
    local result = {blocks={}}
    for id, block in pairs(blocks(data)) do
        if block.owner == owner then result.blocks[id] = {origin=GD.copy(block.origin),nodes=GD.copy(block.nodes)} end
    end
    for _, switch in ipairs(data.switches) do
        if switch.owner == owner then result.switch = {origin=GD.copy(switch.origin),at=GD.copy(switch.at),place=GD.copy(switch.place)} end
    end
    return result
end

function Drafts.nodeKey(instance)
    if instance.data.id then return instance.data.id end
    local origin = instance.origin
    return "unregistered:" .. instance.entityName .. ":" .. instance.facing .. ":"
        .. tostring(origin.x) .. ":" .. tostring(origin.y) .. ":" .. tostring(origin.z or 0)
        .. (instance.componentIndex and ":component:" .. tostring(instance.componentIndex) or "")
end

function Drafts.preview(state)
    local byId = blocks(state.draft)
    for owner, edit in pairs(state.geometry) do
        local geometry = edit.geometry
        local function set(id, nodes)
            local block = byId[owner .. ":" .. id]
            if block then block.nodes = GD.copy(nodes) end
        end
        if geometry.kind == "turn" then set("nodes", geometry.nodes)
        else
            set("at", {geometry.at})
            set("through", #geometry.throughNodes > 0 and geometry.throughNodes or {geometry.at})
            set("diverge", #geometry.divergingNodes > 0 and geometry.divergingNodes or {geometry.at})
            for _, switch in ipairs(state.draft.switches) do
                if switch.owner == owner then switch.at, switch.place = GD.copy(geometry.at), GD.copy(geometry.switch) end
            end
        end
    end
end

--- Reconciles a confirmed snapshot while preserving pending local work and acks.
--- A local edit does not increment the authority's revision; equal revisions
--- mean there is nothing external to merge, not that the draft is unmodified.
---@param state table Local journal state for the current world/author.
---@param current WaymanGraphData Confirmed authoritative graph.
---@param force boolean? Reconcile after an explicit geometry discard at the same revision.
function Drafts.rebase(state, current, force)
    local revision, baseRevision = current.revision or 0, state.base.revision or 0
    if revision == baseRevision and not force then
        -- Accept can retry a previously failed journal write without re-merging.
        -- Publication acknowledgements are still handled separately by onResult.
        if state.storageError then Drafts.save(state) end
        return
    end
    if revision < baseRevision then
        -- A global save can be older after a crash. Keep all versions for review.
        state.conflicts = {"world revision moved backwards; Reload required"}
        state.remote = GD.copy(current)
        Drafts.save(state)
        return
    end
    if not Drafts.changed(state) then
        -- With no topology, staged geometry or raw node edits to preserve, a
        -- newer snapshot can replace both copies without the quadratic merge.
        -- Keep state.pending: a broadcast never acknowledges a publication.
        state.base, state.draft = GD.copy(current), GD.copy(current)
        state.remote, state.conflictVersions, state.conflicts = nil, nil, {}
        Drafts.save(state)
        return
    end
    local original = GD.copy(state.draft)
    local merged, conflicts = Merge.merge(state.base, state.draft, current)
    local after = blocks(current)
    for owner in pairs(state.geometry) do
        local latest = Drafts.ownerGeometry(current, owner)
        if GD.isEmpty(latest.blocks) then state.geometry[owner], state.nodeDrafts[owner] = nil, nil
        elseif not Merge.equal(Drafts.ownerGeometry(state.base, owner), latest) then
            conflicts[#conflicts + 1] = "geometry " .. owner
        end
    end
    local owners = {}
    for _, block in pairs(after) do owners[block.owner] = true end
    for owner, nodeDraft in pairs(state.nodeDrafts) do
        if not owners[owner] and not nodeDraft.unregistered then state.nodeDrafts[owner] = nil
        elseif owners[owner] and nodeDraft.baseGeometry
            and not Merge.equal(nodeDraft.baseGeometry, Drafts.ownerGeometry(current, owner)) then
            conflicts[#conflicts + 1] = "node draft geometry " .. owner
        end
    end
    state.draft = merged
    state.conflicts = conflicts
    if #conflicts == 0 then
        state.base, state.remote, state.conflictVersions = GD.copy(current), nil, nil
    else
        state.conflictVersions = state.conflictVersions or {base=GD.copy(state.base),localDraft=original}
        state.remote = GD.copy(current)
    end
    Drafts.preview(state)
    Drafts.save(state)
end

function Drafts.open(current)
    local key, path = identity()
    if key and session and sessionKey == key then return session end
    local best
    if key then
        for slot = 0, 1 do
            local record = read(path .. "." .. tostring(slot) .. ".json")
            if record and record.format == 1 and record.key == key and type(record.sequence) == "number"
                and type(record.base) == "table" and type(record.draft) == "table"
                and type(record.geometry) == "table" and type(record.nodeDrafts) == "table"
                and (not best or record.sequence > best.sequence) then best = record end
        end
    end
    session = best or {base=GD.copy(current),draft=GD.copy(current),geometry={},nodeDrafts={},conflicts={}}
    session.key = key
    sessionKey = key
    if best then Drafts.rebase(session, current) end
    return session
end

function Drafts.current() return session end

function Drafts.reset(state, current)
    state.base, state.draft = GD.copy(current), GD.copy(current)
    state.geometry, state.nodeDrafts, state.conflicts = {}, {}, {}
    state.pending, state.remote, state.conflictVersions = nil, nil, nil
    return Drafts.save(state)
end

function Drafts.resolveLocal(state)
    if not state.remote or state.remote.revision < state.base.revision then return false end
    state.base = GD.copy(state.remote)
    state.draft.revision = state.base.revision
    for owner, nodeDraft in pairs(state.nodeDrafts) do nodeDraft.baseGeometry = Drafts.ownerGeometry(state.base, owner) end
    state.remote, state.conflictVersions, state.conflicts = nil, nil, {}
    return Drafts.save(state)
end

function Drafts.stageGeometry(state, instance, data)
    local owner = instance.data.id
    if not owner or not blocks(state.draft)[owner .. (instance.defaults.kind == "turn" and ":nodes" or ":at")] then
        return false, "entity owner is absent from WorldData; identity recovery required (WM-04)"
    end
    local master, geometry = instance.master, {kind=instance.defaults.kind}
    for _, field in ipairs(geometry.kind == "turn" and {"nodes"}
        or {"at","switch","throughNodes","divergingNodes"}) do
        geometry[field] = GD.copy(data[field] ~= nil and data[field] or instance.defaults[field])
        if field == "throughNodes" or field == "divergingNodes" then geometry[field] = geometry[field] or {} end
    end
    local square = master:getSquare()
    state.geometry[owner] = {
        x=square:getX(),y=square:getY(),z=square:getZ(),objectIndex=master:getObjectIndex(),
        entityName=instance.entityName,facing=instance.facing,modData=GD.copy(data),geometry=geometry,
    }
    state.nodeDrafts[owner] = nil
    Drafts.preview(state)
    return Drafts.save(state)
end

function Drafts.changed(state)
    return not Merge.equal(state.draft, state.base) or not GD.isEmpty(state.geometry) or not GD.isEmpty(state.nodeDrafts)
end

return Drafts
