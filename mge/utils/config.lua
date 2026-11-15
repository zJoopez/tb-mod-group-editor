-- MGE's config file: the Settings overlay's values and the color picker's palette, kept between game sessions in
-- config.cfg next to main.lua (gitignored, not in the release zip: an update keeps it). One "key value" a line:
--
--   uiScale 1.3
--   cameraFollow 1
--   moveStep 0.5
--   palette 255 128 0 255     one line a color, r g b a 0-255
--
-- Read when MGE starts (Config.load, before the window is built: the UI size is needed then), put on the
-- modules once they're loaded (Config.apply), written when Settings closes, the UI size changes and the
-- palette changes (Config.save). Unknown keys and bad values are skipped: the defaults stay
local Config = {}
MGE.Config = Config

---@class MgeConfigEntry
---@field key string
---@field kind "number"|"boolean"
---@field get fun(): number|boolean
---@field set fun(value: number|boolean)
---@field min number? smallest accepted (inclusive)
---@field max number? largest accepted
---@field whole boolean?

---The settings in the file, in this order. get / set reach the modules once they're loaded
---@type MgeConfigEntry[]
Config.ENTRIES = {
    { key = "uiScale", kind = "number", min = 0.5, max = 3,
        get = function() return tonumber(MGE_UI_SCALE) or (MGE.Widgets and MGE.Widgets.UI_SCALE) or 1.3 end,
        set = function(v) if MGE_UI_SCALE == nil then MGE_UI_SCALE = v end end }, -- a restart's choice wins
    { key = "cameraFollow", kind = "boolean",
        get = function() return MGE.Camera.followMoves end, set = function(v) MGE.Camera.followMoves = v end },
    { key = "moveStep", kind = "number", min = 1e-6, max = 100,
        get = function() return MGE.Gizmo.moveStep end, set = function(v) MGE.Gizmo.moveStep = v end },
    { key = "rotateStep", kind = "number", min = 1e-6, max = 180,
        get = function() return MGE.Gizmo.rotateStep end, set = function(v) MGE.Gizmo.rotateStep = v end },
    { key = "scaleStep", kind = "number", min = 1e-6, max = 10,
        get = function() return MGE.Gizmo.scaleStep end, set = function(v) MGE.Gizmo.scaleStep = v end },
    { key = "maxAtmo", kind = "number", min = 0, max = 100000, whole = true,
        get = function() return MGE.AtmoLayer.maxAtmo end, set = function(v) MGE.AtmoLayer.maxAtmo = v end },
}

---@type table<string, number|boolean> values read from the file, by key
Config.values = {}
---@type number[][] the color picker's saved colors, r g b a with 1 for 255
Config.palette = {}

---@param entry MgeConfigEntry
---@param text string
---@return number|boolean|nil value, nil when it isn't a valid one
local function parseValue(entry, text)
    if entry.kind == "boolean" then
        if text == "1" or text == "true" then return true end
        if text == "0" or text == "false" then return false end
        return nil
    end
    local n = tonumber(text)
    if not n or n ~= n then return nil end
    if entry.whole then n = math.floor(n) end
    if (entry.min and n < entry.min) or (entry.max and n > entry.max) then return nil end
    return n
end

---@param c number[] r g b a, 1 is 255
---@return string "r g b a" 0-255
function Config.colorText(c)
    local n = {}
    for i = 1, 4 do n[i] = math.floor(math.max(0, math.min(1, c[i] or 1)) * 255 + 0.5) end
    return table.concat(n, " ")
end

---@param text string "r g b a" 0-255
---@return number[]? r g b a with 1 for 255, nil unless four numbers
function Config.parseColor(text)
    local n = {}
    for num in text:gmatch("%S+") do n[#n + 1] = tonumber(num) end
    if #n ~= 4 or not (n[1] and n[2] and n[3] and n[4]) then return nil end
    local c = {}
    for i = 1, 4 do c[i] = math.max(0, math.min(255, n[i])) / 255 end
    return c
end

---Reads a config text
---@param text string?
---@return table<string, number|boolean> values, number[][] palette
function Config.parse(text)
    local byKey = {}
    for _, entry in ipairs(Config.ENTRIES) do byKey[entry.key] = entry end
    local values, palette = {}, {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local key, rest = line:match("^%s*(%S+)%s*(.-)%s*$")
        if key == "palette" then
            local c = Config.parseColor(rest)
            if c then palette[#palette + 1] = c end
        elseif key and byKey[key] then
            local v = parseValue(byKey[key], rest)
            if v ~= nil then values[key] = v end
        end
    end
    return values, palette
end

---@param values table<string, number|boolean>
---@param palette number[][]
---@return string
function Config.format(values, palette)
    local lines = {}
    for _, entry in ipairs(Config.ENTRIES) do
        local v = values[entry.key]
        if entry.kind == "boolean" and v ~= nil then
            lines[#lines + 1] = entry.key .. " " .. (v and "1" or "0")
        elseif type(v) == "number" then
            lines[#lines + 1] = entry.key .. " " .. string.format("%.10g", v)
        end
    end
    for _, c in ipairs(palette) do lines[#lines + 1] = "palette " .. Config.colorText(c) end
    return table.concat(lines, "\n") .. "\n"
end

---@return string path from data/script (the game's io.open)
function Config.path() return MGE.scriptPath .. "config.cfg" end

---@param path string
---@return string? text, nil without the file
local function readFile(path)
    local ok, file = pcall(io.open, path, "r")
    if not ok or not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

---Reads config.cfg. The UI size goes straight to MGE_UI_SCALE (ui/widgets.lua reads it when it loads), the
---rest waits for Config.apply. A palette saved before the config existed (assets/palette.txt) is taken in
function Config.load()
    Config.values, Config.palette = Config.parse(readFile(Config.path()))
    if #Config.palette == 0 then
        local old = readFile(MGE.scriptPath .. "assets/palette.txt")
        if old then
            for line in old:gmatch("[^\r\n]+") do
                local c = Config.parseColor(line)
                if c then Config.palette[#Config.palette + 1] = c end
            end
        end
    end
    if Config.values.uiScale ~= nil and MGE_UI_SCALE == nil then MGE_UI_SCALE = Config.values.uiScale end
end

---Puts the values read on the modules (after they're loaded: their defaults stay for anything not in the file)
function Config.apply()
    for _, entry in ipairs(Config.ENTRIES) do
        local v = Config.values[entry.key]
        if v ~= nil then pcall(entry.set, v) end
    end
end

---Writes every setting's current value and the palette
function Config.save()
    for _, entry in ipairs(Config.ENTRIES) do
        local ok, v = pcall(entry.get)
        if ok and v ~= nil then Config.values[entry.key] = v end
    end
    local ok, file = pcall(io.open, Config.path(), "w")
    if not ok or not file then
        echo("^04[MGE] couldn't save the settings to " .. Config.path())
        return
    end
    file:write(Config.format(Config.values, Config.palette))
    file:close()
end

return Config
