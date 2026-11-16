













local MapConv = MGE.MapConv
local Mat3 = MGE.Mat3
local Vec = MapConv.Vec
local Widgets = MGE.Widgets
local Highlight = MGE.Highlight


local MapPlace = {
    active = false,



    maxDraws = 512,
    contextLimit = 250,
    contextMargin = 0.5,
    minRegion = 16,
}
MGE.MapPlace = MapPlace

local COLORS = {
    kept = Highlight.previewColor,
    cut = { 1.0, 0.2, 0.2 },
    context = { 0.8, 0.8, 0.8 },
    region = { 0.2, 0.85, 1.0 },
}
























local session = nil

local editing = "region"

local kept, cut, context = {}, {}, {}

local allContext = {}

local contextCache = nil

local shown = { kept = 0, cut = 0, context = 0, outlines = 0, trimmed = false }

local world = nil


local live = {}

local bar = nil

local windowWasShown = false

local modeBefore = nil

local refreshBar = nil

local info = nil


local function placement()
    return { scale = session.options.scale, yaw = session.options.yaw }
end


local function mapFrame()
    return Mat3.rotZ(math.rad(session.options.yaw))
end


local function regionCenter()
    local r = session.region
    return { (r.min[1] + r.max[1]) / 2, (r.min[2] + r.max[2]) / 2, (r.min[3] + r.max[3]) / 2 }
end


local function regionBox()
    local r = session.region
    local box = { center = regionCenter(), frame = Mat3.IDENTITY, sides = Vec.sub(r.max, r.min) }
    local pos, frame, sides = MapConv.toWorld(box, session.anchor, placement())
    return { pos = pos, frame = frame, sides = sides }
end



local function objectCount()
    local free = #MGE.ModData.freeIds.static + #MGE.ModData.freeIds.nonStatic
    return math.min(free, session.options.objectBudget or free)
end


