-- Side-neutral graph data utilities. It initializes the persistent schema,
-- copies serializable snapshots, flattens ordered node blocks, and validates
-- client editor drafts against server-owned canonical geometry.
RailroaderWaymanGraphData = RailroaderWaymanGraphData or {}
local GraphData = RailroaderWaymanGraphData

--- Deep-copies serializable graph data while preserving repeated table references.
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

--- Returns an independent copy suitable for a client-side editing draft.
function GraphData.copy(value)
    return copy(value)
end

local jsonArrayFields = { availableNodes = true, switches = true, nodes = true }

--- Escapes a Lua string as a compact JSON string literal.
local function jsonQuote(value)
    local replacements = {
        ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
        ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
    }
    return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
        return replacements[character] or string.format("\\u%04x", string.byte(character))
    end) .. '"'
end

--- Serializes current-schema tables while preserving empty JSON array types.
local function encodeJSON(value, context, seen)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("JSON cannot encode a non-finite number")
        end
        return tostring(value)
    end
    if kind == "string" then return jsonQuote(value) end
    if kind ~= "table" then error("JSON cannot encode " .. kind) end
    if seen[value] then error("JSON cannot encode cyclic tables") end
    seen[value] = true

    local forceArray = jsonArrayFields[context] or context == "edgeBlocks"
    local count, maximum, numericOnly = 0, 0, true
    for key in pairs(value) do
        count = count + 1
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            numericOnly = false
        elseif key > maximum then
            maximum = key
        end
    end
    local isArray = forceArray or (count > 0 and numericOnly and maximum == count)
    local parts = {}
    if isArray then
        if not numericOnly or maximum ~= count then error("JSON array is sparse or has named keys") end
        for index = 1, maximum do
            table.insert(parts, encodeJSON(value[index], nil, seen))
        end
        seen[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" then error("JSON object keys must be strings") end
        table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local childContext = key
        if context == "edges" then childContext = "edgeBlocks" end
        table.insert(parts, jsonQuote(key) .. ":" .. encodeJSON(value[key], childContext, seen))
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

--- Converts Wayman world data to deterministic, compact JSON.
function GraphData.worldDataToJSON(worldData)
    if type(worldData) ~= "table" then return nil, "world data must be a table" end
    local ok, result = pcall(encodeJSON, worldData, "worldData", {})
    if not ok then return nil, tostring(result) end
    return result
end

--- Converts one Unicode code point to UTF-8 for JSON escape decoding.
local function codePointToUTF8(code)
    if code <= 0x7F then return string.char(code) end
    if code <= 0x7FF then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end
    if code <= 0xFFFF then
        return string.char(0xE0 + math.floor(code / 0x1000),
            0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000),
        0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

--- Parses JSON text into Lua tables without performing graph import or validation.
function GraphData.worldDataFromJSON(text)
    if type(text) ~= "string" then return nil, "JSON must be a string" end
    local position, length = 1, #text
    local parseValue
    local function fail(message) error(message .. " at character " .. tostring(position), 0) end
    local function skipWhitespace()
        while position <= length and text:sub(position, position):match("%s") do
            position = position + 1
        end
    end
    local function parseString()
        if text:sub(position, position) ~= '"' then fail("expected string") end
        position = position + 1
        local parts = {}
        while position <= length do
            local character = text:sub(position, position)
            if character == '"' then position = position + 1 return table.concat(parts) end
            if string.byte(character) < 32 then fail("unescaped control character") end
            if character ~= "\\" then
                table.insert(parts, character)
                position = position + 1
            else
                position = position + 1
                local escape = text:sub(position, position)
                local simple = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
                    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
                if simple[escape] then
                    table.insert(parts, simple[escape])
                    position = position + 1
                elseif escape == "u" then
                    local digits = text:sub(position + 1, position + 4)
                    if not digits:match("^%x%x%x%x$") then fail("invalid Unicode escape") end
                    local code = tonumber(digits, 16)
                    position = position + 5
                    if code >= 0xD800 and code <= 0xDBFF then
                        if text:sub(position, position + 1) ~= "\\u" then fail("missing low surrogate") end
                        local lowDigits = text:sub(position + 2, position + 5)
                        local low = lowDigits:match("^%x%x%x%x$") and tonumber(lowDigits, 16)
                        if not low or low < 0xDC00 or low > 0xDFFF then fail("invalid low surrogate") end
                        code = 0x10000 + (code - 0xD800) * 0x400 + low - 0xDC00
                        position = position + 6
                    elseif code >= 0xDC00 and code <= 0xDFFF then
                        fail("unexpected low surrogate")
                    end
                    table.insert(parts, codePointToUTF8(code))
                else
                    fail("invalid string escape")
                end
            end
        end
        fail("unterminated string")
    end
    local function parseNumber()
        local start = position
        if text:sub(position, position) == "-" then position = position + 1 end
        if text:sub(position, position) == "0" then
            position = position + 1
            if text:sub(position, position):match("%d") then fail("leading zero in number") end
        else
            if not text:sub(position, position):match("[1-9]") then fail("invalid number") end
            repeat position = position + 1 until not text:sub(position, position):match("%d")
        end
        if text:sub(position, position) == "." then
            position = position + 1
            if not text:sub(position, position):match("%d") then fail("invalid fraction") end
            repeat position = position + 1 until not text:sub(position, position):match("%d")
        end
        if text:sub(position, position):match("[eE]") then
            position = position + 1
            if text:sub(position, position):match("[+-]") then position = position + 1 end
            if not text:sub(position, position):match("%d") then fail("invalid exponent") end
            repeat position = position + 1 until not text:sub(position, position):match("%d")
        end
        local result = tonumber(text:sub(start, position - 1))
        if not result or result ~= result or result == math.huge or result == -math.huge then
            fail("number is not finite")
        end
        return result
    end
    local function parseArray()
        position = position + 1
        skipWhitespace()
        local result = {}
        if text:sub(position, position) == "]" then position = position + 1 return result end
        while true do
            table.insert(result, parseValue())
            skipWhitespace()
            local delimiter = text:sub(position, position)
            if delimiter == "]" then position = position + 1 return result end
            if delimiter ~= "," then fail("expected ',' or ']'") end
            position = position + 1
            skipWhitespace()
        end
    end
    local function parseObject()
        position = position + 1
        skipWhitespace()
        local result = {}
        if text:sub(position, position) == "}" then position = position + 1 return result end
        while true do
            local key = parseString()
            skipWhitespace()
            if text:sub(position, position) ~= ":" then fail("expected ':'") end
            position = position + 1
            skipWhitespace()
            if result[key] ~= nil then fail("duplicate object key") end
            result[key] = parseValue()
            skipWhitespace()
            local delimiter = text:sub(position, position)
            if delimiter == "}" then position = position + 1 return result end
            if delimiter ~= "," then fail("expected ',' or '}'") end
            position = position + 1
            skipWhitespace()
        end
    end
    parseValue = function()
        skipWhitespace()
        local character = text:sub(position, position)
        if character == '"' then return parseString() end
        if character == "{" then return parseObject() end
        if character == "[" then return parseArray() end
        if character == "-" or character:match("%d") then return parseNumber() end
        if text:sub(position, position + 3) == "true" then position = position + 4 return true end
        if text:sub(position, position + 4) == "false" then position = position + 5 return false end
        if text:sub(position, position + 3) == "null" then fail("null is not valid in Wayman world data") end
        fail("unexpected token")
    end
    local ok, result = pcall(function()
        skipWhitespace()
        if text:sub(position, position) ~= "{" then fail("world data root must be an object") end
        local parsed = parseValue()
        skipWhitespace()
        if position <= length then fail("trailing content") end
        return parsed
    end)
    if not ok then return nil, tostring(result) end
    return result
end

--- Adds every required graph collection and counter to a world-data table.
function GraphData.ensure(worldData)
    worldData.availableNodes = worldData.availableNodes or {}
    worldData.edges = worldData.edges or {}
    worldData.switches = worldData.switches or {}
    worldData.revision = worldData.revision or 0
    worldData.nextEdgeId = worldData.nextEdgeId or 1
    return worldData
end

--- Flattens ordered node blocks, applying each block's inversion flag.
function GraphData.getOrderedNodes(blocks)
    local nodes = {}
    for _, block in ipairs(blocks or {}) do
        local source = block.nodes or {}
        if block.invertNodes then
            for index = #source, 1, -1 do table.insert(nodes, source[index]) end
        else
            for _, node in ipairs(source) do table.insert(nodes, node) end
        end
    end
    return nodes
end

--- Indexes every server-owned block and rejects duplicate canonical identities.
local function collectCanonicalBlocks(worldData)
    local byId = {}
    local count = 0
    --- Adds one canonical block to the temporary validation index.
    local function add(block)
        if type(block) ~= "table" or type(block.blockId) ~= "string" then
            return false, "invalid canonical node block"
        end
        if byId[block.blockId] then return false, "duplicate canonical block " .. block.blockId end
        byId[block.blockId] = block
        count = count + 1
        return true
    end
    for _, block in ipairs(worldData.availableNodes or {}) do
        local ok, reason = add(block)
        if not ok then return nil, nil, reason end
    end
    for _, blocks in pairs(worldData.edges or {}) do
        for _, block in ipairs(blocks or {}) do
            local ok, reason = add(block)
            if not ok then return nil, nil, reason end
        end
    end
    return byId, count
end

--- Rebuilds a submitted block from canonical geometry and its editable inversion.
local function canonicalBlock(block, canonical)
    local source = type(block) == "table" and canonical[block.blockId]
    if not source then return nil end
    local result = copy(source)
    result.invertNodes = block.invertNodes == true or nil
    return result
end

--- Allocates the next unused generated edge ID without mutating world data.
local function allocateEdgeId(value, reserved)
    local id
    repeat
        id = "edge_" .. tostring(value)
        value = value + 1
    until not reserved[id]
    reserved[id] = true
    return id, value
end

--- Validates and normalizes an atomic client draft against canonical server data.
function GraphData.validateDraft(worldData, draft)
    -- Reject malformed or stale snapshots before deriving any result state.
    GraphData.ensure(worldData)
    if type(draft) ~= "table" then return nil, "missing graph draft" end
    if draft.revision ~= worldData.revision then return nil, "graph revision changed" end
    if type(draft.availableNodes) ~= "table" or type(draft.edges) ~= "table"
        or type(draft.switches) ~= "table" then
        return nil, "incomplete graph draft"
    end

    -- Only block identity and inversion are editable. Geometry always comes
    -- from the server's canonical collection.
    local canonical, canonicalCount, reason = collectCanonicalBlocks(worldData)
    if not canonical then return nil, reason end
    local seen = {}
    local result = {
        availableNodes = {},
        edges = {},
        switches = {},
        revision = worldData.revision + 1,
    }

    --- Consumes a block exactly once and returns its canonical representation.
    local function consume(block)
        local blockId = type(block) == "table" and block.blockId
        if type(blockId) ~= "string" or seen[blockId] or not canonical[blockId] then
            return nil, "unknown or duplicate block " .. tostring(blockId)
        end
        seen[blockId] = true
        return canonicalBlock(block, canonical)
    end

    -- Consume every available block, then every edge block, exactly once.
    for _, block in ipairs(draft.availableNodes) do
        local normalized, blockReason = consume(block)
        if not normalized then return nil, blockReason end
        normalized.invertNodes = nil
        table.insert(result.availableNodes, normalized)
    end

    -- Validate edge IDs and resolve temporary IDs while preserving references.
    local reserved = {}
    for edgeId in pairs(worldData.edges) do reserved[edgeId] = true end
    local edgeIdMap = {}
    local nextEdgeId = worldData.nextEdgeId or 1
    for requestedId, blocks in pairs(draft.edges) do
        if type(requestedId) ~= "string" or type(blocks) ~= "table" or #blocks == 0 then
            return nil, "edge must have an id and at least one block"
        end
        local edgeId = requestedId
        if requestedId:sub(1, 6) == "__new:" then
            edgeId, nextEdgeId = allocateEdgeId(nextEdgeId, reserved)
        elseif not worldData.edges[requestedId] then
            if not requestedId:match("^[%w_.%-]+$") then
                return nil, "invalid edge id " .. requestedId
            end
            if reserved[requestedId] then return nil, "duplicate edge " .. requestedId end
            reserved[requestedId] = true
        end
        if result.edges[edgeId] then return nil, "duplicate edge " .. edgeId end
        edgeIdMap[requestedId] = edgeId
        result.edges[edgeId] = {}
        for _, block in ipairs(blocks) do
            local normalized, blockReason = consume(block)
            if not normalized then return nil, blockReason end
            table.insert(result.edges[edgeId], normalized)
        end
    end

    local seenCount = 0
    for _ in pairs(seen) do seenCount = seenCount + 1 end
    if seenCount ~= canonicalCount then return nil, "draft omits one or more node blocks" end

    -- Switch identity and geometry remain canonical; only complete leg pairs
    -- may be changed by the draft.
    local canonicalSwitches = {}
    for _, switch in ipairs(worldData.switches) do canonicalSwitches[switch.id] = switch end
    local seenSwitches = {}
    for _, requested in ipairs(draft.switches) do
        local source = type(requested) == "table" and canonicalSwitches[requested.id]
        if not source or seenSwitches[requested.id] then
            return nil, "unknown or duplicate switch " .. tostring(requested and requested.id)
        end
        seenSwitches[requested.id] = true
        local normalized = copy(source)
        normalized.legs = {}
        for _, legName in ipairs({ "throat", "through", "diverge" }) do
            local leg = requested.legs and requested.legs[legName] or {}
            local edge = leg.edge and (edgeIdMap[leg.edge] or leg.edge) or nil
            local toward = leg.toward or nil
            if (edge == nil) ~= (toward == nil) then
                return nil, "switch " .. tostring(requested.id) .. " leg " .. legName
                    .. " must define edge and toward together"
            end
            if edge and not result.edges[edge] then return nil, "switch references missing edge " .. edge end
            if toward and toward ~= "start" and toward ~= "end" then
                return nil, "invalid switch toward " .. tostring(toward)
            end
            normalized.legs[legName] = edge and { edge = edge, toward = toward } or {}
        end
        table.insert(result.switches, normalized)
    end
    for switchId in pairs(canonicalSwitches) do
        if not seenSwitches[switchId] then return nil, "draft omits switch " .. switchId end
    end

    result.nextEdgeId = nextEdgeId
    return result, nil, edgeIdMap
end

return GraphData
