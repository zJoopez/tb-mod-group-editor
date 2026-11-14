-- Click anything in the world to select it, whichever list shows (pickAny): a joint's anchor (any joint
-- on the Joints list, which draws them; elsewhere the ones the game shows, visible 1), else the nearest
-- player or object under the cursor. A joint, player or object from another list switches the list to
-- Joints / Players / Objects with only it selected; on its own list a click selects only it, Shift +
-- click adds / removes it (ModData.clickSelect, Main.selectPlayer, Main.selectJoint, like the lists).
-- Objects don't switch away from the Joints list: its Link tab picks them for the current slot's draft
-- (Joints.offerDraft), on Properties one starts a new joint in the lowest empty slot.
--
-- Shift + drag draws a box and adds what's in it to the current list's selection (no list switch):
-- objects any of its rays hits (a grid of rays over the box plus one through every object center in
-- it, nearest hit per ray, so hidden objects stay unselected), players with a joint in it, joint
-- anchors in it (not on the Link tab). Shift + press never turns the camera, a Shift press released
-- without moving is the usual Shift + click.
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
    clicksOff = false, -- true: clicks in the world don't select, only the gizmo works (ui/map_place.lua)
    boxGridStep = 12, -- box select: pixels between its rays
    boxGridMax = 40, -- box select: at most this many rays + 1 per side (big boxes get a coarser grid)
}

---@type { x: number, y: number, box: boolean?, endX: number?, endY: number?, moved: boolean? }? box:
---a Shift press, dragging draws a box (endX / endY the mouse, moved once past clickMoveLimit)
local pressed = nil
---@type { x1: number, y1: number, x2: number, y2: number }? box waiting for the next draw3d
local pendingBox = nil
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

---@class CameraProjection
---@field eye number[]
---@field forward number[]
---@field right number[]
---@field up number[]
---@field cx number screen position of the look-at point
---@field cy number
---@field m11 number screen offset = M * (sideways / depth)
---@field m12 number
---@field m21 number
---@field m22 number
---@field det number

---Measures the camera's projection. Must be called from draw3d (uses get_screen_pos), the result
---stays valid while the camera doesn't move, so mouse events can use the one from the last frame
---@return CameraProjection?
function WorldSelect.measureProjection()
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
    return { eye = eye, forward = forward, right = right, up = up, cx = cx, cy = cy,
        m11 = m11, m12 = m12, m21 = m21, m22 = m22, det = det }
end

---Camera ray through a screen position, for a measured projection (works outside draw3d)
---@param p CameraProjection
---@param x number
---@param y number
---@return number[] origin, number[]? direction normalized
function WorldSelect.rayFrom(p, x, y)
    local ox, oy = x - p.cx, y - p.cy
    local a = (ox * p.m22 - p.m12 * oy) / p.det
    local b = (p.m11 * oy - p.m21 * ox) / p.det
    return p.eye, normalize(add(p.forward, add(scale(p.right, a), scale(p.up, b))))
end

---Screen position of a world point for a measured projection, the inverse of rayFrom. Works off
---screen too (get_screen_pos gives unusable values there) and outside draw3d (the gizmo draws in draw2d)
---@param p CameraProjection
---@param point number[]
---@return number? x, number? y nil when the point is behind the camera
function WorldSelect.project(p, point)
    local rel = sub(point, p.eye)
    local depth = dot(rel, p.forward)
    if depth < 1e-6 then return nil end
    local a, b = dot(rel, p.right) / depth, dot(rel, p.up) / depth
    return p.cx + p.m11 * a + p.m12 * b, p.cy + p.m21 * a + p.m22 * b
end

---Camera ray through a screen position. Must be called from draw3d (uses get_screen_pos)
---@param x number
---@param y number
---@return number[]? origin, number[]? direction normalized
function WorldSelect.cameraRay(x, y)
    local p = WorldSelect.measureProjection()
    if not p then return nil end
    return WorldSelect.rayFrom(p, x, y)
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

-- ray hits, also used by the gizmo's handles (utils/gizmo.lua)
WorldSelect.hitSphere, WorldSelect.hitBox, WorldSelect.hitCapsule = hitSphere, hitBox, hitCapsule

