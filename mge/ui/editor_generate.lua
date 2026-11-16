









local Rows = MGE.EditorRows
local inwuts = Rows.inputs
local formatHints = Rows.formatHints
local createInputRow = Rows.createInputRow

local FORM = { mode = "form" }
local FORM_WHOLE = { mode = "form", whole = true }
local createChoiceRow = Rows.createChoiceRow
local createToggleButtonRow = Rows.createToggleButtonRow

local Transforms = MGE.Transforms


local GENERATE_AMOUNT = 8
local GENERATE_JOINTS = 0
local GENERATE_ANGLE = 90


local FIELD = { gap = 1, angle = 2, size = 2, increment = 5 }

local AMOUNT, JOINTS = 1, 2

local amountForAtmo = nil
local keptJoints = ""


local align = "out"


local function forAtmo()
    return MGE.Main ~= nil and MGE.Main.listTab == "atmo"
end

local limitsCache = {}




local function dynamicCount()
    local ModData = MGE.ModData
    local state = MGE.History.states[MGE.History.index]
    if limitsCache.parsed ~= ModData.parsed or limitsCache.state ~= state then
        limitsCache = { parsed = ModData.parsed, state = state, dynamic = ModData.countDynamic() }
    end
    return limitsCache.dynamic
end









local function maxGenerate(atmo, perPair)
    local ModData = MGE.ModData
    if atmo then return MGE.AtmoLayer.room(), "room in the atmo" end
    local free = ModData.freeCount()
    if perPair > 0 then
        local dynamicRoom = math.max(0, MGE.MAX_NONSTATIC_OBJECTS - dynamicCount())
        if dynamicRoom < free then return dynamicRoom, "free dynamic ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS end
    end
    return free, "free ids"
end




local function limitsKey()
    return MGE.AtmoLayer.room() .. "," .. MGE.ModData.freeCount() .. "," .. dynamicCount()
end


local function defaultSides()
    local sides = {}
    for v in MGE.Assets.defaultProps().sides:gmatch("%S+") do table.insert(sides, tonumber(v) or 0.5) end
    return sides
end







local anchor = nil
local anchorVersion = 0


local moved = { 0, 0, 0 }


local function anchorToView()

    local origin, dir, look = MGE.Camera.viewRay()
    anchor = { origin = origin, dir = dir, look = look }
    anchorVersion = anchorVersion + 1
    moved = { 0, 0, 0 }
end


local function toView()
    for _, input in ipairs(inwuts.generatePos or {}) do
        if not input.destroyed then input:clearTextfield() end
    end
    anchorToView()
end




local function piecesCenter(pieces)
    local c = { 0, 0, 0 }
    for _, piece in ipairs(pieces) do
        for k = 1, 3 do c[k] = c[k] + piece.pos[k] / #pieces end
    end
    return c
end



local function typedAngles()
    local typed = Rows.readInputs(inwuts.generateRot or {})
    return { typed[1] or 0, typed[2] or 0, typed[3] or 0 }
end



local function typedRotation()
    local a = typedAngles()
    if a[1] == 0 and a[2] == 0 and a[3] == 0 then return nil end
    return MGE.Mat3.fromEulerDegrees(a[1], a[2], a[3])
end
















