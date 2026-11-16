







if MGE.mapOverlay and not MGE.mapOverlay.destroyed then return end

local Widgets = MGE.Widgets
local Rows = MGE.EditorRows
local ModData = MGE.ModData
local MapConv = MGE.loadMapConv()
local DEFAULTS = MapConv.DEFAULTS

local MAPS_DIR = MGE.scriptPath .. "assets/maps"
local RUN_HOOK = MGE.hookname .. "_mapconv"










MapConv.overlayState = MapConv.overlayState or
    { texts = {}, clips = DEFAULTS.clips, terrain = DEFAULTS.terrain, placements = {} }
local state = MapConv.overlayState
state.placements = state.placements or {}








local function freeIds()
    return #ModData.freeIds.static + #ModData.freeIds.nonStatic
end








local FIELDS = {
    { label = "Scale", keys = { "scale" }, hints = { tostring(DEFAULTS.scale) },
        info = "Toribash units per map unit.\nSource: a player is 72 units, a tori about 2.5." },
    { label = "Budget", keys = { "budget" }, hints = { tostring(freeIds()) }, whole = true,
        info = "Most boxes added as objects, the biggest surfaces\nfirst. Empty: all " .. freeIds() ..
            " object ids free in this mod.\n0: every box to the atmo, the object ids stay free." },
    { label = "Atmo", keys = { "atmo" }, hints = { "0" }, whole = true,
        info = "Boxes after the Budget's added to the atmo (drawn\nonly, no collisions, the Atmo list), " ..
            "the\nsmaller ones. Up to " .. MGE.AtmoLayer.room() .. ". Empty: none." },
    { label = "Min size", keys = { "minSize" }, hints = { tostring(DEFAULTS.minSize) },
        info = "Brushes smaller than this on every side are\nleft out (trims, details). Map units." },
    { label = "Terrain tol.", keys = { "terrainTolerance" }, hints = { tostring(DEFAULTS.terrainTolerance) },
        info = "How bumpy one terrain slab may be, map units.\nBigger: fewer boxes (dust2 B site fits at 16)." },
    { label = "Simplify tol.", keys = { "simplifyTolerance" }, hints = { tostring(DEFAULTS.simplifyTolerance) },
        info = "Simplify: how much thicker joined floor tiles and\nstrips may get (bumps, tilt), map units." },
}

local px = Widgets.px
local PANEL_W = px(420)
local PAD = px(12)
local TITLE_H = px(44)
local ROW_H = Widgets.ROW_H
local ROW_GAP = px(4)
local LABEL_W = px(110)
local HELP_SIZE = ROW_H - px(6)
local BUTTON_H = px(32)
local ROWS = 1 + #FIELDS + 2
local panelH = TITLE_H + ROWS * (ROW_H + ROW_GAP) + Widgets.INFO_HEIGHT * 2 + 8 + BUTTON_H + PAD * 2

local overlay = TBMenu:spawnWindowOverlay(true)
MGE.mapOverlay = overlay


local inputs = {}

local defaultKillAction = overlay.killAction
overlay.killAction = function()


    for key, input in pairs(inputs) do
        if input.textfieldstr then state.texts[key] = input.textfieldstr[1] or "" end
    end
    remove_hooks(RUN_HOOK)
    if defaultKillAction then defaultKillAction() end
    Widgets.releaseKeyboard(overlay)
    if MGE then MGE.mapOverlay = nil end
end

local panel = overlay:addChild({
    pos = { (WIN_W - PANEL_W) / 2, (WIN_H - panelH) / 2 },
    size = { PANEL_W, panelH },
    bgColor = Widgets.CONTENT_BG,
    shapeType = ROUNDED,
    rounded = 5,
    interactive = true,
})

local title = panel:addChild({
    pos = { PAD, 0 },
    size = { PANEL_W - PAD * 2, TITLE_H },
})
title:addAdaptedText(true, "Convert Map", nil, nil, Widgets.FONT, nil, Widgets.TITLE_SCALE)







local function addRow(y, label, help)
    local row = panel:addChild({
        pos = { PAD, y },
        size = { PANEL_W - PAD * 2, ROW_H },
    })
    local labelElement = row:addChild({
        pos = { 0, 0 },
        size = { LABEL_W, ROW_H },
    })
    labelElement:addAdaptedText(label, nil, nil, Widgets.FONT, LEFTMID, Widgets.TEXT_SCALE)
    local helpW = help and HELP_SIZE + 6 or 0
    if help then Widgets.helpIcon(row, row.size.w - HELP_SIZE, (ROW_H - HELP_SIZE) / 2, HELP_SIZE, help) end
    return row:addChild({
        pos = { LABEL_W, 0 },
        size = { row.size.w - LABEL_W - helpW, ROW_H },
        interactive = true,
    })