local function setInfo(message)
    if not info or info.destroyed then return end
    local budget = session.options.budget
    local atmoCount = math.max(0, #kept - objectCount())
    Widgets.infoText(info, message or (#kept .. " boxes of " .. budget .. (#cut > 0 and (", " .. #cut .. " over (red)") or "")
        .. (atmoCount > 0 and (", " .. atmoCount .. " to the atmo (purple)") or "")
        .. (shown.trimmed and ", preview trimmed" or "")
        .. "   Move / Scale: Alt + Q / E, Rotate (the map): Alt + W"))
end


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





local function plan()
    shown.kept = #kept
    local left = MapPlace.maxDraws - 2
    shown.cut = math.max(0, math.min(#cut, left))
    left = left - shown.cut
    shown.context = math.max(0, math.min(#context, left))
    left = left - shown.context
    shown.outlines = math.max(0, math.min(shown.kept, left))
    shown.trimmed = shown.kept < #kept or shown.cut < #cut or shown.context < #context
end



local function ground()
    local lowest = math.huge
    for _, box in ipairs(kept) do
        lowest = math.min(lowest, box.center[3] - MapConv.halfHeight(box))
    end
    if lowest == math.huge then return end
    session.anchor[3] = lowest - session.lift / session.options.scale
    world = nil
end



local function follow()
    if not MGE.Camera.followMoves then return end
    local box = regionBox()
    MGE.Camera.focusOn(box.pos, Vec.length(box.sides) / 2)
end


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






local function withLive(box, isRegion)
    if not (live.offset or live.factors or live.rotation) then return box end
    if editing == "region" then
        if not isRegion then return box end
        local pos, sides = box.pos, box.sides
        if live.offset then pos = Vec.add(pos, live.offset) end
        if live.factors then sides = { sides[1] * live.factors[1], sides[2] * live.factors[2], sides[3] * live.factors[3] } end
        return { pos = pos, frame = box.frame, sides = sides }
    end
    local center = regionBox().pos
    local pivot = { center[1], center[2], 0 }
    local turn = live.rotation or Mat3.IDENTITY
    local f = live.factors and live.factors[1] or 1
    local pos = Vec.add(pivot, Vec.scale(Mat3.apply(turn, Vec.sub(box.pos, pivot)), f))
    if live.offset then pos = Vec.add(pos, live.offset) end

    return { pos = pos, frame = live.rotation and Mat3.mul(turn, box.frame) or box.frame, sides = Vec.scale(box.sides, f) }
end


local function draw()
    if not session then return end
    local boxes = worldBoxes()

    for _, box in ipairs(boxes.context) do Highlight.drawBox(withLive(box, false), COLORS.context, 0.08, false) end
    for _, box in ipairs(boxes.cut) do Highlight.drawBox(withLive(box, false), COLORS.cut, 0.3, false) end

    local free = objectCount()
    for i, box in ipairs(boxes.kept) do
        Highlight.drawBox(withLive(box, false), i > free and MGE.AtmoLayer.color or COLORS.kept, Highlight.previewAlpha,
            i <= shown.outlines)
    end
    Highlight.drawBox(withLive(regionBox(), true), COLORS.region, editing == "region" and 0.06 or 0.02, true)
end



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






local function anchorAroundRegion(turn, factor)
    return MapConv.anchorAround(session.anchor, placement(), regionBox().pos, turn, factor)
end





local function mapTarget()
    return {
        scalable = true,
        uniformScaleOnly = true,
        ringsOnly = 3,
        pivot = function() return regionBox().pos end,
        frame = mapFrame,

        previewMove = function(offset) live = { offset = { offset[1], offset[2], math.max(offset[3], -session.lift) } } end,
        previewRotate = function(rotation) live = { rotation = rotation } end,
        previewScale = function(factors) live = { factors = factors } end,
        liveSides = function() return nil end,
        restoreLive = function() live = {} end,
        moveBy = function(offset)
            live = {}

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
            session.anchor = anchorAroundRegion(Mat3.rotZ(math.rad(turn)), 1)
            session.options.yaw = (session.options.yaw + turn) % 360
            world = nil
            follow()
        end,
        scaleBy = function(factors)
            live = {}
            local scale = math.max(session.options.scale * factors[1], 0.0005)
            session.anchor = anchorAroundRegion(Mat3.IDENTITY, scale / session.options.scale)
            session.options.scale = scale
            ground()
            world = nil
            setInfo()
            follow()
        end,
    }
end



local function gizmoTarget(mode)
    if not session then return nil end
    if editing == "region" then
        if mode ~= "rotate" then return regionTarget() end


        editing = "map"
        if refreshBar then refreshBar() end
    end
    return mapTarget()
end



local function placed(s)
    return {
        region = s.region,
        anchor = { s.anchor[1], s.anchor[2], s.anchor[3] },
        yaw = s.options.yaw,
        scale = s.options.scale,
        lift = s.lift,
        simplify = s.options.simplify ~= false,
        dropCovered = s.options.dropCovered == true,
    }
end


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

    if modeBefore and not MGE.quitting then MGE.Gizmo.setMode(modeBefore) end
    modeBefore = nil

    local window = MGE.Main and MGE.Main.window
    if windowWasShown and window and not window.destroyed and not MGE.quitting then
        window:show(false)
        MGE.Main.applyTab()
        MGE.Main.updateWindow()
    end
    windowWasShown = false
    bar, info, session, world, live = nil, nil, nil, nil, {}
    kept, cut, context, allContext = {}, {}, {}, {}
    shown = { kept = 0, cut = 0, context = 0, outlines = 0, trimmed = false }
    MapPlace.active = false
end


function MapPlace.settings()
    if not session then return end
    local s = session
    stop()
    s.onSettings(placed(s))
end
MapPlace.cancel = MapPlace.settings


function MapPlace.convert()
    if not session then return end
    MGE.Gizmo.cancel()
    local s = session
    local finish, err = s.onConvert(placed(s))
    if finish then


        stop()
        finish()
    else
        setInfo(err or "Nothing to convert")
    end
end




local function light(button, on)
    if not button.destroyed then button.bgColor = on and Widgets.ACTIVE_COLOR or Widgets.STYLE.bg end
end






local function buildBar()
    local px = Widgets.px
    local w, pad, gap = px(720), px(6), px(24)
    local rowH, toggleH = px(30), px(26)
    local h = pad + rowH + 4 + toggleH + 4 + Widgets.INFO_HEIGHT + 4 + pad
    local window = MGE.Main.window
    bar = UIElement:new({
        globalid = window.globalid,
        pos = { (WIN_W - w) / 2, 10 },
        size = { w, h },
        bgColor = Widgets.CONTENT_BG,
        shapeType = ROUNDED,
        rounded = 5,
        interactive = true,
    })
    local inner = w - pad * 2
    local unit = (inner - gap * 2) / 7
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
        light(toggles[1], session.options.simplify ~= false)
        light(toggles[2], session.options.dropCovered == true)
        setInfo()
    end
    refreshBar = refresh
    local function pick(what)
        Gizmo.cancel()
        editing = what

        if what == "region" and Gizmo.mode == "rotate" then Gizmo.setMode("move") end
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
        { label = "Simplify", onClick = function()
            session.options.simplify = session.options.simplify == false
            reselect()
            refresh()
        end },
        { label = "Covered", onClick = function() flip("dropCovered") end },
    }, 4, Widgets.TEXT_SCALE_SMALL)
    Widgets.popupBelow(toggles[1], "Joins nearly flat neighbouring slabs (terrain floors,\nfloor tiles) into bigger ones: far fewer boxes")
    Widgets.popupBelow(toggles[2], "Also leaves out boxes " .. math.floor(MapConv.COVERED_SHARE * 100 + 0.5) ..
        "% covered by other boxes\ntogether. Boxes inside one other box always go")
    info = bar:addChild({ pos = { pad, pad + rowH + 4 + toggleH + 4 }, size = { inner, Widgets.INFO_HEIGHT + 4 } })
    table.insert(Gizmo.modeListeners, refresh)
    refresh()
end



function MapPlace.start(s)
    if MapPlace.active then stop() end
    session = s
    s.lift = math.max(0, s.lift or 0)
    MapPlace.active = true
    editing = "region"
    live = {}

    local all = MapConv.withDefaults(s.options)

    all.region, all.budget, all.simplify = nil, math.huge, false
    all.dropHidden, all.dropCovered = false, false


    local key = table.concat({ tostring(all.merge), all.minSize }, "|")
    if contextCache and contextCache.pieces == s.pieces and contextCache.key == key then
        allContext = contextCache.boxes
    else
        allContext = MapConv.select(s.pieces, all, s.report)
        contextCache = { pieces = s.pieces, key = key, boxes = allContext }
    end
    reselect()
    MGE.Gizmo.targetOverride = gizmoTarget
    modeBefore = MGE.Gizmo.mode
    if MGE.Gizmo.mode == "none" then MGE.Gizmo.setMode("move") end
    Highlight.placement = draw
    MGE.WorldSelect.clicksOff = true

    local window = MGE.Main.window
    windowWasShown = window.displayed == true
    if windowWasShown then window:hide(false) end
    buildBar()
    local box = regionBox()
    MGE.Camera.focusOn(box.pos, Vec.length(box.sides) / 2)
end

table.insert(MGE.onQuit, function() if MapPlace.active then stop() end end)

return MapPlace