local function planFromFields(factors, turn)
    local function reader(fields)
        return function(i) return fields[i] and not fields[i].destroyed and tonumber(fields[i].textfieldstr[1]) end
    end
    local typed, typedAmount = reader(inwuts.generate or {}), reader(inwuts.generateAmount or {})
    local amount = math.floor((typedAmount(AMOUNT) or GENERATE_AMOUNT) + 0.5)
    local perPair = math.floor((typedAmount(JOINTS) or GENERATE_JOINTS) + 0.5)
    local atmo = forAtmo()
    if atmo then perPair = 0 end
    local sides, increment = defaultSides(), {}
    for i = 1, 3 do
        local value = typed(FIELD.size + i)
        if value and value > 0 then sides[i] = math.max(value, MGE.MIN_SIDE) end
        increment[i] = typed(FIELD.increment + i) or 0
        if factors then
            sides[i] = math.max(sides[i] * factors[i], MGE.MIN_SIDE)
            increment[i] = increment[i] * factors[i]
        end
    end
    local note

    local most, limit = maxGenerate(atmo, amount >= 2 and math.max(perPair, 0) or 0)
    if most == 0 then
        if atmo then
            note = "no room in the atmo (Settings > Max atmo objects)"
        elseif MGE.ModData.freeCount() > 0 then
            note = "no free dynamic ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS .. " for joined pieces: Joints 0, or Reindex (Advanced)"
        else
            note = "no free object ids"
        end
    elseif amount > most then
        note = "amount must be at most " .. most .. " (" .. limit .. ")"
    elseif amount >= 2 and (perPair < 0 or perPair > 2) then
        note = "joints between two pieces must be 0, 1 or 2"
    elseif amount >= 2 then
        local jointCount, free = (amount - 1) * perPair, #MGE.Joints.freeIds()
        local shrinkMost = MGE.ShapeGen.maxPieces(sides, increment)
        if jointCount > free then
            note = jointCount .. " joints needed, " .. free .. " free (max " .. MGE.MAX_ENV_JOINTS .. "), use fewer pieces"
        elseif shrinkMost and amount > shrinkMost then
            note = "the increment shrinks pieces to nothing after " .. shrinkMost .. " pieces, use fewer or a smaller increment"
        end
    end
    local single = note ~= nil or amount < 2
    if single then amount, perPair = 1, 0 end
    local ShapeGen = MGE.ShapeGen
    local angle = single and 0 or (typed(FIELD.angle) or GENERATE_ANGLE)
    local pieces, bounds = ShapeGen.plan(amount, typed(FIELD.gap) or 0, angle, sides,
        { 0, 0 }, { increment = increment, align = align, rotation = typedRotation(), firstTurn = turn })
    if not anchor then anchorToView() end


    anchor.point = anchor.point or MGE.Camera.spawnPoint(bounds, anchor.origin, anchor.dir, anchor.look)
    ShapeGen.moveTo(pieces, bounds, anchor.point)

    local center = piecesCenter(pieces)
    local shift, origin = { moved[1], moved[2], moved[3] }, MGE.POS_ORIGIN
    for k, input in ipairs(inwuts.generatePos or {}) do
        local value = not input.destroyed and tonumber(input.textfieldstr[1])
        if value then shift[k] = value + origin[k] - center[k] end
    end
    for _, piece in ipairs(pieces) do
        for k = 1, 3 do piece.pos[k] = piece.pos[k] + shift[k] end
    end
    local shown = {}
    for k = 1, 3 do shown[k] = center[k] + shift[k] - origin[k] end



    local point = anchor.point
    local middle = { point[1] + shift[1], point[2] + shift[2], point[3] + (bounds.max[3] - bounds.min[3]) / 2 + shift[3] }
    return pieces, note, shown, ShapeGen.joints(pieces, perPair), middle
end




local previewKey, previewPieces, previewAnchors

local previewMiddle
local previewShown = false

local positionHints = { "0.00", "0.00", "0.00" }


local liveOffset = nil

local liveFactors = nil

local liveRotation = nil



local function addTexts(list, parts)
    for _, field in ipairs(list or {}) do
        table.insert(parts, field.destroyed and "" or field.textfieldstr[1])
    end
end


local function fieldsKey()

    local parts = { align .. "#" .. anchorVersion, table.concat(moved, ","), limitsKey() }
    addTexts(inwuts.generateAmount, parts)
    addTexts(inwuts.generate, parts)
    addTexts(inwuts.generatePos, parts)
    addTexts(inwuts.generateRot, parts)
    return table.concat(parts, "|")
end




local function followPreview()
    if not MGE.Camera.followMoves or not previewPieces then return end
    local center, radius = previewMiddle, 0
    for _, piece in ipairs(previewPieces) do
        local d, half = 0, 0
        for k = 1, 3 do
            d = d + (piece.pos[k] - center[k]) ^ 2
            half = half + piece.sides[k] ^ 2
        end
        radius = math.max(radius, math.sqrt(d) + math.sqrt(half) / 2)
    end
    MGE.Camera.focusOn(center, math.min(radius, MGE.Camera.maxObjectRadius))
end



