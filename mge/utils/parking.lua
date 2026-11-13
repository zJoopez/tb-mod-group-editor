-- Parked objects: objects past the game's object limit (MGE.MAX_ENV_OBJECTS), kept in
-- ModData.parsed.parked. The mod file has them as comments the game skips (utils/file_handler.lua,
-- PARKED_TAG), so they never load as objects; MGE draws them as ghosts (utils/highlight.lua with
-- Parking.ghost). They're listed after the objects (P1, P2...) and can be selected there.
--   Park (Advanced tab):   the selected objects become parked, their ids are free for others
--   Unpark:                selected parked objects come back as objects, as many as there are free ids
--   Export atmo:           writes the parked objects as a Toribash atmosphere,
--                          data/atmospheres/MGE - <mod>.atmo. The game draws atmo objects but they
--                          don't collide, and each player loads the atmo themselves (main menu's
--                          Shaders & Atmos > Atmos)
-- Parked objects aren't in the world: to edit one, unpark it, edit, park it again.
local ModData = MGE.ModData
local History = MGE.History
local Mat3 = MGE.Mat3
local FileHandler = MGE.FileHandler

---@class Parking
local Parking = {
    color = { 0.75, 0.45, 1.0 }, -- ghost fill, selected ones use the selection highlight's color
    alpha = 0.15,
    selectedAlpha = 0.3,
    -- most parked objects an import may add (the map converter's Budget over the free ids): atmos
    -- hold at least 512 objects without trouble (the user's tests)
    maxParked = 512,
    atmoFolder = "../data/atmospheres/", -- from the Toribash folder (Files.Open's ../ root)
    atmoPrefix = "MGE - ", -- never the name of one of the game's own atmospheres
}
MGE.Parking = Parking

---@param value string?
---@return number[]
local function numbers(value)
    local out = {}
    for n in tostring(value or ""):gmatch("%S+") do out[#out + 1] = tonumber(n) or 0 end
    return out
end

---@param obj FileParserEnvObj
---@return string "box", "sphere" or "cylinder" (a pill in game), as mod files and atmos write them
local function shapeOf(obj)
    local shape = tostring(obj.props.shape or "box"):match("^%s*(%a+)") or "box"
    if shape == "sphere" or shape == "cylinder" or shape == "capsule" then
        return shape == "capsule" and "cylinder" or shape
    end
    return "box"
end
Parking.shapeOf = shapeOf

---Orientation of a rot line (degrees), columns are the object's axes: rotX(x) rotY(y) rotZ(z), the
---way the game reads it (the converted maps' rot lines, Mat3.toEulerXYZ, were checked in game)
---@param rot number[]
---@return number[][]
function Parking.frameOf(rot)
    local r = math.rad
    return Mat3.mul(Mat3.mul(Mat3.rotX(r(rot[1] or 0)), Mat3.rotY(r(rot[2] or 0))), Mat3.rotZ(r(rot[3] or 0)))
end

---@class ParkingGhost: HighlightBox
---@field shape string
---@field pos number[]
---@field frame number[][]
---@field sides number[] box sides, sphere: radius first, pill: radius, length

---What a parked object looks like, for drawing. Worked out again only when its lines change
---@param obj FileParserEnvObj
---@return ParkingGhost? nil without a pos line
function Parking.ghost(obj)
    local p = obj.props
    if not p.pos then return nil end
    local key = table.concat({ p.pos, p.rot or "", p.sides or "", p.shape or "" }, "|")
    local cached = obj.ghostCache
    if cached and cached.key == key then return cached.ghost end
    local sides = numbers(p.sides)
    for k = 1, 3 do sides[k] = math.max(math.abs(sides[k] or 0), 0.01) end
    local ghost = { shape = shapeOf(obj), pos = numbers(p.pos), frame = Parking.frameOf(numbers(p.rot)), sides = sides }
    obj.ghostCache = { key = key, ghost = ghost }
    return ghost
end

---Game values a parked object needs in its lines: the flag (static or not, for Unpark's id range) and
---the color (for the atmo). Objects from the file have them, older ones may not
---@param obj FileParserEnvObj in the world
local function writeMissingLines(obj)
    local id = obj.id - 1
    if obj.props.flag == nil then
        local flag = get_obj_flag(id)
        obj.props.flag = tostring(flag or MGE.FLAGS.STATIC)
    end
    if obj.props.color == nil then
        local ok, r, g, b, a = pcall(get_obj_color, id)
        if ok and type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
        if ok and tonumber(r) then obj.props.color = FileHandler.formatNumbers(r, g, b, a or 1) end
    end
end

---Park: the selected objects leave the game's objects (their ids are freed) and become parked, still
---selected. Objects joined by a joint stay: a joint can only hold objects in the game
function Parking.park()
    local selected = ModData.getSelected()
    if #selected == 0 then
        echo("^04[MGE] select the objects to park first")
        return
    end
    ModData.refreshJointIds() -- links made since the mod loaded count too
    local parked, joined = {}, 0
    for i = #ModData.parsed.env_obj, 1, -1 do
        local obj = ModData.parsed.env_obj[i]
        if obj.selected then
            if ModData.jointIds[obj.id] then
                joined = joined + 1
            else
                writeMissingLines(obj)
                table.remove(ModData.parsed.env_obj, i)
                ModData.releaseId(obj.id)
                table.insert(parked, 1, obj) -- kept in id order
            end
        end
    end
    if joined > 0 then
        echo("^04[MGE] " .. joined .. " objects joined by joints stay in the game, remove their joints to park them")
    end
    if #parked == 0 then return end
    for _, obj in ipairs(parked) do
        table.insert(ModData.parsed.parked, obj)
        obj.id = #ModData.parsed.parked -- parked ids are their place in the list
    end
    echo("^04[MGE] parked " .. #parked .. " objects (" .. #ModData.parsed.parked .. " parked in all)")
    History.commit()
    MGE.apply()
end

---Unpark: selected parked objects get free ids and are objects in the game again, still selected. When
---there aren't enough ids the first ones come back and the rest stay parked
function Parking.unpark()
    local list = ModData.getSelectedParked()
    if #list == 0 then
        echo("^04[MGE] select parked objects (P in the list) to unpark first")
        return
    end
    local free = #ModData.freeIds.static + #ModData.freeIds.nonStatic
    local count = math.min(#list, free)
    if count == 0 then
        echo("^04[MGE] no free object ids (" .. MGE.MAX_ENV_OBJECTS .. " in the game): park or delete objects first")
        return
    end
    local plans = {}
    for i = 1, count do plans[i] = { pool = ModData.idPool(list[i], false, {}), linked = false } end
    local ids = ModData.allocateIds(plans)
    if not ids then return end -- allocateIds says why
    local back = {}
    for i = 1, count do
        back[list[i]] = true
        list[i].id = ids[i]
        table.insert(ModData.parsed.env_obj, list[i])
    end
    local stay = {}
    for _, obj in ipairs(ModData.parsed.parked) do
        if not back[obj] then
            stay[#stay + 1] = obj
            obj.id = #stay
        end
    end
    ModData.parsed.parked = stay
    ModData.sortObjects()
    echo("^04[MGE] unparked " .. count .. " objects" ..
        (count < #list and (", " .. (#list - count) .. " stay parked: no more free ids") or ""))
    History.commit()
    MGE.apply()
end

---@return integer parked objects an import may still add (maxParked minus those parked already)
function Parking.room()
    return math.max(0, Parking.maxParked - #ModData.parsed.parked)
end

---Adds objects as parked, selected (an import's objects over the free ids, ui/assets.lua). No undo
---step or save of its own: the import makes them
---@param objects FileParserEnvObj[]
function Parking.add(objects)
    for _, obj in ipairs(objects) do
        obj.kind, obj.selected = "env_obj", true
        table.insert(ModData.parsed.parked, obj)
        obj.id = #ModData.parsed.parked
    end
end

---Removes the selected parked objects (the list's Delete, ui/editor.lua does the rest)
---@return integer removed
function Parking.removeSelected()
    local stay = {}
    for _, obj in ipairs(ModData.parsed.parked) do
        if not obj.selected then
            stay[#stay + 1] = obj
            obj.id = #stay
        end
    end
    local removed = #ModData.parsed.parked - #stay
    ModData.parsed.parked = stay
    return removed
end

---Name the atmo gets: the mod's, with atmoPrefix
---@return string file name in data/atmospheres
function Parking.atmoName()
    local name = tostring(MGE.sourcePath or MGE.modPath or "mod"):gsub("^.*[/\\]", ""):gsub("%.tbm$", "")
    if name == "" or name == MGE.outputName:gsub("%.tbm$", "") then name = "unsaved" end
    return Parking.atmoPrefix .. name .. ".atmo"
end

---@param value number
---@return string
local function fmt(value) return FileHandler.formatNumber(value) end

---The atmo text for the parked objects. Objects the game wouldn't show (visible 0) are left out, models
---are drawn as their shape. Atmo rotations turn the other way round than mod files' (toriui's
---UIElement3D builds Rz Ry Rx and draws its transpose), so the angles are written negated
---@param parked FileParserEnvObj[]
---@param source string? what the comment at the top names
---@return string text, integer written, integer models drawn as their shape
function Parking.atmoText(parked, source)
    local lines = { "# made by MGE from " .. tostring(source or "a mod") .. ": its parked objects, drawn only (no collisions)", "" }
    local written, models = 0, 0
    for _, obj in ipairs(parked) do
        local p = obj.props
        if p.pos and tonumber(p.visible or "1") ~= 0 then
            written = written + 1
            if p.use_model == "1" then models = models + 1 end
            local pos, rot, sides = numbers(p.pos), numbers(p.rot), numbers(p.sides)
            local color = numbers(p.color or "1 1 1 1")
            for k = 1, 3 do color[k] = math.min(math.max(color[k] or 1, 0), 2) end -- above 2 the game reads 0-256
            color[4] = math.min(math.max(color[4] or 1, 0), 1)
            table.insert(lines, "env_obj mge_" .. written)
            table.insert(lines, "\tshape " .. shapeOf(obj))
            table.insert(lines, "\tpos " .. fmt(pos[1] or 0) .. " " .. fmt(pos[2] or 0) .. " " .. fmt(pos[3] or 0))
            table.insert(lines, "\trot " .. fmt(-(rot[1] or 0)) .. " " .. fmt(-(rot[2] or 0)) .. " " .. fmt(-(rot[3] or 0)))
            table.insert(lines, "\tsize " .. fmt(sides[1] or 1) .. " " .. fmt(sides[2] or 1) .. " " .. fmt(sides[3] or 1))
            table.insert(lines, "\tcolor " .. fmt(color[1]) .. " " .. fmt(color[2]) .. " " .. fmt(color[3]) .. " " .. fmt(color[4]))
            table.insert(lines, "")
        end
    end
    return table.concat(lines, "\n"), written, models
end

---Export atmo: writes every parked object into data/atmospheres. Loading it is up to the player
---(the main menu's Shaders & Atmos > Atmos lists it)
function Parking.exportAtmo()
    local parked = ModData.parsed.parked
    if #parked == 0 then
        echo("^04[MGE] nothing parked to export: Park moves selected objects there")
        return
    end
    local name = Parking.atmoName()
    local text, written, models = Parking.atmoText(parked, MGE.sourcePath or MGE.modPath)
    local file = Files.Open(Parking.atmoFolder .. name, FILES_MODE_WRITE)
    if not file or not file.data then
        echo("^04[MGE] couldn't write " .. name)
        return
    end
    for line in (text .. "\n"):gmatch("(.-)\n") do file:writeLine(line) end
    file:close()
    echo("^04[MGE] wrote data/atmospheres/" .. name .. ": " .. written .. " objects" ..
        (models > 0 and (", " .. models .. " models drawn as their shape") or "") ..
        ". Load it in the main menu's Shaders & Atmos > Atmos")
end

return Parking
