--stolen and modified from rpl save, tanks :)
if (MGE.saveOverlay ~= nil) then
    return
end

-- name prompt for MGE.saveAs (the mod's first Save) and asset Export, MGE.saveOverlayContext says
-- what saving does (onSave), the title, placeholder and default name
local saveContext = MGE.saveOverlayContext or {}

local ModSaveOverlay = TBMenu:spawnWindowOverlay()
MGE.saveOverlay = ModSaveOverlay -- lets MGE.quit close it
local defaultKillAction = ModSaveOverlay.killAction
ModSaveOverlay.killAction = function()
    if (defaultKillAction ~= nil) then
        defaultKillAction()
    end
    -- the name field would otherwise stay in toriui's keyboard list (see Widgets.releaseKeyboard)
    if MGE and MGE.Widgets then MGE.Widgets.releaseKeyboard(ModSaveOverlay) end
    if MGE then MGE.saveOverlay = nil end
    if MGE then MGE.saveOverlayContext = nil end
    enable_camera_movement()
end

local function closeOverlay()
    if ModSaveOverlay then
        ModSaveOverlay:kill()
    end
end

-- as tall as its parts (title, name field, buttons, 10px between): they're sized with Widgets.px, a fixed
-- 180 let the buttons cover the name field at bigger UI sizes
local boxH = MGE.Widgets.px(50) + 10 + MGE.Widgets.px(40) + 10 + MGE.Widgets.px(40) + 10
local modSave = ModSaveOverlay:addChild({
    shift = { WIN_W / 4, (WIN_H - boxH) / 2 },
    bgColor = MGE.Widgets.CONTENT_BG, -- like MGE's lists and editor
    shapeType = ROUNDED,
    rounded = 5,
    interactive = true
})

local modSaveTitle = modSave:addChild({
    pos = { 10, 0 },
    size = { modSave.size.w - 20, MGE.Widgets.px(50) }
})
modSaveTitle:addAdaptedText(true, saveContext.title or "Mod Name", nil, nil, MGE.Widgets.FONT, nil, MGE.Widgets.TITLE_SCALE)

-- MGE's buttons (Widgets.button): the menu's colors, font and shape. Save's click is added below
local buttonH = MGE.Widgets.px(40)
local modSaveButton = MGE.Widgets.button(modSave, { x = modSave.size.w / 2 + 5, y = -MGE.Widgets.px(50),
    w = modSave.size.w / 2 - 15, h = buttonH }, TB_MENU_LOCALIZED.BUTTONSAVE)
MGE.Widgets.button(modSave, { x = 10, y = -MGE.Widgets.px(50), w = modSave.size.w / 2 - 15, h = buttonH },
    TB_MENU_LOCALIZED.BUTTONCANCEL, closeOverlay)

local replayNameBackground = modSave:addChild({
    pos = { 10, modSaveTitle.size.h + modSaveTitle.shift.y + 10 },
    size = { modSave.size.w - 20, MGE.Widgets.px(40) },
    bgColor = MGE.Widgets.BAR_COLOR, -- the name field, darker than the panel
    rounded = 4
}, true)
local replayNameInput = TBMenu:spawnTextField2(replayNameBackground, {}, nil, saveContext.placeholder or "Enter Mod Name", {
    fontId = MGE.Widgets.FONT,
    textScale = MGE.Widgets.TEXT_SCALE,
    textAlign = CENTERMID,
    darkerMode = true
})

local function sanitizeName(newname)
    if not newname then return "" end
    if saveContext.sanitize then
        return saveContext.sanitize(newname)
    end
    return newname:gsub("%.tbm$", "")
end

local function save(newname)
    local name = sanitizeName(newname)
    if name == "" then
        return
    end
    if saveContext.validate then
        local ok, err = saveContext.validate(name)
        if not ok then
            TBMenu:showStatusMessage(err or "Invalid name")
            return
        end
    elseif (utf8.find(name, "[^%d%a-_ ]") or not utf8.find(name, "[%a%d]")) then
        TBMenu:showStatusMessage(
            "Mod name must be alphanumeric and can only contain underscores, spaces or dashes as special characters")
        return
    end
    -- the opener decides what saving means: the mod's Save (MGE.saveAs) or an asset Export
    local ok = saveContext.onSave and saveContext.onSave(name)
    if ok ~= false then
        closeOverlay()
    end
end

MGE.Widgets.closeOnEscape(replayNameInput) -- Esc cancels, like the Cancel button

replayNameInput:addEnterAction(function()
    save(replayNameInput.textfieldstr[1])
end)
modSaveButton:addMouseHandlers(nil, function()
    save(replayNameInput.textfieldstr[1])
end)

if saveContext.defaultName then
    replayNameInput.textfieldstr[1] = saveContext.defaultName
end
replayNameInput.btnDown()
replayNameInput.keyboard = true
disable_camera_movement()