local function showPosition(center)
    if not center then return end
    local hints = formatHints(center)
    if hints[1] == positionHints[1] and hints[2] == positionHints[2] and hints[3] == positionHints[3] then return end
    positionHints = hints
    Rows.refreshBlocks({ "generatePos" })
end



local function replan()
    previewKey = fieldsKey()
    local center, joints, _

    previewPieces, _, center, joints, previewMiddle = planFromFields()
    previewAnchors = {}
    for i, joint in ipairs(joints or {}) do previewAnchors[i] = joint.pos end
    showPosition(center)
    followPreview()
end




local function tabOpen()
    local Main = MGE.Main
    local list = Main.listTab
    return (list == "objects" or list == "atmo") and Main.activeTabs[list] == "generate"
        and inwuts.generate ~= nil
        and Main.window ~= nil and Main.window.displayed == true
end

MGE.Highlight.preview = function()
    if not tabOpen() then
        previewShown = false
        liveOffset, liveFactors, liveRotation = nil, nil, nil
        return nil
    end
    if not previewShown then
        previewShown = true
        anchorToView()
    end

    if amountForAtmo ~= forAtmo() then
        local joints = (inwuts.generateAmount or {})[JOINTS]
        if joints and not joints.destroyed then keptJoints = joints.textfieldstr[1] or "" end
        Rows.refreshBlocks({ "generateAmount" })
    end
    if fieldsKey() ~= previewKey then replan() end

    if (liveFactors or liveRotation) and previewPieces then
        local pieces, _, _, joints = planFromFields(liveFactors, liveRotation)
        local anchors = {}
        for i, joint in ipairs(joints or {}) do anchors[i] = joint.pos end
        return pieces, anchors
    end
    if not (liveOffset and previewPieces) then return previewPieces, previewAnchors end

    local add = MGE.GizmoMath.add
    local boxes, anchors = {}, {}
    for i, piece in ipairs(previewPieces) do
        boxes[i] = { pos = add(piece.pos, liveOffset), frame = piece.frame, sides = piece.sides }
    end
    for i, p in ipairs(previewAnchors) do anchors[i] = add(p, liveOffset) end
    return boxes, anchors
end




local function moveBy(offset)
    liveOffset = nil
    if not tabOpen() then return end
    local typedPos = inwuts.generatePos or {}
    for k = 1, 3 do
        local input = typedPos[k]
        local value = input and not input.destroyed and tonumber(input.textfieldstr[1])
        if value then
            local text = formatHints({ value + offset[k], 0, 0 })[1]
            input.textfieldstr[1] = text
            input.textfieldindex = #text
        else
            moved[k] = moved[k] + offset[k]
        end
    end
    replan()
end




local function sizeText(value)
    return Rows.formatNumberText(value, 4)
end




local function scaleBy(factors)
    liveFactors = nil
    if not tabOpen() then return end
    local fields = inwuts.generate or {}
    local sides = defaultSides()
    for i = 1, 3 do
        local size, inc = fields[FIELD.size + i], fields[FIELD.increment + i]
        if size and not size.destroyed then
            local value = tonumber(size.textfieldstr[1])
            if not (value and value > 0) then value = sides[i] end
            local text = sizeText(math.max(value * factors[i], MGE.MIN_SIDE))
            size.textfieldstr[1], size.textfieldindex = text, #text
        end
        local incValue = inc and not inc.destroyed and tonumber(inc.textfieldstr[1])
        if incValue and incValue ~= 0 then
            local text = sizeText(incValue * factors[i])
            inc.textfieldstr[1], inc.textfieldindex = text, #text
        end
    end
    replan()
end






local function rotateBy(rotation)
    liveRotation = nil
    if not tabOpen() or not previewPieces or not previewPieces[1] then return end
    local Mat3 = MGE.Mat3
    local current = typedRotation() or Mat3.IDENTITY
    local frame = previewPieces[1].frame
    local turned = Mat3.mul(current, Mat3.mul(Mat3.transpose(frame), Mat3.mul(rotation, frame)))
    local x, y, z = Mat3.toEulerXYZ(turned)
    local angles = { math.deg(x), math.deg(y), math.deg(z) }
    for k, input in ipairs(inwuts.generateRot or {}) do
        if not input.destroyed then
            local text = Rows.formatNumberText(angles[k], 2)
            input.textfieldstr[1], input.textfieldindex = text, #text
        end
    end
    replan()