---@class WorldSelectShape a world object read once for many ray tests (box select)
---@field center number[]
---@field radius number bounding sphere
---@field hit fun(origin: number[], dir: number[]): number? distance along the ray, nil when missed
---@field obj FileParserEnvObj?

---@param id integer 0-based object id
---@return WorldSelectShape?
local function objectShape(id)
    local x, y, z = get_obj_pos(id)
    if x == nil then return nil end
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    local center = { x, y, z }
    if shape == SHAPE.SPHERE then -- x radius
        return { center = center, radius = sx, hit = function(o, d) return hitSphere(o, d, center, sx) end }
    end
    local axes = getLocalAxes(id)
    if shape == SHAPE.CAPSULE then -- x radius, y length of the straight part along local z
        local halfAxis = scale(axes[3], sy / 2)
        local a, b = sub(center, halfAxis), add(center, halfAxis)
        return { center = center, radius = sy / 2 + sx, hit = function(o, d) return hitCapsule(o, d, a, b, sx) end }
    end
    local half = { sx / 2, sy / 2, sz / 2 } -- box, full sizes
    return { center = center, radius = length(half), hit = function(o, d) return hitBox(o, d, center, axes, half) end }
end

---Whether the ray can reach the sphere at all (cheap test before the exact shape)
local function nearSphere(origin, dir, center, radius)
    local ox, oy, oz = origin[1] - center[1], origin[2] - center[2], origin[3] - center[3]
    local c = ox * ox + oy * oy + oz * oz - radius * radius
    if c <= 0 then return true end -- starts inside
    local b = ox * dir[1] + oy * dir[2] + oz * dir[3]
    return b < 0 and b * b >= c
end

---Distance along the ray to a world object, nil when missed
---@param id integer 0-based object id
---@return number?
function WorldSelect.hitObject(origin, dir, id)
    local s = objectShape(id)
    return s and s.hit(origin, dir)
end

---Mod object under the screen position, nearest along the camera ray. Must be called from draw3d.
---@param x number
---@param y number
---@return FileParserEnvObj?
---@return number? distance along the ray
function WorldSelect.pick(x, y)
    local origin, dir = WorldSelect.cameraRay(x, y)
    if not origin or not dir then return nil end
    local best, bestT = nil, math.huge
    for _, obj in ipairs(ModData.parsed.env_obj) do
        local t = WorldSelect.hitObject(origin, dir, obj.id - 1)
        if t and t < bestT then best, bestT = obj, t end
    end
    return best, best and bestT
end

---Joint whose anchor (the sphere the highlight draws, Highlight.anchorPickRadius) is under the screen
---position, nearest along the camera ray. Must be called from draw3d. Joints without a pos line have
---no anchor to click
---@param x number
---@param y number
---@param visibleOnly boolean? only joints the game draws itself (visible 1): off the Joints list MGE
---draws no anchors, a hidden joint there would be an invisible target
---@return FileParserEnvObjJoint?
function WorldSelect.pickJoint(x, y, visibleOnly)
    local origin, dir = WorldSelect.cameraRay(x, y)
    if not origin or not dir then return nil end
    local radius = MGE.Highlight.anchorPickRadius
    local best, bestT = nil, math.huge
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        local shown = not visibleOnly or joint.props.visible == "1"
        local p = shown and joint.id and MGE.Joints.anchorOf(joint)
        local t = p and hitSphere(origin, dir, p, radius)
        if t and t < bestT then best, bestT = joint, t end
    end
    return best
end

-- player body part shapes (BodyInfo.shape): sphere x radius, box full sides, cylinder (pill) x radius
-- y length along its z, like objects
local BODY_SPHERE, BODY_CYLINDER = 0, 2

---Distance along the ray to a player's body part, nil when missed
---@param player integer 0-based
---@param id integer body part
---@return number?
local function hitBody(origin, dir, player, id)
    local b = get_body_info(player, id)
    local center, s, r = { b.pos.x, b.pos.y, b.pos.z }, b.sides, b.rot
    if b.shape == BODY_SPHERE then return hitSphere(origin, dir, center, s.x) end
    local axes = { { r.r0, r.r4, r.r8 }, { r.r1, r.r5, r.r9 }, { r.r2, r.r6, r.r10 } } -- columns: local axes
    if b.shape == BODY_CYLINDER then
        local halfAxis = scale(axes[3], s.y / 2)
        return hitCapsule(origin, dir, sub(center, halfAxis), add(center, halfAxis), s.x)
    end
    return hitBox(origin, dir, center, axes, { s.x / 2, s.y / 2, s.z / 2 })
