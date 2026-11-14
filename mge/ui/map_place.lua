-- Map placement view, opened by the Convert Map overlay's Place button (ui/map_overlay.lua): where a
-- map conversion is picked. The map is drawn in the world where Convert puts it, with the box of it
-- that gets converted (the region). The gizmo (toolbar Move / Rotate / Scale, Shift + Q / W / E) works
-- on what the bar at the top picks:
--   Region: Move it, Scale it per axis (its size), in the map's own axes
--   Map:    Move (where the map sits: the anchor), Rotate around z (yaw), Scale (white cube: map scale)
-- Orange: what Convert adds (the biggest pieces up to the budget), purple: added parked (the ones
-- after the overlay's Budget, its Parked count, utils/parking.lua), red: in the region but over the
-- budget, grey: the map around the region (MapPlace.contextMargin, its biggest boxes). The counts in
-- the bar are the conversion's own (MapConv.select, run again after every region change). The preview
-- draws at most MapPlace.maxDraws shapes a frame, the bar says when some are left out.
-- Convert adds the boxes and closes the view, Settings (or Esc) goes back to the overlay. Both keep
-- the placement for the next time. World clicks don't select while it's open, camera drags still work.
local MapConv = MGE.MapConv
local Mat3 = MGE.Mat3
local Vec = MapConv.Vec
local Widgets = MGE.Widgets
local Highlight = MGE.Highlight

---@class MapPlace
local MapPlace = {
    active = false,
    -- the game draws only so many 3D shapes a frame, a whole map (dust2) is far more: what's drawn is
    -- capped, in this order (a draw each): region, kept, over budget, grey context, kept outlines
    maxDraws = 786,
    contextLimit = 250, -- grey boxes at most, the biggest near the region
    contextMargin = 0.5, -- grey boxes come from around the region: this share of its size on each side
    minRegion = 16, -- map units, smallest region side
}
MGE.MapPlace = MapPlace

local COLORS = {
    kept = Highlight.previewColor,
    cut = { 1.0, 0.2, 0.2 },
    context = { 0.8, 0.8, 0.8 },
    region = { 0.2, 0.85, 1.0 },
}

---@class MapPlaceSession
---@field pieces MapConvPiece[] MapConv.pieces of the map
---@field report MapConvReport the report that came with them
---@field options MapConvOptions the overlay's options (budget, scale, yaw...), region and anchor aside
---@field region { min: number[], max: number[] } map units
---@field anchor number[] map units. Its height is worked out (ground): the lowest kept box sits lift
---above the ground (z 0), the game's floor can't be removed and nothing should end up under it
---@field lift number world units the lowest point sits above the ground, 0 or more (Map Move up / down)
---@field onConvert fun(placed: MapPlaced): (fun()?), string? converts: a function that adds the boxes (run
---once the view is closed and MGE's window is back), or nil and why nothing could be added (the view
---stays open)
---@field onSettings fun(placed: MapPlaced) back to the overlay, keeping the placement

---@class MapPlaced what the view picked
---@field region { min: number[], max: number[] }
---@field anchor number[]
---@field yaw number
---@field scale number
---@field lift number
---@field floorsFirst boolean the bar's budget order toggles
---@field centerFirst boolean
---@field simplify boolean the bar's Simplify toggle (Merge.flat)
---@field dropCovered boolean the bar's Covered toggle (Merge.hidden with MapConv.COVERED_SHARE)

---@type MapPlaceSession?
local session = nil
---@type "region"|"map" what the gizmo works on
local editing = "region"
-- the conversion as it stands: kept and cut boxes (map units), the rest of the map for context
local kept, cut, context = {}, {}, {}
-- the whole map merged, the biggest first: context is picked from it around the region
local allContext = {}
-- how many of kept, cut and context fit in MapPlace.maxDraws (see plan)
local shown = { kept = 0, cut = 0, context = 0, outlines = 0, trimmed = false }
---@type { key: string, kept: HighlightBox[], cut: HighlightBox[], context: HighlightBox[] }?
local world = nil
-- a gizmo drag in progress: shown live, committed on release
---@type { offset: number[]?, factors: number[]?, rotation: number[][]? }
local live = {}
---@type UIElement?
local bar = nil
-- MGE's window was shown when the view opened: it's hidden meanwhile and shown again after
local windowWasShown = false
---@type GizmoMode? the gizmo's tool when the view opened: it starts on Move, stop puts this one back
local modeBefore = nil
---@type fun()? the bar's refresh while it's up, also a gizmo mode listener (Gizmo.modeListeners)
local refreshBar = nil
---@type UIElement?
local info = nil

---@return { scale: number, yaw: number }
local function placement()
    return { scale = session.options.scale, yaw = session.options.yaw }
end

---@return number[][] the map's axes in the world (yaw)
local function mapFrame()
    return Mat3.rotZ(math.rad(session.options.yaw))
end

---@return number[] middle of the region, map units
local function regionCenter()
    local r = session.region
    return { (r.min[1] + r.max[1]) / 2, (r.min[2] + r.max[2]) / 2, (r.min[3] + r.max[3]) / 2 }
end

---@return HighlightBox the region in the world, committed (no drag)
local function regionBox()
    local r = session.region
    local box = { center = regionCenter(), frame = Mat3.IDENTITY, sides = Vec.sub(r.max, r.min) }
    local pos, frame, sides = MapConv.toWorld(box, session.anchor, placement())
    return { pos = pos, frame = frame, sides = sides }
end

---@return integer how many kept boxes become objects: those past it get parked (utils/parking.lua). The
---overlay's Budget (objectBudget), at most the object ids free in the mod
local function objectCount()
    local free = #MGE.ModData.freeIds.static + #MGE.ModData.freeIds.nonStatic
    return math.min(free, session.options.objectBudget or free)
end

---@param message string? shown instead of the counts (a failed Convert)
local function setInfo(message)
    if not info or info.destroyed then return end
    local budget = session.options.budget
    local parked = math.max(0, #kept - objectCount())
    Widgets.infoText(info, message or (#kept .. " boxes of " .. budget .. (#cut > 0 and (", " .. #cut .. " over (red)") or "")
        .. (parked > 0 and (", " .. parked .. " parked (purple)") or "")
        .. (shown.trimmed and ", preview trimmed" or "")
        .. "   Move / Scale: Shift + Q / E" .. (editing == "map" and ", Rotate: Shift + W" or "")))
end

---The grey context: boxes of the whole map whose middle is around the region but not in it
local function pickContext()
    local r = session.region
    local min, max = {}, {}
    for k = 1, 3 do
        local margin = (r.max[k] - r.min[k]) * MapPlace.contextMargin
        min[k], max[k] = r.min[k] - margin, r.max[k] + margin
    end
    context = {}
    for _, box in ipairs(allContext) do
        if #context >= MapPlace.contextLimit then break end
        local c, around, inside = box.center, true, true
        for k = 1, 3 do
            if c[k] < min[k] or c[k] > max[k] then around = false end
            if c[k] < r.min[k] or c[k] > r.max[k] then inside = false end
        end
        if around and not inside then context[#context + 1] = box end
    end
end

---How many boxes of each kind fit in MapPlace.maxDraws, one draw per fill: the region box (fill and
---outline), kept, over budget, context, then outlines for the kept boxes with what's left. Outlines
---go first, the boxes themselves last
local function plan()
    local left = MapPlace.maxDraws - 2
    shown.kept = math.max(0, math.min(#kept, left))
    left = left - shown.kept
    shown.cut = math.max(0, math.min(#cut, left))
    left = left - shown.cut
    shown.context = math.max(0, math.min(#context, left))
    left = left - shown.context
    shown.outlines = math.max(0, math.min(shown.kept, left))
    shown.trimmed = shown.kept < #kept or shown.cut < #cut or shown.context < #context
end

---Height of the anchor: the lowest point of the kept boxes goes lift above the ground. The map only
---turns around z, so heights in map units carry over: world z = (z - anchor z) * scale
local function ground()
    local lowest = math.huge
    for _, box in ipairs(kept) do
        lowest = math.min(lowest, box.center[3] - MapConv.halfHeight(box))
    end
    if lowest == math.huge then return end -- nothing kept, the height stays
    session.anchor[3] = lowest - session.lift / session.options.scale
    world = nil
end

---After a change: the camera looks at the region again (keeping its distance when it's far enough),
---like moving objects does with Camera follow on
local function follow()
    if not MGE.Camera.followMoves then return end
    local box = regionBox()
    MGE.Camera.focusOn(box.pos, Vec.length(box.sides) / 2, true)
end

---Runs the conversion's selection for the region again
local function reselect()
    local options = MapConv.withDefaults(session.options)
    options.region = session.region
    kept, cut = MapConv.select(session.pieces, options, session.report)
    ground()
    pickContext()
    plan()
    world = nil
    setInfo()
end

---World boxes for drawing, made again when the conversion or the placement changed
local function worldBoxes()
    local p = placement()
    local key = table.concat({ p.scale, p.yaw, session.anchor[1], session.anchor[2], session.anchor[3] }, "|")
    if world and world.key == key then return world end
    local function convert(list, limit)
        local out = {}
        for i, box in ipairs(list) do
            if limit and i > limit then break end
            local pos, frame, sides = MapConv.toWorld(box, session.anchor, p)
            out[i] = { pos = pos, frame = frame, sides = sides }
        end
        return out
    end
    world = { key = key, kept = convert(kept, shown.kept), cut = convert(cut, shown.cut),
        context = convert(context, shown.context) }
    return world
end

---A drawn box moved by the drag in progress: the map's around the dojo center (move, turn, scale), the
---region's by its own offset and per axis factors
---@param box HighlightBox
---@param isRegion boolean
---@return HighlightBox
local function withLive(box, isRegion)
    if not (live.offset or live.factors or live.rotation) then return box end
    if editing == "region" then
        if not isRegion then return box end
        local pos, sides = box.pos, box.sides
        if live.offset then pos = Vec.add(pos, live.offset) end
        if live.factors then sides = { sides[1] * live.factors[1], sides[2] * live.factors[2], sides[3] * live.factors[3] } end
        return { pos = pos, frame = box.frame, sides = sides }
    end
    local origin = MGE.POS_ORIGIN
    local pivot = { origin[1], origin[2], 0 }
    local turn = live.rotation or Mat3.IDENTITY
    local f = live.factors and live.factors[1] or 1
    local pos = Vec.add(pivot, Vec.scale(Mat3.apply(turn, Vec.sub(box.pos, pivot)), f))
    if live.offset then pos = Vec.add(pos, live.offset) end
    return { pos = pos, frame = Mat3.mul(turn, box.frame), sides = Vec.scale(box.sides, f) }
end

---Highlight.placement while open
local function draw()
    if not session then return end
    local boxes = worldBoxes()
    -- draw counts as planned (plan): fills, outlines only on the biggest kept boxes that fit
    for _, box in ipairs(boxes.context) do Highlight.drawBox(withLive(box, false), COLORS.context, 0.08, false) end
    for _, box in ipairs(boxes.cut) do Highlight.drawBox(withLive(box, false), COLORS.cut, 0.3, false) end
    -- kept past the object budget: parked by Convert (the smallest, kept is in budget order)
    local free = objectCount()
    for i, box in ipairs(boxes.kept) do
        Highlight.drawBox(withLive(box, false), i > free and MGE.Parking.color or COLORS.kept, Highlight.previewAlpha,
            i <= shown.outlines)
    end
    Highlight.drawBox(withLive(regionBox(), true), COLORS.region, editing == "region" and 0.06 or 0.02, true)
end

---The region as a gizmo target: Move and Scale in the map's axes, no Rotate
---@return GizmoTarget
local function regionTarget()
    return {
        scalable = true,
        pivot = function() return regionBox().pos end,
        frame = mapFrame,
        previewMove = function(offset) live = { offset = offset } end,
        previewRotate = function() end,
        previewScale = function(factors) live = { factors = factors } end,
        liveSides = function() return nil end,
        restoreLive = function() live = {} end,
        moveBy = function(offset)
            live = {}
            local shift = Vec.scale(Mat3.apply(Mat3.transpose(mapFrame()), offset), 1 / session.options.scale)
            session.region = { min = Vec.add(session.region.min, shift), max = Vec.add(session.region.max, shift) }
            reselect()
            follow()
        end,
        rotateByMatrix = function() live = {} end,
        scaleBy = function(factors)
            live = {}
            local c, r = regionCenter(), session.region
            local min, max = {}, {}
            for k = 1, 3 do
                local half = math.max((r.max[k] - r.min[k]) * factors[k], MapPlace.minRegion) / 2
                min[k], max[k] = c[k] - half, c[k] + half
            end
            session.region = { min = min, max = max }
            reselect()
            follow()
        end,
    }
end

---The map as a gizmo target, around the dojo center: Move (anchor across, lift up and down: never
---below the ground), Rotate around z (yaw), the white Scale cube (map scale). The region goes along,
---it's in map units
---@return GizmoTarget
local function mapTarget()
    local origin = MGE.POS_ORIGIN
    return {
        scalable = true,
        uniformScaleOnly = true,
        ringsOnly = 3,
        pivot = function() return { origin[1], origin[2], 0 } end,
        frame = mapFrame,
        -- the preview doesn't go below the ground either
        previewMove = function(offset) live = { offset = { offset[1], offset[2], math.max(offset[3], -session.lift) } } end,
        previewRotate = function(rotation) live = { rotation = rotation } end,
        previewScale = function(factors) live = { factors = factors } end,
        liveSides = function() return nil end,
        restoreLive = function() live = {} end,
        moveBy = function(offset)
            live = {}
            -- across: R (m - a') s = R (m - a) s + offset, a' = a - R^T offset / s (R turns around z only)
            local back = Vec.scale(Mat3.apply(Mat3.transpose(mapFrame()), { offset[1], offset[2], 0 }), 1 / session.options.scale)
            session.anchor = { session.anchor[1] - back[1], session.anchor[2] - back[2], session.anchor[3] }
            session.lift = math.max(0, session.lift + offset[3])
            ground()
            world = nil
            follow()
        end,
        rotateByMatrix = function(rotation)
            live = {}
            local turn = math.deg((math.atan2 or math.atan)(rotation[2][1], rotation[1][1]))
            session.options.yaw = (session.options.yaw + turn) % 360
            world = nil
            follow()
        end,
        scaleBy = function(factors)
            live = {}
            session.options.scale = math.max(session.options.scale * factors[1], 0.0005)
            ground() -- the anchor's height depends on the scale
            world = nil
            setInfo()
            follow()
        end,
    }
end

---@param mode GizmoMode
---@return GizmoTarget?
local function gizmoTarget(mode)
    if not session then return nil end
    if editing == "region" then
        if mode == "rotate" then return nil end -- the region stays in the map's axes
        return regionTarget()
    end
    return mapTarget()
end

---@param s MapPlaceSession
---@return MapPlaced
local function placed(s)
    return {
        region = s.region,
        anchor = { s.anchor[1], s.anchor[2], s.anchor[3] },
        yaw = s.options.yaw,
        scale = s.options.scale,
        lift = s.lift,
        floorsFirst = s.options.floorsFirst == true,
        centerFirst = s.options.centerFirst == true,
        simplify = s.options.simplify ~= false,
        dropCovered = s.options.dropCovered == true,
    }
end

---Ends the view (Convert, Settings, Esc, quit), the gizmo and world clicks go back to the selection
local function stop()
    MGE.Gizmo.cancel()
    MGE.Gizmo.targetOverride = nil
    Highlight.placement = nil
    MGE.WorldSelect.clicksOff = false
    for i = #MGE.Gizmo.modeListeners, 1, -1 do
        if MGE.Gizmo.modeListeners[i] == refreshBar then table.remove(MGE.Gizmo.modeListeners, i) end
    end
    refreshBar = nil
    if bar and not bar.destroyed then bar:kill() end
    -- the selection's tool as it was (the view turns Move on), after the bar's listener is gone
    if modeBefore and not MGE.quitting then MGE.Gizmo.setMode(modeBefore) end
    modeBefore = nil
    -- MGE's window back, as it was before the view (not while quitting, it's being closed)
    local window = MGE.Main and MGE.Main.window
    if windowWasShown and window and not window.destroyed and not MGE.quitting then
        window:show(false)
        MGE.Main.applyTab() -- the shown list's tab row and editor panel, whatever happened meanwhile
        MGE.Main.updateWindow()
    end
    windowWasShown = false
    bar, info, session, world, live = nil, nil, nil, nil, {}
    kept, cut, context, allContext = {}, {}, {}, {}
    shown = { kept = 0, cut = 0, context = 0, outlines = 0, trimmed = false }
    MapPlace.active = false
end

---Settings (and Esc, MGE.closeTopOverlay): back to the overlay, the placement is kept
function MapPlace.settings()
    if not session then return end
    local s = session
    stop()
    s.onSettings(placed(s))
end
MapPlace.cancel = MapPlace.settings -- what Esc calls

---Convert: adds the boxes and closes the view. When nothing could be added it stays open and says why
function MapPlace.convert()
    if not session then return end
    MGE.Gizmo.cancel() -- a drag in progress isn't part of it
    local s = session
    local finish, err = s.onConvert(placed(s))
    if finish then
        -- the window back first: adding the boxes switches its tab and reloads the mod, done while it
        -- was hidden the editor's tabs didn't come back until another tab was picked
        stop()
        finish()
    else
        setInfo(err or "Nothing to convert")
    end
end

---Lights the buttons that are on
---@param button UIElement
---@param on boolean
local function light(button, on)
    if not button.destroyed then button.bgColor = on and TB_MENU_DEFAULT_LIGHTER_COLOR or Widgets.STYLE.bg end
end

---Bar at the top, MGE's window is hidden meanwhile:
---  Region | Map (what the gizmo edits), Move | Rotate | Scale (the gizmo tool: the window's toolbar
---  isn't shown), Settings | Convert
---  Floors first | Center first (the budget's order, MapConv.priority)
---  counts
local function buildBar()
    local w, pad, gap = 720, 6, 24
    local rowH, toggleH = 30, 26
    local h = pad + rowH + 4 + toggleH + 4 + Widgets.INFO_HEIGHT + 4 + pad
    local window = MGE.Main.window
    bar = UIElement:new({
        globalid = window.globalid, -- drawn with MGE's window
        pos = { (WIN_W - w) / 2, 10 },
        size = { w, h },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
        shapeType = ROUNDED,
        rounded = 5,
        interactive = true, -- clicks on it don't reach the world
    })
    local inner = w - pad * 2
    local unit = (inner - gap * 2) / 7 -- 2 + 3 + 2 buttons
    local function group(x, count)
        return bar:addChild({ pos = { pad + x, pad }, size = { unit * count, rowH } })
    end
    local Gizmo = MGE.Gizmo
    local edits, tools, toggles
    local function refresh()
        if not session then return end
        light(edits[1], editing == "region")
        light(edits[2], editing == "map")
        for i, mode in ipairs({ "move", "rotate", "scale" }) do light(tools[i], Gizmo.mode == mode) end
        light(toggles[1], session.options.floorsFirst == true)
        light(toggles[2], session.options.centerFirst == true)
        light(toggles[3], session.options.simplify ~= false)
        light(toggles[4], session.options.dropCovered == true)
        setInfo()
    end
    refreshBar = refresh
    local function pick(what)
        Gizmo.cancel()
        editing = what
        refresh()
    end
    edits = Widgets.buttonRow(group(0, 2), 0, rowH, {
        { label = "Region", onClick = function() pick("region") end },
        { label = "Map", onClick = function() pick("map") end },
    }, 4)
    tools = Widgets.buttonRow(group(unit * 2 + gap, 3), 0, rowH, {
        { label = "Move", onClick = function() Gizmo.toggle("move") end },
        { label = "Rotate", onClick = function() Gizmo.toggle("rotate") end },
        { label = "Scale", onClick = function() Gizmo.toggle("scale") end },
    }, 4)
    Widgets.buttonRow(group(unit * 5 + gap * 2, 2), 0, rowH, {
        { label = "Settings", onClick = MapPlace.settings },
        { label = "Convert", onClick = MapPlace.convert },
    }, 4)
    local function flip(key)
        session.options[key] = not session.options[key]
        reselect()
        refresh()
    end
    local toggleRow = bar:addChild({ pos = { pad, pad + rowH + 4 }, size = { inner, toggleH } })
    toggles = Widgets.buttonRow(toggleRow, 0, toggleH, {
        { label = "Floors first", onClick = function() flip("floorsFirst") end },
        { label = "Center first", onClick = function() flip("centerFirst") end },
        { label = "Simplify", onClick = function()
            session.options.simplify = session.options.simplify == false -- nil (default) counts as on
            reselect()
            refresh()
        end },
        { label = "Covered", onClick = function() flip("dropCovered") end },
    }, 4, 0.6)
    TBMenu:displayPopup(toggles[1], "Over the budget, what can be stood on goes in\nbefore equally big walls and ceilings")
    TBMenu:displayPopup(toggles[2], "Over the budget, the middle of the region goes in\nfirst, its edges are left out first")
    TBMenu:displayPopup(toggles[3], "Joins nearly flat neighbouring slabs (terrain floors,\nfloor tiles) into bigger ones: far fewer boxes")
    TBMenu:displayPopup(toggles[4], "Also leaves out boxes " .. math.floor(MapConv.COVERED_SHARE * 100 + 0.5) ..
        "% covered by other boxes\ntogether. Boxes inside one other box always go")
    info = bar:addChild({ pos = { pad, pad + rowH + 4 + toggleH + 4 }, size = { inner, Widgets.INFO_HEIGHT + 4 } })
    table.insert(Gizmo.modeListeners, refresh)
    refresh()
end

---Opens the view
---@param s MapPlaceSession
function MapPlace.start(s)
    if MapPlace.active then stop() end
    session = s
    s.lift = math.max(0, s.lift or 0)
    MapPlace.active = true
    editing = "region"
    live = {}
    -- the whole map, merged, the biggest boxes first: the grey context around the region comes from it
    local all = MapConv.withDefaults(s.options)
    -- grey background only: Simplify over the whole map (dust2: 11 000 pieces) isn't worth the wait
    all.region, all.budget, all.simplify = nil, math.huge, false
    all.dropHidden, all.dropCovered = false, false -- the grey context doesn't need them: 0.3 s on dust2
    allContext = MapConv.select(s.pieces, all, s.report)
    reselect()
    MGE.Gizmo.targetOverride = gizmoTarget
    modeBefore = MGE.Gizmo.mode
    if MGE.Gizmo.mode == "none" then MGE.Gizmo.setMode("move") end
    Highlight.placement = draw
    MGE.WorldSelect.clicksOff = true
    -- MGE's window out of the way, the bar has what's needed (shown again by stop)
    local window = MGE.Main.window
    windowWasShown = window.displayed == true
    if windowWasShown then window:hide(false) end
    buildBar()
    local box = regionBox()
    MGE.Camera.focusOn(box.pos, Vec.length(box.sides) / 2)
end

table.insert(MGE.onQuit, function() if MapPlace.active then stop() end end)

return MapPlace
