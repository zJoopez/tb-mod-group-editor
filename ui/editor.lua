container = {}

local totalHeight = 0
local margin = 10

local function updateContentHeight(height)
    totalHeight = totalHeight + height + margin
end

local function moveSelected(target, input)
    for _, v in pairs(MGE.modData.objects) do
        if v.selected then
            local lpos = { v.pos[1], v.pos[2], v.pos[3] }
            lpos[target] = v.pos[target] + input
            set_obj_pos(v.id - 1, lpos[1], lpos[2], lpos[3])
        end
    end
end

local function createInput(container, onInputFunc, target)
    local input = TBMenu:spawnTextField2(container, nil, "0",
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
    input:addMouseUpHandler(function()
        input.textfieldstr = { "" }
    end)
    input:addKeyboardHandlers(nil, function()
        local input = tonumber(input.textfieldstr[1]) or 0
        onInputFunc(target, input)
    end)
    return input
end

---@param container UIElement
---@param inputCount integer
local function createRow(container, inputCount)
    local width = 0
    local row = container:addChild({
        pos = { 0, totalHeight },
        size = { container.size.w, 30 },
        interactive = true,
    }, true)

    local columnSize = row.size.w / (inputCount + 1)
    local inputs = {}

    local label = row:addChild({
        pos = { width, 0 },
        size = { columnSize, row.size.h },
    }, true)
    label:addAdaptedText("Pos", nil, nil, nil, CENTERMID, 0.8, nil, nil)
    width = width + columnSize

    for i = 1, inputCount, 1 do
        local inputContainer = row:addChild({
            pos = { width, totalHeight },
            size = { columnSize, 30 },
            interactive = true,
        }, true)
        inputs[i] = createInput(inputContainer, moveSelected, i)
        width = width + columnSize
    end
    updateContentHeight(row.size.h)
    return inputs
end

function container.create(container)
    local posInputs = createRow(container, 3)
end

return container
