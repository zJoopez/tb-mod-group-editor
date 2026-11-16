




















local GizmoMath = MGE.GizmoMath
local WorldSelect = MGE.WorldSelect
local ModData = MGE.ModData
local Mat3 = MGE.Mat3
local HOOK_SET = MGE.hookname .. "_gizmo"
local add, sub, scale, length = GizmoMath.add, GizmoMath.sub, GizmoMath.scale, GizmoMath.length




local Gizmo = {

    mode = "move",


    modeListeners = {},
    size = 0.10,


    targetOverride = nil,



    previewTarget = nil,
}
MGE.Gizmo = Gizmo


local MODES = { move = true, rotate = true, scale = true }

local COLORS = { { 1.0, 0.25, 0.25 }, { 0.3, 0.9, 0.3 }, { 0.3, 0.5, 1.0 }, { 0.9, 0.9, 0.9 } }
local ACTIVE_COLOR = { 1.0, 0.9, 0.2 }
local OUTLINE = { 0, 0, 0, 0.55 }
local LINE_WIDTH, ACTIVE_LINE_WIDTH, OUTLINE_EXTRA = 3, 5, 3
local MIN_MARKER = 4


local projection = nil

local mouse = nil

local hovered = nil












local drag = nil




























local targetCache = {}



local function selectionKey(objects)
    local History = MGE.History
    return tostring(History.states[History.index]) .. "|" .. tostring(MGE.ModData.parsed) .. "|" .. #objects ..
        "|" .. tostring(objects[1]) .. "|" .. tostring(objects[#objects])
end





local function cachedFor(objects, name, compute)
    local key = selectionKey(objects)
    if targetCache.key ~= key then targetCache = { key = key } end
    if targetCache[name] == nil then targetCache[name] = compute() end
    return targetCache[name]
end

local function objectTarget(objects)
    local T, AtmoLayer = MGE.Transforms, MGE.AtmoLayer
    local hasAtmo = false
    for _, obj in ipairs(objects) do
        if obj.kind == "atmo" then hasAtmo = true break end
    end

    local function pivot()
        local p = cachedFor(objects, "pivot", function() return { T.getSelectionPivot(objects) } end)
        return { p[1], p[2], p[3] }
    end
    local function frame()
        local f = cachedFor(objects, "frame", function() return T.groupFrame(objects) end)
        return { { f[1][1], f[1][2], f[1][3] }, { f[2][1], f[2][2], f[2][3] }, { f[3][1], f[3][2], f[3][3] } }
    end
    return {
        objects = objects,
        scalable = true,
        pivot = pivot,
        frame = frame,
        previewMove = function(offset)
            T.previewMove(objects, offset)
            if hasAtmo then AtmoLayer.live = { move = offset } end
        end,
        previewRotate = function(rotation)
            T.previewRotate(objects, rotation, pivot())
            if hasAtmo then AtmoLayer.live = { rotation = rotation, pivot = pivot() } end
        end,
        previewScale = function(factors, baseSides)
            T.previewScale(objects, factors, baseSides, pivot(), frame())
            if hasAtmo then AtmoLayer.live = { scale = factors, pivot = pivot(), frame = frame() } end
        end,
        liveSides = function() return T.liveSides(objects) end,
        restoreLive = function(baseSides)
            AtmoLayer.live = nil
            T.restoreLive(objects, baseSides)
        end,
        moveBy = function(offset)
            AtmoLayer.live = nil
            T.moveBy(objects, offset)
        end,

        rotateByMatrix = function(rotation)
            AtmoLayer.live = nil
            T.rotateByMatrix(objects, rotation, pivot())
        end,
        scaleBy = function(factors)
            AtmoLayer.live = nil
            T.scaleBy(objects, factors, pivot(), frame())
        end,
    }
end




local function gizmoTarget()
    local Main = MGE.Main
    if not MODES[Gizmo.mode] or not Main or not Main.window then return nil end

    if not Main.window.displayed and not Gizmo.targetOverride then return nil end

    if MGE.overlayOpen and MGE.overlayOpen() then return nil end

    if Gizmo.targetOverride then return Gizmo.targetOverride(Gizmo.mode) end
    if Main.listTab == "misc" then return nil end
    if Main.listTab == "joints" then

        if Gizmo.mode ~= "move" then return nil end
        return MGE.Joints.target(Main.selectedJointList())
    end
    if Main.listTab == "players" then
        local t = MGE.Players and MGE.Players.target(Main.selectedPlayerList())
        if t and Gizmo.mode == "scale" and not t.scalable then return nil end
        return t
    end
    if (Main.listTab == "objects" or Main.listTab == "atmo") and Gizmo.previewTarget then
        local t = Gizmo.previewTarget(Gizmo.mode)
        if t ~= nil then return t or nil end
    end

    local objects = {}
    for _, obj in ipairs(ModData.getEditSelection()) do
        if obj.kind == "atmo" and obj.props.pos or obj.kind ~= "atmo" and get_obj_pos(obj.id - 1) ~= nil then
            table.insert(objects, obj)
        end
    end
    return #objects > 0 and objectTarget(objects) or nil
end



local function modeOf(handle)
    if handle.kind == "ring" then return "rotate" end
    if handle.kind == "scale" or handle.kind == "uniform" then return "scale" end
    return "move"
end






local function scaleBase(target, size)
    local frame = target.frame()
    local axes = {
        { frame[1][1], frame[2][1], frame[3][1] },
        { frame[1][2], frame[2][2], frame[3][2] },
        { frame[1][3], frame[2][3], frame[3][3] },
    }
    local corner = GizmoMath.SHAPE.uniformOffset * size
    return { axes = axes, tips = { size, size, size }, corner = { corner, corner, corner }, size = size }
end






local function layout(target, mode)
    if not projection then return nil end
    local pivot = target.pivot()
    local center = (drag and drag.offset) and add(pivot, drag.offset) or pivot
    local toCenter = sub(center, projection.eye)
    local dist = length(toCenter)
    if dist < 1e-6 then return nil end
    local viewDir = scale(toCenter, 1 / dist)
    local size = dist * Gizmo.size
    local handles
    if mode == "rotate" then

        local frame = target.frame()
        if drag and drag.rotation then frame = Mat3.mul(drag.rotation, frame) end
        handles = GizmoMath.ringHandles(center, frame, GizmoMath.SHAPE.ringRadius * size)
        if target.ringsOnly then
            for _, h in ipairs(handles) do
                if h.index ~= target.ringsOnly then h.enabled = false end
            end
        end
    elseif mode == "scale" then

        local base = (drag and drag.base) or scaleBase(target, size)
        local travel = (drag and drag.travel) or 0
        local kind, index = drag and drag.handle.kind, drag and drag.handle.index
        local tips, toCorner = {}, {}
        for k = 1, 3 do
            tips[k] = base.tips[k]
            if kind == "scale" and index == k then tips[k] = math.max(tips[k] + travel, 0.05 * base.size) end
            toCorner[k] = base.corner[k]

            if kind == "uniform" then toCorner[k] = math.max(toCorner[k] + travel / math.sqrt(3), 0.05 * base.size) end
        end
        handles = GizmoMath.scaleHandles(center, base.axes, tips, toCorner, viewDir)
        if target.uniformScaleOnly then
            for _, h in ipairs(handles) do
                if h.kind ~= "uniform" then h.enabled = false end
            end
        end
        size = base.size
    else
        handles = GizmoMath.moveHandles(center, size, viewDir)
    end
    return center, handles, size, viewDir
end
Gizmo.layout = function(objects) return layout(objectTarget(objects), Gizmo.mode) end





local function pickHandle(handles, size, x, y)
    local o, d = WorldSelect.rayFrom(projection, x, y)
    if not d then return nil end
    local pickRadius = GizmoMath.SHAPE.pickRadius * size
    local best, bestT = nil, math.huge
    for _, h in ipairs(handles) do
        if h.enabled then
            local t
            if h.kind == "axis" or h.kind == "scale" then
                t = WorldSelect.hitCapsule(o, d, h.from, h.to, pickRadius)
            elseif h.kind == "uniform" then
                local half = pickRadius * 1.25
                t = WorldSelect.hitBox(o, d, h.to, h.axes, { half, half, half })
            elseif h.kind == "plane" then
                t = WorldSelect.hitBox(o, d, h.center, GizmoMath.AXES, h.half)
            else
                for k = 1, #h.points - 1 do
                    local st = WorldSelect.hitCapsule(o, d, h.points[k], h.points[k + 1], pickRadius)
                    if st and (not t or st < t) then t = st end
                end
            end
            if t and t < bestT then best, bestT = h, t end
        end
    end
    return best, best and bestT
end











local shapes = nil

local function screen(point) return WorldSelect.project(projection, point) end


local function pixelRadius(point, radius)
    local x, y = screen(point)
    local x2, y2 = screen(add(point, scale(projection.right, radius)))
    if not x or not x2 then return MIN_MARKER end
    return math.max(math.sqrt((x2 - x) ^ 2 + (y2 - y) ^ 2), MIN_MARKER)
end


local function addLine(shape, a, b)
    local ax, ay = screen(a)
    local bx, by = screen(b)
    if not ax or not bx then return end
    table.insert(shape.lines, { ax, ay, bx, by })
    table.insert(shape.disks, { ax, ay, shape.width / 2 })
    table.insert(shape.disks, { bx, by, shape.width / 2 })
end






local function buildShape(h, size, active)
    local S = GizmoMath.SHAPE
    local shape = { color = active and ACTIVE_COLOR or COLORS[h.index], width = active and ACTIVE_LINE_WIDTH or LINE_WIDTH,
        lines = {}, disks = {}, squares = {}, alpha = 1 }
    if h.kind == "axis" then
        addLine(shape, h.from, h.to)
        local x, y = screen(h.to)
        if x then table.insert(shape.disks, { x, y, pixelRadius(h.to, S.tipRadius * size) }) end
    elseif h.kind == "plane" then
        local u, v = h.index % 3 + 1, (h.index + 1) % 3 + 1
        local function corner(su, sv)
            local c = { h.center[1], h.center[2], h.center[3] }
            c[u], c[v] = c[u] + su * h.half[u], c[v] + sv * h.half[v]
            return c
        end
        local c1, c2, c3, c4 = corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1)
        addLine(shape, c1, c2); addLine(shape, c2, c3); addLine(shape, c3, c4); addLine(shape, c4, c1)

        shape.fill = {}
        for k = 1, 7 do
            local t = k / 8
            local a = add(c1, scale(sub(c4, c1), t))
            local b = add(c2, scale(sub(c3, c2), t))
            local ax, ay = screen(a)
            local bx, by = screen(b)
            if ax and bx then table.insert(shape.fill, { ax, ay, bx, by }) end
        end
    elseif h.kind == "ring" then
        for k = 1, #h.points - 1 do addLine(shape, h.points[k], h.points[k + 1]) end
    else
        if h.kind == "scale" then addLine(shape, h.from, h.to) end
        local x, y = screen(h.to)
        local half = (h.kind == "uniform" and 1.3 or 1) * S.tipRadius * size
        if x then table.insert(shape.squares, { x, y, pixelRadius(h.to, half) }) end
    end
    return shape
end



local function drawShape(shape, outline)
    local extra = outline and OUTLINE_EXTRA or 0
    local c = outline and OUTLINE or shape.color
    set_color(c[1], c[2], c[3], outline and c[4] or shape.alpha)
    if shape.fill and not outline then
        set_color(c[1], c[2], c[3], 0.35)
        for _, l in ipairs(shape.fill) do draw_line(l[1], l[2], l[3], l[4], 2) end
        set_color(c[1], c[2], c[3], shape.alpha)
    end
    for _, l in ipairs(shape.lines) do draw_line(l[1], l[2], l[3], l[4], shape.width + extra) end
    for _, d in ipairs(shape.disks) do draw_disk(d[1], d[2], 0, d[3] + extra / 2, 16, 1, 0, 360, 0) end
    for _, q in ipairs(shape.squares) do
        local half = q[3] + extra / 2
        draw_quad(q[1] - half, q[2] - half, half * 2, half * 2)
    end
end


local function updateDrag(x, y)
    local o, d = WorldSelect.rayFrom(projection, x, y)
    if not d then return end


    local step, turn = nil, nil
    if get_keyboard_ctrl() ~= 0 then
        local Config = MGE.Config
        if get_keyboard_shift() ~= 0 then
            step, turn = Config.wheelFineStep, math.rad(1)
        else
            step, turn = Config.wheelStep, math.rad(Config.rotateStep)
        end
    end
    if drag.handle.kind == "ring" then
        local angle = GizmoMath.ringAngle(drag.handle, drag.grab, o, d, turn)
        if not angle then return end
        drag.rotation = GizmoMath.rotationAbout(drag.handle.normal, angle)
        drag.target.previewRotate(drag.rotation)
    elseif drag.scale then
        local factors, travel = GizmoMath.scaleFactors(drag.handle, drag.grab, o, d, drag.base.size,
            step)
        if not factors then return end
        drag.scale, drag.travel = factors, travel
        drag.target.previewScale(factors, drag.baseSides)
    else
        local offset = GizmoMath.dragOffset(drag.handle, drag.center, drag.grab, o, d, step)
        if not offset then return end
        drag.offset = offset
        drag.target.previewMove(offset)
    end
end


function Gizmo.isDragging()
    return drag ~= nil
end


function Gizmo.draggedHandle()
    return drag and drag.handle
end


function Gizmo.draggedGrab()
    return drag and drag.grab
end



function Gizmo.press(x, y)
    if drag or not projection then return false end
    local target = gizmoTarget()
    if not target then return false end
    local center, handles, size, viewDir = layout(target, Gizmo.mode)
    if not center then return false end
    local handle, t = pickHandle(handles, size, x, y)
    if not handle then return false end
    local o, d = WorldSelect.rayFrom(projection, x, y)
    if not d then return false end
    local mode = modeOf(handle)
    local grab
    if mode == "rotate" then
        grab = GizmoMath.ringGrab(handle, o, d, t, viewDir)
    elseif mode == "scale" then
        grab = GizmoMath.scaleStart(handle, o, d)
    else
        grab = GizmoMath.dragStart(handle, center, o, d)
    end
    if not grab then return false end
    drag = { handle = handle, center = center, grab = grab, target = target }
    if target.begin then target.begin() end
    if mode == "rotate" then
        drag.rotation = Mat3.IDENTITY
    elseif mode == "scale" then
        drag.scale = { 1, 1, 1 }
        drag.base = scaleBase(target, size)
        drag.baseSides = target.liveSides and target.liveSides()
    else
        drag.offset = { 0, 0, 0 }
    end
    hovered = nil
    return true
end



function Gizmo.release(x, y)
    if not drag then return false end
    if projection then updateDrag(x, y) end
    local done = drag
    drag = nil
    local target = done.target
    if done.rotation then
        local turned = false
        for r = 1, 3 do
            for c = 1, 3 do
                if math.abs(done.rotation[r][c] - Mat3.IDENTITY[r][c]) > 1e-9 then turned = true end
            end
        end
        if turned then target.rotateByMatrix(done.rotation) else target.restoreLive() end
    elseif done.scale then

        target.restoreLive(done.baseSides)
        local f = done.scale
        if math.abs(f[1] - 1) > 1e-9 or math.abs(f[2] - 1) > 1e-9 or math.abs(f[3] - 1) > 1e-9 then
            target.scaleBy(f)
        end
    elseif length(done.offset) > 1e-9 then
        target.moveBy(done.offset)
    else
        target.restoreLive()
    end
    return true
end



function Gizmo.cancel()
    if not drag then return end
    local target, baseSides = drag.target, drag.baseSides
    drag = nil
    target.restoreLive(baseSides)
end




function Gizmo.setMode(mode)
    if mode ~= "none" and not MODES[mode] then return end
    if mode == Gizmo.mode then return end
    Gizmo.cancel()
    Gizmo.mode = mode
    for _, listener in ipairs(Gizmo.modeListeners) do listener() end
end



function Gizmo.toggle(mode)
    Gizmo.setMode(Gizmo.mode == mode and "none" or mode)
end

add_hook("mouse_move", HOOK_SET, function(x, y)
    mouse = { x = x, y = y }
end)

add_hook("draw3d", HOOK_SET, function()
    local ok, err = pcall(function()
        shapes = nil
        projection = WorldSelect.measureProjection()
        if not projection then
            hovered = nil
            return
        end
        if drag and mouse then updateDrag(mouse.x, mouse.y) end
        local target = drag and drag.target or gizmoTarget()
        if not target then
            hovered = nil
            return
        end
        local mode = drag and modeOf(drag.handle) or Gizmo.mode
        local center, handles, size = layout(target, mode)
        if not center then return end
        hovered = nil
        if not drag and mouse and not TB_MENU_INPUT_ISACTIVE and not MGE.Widgets.isMouseOverUI(mouse.x, mouse.y) then
            hovered = pickHandle(handles, size, mouse.x, mouse.y)
        end
        local built = {}
        local active
        for _, h in ipairs(handles) do
            local isDragged = drag and drag.handle.kind == h.kind and drag.handle.index == h.index
            local isActive = isDragged or (hovered ~= nil and hovered.kind == h.kind and hovered.index == h.index)
            if h.enabled or isDragged then
                local shape = buildShape(h, size, isActive)
                if isActive then active = shape else table.insert(built, shape) end
            end
        end
        if active then table.insert(built, active) end
        shapes = built
    end)
    if not ok then
        shapes = nil
        if not Gizmo.errorShown then
            Gizmo.errorShown = true
            MGE.say("gizmo error: " .. tostring(err))
        end
    end
end)


add_hook("draw2d", HOOK_SET, function()
    if not shapes then return end
    if MGE.overlayOpen and MGE.overlayOpen() then return end
    local ok, err = pcall(function()
        for _, shape in ipairs(shapes) do drawShape(shape, true) end
        for _, shape in ipairs(shapes) do drawShape(shape, false) end
    end)
    if not ok and not Gizmo.errorShown then
        Gizmo.errorShown = true
        MGE.say("gizmo draw error: " .. tostring(err))
    end
end)


table.insert(MGE.onQuit, function()
    Gizmo.cancel()
    remove_hooks(HOOK_SET)
end)

return Gizmo
