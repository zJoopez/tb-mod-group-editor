



























require("toriui.uielement3d")

local ModData = MGE.ModData
local SHAPE = MGE.SHAPE
local HOOK_SET = MGE.hookname .. "_worldselect"


local WorldSelect = {
    clickMoveLimit = 4,
    clicksOff = false,
    boxGridStep = 12,
    boxGridMax = 40,
}



local pressed = nil

local pendingBox = nil

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
















local MEASURE_SHARES = { 0.25, 0.05 }



local function screenAt(target, dir, e)
    local x, y, z = get_screen_pos(target[1] + dir[1] * e, target[2] + dir[2] * e, target[3] + dir[3] * e)
    if x == nil or z ~= 0 then return nil end
    return x, y
end






local frameProjection = nil
local frameMeasured = nil





function WorldSelect.measureProjection()
    local frame = UIElement and UIElement.frameIndex
    if frame and frame == frameMeasured then return frameProjection end
    frameProjection, frameMeasured = WorldSelect.measureProjectionNow(), frame
    return frameProjection
end



function WorldSelect.measureProjectionNow()
    local info = get_camera_info()
    local eye = { info.pos.x, info.pos.y, info.pos.z }
    local target = { info.lookat.x, info.lookat.y, info.lookat.z }
    local toTarget = sub(target, eye)
    local dist = length(toTarget)
    local forward = normalize(toTarget)
    if not forward then return nil end
    local right = normalize(cross(forward, { 0, 0, 1 })) or { 1, 0, 0 }
    local up = cross(right, forward)







    for _, share in ipairs(MEASURE_SHARES) do
        local e = dist * share
        local rx1, ry1 = screenAt(target, right, e)
        local rx2, ry2 = screenAt(target, right, -e)
        local ux1, uy1 = screenAt(target, up, e)
        local ux2, uy2 = screenAt(target, up, -e)
        if rx1 and rx2 and ux1 and ux2 then
            local k = dist / (2 * e)
            local m11, m21 = (rx1 - rx2) * k, (ry1 - ry2) * k
            local m12, m22 = (ux1 - ux2) * k, (uy1 - uy2) * k
            local det = m11 * m22 - m12 * m21
            if math.abs(det) < 1e-9 then return nil end

            local cx = (rx1 + rx2 + ux1 + ux2) / 4
            local cy = (ry1 + ry2 + uy1 + uy2) / 4
            return { eye = eye, forward = forward, right = right, up = up, cx = cx, cy = cy,
                m11 = m11, m12 = m12, m21 = m21, m22 = m22, det = det }
        end
    end
    return nil
end






function WorldSelect.rayFrom(p, x, y)
    local ox, oy = x - p.cx, y - p.cy
    local a = (ox * p.m22 - p.m12 * oy) / p.det
    local b = (p.m11 * oy - p.m21 * ox) / p.det
    return p.eye, normalize(add(p.forward, add(scale(p.right, a), scale(p.up, b))))
end






function WorldSelect.project(p, point)
    local rel = sub(point, p.eye)
    local depth = dot(rel, p.forward)
    if depth < 1e-6 then return nil end
    local a, b = dot(rel, p.right) / depth, dot(rel, p.up) / depth
    return p.cx + p.m11 * a + p.m12 * b, p.cy + p.m21 * a + p.m22 * b
end





function WorldSelect.cameraRay(x, y)
    local p = WorldSelect.measureProjection()
    if not p then return nil end
    return WorldSelect.rayFrom(p, x, y)
end





local function getLocalAxes(id)
    local raw = get_obj_rot(id)
    if type(raw) ~= "table" then return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } end
    local m = Utils3D.MatrixToMatrixTB(raw)
    return { { m.r0, m.r4, m.r8 }, { m.r1, m.r5, m.r9 }, { m.r2, m.r6, m.r10 } }
end


local function hitSphere(origin, dir, center, radius)
    local oc = sub(origin, center)
    local b = dot(oc, dir)
    local c = dot(oc, oc) - radius * radius
    local h = b * b - c
    if h < 0 then return nil end
    local t = -b - math.sqrt(h)
    return t >= 0 and t or nil
end


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
    return tmin >= 0 and tmin or nil
end


