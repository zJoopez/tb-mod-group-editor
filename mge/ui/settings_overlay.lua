-- Settings overlay, opened by the toolbar's settings button (ui/main.lua):
--   Camera follow: the camera looks at the selection when selecting and moving (MGE.Camera.followMoves)
--   Gizmo snapping: the steps a gizmo drag snaps to while Ctrl is held (Gizmo.moveStep / rotateStep /
--                   scaleStep). A typed step applies on Enter or when the overlay closes, an invalid
--                   one goes back to the current step
--   Atmo objects:   the atmo's size (AtmoLayer.maxAtmo), every one is drawn: the game's graphics
--                   settings set how many shapes it draws a frame. Typed like the steps
--   Shortcuts:      heading with a "?", hovering it lists the keyboard and mouse shortcuts
-- Every row explains itself on the "?" at its end, like the editor rows
--   UI size:        MGE's overall size (Widgets.UI_SCALE), restarts MGE to apply it
-- Saved in MGE's config file when the overlay closes (utils/config.lua), the UI size when it's picked.
-- Clicking outside the panel, Close or Esc closes it, MGE.quit closes it too (MGE.settingsOverlay).
if MGE.settingsOverlay and not MGE.settingsOverlay.destroyed then return end

local Widgets = MGE.Widgets
local Rows = MGE.EditorRows
local Camera = MGE.Camera
local Gizmo = MGE.Gizmo

---@class MgeSetting
---@field label string
---@field get fun(): boolean
---@field set fun(on: boolean)

---@type MgeSetting[]
local SETTINGS = {
    {
        label = "Camera follow",
        -- the camera looks at the selection, or the picked player
        get = function() return Camera.followMoves end,
        set = function(on) Camera.followMoves = on end,
    },
}

---@class MgeNumberSetting a typed number: applied on Enter or when the overlay closes, an invalid one
---goes back to the current value
---@field label string
---@field get fun(): number
---@field set fun(value: number)
---@field min number smallest value accepted (exclusive unless minInclusive)
---@field minInclusive boolean?
---@field max number largest value accepted
---@field whole boolean? rounded down to a whole number

---@param key "moveStep"|"rotateStep"|"scaleStep" field on Gizmo
local function gizmoField(label, key, max)
    return { label = label, min = 0, max = max, get = function() return Gizmo[key] end, set = function(v) Gizmo[key] = v end }
end

---@type MgeNumberSetting[]
local SNAP_STEPS = {
    gizmoField("Move step", "moveStep", 100),
    gizmoField("Rotate step", "rotateStep", 180),
    gizmoField("Scale step", "scaleStep", 10),
}
local SNAP_INFO = "Hold Ctrl while dragging. Move: units, rotate: degrees"

-- atmo objects (utils/atmo_layer.lua): the atmo's size. MGE draws every one, the game draws only so
-- many shapes a frame, how many depends on its graphics settings (lowest: 10 000)
local AtmoLayer = MGE.AtmoLayer
---@type MgeNumberSetting[]
local ATMO_FIELDS = {
    { label = "Max atmo objects", min = 0, minInclusive = true, max = 100000, whole = true,
        get = function() return AtmoLayer.maxAtmo end, set = function(v) AtmoLayer.maxAtmo = v end },
}
-- (all are drawn: above 256, lower graphics settings may be needed to see them all)

-- shortcut list, shown by the "?" next to the Shortcuts heading (the toolbar used to have it)
local SHORTCUTS = table.concat({
    "F1: show / hide window",
    "Esc: close the open prompt / popup / settings",
    "Ctrl + S: save   Ctrl + Shift + S: rename",
    "Ctrl + A: select / deselect all (of the shown list)",
    "Click object, id, joint or player: select it, Shift + click: add / remove",
    "Ctrl + N / D: new / duplicate selected (of the shown list)",
    "Delete: delete selected, of the shown list (asks first)",
    "Shift + Z / Y: undo / redo",
    "Enter: apply the typed field",
    "Click Pos / Rot / Scale: switch to Move / Rotate / Resize",
    "Alt + Q / W / E: Move / Rotate / Scale gizmo on / off",
    "Ctrl while dragging the gizmo: snap steps (above)",
    "Drag (off the gizmo) / wheel: orbit / zoom camera",
    "Shift + drag: box select what shows, Ctrl + Shift + drag: everything inside",
}, "\n")