end

---Player under the screen position (its body parts and joints), nearest along the camera ray. Must be
---called from draw3d
---@param x number
---@param y number
---@return integer? player 0-based
---@return number? distance along the ray
function WorldSelect.pickPlayer(x, y)
    local origin, dir = WorldSelect.cameraRay(x, y)
    if not origin or not dir or not MGE.Players then return nil end
    local best, bestT = nil, math.huge
    for player = 0, MGE.Players.count() - 1 do
        if MGE.Players.exists(player) then
            for _, id in pairs(BODYPARTS) do
                local t = hitBody(origin, dir, player, id)
                if t and t < bestT then best, bestT = player, t end
            end
            for _, id in pairs(JOINTS) do
                local jx, jy, jz = get_joint_pos(player, id)
                local t = jx and hitSphere(origin, dir, { jx, jy, jz }, get_joint_radius(player, id) or 0.1)
                if t and t < bestT then best, bestT = player, t end
            end
        end
    end
    return best, best and bestT
end

---What a world click hits: a joint's anchor first (they sit on the faces between objects, the ray
---reaches an object first), else the nearer of a player and an object. Any joint on the Joints list
---(it draws every anchor, utils/highlight.lua), elsewhere only the ones the game shows (visible 1).
---Must be called from draw3d
---@param x number
---@param y number
---@return "joint"|"player"|"object"|nil kind
---@return any hit FileParserEnvObjJoint / player id (0-based) / FileParserEnvObj
function WorldSelect.pickAny(x, y)
    local joint = WorldSelect.pickJoint(x, y, MGE.Main.listTab ~= "joints")
    if joint then return "joint", joint end
    local obj, objT = WorldSelect.pick(x, y)
    local player, playerT = WorldSelect.pickPlayer(x, y)
    if player and (not obj or playerT < objT) then return "player", player end
    if obj then return "object", obj end
    return nil
end

---@param p CameraProjection
---@param point number[]
---@param box { left: number, top: number, right: number, bottom: number }
local function projectsInto(p, point, box)
    local x, y = WorldSelect.project(p, point)
    return x ~= nil and x >= box.left and x <= box.right and y >= box.top and y <= box.bottom, x, y
end

---@return { left: number, top: number, right: number, bottom: number }
local function boxOf(x1, y1, x2, y2)
    return { left = math.min(x1, x2), top = math.min(y1, y2), right = math.max(x1, x2), bottom = math.max(y1, y2) }
end

