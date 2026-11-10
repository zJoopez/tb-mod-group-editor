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
    zoomMin = 0.5,
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
    pitch = 0,
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
---Camera.maxObjectRadius (huge ground objects)
---@param objects FileParserEnvObj[]
---@return number[]? center, number radius
function Camera.bounds(objects)
    local positions = {}
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, obj in ipairs(objects) do
        local x, y, z = get_obj_pos(obj.id - 1)
        if x then
            local p = { x, y, z }
            local radius = math.min(objectRadius(obj.id - 1), Camera.maxObjectRadius)
            table.insert(positions, { pos = p, radius = radius })
            for i = 1, 3 do
                if p[i] < min[i] then min[i] = p[i] end
                if p[i] > max[i] then max[i] = p[i] end
            end
        end
    end
    if #positions == 0 then return nil, 0 end
    local center = { (min[1] + max[1]) / 2, (min[2] + max[2]) / 2, (min[3] + max[3]) / 2 }
    local radius = 0
    for _, entry in ipairs(positions) do
        local d = math.sqrt((entry.pos[1] - center[1]) ^ 2 + (entry.pos[2] - center[2]) ^ 2 + (entry.pos[3] - center[3]) ^ 2)
        radius = math.max(radius, d + entry.radius)
    end
    return center, radius
end

---Places the camera from target, yaw, pitch and distance
local function place()
    local t, d = Camera.target, Camera.distance
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

local function windowShown()
    local Main = MGE.Main
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
        if overUI(x, y) then return end
        if button == 4 or button == 5 then -- wheel: 4 up = closer
            local factor = button == 4 and 1 / Camera.zoomStep or Camera.zoomStep
            Camera.distance = math.min(math.max(Camera.distance * factor, Camera.zoomMin), Camera.zoomMax)
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

    local distance = math.max(radius * Camera.fitFactor + Camera.margin, Camera.minDistance)
    distance = math.min(distance, Camera.zoomMax)
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

table.insert(MGE.onQuit, Camera.release)

MGE.Camera = Camera