local function hitCapsule(origin, dir, a, b, radius)
    local ba, oa = sub(b, a), sub(origin, a)
    local baba, bard, baoa = dot(ba, ba), dot(ba, dir), dot(ba, oa)
    local rdoa, oaoa = dot(dir, oa), dot(oa, oa)
    local qa = baba - bard * bard
    local best
    if qa > 1e-12 then
        local qb = baba * rdoa - baoa * bard
        local qc = baba * oaoa - baoa * baoa - radius * radius * baba
        local h = qb * qb - qa * qc
        if h >= 0 then
            local t = (-qb - math.sqrt(h)) / qa
            local along = baoa + t * bard
            if t >= 0 and along > 0 and along < baba then best = t end
        end
    end
    for _, capCenter in ipairs({ a, b }) do
        local t = hitSphere(origin, dir, capCenter, radius)
        if t and (not best or t < best) then best = t end
    end
    return best
end


WorldSelect.hitSphere, WorldSelect.hitBox, WorldSelect.hitCapsule = hitSphere, hitBox, hitCapsule









local function objectShape(id)
    local x, y, z = get_obj_pos(id)
    if x == nil then return nil end
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    local center = { x, y, z }
    if shape == SHAPE.SPHERE then
        return { center = center, radius = sx, hit = function(o, d) return hitSphere(o, d, center, sx) end }
    end
    local axes = getLocalAxes(id)
    if shape == SHAPE.CAPSULE then
        local halfAxis = scale(axes[3], sy / 2)
        local a, b = sub(center, halfAxis), add(center, halfAxis)
        return { center = center, radius = sy / 2 + sx, hit = function(o, d) return hitCapsule(o, d, a, b, sx) end }
    end
    local half = { sx / 2, sy / 2, sz / 2 }
    return { center = center, radius = length(half), hit = function(o, d) return hitBox(o, d, center, axes, half) end }
end





local function ghostShape(obj)
    local g = MGE.AtmoLayer.ghost(obj)
    if not g then return nil end
    local f, s = g.frame, g.sides
    local center = { g.pos[1], g.pos[2], g.pos[3] }
    local axes = { { f[1][1], f[2][1], f[3][1] }, { f[1][2], f[2][2], f[3][2] }, { f[1][3], f[2][3], f[3][3] } }
    local shape
    if g.shape == "sphere" then
        shape = { center = center, radius = s[1], hit = function(o, d) return hitSphere(o, d, center, s[1]) end }
    elseif g.shape == "cylinder" then
        local halfAxis = scale(axes[3], s[2] / 2)
        local a, b = sub(center, halfAxis), add(center, halfAxis)
        shape = { center = center, radius = s[2] / 2 + s[1], hit = function(o, d) return hitCapsule(o, d, a, b, s[1]) end }
    else
        local half = { s[1] / 2, s[2] / 2, s[3] / 2 }
        shape = { center = center, radius = length(half), hit = function(o, d) return hitBox(o, d, center, axes, half) end }
    end
    shape.obj = obj
    return shape
end




local function atmoListed()
    local tab = MGE.Main and MGE.Main.listTab
    return tab == "objects" or tab == "atmo"
end







function WorldSelect.pickAtmo(x, y)
    local origin, dir = WorldSelect.cameraRay(x, y)
    if not origin or not dir then return nil end
    local best, bestT = nil, math.huge
    local AtmoLayer = MGE.AtmoLayer
    for _, obj in ipairs(ModData.parsed.atmo or {}) do


        local g = AtmoLayer.ghost(obj)
        if g then
            local ox, oy, oz = origin[1] - g.pos[1], origin[2] - g.pos[2], origin[3] - g.pos[3]
            local c = ox * ox + oy * oy + oz * oz - g.radius * g.radius
            local b = ox * dir[1] + oy * dir[2] + oz * dir[3]
            if c <= 0 or (b < 0 and b * b >= c) then
                local shape = ghostShape(obj)
                local t = shape and shape.hit(origin, dir)
                if t and t < bestT then best, bestT = obj, t end
            end
        end
    end
    return best, best and bestT
end


local function nearSphere(origin, dir, center, radius)
    local ox, oy, oz = origin[1] - center[1], origin[2] - center[2], origin[3] - center[3]
    local c = ox * ox + oy * oy + oz * oz - radius * radius
    if c <= 0 then return true end
    local b = ox * dir[1] + oy * dir[2] + oz * dir[3]
    return b < 0 and b * b >= c
