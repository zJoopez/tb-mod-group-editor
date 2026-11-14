-- The atmo layer: atmo objects, kept in ModData.parsed.atmo and in the mod's own atmosphere file,
-- data/atmospheres/MGE - <mod>.atmo (utils/atmo.lua: read with the mod, written by Save when it
-- changed). The game draws atmo objects without collisions and past its object limit
-- (MGE.MAX_ENV_OBJECTS); each player loads the atmo themselves (main menu's Shaders & Atmos > Atmos).
-- MGE draws them itself (utils/highlight.lua with AtmoLayer.ghost); the Atmo list shows them (A1, A2...).
--   To atmo (Objects > Advanced):  the selected objects become atmo objects, their ids are free for others
--   To objects (the Atmo tab):     selected atmo objects come back as objects, as many as there are free ids
--   Save atmo:                     writes the atmo file now, without saving the mod
-- Atmo objects aren't in the world, but they're edited like objects (utils/transforms.lua reads and
-- writes their lines). AtmoLayer.moveBy / rotateBy / scaleBy only draw a gizmo drag's preview.
-- Only so many are drawn (the nearest): the game draws only so many shapes a frame, and the Generate
-- preview comes first.
-- An atmo object's id is its place in the atmo list, NOT an object id: never hand one to get_obj_*
-- (AtmoLayer.isAtmo tells them apart)
local ModData = MGE.ModData
local History = MGE.History
local Mat3 = MGE.Mat3
local FileHandler = MGE.FileHandler

---@class AtmoLayer
local AtmoLayer = {
    color = { 0.75, 0.45, 1.0 }, -- ghost fill, selected ones use the selection highlight's color
    alpha = 0.15,
    -- the atmo's size, what imports, Generate, Duplicate and To atmo may fill. MGE draws every atmo object
    -- (utils/highlight.lua): 256 leaves 256 more shapes for the rest MGE draws, next to the game's 256
    -- objects. How many the game draws a frame depends on its graphics settings (10 000 drew on the
    -- lowest): Settings > Most atmo objects raises it, the player's call
    maxAtmo = 256,
    -- the objects' alpha while the Atmo list shows (set live, put back after): see-through, the atmo in front
    seeThroughAlpha = 0.15,
    ---@type { move: number[]?, rotation: number[][]?, scale: number[]?, pivot: number[], frame: number[][] }?
    ---a gizmo drag in progress on the selected atmo objects: their ghosts are drawn where it puts them
    live = nil,
}
MGE.AtmoLayer = AtmoLayer

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
AtmoLayer.shapeOf = shapeOf

---A rot line (degrees) as the rotation draw_*_m needs to show it the way the game shows the object:
---rotX(-x) rotY(-y) rotZ(-z), the same matrix get_obj_rot gives for it (measured in game with
---mge/tools/rotcheck.lua, 2026-11-14: rot 10 -20 30 matched exactly) and Transforms.orientationOf's.
---Earlier versions drew rotX(x) rotY(y) rotZ(z) and then its transpose: ghosts showed turned wrong
---@param rot number[]
---@return number[][]
function AtmoLayer.frameOf(rot)
    local r = math.rad
    return Mat3.mul(Mat3.mul(Mat3.rotX(-r(rot[1] or 0)), Mat3.rotY(-r(rot[2] or 0))), Mat3.rotZ(-r(rot[3] or 0)))
end

---@class AtmoGhost: HighlightBox
---@field shape string
---@field pos number[]
---@field frame number[][]
---@field sides number[] box sides, sphere: radius first, pill: radius, length

---What an atmo object looks like, for drawing. Worked out again only when its lines change
---@param obj FileParserEnvObj
---@return AtmoGhost? nil without a pos line
function AtmoLayer.ghost(obj)
    local p = obj.props
    if not p.pos then return nil end
    local key = table.concat({ p.pos, p.rot or "", p.sides or "", p.shape or "" }, "|")
    local cached = obj.ghostCache
    if cached and cached.key == key then return cached.ghost end
    local sides = numbers(p.sides)
    for k = 1, 3 do sides[k] = math.max(math.abs(sides[k] or 0), 0.01) end
    local ghost = { shape = shapeOf(obj), pos = numbers(p.pos), frame = AtmoLayer.frameOf(numbers(p.rot)), sides = sides }
    obj.ghostCache = { key = key, ghost = ghost }
    return ghost
end

---Game values an atmo object needs in its lines: the flag (static or not, for To objects' id range) and
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

---Moves the selected objects into the atmo: they leave the game's objects (their ids are freed), still
---selected. Objects joined by a joint stay: a joint can only hold objects in the game
function AtmoLayer.moveIn()
    local selected = ModData.getSelected()
    if #selected == 0 then
        echo("^04[MGE] select the objects to move to the atmo first")
        return
    end
    ModData.refreshJointIds() -- links made since the mod loaded count too
    local moved, joined = {}, 0
    for i = #ModData.parsed.env_obj, 1, -1 do
        local obj = ModData.parsed.env_obj[i]
        if obj.selected then
            if ModData.jointIds[obj.id] then
                joined = joined + 1
            else
                writeMissingLines(obj)
                MGE.Atmo.fromMod(obj)
                obj.kind = "atmo"
                table.remove(ModData.parsed.env_obj, i)
                ModData.releaseId(obj.id)
                table.insert(moved, 1, obj) -- kept in id order
            end
        end
    end
    if joined > 0 then
        echo("^04[MGE] " .. joined .. " objects joined by joints stay in the game, remove their joints to move them")
    end
    if #moved == 0 then return end
    for _, obj in ipairs(moved) do
        table.insert(ModData.parsed.atmo, obj)
        obj.id = #ModData.parsed.atmo -- atmo ids are their place in the list
    end
    echo("^04[MGE] moved " .. #moved .. " objects to the atmo (" .. #ModData.parsed.atmo .. " atmo objects in all)")
    History.commit()
    MGE.apply()
end

---Moves the selected atmo objects back: they get free ids and are objects in the game again, still selected. When
---there aren't enough ids the first ones come back and the rest stay in the atmo
function AtmoLayer.moveOut()
    local list = ModData.getSelectedAtmo()
    if #list == 0 then
        echo("^04[MGE] select atmo objects (the Atmo list) to move back first")
        return
    end
    local free = #ModData.freeIds.static + #ModData.freeIds.nonStatic
    local count = math.min(#list, free)
    if count == 0 then
        echo("^04[MGE] no free object ids (" .. MGE.MAX_ENV_OBJECTS .. " in the game): move or delete objects first")
        return
    end
    local plans = {}
    for i = 1, count do plans[i] = { pool = ModData.idPool(list[i], false, {}), linked = false } end
    local ids = ModData.allocateIds(plans)
    if not ids then return end -- allocateIds says why
    local back = {}
    for i = 1, count do
        back[list[i]] = true
        list[i].id, list[i].kind = ids[i], "env_obj"
        table.insert(ModData.parsed.env_obj, list[i])
    end
    local stay = {}
    for _, obj in ipairs(ModData.parsed.atmo) do
        if not back[obj] then
            stay[#stay + 1] = obj
            obj.id = #stay
        end
    end
    ModData.parsed.atmo = stay
    ModData.sortObjects()
    echo("^04[MGE] moved " .. count .. " atmo objects back to objects" ..
        (count < #list and (", " .. (#list - count) .. " stay in the atmo: no more free ids") or ""))
    History.commit()
    MGE.apply()
end

---To atmo (the Advanced tab): moveIn, then the Atmo list shows them, still selected
function AtmoLayer.toAtmo()
    local before = #ModData.parsed.atmo
    AtmoLayer.moveIn()
    if #ModData.parsed.atmo > before and MGE.Main then MGE.Main.setListTab("atmo") end
end

---To objects (the Atmo list's Atmo tab): moveOut, then the Objects list shows them, still selected
function AtmoLayer.toObjects()
    local before = #ModData.parsed.atmo
    AtmoLayer.moveOut()
    if #ModData.parsed.atmo < before and MGE.Main then MGE.Main.setListTab("objects") end
end

---@return integer atmo objects an import may still add (maxAtmo minus those there already)
function AtmoLayer.room()
    return math.max(0, AtmoLayer.maxAtmo - #ModData.parsed.atmo)
end

---Adds objects to the atmo, selected (an import's objects over the free ids, ui/assets.lua). No undo
---step or save of its own: the import makes them
---@param objects FileParserEnvObj[]
function AtmoLayer.add(objects)
    for _, obj in ipairs(objects) do
        obj.kind, obj.selected = "atmo", true
        MGE.Atmo.fromMod(obj)
        table.insert(ModData.parsed.atmo, obj)
        obj.id = #ModData.parsed.atmo
    end
end

---Unloads the atmo the game has loaded (main menu > Shaders & Atmos > Atmos, or its default atmo from
---data/atmospheres/atmo.cfg), back to the game's default look: MGE draws the mod's atmo itself, a
---loaded copy of it (MGE - <mod>.atmo, after a Save) would show every object twice, its old version
---where the edited ones were. Called once, when MGE starts.
---Nothing loaded (_ATMO nil, the game manager's own flag): nothing happens, the shader stays as it is.
---The default in atmo.cfg stays: the player's choice for the next game start
---@return boolean unloaded
function AtmoLayer.unloadGameAtmo()
    if rawget(_G, "_ATMO") == nil then return false end
    local manager = rawget(_G, "Atmospheres")
    if type(manager) ~= "table" or type(manager.Unload) ~= "function" then return false end
    local ok = pcall(manager.Unload)
    if ok then echo("^04[MGE] unloaded the game's atmo: MGE draws the atmo it edits itself") end
    return ok
end

---Removes the selected atmo objects (the list's Delete, ui/editor.lua does the rest)
---@return integer removed
function AtmoLayer.removeSelected()
    local stay = {}
    for _, obj in ipairs(ModData.parsed.atmo) do
        if not obj.selected then
            stay[#stay + 1] = obj
            obj.id = #stay
        end
    end
    local removed = #ModData.parsed.atmo - #stay
    ModData.parsed.atmo = stay
    return removed
end

---The object is an atmo object (kind "atmo": its id is its place in the atmo list, not an object id)
---@param obj FileParserEnvObj
---@return boolean
function AtmoLayer.isAtmo(obj)
    return obj.kind == "atmo"
end

---pos line as numbers, 0 0 0 without one
---@param obj FileParserEnvObj
---@return number[]
local function posOf(obj)
    local p = numbers(obj.props.pos)
    return { p[1] or 0, p[2] or 0, p[3] or 0 }
end
AtmoLayer.posOf = posOf

---Middle of the atmo objects (average of their pos lines), where the gizmo goes for them alone
---@param list FileParserEnvObj[]
---@return number[]
function AtmoLayer.center(list)
    local c = { 0, 0, 0 }
    for _, obj in ipairs(list) do
        local p = posOf(obj)
        for k = 1, 3 do c[k] = c[k] + p[k] / #list end
    end
    return c
end

---Moves atmo objects by offset: pos lines only (no undo step: the caller commits, with the
---objects' move when there are some)
---@param list FileParserEnvObj[]
---@param offset number[]
---@param props table<FileParserEnvObj, table>? write into these copies of the props instead (preview)
function AtmoLayer.moveBy(list, offset, props)
    for _, obj in ipairs(list) do
        local target = props and props[obj] or obj
        local p = numbers(target.props.pos)
        MGE.Transforms.writeVector(target, "pos", { (p[1] or 0) + offset[1], (p[2] or 0) + offset[2], (p[3] or 0) + offset[3] })
    end
end

local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")

---Turns atmo objects by a rotation matrix around pivot, with the same math as the objects' rotate
---(Transforms.rotBy: RotatingOld on the pos and rot lines), so an atmo object ends up the way an
---object would. Lines only, the caller commits
---@param list FileParserEnvObj[]
---@param rotation number[][]
---@param pivot number[]
---@param props table<FileParserEnvObj, table>? see moveBy
function AtmoLayer.rotateBy(list, rotation, pivot, props)
    local ox, oy, oz = Mat3.toEulerXYZ(rotation) -- rotBy's offsets: rotX(x) rotY(y) rotZ(z)
    for _, obj in ipairs(list) do
        local target = props and props[obj] or obj
        local pos, rot = numbers(target.props.pos), numbers(target.props.rot)
        local r = math.rad
        local outPos = RotatingOld.SetRotPos(pos[1] or 0, pos[2] or 0, pos[3] or 0, pivot[1], pivot[2], pivot[3], ox, oy, oz)
        local outRot = RotatingOld.SetRotOffset(r(rot[1] or 0), r(rot[2] or 0), r(rot[3] or 0), ox, oy, oz)
        MGE.Transforms.writeVector(target, "rot", outRot)
        MGE.Transforms.writeVector(target, "pos", outPos)
    end
end

---Scales atmo objects by factors along frame's axes around pivot, like the objects' Resize
---(Transforms.planScale: positions through the group scale, sides by Transforms.scaleSidesFor with the
---shape their shape line gives). Lines only, the caller commits
---@param list FileParserEnvObj[]
---@param factors number[]
---@param pivot number[]
---@param frame number[][] group frame, columns are its axes
---@param props table<FileParserEnvObj, table>? see moveBy
function AtmoLayer.scaleBy(list, factors, pivot, frame, props)
    local T = MGE.Transforms
    local map = Mat3.mul(Mat3.mul(frame, { { factors[1], 0, 0 }, { 0, factors[2], 0 }, { 0, 0, factors[3] } }), Mat3.transpose(frame))
    for _, obj in ipairs(list) do
        local target = props and props[obj] or obj
        local p = numbers(target.props.pos)
        local rel = Mat3.apply(map, { (p[1] or 0) - pivot[1], (p[2] or 0) - pivot[2], (p[3] or 0) - pivot[3] })
        local s = numbers(target.props.sides)
        local sides = T.scaleSidesFor(target, { s[1] or 1, s[2] or 1, s[3] or 1 }, frame, factors, shapeOf(target))
        T.writeVector(target, "pos", { pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3] })
        T.writeVector(target, "sides", sides)
    end
end

---The selected atmo objects as a gizmo drag in progress would leave them: copies with changed lines
---(AtmoLayer.live), drawn instead of them. nil when no drag is on
---@return table<FileParserEnvObj, FileParserEnvObj>? copies by object
function AtmoLayer.liveCopies()
    local live = AtmoLayer.live
    if not live then return nil end
    local list, copies = {}, {}
    for _, obj in ipairs(ModData.getSelectedAtmo()) do
        list[#list + 1] = obj
        copies[obj] = { kind = obj.kind, id = obj.id, props = ModData.copy(obj.props), selected = true }
    end
    if live.move then AtmoLayer.moveBy(list, live.move, copies) end
    if live.rotation then AtmoLayer.rotateBy(list, live.rotation, live.pivot, copies) end
    if live.scale then AtmoLayer.scaleBy(list, live.scale, live.pivot, live.frame, copies) end
    return copies
end

---@type table<integer, number[]>? the objects' live colors before they turned see-through (game ids, 0-based)
local seeThrough = nil

---The mod's objects see-through (the Atmo list: the atmo objects are what's edited) or back. Live only:
---their color's alpha set with set_obj_color, the file's lines untouched, the colors before put back.
---A reload brings the file's colors back by itself, AtmoLayer.reapplySeeThrough makes them see-through again
---@param on boolean
function AtmoLayer.setObjectsSeeThrough(on)
    if on then
        if seeThrough then return end
        seeThrough = {}
        for _, obj in ipairs(ModData.parsed.env_obj) do
            local id = obj.id - 1
            if get_obj_pos(id) ~= nil then
                local ok, r, g, b, a = pcall(get_obj_color, id)
                if ok and type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
                if ok and tonumber(r) then
                    seeThrough[id] = { r, g, b, a or 1 }
                    pcall(set_obj_color, id, r, g, b, math.min(a or 1, AtmoLayer.seeThroughAlpha))
                end
            end
        end
    elseif seeThrough then
        for id, c in pairs(seeThrough) do
            if get_obj_pos(id) ~= nil then pcall(set_obj_color, id, c[1], c[2], c[3], c[4]) end
        end
        seeThrough = nil
    end
end

---After a reload (the game set the file's colors again): see-through again when it was
function AtmoLayer.reapplySeeThrough()
    if not seeThrough then return end
    seeThrough = nil
    AtmoLayer.setObjectsSeeThrough(true)
end

table.insert(MGE.onQuit, function() AtmoLayer.setObjectsSeeThrough(false) end)

---Export atmo: writes the atmo layer to the mod's file now, data/atmospheres/MGE - <mod>.atmo, as Save
---does (utils/atmo.lua). Loading it is up to the player (main menu > Shaders & Atmos > Atmos)
function AtmoLayer.exportAtmo()
    if not MGE.sourcePath then
        echo("^04[MGE] save the mod first: its atmo is named after it")
        return
    end
    if #ModData.parsed.atmo == 0 then
        echo("^04[MGE] the atmo is empty: To atmo (Objects > Advanced) or New add to it")
        return
    end
    if not MGE.Atmo.hasChanges() then
        echo("^04[MGE] data/atmospheres/" .. tostring(MGE.Atmo.fileName(MGE.sourcePath)) .. " is up to date")
        return
    end
    MGE.Atmo.saveFor(MGE.sourcePath)
end

return AtmoLayer
