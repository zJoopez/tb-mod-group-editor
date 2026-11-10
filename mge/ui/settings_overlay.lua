-- Settings overlay, opened by the toolbar's settings button (ui/main.lua):
--   Camera follow: the camera looks at the selection when selecting and moving (MGE.Camera.followMoves)
--   Gizmo snapping: the steps a gizmo drag snaps to while Ctrl is held (Gizmo.moveStep / rotateStep /
--                   scaleStep). A typed step applies on Enter or when the overlay closes, an invalid
--                   one goes back to the current step
--   Shortcuts:      heading with a "?", hovering it lists the keyboard and mouse shortcuts
-- Kept while the script runs, not saved. Clicking outside the panel, Close or Esc closes it, MGE.quit
-- closes it too (MGE.settingsOverlay).
if MGE.settingsOverlay and not MGE.settingsOverlay.destroyed then return end

local Widgets = MGE.Widgets
local Rows = MGE.EditorRows
local Camera = MGE.Camera
local Gizmo = MGE.Gizmo

---@class MgeSetting
---@field label string
---@field info string small line under the row
---@field get fun(): boolean
---@field set fun(on: boolean)

---@type MgeSetting[]
local SETTINGS = {
    {
        label = "Camera follow",
        info = "Camera looks at the selection, or the picked player",
        get = function() return Camera.followMoves end,
        set = function(on) Camera.followMoves = on end,
    },
}

---@class MgeSnapStep
---@field label string
---@field key "moveStep"|"rotateStep"|"scaleStep" field on Gizmo
---@field min number smallest step accepted, exclusive
---@field max number largest step accepted

---@type MgeSnapStep[]
local SNAP_STEPS = {
    { label = "Move step", key = "moveStep", min = 0, max = 100 },
    { label = "Rotate step", key = "rotateStep", min = 0, max = 180 },
    { label = "Scale step", key = "scaleStep", min = 0, max = 10 },
}
local SNAP_INFO = "Hold Ctrl while dragging. Move: units, rotate: degrees"

-- shortcut list, shown by the "?" next to the Shortcuts heading (the toolbar used to have it)
local SHORTCUTS = table.concat({
    "F1: show / hide window",
    "Esc: close the open prompt / popup / settings",
    "Ctrl + S: save   Ctrl + Shift + S: rename",
    "Ctrl + A: select / deselect all (players on the Players list)",
    "Click object, id or player: select it, Shift + click: add / remove",
    "Ctrl + N / D: new / duplicate selected (players on the Players list)",
    "Delete: delete selected, objects or players (asks first)",
    "Shift + Z / Y: undo / redo",
    "Enter: apply the typed field",
    "Click Pos / Rot / Scale: switch to Move / Rotate / Resize",
    "Shift + Q / W / E: Move / Rotate / Scale gizmo on / off",
    "Ctrl while dragging the gizmo: snap steps (above)",
    "Drag (off the gizmo) / wheel: orbit / zoom camera",
}, "\n")

local PANEL_W = 340
local PAD = 12
local TITLE_H = 44
local ROW_H = 28
local ROW_GAP = 4
local SETTING_H = ROW_H + Widgets.INFO_HEIGHT + 8 -- row, info line, gap
local SECTION_H = 26 -- section heading
local SNAP_H = SECTION_H + #SNAP_STEPS * (ROW_H + ROW_GAP) + Widgets.INFO_HEIGHT + 8
local SHORTCUTS_H = SECTION_H + 4
local CLOSE_H = 28
local LABEL_W = 150
local panelH = TITLE_H + #SETTINGS * SETTING_H + SNAP_H + SHORTCUTS_H + CLOSE_H + PAD * 2

local overlay = TBMenu:spawnWindowOverlay(true) -- true: a click on the dark background closes it
MGE.settingsOverlay = overlay

---@type { step: MgeSnapStep, input: UIElement }[]
local snapInputs = {}

---Step as the field shows it, 0.1 not 0.10000000000000001
---@param value number
---@return string
local function formatStep(value)
    return string.format("%g", value)
end

---@param step MgeSnapStep
---@return number
local function currentStep(step)
    return Gizmo[step.key] --[[@as number]]
end

---Applies a typed step, or puts the current step back in the field when the text isn't a valid one
---@param entry { step: MgeSnapStep, input: UIElement }
local function applySnap(entry)
    local step, input = entry.step, entry.input
    if input.destroyed then return end
    local value = tonumber(input.textfieldstr[1])
    if value and value > step.min and value <= step.max then
        Gizmo[step.key] = value
    end
    local text = formatStep(currentStep(step))
    input.textfieldstr[1] = text
    input.textfieldindex = #text
end