end




function WorldSelect.hitObject(origin, dir, id)
    local s = objectShape(id)
    return s and s.hit(origin, dir)
end






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



local BODY_SPHERE, BODY_CYLINDER = 0, 2





local function hitBody(origin, dir, player, id)
    local b = get_body_info(player, id)
    local center, s, r = { b.pos.x, b.pos.y, b.pos.z }, b.sides, b.rot
    if b.shape == BODY_SPHERE then return hitSphere(origin, dir, center, s.x) end
    local axes = { { r.r0, r.r4, r.r8 }, { r.r1, r.r5, r.r9 }, { r.r2, r.r6, r.r10 } }
    if b.shape == BODY_CYLINDER then
        local halfAxis = scale(axes[3], s.y / 2)
        return hitCapsule(origin, dir, sub(center, halfAxis), add(center, halfAxis), s.x)
    end
    return hitBox(origin, dir, center, axes, { s.x / 2, s.y / 2, s.z / 2 })
end







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










function WorldSelect.pickAny(x, y)
    local joint = WorldSelect.pickJoint(x, y, MGE.Main.listTab ~= "joints")
    if joint then return "joint", joint end
    local obj, objT = WorldSelect.pick(x, y)
    if atmoListed() then
        local ghost, ghostT = WorldSelect.pickAtmo(x, y)
        if ghost and (not obj or ghostT < objT) then obj, objT = ghost, ghostT end
    end
    local player, playerT = WorldSelect.pickPlayer(x, y)
    if player and (not obj or playerT < objT) then return "player", player end
    if obj then return "object", obj end
    return nil
end




local function projectsInto(p, point, box)
    local x, y = WorldSelect.project(p, point)
    return x ~= nil and x >= box.left and x <= box.right and y >= box.top and y <= box.bottom, x, y
end


local function boxOf(x1, y1, x2, y2)
    return { left = math.min(x1, x2), top = math.min(y1, y2), right = math.max(x1, x2), bottom = math.max(y1, y2) }
end







local function screenExtent(p, center, radius)
    local rel = sub(center, p.eye)
    local depth = dot(rel, p.forward)
    if depth < -radius then return nil end
    if depth <= radius then return -math.huge, -math.huge, math.huge, math.huge end
    local x, y = WorldSelect.project(p, center)
    if not x then return -math.huge, -math.huge, math.huge, math.huge end
    local sr = radius / depth * math.sqrt(p.m11 * p.m11 + p.m21 * p.m21) * 1.5 + 4
    return x - sr, y - sr, x + sr, y + sr
end



local BOX_CELL = 24






