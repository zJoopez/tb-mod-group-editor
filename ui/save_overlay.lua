--stolen and modified from rpl save, tanks :)
if (ModSaveOverlay ~= nil) then
	return
end

ModSaveOverlay = TBMenu:spawnWindowOverlay()
local defaultKillAction = ModSaveOverlay.killAction
ModSaveOverlay.killAction = function()
	if (defaultKillAction ~= nil) then
		defaultKillAction()
	end
	ModSaveOverlay = nil
	enable_camera_movement()
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
modSaveTitle:addAdaptedText(true, "Mod Name", nil, nil, FONTS.BIG, nil, 0.65)

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
	ModSaveOverlay:kill()
end)

local replayNameBackground = modSave:addChild({
	pos = { 10, modSaveTitle.size.h + modSaveTitle.shift.y + 10 },
	size = { modSave.size.w - 20, 40 },
	bgColor = TB_MENU_DEFAULT_DARKEST_COLOR,
	rounded = 4
}, true)
local replayNameInput = TBMenu:spawnTextField2(replayNameBackground, {}, nil, "Enter Mod Name", {
	fontId = 4,
	textScale = 0.7,
	textAlign = CENTERMID,
	darkerMode = true
})

local function save(newname)
	if (newname == "" or not newname) then
		return
	end
	if (utf8.find(newname, "[^%d%a-_ ]") or not utf8.find(newname, "[%a%d]")) then
		TBMenu:showStatusMessage(
			"Mod name must be alphanumeric and can only contain underscores, spaces or dashes as special characters")
		return
	end
	FileHandler.WriteMod(ModData.parsed, MGE.modFolder .. newname .. ".tbm")
	print("export complete")
	ModSaveOverlay:kill()
end

replayNameInput:addEnterAction(function() save(replayNameInput.textfieldstr[1]:gsub("%.tbm$", "")) end)
modSaveButton:addMouseHandlers(nil, function()
	save(replayNameInput.textfieldstr[1]:gsub("%.tbm$", ""))
end)

replayNameInput.btnDown()
replayNameInput.keyboard = true
disable_camera_movement()
