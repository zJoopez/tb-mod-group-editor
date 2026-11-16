












if MGE.settingsOverlay and not MGE.settingsOverlay.destroyed then return end

local Widgets = MGE.Widgets
local Rows = MGE.EditorRows
local Camera = MGE.Camera







local SETTINGS = {
    {
        label = "Camera follow",

        get = function() return Camera.followMoves end,
        set = function(on) Camera.followMoves = on end,
    },
}













local Config = MGE.Config



local function stepField(label, key, max)
    return { label = label, min = 0, max = max, get = function() return Config[key] end, set = function(v) Config[key] = v end }
end


local SNAP_STEPS = {
    stepField("Step", "wheelStep", 1000),
    stepField("Shift step", "wheelFineStep", 1000),
    stepField("Rotate step", "rotateStep", 180),
}
local SNAP_INFO = "Wheel over a number field, or Ctrl while\ndragging the gizmo. Hold Shift for the\n" ..
    "Shift step (rotation: 1 degree)."



local AtmoLayer = MGE.AtmoLayer

local ATMO_FIELDS = {
    { label = "Max atmo objects", min = 0, minInclusive = true, max = 100000, whole = true,
        get = function() return AtmoLayer.maxAtmo end, set = function(v) AtmoLayer.maxAtmo = v end },
}
local ATMO_INFO = "How many objects the atmo holds. MGE draws every one,\n" ..
    "but the game draws only so many shapes a frame:\nlower graphics settings draw more. Above 256 you may\n" ..
    "need lower graphics to see them all."


local SHORTCUTS = table.concat({
    "F1: show / hide window",
    "Esc: close the open prompt / popup / settings",
    "Ctrl + S: save   Ctrl + Shift + S: rename",
    "Ctrl + A: select / deselect all (of the shown list)",
    "Click object, id, joint or player: select it, Shift + click: add / remove",
    "Ctrl + N / D: new / duplicate selected (of the shown list)",
    "Delete: delete selected, of the shown list (asks first)",
    "Shift + Z / Y: undo / redo",
    "Number fields apply when you leave them (or Enter), Esc drops the typing",
    "Wheel over a number field: + / - the step, Shift: the Shift step (one undo step a scroll)",
    "Alt + Q / W / E: Move / Rotate / Scale gizmo on / off",
    "Ctrl while dragging the gizmo: snap to the steps, Ctrl + Shift: the Shift step",
    "Drag (off the gizmo) / wheel: orbit / zoom camera",
    "Shift + drag: box select what shows, Ctrl + Shift + drag: everything inside",
}, "\n")

