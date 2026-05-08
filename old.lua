-- Created by joopez
-- Project: Mod Group Editor v.0.9
-- Built for Toribash v.5.76
-- /ls tb-move-stuff/mge.lua

require("tb-move-stuff/rotating")
require("toriui/uielement")

-- UI stuff
local header = UIElement:new({
	pos = { 1590, 0 },
	size = { 330, 40 },
	bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
})

local title = UIElement:new({
	parent = header,
	pos = { 0, 0 },
	size = { 250, 40 },
	interactive = true,
})
title:addAdaptedText(false, "Mod Group Edit")
title:addMouseHandlers(nil, function()
	toggleWindow()
end)

local x = UIElement:new({
	parent = header,
	pos = { 285, 5 },
	size = { 35, 30 },
	bgColor = TB_MENU_DEFAULT_BG_COLOR,
	hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
	shapeType = ROUNDED,
	rounded = 5,
	interactive = true,
})
x:addAdaptedText(false, "x")
x:addMouseHandlers(nil, function()
	killAll()
end)

local window = UIElement:new({
	pos = { 1590, 40 },
	size = { 330, 365 },
	bgColor = TB_MENU_DEFAULT_BG_COLOR,
})

local start_id_label = UIElement:new({
	parent = window,
	pos = { 10, 10 },
	size = { 150, 30 },
})
start_id_label:addAdaptedText(false, "Start Object ID:")

local start_index_input_holder = UIElement:new({
	parent = window,
	pos = { 170, 10 },
	size = { 150, 30 },
	interactive = true,
	textfield = true,
})
local start_index_input = TBMenu:spawnTextField2(start_index_input_holder, start_index_input_holder.size, "1", "1", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
	allowNegative = false,
})

local start_id_label = UIElement:new({
	parent = window,
	pos = { 10, 50 },
	size = { 150, 30 },
})
start_id_label:addAdaptedText(false, "End Object ID:")

local end_index_input_holder = UIElement:new({
	parent = window,
	pos = { 170, 50 },
	size = { 150, 30 },
	interactive = true,
	textfield = true,
})
local end_index_input = TBMenu:spawnTextField2(end_index_input_holder, end_index_input_holder.size, "256", "256", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
	allowNegative = false,
})


local input_group1 = UIElement:new({
	parent = window,
	pos = { 10, 90 },
	size = { 310, 60 },
})
local input_group1_label = UIElement:new({
	parent = input_group1,
	pos = { 0, 0 },
	size = { 130, 25 },
})
input_group1_label:addAdaptedText(false, "Position offset")

