--stolen and modified from rpl save, tanks :)
if (MGE.saveOverlay ~= nil) then
    return
end

local saveContext = MGE.saveOverlayContext or {}

local ModData = MGE.ModData
local FileHandler = MGE.FileHandler

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

local modSave = ModSaveOverlay:addChild({
    shift = { WIN_W / 4, WIN_H / 2 - 90 },
    bgColor = TB_MENU_DEFAULT_BG_COLOR,
    shapeType = ROUNDED,
    rounded = 5,
    interactive = true
})

local modSaveTitle = modSave:addChild({
    pos = { 10, 0 },
    size = { modSave.size.w - 20, 50 }
})
modSaveTitle:addAdaptedText(true, saveContext.title or "Mod Name", nil, nil, FONTS.BIG, nil, 0.65)

local modSaveButton = modSave:addChild({
    pos = { modSave.size.w / 2 + 5, -50 },
    size = { modSave.size.w / 2 - 15, 40 },
    interactive = true,
    bgColor = { 0, 0, 0, 0.1 },
    hoverColor = { 0, 0, 0, 0.3 },
    pressedColor = { 1, 1, 1, 0.2 },
    rounded = 4
}, true)
modSaveButton:addAdaptedText(false, TB_MENU_LOCALIZED.BUTTONSAVE)

local modCancelButton = modSave:addChild({
    pos = { 10, -50 },
    size = { modSave.size.w / 2 - 15, 40 },
    interactive = true,
    bgColor = { 0, 0, 0, 0.1 },
    hoverColor = { 0, 0, 0, 0.3 },
    pressedColor = { 1, 1, 1, 0.2 },
    rounded = 4
}, true)
modCancelButton:addAdaptedText(false, TB_MENU_LOCALIZED.BUTTONCANCEL)
modCancelButton:addMouseHandlers(nil, function()
    closeOverlay()
end)

local replayNameBackground = modSave:addChild({
    pos = { 10, modSaveTitle.size.h + modSaveTitle.shift.y + 10 },
    size = { modSave.size.w - 20, 40 },
    bgColor = TB_MENU_DEFAULT_DARKEST_COLOR,
    rounded = 4
}, true)
local replayNameInput = TBMenu:spawnTextField2(replayNameBackground, {}, nil, saveContext.placeholder or "Enter Mod Name", {
    fontId = 4,
    textScale = 0.7,
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
    if saveContext.onSave then
        local ok = saveContext.onSave(name)
        if ok ~= false then
            closeOverlay()
        end
        return
    end
    MGE.syncGamerules() -- rules changed in the game's menu
    FileHandler.WriteMod(ModData.parsed, MGE.modFolder .. name .. ".tbm")
    print("saved as " .. name .. ".tbm")
    -- the named copy is the one that gets shared, say so if dynamic objects won't fully work in it
    local warning = MGE.Main and MGE.Main.dynamicWarning()
    if warning then echo("^04[MGE] saved with " .. warning) end
    closeOverlay()
end

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
