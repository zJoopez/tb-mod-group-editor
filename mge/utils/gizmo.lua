-- Gizmo in the world for the active tool (Gizmo.mode). The toolbar's Move / Rotate / Scale toggles
-- (ui/main.lua) and Shift + Q / W / E (main.lua) switch it with Gizmo.toggle:
--   none:   no tool on, clicking only selects
--   move:   arrows (one world axis) and squares (two axes) at the selection's center
--   rotate: a ring per group axis (the axes Rot shows) around the selection
--   scale:  a cube handle per group axis (the axes Resize uses) and a white one for all three
-- Keeps its size on screen (Gizmo.size of the camera distance). Drawn in draw2d on top of the world
-- like rph's, so objects never hide it (picking ignores objects too).
--
-- Built on MGE's own camera rays (WorldSelect), not on screen positions of the handles: handles are
-- picked by hitting them with the mouse ray in 3D and drags are worked out on the axis / plane / ring
-- in 3D (utils/gizmo_math.lua), so a gizmo partly off screen still works. rph's gizmo projects handles
-- to the screen and adds up mouse deltas, which breaks off screen and drifts.
--
-- Works on a GizmoTarget: the selected objects (Transforms), on the Players list the selected
-- player (utils/players.lua: Move, Rotate, Scale with the white cube only), on the Joints list the
-- selected joints' anchors (utils/joints.lua: Move only).
-- A drag only changes the live world (target.previewMove / previewRotate). Releasing applies it
-- once like the Move / Rotate / Resize rows do (target.moveBy / rotateByMatrix / scaleBy): one undo
-- step (Shift + Z takes the drag back), joints follow, editor rows refresh. Ctrl snaps: Gizmo.moveStep,
-- rotateStep, scaleStep.
local GizmoMath = MGE.GizmoMath
local WorldSelect = MGE.WorldSelect
local ModData = MGE.ModData
local Mat3 = MGE.Mat3
local HOOK_SET = MGE.hookname .. "_gizmo"
local add, sub, scale, length = GizmoMath.add, GizmoMath.sub, GizmoMath.scale, GizmoMath.length

---@alias GizmoMode "none"|"move"|"rotate"|"scale"

