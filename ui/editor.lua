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

local function moveSelected(target, input)
    local offsets = {}
    for i, value in ipairs(inwuts.pos) do
        offsets[i] = tonumber(value.textfieldstr[1]) or 0
    end
    for _, v in pairs(MGE.modData.objects) do
        if v.selected then
            local pos = { get_obj_pos(v.id - 1) }
            for i, value in ipairs(pos) do
                pos[i] = pos[i] + offsets[i]
            end
            set_obj_pos(v.id - 1, pos[1], pos[2], pos[3])
            formatStrArr(pos)
            MGE.modData.parsed.env_obj[v.id].props.pos = table.concat(pos, " ")
        end
    end
end

local function rotSelected(target, input)
    local pivot = RotatingOld.GetSelectionPivot()
    local offsets = {}
    for i, value in ipairs(inwuts.rot) do
        offsets[i] = math.rad(tonumber(value.textfieldstr[1]) or 0)
    end

    for _, v in pairs(MGE.modData.objects) do
        if v.selected then
            -- local rot = Utils3D.GetEulerFromMatrixTB(get_obj_rot(v.id -1))
            local rot = { MGE.modData.parsed.env_obj[v.id].props.rot:match("(%S+)%s+(%S+)%s+(%S+)") }
            local pos = { get_obj_pos(v.id - 1) }
            -- print("real")
            -- print_r(rot)

            local outPos = RotatingOld.SetRotPos(
                pos[1], pos[2], pos[3],
                pivot.x, pivot.y, pivot.z,
                offsets[1], offsets[2], offsets[3]
            )
            local outRot = RotatingOld.SetRotOffset(
            -- math.rad(rot.x), math.rad(rot.y), math.rad(rot.z),
                math.rad(tonumber(rot[1]) or 0), math.rad(tonumber(rot[2]) or 0), math.rad(tonumber(rot[3]) or 0),
                offsets[1], offsets[2], offsets[3]
            )
            set_obj_rot(v.id - 1, math.rad(outRot[1]), math.rad(outRot[2]), math.rad(outRot[3]))
            set_obj_pos(v.id - 1, outPos[1], outPos[2], outPos[3])

            formatStrArr(outRot)
            formatStrArr(outPos)
            MGE.modData.parsed.env_obj[v.id].props.rot = table.concat(outRot, " ")
            MGE.modData.parsed.env_obj[v.id].props.pos = table.concat(outPos, " ")
        end
    end
end

local function adjustColor(target, input)
    local color = {}
    for i, value in ipairs(inwuts.color) do
        local n = tonumber(value.textfieldstr[1]) or 0
        n = math.max(0, math.min(500, n))
        color[i] = n / 255
    end
    for _, v in pairs(MGE.modData.objects) do
        if v.selected then
            set_obj_color(v.id - 1, color[1], color[2], color[3], color[4])
            formatStrArr(color)
            MGE.modData.parsed.env_obj[v.id].props.color = table.concat(color, " ")
        end
    end
end

local function createInput(container, target, onInputFunc)
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
        local input = tonumber(input.textfieldstr[1]) or 0
        onInputFunc(target, input)
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
        inputs[i] = createInput(inputContainer, i, func)
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
        btn:addAdaptedText(names[i])
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

function container.create(container)
    inwuts.pos = createRow("Pos", container, 3, moveSelected)
    inwuts.rot = createRow("Rot", container, 3, rotSelected)
    createRow("Color", container, 0, nil)
    inwuts.color = createRow(nil, container, 4, adjustColor, { "", "", "", "255" })

    updateContentHeight(margin)
    local duplicate = function()
        local selectedObjs = {}
        for _, obj in ipairs(MGE.modData.parsed.env_obj) do
            if obj.selected then
                table.insert(selectedObjs, obj)
            end
        end

        for _, obj in ipairs(selectedObjs) do
            local taberu
            if obj.props.flag ~= "0" then
                taberu = MGE.modData.freeIds.static
            else
                taberu = MGE.modData.freeIds.dynamic
            end

            local newId = taberu[1]
            if not newId then
                print("Not enough objects available")
                return
            end

            MGE.modData.parsed.env_obj[newId] = shallowCopy(obj)

            obj.id = newId
            table.remove(taberu, 1)
        end
        MGE.save()
    end
    local funcs = { duplicate }
    createButtonRow(container, funcs, { "duplicate" })
end

return container
