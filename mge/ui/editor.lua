local container = {}
dofile(MGE.scriptPath .. "utils/rotating.lua")

local totalHeight = 0
local margin = 10
local absoluteMode = false

---@type table<string, UIElement[]>
local inwuts = {}
local function updateContentHeight(height)
    totalHeight = totalHeight + height
end

local function formatStrArr(arr)
    for index, value in ipairs(arr) do
        arr[index] = string.format("%.2f", value)
    end
end

---@return number, number, number
local function getSelectionPivot()
    local sumX, sumY, sumZ = 0, 0, 0
    local n = 0

    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.selected then
            local pos = { get_obj_pos(obj.id - 1) }
            sumX = sumX + pos[1]
            sumY = sumY + pos[2]
            sumZ = sumZ + pos[3]
            n = n + 1
        end
    end

    if n == 0 then return 0, 0, 0 end

    return
        sumX / n,
        sumY / n,
        sumZ / n
end

local function moveSelected()
    local offsets = {}
    for i, input in ipairs(inwuts.pos) do
        offsets[i] = tonumber(input.textfieldstr[1]) or 0
    end
    if absoluteMode then
        local pivot = { getSelectionPivot() }
        for i = 1, #offsets do
            offsets[i] = offsets[i] - pivot[i]
        end
    end
    for _, v in pairs(ModData.parsed.env_obj) do
        if v.selected then
            local x, y, z = get_obj_pos(v.id - 1)
            local pos = { x + offsets[1], y + offsets[2], z + offsets[3] }
            set_obj_pos(v.id - 1, pos[1], pos[2], pos[3])
            formatStrArr(pos)
            v.props.pos = table.concat(pos, " ")
        end
    end
    set_camera_mode(4)
    set_camera_lookat(getSelectionPivot())
end

local function rotSelected()
    local pivot = { getSelectionPivot() }
    local offsets = {}
    for i, input in ipairs(inwuts.rot) do
        offsets[i] = math.rad(tonumber(input.textfieldstr[1]) or 0)
    end

    for _, v in pairs(ModData.parsed.env_obj) do
        if v.selected then
            local x, y, z = v.props.rot:match("(%S+)%s+(%S+)%s+(%S+)")
            local rot = { math.rad(tonumber(x) or 0), math.rad(tonumber(y) or 0), math.rad(tonumber(z) or 0) }
            local pos = { get_obj_pos(v.id - 1) }

            local outPos = RotatingOld.SetRotPos(
                pos[1], pos[2], pos[3],
                pivot[1], pivot[2], pivot[3],
                offsets[1], offsets[2], offsets[3]
            )
            local outRot = RotatingOld.SetRotOffset(
                rot[1], rot[2], rot[3],
                offsets[1], offsets[2], offsets[3]
            )
            set_obj_rot(v.id - 1, math.rad(outRot[1]), math.rad(outRot[2]), math.rad(outRot[3]))
            set_obj_pos(v.id - 1, outPos[1], outPos[2], outPos[3])

            formatStrArr(outRot)
            formatStrArr(outPos)
            v.props.rot = table.concat(outRot, " ")
            v.props.pos = table.concat(outPos, " ")
        end
    end
end

local function scaleSelected()
    local pivot = { getSelectionPivot() }
    local scale = {}
    for i, input in ipairs(inwuts.scale) do
        local value = tonumber(input.textfieldstr[1]) or 0
        if value == 0 or value == -1 then
            scale[i] = 1
        else
            scale[i] = value
        end
    end

    for _, v in pairs(ModData.parsed.env_obj) do
        if v.selected then
            local sides = { get_obj_sides(v.id - 1) }
            local pos = { get_obj_pos(v.id - 1) }

            local rel = {
                pos[1] - pivot[1],
                pos[2] - pivot[2],
                pos[3] - pivot[3],
            }
            local outPos = {
                pivot[1] + rel[1] * scale[1],
                pivot[2] + rel[2] * scale[2],
                pivot[3] + rel[3] * scale[3],
            }
            local outSides = {
                sides[1] * scale[1],
                sides[2] * scale[2],
                sides[3] * scale[3],
            }

            set_obj_pos(v.id - 1, outPos[1], outPos[2], outPos[3])
            set_obj_sides(v.id - 1, outSides[1], outSides[2], outSides[3])

            formatStrArr(outPos)
            formatStrArr(outSides)
            v.props.pos = table.concat(outPos, " ")
            v.props.sides = table.concat(outSides, " ")
        end
    end
end