---@class Gizmo
local Gizmo = {
    ---@type GizmoMode active tool, change it with Gizmo.setMode / Gizmo.toggle. Move is on at start
    mode = "move",
    ---@type fun()[] called after the tool changes: toolbar toggles (ui/main.lua), row name highlights
    ---(ui/editor_core.lua)
    modeListeners = {},
    size = 0.10,      -- arrow length as a share of the camera distance, keeps the gizmo's size on screen
    moveStep = 0.1,   -- Ctrl while dragging an arrow / square: the offset moves in these steps
    rotateStep = 15,  -- Ctrl while dragging a ring: degrees
    scaleStep = 0.1,  -- Ctrl while dragging a scale handle: factor steps
    ---@type (fun(mode: GizmoMode): GizmoTarget?)? when set, the gizmo works on what this gives instead
    ---of the selection (ui/map_place.lua: the region or the map being placed)
    targetOverride = nil,
    ---@type (fun(mode: GizmoMode): GizmoTarget|false|nil)? on the Objects list, before the selection:
    ---a target takes the gizmo, false takes it but shows none, nil leaves it to the selection
    ---(ui/editor_generate.lua: the Generate tab's preview, Move only)
    previewTarget = nil,
}
MGE.Gizmo = Gizmo

---@type table<string, boolean> modes that show a gizmo ("none" doesn't)
local MODES = { move = true, rotate = true, scale = true }

local COLORS = { { 1.0, 0.25, 0.25 }, { 0.3, 0.9, 0.3 }, { 0.3, 0.5, 1.0 }, { 0.9, 0.9, 0.9 } } -- x y z, all
local ACTIVE_COLOR = { 1.0, 0.9, 0.2 } -- hovered or dragged handle
local OUTLINE = { 0, 0, 0, 0.55 } -- dark edge under every line, keeps it readable on any background
local LINE_WIDTH, ACTIVE_LINE_WIDTH, OUTLINE_EXTRA = 3, 5, 3 -- pixels
local MIN_MARKER = 4 -- pixels, smallest tip / cube on screen

---@type CameraProjection? measured every frame, mouse events build their rays from it
local projection = nil
---@type { x: number, y: number }? last mouse position
local mouse = nil
---@type GizmoHandle? handle under the mouse (not dragging)
local hovered = nil
---@class GizmoDrag
---@field handle GizmoHandle
---@field target GizmoTarget objects or player being dragged
---@field center number[] gizmo center at the grab
---@field grab any dragStart's result (arrow / square) or GizmoRingGrab (ring)
---@field offset number[] move: current offset
---@field rotation number[][] rotate: current rotation
---@field scale number[] scale: current factors
---@field travel number? scale: mouse travel along the handle since the grab
---@field base table scale: handle layout at the grab (scaleBase)
---@field baseSides table<integer, number[]> scale: object sizes at the grab
---@type GizmoDrag?
local drag = nil

---@class GizmoTarget what the gizmo works on: selected objects, or a player (utils/players.lua)
---@field pivot fun(): number[] center, stays where the drag started while the preview moves things
---@field frame fun(): number[][] axes the rings / scale handles use
---@field begin fun()? called when a drag starts
---@field previewMove fun(offset: number[])
---@field previewRotate fun(rotation: number[][])
---@field previewScale fun(factors: number[], baseSides: table)?
---@field liveSides fun(): table?
---@field restoreLive fun(baseSides: table?)
---@field moveBy fun(offset: number[])
---@field rotateByMatrix fun(rotation: number[][])
---@field scaleBy fun(factors: number[])?
---@field scalable boolean? has a Scale gizmo
---@field ringsOnly integer? only this ring of Rotate
---@field uniformScaleOnly boolean? Scale has only the white cube (players)

---The selection as a gizmo target, the Transforms the editor's rows use: objects, or on the Atmo list
---atmo objects (utils/atmo_layer.lua). Transforms works on both (an atmo object only through its lines),
---commits are one undo step. Atmo objects aren't drawn by the game: a drag shows them through
---AtmoLayer.live (their ghosts drawn where it puts them, utils/highlight.lua)
---@param objects FileParserEnvObj[] in the world, or atmo objects with a pos line
---@return GizmoTarget
local function objectTarget(objects)
    local T, AtmoLayer = MGE.Transforms, MGE.AtmoLayer
    local hasAtmo = false
    for _, obj in ipairs(objects) do
        if obj.kind == "atmo" then hasAtmo = true break end
    end
    local function pivot() return { T.getSelectionPivot(objects) } end
    local function frame() return T.groupFrame(objects) end
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
            T.previewRotate(objects, rotation)
            if hasAtmo then AtmoLayer.live = { rotation = rotation, pivot = pivot() } end
        end,
        previewScale = function(factors, baseSides)
            T.previewScale(objects, factors, baseSides)
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
            T.rotateByMatrix(objects, rotation)
        end,
        scaleBy = function(factors)
            AtmoLayer.live = nil
            T.scaleBy(objects, factors)
        end,
    }
end

---What the gizmo works on, nil when no gizmo is shown: the selected objects, or on the Players list
---the selected player (Move and Rotate around z only)
---@return GizmoTarget?
local function gizmoTarget()
    local Main = MGE.Main
    if not MODES[Gizmo.mode] or not Main or not Main.window then return nil end
    -- MGE's window hidden: no gizmo, except for an override (the map placement view hides the window)
    if not Main.window.displayed and not Gizmo.targetOverride then return nil end
    -- the gizmo draws in draw2d, on top of everything: hidden (and not grabbable) under an overlay
    if MGE.overlayOpen and MGE.overlayOpen() then return nil end
    -- something else has the gizmo (the map placement view, ui/map_place.lua), nil: no gizmo
    if Gizmo.targetOverride then return Gizmo.targetOverride(Gizmo.mode) end
    if Main.listTab == "joints" then
        -- the selected joints' anchors, Move only, on both of the list's tabs
        if Gizmo.mode ~= "move" then return nil end
        return MGE.Joints.target(Main.selectedJointList())
    end
    if Main.listTab == "players" then
        local t = MGE.Players and MGE.Players.target(Main.selectedPlayerList()) -- all selected, as a group
        if t and Gizmo.mode == "scale" and not t.scalable then return nil end
        return t
    end
    if (Main.listTab == "objects" or Main.listTab == "atmo") and Gizmo.previewTarget then
        local t = Gizmo.previewTarget(Gizmo.mode)
        if t ~= nil then return t or nil end
    end
    -- the objects in the world, or on the Atmo list the atmo objects with a pos line (the ones drawn)
    local objects = {}
    for _, obj in ipairs(ModData.getEditSelection()) do
        if obj.kind == "atmo" and obj.props.pos or obj.kind ~= "atmo" and get_obj_pos(obj.id - 1) ~= nil then
            table.insert(objects, obj)
        end
    end
    return #objects > 0 and objectTarget(objects) or nil
end

---@param handle GizmoHandle
---@return GizmoMode
local function modeOf(handle)
    if handle.kind == "ring" then return "rotate" end
    if handle.kind == "scale" or handle.kind == "uniform" then return "scale" end
    return "move"
end

---Scale handle layout: group axes and where the axis cubes and the uniform cube sit (distances from
---the center). Kept from the grab while dragging, the handles then stretch by the factors
---@param target GizmoTarget
---@param size number gizmo size
---@return { axes: number[][], tips: number[], corner: number[], size: number }
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

---Gizmo center (the selection's center as the file has it, moved / turned by the drag so far) and its
---handles. The size is a share of the camera distance, so the gizmo looks the same at any zoom
---@param target GizmoTarget
---@param mode GizmoMode
---@return number[]? center, GizmoHandle[]? handles, number? size, number[]? viewDir
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
        -- rings on the group's axes, turning along while dragging
        local frame = target.frame()
        if drag and drag.rotation then frame = Mat3.mul(drag.rotation, frame) end
        handles = GizmoMath.ringHandles(center, frame, GizmoMath.SHAPE.ringRadius * size)
        if target.ringsOnly then -- players turn around z only
            for _, h in ipairs(handles) do
                if h.index ~= target.ringsOnly then h.enabled = false end
            end
        end
    elseif mode == "scale" then
        -- the layout from the grab, the dragged cube moved along with the cursor
        local base = (drag and drag.base) or scaleBase(target, size)
        local travel = (drag and drag.travel) or 0
        local kind, index = drag and drag.handle.kind, drag and drag.handle.index
        local tips, toCorner = {}, {}
        for k = 1, 3 do
            tips[k] = base.tips[k]
            if kind == "scale" and index == k then tips[k] = math.max(tips[k] + travel, 0.05 * base.size) end
            toCorner[k] = base.corner[k]
            -- the uniform cube moves along the diagonal: travel / sqrt(3) along each axis
            if kind == "uniform" then toCorner[k] = math.max(toCorner[k] + travel / math.sqrt(3), 0.05 * base.size) end
        end
        handles = GizmoMath.scaleHandles(center, base.axes, tips, toCorner, viewDir)
        if target.uniformScaleOnly then -- players: the white cube only
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
Gizmo.layout = function(objects) return layout(objectTarget(objects), Gizmo.mode) end -- for the offline tests

---Nearest enabled handle hit by the ray through the screen position
---@param handles GizmoHandle[]
---@param size number
---@return GizmoHandle? handle, number? distance along the ray
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
            else -- ring: its segments
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

---@class GizmoShape what draw2d draws for one handle, in screen pixels
---@field color number[]
---@field width number line width
---@field lines number[][] { x1, y1, x2, y2 }
---@field disks number[][] { x, y, radius } round tips and line joints
---@field squares number[][] { x, y, half } screen aligned (scale cubes)
---@field fill number[][]? { x1, y1, x2, y2 } thin lines filling a plane square
---@field alpha number

---@type GizmoShape[]? built in draw3d (the projection is measured there), drawn in draw2d
local shapes = nil

local function screen(point) return WorldSelect.project(projection, point) end

---Pixel radius of a world radius at a point
local function pixelRadius(point, radius)
    local x, y = screen(point)
    local x2, y2 = screen(add(point, scale(projection.right, radius)))
    if not x or not x2 then return MIN_MARKER end
    return math.max(math.sqrt((x2 - x) ^ 2 + (y2 - y) ^ 2), MIN_MARKER)
end

---Adds the screen line a-b to a shape, with round joints. Skipped when an end is behind the camera
local function addLine(shape, a, b)
    local ax, ay = screen(a)
    local bx, by = screen(b)
    if not ax or not bx then return end
    table.insert(shape.lines, { ax, ay, bx, by })
    table.insert(shape.disks, { ax, ay, shape.width / 2 })
    table.insert(shape.disks, { bx, by, shape.width / 2 })
end

---Screen drawing of one handle
---@param h GizmoHandle
---@param size number
---@param active boolean
---@return GizmoShape
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
        -- see-through fill: lines across the square
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
    else -- scale / uniform: shaft and a cube, shown as a square on screen
        if h.kind == "scale" then addLine(shape, h.from, h.to) end
        local x, y = screen(h.to)
        local half = (h.kind == "uniform" and 1.3 or 1) * S.tipRadius * size
        if x then table.insert(shape.squares, { x, y, pixelRadius(h.to, half) }) end
    end
    return shape
end

---@param shape GizmoShape
---@param outline boolean the dark pass under the colors
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

---Works out the drag for the ray through the screen position and shows it in the world
local function updateDrag(x, y)
    local o, d = WorldSelect.rayFrom(projection, x, y)
    if not d then return end
    local snapping = get_keyboard_ctrl() ~= 0
    if drag.handle.kind == "ring" then
        local angle = GizmoMath.ringAngle(drag.handle, drag.grab, o, d, snapping and math.rad(Gizmo.rotateStep) or nil)
        if not angle then return end -- ray unusable this frame, keep the last angle
        drag.rotation = GizmoMath.rotationAbout(drag.handle.normal, angle)
        drag.target.previewRotate(drag.rotation)
    elseif drag.scale then
        local factors, travel = GizmoMath.scaleFactors(drag.handle, drag.grab, o, d, drag.base.size,
            snapping and Gizmo.scaleStep or nil)
        if not factors then return end -- ray parallel to the handle this frame, keep the last factors
        drag.scale, drag.travel = factors, travel
        drag.target.previewScale(factors, drag.baseSides)
    else
        local offset = GizmoMath.dragOffset(drag.handle, drag.center, drag.grab, o, d, snapping and Gizmo.moveStep or nil)
        if not offset then return end -- ray parallel to the axis this frame, keep the last offset
        drag.offset = offset
        drag.target.previewMove(offset)
    end
end

---@return boolean
function Gizmo.isDragging()
    return drag ~= nil
end

---@return GizmoHandle? the handle being dragged
function Gizmo.draggedHandle()
    return drag and drag.handle
end

---@return any the drag's grab state (offline tests)
function Gizmo.draggedGrab()
    return drag and drag.grab
end

---Left mouse down (from WorldSelect's hook): starts a drag when it's on a handle
---@return boolean true when a handle was grabbed, the click is used up
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

---Left mouse up (from WorldSelect's hook): applies the drag
---@return boolean true when a drag ended, the click is used up
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
        -- sizes back to the grab first: scaleBy reads them from the world
        target.restoreLive(done.baseSides)
        local f = done.scale
        if math.abs(f[1] - 1) > 1e-9 or math.abs(f[2] - 1) > 1e-9 or math.abs(f[3] - 1) > 1e-9 then
            target.scaleBy(f) -- file and world, undo step, rows refresh
        end
    elseif length(done.offset) > 1e-9 then
        target.moveBy(done.offset) -- file and world, undo step, rows refresh
    else
        target.restoreLive()
    end
    return true
end

---Ends a drag without changing anything, the world goes back to the file. Not a control: used when
---world clicking is turned off or MGE quits mid drag, so the world isn't left half done
function Gizmo.cancel()
    if not drag then return end
    local target, baseSides = drag.target, drag.baseSides
    drag = nil
    target.restoreLive(baseSides)
end

---Picks the tool. A drag in progress is cancelled. A gizmo tool turns world clicking back on, a
---gizmo can't be used without it
---@param mode GizmoMode
function Gizmo.setMode(mode)
    if mode ~= "none" and not MODES[mode] then return end
    if mode == Gizmo.mode then return end
    Gizmo.cancel()
    Gizmo.mode = mode
    for _, listener in ipairs(Gizmo.modeListeners) do listener() end
end

---Turns a tool on, or off when it's the active one (back to only selecting)
---@param mode GizmoMode
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
        if active then table.insert(built, active) end -- on top of the others
        shapes = built
    end)
    if not ok then
        shapes = nil
        if not Gizmo.errorShown then -- report once instead of every frame
            Gizmo.errorShown = true
            echo("[MGE] gizmo error: " .. tostring(err))
        end
    end
end)

-- on top of the world: objects don't hide the gizmo
add_hook("draw2d", HOOK_SET, function()
    if not shapes then return end
    if MGE.overlayOpen and MGE.overlayOpen() then return end -- also mid drag: not over an overlay
    local ok, err = pcall(function()
        for _, shape in ipairs(shapes) do drawShape(shape, true) end
        for _, shape in ipairs(shapes) do drawShape(shape, false) end
    end)
    if not ok and not Gizmo.errorShown then
        Gizmo.errorShown = true
        echo("[MGE] gizmo draw error: " .. tostring(err))
    end
end)

-- MGE.quit removes hooks of MGE.hookname only
table.insert(MGE.onQuit, function()
    Gizmo.cancel()
    remove_hooks(HOOK_SET)
end)

return Gizmo