end





MGE.Gizmo.previewTarget = function(mode)
    if not (previewShown and previewPieces and tabOpen()) then return nil end
    if mode ~= "move" and mode ~= "scale" and mode ~= "rotate" then return false end
    local pieces = previewPieces
    local middle = previewMiddle
    local function clear() liveOffset, liveFactors, liveRotation = nil, nil, nil end
    return {
        scalable = true,

        pivot = function() return mode == "rotate" and middle or piecesCenter(pieces) end,


        frame = function() return mode ~= "move" and pieces[1].frame or MGE.Mat3.IDENTITY end,
        previewMove = function(offset) liveOffset = offset end,
        previewRotate = function(rotation) liveRotation = rotation end,
        previewScale = function(factors) liveFactors = factors end,
        liveSides = function() return nil end,
        restoreLive = clear,
        moveBy = moveBy,
        rotateByMatrix = rotateBy,
        scaleBy = scaleBy,
    }
end




local function atmoPieces(pieces)
    local objects = {}
    for i, piece in ipairs(pieces) do
        local all = MGE.Assets.defaultProps()
        local obj = { kind = "atmo", id = i, props = { shape = all.shape, color = all.color } }
        Transforms.writeVector(obj, "pos", piece.pos)
        Transforms.writeVector(obj, "rot", piece.rot)
        Transforms.writeVector(obj, "sides", piece.sides)
        objects[i] = obj
    end
    return objects
end




local function generate()
    local pieces, note, _, joints = planFromFields()

    if maxGenerate(forAtmo(), 0) == 0 then
        MGE.say("Generate: " .. tostring(note))
        return
    end

    if note then MGE.say("Generate: " .. note .. ", added one default object instead") end
    if forAtmo() then
        if MGE.Assets.addAtmo(atmoPieces(pieces), false) then
            previewKey, previewPieces, previewAnchors = fieldsKey(), nil, nil
        end
        return
    end

    local objects = {}
    for i, piece in ipairs(pieces) do
        local obj = { kind = "env_obj", id = i, props = MGE.Assets.defaultProps() }

        obj.props.flag = #joints > 0 and "0" or tostring(MGE.FLAGS.STATIC)
        Transforms.writeVector(obj, "pos", piece.pos)
        Transforms.writeVector(obj, "rot", piece.rot)
        Transforms.writeVector(obj, "sides", piece.sides)
        objects[i] = obj
    end


    local jointBlocks = {}
    for i, joint in ipairs(joints) do
        jointBlocks[i] = { kind = "env_obj_joint", id = i, obj1 = joint.a, obj2 = joint.b, lines = {},
            props = { pos = MGE.FileHandler.formatNumbers(joint.pos[1], joint.pos[2], joint.pos[3]), visible = MGE.Joints.NEW_VISIBLE } }
    end

    MGE.Assets.addObjects(objects, true, nil, jointBlocks)

    previewKey, previewPieces, previewAnchors = fieldsKey(), nil, nil
end



local function buildAlign(holder)
    Rows.begin()
    createChoiceRow("Align", holder, {
        { label = "In", value = "in" },
        { label = "Out", value = "out" },
        { label = "Center", value = "center" },
    }, align, function(value)
        align = value
        Rows.refreshBlocks({ "generateAlign" })
    end,
        "Edge the pieces line up on: inside of the bend,\noutside, or their middles.")
end




local function buildAmount(holder)
    Rows.begin()
    amountForAtmo = forAtmo()
    local pieces = (amountForAtmo and "Pieces in the shape, as many as the atmo has room\nfor (Settings > Max atmo objects)"
        or "Pieces in the shape, as many as there are free ids\n(joined ones: free dynamic ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS .. ")") ..
        ". 1, or values that\ncan't make a shape: one default object"
    if amountForAtmo then
        inwuts.generateAmount = createInputRow("Amount", holder, function() generate() end, { GENERATE_AMOUNT .. " obj" },
            pieces .. ".\nEnter in any field generates.", nil, FORM_WHOLE)
    else
        inwuts.generateAmount = createInputRow("Amount", holder, function() generate() end,
            { GENERATE_AMOUNT .. " obj", GENERATE_JOINTS .. " joint" },
            pieces .. ",\nand joints between neighbours (1: rigid, 2: a hinge).\n" ..
            "Enter in any field generates.", nil, FORM_WHOLE)
        local joints = inwuts.generateAmount[JOINTS]
        if keptJoints ~= "" then joints.textfieldstr[1], joints.textfieldindex = keptJoints, #keptJoints end
        keptJoints = ""
    end
