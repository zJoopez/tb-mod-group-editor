local container = {}
dofile(MGE.scriptPath .. "math/rotating.lua")

-- debug junk
-- dofile("chatlog/chatlog.lua")
-- runCmd("lm scooter_jump_x_grind_mp.tbm")

local totalHeight = 0
local margin = 10
local color = {0,0,0,0}
local function updateContentHeight(height)
    totalHeight = totalHeight + height
end

local function moveSelected(target, input)
    for _, v in pairs(MGE.modData.objects) do
        if v.selected then
            local pos = { v.pos[1], v.pos[2], v.pos[3] }
            pos[target] = v.pos[target] + input
            set_obj_pos(v.id - 1, pos[1], pos[2], pos[3])
        end
    end
end

local function rotSelected(target, input)
    local pivot = RotatingOld.GetSelectionPivot()
    local delta = { 0, 0, 0 }
    delta[target] = math.rad(tonumber(input) or 0)

    for _, v in pairs(MGE.modData.objects) do
        if v.selected then
            local m = get_obj_rot(v.id - 1)
            local mtb = Utils3D.MatrixToMatrixTB(m)
            set_obj_rot_m(v.id - 1, mtb)
            print("done")
            print("In: " .. v.id .. " rot: " .. v.rot.x .. ", " .. v.rot.y .. ", " .. v.rot.z)
            -- pre-convert rot to radians once per object, outside any further calls
            local rx, ry, rz = math.rad(v.rot.x), math.rad(v.rot.y), math.rad(v.rot.z)
            -- local rx, ry, rz = v.rot.x, v.rot.y, v.rot.z

            local px, py, pz = RotatingOld.SetRotPos(
                v.pos[1], v.pos[2], v.pos[3],
                pivot.x, pivot.y, pivot.z,
                delta[1], delta[2], delta[3]
            )
            local outx, outy, outz = RotatingOld.SetRotOffset(
                rx, ry, rz,
                delta[1], delta[2], delta[3]
            )
            print("Out: " .. v.id .. " rot: " .. outx .. ", " .. outy .. ", " .. outz)
            set_obj_rot(v.id - 1, math.rad(outx), math.rad(outy), math.rad(outz))
            set_obj_pos(v.id - 1, px, py, pz)
        end
    end
end

local function adjustColor(target, input)
    for _, v in pairs(MGE.modData.objects) do
        if v.selected then
            color[target] = input / 255
            set_obj_color(v.id - 1, color[1], color[2], color[3], color[4])
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
local function createRow(label, container, inputCount, func)
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
        width = width + columnSize
    end
    updateContentHeight(row.size.h)
    return inputs
end

function container.create(container)
    local posInputs = createRow("Pos", container, 3, moveSelected)
    local rotInputs = createRow("Rot", container, 3, rotSelected)
    local rotInputs = createRow("Color", container, 0, nil)
    local rotInputs = createRow(nil, container, 4, adjustColor)
end

return container
