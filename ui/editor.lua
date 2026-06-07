local container = {}
dofile(MGE.scriptPath .. "math/rotating.lua")

local totalHeight = 0
local margin = 10

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

local function moveSelected()
    local offsets = {}
    for i, input in ipairs(inwuts.pos) do
        offsets[i] = tonumber(input.textfieldstr[1]) or 0
    end
    for _, v in pairs(ModData.objects) do
        if v.selected then
            local pos = { get_obj_pos(v.id - 1) }
            for i, input in ipairs(pos) do
                pos[i] = pos[i] + offsets[i]
            end
            set_obj_pos(v.id - 1, pos[1], pos[2], pos[3])
            formatStrArr(pos)
            ModData.parsed.env_obj[v.id].props.pos = table.concat(pos, " ")
        end
    end
end

local function rotSelected()
    local pivot = RotatingOld.GetSelectionPivot()
    local offsets = {}
    for i, input in ipairs(inwuts.rot) do
        offsets[i] = math.rad(tonumber(input.textfieldstr[1]) or 0)
    end

    for _, v in pairs(ModData.objects) do
        if v.selected then
            local rot = { ModData.parsed.env_obj[v.id].props.rot:match("(%S+)%s+(%S+)%s+(%S+)") }
            local pos = { get_obj_pos(v.id - 1) }

            local outPos = RotatingOld.SetRotPos(
                pos[1], pos[2], pos[3],
                pivot.x, pivot.y, pivot.z,
                offsets[1], offsets[2], offsets[3]
            )
            local outRot = RotatingOld.SetRotOffset(
                math.rad(tonumber(rot[1]) or 0), math.rad(tonumber(rot[2]) or 0), math.rad(tonumber(rot[3]) or 0),
                offsets[1], offsets[2], offsets[3]
            )
            set_obj_rot(v.id - 1, math.rad(outRot[1]), math.rad(outRot[2]), math.rad(outRot[3]))
            set_obj_pos(v.id - 1, outPos[1], outPos[2], outPos[3])

            formatStrArr(outRot)
            formatStrArr(outPos)
            ModData.parsed.env_obj[v.id].props.rot = table.concat(outRot, " ")
            ModData.parsed.env_obj[v.id].props.pos = table.concat(outPos, " ")
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
    for _, v in pairs(ModData.objects) do
        if v.selected then
            set_obj_color(v.id - 1, color[1], color[2], color[3], color[4])
            formatStrArr(color)
            ModData.parsed.env_obj[v.id].props.color = table.concat(color, " ")
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
local function createRow(label, container, inputCount, func, defaultValue)
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
            size = { columnSize, row.size.h },
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

    updateContentHeight(row.size.h)
    return btns
end

local function shallowCopy(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

local function duplicate()
    print_r(ModData.parsed.env_obj)
    for _, obj in ipairs(ModData.parsed.env_obj) do
        print(obj.id, obj.selected)
        if obj.selected then
            print_r(obj)
            local freeIds
            if obj.props.flag ~= "0" then
                freeIds = ModData.freeIds.static
            else
                freeIds = ModData.freeIds.nonStatic
            end

            local newId = freeIds[1]
            if not newId then
                print("Not enough objects available")
                return
            end
            print(newId)

            local copy = shallowCopy(obj)
            copy.id = newId
            table.insert(ModData.parsed.env_obj, newId, copy)
            table.remove(freeIds, 1)
        end
    end
    MGE.save()
end

local function delete()
    for i = #ModData.parsed.env_obj, 1, -1 do -- iterating backwards to prevent index issues when removing
        local obj = ModData.parsed.env_obj[i]
        if obj.selected then
            table.remove(ModData.parsed.env_obj, i)
            if obj.props.flag ~= "0" then
                table.insert(ModData.freeIds.static, obj.id)
            else
                table.insert(ModData.freeIds.nonStatic, obj.id)
            end
        end
    end
    MGE.save()
end

function container.create(container)
    inwuts.pos = createRow("Pos", container, 3, moveSelected)
    inwuts.rot = createRow("Rot", container, 3, rotSelected)
    createRow("Color", container, 0, nil)
    inwuts.color = createRow(nil, container, 4, adjustColor, { "", "", "", "255" })

    updateContentHeight(margin)
    createButtonRow(container, { duplicate, delete }, { "duplicate", "delete" })
end

return container
