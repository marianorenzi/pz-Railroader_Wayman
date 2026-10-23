-- Three-way merge of editor topology. Geometry and owner lifetime come from
-- the current authority; conflicts retain the local choice for explicit review.
require "Wayman/WaymanGraphData"
RailroaderWaymanDraftMerge = {}
local Merge, GD = RailroaderWaymanDraftMerge, RailroaderWaymanGraphData

function Merge.equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Merge.equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function index(data)
    local blocks, locations, orders, switches = {}, {}, {}, {}
    local function add(list, edge)
        for i, block in ipairs(list or {}) do
            blocks[block.blockId], locations[block.blockId] = block, edge
            orders[block.blockId] = i
        end
    end
    add(data.availableNodes, false)
    for edge, list in pairs(data.edges) do add(list, edge) end
    for _, switch in ipairs(data.switches) do switches[switch.id] = switch end
    return blocks, locations, orders, switches
end

function Merge.merge(base, draft, current)
    base, draft, current = GD.ensure(base), GD.ensure(draft), GD.ensure(current)
    local bb, bl, bo, bs = index(base)
    local lb, ll, lo, ls = index(draft)
    local rb, rl, ro, rs = index(current)
    local conflicts = {}
    local function conflict(path) conflicts[#conflicts + 1] = path end
    local function choose(b, l, r, path)
        if Merge.equal(l, b) then return GD.copy(r) end
        if Merge.equal(r, b) or Merge.equal(l, r) then return GD.copy(l) end
        local function describe(value)
            if value == nil then return "(absent)" end
            local json = GD.worldDataToJSON({value=value})
            return json or tostring(value)
        end
        conflict(path .. " | base=" .. describe(b) .. " | local=" .. describe(l) .. " | server=" .. describe(r))
        return GD.copy(l)
    end
    local result = GD.copy(current)
    result.availableNodes, result.edges, result.switches = {}, {}, {}
    local edgeIds = {}
    for id in pairs(base.edges) do edgeIds[id] = true end
    for id in pairs(draft.edges) do edgeIds[id] = true end
    for id in pairs(current.edges) do edgeIds[id] = true end
    local function signature(list)
        if not list then return nil end
        local ids = {}
        for _, block in ipairs(list) do
            -- Deletions by the authority cannot be undone by an old draft.
            if rb[block.blockId] then ids[#ids + 1] = {block.blockId, block.invertNodes == true} end
        end
        return ids
    end
    for id in pairs(edgeIds) do
        local b, l, r = base.edges[id], draft.edges[id], current.edges[id]
        local keep = choose(b ~= nil, l ~= nil, r ~= nil, "edge " .. id)
        if b and l and not r and not Merge.equal(signature(b), signature(l)) then
            conflict("edge deleted on server: " .. id); keep = true
        elseif b and not l and r and not Merge.equal(signature(b), signature(r)) then
            conflict("edge deleted locally: " .. id)
        end
        if keep then result.edges[id] = {} end
    end
    local ids = {}
    for id in pairs(rb) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local block = GD.copy(rb[id])
        local location
        if bb[id] then location = choose(bl[id], ll[id], rl[id], "membership " .. id)
        else location = rl[id] end
        if location and not result.edges[location] then
            conflict("membership in deleted edge: " .. id); location = false
        end
        block.invertNodes = location and choose(bb[id] and bb[id].invertNodes == true,
            lb[id] and lb[id].invertNodes == true, rb[id].invertNodes == true,
            "inversion " .. id) or nil
        local list = location and result.edges[location] or result.availableNodes
        list[#list + 1] = block
    end
    -- Merge relative order rather than treating an entire edge as one edit.
    -- A cycle means the independently chosen order constraints are incompatible.
    for edge, list in pairs(result.edges) do
        local outgoing, degree = {}, {}
        for _, block in ipairs(list) do outgoing[block.blockId], degree[block.blockId] = {}, 0 end
        local function before(a, b, locations, order)
            if locations[a] == edge and locations[b] == edge then return order[a] < order[b] end
            return nil
        end
        for i = 1, #list do
            for j = i + 1, #list do
                local a, b = list[i].blockId, list[j].blockId
                local order = choose(before(a,b,bl,bo), before(a,b,ll,lo), before(a,b,rl,ro),
                    "order " .. edge .. ": " .. a .. "/" .. b)
                if order ~= nil then
                    local first, last = order and a or b, order and b or a
                    outgoing[first][last], degree[last] = true, degree[last] + 1
                end
            end
        end
        local sorted, used = {}, {}
        for _ = 1, #list do
            local selected
            for _, block in ipairs(list) do
                if not used[block.blockId] and degree[block.blockId] == 0 then selected = block break end
            end
            if not selected then break end
            local id = selected.blockId
            sorted[#sorted + 1], used[id] = selected, true
            for other in pairs(outgoing[id]) do degree[other] = degree[other] - 1 end
        end
        if #sorted ~= #list then
            conflict("order cycle " .. edge)
            table.sort(list, function(a,b)
                local ai, bi = lo[a.blockId] or ro[a.blockId] or 0, lo[b.blockId] or ro[b.blockId] or 0
                if ai == bi then return a.blockId < b.blockId end
                return ai < bi
            end)
        else result.edges[edge] = sorted end
        -- Physical removal must also remove the now-empty edge and its legs.
        if #list == 0 and current.edges[edge] == nil and base.edges[edge] then result.edges[edge] = nil end
    end
    for _, remote in ipairs(current.switches) do
        local switch = GD.copy(remote)
        switch.legs = {}
        for _, leg in ipairs({"throat", "through", "diverge"}) do
            local function value(s) return s and s.legs and s.legs[leg] or {} end
            local chosen = bs[remote.id] and choose(value(bs[remote.id]), value(ls[remote.id]),
                value(remote), "leg " .. remote.id .. "." .. leg) or GD.copy(value(remote))
            if chosen.edge and not chosen.external and not result.edges[chosen.edge] then chosen = {} end
            switch.legs[leg] = chosen
        end
        result.switches[#result.switches + 1] = switch
    end
    table.sort(conflicts)
    return result, conflicts
end

return Merge
