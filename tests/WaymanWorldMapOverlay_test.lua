-- Standalone IDE test for the client-side world-map overlay.

local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/") or "."
local clientFile = root
    .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/client/Wayman/WaymanWorldMapOverlay.lua"
local sharedRoot = root
    .. "/RailroaderWayman/Contents/mods/RailroaderWayman/42/media/lua/shared/"

local handlers = {}
local registry = {}
local requests = {}

local function event(name)
    handlers[name] = {}
    return {
        Add = function(callback) table.insert(handlers[name], callback) end,
    }
end

Events = {
    OnGameStart = event("OnGameStart"),
    OnConnected = event("OnConnected"),
    OnReceiveGlobalModData = event("OnReceiveGlobalModData"),
    OnServerCommand = event("OnServerCommand"),
}

ModData = {
    get = function(key) return registry[key] end,
    remove = function(key) registry[key] = nil end,
    add = function(key, data) registry[key] = data end,
    request = function(key) table.insert(requests, key) end,
}

function isClient() return true end

ISWorldMap = {
    createChildren = function() end,
    render = function(self) self.originalRenderCount = self.originalRenderCount + 1 end,
}
ISWorldMap.__index = ISWorldMap

RailroaderWaymanGraphEditor = {
    onWorldData = function() end,
    onRejected = function() end,
    getOverlayState = function(data)
        return {
            data = data,
            showAllEdges = true,
            showAvailableNodes = true,
            showSelectedEdge = true,
            selectedAvailableBlockId = "turn_1:nodes",
        }
    end,
}

RailroaderWaymanGraphDisplay = {
    refresh = function() end,
}

local rrRegistrations = {}
RailroaderWaymanRRGraph = {
    register = function(data)
        table.insert(rrRegistrations, data)
        return true
    end,
}

function require(name)
    if name == "Wayman/WaymanGraphData" then return dofile(sharedRoot .. name .. ".lua") end
end

dofile(clientFile)

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

handlers.OnGameStart[1]()
handlers.OnConnected[1]()
assertEqual(#requests, 1, "duplicate data request prevention")
assertEqual(requests[1], "RailroaderWayman_World", "requested key")

handlers.OnReceiveGlobalModData[1]("OtherMod", { availableNodes = {} })
assertEqual(registry.OtherMod, nil, "unrelated global data")

local data = {
    availableNodes = {
        { blockId = "turn_1:nodes", nodes = {
            { x = 10, y = 20, z = 0 }, { x = 30, y = 40, z = 0 },
        } },
        { blockId = "turn_2:nodes", nodes = { { x = 50, y = 80, z = 1 } } },
    },
    edges = {
        edge_1 = {
            { blockId = "turn_1:nodes", nodes = {
                { x = 5, y = 6 }, { x = 7, y = 9 },
            } },
        },
    },
    switches = {},
}
handlers.OnReceiveGlobalModData[1]("RailroaderWayman_World", data)
assertEqual(registry.RailroaderWayman_World, data, "received data registration")
assertEqual(#rrRegistrations, 0, "data without wayman edge must not register RR")

data.edges.wayman = data.edges.edge_1
handlers.OnReceiveGlobalModData[1]("RailroaderWayman_World", data)
assertEqual(#rrRegistrations, 1, "persisted wayman graph registration")
assertEqual(rrRegistrations[1], data, "registered authoritative graph snapshot")
data.edges.wayman = nil

local mouseX, mouseY = 1000, 1000
local map = setmetatable({
    originalRenderCount = 0,
    rectangles = {},
    lines = {},
    mapAPI = {
        worldToUIX = function(_, x, _) return x * 2 end,
        worldToUIY = function(_, _, y) return y * 3 end,
    },
    getWidth = function() return 200 end,
    getHeight = function() return 200 end,
    getMouseX = function() return mouseX end,
    getMouseY = function() return mouseY end,
    drawRect = function(self, x, y, width, height, alpha, red, green, blue)
        table.insert(self.rectangles, {
            x = x, y = y, width = width, height = height,
            alpha = alpha, red = red, green = green, blue = blue,
        })
    end,
    drawLine = function(self, texture, x1, y1, x2, y2, thickness, alpha, red, green, blue)
        table.insert(self.lines, { x1 = x1, y1 = y1, x2 = x2, y2 = y2, thickness = thickness })
    end,
    drawRectBorder = function() end,
    drawText = function(self, text) self.hoverText = text end,
}, ISWorldMap)

map:render()
assertEqual(map.originalRenderCount, 1, "original map render call")
-- The third node maps below the visible map, so only two points are drawn.
assertEqual(#map.rectangles, 4, "visible point rectangle count")
assertEqual(map.rectangles[2].x, 17.5, "first point x")
assertEqual(map.rectangles[2].y, 57.5, "first point y")
assertEqual(map.rectangles[2].red, 1.0, "selected available block red")
assertEqual(map.rectangles[2].blue, 0.85, "selected available block blue")
assertEqual(map.rectangles[4].x, 57.5, "second point x")
assertEqual(map.rectangles[4].y, 117.5, "second point y")
assertEqual(#map.lines, 1, "edge segment count")
assertEqual(map.lines[1].x1, 10, "edge start x")
assertEqual(map.lines[1].y2, 27, "edge end y")

UIFont = { Small = "Small" }
function getTextManager()
    return {
        MeasureStringX = function(_, _, text) return #text * 7 end,
        getFontHeight = function() return 12 end,
    }
end
mouseX, mouseY = 10, 18
map:render()
assertEqual(map.hoverText, "Edge: edge_1", "edge hover identifier")

handlers.OnReceiveGlobalModData[1]("RailroaderWayman_World", false)
handlers.OnConnected[1]()
assertEqual(#requests, 2, "retry after false response")

print("PASS: requested and registered global modData")
print("PASS: rendered 2 visible availableNodes points and culled 1 off-map point")
print("PASS: rendered an edge segment")
print("PASS: identified an edge segment on hover")