local px = Widgets.px
local PANEL_W = px(340)
local PAD = px(12)
local TITLE_H = px(44)
local ROW_H = Widgets.ROW_H
local ROW_GAP = px(4)
local SETTING_H = ROW_H + ROW_GAP
local SECTION_H = px(26)
local SNAP_H = SECTION_H + #SNAP_STEPS * SETTING_H
local ATMO_H = SECTION_H + #ATMO_FIELDS * SETTING_H
local SHORTCUTS_H = SECTION_H + px(4)
local CLOSE_H = Widgets.ROW_H
local LABEL_W = px(150)
local panelH = TITLE_H + (#SETTINGS + 1) * SETTING_H + SNAP_H + ATMO_H + SHORTCUTS_H + CLOSE_H + PAD * 2

local overlay = TBMenu:spawnWindowOverlay(true)
MGE.settingsOverlay = overlay


local numberInputs = {}




local function formatStep(value)
    return string.format("%g", value)
end



local function applySnap(entry)
    local step, input = entry.step, entry.input


    if not input.textfieldstr then return end
    local value = tonumber(input.textfieldstr[1])
    if value and step.whole then value = math.floor(value) end
    local aboveMin = value and (step.minInclusive and value >= step.min or value > step.min)
    if aboveMin and value <= step.max then step.set(value) end
    local text = formatStep(step.get())
    input.textfieldstr[1] = text
    input.textfieldindex = #text
end

local defaultKillAction = overlay.killAction
overlay.killAction = function()
    for _, entry in ipairs(numberInputs) do applySnap(entry) end
    if MGE and MGE.Config then MGE.Config.save() end
    if defaultKillAction then defaultKillAction() end
    Widgets.releaseKeyboard(overlay)
    if MGE then MGE.settingsOverlay = nil end
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
title:addAdaptedText(true, "Settings", nil, nil, Widgets.FONT, nil, Widgets.TITLE_SCALE)


local HELP_SIZE = ROW_H - px(6)
local HELP_GAP = px(6)







local function addRow(y, label, help)
    local row = panel:addChild({
        pos = { PAD, y },
        size = { PANEL_W - PAD * 2, ROW_H },
    })
    local labelElement = row:addChild({
        pos = { 0, 0 },
        size = { LABEL_W - (help and HELP_SIZE + HELP_GAP or 0), ROW_H },
    })
    labelElement:addAdaptedText(label, nil, nil, Widgets.FONT, LEFTMID, Widgets.TEXT_SCALE)
    if help then
        Widgets.helpIcon(row, LABEL_W - HELP_GAP - HELP_SIZE, (ROW_H - HELP_SIZE) / 2, HELP_SIZE, help)
    end
    return row:addChild({
        pos = { LABEL_W, 0 },
        size = { row.size.w - LABEL_W, ROW_H },
        interactive = true,
    })
end









local function addHelpHeading(y, text, help)
    local heading = panel:addChild({
        pos = { PAD, y },
        size = { PANEL_W - PAD * 2 - (HELP_SIZE + HELP_GAP), SECTION_H },
    })
    heading:addAdaptedText(text, nil, nil, Widgets.FONT, CENTERMID, Widgets.TEXT_SCALE)
    local textW = get_string_length(heading.dispstr and heading.dispstr[1] or text, heading.textFont)
        * (heading.textScale or 1)
    Widgets.helpIcon(panel, (PANEL_W + textW - HELP_SIZE - HELP_GAP) / 2 + HELP_GAP, y + (SECTION_H - HELP_SIZE) / 2,
        HELP_SIZE, help)
end


local toggles = {}


local function refresh()
    for _, t in ipairs(toggles) do
        local on = t.setting.get()
        for btn, value in pairs({ [t.on] = true, [t.off] = false }) do
            if not btn.destroyed then
                btn.bgColor = on == value and Widgets.ACTIVE_COLOR or Widgets.STYLE.bg
            end
        end
    end
end

local y = TITLE_H




do
    local content = addRow(y, "UI size")
    local items = {}
    for i, scale in ipairs(Widgets.UI_SCALES) do
        items[i] = { label = math.floor(scale * 100 + 0.5) .. "%", onClick = function()
            if scale == Widgets.UI_SCALE then return end
            MGE_UI_SCALE = scale
            MGE.Config.save()
            local entry = MGE.scriptPath:gsub("mge/$", "") .. "mge.lua"
            MGE.say("UI size " .. items[i].label .. ", restarting MGE")
            pcall(MGE.quit)

            add_hook("draw2d", "mge_restart", function()
                remove_hooks("mge_restart")
                dofile(entry)
            end)
        end }
    end
    local buttons = Widgets.buttonRow(content, 0, ROW_H, items, Widgets.GAP)
    for i, scale in ipairs(Widgets.UI_SCALES) do
        if scale == Widgets.UI_SCALE then buttons[i].bgColor = Widgets.ACTIVE_COLOR end
    end
    y = y + SETTING_H
end

for _, setting in ipairs(SETTINGS) do
    local content = addRow(y, setting.label)
    local created = Widgets.buttonRow(content, 0, ROW_H, {
        { label = "On", onClick = function() setting.set(true) refresh() end },
        { label = "Off", onClick = function() setting.set(false) refresh() end },
    }, Widgets.GAP)
    table.insert(toggles, { setting = setting, on = created[1], off = created[2] })
    y = y + SETTING_H
end






local function addNumberSection(name, fields, infoText)
    if infoText then
        addHelpHeading(y, name, infoText)
    else
        local heading = panel:addChild({
            pos = { PAD, y },
            size = { PANEL_W - PAD * 2, SECTION_H },
        })
        heading:addAdaptedText(name, nil, nil, Widgets.FONT, CENTERMID, Widgets.TEXT_SCALE)
    end
    y = y + SECTION_H
    for _, step in ipairs(fields) do
        local content = addRow(y, step.label)
        local entry = { step = step }

        entry.input = Rows.createInput(content, function() applySnap(entry) end, formatStep(step.get()),
            { mode = "keep", whole = step.whole })
        Widgets.closeOnEscape(entry.input)
        table.insert(numberInputs, entry)
        applySnap(entry)
        y = y + SETTING_H
    end
end

addNumberSection("Snapping", SNAP_STEPS, SNAP_INFO)
addNumberSection("Atmo objects", ATMO_FIELDS, ATMO_INFO)


addHelpHeading(y, "Shortcuts", SHORTCUTS)
y = y + SECTION_H

Widgets.button(panel, { x = PAD, y = panelH - PAD - CLOSE_H, w = PANEL_W - PAD * 2, h = CLOSE_H }, "Close",
    function() overlay:kill() end)

refresh()