end



local gizmoLabels, highlightGizmoLabels = Rows.gizmoLabels()



local bendInputs, sizeInputs = {}, {}

local function joinGenerateInputs()
    local inputs = {}
    for _, list in ipairs({ bendInputs, sizeInputs }) do
        for _, input in ipairs(list) do inputs[#inputs + 1] = input end
    end
    inwuts.generate = inputs
end



local function addAll(list, row)
    for _, input in ipairs(row) do list[#list + 1] = input end
end




local function buildBend(holder)
    Rows.begin()
    local function apply() generate() end
    bendInputs = {}
    addAll(bendInputs, createInputRow("Gap", holder, apply, { "0.00" }, "Space between pieces, negative overlaps.", nil, FORM))
    addAll(bendInputs, createInputRow("Angle", holder, apply, { tostring(GENERATE_ANGLE) },
        "Total bend: 0 line, 90 quarter pipe, 360 loop.", nil, { mode = "form", angle = true }))
    joinGenerateInputs()
end



local function buildSize(holder)
    Rows.begin()
    local function apply() generate() end
    sizeInputs = {}
    local row, _, sizeLabel = createInputRow("Size", holder, apply, formatHints(defaultSides()),
        "First piece's size, empty: the default object's.\nThe Scale gizmo on the preview sets it too.", nil, FORM)
    addAll(sizeInputs, row)
    gizmoLabels.scale = sizeLabel
    addAll(sizeInputs, createInputRow("Increment", holder, apply, { "0.00", "0.00", "0.00" },
        "Added to each next piece's size, negative shrinks.\nThe Scale gizmo scales it along with Size.", nil, FORM))
    joinGenerateInputs()
    highlightGizmoLabels()
end



local function buildPosition(holder)
    Rows.begin()
    local _
    inwuts.generatePos, _, gizmoLabels.move = createInputRow("Position", holder, function() generate() end, positionHints,
        "Center from the dojo center, empty: in front of\nthe camera. The Move gizmo drags the preview too.", nil, FORM)
    highlightGizmoLabels()
end




local function buildRot(holder)
    Rows.begin()
    local _
    inwuts.generateRot, _, gizmoLabels.rotate = createInputRow("Rot", holder, function() generate() end,
        { "0", "0", "0" }, "Turns each piece around its center (degrees),\nlike Size. The Rotate gizmo turns them too.",
        nil, { mode = "form", angle = true })
    highlightGizmoLabels()
end



local function resetFields()
    for _, key in ipairs({ "generate", "generateAmount", "generatePos", "generateRot" }) do
        for _, input in ipairs(inwuts[key] or {}) do
            if not input.destroyed then input:clearTextfield() end
        end
    end
    keptJoints = ""
end



local function buildButtons(holder)
    Rows.begin()
    createToggleButtonRow("", holder, {
        { label = "Reset", active = false, onClick = resetFields },
        { label = "To view", active = false, onClick = toView },
        { label = "Generate", active = false, onClick = generate },
    }, "Reset: back to the defaults. To view: moves the\npreview in front of the camera. Generate: adds it.")
end



return {
    fixed = {


        { build = buildBend, panel = "generate", row = 2, rows = 2 },
        { build = buildRot, panel = "generate", row = 5, rows = 1 },
        { build = buildSize, panel = "generate", row = 6, rows = 2 },
        { build = buildButtons, panel = "generate", row = 8, rows = 1 },
    },
    blocks = {
        { name = "generateAlign", build = buildAlign, panel = "generate", row = 0, rows = 1 },
        { name = "generateAmount", build = buildAmount, panel = "generate", row = 1, rows = 1 },
        { name = "generatePos", build = buildPosition, panel = "generate", row = 4, rows = 1 },
    },
    inputs = { fixed = { "generate", "generateRot" }, rebuilt = { "generateAmount", "generatePos" } },
}
