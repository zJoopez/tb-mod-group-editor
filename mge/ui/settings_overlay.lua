-- Settings overlay, opened by the toolbar's settings button (ui/main.lua). On / off settings that
-- were toolbar toggles, moved here to make room for the gizmo tools:
--   Camera follow: the camera looks at the selection when selecting and moving (MGE.Camera.followMoves)
--   World select:  clicking objects in the world selects them, off to play the mod (MGE.WorldSelect)
-- Clicking outside the panel or Close closes it. MGE.quit closes it too (MGE.settingsOverlay).
if MGE.settingsOverlay and not MGE.settingsOverlay.destroyed then return end

local Widgets = MGE.Widgets
local WorldSelect = MGE.WorldSelect
local Camera = MGE.Camera

local overlay = TBMenu:spawnWindowOverlay(true) -- true: a click on the dark background closes it
MGE.settingsOverlay = overlay
local defaultKillAction = overlay.killAction
overlay.killAction = function()
    if defaultKillAction then defaultKillAction() end
    WorldSelect.onChanged = function() end -- the buttons it updates are gone
    if MGE then MGE.settingsOverlay = nil end
end

---@class MgeSetting
---@field label string
---@field info string small line under the row
---@field get fun(): boolean
---@field set fun(on: boolean)

---@type MgeSetting[]
local SETTINGS = {
    {
        label = "Camera follow",
        info = "Camera looks at the selection when selecting and moving",
        get = function() return Camera.followMoves end,
        set = function(on) Camera.followMoves = on end,
    },
    {
        label = "World select",
        info = "Click objects in the world to select. Off: play the mod",
        get = function() return WorldSelect.enabled end,
        set = function(on) WorldSelect.setEnabled(on) end,
    },
}

local PANEL_W = 340
local PAD = 12
local TITLE_H = 44
local ROW_H = 28
local SETTING_H = ROW_H + Widgets.INFO_HEIGHT + 8 -- row, info line, gap
local CLOSE_H = 28
local panelH = TITLE_H + #SETTINGS * SETTING_H + CLOSE_H + PAD * 2

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

local LABEL_W = 150
local y = TITLE_H
for _, setting in ipairs(SETTINGS) do
    local row = panel:addChild({
        pos = { PAD, y },
        size = { PANEL_W - PAD * 2, ROW_H },
    })
    local label = row:addChild({
        pos = { 0, 0 },
        size = { LABEL_W, ROW_H },
    })
    label:addAdaptedText(setting.label, nil, nil, nil, LEFTMID, Widgets.TEXT_SCALE)
    local buttons = row:addChild({
        pos = { LABEL_W, 0 },
        size = { row.size.w - LABEL_W, ROW_H },
    })
    local created = Widgets.buttonRow(buttons, 0, ROW_H, {
        { label = "On", onClick = function() setting.set(true) refresh() end },
        { label = "Off", onClick = function() setting.set(false) refresh() end },
    }, 4)
    table.insert(toggles, { setting = setting, on = created[1], off = created[2] })

    local info = panel:addChild({
        pos = { PAD, y + ROW_H + 2 },
        size = { PANEL_W - PAD * 2, Widgets.INFO_HEIGHT },
    })
    Widgets.infoText(info, setting.info)
    y = y + SETTING_H
end

Widgets.button(panel, { x = PAD, y = panelH - PAD - CLOSE_H, w = PANEL_W - PAD * 2, h = CLOSE_H }, "Close",
    function() overlay:kill() end)

-- a gizmo tool (Shift + Q / W / E) turns world clicking back on, keep the buttons right while open
WorldSelect.onChanged = refresh
refresh()