local function adjustColor()
    local color = {}
    for i, input in ipairs(inwuts.color) do
        local n = tonumber(input.textfieldstr[1]) or 0
        n = math.max(0, math.min(500, n))
        color[i] = n / 255
    end
    for _, v in pairs(ModData.parsed.env_obj) do
        if v.selected then
            set_obj_color(v.id - 1, color[1], color[2], color[3], color[4])
            formatStrArr(color)
            v.props.color = table.concat(color, " ")
        end
    end
end

local function createInput(container, onInputFunc)
    local input = TBMenu:spawnTextField2(container, nil, "",
        "0.00",
        {
            inputType = 2,
            textfield = true,
            returnKeyType = KEYBOARD_RETURN.SEND,
            isNumeric = true,
            allowDecimal = true,
            allowNegative = true,
            textAlign = CENTER,
        })
    input:addKeyboardHandlers(nil, function(key)
        if key ~= 13 then return end --enter
        onInputFunc()
    end)
    return input
end

---@param container UIElement
---@param inputCount integer
---@param defaultValue string[]?
local function createInputRow(label, container, inputCount, func, defaultValue) --todo margin as param?
    local width = 0
    local row = container:addChild({
        pos = { 0, totalHeight },
        size = { container.size.w, 30 },
        interactive = true,
    }, true)

    local columnCount = inputCount
    if label then columnCount = columnCount + 1 end
    local columnSize = row.size.w / columnCount
    local inputs = {}

    if label then
        local labelContainer = row:addChild({
            pos = { width, 0 },
            size = { columnSize, row.size.h },
        }, true)
        labelContainer:addAdaptedText(label, nil, nil, nil, CENTERMID, 0.8, nil, nil)
        width = width + columnSize
    end

    for i = 1, inputCount, 1 do
        local inputContainer = row:addChild({
            pos = { width, 0 },
            size = { columnSize, row.size.h },
            interactive = true,
        }, true)
        inputs[i] = createInput(inputContainer, func)
        if defaultValue then inputs[i].textfieldstr[1] = defaultValue[i] end
        width = width + columnSize
    end
    updateContentHeight(row.size.h)
    return inputs
end

---comment
---@param container UIElement
---@param funcs function[]
---@param names string[]
---@return table
local function createButtonRow(container, funcs, names)
    local row = container:addChild({
        pos = { 0, totalHeight },
        size = { container.size.w, 30 },
        interactive = true,
    }, true)

    local columnSize = row.size.w / #funcs
    local width = 0
    local btns = {}

    for i, value in ipairs(funcs) do
        local btn = row:addChild({
            pos = { width, 0 },
            size = { columnSize - margin, row.size.h },
            interactive = true,
            bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
            hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
            pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR
        }, true)
        btn:addMouseUpHandler(value)
        btn:addAdaptedText(names[i] or "")
        btns[i] = btn
        width = width + columnSize
    end

    updateContentHeight(row.size.h + margin)
    return btns
end

local function shallowCopy(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

local function duplicate()
    local taberu = ModData.parsed.env_obj
    for i = 1, #taberu do
        local obj = taberu[i]
        if obj and obj.selected then
            local freeIds
            if obj.props.flag ~= "0" and not ModData.jointIds[obj.id] then
                freeIds = ModData.freeIds.static
            else
                freeIds = ModData.freeIds.nonStatic
            end

            local newId = freeIds[1]
            if not newId then
                print("Not enough objects available")
                return
            end

            local copy = shallowCopy(obj)
            copy.id = newId
            table.insert(ModData.parsed.env_obj, copy)
            table.remove(freeIds, 1)
        end
    end
    table.sort(taberu, function(a, b)
        return a.id < b.id
    end)
    MGE.save()
end

local function delete()
    for i = #ModData.parsed.env_obj, 1, -1 do -- iterating backwards to prevent index issues when removing
        local obj = ModData.parsed.env_obj[i]
        if obj.selected then
            table.remove(ModData.parsed.env_obj, i)
            if obj.props.flag ~= "0" and not ModData.jointIds[obj.id] then
                table.insert(ModData.freeIds.static, obj.id)
            else
                table.insert(ModData.freeIds.nonStatic, obj.id)
            end
        end
    end
    MGE.save()
end

local function export()
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end

function container.create(container)
    totalHeight = 0
    inwuts.pos = createInputRow("Pos", container, 3, moveSelected)
    inwuts.rot = createInputRow("Rot", container, 3, rotSelected)
    inwuts.scale = createInputRow("Scale", container, 3, scaleSelected)
    updateContentHeight(margin)

    createInputRow("Color", container, 0, nil)
    inwuts.color = createInputRow(nil, container, 4, adjustColor, { "", "", "", "255" })
    updateContentHeight(margin) 

    createButtonRow(container, { duplicate, delete }, { "Duplicate", "Delete" })
    createButtonRow(container, { MGE.save, export }, { "Save", "Export" })
end

return container
