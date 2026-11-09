-- Click objects in the world to select them: click selects only that object, Shift + click adds /
-- removes it (ModData.clickSelect, same as the object list).
--
-- The click is turned into a camera ray by MGE itself and intersected exactly with every object's
-- shape (box, sphere, capsule). The nearest hit along the ray wins, so objects in front block the
-- ones behind them.
--
-- To build the ray, the camera's projection is measured each click: get_screen_pos is called for
-- three points around the look-at point (always on screen) and the click is mapped back through
-- that projection. Approaches tried before (don't switch back):
--   * engine raycast (create_raycast_body + shoot_camera_ray): picks inaccurately in game
--   * object outlines projected with get_screen_pos: off-screen points come back unusable, so
--     objects partly off screen (close ones, large ones below) couldn't be picked
require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

local ModData = MGE.ModData
local SHAPE = MGE.SHAPE
local HOOK_SET = MGE.hookname .. "_worldselect" -- own set, MGE's draw3d hook is used by highlight

---@class WorldSelect
local WorldSelect = {
    clickMoveLimit = 4, -- pixels the mouse may move between down and up to still count as a click
    enabled = true, -- toggled by the mouse button in the top menu, off lets you play without selecting
}

---@type { x: number, y: number }?
local pressed = nil
---@type { x: number, y: number, additive: boolean }? click waiting for the next draw3d (get_screen_pos only works there)
local pendingClick = nil

local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function scale(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function length(a) return math.sqrt(dot(a, a)) end
local function normalize(a)
    local l = length(a)
    if l < 1e-12 then return nil end
    return scale(a, 1 / l)
end

---Camera ray through a screen position. Must be called from draw3d (uses get_screen_pos)
---@param x number
---@param y number
---@return number[]? origin, number[]? direction normalized
function WorldSelect.cameraRay(x, y)
    local info = get_camera_info()
    local eye = { info.pos.x, info.pos.y, info.pos.z }
    local target = { info.lookat.x, info.lookat.y, info.lookat.z }
    local toTarget = sub(target, eye)
    local dist = length(toTarget)
    local forward = normalize(toTarget)
    if not forward then return nil end
    local right = normalize(cross(forward, { 0, 0, 1 })) or { 1, 0, 0 } -- straight down: any right works
    local up = cross(right, forward)

    -- measure the projection: screen offset = M * (sideways / depth) for points around the target
    local cx, cy, cz = get_screen_pos(target[1], target[2], target[3])
    if cx == nil or cz ~= 0 then return nil end
    local e = dist * 0.05
    local rx, ry = get_screen_pos(target[1] + right[1] * e, target[2] + right[2] * e, target[3] + right[3] * e)
    local ux, uy = get_screen_pos(target[1] + up[1] * e, target[2] + up[2] * e, target[3] + up[3] * e)
    if rx == nil or ux == nil then return nil end
    local k = dist / e -- 1 / (sideways / depth) of the measured points
    local m11, m21 = (rx - cx) * k, (ry - cy) * k
    local m12, m22 = (ux - cx) * k, (uy - cy) * k
    local det = m11 * m22 - m12 * m21
    if math.abs(det) < 1e-9 then return nil end

    local ox, oy = x - cx, y - cy
    local a = (ox * m22 - m12 * oy) / det
    local b = (m11 * oy - m21 * ox) / det
    return eye, normalize(add(forward, add(scale(right, a), scale(up, b))))
end

---World directions of an object's local axes. get_obj_rot is row-major, the axes are its columns
---(same as the editor's scale code)
---@param id integer 0-based object id
---@return number[][]
local function getLocalAxes(id)
    local raw = get_obj_rot(id)
    if type(raw) ~= "table" then return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } end
    local m = Utils3D.MatrixToMatrixTB(raw)
    return { { m.r0, m.r4, m.r8 }, { m.r1, m.r5, m.r9 }, { m.r2, m.r6, m.r10 } }
end

---Distance along the ray to a sphere, nil when missed or when the ray starts inside it
local function hitSphere(origin, dir, center, radius)
    local oc = sub(origin, center)
    local b = dot(oc, dir)
    local c = dot(oc, oc) - radius * radius
    local h = b * b - c
    if h < 0 then return nil end
    local t = -b - math.sqrt(h)
    return t >= 0 and t or nil
end

---Distance along the ray to an oriented box (half sizes along the local axes)
local function hitBox(origin, dir, center, axes, half)
    local rel = sub(origin, center)
    local tmin, tmax = -math.huge, math.huge
    for i = 1, 3 do
        local o, d = dot(rel, axes[i]), dot(dir, axes[i])
        if math.abs(d) < 1e-12 then
            if math.abs(o) > half[i] then return nil end
        else
            local t1, t2 = (-half[i] - o) / d, (half[i] - o) / d
            if t1 > t2 then t1, t2 = t2, t1 end
            if t1 > tmin then tmin = t1 end
            if t2 < tmax then tmax = t2 end
            if tmin > tmax then return nil end
        end
    end
    return tmin >= 0 and tmin or nil -- negative: camera inside the box, can't pick it from there
end

---Distance along the ray to a capsule (segment a-b with radius)
local function hitCapsule(origin, dir, a, b, radius)
    local ba, oa = sub(b, a), sub(origin, a)
    local baba, bard, baoa = dot(ba, ba), dot(ba, dir), dot(ba, oa)
    local rdoa, oaoa = dot(dir, oa), dot(oa, oa)
    local qa = baba - bard * bard
    local best
    if qa > 1e-12 then -- straight part
        local qb = baba * rdoa - baoa * bard
        local qc = baba * oaoa - baoa * baoa - radius * radius * baba
        local h = qb * qb - qa * qc
        if h >= 0 then
            local t = (-qb - math.sqrt(h)) / qa
            local along = baoa + t * bard
            if t >= 0 and along > 0 and along < baba then best = t end
        end
    end
    for _, capCenter in ipairs({ a, b }) do -- round ends
        local t = hitSphere(origin, dir, capCenter, radius)
        if t and (not best or t < best) then best = t end
    end
    return best
end

---Distance along the ray to a world object, nil when missed
---@param id integer 0-based object id
---@return number?
function WorldSelect.hitObject(origin, dir, id)
    local x, y, z = get_obj_pos(id)
    if x == nil then return nil end
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    local center = { x, y, z }
    if shape == SHAPE.SPHERE then -- x radius
        return hitSphere(origin, dir, center, sx)
    end
    local axes = getLocalAxes(id)
    if shape == SHAPE.CAPSULE then -- x radius, y length of the straight part along local z
        local halfAxis = scale(axes[3], sy / 2)
        return hitCapsule(origin, dir, sub(center, halfAxis), add(center, halfAxis), sx)
    end
    return hitBox(origin, dir, center, axes, { sx / 2, sy / 2, sz / 2 }) -- box, full sizes
end

---Mod object under the screen position, nearest along the camera ray. Must be called from draw3d
---@param x number
---@param y number
---@return FileParserEnvObj?
function WorldSelect.pick(x, y)
    local origin, dir = WorldSelect.cameraRay(x, y)
    if not origin or not dir then return nil end
    local best, bestT = nil, math.huge
    for _, obj in ipairs(ModData.parsed.env_obj) do
        local t = WorldSelect.hitObject(origin, dir, obj.id - 1)
        if t and t < bestT then best, bestT = obj, t end
    end
    return best
end

local function isOverUI(x, y)
    return MGE.Widgets.isMouseOverUI(x, y) -- Widgets loads after this module, read on use
end

local function isActive()
    local Main = MGE.Main -- created after this module loads
    return WorldSelect.enabled and Main and Main.window and Main.window.displayed and not TB_MENU_INPUT_ISACTIVE
end

---Turns click to select on or off. A click already waiting is dropped when turned off
---@param enabled boolean
function WorldSelect.setEnabled(enabled)
    WorldSelect.enabled = enabled
    if not enabled then pressed, pendingClick = nil, nil end
end

add_hook("mouse_button_down", HOOK_SET, function(button, x, y)
    pressed = nil
    if button ~= 1 or not isActive() or isOverUI(x, y) then return end
    pressed = { x = x, y = y }
end)

add_hook("mouse_button_up", HOOK_SET, function(button, x, y)
    local start = pressed
    pressed = nil
    if button ~= 1 or not start or not isActive() then return end
    local limit = WorldSelect.clickMoveLimit
    if math.abs(x - start.x) > limit or math.abs(y - start.y) > limit then return end -- camera drag
    pendingClick = { x = x, y = y, additive = get_keyboard_shift() ~= 0 } -- Shift read at the click
end)

add_hook("draw3d", HOOK_SET, function()
    local click = pendingClick
    if not click then return end
    pendingClick = nil
    local ok, obj = pcall(WorldSelect.pick, click.x, click.y)
    if not ok then
        echo("[MGE] world select error: " .. tostring(obj))
        return
    end
    if not obj then return end
    ModData.clickSelect(obj, click.additive)
    MGE.Main.updateWindow() -- list checkboxes and editor values follow the selection
end)

-- MGE.quit removes hooks of MGE.hookname only
table.insert(MGE.onQuit, function() remove_hooks(HOOK_SET) end)

MGE.WorldSelect = WorldSelect
