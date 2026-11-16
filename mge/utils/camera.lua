













local SHAPE = MGE.SHAPE
local HOOK_SET = MGE.hookname .. "_camera"
local atan2 = math.atan2 or math.atan



local Camera = {
    fitFactor = 2.5,
    margin = 1,




    minDistance = 6,



    maxObjectRadius = 10,
    zoomStep = 1.15,
    zoomMin = 6,
    zoomMax = 200,
    orbitSpeed = 0.008,
    maxPitch = math.rad(85),
    dragThreshold = 4,





    orbitButtons = { [1] = true },

    distance = nil,
    followMoves = true,

    target = nil,
    yaw = 0,
    pitch = 0.0,
}


local drag = nil

local function gizmoBusy()
    return MGE.Gizmo ~= nil and MGE.Gizmo.isDragging()
end




local function objectRadius(id)
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    if shape == SHAPE.SPHERE then return sx end
    if shape == SHAPE.CAPSULE then return sy / 2 + sx end
    return math.sqrt(sx * sx + sy * sy + sz * sz) / 2
end








function Camera.bounds(objects)
    local Transforms = MGE.Transforms
    local positions = {}
    for _, obj in ipairs(objects) do
        if obj.kind == "atmo" then

            local g = MGE.AtmoLayer.ghost(obj)
            if g then
                local s = g.sides
                local r = g.shape == "sphere" and s[1] or g.shape == "cylinder" and s[2] / 2 + s[1]
                    or math.sqrt(s[1] * s[1] + s[2] * s[2] + s[3] * s[3]) / 2
                table.insert(positions, { pos = g.pos, radius = math.min(r, Camera.maxObjectRadius) })
            end
        elseif get_obj_pos(obj.id - 1) ~= nil then
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




function Camera.fitDistance(radius)
    return math.min(math.max(radius * Camera.fitFactor + Camera.margin, Camera.minDistance), Camera.zoomMax)
end




function Camera.viewRay()
    local origin, lookat, lookDistance
    if Camera.distance and Camera.target then
        local t, d, cp = Camera.target, Camera.distance, math.cos(Camera.pitch)
        origin = { t[1] + math.cos(Camera.yaw) * cp * d, t[2] + math.sin(Camera.yaw) * cp * d,
            t[3] + math.sin(Camera.pitch) * d }
        lookat, lookDistance = t, d
    else
        local c = get_camera_info()
        origin, lookat = { c.pos.x, c.pos.y, c.pos.z }, { c.lookat.x, c.lookat.y, c.lookat.z }
    end
    local dir = { lookat[1] - origin[1], lookat[2] - origin[2], lookat[3] - origin[3] }
    local len = math.sqrt(dir[1] ^ 2 + dir[2] ^ 2 + dir[3] ^ 2)
    if len < 1e-6 then return origin, { 0, 1, 0 } end
    return origin, { dir[1] / len, dir[2] / len, dir[3] / len }, lookDistance
end



Camera.GROUND_Z = 0
Camera.GROUND_NEAR = 1

Camera.GROUND_FAR = 1.6
Camera.GROUND_MAX = 25


















function Camera.spawnPoint(bounds, origin, dir, lookDistance)
    if not origin or not dir then origin, dir, lookDistance = Camera.viewRay() end
    local size = {}
    for k = 1, 3 do size[k] = bounds.max[k] - bounds.min[k] end
    if lookDistance then
        local p = {}
        for k = 1, 3 do p[k] = origin[k] + dir[k] * lookDistance end
        return { p[1], p[2], math.max(Camera.GROUND_Z, p[3] - size[3] / 2) }
    end
    local distance = Camera.fitDistance(math.sqrt(size[1] ^ 2 + size[2] ^ 2 + size[3] ^ 2) / 2)
    local groundZ = Camera.GROUND_Z
    if dir[3] < -1e-3 then
        local t = (groundZ - origin[3]) / dir[3]
        if t >= distance * Camera.GROUND_NEAR and t <= math.max(distance * Camera.GROUND_FAR, Camera.GROUND_MAX) then
            return { origin[1] + dir[1] * t, origin[2] + dir[2] * t, groundZ }
        end
    end
    local p = {}
    for k = 1, 3 do p[k] = origin[k] + dir[k] * distance end
    return { p[1], p[2], math.max(groundZ, p[3] - size[3] / 2) }
end