---Objects the rays through a screen box hit: a grid of rays over it plus one through every object
---center inside it (small objects between the grid's rays), each ray takes only the nearest object, so
---objects hidden behind others aren't taken. Must be called from draw3d
---@return FileParserEnvObj[] in id order
function WorldSelect.pickBox(x1, y1, x2, y2)
    local p = WorldSelect.measureProjection()
    if not p then return {} end
    local box = boxOf(x1, y1, x2, y2)
    local shapes = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        local s = objectShape(obj.id - 1)
        if s then
            s.obj = obj
            shapes[#shapes + 1] = s
        end
    end
    local points = {}
    local w, h = box.right - box.left, box.bottom - box.top
    local cols = math.max(1, math.min(WorldSelect.boxGridMax, math.ceil(w / WorldSelect.boxGridStep)))
    local rows = math.max(1, math.min(WorldSelect.boxGridMax, math.ceil(h / WorldSelect.boxGridStep)))
    for i = 0, cols do
        for j = 0, rows do points[#points + 1] = { box.left + w * i / cols, box.top + h * j / rows } end
    end
    for _, s in ipairs(shapes) do
        local inside, sx, sy = projectsInto(p, s.center, box)
        if inside then points[#points + 1] = { sx, sy } end
    end
    local taken, list = {}, {}
    for _, pt in ipairs(points) do
        local origin, dir = WorldSelect.rayFrom(p, pt[1], pt[2])
        if dir then
            local best, bestT = nil, math.huge
            for _, s in ipairs(shapes) do
                if nearSphere(origin, dir, s.center, s.radius) then
                    local t = s.hit(origin, dir)
                    if t and t < bestT then best, bestT = s.obj, t end
                end
            end
            if best and not taken[best] then
                taken[best] = true
                list[#list + 1] = best
            end
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

---Players with a joint inside a screen box. Must be called from draw3d
---@return integer[] 0-based
function WorldSelect.pickPlayersBox(x1, y1, x2, y2)
    local p = WorldSelect.measureProjection()
    if not p or not MGE.Players then return {} end
    local box = boxOf(x1, y1, x2, y2)
    local list = {}
    for player = 0, MGE.Players.count() - 1 do
        if MGE.Players.exists(player) then
            for _, id in pairs(JOINTS) do
                local jx, jy, jz = get_joint_pos(player, id)
                if jx and projectsInto(p, { jx, jy, jz }, box) then
                    list[#list + 1] = player
                    break
                end
            end
        end
    end
    return list
end

---Joints whose anchor is inside a screen box (all of them, the Joints list draws every anchor). Must be
---called from draw3d
---@return FileParserEnvObjJoint[]
function WorldSelect.pickJointsBox(x1, y1, x2, y2)
    local p = WorldSelect.measureProjection()
    if not p then return {} end
    local box = boxOf(x1, y1, x2, y2)
    local list = {}
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        local anchor = joint.id and MGE.Joints.anchorOf(joint)
        if anchor and projectsInto(p, anchor, box) then list[#list + 1] = joint end
    end
    return list
end

local function isOverUI(x, y)
    return MGE.Widgets.isMouseOverUI(x, y) -- Widgets loads after this module, read on use
end

local function isActive()
    local Main = MGE.Main -- created after this module loads
    -- clicksOff: the map placement view, it hides the window but its gizmo takes clicks
    return Main and Main.window and (Main.window.displayed or WorldSelect.clicksOff) and not TB_MENU_INPUT_ISACTIVE
end

-- The gizmo (utils/gizmo.lua, loads after this module) gets the mouse first: a press on one of its
-- handles starts a drag instead of a select, and returning 1 keeps the game from turning it into a
-- camera drag
add_hook("mouse_button_down", HOOK_SET, function(button, x, y)
    local Gizmo = MGE.Gizmo
    if Gizmo and Gizmo.isDragging() then return 1 end -- other buttons do nothing mid drag
    pressed = nil
    if button ~= 1 or not isActive() or isOverUI(x, y) then return end
    if Gizmo and Gizmo.press(x, y) then return 1 end
    if WorldSelect.clicksOff then return end -- only the gizmo (map placement), drags still turn the camera
    -- Shift: a drag draws a select box instead of turning the camera. Not while a one-shot pick waits
    if get_keyboard_shift() ~= 0 and not WorldSelect.picking then
        pressed = { x = x, y = y, box = true, endX = x, endY = y }
        return 1
    end
    pressed = { x = x, y = y }
end)

add_hook("mouse_button_up", HOOK_SET, function(button, x, y)
    local Gizmo = MGE.Gizmo
    if button == 1 and Gizmo and Gizmo.release(x, y) then
        pressed = nil
        return 1
    end
    local start = pressed
    if button ~= 1 or not start then return end
    pressed = nil
    if not isActive() then return start.box and 1 or nil end
    if start.box and start.moved then
        pendingBox = { x1 = start.x, y1 = start.y, x2 = x, y2 = y }
        return 1
    end
    local limit = WorldSelect.clickMoveLimit
    if math.abs(x - start.x) > limit or math.abs(y - start.y) > limit then return end -- camera drag
    pendingClick = { x = x, y = y, additive = start.box or get_keyboard_shift() ~= 0 } -- Shift read at the click
    if start.box then return 1 end
end)

---@type { x: number, y: number }? mouse position to test for the hovered object on the next draw3d
local pendingHover = nil
---@type FileParserEnvObj? object under the cursor on the Joints list's Link tab (highlight.lua shows it)
WorldSelect.hover = nil

---@return integer? the joint slot a world click links objects to (Main.linkSlot), nil when clicks select
local function linkSlot()
    local Main = MGE.Main -- created after this module loads
    return Main and Main.linkSlot and Main.linkSlot() or nil
end

---@type { done: fun(obj: FileParserEnvObj), ended: fun()? }? a one-shot pick (the Core tab's color
---picker): the next world click hands its object to done instead of selecting, a click on nothing
---cancels. ended runs either way (and on cancelPick)
WorldSelect.picking = nil

---Starts a one-shot pick, replacing one in progress
---@param done fun(obj: FileParserEnvObj)
---@param ended fun()? after done, or when cancelled
function WorldSelect.startPick(done, ended)
    WorldSelect.cancelPick()
    WorldSelect.picking = { done = done, ended = ended }
end

---Ends a pick in progress without picking (Esc, its button again)
---@return boolean cancelled one was in progress
function WorldSelect.cancelPick()
    local p = WorldSelect.picking
    WorldSelect.picking, WorldSelect.hover = nil, nil
    if p and p.ended then p.ended() end
    return p ~= nil
end

-- on the Link tab, and while picking, the object under the cursor is highlighted: it's what a click
-- would pick. Tested only after the mouse moved, not every frame
add_hook("mouse_move", HOOK_SET, function(x, y)
    local box = pressed and pressed.box and pressed
    if box then
        box.endX, box.endY = x, y
        local limit = WorldSelect.clickMoveLimit
        if math.abs(x - box.x) > limit or math.abs(y - box.y) > limit then box.moved = true end
    end
    if not linkSlot() and not WorldSelect.picking then return end
    if not isActive() or isOverUI(x, y) then
        pendingHover, WorldSelect.hover = nil, nil
        return
    end
    pendingHover = { x = x, y = y }
end)

---Properties tab click on an object: taken as the start of a new joint. The lowest empty slot on the
---Link tab, the object picked for it (the next click picks the other one). Joints full: says so
---@param obj FileParserEnvObj
local function startNewJoint(obj)
    local Main, Joints = MGE.Main, MGE.Joints
    local id = Joints.nextId()
    if not id then
        Joints.haveRoom(1) -- prints that the joints are full
        return
    end
    Main.selectJointsOnly({ id })
    Main.setTab("jointLink")
    Main.updateWindow() -- the list's cells and the Link tab show the new slot
    Joints.offerDraft(id, obj.id)
end

---A clicked object: on the Joints list it never switches lists (after Create the Properties tab shows,
---the next object click would throw the joint work away): the Link tab picks it for the current slot's
---draft, Properties starts a new joint with it. On the Objects list the usual click select, from
---Players it switches to Objects with only that object selected
---@param obj FileParserEnvObj
---@param additive boolean
local function clickObject(obj, additive)
    local Main = MGE.Main
    if Main.listTab == "joints" then
        local slot = linkSlot()
        if slot then MGE.Joints.offerDraft(slot, obj.id) else startNewJoint(obj) end
    elseif Main.listTab == "objects" then
        local selected = ModData.clickSelect(obj, additive)
        Main.updateWindow() -- list checkboxes and editor values follow the selection
        if selected then MGE.Camera.followSelection() end -- like selecting in the list
    else
        for _, other in ipairs(ModData.parsed.env_obj) do other.selected = nil end
        obj.selected = true
        Main.setListTab("objects") -- rebuilds the window, camera follow frames the selection
    end
end

---A clicked player: the usual click select on the Players list, from any other list it switches there
---with only that player selected
---@param player integer 0-based
---@param additive boolean
local function clickPlayer(player, additive)
    local Main = MGE.Main
    if Main.listTab == "players" then
        Main.selectPlayer(player, additive) -- Shift + click adds / removes, like objects
        return
    end
    Main.selectedPlayers, Main.selectedPlayer = { [player] = true }, player
    Main.setListTab("players") -- rebuilds the window, camera follow frames the player
end

---A clicked joint anchor: the usual click select on the Joints list, from any other list it switches
---there with only that joint selected (on the Joints tab used last)
---@param joint FileParserEnvObjJoint
---@param additive boolean
local function clickJoint(joint, additive)
    local Main = MGE.Main
    if Main.listTab == "joints" then
        Main.selectJoint(joint.id, additive) -- Shift adds / removes it, like its cell
        Main.updateWindow() -- the list's cells follow (a cell click restyles them itself)
        return
    end
    Main.selectJointsOnly({ joint.id })
    Main.setListTab("joints") -- rebuilds the window, camera follow frames the joint's objects
end

---A Shift + drag box: what's in it is added to the current list's selection
---@param b { x1: number, y1: number, x2: number, y2: number }
local function boxSelect(b)
    local Main = MGE.Main
    if Main.listTab == "objects" then
        local objects = WorldSelect.pickBox(b.x1, b.y1, b.x2, b.y2)
        if not objects[1] then return end
        for _, obj in ipairs(objects) do obj.selected = true end
        Main.updateWindow() -- list checkboxes and editor values follow the selection
        MGE.Camera.followSelection()
    elseif Main.listTab == "players" then
        local players = WorldSelect.pickPlayersBox(b.x1, b.y1, b.x2, b.y2)
        if not players[1] then return end
        for _, player in ipairs(players) do Main.selectedPlayers[player] = true end
        Main.selectedPlayer = players[#players]
        Main.updateWindow()
        MGE.Camera.followPlayer(Main.selectedPlayerList())
    elseif Main.listTab == "joints" and not linkSlot() then -- Link tab: clicks pick objects for a draft
        local last
        for _, joint in ipairs(WorldSelect.pickJointsBox(b.x1, b.y1, b.x2, b.y2)) do
            if not Main.selectedJoints[joint.id] then
                if last then Main.selectedJoints[last] = true end
                last = joint.id
            end
        end
        if not last then return end -- nothing new
        Main.selectJoint(last, true) -- adds the last one as the current slot, drops another slot's draft
        Main.updateWindow() -- the list's cells follow
    end
end

-- the box while Shift + dragging
add_hook("draw2d", HOOK_SET, function()
    local b = pressed
    if not b or not b.box or not b.moved then return end
    local l, t = math.min(b.x, b.endX), math.min(b.y, b.endY)
    local r, btm = math.max(b.x, b.endX), math.max(b.y, b.endY)
    set_color(0.35, 0.65, 1, 0.15)
    draw_quad(l, t, r - l, btm - t)
    set_color(0.35, 0.65, 1, 0.9)
    draw_line(l, t, r, t, 1)
    draw_line(r, t, r, btm, 1)
    draw_line(r, btm, l, btm, 1)
    draw_line(l, btm, l, t, 1)
end)

add_hook("draw3d", HOOK_SET, function()
    local box = pendingBox
    if box then
        pendingBox = nil
        local ok, err = pcall(boxSelect, box)
        if not ok then echo("[MGE] box select error: " .. tostring(err)) end
    end
    local picking = WorldSelect.picking
    if not linkSlot() and not picking then
        pendingHover, WorldSelect.hover = nil, nil
    elseif pendingHover then
        -- only an object a click would pick for the draft: not one behind a joint's anchor or a player.
        -- A pick (color picker) takes objects only, whatever is in front
        local ok, kind, hit
        if picking then
            ok, hit = pcall(WorldSelect.pick, pendingHover.x, pendingHover.y)
            kind = hit and "object"
        else
            ok, kind, hit = pcall(WorldSelect.pickAny, pendingHover.x, pendingHover.y)
        end
        WorldSelect.hover = ok and kind == "object" and hit or nil
        pendingHover = nil
    end
    local click = pendingClick
    if not click then return end
    pendingClick = nil
    if picking then
        WorldSelect.picking, WorldSelect.hover = nil, nil
        local ok, obj = pcall(WorldSelect.pick, click.x, click.y)
        if ok and obj then
            local done, err = pcall(picking.done, obj)
            if not done then echo("^04[MGE] pick error: " .. tostring(err)) end
        else
            echo("^04[MGE] no object there, pick cancelled")
        end
        if picking.ended then picking.ended() end
        return
    end
    -- whatever is under the cursor, whichever list shows: a joint, player or object switches to its list
    local ok, kind, hit = pcall(WorldSelect.pickAny, click.x, click.y)
    if not ok then
        echo("[MGE] world select error: " .. tostring(kind))
    elseif kind == "joint" then
        clickJoint(hit, click.additive)
    elseif kind == "player" then
        clickPlayer(hit, click.additive)
    elseif kind == "object" then
        clickObject(hit, click.additive)
    end
end)

-- MGE.quit removes hooks of MGE.hookname only
table.insert(MGE.onQuit, function()
    WorldSelect.picking = nil -- its ended callback would touch the closing window
    remove_hooks(HOOK_SET)
end)

MGE.WorldSelect = WorldSelect