local defaultKillAction = overlay.killAction
overlay.killAction = function()
    for _, entry in ipairs(snapInputs) do applySnap(entry) end -- typed but not entered still counts
    if defaultKillAction then defaultKillAction() end
    Widgets.releaseKeyboard(overlay) -- the step fields would otherwise stay in toriui's keyboard list
    if MGE then MGE.settingsOverlay = nil end
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
title:addAdaptedText(true, "Settings", nil, nil, FONTS.BIG, nil, 0.65)

---Row inside the panel: label on the left, returns the space right of it for buttons or a field
---@param y number
---@param label string
---@return UIElement content
local function addRow(y, label)
    local row = panel:addChild({
        pos = { PAD, y },
        size = { PANEL_W - PAD * 2, ROW_H },
    })
    local labelElement = row:addChild({
        pos = { 0, 0 },
        size = { LABEL_W, ROW_H },
    })
    labelElement:addAdaptedText(label, nil, nil, nil, LEFTMID, Widgets.TEXT_SCALE)
    return row:addChild({
        pos = { LABEL_W, 0 },
        size = { row.size.w - LABEL_W, ROW_H },
        interactive = true,
    })
end

---Small centered line (row explanations)
---@param y number
---@param text string
local function addInfo(y, text)
    local info = panel:addChild({
        pos = { PAD, y },
        size = { PANEL_W - PAD * 2, Widgets.INFO_HEIGHT },
    })
    Widgets.infoText(info, text)
end

---@type { setting: MgeSetting, on: UIElement, off: UIElement }[]
local toggles = {}

---On / Off buttons show each setting's current value
local function refresh()
    for _, t in ipairs(toggles) do
        local on = t.setting.get()
        for btn, value in pairs({ [t.on] = true, [t.off] = false }) do
            if not btn.destroyed then
                btn.bgColor = on == value and TB_MENU_DEFAULT_LIGHTER_COLOR or Widgets.STYLE.bg
            end
        end
    end
end

local y = TITLE_H
for _, setting in ipairs(SETTINGS) do
    local content = addRow(y, setting.label)
    local created = Widgets.buttonRow(content, 0, ROW_H, {
        { label = "On", onClick = function() setting.set(true) refresh() end },
        { label = "Off", onClick = function() setting.set(false) refresh() end },
    }, 4)
    table.insert(toggles, { setting = setting, on = created[1], off = created[2] })
    addInfo(y + ROW_H + 2, setting.info)
    y = y + SETTING_H
end

-- gizmo snapping: one number field per step, filled with the current step
local heading = panel:addChild({
    pos = { PAD, y },
    size = { PANEL_W - PAD * 2, SECTION_H },
})
heading:addAdaptedText("Gizmo snapping", nil, nil, nil, CENTERMID, Widgets.TEXT_SCALE)
y = y + SECTION_H
for _, step in ipairs(SNAP_STEPS) do
    local content = addRow(y, step.label)
    local entry = { step = step }
    entry.input = Rows.createInput(content, function() applySnap(entry) end, formatStep(currentStep(step)))
    Widgets.closeOnEscape(entry.input) -- Esc while typing a step closes too (applies it, like Close)
    table.insert(snapInputs, entry)
    applySnap(entry) -- fills the field with the current step
    y = y + ROW_H + ROW_GAP
end
addInfo(y, SNAP_INFO)
y = y + Widgets.INFO_HEIGHT + 8

-- Shortcuts heading with the "?" right after the text, hovering it lists them. Heading and icon are
-- centered together: the text is measured the way the game's help popups measure theirs
local HELP_SIZE = 22 -- same as the editor rows' "?" (ui/editor_rows.lua)
local HELP_GAP = 6
-- the heading area is one icon (and gap) narrower than the row, so its centered text sits half that
-- left of the panel's center and the icon fits after it. Not moved left with moveTo: a negative x
-- counts from the parent's right edge in toriui
local shortcutsHeading = panel:addChild({
    pos = { PAD, y },
    size = { PANEL_W - PAD * 2 - (HELP_SIZE + HELP_GAP), SECTION_H },
})
shortcutsHeading:addAdaptedText("Shortcuts", nil, nil, nil, CENTERMID, Widgets.TEXT_SCALE)
local headingW = get_string_length(shortcutsHeading.dispstr and shortcutsHeading.dispstr[1] or "Shortcuts",
    shortcutsHeading.textFont) * (shortcutsHeading.textScale or 1)
Widgets.helpIcon(panel, (PANEL_W + headingW - HELP_SIZE - HELP_GAP) / 2 + HELP_GAP, y + (SECTION_H - HELP_SIZE) / 2,
    HELP_SIZE, SHORTCUTS)
y = y + SECTION_H

Widgets.button(panel, { x = PAD, y = panelH - PAD - CLOSE_H, w = PANEL_W - PAD * 2, h = CLOSE_H }, "Close",
    function() overlay:kill() end)

refresh()