local px = Widgets.px -- MGE's overall size (Widgets.UI_SCALE)
local PANEL_W = px(340)
local PAD = px(12)
local TITLE_H = px(44)
local ROW_H = Widgets.ROW_H
local ROW_GAP = px(4)
local SETTING_H = ROW_H + ROW_GAP -- a row, its explanation is its "?" (like the editor rows)
local SECTION_H = px(26) -- section heading
local SNAP_H = SECTION_H + #SNAP_STEPS * SETTING_H
local ATMO_H = SECTION_H + #ATMO_FIELDS * SETTING_H
local SHORTCUTS_H = SECTION_H + px(4)
local CLOSE_H = Widgets.ROW_H
local LABEL_W = px(150)
local panelH = TITLE_H + (#SETTINGS + 1) * SETTING_H + SNAP_H + ATMO_H + SHORTCUTS_H + CLOSE_H + PAD * 2 -- + UI size

local overlay = TBMenu:spawnWindowOverlay(true) -- true: a click on the dark background closes it
MGE.settingsOverlay = overlay

---@type { step: MgeNumberSetting, input: UIElement }[] every number field
local numberInputs = {}

---Value as the field shows it, 0.1 not 0.10000000000000001
---@param value number
---@return string
local function formatStep(value)
    return string.format("%g", value)
end

---Applies a typed value, or puts the current one back in the field when the text isn't a valid one
---@param entry { step: MgeNumberSetting, input: UIElement }
local function applySnap(entry)
    local step, input = entry.step, entry.input
    -- not skipped once destroyed: UIElement:kill destroys the fields before the overlay's killAction
    -- (which applies them) runs, their text is still there
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
    for _, entry in ipairs(numberInputs) do applySnap(entry) end -- typed but not entered still counts
    if MGE and MGE.Config then MGE.Config.save() end -- kept for the next game session
    if defaultKillAction then defaultKillAction() end
    Widgets.releaseKeyboard(overlay) -- the step fields would otherwise stay in toriui's keyboard list
    if MGE then MGE.settingsOverlay = nil end
end

local panel = overlay:addChild({
    pos = { (WIN_W - PANEL_W) / 2, (WIN_H - panelH) / 2 },
    size = { PANEL_W, panelH },
    bgColor = Widgets.CONTENT_BG, -- like MGE's lists and editor
    shapeType = ROUNDED,
    rounded = 5,
    interactive = true, -- clicks on the panel don't reach the background's close handler
})

local title = panel:addChild({
    pos = { PAD, 0 },
    size = { PANEL_W - PAD * 2, TITLE_H },
})
title:addAdaptedText(true, "Settings", nil, nil, Widgets.FONT, nil, Widgets.TITLE_SCALE)

-- the "?" at a row's end, the same size and place as the editor rows' (ui/editor_rows.lua)
local HELP_SIZE = ROW_H - px(6)
local HELP_GAP = px(6) -- between the "?" and what's next to it

---Row inside the panel: label on the left with its "?" at the end of the label column (rows with and
---without one line up), returns the space right of it for buttons or a field
---@param y number
---@param label string
---@param help string? shown when hovering the "?", none without
---@return UIElement content
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

---Centered heading with a "?" right after its text (hovering it shows help). Heading and icon are
---centered together: the text is measured the way the game's help popups measure theirs. The heading
---area is one icon (and gap) narrower than the row, so its centered text sits half that left of the
---panel's center and the icon fits after it. Not moved left with moveTo: a negative x counts from the
---parent's right edge in toriui
---@param y number
---@param text string
---@param help string
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

---@type { setting: MgeSetting, on: UIElement, off: UIElement }[]
local toggles = {}

---On / Off buttons show each setting's current value
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

-- UI size: MGE's overall size (Widgets.UI_SCALE). Every size is worked out when the window is built, so a
-- new one restarts MGE: the mod stays as it is (the working copy and the atmo are kept over a restart,
-- like any /ls of MGE), the undo history starts over
do
    local content = addRow(y, "UI size") -- picking one restarts MGE: the mod stays, the undo history starts over
    local items = {}
    for i, scale in ipairs(Widgets.UI_SCALES) do
        items[i] = { label = math.floor(scale * 100 + 0.5) .. "%", onClick = function()
            if scale == Widgets.UI_SCALE then return end
            MGE_UI_SCALE = scale
            MGE.Config.save() -- before the restart: the next game session starts at this size too
            local entry = MGE.scriptPath:gsub("mge/$", "") .. "mge.lua" -- the script /ls loads
            echo("^04[MGE] UI size " .. items[i].label .. ", restarting MGE")
            pcall(MGE.quit)
            -- started again on the next frame, out of this click (the window it's in is gone)
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

---A heading and one number field per setting, filled with the current values. With infoText the heading
---has a "?" explaining the section
---@param name string the heading
---@param fields MgeNumberSetting[]
---@param infoText string?
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
        entry.input = Rows.createInput(content, function() applySnap(entry) end, formatStep(step.get()))
        Widgets.closeOnEscape(entry.input) -- Esc while typing closes too (applies it, like Close)
        table.insert(numberInputs, entry)
        applySnap(entry) -- fills the field with the current value
        y = y + SETTING_H
    end
end

addNumberSection("Gizmo snapping", SNAP_STEPS, SNAP_INFO) -- three steps, one explanation: on the heading
addNumberSection("Atmo objects", ATMO_FIELDS) -- the label says enough

-- Shortcuts heading with the "?" right after the text, hovering it lists them
addHelpHeading(y, "Shortcuts", SHORTCUTS)
y = y + SECTION_H

Widgets.button(panel, { x = PAD, y = panelH - PAD - CLOSE_H, w = PANEL_W - PAD * 2, h = CLOSE_H }, "Close",
    function() overlay:kill() end)

refresh()