function Camera.spawnShift(bounds, point)
    return {
        point[1] - (bounds.min[1] + bounds.max[1]) / 2,
        point[2] - (bounds.min[2] + bounds.max[2]) / 2,
        point[3] - bounds.min[3],
    }
end





Camera.minHeight =  0






function Camera.minPitch(target, distance)
    if distance <= 1e-6 then return -Camera.maxPitch end
    local s = (Camera.GROUND_Z + Camera.minHeight - target[3]) / distance
    if s <= -1 then return -Camera.maxPitch end
    if s >= 1 then return Camera.maxPitch end
    return math.min(math.max(math.asin(s), -Camera.maxPitch), Camera.maxPitch)
end



local function place()
    local t, d = Camera.target, Camera.distance
    Camera.pitch = math.max(Camera.pitch, Camera.minPitch(t, d))
    local cp = math.cos(Camera.pitch)
    set_camera_lookat(t[1], t[2], t[3])
    set_camera_pos(t[1] + math.cos(Camera.yaw) * cp * d, t[2] + math.sin(Camera.yaw) * cp * d,
        t[3] + math.sin(Camera.pitch) * d)
end



function Camera.isControlling()
    return Camera.distance ~= nil
end


function Camera.release()
    Camera.distance, Camera.target, drag = nil, nil, nil
    remove_hooks(HOOK_SET)
end



local function windowShown()
    local Main = MGE.Main
    if MGE.isPlacing() then return true end
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
        return 1
    end)
    add_hook("mouse_button_down", HOOK_SET, function(button, x, y)
        if button == 4 or button == 5 then


            if overUI(MOUSE_X or x, MOUSE_Y or y) or (MGE.overlayOpen and MGE.overlayOpen()) then return end
            local factor = button == 4 and 1 / Camera.zoomStep or Camera.zoomStep
            Camera.distance = math.min(math.max(Camera.distance * factor, Camera.zoomMin), Camera.zoomMax)
        elseif overUI(x, y) then
            return
        elseif Camera.orbitButtons[button] and not gizmoBusy() then

            drag = { x = x, y = y, dragging = false, button = button }
        end
    end)
    add_hook("mouse_move", HOOK_SET, function(x, y)
        if not drag then return end

        if gizmoBusy() then
            drag = nil
            return
        end
        local dx, dy = x - drag.x, y - drag.y
        if not drag.dragging then
            if math.abs(dx) <= Camera.dragThreshold and math.abs(dy) <= Camera.dragThreshold then return end
            drag.dragging = true
        end
        Camera.yaw = Camera.yaw - dx * Camera.orbitSpeed
        Camera.pitch = math.min(math.max(Camera.pitch + dy * Camera.orbitSpeed, -Camera.maxPitch), Camera.maxPitch)
        drag.x, drag.y = x, y
    end)
    add_hook("mouse_button_up", HOOK_SET, function(button)
        if drag and drag.button == button then drag = nil end
    end)
end



function Camera.focus(objects)
    local center, radius = Camera.bounds(objects)
    if not center then return end
    Camera.focusOn(center, radius)
end






function Camera.focusOn(center, radius)
    local c = get_camera_info()
    if not Camera.isControlling() then

        local dx, dy, dz = c.pos.x - c.lookat.x, c.pos.y - c.lookat.y, c.pos.z - c.lookat.z
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len < 1e-6 then dx, dy, dz, len = 1, -1, 0.6, math.sqrt(2.36) end
        Camera.yaw = atan2(dy, dx)
        Camera.pitch = math.min(math.max(math.asin(dz / len), -Camera.maxPitch), Camera.maxPitch)
        Camera.distance = len
    end

    local distance = math.max(Camera.fitDistance(radius), Camera.distance)

    set_camera_mode(4)
    MGE.cameraChanged = true
    Camera.target = center
    Camera.distance = distance
    takeControl()
    place()
end




function Camera.followSelection()
    if not Camera.followMoves then return end
    local selected = MGE.ModData.getEditSelection()
    if #selected > 0 then Camera.focus(selected) end
end











function Camera.followPlayer(players, after)
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
    if after and after.offset then
        for k = 1, 3 do center[k] = center[k] + after.offset[k] end
    end
    if after and after.factor then
        local pivot = after.pivot or center
        for k = 1, 3 do center[k] = pivot[k] + (center[k] - pivot[k]) * after.factor end
        radius = radius * after.factor
    end

    Camera.focusOn(center, math.min(radius + 0.5, Camera.maxObjectRadius))
end

table.insert(MGE.onQuit, Camera.release)

MGE.Camera = Camera