function WorldSelect.pickBox(x1, y1, x2, y2)
    local p = WorldSelect.measureProjection()
    if not p then return {} end
    local box = boxOf(x1, y1, x2, y2)





    local cellCols = math.max(1, math.ceil((box.right - box.left) / BOX_CELL))
    local cellRows = math.max(1, math.ceil((box.bottom - box.top) / BOX_CELL))
    local cells = {}
    local shapes = {}
    local function addShape(shape, l, t, r, b)
        if r < box.left or l > box.right or b < box.top or t > box.bottom then return end
        shapes[#shapes + 1] = shape
        local c0 = math.max(0, math.floor((l - box.left) / BOX_CELL))
        local c1 = math.min(cellCols - 1, math.floor((r - box.left) / BOX_CELL))
        local r0 = math.max(0, math.floor((t - box.top) / BOX_CELL))
        local r1 = math.min(cellRows - 1, math.floor((b - box.top) / BOX_CELL))
        for c = c0, c1 do
            for rr = r0, r1 do
                local key = rr * cellCols + c
                local list = cells[key]
                if not list then list = {}; cells[key] = list end
                list[#list + 1] = shape
            end
        end
    end
    for _, obj in ipairs(ModData.parsed.env_obj) do
        local sh = objectShape(obj.id - 1)
        if sh then
            local l, t, r, b = screenExtent(p, sh.center, sh.radius)
            if l then
                sh.obj = obj
                addShape(sh, l, t, r, b)
            end
        end
    end
    if atmoListed() then
        local AtmoLayer = MGE.AtmoLayer
        for _, obj in ipairs(ModData.parsed.atmo or {}) do
            local g = AtmoLayer.ghost(obj)
            if g then
                local l, t, r, b = screenExtent(p, g.pos, g.radius)
                if l and not (r < box.left or l > box.right or b < box.top or t > box.bottom) then
                    addShape(ghostShape(obj), l, t, r, b)
                end
            end
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
        local c = math.min(cellCols - 1, math.max(0, math.floor((pt[1] - box.left) / BOX_CELL)))
        local rr = math.min(cellRows - 1, math.max(0, math.floor((pt[2] - box.top) / BOX_CELL)))
        local inCell = cells[rr * cellCols + c]
        if dir and inCell then
            local best, bestT = nil, math.huge
            for _, s in ipairs(inCell) do
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





function WorldSelect.pickBoxThrough(x1, y1, x2, y2)
    local p = WorldSelect.measureProjection()
    if not p then return {} end
    local box = boxOf(x1, y1, x2, y2)
    local list = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        local x, y, z = get_obj_pos(obj.id - 1)
        if x and projectsInto(p, { x, y, z }, box) then list[#list + 1] = obj end
    end
    if atmoListed() then
        local AtmoLayer = MGE.AtmoLayer
        for _, obj in ipairs(ModData.parsed.atmo or {}) do
            local g = AtmoLayer.ghost(obj)
            if g and projectsInto(p, g.pos, box) then list[#list + 1] = obj end
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end



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
    return MGE.Widgets.isMouseOverUI(x, y)
end

local function isActive()
    local Main = MGE.Main

    return Main and Main.window and (Main.window.displayed or WorldSelect.clicksOff) and not TB_MENU_INPUT_ISACTIVE
end




add_hook("mouse_button_down", HOOK_SET, function(button, x, y)
    local Gizmo = MGE.Gizmo
    if Gizmo and Gizmo.isDragging() then return 1 end
    pressed = nil
    if button ~= 1 or not isActive() or isOverUI(x, y) then return end
    if Gizmo and Gizmo.press(x, y) then return 1 end
    if WorldSelect.clicksOff then return end

    if get_keyboard_shift() ~= 0 and not WorldSelect.picking then

        pressed = { x = x, y = y, box = true, endX = x, endY = y, through = get_keyboard_ctrl() ~= 0 }
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
        pendingBox = { x1 = start.x, y1 = start.y, x2 = x, y2 = y, through = start.through or get_keyboard_ctrl() ~= 0 }
        return 1
    end
    local limit = WorldSelect.clickMoveLimit
    if math.abs(x - start.x) > limit or math.abs(y - start.y) > limit then return end
    pendingClick = { x = x, y = y, additive = start.box or get_keyboard_shift() ~= 0 }
    if start.box then return 1 end
end)


local pendingHover = nil

WorldSelect.hover = nil


local function linkSlot()
    local Main = MGE.Main
    return Main and Main.linkSlot and Main.linkSlot() or nil
end



local function linkPick()
    local slot = linkSlot()
    return slot and MGE.Joints and MGE.Joints.worldPick and slot or nil
end




WorldSelect.picking = nil




function WorldSelect.startPick(done, ended)
    WorldSelect.cancelPick()
    WorldSelect.picking = { done = done, ended = ended }
end



function WorldSelect.cancelPick()
    local p = WorldSelect.picking
    WorldSelect.picking, WorldSelect.hover = nil, nil
    if p and p.ended then p.ended() end
    return p ~= nil
end



add_hook("mouse_move", HOOK_SET, function(x, y)
    local box = pressed and pressed.box and pressed
    if box then
        box.endX, box.endY = x, y
        local limit = WorldSelect.clickMoveLimit
        if math.abs(x - box.x) > limit or math.abs(y - box.y) > limit then box.moved = true end
    end
    if not linkPick() and not WorldSelect.picking then return end
    if not isActive() or isOverUI(x, y) then
        pendingHover, WorldSelect.hover = nil, nil
        return
    end
    pendingHover = { x = x, y = y }
end)







local function clickObject(obj, additive)
    local Main = MGE.Main
    if obj.kind == "atmo" then


        if Main.listTab == "atmo" then
            local selected = ModData.clickSelect(obj, additive)
            Main.updateWindow()
            if selected then Main.selectionMade() end
        else
            for _, other in ipairs(ModData.parsed.atmo) do other.selected = nil end
            obj.selected = true
            Main.leaveGenerate("atmo")
            Main.setListTab("atmo")
        end
        return
    end
    local slot = linkPick()
    if slot then
        MGE.Joints.offerDraft(slot, obj.id)
    elseif Main.listTab == "objects" then
        local selected = ModData.clickSelect(obj, additive)
        Main.updateWindow()
        if selected then Main.selectionMade() end
    else
        for _, other in ipairs(ModData.parsed.env_obj) do other.selected = nil end
        obj.selected = true
        Main.leaveGenerate("objects")
        Main.setListTab("objects")
    end
end





local function clickPlayer(player, additive)
    local Main = MGE.Main
    if Main.listTab == "players" then
        Main.selectPlayer(player, additive)
        return
    end
    Main.selectedPlayers, Main.selectedPlayer = { [player] = true }, player
    Main.setListTab("players")
end





local function clickJoint(joint, additive)
    local Main = MGE.Main
    if Main.listTab == "joints" then
        Main.selectJoint(joint.id, additive)
        Main.updateWindow()
        return
    end
    Main.selectJointsOnly({ joint.id })
    Main.setListTab("joints")
end




local function boxSelect(b)
    local Main = MGE.Main
    if Main.listTab == "objects" or Main.listTab == "atmo" then

        local atmo, any = Main.listTab == "atmo", false
        local pick = b.through and WorldSelect.pickBoxThrough or WorldSelect.pickBox
        for _, obj in ipairs(pick(b.x1, b.y1, b.x2, b.y2)) do
            if (obj.kind == "atmo") == atmo then
                obj.selected, any = true, true
            end
        end
        if not any then return end
        Main.updateWindow()
        Main.selectionMade()
    elseif Main.listTab == "players" then
        local players = WorldSelect.pickPlayersBox(b.x1, b.y1, b.x2, b.y2)
        if not players[1] then return end
        for _, player in ipairs(players) do Main.selectedPlayers[player] = true end
        Main.selectedPlayer = players[#players]
        Main.updateWindow()
        MGE.Camera.followPlayer(Main.selectedPlayerList())
    elseif Main.listTab == "joints" and not linkPick() then
        local last
        for _, joint in ipairs(WorldSelect.pickJointsBox(b.x1, b.y1, b.x2, b.y2)) do
            if not Main.selectedJoints[joint.id] then
                if last then Main.selectedJoints[last] = true end
                last = joint.id
            end
        end
        if not last then return end
        Main.selectJoint(last, true)
        Main.updateWindow()
    end
end


add_hook("draw2d", HOOK_SET, function()
    local b = pressed
    if not b or not b.box or not b.moved then return end
    local l, t = math.min(b.x, b.endX), math.min(b.y, b.endY)
    local r, btm = math.max(b.x, b.endX), math.max(b.y, b.endY)

    local through = b.through or get_keyboard_ctrl() ~= 0
    local c = through and { 1, 0.6, 0.2 } or { 0.35, 0.65, 1 }
    set_color(c[1], c[2], c[3], 0.15)
    draw_quad(l, t, r - l, btm - t)
    set_color(c[1], c[2], c[3], 0.9)
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
        if not ok then MGE.say("box select error: " .. tostring(err)) end
    end
    local picking = WorldSelect.picking
    if not linkPick() and not picking then
        pendingHover, WorldSelect.hover = nil, nil
    elseif pendingHover then


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
            if not done then MGE.say("pick error: " .. tostring(err)) end
        else
            MGE.say("no object there, pick cancelled")
        end
        if picking.ended then picking.ended() end
        return
    end

    local ok, kind, hit = pcall(WorldSelect.pickAny, click.x, click.y)
    if not ok then
        MGE.say("world select error: " .. tostring(kind))
    elseif kind == "joint" then
        clickJoint(hit, click.additive)
    elseif kind == "player" then
        clickPlayer(hit, click.additive)
    elseif kind == "object" then
        clickObject(hit, click.additive)
    end
end)


table.insert(MGE.onQuit, function()
    WorldSelect.picking = nil
    remove_hooks(HOOK_SET)
end)

MGE.WorldSelect = WorldSelect
