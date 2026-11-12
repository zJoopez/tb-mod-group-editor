-- Camera control for MGE: looks at objects from the current viewing direction, far enough away
-- that they fit on screen.
--
-- The game's free orbital camera (mode 4) keeps its own distance, capped at about 13.5, and rebuilds
-- the camera position from it every frame. Tested in game (mge/debug_camera.lua):
--   * set_camera_pos, also every frame from the camera hook, is undone by the game's update
--   * set_camera_range doesn't change the distance
--   * returning 1 from the camera hook skips the game's camera update: the position holds, but the
--     game's own orbiting stops too
-- So while MGE controls the camera it owns it completely: the camera hook places it every frame and
-- returns 1, and MGE handles orbiting (left mouse drag) and zoom (mouse wheel) itself. Control
-- goes back to the game when the MGE window is hidden, the camera mode changes or MGE quits.
-- A left press on a gizmo handle drags the gizmo instead (utils/gizmo.lua), the camera stays put.

local SHAPE = MGE.SHAPE
local HOOK_SET = MGE.hookname .. "_camera"
local atan2 = math.atan2 or math.atan -- the game's Lua has atan2, newer Lua takes two arguments in atan

---@class Camera
---@field followMoves boolean
local Camera = {
    fitFactor = 2.5,     -- camera distance per unit of selection radius (covers the game's field of view)
    margin = 1,          -- extra distance so objects don't touch the screen edges
    minDistance = 2.5,   -- closest framing distance
    -- largest radius an object counts with when framing. Many mods use a huge object as the ground,
    -- framing all of it put the camera thousands of units away. Bigger objects are framed like one this
    -- size at their center, so a selection with a ground object still shows the other objects
    maxObjectRadius = 10,
    zoomStep = 1.15,     -- distance factor per mouse wheel step
    zoomMin = 1,
    zoomMax = 200,       -- also the furthest framing distance (objects spread very far apart)
    orbitSpeed = 0.008,  -- radians per dragged pixel
    maxPitch = math.rad(85),
    dragThreshold = 4,   -- pixels before a press turns into an orbit drag (shorter left clicks select objects)
    -- mouse buttons that orbit when dragged. Only the left button's presses reach Lua: for right and
    -- middle the game only passes the release on (mge/debug_mouse.lua, tested in game), so their drags
    -- can't be seen. Using the game's own right drag orbit doesn't work either, the camera hook has to
    -- skip the game's camera update (see above), which stops its orbit. A left press on a gizmo handle
    -- drags the gizmo, anywhere else it orbits (or selects, when it's a click)
    orbitButtons = { [1] = true },
    ---@type number? distance MGE keeps the camera at, nil when the game controls the camera
    distance = nil,
    followMoves = true,  -- selecting and moving point the camera at the selection (Camera button in the top menu)
    ---@type number[]? look-at point
    target = nil,
    yaw = 0,             -- direction from the target to the camera
    pitch = 0.0,         -- radians, kept above the floor (Camera.minPitch)
}

---@type { x: number, y: number, dragging: boolean, button: integer }?
local drag = nil

local function gizmoBusy()
    return MGE.Gizmo ~= nil and MGE.Gizmo.isDragging()
end

---Distance from an object's center to its furthest point
---@param id integer 0-based object id
---@return number
local function objectRadius(id)
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    if shape == SHAPE.SPHERE then return sx end                 -- x radius
    if shape == SHAPE.CAPSULE then return sy / 2 + sx end       -- half length + radius
    return math.sqrt(sx * sx + sy * sy + sz * sz) / 2           -- box: half diagonal
end

---Center and radius of a sphere around the objects, each object counting with at most
---Camera.maxObjectRadius (huge ground objects). The center is the selection pivot the gizmo, Rotate,
---Resize and the Pos row use (Transforms.getSelectionPivot: average of the file positions), so the
---gizmo sits in the middle of the screen. The middle of the objects' box was used before: for an uneven
---selection (Select All) it's somewhere else and the gizmo ended up off center
---@param objects FileParserEnvObj[]
---@return number[]? center, number radius
function Camera.bounds(objects)
    local Transforms = MGE.Transforms
    local positions = {}
    for _, obj in ipairs(objects) do
        if get_obj_pos(obj.id - 1) ~= nil then -- in the world, position as the file has it (like the pivot)
            local radius = math.min(objectRadius(obj.id - 1), Camera.maxObjectRadius)
            table.insert(positions, { pos = Transforms.positionOf(obj), radius = radius })
        end
    end
    if #positions == 0 then return nil, 0 end
    local cx, cy, cz = Transforms.getSelectionPivot(objects)
    local center = { cx, cy, cz }
    local radius = 0
    for _, entry in ipairs(positions) do
        local d = math.sqrt((entry.pos[1] - center[1]) ^ 2 + (entry.pos[2] - center[2]) ^ 2 + (entry.pos[3] - center[3]) ^ 2)
        radius = math.max(radius, d + entry.radius)
    end
    return center, radius
end

---Camera distance that fits a sphere of this radius on screen, the same framing Camera.focus uses
---@param radius number
---@return number
function Camera.fitDistance(radius)
    return math.min(math.max(radius * Camera.fitFactor + Camera.margin, Camera.minDistance), Camera.zoomMax)
end

---Where the camera is and the unit direction it looks in, MGE's own camera or the game's
---@return number[] origin, number[] dir
function Camera.viewRay()
    local origin, lookat
    if Camera.distance and Camera.target then
        local t, d, cp = Camera.target, Camera.distance, math.cos(Camera.pitch)
        origin = { t[1] + math.cos(Camera.yaw) * cp * d, t[2] + math.sin(Camera.yaw) * cp * d,
            t[3] + math.sin(Camera.pitch) * d }
        lookat = t
    else
        local c = get_camera_info()
        origin, lookat = { c.pos.x, c.pos.y, c.pos.z }, { c.lookat.x, c.lookat.y, c.lookat.z }
    end
    local dir = { lookat[1] - origin[1], lookat[2] - origin[2], lookat[3] - origin[3] }
    local len = math.sqrt(dir[1] ^ 2 + dir[2] ^ 2 + dir[3] ^ 2)
    if len < 1e-6 then return origin, { 0, 1, 0 } end
    return origin, { dir[1] / len, dir[2] / len, dir[3] / len }
end

-- Spawning in view (Generate tab, imports, New): new things go on screen, about as far from the camera
-- as framing them would put it, not at the dojo center
Camera.GROUND_Z = 0          -- the floor, things are put on it when the view meets it close enough
Camera.GROUND_NEAR = 0.6     -- the view meeting the floor between these shares of the framing distance
Camera.GROUND_FAR = 1.6      -- counts as close enough,
Camera.GROUND_MAX = 25       -- and so does any distance up to this: small things frame close, but on the
                             -- floor a usual editing view away they're still easy to see

---@class SpawnBounds box around what is spawned, world axes, any position
---@field min number[]
---@field max number[]

---Where something goes in front of the camera: on the floor where the view line meets it, when that's
---about the distance that fits it on screen (or within GROUND_MAX), otherwise centered on the view line
---at that distance (not below the floor)
---@param bounds SpawnBounds
---@param origin number[]? view line to use (Generate keeps one), defaults to Camera.viewRay()
---@param dir number[]? unit direction of that line
---@return number[] point x y: the center goes there, z: the lowest point
function Camera.spawnPoint(bounds, origin, dir)
    if not origin or not dir then origin, dir = Camera.viewRay() end
    local size = {}
    for k = 1, 3 do size[k] = bounds.max[k] - bounds.min[k] end
    local distance = Camera.fitDistance(math.sqrt(size[1] ^ 2 + size[2] ^ 2 + size[3] ^ 2) / 2)
    local groundZ = Camera.GROUND_Z
    if dir[3] < -1e-3 then -- looking down: where the view meets the floor
        local t = (groundZ - origin[3]) / dir[3]
        if t >= distance * Camera.GROUND_NEAR and t <= math.max(distance * Camera.GROUND_FAR, Camera.GROUND_MAX) then
            return { origin[1] + dir[1] * t, origin[2] + dir[2] * t, groundZ }
        end
    end
    local p = {}
    for k = 1, 3 do p[k] = origin[k] + dir[k] * distance end
    return { p[1], p[2], math.max(groundZ, p[3] - size[3] / 2) }
end

---Offset that moves bounds so their center (x y) and lowest point (z) are at point
---@param bounds SpawnBounds
---@param point number[] from Camera.spawnPoint
---@return number[]
function Camera.spawnShift(bounds, point)
    return {
        point[1] - (bounds.min[1] + bounds.max[1]) / 2,
        point[2] - (bounds.min[2] + bounds.max[2]) / 2,
        point[3] - bounds.min[3],
    }
end

-- The game won't put the camera under the floor: a camera MGE places below it is pushed back up, right
-- next to the target, and the gizmo (sized from the camera distance, drawn from the camera's real
-- position) collapses to nothing. So the orbit stops this far above the floor (0.3 worked but stopped
-- the view noticeably early)
Camera.minHeight =  0

---Lowest pitch that keeps a camera at `distance` from `target` at least minHeight above the floor.
---Looking up from below is still possible while the target is high enough
---@param target number[]
---@param distance number
---@return number pitch radians (from -maxPitch to maxPitch)
function Camera.minPitch(target, distance)
    if distance <= 1e-6 then return -Camera.maxPitch end
    local s = (Camera.GROUND_Z + Camera.minHeight - target[3]) / distance -- sin(pitch) at the floor
    if s <= -1 then return -Camera.maxPitch end
    if s >= 1 then return Camera.maxPitch end -- target far underground: as high as the camera goes
    return math.min(math.max(math.asin(s), -Camera.maxPitch), Camera.maxPitch)
end

---Places the camera from target, yaw, pitch and distance, kept above the floor (Camera.minPitch). The
---pitch itself is raised, so a drag further down doesn't build up and the drag back up answers at once
local function place()
    local t, d = Camera.target, Camera.distance
    Camera.pitch = math.max(Camera.pitch, Camera.minPitch(t, d))
    local cp = math.cos(Camera.pitch)
    set_camera_lookat(t[1], t[2], t[3])
    set_camera_pos(t[1] + math.cos(Camera.yaw) * cp * d, t[2] + math.sin(Camera.yaw) * cp * d,
        t[3] + math.sin(Camera.pitch) * d)
end

---True while MGE owns the camera
---@return boolean
function Camera.isControlling()
    return Camera.distance ~= nil
end

---Gives the camera back to the game (its orbital camera continues from its own distance)
function Camera.release()
    Camera.distance, Camera.target, drag = nil, nil, nil
    remove_hooks(HOOK_SET)
end

---MGE's camera works while the window is shown, or while the map placement view has it hidden
---(ui/map_place.lua: orbit and zoom keep working there)
local function windowShown()
    local Main = MGE.Main
    if MGE.MapPlace and MGE.MapPlace.active then return true end
    return Main and Main.window and Main.window.displayed
end

local function overUI(x, y)
    return MGE.Widgets and MGE.Widgets.isMouseOverUI(x, y)
end

local function takeControl()
    remove_hooks(HOOK_SET)
    add_hook("camera", HOOK_SET, function()
        if not Camera.distance or get_camera_mode() ~= 4 or not windowShown() then
            Camera.release()
            return
        end
        place()
        return 1 -- skip the game's camera update, it would put the camera back at its own distance
    end)
    add_hook("mouse_button_down", HOOK_SET, function(button, x, y)
        if button == 4 or button == 5 then -- wheel: 4 up = closer
            -- the wheel's x, y aren't the cursor: check toriui's tracked cursor (MOUSE_X / Y), so scrolling
            -- a list (ours or the game's) doesn't zoom. No zoom under an overlay either (Mods, file picker)
            if overUI(MOUSE_X or x, MOUSE_Y or y) or (MGE.overlayOpen and MGE.overlayOpen()) then return end
            local factor = button == 4 and 1 / Camera.zoomStep or Camera.zoomStep
            Camera.distance = math.min(math.max(Camera.distance * factor, Camera.zoomMin), Camera.zoomMax)
        elseif overUI(x, y) then
            return
        elseif Camera.orbitButtons[button] and not gizmoBusy() then
            -- dragging orbits, a short left click still selects (world_select.lua)
            drag = { x = x, y = y, dragging = false, button = button }
        end
    end)
    add_hook("mouse_move", HOOK_SET, function(x, y)
        if not drag then return end
        -- the press grabbed a gizmo handle (its hook may run after this one): the gizmo gets the drag
        if gizmoBusy() then
            drag = nil
            return
        end
        local dx, dy = x - drag.x, y - drag.y
        if not drag.dragging then
            if math.abs(dx) <= Camera.dragThreshold and math.abs(dy) <= Camera.dragThreshold then return end
            drag.dragging = true -- from here on it's an orbit, not a click
        end
        Camera.yaw = Camera.yaw - dx * Camera.orbitSpeed
        Camera.pitch = math.min(math.max(Camera.pitch + dy * Camera.orbitSpeed, -Camera.maxPitch), Camera.maxPitch)
        drag.x, drag.y = x, y
    end)
    add_hook("mouse_button_up", HOOK_SET, function(button)
        if drag and drag.button == button then drag = nil end
    end)
end

---Points the camera at the objects from the current viewing direction
---@param objects FileParserEnvObj[]
---@param keepDistance boolean? keep the current distance when it's already far enough (used while editing)
function Camera.focus(objects, keepDistance)
    local center, radius = Camera.bounds(objects)
    if not center then return end
    Camera.focusOn(center, radius, keepDistance)
end

---Points MGE's camera at a sphere from the current viewing direction, far enough that it fits
---@param center number[]
---@param radius number
---@param keepDistance boolean? see Camera.focus
function Camera.focusOn(center, radius, keepDistance)
    local c = get_camera_info()
    if not Camera.isControlling() then
        -- start from the game's current view direction
        local dx, dy, dz = c.pos.x - c.lookat.x, c.pos.y - c.lookat.y, c.pos.z - c.lookat.z
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len < 1e-6 then dx, dy, dz, len = 1, -1, 0.6, math.sqrt(2.36) end
        Camera.yaw = atan2(dy, dx)
        Camera.pitch = math.min(math.max(math.asin(dz / len), -Camera.maxPitch), Camera.maxPitch)
        Camera.distance = len
    end

    local distance = Camera.fitDistance(radius)
    if keepDistance then distance = math.max(distance, Camera.distance) end

    set_camera_mode(4)
    MGE.cameraChanged = true -- reset on quit
    Camera.target = center
    Camera.distance = distance
    takeControl()
    place()
end

---After a select (object list, click in the world, Select All / Ctrl + A): looks at the whole
---selection when the Camera button is on, so it and its gizmo are in view. Call it only when something
---got selected, deselecting leaves the camera where it is
function Camera.followSelection()
    if not Camera.followMoves then return end
    local selected = MGE.ModData.getSelected()
    if #selected > 0 then Camera.focus(selected) end
end

---Players list (picking players, opening the list): frames the selected players like a selection when
---camera follow is on, around their shared center (where the gizmo is). MGE's own camera for every
---player, so orbit and zoom work the same as for objects (the game's tori / uke cameras would take
---those away and only exist for two players)
---@param players integer|integer[] 0-based
function Camera.followPlayer(players)
    if not Camera.followMoves then return end
    local Players = MGE.Players
    if not Players then return end
    local list = {}
    for _, player in ipairs(type(players) == "table" and players or { players }) do
        if Players.exists(player) then table.insert(list, player) end
    end
    if #list == 0 then return end
    local center, radius = Players.groupCenter(list), 0
    for _, player in ipairs(list) do
        for _, id in pairs(BODYPARTS) do
            local p = get_body_info(player, id).pos
            radius = math.max(radius, math.sqrt((p.x - center[1]) ^ 2 + (p.y - center[2]) ^ 2 + (p.z - center[3]) ^ 2))
        end
    end
    Camera.focusOn(center, math.min(radius + 0.5, Camera.maxObjectRadius))
end

table.insert(MGE.onQuit, Camera.release)

MGE.Camera = Camera
