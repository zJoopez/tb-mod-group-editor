-- Convert Map overlay, opened by the Advanced tab's Map row (ui/editor_advanced.lua): the settings of
-- a map conversion (.vmf, or a compiled Source .bsp from assets/maps; mapconv/*.lua). Place (or Enter
-- in a field) goes on to the placement view (ui/map_place.lua), where the region to convert and where
-- the map sits are picked with the gizmo, and its Convert adds the boxes like an import, in one undo
-- step. The view's Settings button comes back here. The Map button opens the file picker over it.
-- Empty fields use the converter's defaults (shown as placeholders). Typed values, the picked map and
-- each map's placement are kept while the script runs. Clicking outside, Cancel or Esc closes it,
-- MGE.quit too (MGE.mapOverlay). Same converter as tools/mapconv.lua, plan: docs/map-import-plan.md
if MGE.mapOverlay and not MGE.mapOverlay.destroyed then return end

local Widgets = MGE.Widgets
local Rows = MGE.EditorRows
local ModData = MGE.ModData
local MapConv = MGE.loadMapConv() -- already loaded by the Map row, a no-op then
local DEFAULTS = MapConv.DEFAULTS

local MAPS_DIR = MGE.scriptPath .. "assets/maps" -- under data/script, like the object assets
local RUN_HOOK = MGE.hookname .. "_mapconv" -- one-shot draw2d hook that runs the conversion

---@class MapOverlayState kept while the script runs
---@field path string? picked map, relative to MAPS_DIR
---@field texts table<string, string> typed field texts by field key
---@field clips boolean
---@field terrain boolean
---@field placements table<string, MapPlacement> where each map was placed last, by path
---@field floorsFirst boolean? the placement view's budget order toggles, nil: the converter's default
---@field centerFirst boolean?
---@field simplify boolean? the placement view's Simplify toggle
---@field dropCovered boolean? the placement view's Covered toggle
---@field cache { key: string, map: MapFile, pieces: MapConvPiece[], report: MapConvReport }? see loadPieces
MapConv.overlayState = MapConv.overlayState or
    { texts = {}, clips = DEFAULTS.clips, terrain = DEFAULTS.terrain, placements = {} }
local state = MapConv.overlayState --[[@as MapOverlayState]]
state.placements = state.placements or {}

---@class MapPlacement picked in the placement view, map units and degrees
---@field region { min: number[], max: number[] }
---@field anchor number[]
---@field yaw number
---@field lift number world units the lowest point sits above the ground

---@return integer object ids free in the mod
local function freeIds()
    return #ModData.freeIds.static + #ModData.freeIds.nonStatic
end

---@class MapOverlayField
---@field label string
---@field keys string[] one per input, keys of state.texts
---@field hints string[] placeholders
---@field info string? hover text

---@type MapOverlayField[]
local FIELDS = {
    { label = "Scale", keys = { "scale" }, hints = { tostring(DEFAULTS.scale) },
        info = "Toribash units per map unit.\nSource: a player is 72 units, a tori about 2.5." },
    { label = "Budget", keys = { "budget" }, hints = { tostring(freeIds()) },
        info = "Most boxes added as objects, the biggest surfaces\nfirst. Empty: all " .. freeIds() ..
            " object ids free in this mod.\n0: only parked boxes, the object ids stay free." },
    { label = "Parked", keys = { "parked" }, hints = { "0" },
        info = "Boxes after the Budget's that are parked (drawn\nonly, no collisions, Advanced > Export atmo), " ..
            "the\nsmaller ones. Up to " .. MGE.Parking.room() .. ". Empty: none." },
    { label = "Min size", keys = { "minSize" }, hints = { tostring(DEFAULTS.minSize) },
        info = "Brushes smaller than this on every side are\nleft out (trims, details). Map units." },
    { label = "Terrain tol.", keys = { "terrainTolerance" }, hints = { tostring(DEFAULTS.terrainTolerance) },
        info = "How bumpy one terrain slab may be, map units.\nBigger: fewer boxes (dust2 B site fits at 16)." },
    { label = "Simplify tol.", keys = { "simplifyTolerance" }, hints = { tostring(DEFAULTS.simplifyTolerance) },
        info = "Simplify: how much thicker joined floor tiles and\nstrips may get (bumps, tilt), map units." },
}

local PANEL_W = 420
local PAD = 12
local TITLE_H = 44
local ROW_H = 28
local ROW_GAP = 4
local LABEL_W = 110
local HELP_SIZE = 22
local BUTTON_H = 32
local ROWS = 1 + #FIELDS + 2 -- Map, fields, Terrain and Clips
local panelH = TITLE_H + ROWS * (ROW_H + ROW_GAP) + Widgets.INFO_HEIGHT * 2 + 8 + BUTTON_H + PAD * 2

local overlay = TBMenu:spawnWindowOverlay(true) -- true: a click on the dark background closes it
MGE.mapOverlay = overlay

---@type table<string, UIElement> inputs by field key
local inputs = {}

local defaultKillAction = overlay.killAction
overlay.killAction = function()
    for key, input in pairs(inputs) do
        if not input.destroyed then state.texts[key] = input.textfieldstr[1] end
    end
    remove_hooks(RUN_HOOK) -- a conversion waiting to run is dropped with the overlay
    if defaultKillAction then defaultKillAction() end
    Widgets.releaseKeyboard(overlay) -- the fields would otherwise stay in toriui's keyboard list
    if MGE then MGE.mapOverlay = nil end
end

local panel = overlay:addChild({
    pos = { (WIN_W - PANEL_W) / 2, (WIN_H - panelH) / 2 },
    size = { PANEL_W, panelH },
    bgColor = TB_MENU_DEFAULT_BG_COLOR,
    shapeType = ROUNDED,
    rounded = 5,
    interactive = true, -- clicks on the panel don't reach the background's close handler
})

local title = panel:addChild({
    pos = { PAD, 0 },
    size = { PANEL_W - PAD * 2, TITLE_H },
})
title:addAdaptedText(true, "Convert Map", nil, nil, FONTS.BIG, nil, 0.65)

---Row inside the panel: label on the left, "?" on the right when there's help, returns the space
---between them
---@param y number
---@param label string
---@param help string?
---@return UIElement content
local function addRow(y, label, help)
    local row = panel:addChild({
        pos = { PAD, y },
        size = { PANEL_W - PAD * 2, ROW_H },
    })
    local labelElement = row:addChild({
        pos = { 0, 0 },
        size = { LABEL_W, ROW_H },
    })
    labelElement:addAdaptedText(label, nil, nil, nil, LEFTMID, Widgets.TEXT_SCALE)
    local helpW = help and HELP_SIZE + 6 or 0
    if help then Widgets.helpIcon(row, row.size.w - HELP_SIZE, (ROW_H - HELP_SIZE) / 2, HELP_SIZE, help) end
    return row:addChild({
        pos = { LABEL_W, 0 },
        size = { row.size.w - LABEL_W - helpW, ROW_H },
        interactive = true,
    })
end

local y = TITLE_H

-- Map: picked file, the button opens the picker over this overlay
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

local convert -- defined below, Enter in a field goes on to the placement view

for _, field in ipairs(FIELDS) do
    local content = addRow(y, field.label, field.info)
    local gap = 4
    local w = (content.size.w - gap * (#field.keys - 1)) / #field.keys
    for i, key in ipairs(field.keys) do
        local holder = content:addChild({
            pos = { (i - 1) * (w + gap), 0 },
            size = { w, ROW_H },
        })
        local input = Rows.createInput(holder, function() convert() end, field.hints[i])
        Widgets.closeOnEscape(input)
        local text = state.texts[key] or ""
        input.textfieldstr[1] = text
        input.textfieldindex = #text
        inputs[key] = input
    end
    y = y + ROW_H + ROW_GAP
end

---On / Off pair for a state flag, the current one lit
---@param label string
---@param key "clips"|"terrain"
---@param help string
local function addToggle(label, key, help)
    local content = addRow(y, label, help)
    local buttons
    local function refresh()
        for i, btn in ipairs(buttons) do
            if not btn.destroyed then
                btn.bgColor = (state[key] == (i == 1)) and TB_MENU_DEFAULT_LIGHTER_COLOR or Widgets.PANEL_STYLE.bg
            end
        end
    end
    buttons = Widgets.buttonRow(content, 0, ROW_H, {
        { label = "On", onClick = function() state[key] = true refresh() end },
        { label = "Off", onClick = function() state[key] = false refresh() end },
    }, 4, nil, Widgets.PANEL_STYLE)
    refresh()
    y = y + ROW_H + ROW_GAP
end
addToggle("Terrain", "terrain","Terrain of compiled maps (.bsp displacements),\n" ..
    "dust2's ground: slabs under it, neighbours joined.")
addToggle("Clips", "clips", "Player clips: the map's invisible walls, ramps\nover stairs, smoothed corners. Colored like\n" ..
    "what they cover. The big lids under the sky\nare left out.")

local info = panel:addChild({
    pos = { PAD, y + 4 },
    size = { PANEL_W - PAD * 2, Widgets.INFO_HEIGHT * 2 },
})
local function setInfo(text) Widgets.infoText(info, text) end
setInfo("Map units: Source uses inches. Empty fields use the hints.")

---@param key string
---@return number? typed number, nil when empty
---@return boolean ok false when text is there but isn't a number
local function typed(key)
    local text = inputs[key] and not inputs[key].destroyed and inputs[key].textfieldstr[1] or ""
    if text:match("^%s*$") then return nil, true end
    local value = tonumber(text)
    return value, value ~= nil
end

---Options from the fields, or the reason they can't be used
---@return MapConvOptions? options
---@return string? error
local function readOptions()
    local options = { clips = state.clips, terrain = state.terrain, source = state.path }
    -- the placement view's budget order toggles, kept from its last use
    if state.floorsFirst ~= nil then options.floorsFirst = state.floorsFirst end
    if state.centerFirst ~= nil then options.centerFirst = state.centerFirst end
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
    local free, room = freeIds(), MGE.Parking.room()
    -- objects first, then the parked ones (Assets.addObjects' parkExcess: the boxes after objectBudget)
    budget = math.floor(budget or free) -- empty: every free object id, 0: only parked boxes
    if budget < 0 or budget > free then return nil, "Budget must be 0-" .. free .. " (free object ids)" end
    local parked = math.floor(typed("parked") or 0) -- empty: none
    if parked < 0 or parked > room then return nil, "Parked must be 0-" .. room .. " (" .. MGE.Parking.maxParked .. " at most)" end
    if budget + parked < 1 then return nil, "Budget and Parked are both 0" end
    options.scale, options.budget, options.minSize = scale, budget + parked, minSize
    options.objectBudget = budget
    -- region, anchor and yaw are picked in the placement view
    return options
end

---Field text for a number: scale to 0.0001, no trailing zeros
---@param value number
---@param decimals integer
---@return string
local function fieldText(value, decimals)
    local s = string.format("%." .. decimals .. "f", value):gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end

---The map's pieces (MapConv.pieces): read and built once per map and the options they depend on,
---kept while the script runs, so placing again and converting don't redo them. Only the entities of
---the map itself are kept (the anchor), its brushes and terrain grids are big
---@param options MapConvOptions
---@return { key: string, map: MapFile, pieces: MapConvPiece[], report: MapConvReport }? cache
---@return string? error
local function loadPieces(options)
    local opts = MapConv.withDefaults(options)
    local key = table.concat({ state.path, tostring(opts.terrain), opts.terrainTolerance, tostring(opts.clips),
        opts.slabThickness, opts.slabError }, "|")
    if state.cache and state.cache.key == key then return state.cache end
    -- io.open, not Files: a .bsp is read in parts (dust2 is 325 MB, 9 MB of it is used). Desktop only,
    -- like the rest of MGE. The game's io.open starts at data/script
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

---Opens the overlay again (the placement view's Settings button, Esc)
local function reopen()
    if MGE and not MGE.mapOverlay then dofile(MGE.scriptPath .. "ui/map_overlay.lua") end
end

---Place: closes the overlay and opens the placement view (ui/map_place.lua) for the map. It starts
---where this map was placed last, else around the anchor entity (a T spawn) with a 1000 x 1000 unit
---region. Its Convert adds the boxes, its Settings comes back here; both keep the placement
---@param options MapConvOptions
local function place(options)
    local cache, err = loadPieces(options)
    if not cache then
        setInfo(err or "")
        return
    end
    local path = state.path --[[@as string]]
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
    ---Keeps what the view picked: the placement for this map, the scale in the Scale field
    ---@param p MapPlaced
    local function keep(p)
        state.placements[path] = { region = p.region, anchor = p.anchor, yaw = p.yaw, lift = p.lift }
        state.texts.scale = fieldText(p.scale, 4)
        -- for every map
        state.floorsFirst, state.centerFirst, state.simplify = p.floorsFirst, p.centerFirst, p.simplify
        state.dropCovered = p.dropCovered
    end
    overlay:kill()
    if not MGE.MapPlace then dofile(MGE.scriptPath .. "ui/map_place.lua") end
    MGE.MapPlace.start({
        pieces = cache.pieces,
        report = cache.report,
        options = opts,
        region = region,
        anchor = { anchor[1], anchor[2], anchor[3] }, -- the view sets its height (ground)
        lift = lift or 0,
        onConvert = function(p)
            keep(p)
            local convertOptions = {}
            for k, v in pairs(opts) do convertOptions[k] = v end
            convertOptions.region, convertOptions.anchor, convertOptions.yaw, convertOptions.scale = p.region, p.anchor, p.yaw, p.scale
            local result = MapConv.convert(cache.map, convertOptions, cache.pieces, cache.report)
            if #result.objects == 0 then return nil, "No boxes in the region" end
            -- run by the view once it's closed and MGE's window is shown again
            return function()
                -- new ids, selected, one undo step, kept in place. The boxes after objectBudget (the
                -- smallest, the converter's order) are parked
                MGE.Assets.addObjects(result.objects, false, false, nil, opts.objectBudget or true)
                for _, line in ipairs(MapConv.reportLines(result.report)) do echo("^04[MGE] " .. line) end
            end
        end,
        onSettings = function(p)
            keep(p)
            reopen()
        end,
    })
end

local pending -- label of the action waiting for the next frames, see defer

---Runs action a frame later, after the info line says what's happening: reading a big map pauses
---the game. A hook of its own, not the panel's draw: the action closes the overlay, which shouldn't
---happen while toriui is drawing it. Removed after running, or by the overlay's killAction
---@param label string
---@param action fun(options: MapConvOptions)
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
        if frames < 2 then return end -- the info line is drawn once first
        remove_hook("draw2d", RUN_HOOK)
        pending = nil
        if not overlay.destroyed then action(options) end
    end)
end

convert = function() defer("Loading", place) end -- Enter in a field: on to the placement view

local buttonW = (PANEL_W - PAD * 2 - 8) / 2
local buttonY = panelH - PAD - BUTTON_H
Widgets.button(panel, { x = PAD, y = buttonY, w = buttonW, h = BUTTON_H }, "Cancel", function() overlay:kill() end)
local placeButton = Widgets.button(panel, { x = PAD + buttonW + 8, y = buttonY, w = buttonW, h = BUTTON_H },
    function() return pending and "Loading..." or "Place" end, function() convert() end)
TBMenu:displayPopup(placeButton, "Shows the map in the world: pick the region to\nconvert and where the map sits, then Convert there")