local offset_x_input_label = UIElement:new({
	parent = input_group1,
	pos = { 0, 30 },
	size = { 10, 25 },
})
offset_x_input_label:addAdaptedText(false, "X")
local offset_x_input_holder = UIElement:new({
	parent = input_group1,
	pos = { 20, 30 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local pos_offset_x_input = TBMenu:spawnTextField2(offset_x_input_holder, offset_x_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	allowDecimal = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
})

local offset_y_input_label = UIElement:new({
	parent = input_group1,
	pos = { 80, 30 },
	size = { 10, 25 },
})
offset_y_input_label:addAdaptedText(false, "Y")
local offset_y_input_holder = UIElement:new({
	parent = input_group1,
	pos = { 100, 30 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local pos_offset_y_input = TBMenu:spawnTextField2(offset_y_input_holder, offset_y_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	allowDecimal = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
})

local offset_z_input_label = UIElement:new({
	parent = input_group1,
	pos = { 160, 30 },
	size = { 10, 25 },
})
offset_z_input_label:addAdaptedText(false, "Z")
local offset_z_input_holder = UIElement:new({
	parent = input_group1,
	pos = { 180, 30 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local pos_offset_z_input = TBMenu:spawnTextField2(offset_z_input_holder, offset_z_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	allowDecimal = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
})

local input_group2 = UIElement:new({
	parent = window,
	pos = { 10, 150 },
	size = { 310, 60 },
})
local input_group2_label = UIElement:new({
	parent = input_group2,
	pos = { 0, 0 },
	size = { 130, 25 },
})
input_group2_label:addAdaptedText(false, "Rotation offset")

local rot_offset_x_input_label = UIElement:new({
	parent = input_group2,
	pos = { 0, 30 },
	size = { 10, 25 },
})
rot_offset_x_input_label:addAdaptedText(false, "X")
local offset_x_input_holder = UIElement:new({
	parent = input_group2,
	pos = { 20, 30 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local rot_offset_x_input = TBMenu:spawnTextField2(offset_x_input_holder, offset_x_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	allowDecimal = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
})

local rot_offset_y_input_label = UIElement:new({
	parent = input_group2,
	pos = { 80, 30 },
	size = { 10, 25 },
})
rot_offset_y_input_label:addAdaptedText(false, "Y")
local offset_y_input_holder = UIElement:new({
	parent = input_group2,
	pos = { 100, 30 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local rot_offset_y_input = TBMenu:spawnTextField2(offset_y_input_holder, offset_y_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	allowDecimal = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
})

local rot_offset_z_input_label = UIElement:new({
	parent = input_group2,
	pos = { 160, 30 },
	size = { 10, 25 },
})
rot_offset_z_input_label:addAdaptedText(false, "Z")
local offset_z_input_holder = UIElement:new({
	parent = input_group2,
	pos = { 180, 30 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local rot_offset_z_input = TBMenu:spawnTextField2(offset_z_input_holder, offset_z_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	allowDecimal = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
})

local input_group3 = UIElement:new({
	parent = window,
	pos = { 10, 210 },
	size = { 310, 60 },
})
local input_group3_label = UIElement:new({
	parent = input_group3,
	pos = { 0, 0 },
	size = { 150, 25 },
})
input_group3_label:addAdaptedText(false, "Rotation Axis Point")

local rot_axis_x_input_label = UIElement:new({
	parent = input_group3,
	pos = { 0, 30 },
	size = { 10, 25 },
})
rot_axis_x_input_label:addAdaptedText(false, "X")
local offset_x_input_holder = UIElement:new({
	parent = input_group3,
	pos = { 20, 30 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local rot_axis_x_input = TBMenu:spawnTextField2(offset_x_input_holder, offset_x_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	allowDecimal = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
})

local rot_axis_y_input_label = UIElement:new({
	parent = input_group3,
	pos = { 80, 30 },
	size = { 10, 25 },
})
rot_axis_y_input_label:addAdaptedText(false, "Y")
local offset_y_input_holder = UIElement:new({
	parent = input_group3,
	pos = { 100, 30 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local rot_axis_y_input = TBMenu:spawnTextField2(offset_y_input_holder, offset_y_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	allowDecimal = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
})

local rot_axis_z_input_label = UIElement:new({
	parent = input_group3,
	pos = { 160, 30 },
	size = { 10, 25 },
})
rot_axis_z_input_label:addAdaptedText(false, "Z")
local offset_z_input_holder = UIElement:new({
	parent = input_group3,
	pos = { 180, 30 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local rot_axis_z_input = TBMenu:spawnTextField2(offset_z_input_holder, offset_z_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	allowDecimal = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
})

local color_sect_label = UIElement:new({
	parent = window,
	pos = { 10, 265 },
	size = { 45, 25 },
})
color_sect_label:addAdaptedText(false, "Color")
local color_r_input_label = UIElement:new({
	parent = window,
	pos = { 10, 290 },
	size = { 10, 25 },
})
color_r_input_label:addAdaptedText(false, "R")
local color_r_input_holder = UIElement:new({
	parent = window,
	pos = { 30, 290 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local color_r_input = TBMenu:spawnTextField2(color_r_input_holder, color_r_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
	allowNegative = false,
})

local color_g_input_label = UIElement:new({
	parent = window,
	pos = { 90, 290 },
	size = { 10, 25 },
})
color_g_input_label:addAdaptedText(false, "G")
local color_g_input_holder = UIElement:new({
	parent = window,
	pos = { 110, 290 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local color_g_input = TBMenu:spawnTextField2(color_g_input_holder, color_g_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
	allowNegative = false,
})

local color_b_input_label = UIElement:new({
	parent = window,
	pos = { 170, 290 },
	size = { 10, 25 },
})
color_b_input_label:addAdaptedText(false, "B")
local color_b_input_holder = UIElement:new({
	parent = window,
	pos = { 190, 290 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local color_b_input = TBMenu:spawnTextField2(color_b_input_holder, color_b_input_holder.size, nil, "0", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
	allowNegative = false,
})

local color_a_input_label = UIElement:new({
	parent = window,
	pos = { 250, 290 },
	size = { 10, 25 },
})
color_a_input_label:addAdaptedText(false, "A")
local color_a_input_holder = UIElement:new({
	parent = window,
	pos = { 270, 290 },
	size = { 50, 25 },
	interactive = true,
	textfield = true,
})
local color_a_input = TBMenu:spawnTextField2(color_a_input_holder, color_a_input_holder.size, nil, "255", {
	fontId = FONTS.SMALL,
	textAlign = LEFTMID,
	isNumeric = true,
	returnKeyType = KEYBOARD_RETURN.SEND,
	inputType = KEYBOARD_INPUT.DEFAULT,
	allowNegative = false,
})

local adjust_button = UIElement:new({
	parent = window,
	pos = { 10, 330 },
	size = { 150, 30 },
	interactive = true,
	bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
	hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
	shapeType = ROUNDED,
	rounded = 5,
})
adjust_button:addAdaptedText(false, "Apply")
adjust_button:addMouseHandlers(nil, function()
	apply()
end)

local mod_change_button = UIElement:new({
	parent = window,
	pos = { 170, 330 },
	size = { 150, 30 },
	interactive = true,
	bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
	hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
	shapeType = ROUNDED,
	rounded = 5,
})
mod_change_button:addAdaptedText(false, "Select Mod")
mod_change_button:addMouseHandlers(nil, function()
	Mods:showMain()
end)

function killAll()
	window:kill()
	header:kill()
end

function toggleWindow()
	if window.hidden then
		window:show()
		window.hidden = false
	else
		window:hide()
		window.hidden = true
	end
end

function apply()
	runCmd("clear")
	process_request()
end

function process_request()
	local modName = find_mod(get_game_rules().mod) --find_mod doesn't have different returns for /lm and gui selected mod
	local path = "../data/mod/" .. modName

	--Read File
	local file = Files.Open(path, FILES_MODE_READONLY)
	if not (file.data) then
		echo("Mod not found")
		return
	end
	echo("Mod found")
	echo("owo what is this?")
	local content = file:readAll()
	file:close()
	echo("Read done")

	local i_start = tonumber(start_index_input.textfieldstr[1]) or 1
	local i_end = tonumber(end_index_input.textfieldstr[1]) or 256

	local pos_offset_x = tonumber(pos_offset_x_input.textfieldstr[1]) or 0
	local pos_offset_y = tonumber(pos_offset_y_input.textfieldstr[1]) or 0
	local pos_offset_z = tonumber(pos_offset_z_input.textfieldstr[1]) or 0

	local rot_offsets = {
		x = math.rad(tonumber(rot_offset_x_input.textfieldstr[1]) or 0),
		y = math.rad(tonumber(rot_offset_y_input.textfieldstr[1]) or 0),
		z = math.rad(tonumber(rot_offset_z_input.textfieldstr[1]) or 0)
	}

	-- The point around which to rotate
	local axisPoint = {
		x = tonumber(rot_axis_x_input.textfieldstr[1]) or 0,
		y = tonumber(rot_axis_y_input.textfieldstr[1]) or 0,
		z = tonumber(rot_axis_z_input.textfieldstr[1]) or 0
	}

	-- account for random modmaker offset :))
	axisPoint.x = axisPoint.x + 1
	axisPoint.y = axisPoint.y - 0.1

	local new_color_line = color_input_to_line()
	local modified_lines = {} --tmp solution hopefully
	local environment_objects = {}

	local reader_env_obj_id
	local reader_env_obj_tracked = false

	echo("values set")

	for i, line in pairs(content) do
		while true do --allows continue like behaviour
			if line:find("env_obj_joint") or line:find("player") then
				reader_env_obj_id = nil
				reader_env_obj_tracked = false
				break
			end

			local new_env_obj_id = tonumber(string.match(line, "^env_obj%s+(%d+)$"))
			if new_env_obj_id then
				reader_env_obj_id = new_env_obj_id
				environment_objects[reader_env_obj_id] = {}
				reader_env_obj_tracked = reader_env_obj_id >= i_start and reader_env_obj_id <= i_end
				break
			end

			if reader_env_obj_id and line:match("^%s*pos%s+") then
				local pos = { x = 0, y = 0, z = 0 }
				pos.x, pos.y, pos.z = get_obj_pos(reader_env_obj_id - 1)

				--applying offset
				pos.x = pos.x + pos_offset_x
				pos.y = pos.y + pos_offset_y
				pos.z = pos.z + pos_offset_z

				SetRotPos(pos, axisPoint, rot_offsets)
				environment_objects[reader_env_obj_id].pos = pos

				if reader_env_obj_tracked == true then
					modified_lines[i] = string.format("   pos %.2f %.2f %.2f", pos.x, pos.y, pos.z)
				end
				break
			end

			if reader_env_obj_id and line:match("^%s*rot%s+") then
				local obj_rot = {}
				for num in string.gmatch(line, "[+-]?%d+%.?%d*") do
					local num = math.rad(tonumber(num) or 0)
					table.insert(obj_rot, num)
				end

				SetRotOffset(obj_rot, rot_offsets)
				environment_objects[reader_env_obj_id].rot = obj_rot

				if reader_env_obj_tracked == true then
					modified_lines[i] = string.format("   rot %.2f %.2f %.2f", obj_rot[1], obj_rot[2], obj_rot[3])
				end
				break
			end

			if reader_env_obj_id and line:match("^%s*color%s+") then
				environment_objects[reader_env_obj_id].color = get_obj_color(reader_env_obj_id - 1)
				if reader_env_obj_tracked == true and new_color_line then
					modified_lines[i] = new_color_line
				end
				break
			end

			break -- ensure loop is broken
		end
	end

	echo("content updated")

	--Update File
	file = Files.Open(path, FILES_MODE_WRITE)
	if (file.data) then
		echo("write started")
		for i, line in pairs(content) do
			if modified_lines[i] then
				file:writeLine(modified_lines[i])
			else
				file:writeLine(line)
			end
		end
		echo("File written successfully.")
	else
		echo("Error: Unable to open file.")
	end
	file:close()

	--reload mod
	runCmd("lm " .. "classic") -- mod swap required to update objects (mby better way exists)
	runCmd("lm " .. modName)
end

function color_input_to_line()
	local hasInput =
		tonumber(color_r_input.textfieldstr[1]) or
		tonumber(color_g_input.textfieldstr[1]) or
		tonumber(color_b_input.textfieldstr[1]) or
		tonumber(color_a_input.textfieldstr[1])
	if not hasInput then
		return nil
	end

	local color = {
		r = tonumber(color_r_input.textfieldstr[1]) or 0,
		g = tonumber(color_g_input.textfieldstr[1]) or 0,
		b = tonumber(color_b_input.textfieldstr[1]) or 0,
		a = tonumber(color_a_input.textfieldstr[1]) or 255
	}
	for key, val in pairs(color) do
		if val < 1 then
			color[key] = 0
		elseif val > 254 then
			color[key] = 1
		else
			color[key] = val / 255
		end
	end

	return string.format("   color %.8f %.8f %.8f %.8f", color.r, color.g, color.b, color.a)
end