end

local y = TITLE_H


local mapRow = addRow(y, "Map", "A .vmf (Hammer map) or a compiled Source .bsp\n(CS:S, CS:GO, TF2...) from " .. MAPS_DIR ..
    ".\nNot CS 1.6 or CS2 maps.")
Widgets.button(mapRow, { x = 0, y = 0, w = mapRow.size.w, h = ROW_H },
    function() return state.path or "Pick map" end, function()
        MGE.FilePicker.open({
            title = "Pick Map",
            root = "data/script/" .. MAPS_DIR,
            rootLabel = "assets/maps",
            extension = table.concat(MapConv.EXTENSIONS, " "),
            keepExtension = true,
            selected = state.path,
            confirmLabel = "Use map",
            emptyText = "No maps here, put .vmf or .bsp files in data/script/" .. MAPS_DIR,
            onConfirm = function(path) state.path = path end,
        })
    end, nil, Widgets.PANEL_STYLE)
y = y + ROW_H + ROW_GAP

local convert

for _, field in ipairs(FIELDS) do
    local content = addRow(y, field.label, field.info)
    local gap = 4
    local w = (content.size.w - gap * (#field.keys - 1)) / #field.keys
    for i, key in ipairs(field.keys) do
        local holder = content:addChild({
            pos = { (i - 1) * (w + gap), 0 },
            size = { w, ROW_H },
        })

        local input = Rows.createInput(holder, function() convert() end, field.hints[i], { mode = "form", whole = field.whole })
        Widgets.closeOnEscape(input)
        local text = state.texts[key] or ""
        input.textfieldstr[1] = text
        input.textfieldindex = #text
        inputs[key] = input
    end
    y = y + ROW_H + ROW_GAP
end





local function addToggle(label, key, help)
    local content = addRow(y, label, help)
    local buttons
    local function refresh()
        for i, btn in ipairs(buttons) do
            if not btn.destroyed then
                btn.bgColor = (state[key] == (i == 1)) and Widgets.ACTIVE_COLOR or Widgets.PANEL_STYLE.bg
            end
        end
    end
    buttons = Widgets.buttonRow(content, 0, ROW_H, {
        { label = "On", onClick = function() state[key] = true refresh() end },
        { label = "Off", onClick = function() state[key] = false refresh() end },
    }, Widgets.GAP, nil, Widgets.PANEL_STYLE)
    refresh()
    y = y + ROW_H + ROW_GAP
end
addToggle("Terrain", "terrain","Terrain of compiled maps (.bsp displacements),\n" ..
    "dust2's ground: slabs under it, neighbours joined.")
addToggle("Clips", "clips", "Player clips: invisible walls, ramps over stairs.\nThe big lids under the sky are left out.")

local info = panel:addChild({
    pos = { PAD, y + 4 },
    size = { PANEL_W - PAD * 2, Widgets.INFO_HEIGHT * 2 },
})
local function setInfo(text) Widgets.infoText(info, text) end
setInfo("Map units: Source uses inches. Empty fields use the hints.")




local function typed(key)
    local text = inputs[key] and not inputs[key].destroyed and inputs[key].textfieldstr[1] or ""
    if text:match("^%s*$") then return nil, true end
    local value = tonumber(text)
    return value, value ~= nil
end




local function readOptions()
    local options = { clips = state.clips, terrain = state.terrain }

    if state.simplify ~= nil then options.simplify = state.simplify end
    if state.dropCovered ~= nil then options.dropCovered = state.dropCovered end
    for _, field in ipairs(FIELDS) do
        for _, key in ipairs(field.keys) do
            local _, ok = typed(key)
            if not ok then return nil, field.label .. ": not a number" end
        end
    end
    local scale, budget, minSize = typed("scale"), typed("budget"), typed("minSize")
    local tolerance = typed("terrainTolerance")
    if tolerance and tolerance <= 0 then return nil, "Terrain tol. must be above 0" end
    options.terrainTolerance = tolerance
    local simplifyTolerance = typed("simplifyTolerance")
    if simplifyTolerance and simplifyTolerance < 0 then return nil, "Simplify tol. can't be below 0" end
    options.simplifyTolerance = simplifyTolerance
    if scale and scale <= 0 then return nil, "Scale must be above 0" end
    local free, room = freeIds(), MGE.AtmoLayer.room()

    budget = math.floor(budget or free)
    if budget < 0 or budget > free then return nil, "Budget must be 0-" .. free .. " (free object ids)" end
    local atmoCount = math.floor(typed("atmo") or 0)
    if atmoCount < 0 or atmoCount > room then return nil, "Atmo must be 0-" .. room .. " (" .. MGE.AtmoLayer.maxAtmo .. " at most)" end
    if budget + atmoCount < 1 then return nil, "Budget and Atmo are both 0" end
    options.scale, options.budget, options.minSize = scale, budget + atmoCount, minSize
    options.objectBudget = budget

    return options
end





local function fieldText(value, decimals)
    return MGE.EditorRows.formatNumberText(value, decimals)
end







local function loadPieces(options)
    local opts = MapConv.withDefaults(options)
    local key = table.concat({ state.path, tostring(opts.terrain), opts.terrainTolerance, tostring(opts.clips),
        opts.slabThickness, opts.slabError }, "|")
    if state.cache and state.cache.key == key then return state.cache end


    local mapPath = MAPS_DIR .. "/" .. state.path
    local file = io.open(mapPath, "rb")
    if not file then return nil, "Can't read " .. state.path end
    local ok, map = pcall(MapConv.parse, file, state.path)
    file:close()
    if not ok then return nil, "Not a readable map: " .. tostring(map) end
    local pieces, report = MapConv.pieces(map, opts)
    state.cache = { key = key, map = { brushes = {}, entities = map.entities }, pieces = pieces, report = report }
    return state.cache
end


local function reopen()
    if MGE and not MGE.mapOverlay then dofile(MGE.scriptPath .. "ui/map_overlay.lua") end
end





local function place(options)
    local cache, err = loadPieces(options)
    if not cache then
        setInfo(err or "")
        return
    end
    local path = state.path
    local opts = MapConv.withDefaults(options)
    local last = state.placements[path]
    local anchor, region, lift
    if last then
        anchor, region, opts.yaw, lift = last.anchor, last.region, last.yaw, last.lift
    else
        anchor = MapConv.anchorFor(cache.map, cache.pieces, opts)
        anchor = { anchor[1], anchor[2], anchor[3] }
        region = {
            min = { anchor[1] - 500, anchor[2] - 500, anchor[3] - 200 },
            max = { anchor[1] + 500, anchor[2] + 500, anchor[3] + 600 },
        }
    end


    local function keep(p)
        state.placements[path] = { region = p.region, anchor = p.anchor, yaw = p.yaw, lift = p.lift }
        state.texts.scale = fieldText(p.scale, 4)

        state.simplify = p.simplify
        state.dropCovered = p.dropCovered
    end
    overlay:kill()
    if not MGE.MapPlace then dofile(MGE.scriptPath .. "ui/map_place.lua") end
    MGE.MapPlace.start({
        pieces = cache.pieces,
        report = cache.report,
        options = opts,
        region = region,
        anchor = { anchor[1], anchor[2], anchor[3] },
        lift = lift or 0,
        onConvert = function(p)
            keep(p)
            local convertOptions = {}
            for k, v in pairs(opts) do convertOptions[k] = v end
            convertOptions.region, convertOptions.anchor, convertOptions.yaw, convertOptions.scale = p.region, p.anchor, p.yaw, p.scale
            local result = MapConv.convert(cache.map, convertOptions, cache.pieces, cache.report)
            if #result.objects == 0 then return nil, "No boxes in the region" end

            return function()


                MGE.Assets.addObjects(result.objects, false, false, nil, opts.objectBudget or true)
                for _, line in ipairs(MapConv.reportLines(result.report)) do MGE.say("" .. line) end
            end
        end,
        onSettings = function(p)
            keep(p)
            reopen()
        end,
    })
end

local pending






local function defer(label, action)
    if pending then return end
    if not state.path then
        setInfo("Pick a map first")
        return
    end
    local options, err = readOptions()
    if not options then
        setInfo(err or "")
        return
    end
    pending = label
    setInfo(label .. " " .. state.path .. "...")
    local frames = 0
    add_hook("draw2d", RUN_HOOK, function()
        frames = frames + 1
        if frames < 2 then return end
        remove_hook("draw2d", RUN_HOOK)
        pending = nil
        if not overlay.destroyed then action(options) end
    end)
end

convert = function() defer("Loading", place) end

local buttonW = (PANEL_W - PAD * 2 - 8) / 2
local buttonY = panelH - PAD - BUTTON_H
Widgets.button(panel, { x = PAD, y = buttonY, w = buttonW, h = BUTTON_H }, "Cancel", function() overlay:kill() end)
local placeButton = Widgets.button(panel, { x = PAD + buttonW + 8, y = buttonY, w = buttonW, h = BUTTON_H },
    function() return pending and "Loading..." or "Place" end, function() convert() end)
Widgets.popupBelow(placeButton, "Shows the map in the world: pick the region to\nconvert and where the map sits, then Convert there")
