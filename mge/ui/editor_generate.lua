-- Generate tab: lines, ramps, loops, stairs and pyramids made of default objects (geometry in utils/shape_gen.lua),
-- placed in front of the camera, or where the Position row says. The Move gizmo drags the preview, the
-- Scale gizmo sizes its pieces (Size and Increment, along the first piece's axes) (Camera follow on: the camera looks at the shape when the tab opens and after every change). Amount's
-- second field joins each two
-- neighbouring pieces: 1 joint between their centers, 2 at their edges like a door's hinges
-- (ShapeGen.joints). Joined pieces are made dynamic, static ones wouldn't move at the joints
-- On the Atmo list the same tab adds the pieces to the atmo (utils/atmo_layer.lua): no joints there,
-- atmos have none
local Rows = MGE.EditorRows
local inwuts = Rows.inputs
local formatHints = Rows.formatHints
local createInputRow = Rows.createInputRow
-- fields the Generate action reads (Enter generates): the wheel only changes their text (ui/editor_rows.lua)
local FORM = { mode = "form" }
local FORM_WHOLE = { mode = "form", whole = true } -- Amount: pieces and joints, the wheel steps by 1
local createChoiceRow = Rows.createChoiceRow
local createToggleButtonRow = Rows.createToggleButtonRow

local Transforms = MGE.Transforms

-- used for empty Generate fields, shown as their placeholders
local GENERATE_AMOUNT = 8
local GENERATE_JOINTS = 0 -- joints between each two neighbouring pieces: 0, 1 or 2
local GENERATE_ANGLE = 90

-- inwuts.generate indexes: Gap, Angle, Size x y z, Increment x y z
local FIELD = { gap = 1, angle = 2, size = 2, increment = 5 } -- size / increment: + axis
-- inwuts.generateAmount (a rebuilt row): pieces, and joints on the Objects list only (atmos have none)
local AMOUNT, JOINTS = 1, 2
---@type boolean? the list the Amount row was built for (true: Atmo, no joints field), nil before it's built
local amountForAtmo = nil
local keptJoints = "" -- the joints field's text while the Atmo list's row (without it) is shown

---@type GenerateAlign kept while the script runs
local align = "out"

---@return boolean the Atmo list is shown: the pieces go to the atmo, without joints
local function forAtmo()
    return MGE.Main ~= nil and MGE.Main.listTab == "atmo"
end

---The most pieces Generate can add now, and what limits it. Objects: the free ids, joined pieces (they're
---dynamic) only as many as fit in ids 1-MAX_NONSTATIC_OBJECTS. Atmo list: the atmo's room (Settings > Most
---atmo objects): its default 256 keeps a typo from planning thousands, raising it is the player's call. It
---was a fixed 200, which kept the atmo from getting more at once
---@param atmo boolean the Atmo list (forAtmo)
---@param perPair integer joints between two pieces
---@return integer most
---@return string limit what limits it, for the note
local function maxGenerate(atmo, perPair)
    local ModData = MGE.ModData
    if atmo then return MGE.AtmoLayer.room(), "room in the atmo" end
    local free = ModData.freeCount()
    if perPair > 0 then
        local dynamicRoom = math.max(0, MGE.MAX_NONSTATIC_OBJECTS - ModData.countDynamic())
        if dynamicRoom < free then return dynamicRoom, "free dynamic ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS end
    end
    return free, "free ids"
end

---What the limits depend on, for the preview's key: the preview is planned again when they change (an
---import, a delete, Max atmo objects), so it never shows something Generate wouldn't add
---@return string
local limitsCache = {} -- countDynamic scans every object: once per undo state / reload, not every frame
local function limitsKey()
    local ModData = MGE.ModData
    local state = MGE.History.states[MGE.History.index]
    if limitsCache.parsed ~= ModData.parsed or limitsCache.state ~= state then
        limitsCache = { parsed = ModData.parsed, state = state, dynamic = ModData.countDynamic() }
    end
    return MGE.AtmoLayer.room() .. "," .. ModData.freeCount() .. "," .. limitsCache.dynamic
end

---@return number[] sides of the default object (ui/assets.lua), what empty Size fields use
local function defaultSides()
    local sides = {}
    for v in MGE.Assets.defaultProps().sides:gmatch("%S+") do table.insert(sides, tonumber(v) or 0.5) end
    return sides
end

-- Where the shape goes: in front of the camera (Camera.spawnPoint), along the view line taken
-- when the tab opens or To view is clicked. The point is taken with the first shape planned there
-- and kept: other values (Amount, Angle, Size...) change the shape around it (its middle, its bottom
-- on the point), they don't move it along the view line. Camera follow on: the camera looks at the
-- shape after every change, backing off when it no longer fits
---@type { origin: number[], dir: number[], look: number?, point: number[]? }?
local anchor = nil
local anchorVersion = 0 -- part of the preview's key: a new view line plans the preview again
-- the gizmo's Move on the preview: how far it was moved from the view line, on the axes without a
-- typed Position value (a typed one gets the move in its text instead). Back to 0 with the view line
local moved = { 0, 0, 0 }

---Takes the camera's current view line as the place for the shape
local function anchorToView()
    -- look: MGE's camera looks at a point, the shape goes there (Camera.spawnPoint)
    local origin, dir, look = MGE.Camera.viewRay()
    anchor = { origin = origin, dir = dir, look = look }
    anchorVersion = anchorVersion + 1
    moved = { 0, 0, 0 }
end

---To view button: back to the automatic place, typed Position values are cleared too
local function toView()
    for _, input in ipairs(inwuts.generatePos or {}) do
        if not input.destroyed then input:clearTextfield() end
    end
    anchorToView()
end

---Center of the pieces, the way the Core tab's Pos row shows a selection: average of the positions
---@param pieces GeneratePiece[]
---@return number[]
local function piecesCenter(pieces)
    local c = { 0, 0, 0 }
    for _, piece in ipairs(pieces) do
        for k = 1, 3 do c[k] = c[k] + piece.pos[k] / #pieces end
    end
    return c
end

---Pieces for the typed values (empty fields use their placeholders), same for the preview and Generate.
---Placed in front of the camera and moved as far as the gizmo moved the preview, then moved on the
---axes typed in the Position row: those are the center the Pos row would show for the generated
---pieces, counted from the dojo center (MGE.POS_ORIGIN)
---Values that can't make a shape (Amount 1 or less, too many pieces or joints, an increment that
---shrinks pieces to nothing) give one default object instead: flat, the typed Size, no joints
---@param factors number[]? a Scale gizmo drag in progress: Size and Increment multiplied per axis
---@return GeneratePiece[] pieces
---@return string? note why it's one default object instead of the shape (nil for Amount 1 or less)
---@return number[] center where the shape is, Pos-row style
---@return GenerateJoint[] joints between neighbouring pieces, where they end up
---@return number[] middle the middle of the shape's bounds, world: what the camera looks at
local function planFromFields(factors)
    local function reader(fields)
        return function(i) return fields[i] and not fields[i].destroyed and tonumber(fields[i].textfieldstr[1]) end
    end
    local typed, typedAmount = reader(inwuts.generate or {}), reader(inwuts.generateAmount or {})
    local amount = math.floor((typedAmount(AMOUNT) or GENERATE_AMOUNT) + 0.5)
    local perPair = math.floor((typedAmount(JOINTS) or GENERATE_JOINTS) + 0.5)
    local atmo = forAtmo()
    if atmo then perPair = 0 end -- atmos have no joints (the row has no joints field there)
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
    -- joints only between two or more pieces: Amount 1 makes none, its id needn't be a dynamic one
    local most, limit = maxGenerate(atmo, amount >= 2 and math.max(perPair, 0) or 0)
    if most == 0 then
        if atmo then
            note = "no room in the atmo (Settings > Max atmo objects)"
        elseif MGE.ModData.freeCount() > 0 then
            note = "no free dynamic ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS .. " for joined pieces: Joints 0, or Reindex (Misc)"
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
        { 0, 0 }, { increment = increment, align = align })
    if not anchor then anchorToView() end
    ---@cast anchor -nil
    -- the first shape there picks the point (far enough to fit it on screen), later ones keep it
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
    -- the middle of the shape's bounds, where it was placed (Camera.spawnPoint: x y the middle, z its
    -- bottom): the camera looks there. The pieces' average is off it for a bend or a ramp, looking at
    -- that moved the next placement (on the look-at point) by the difference every time the tab opened
    local point = anchor.point ---@cast point -nil
    local middle = { point[1] + shift[1], point[2] + shift[2], point[3] + (bounds.max[3] - bounds.min[3]) / 2 + shift[3] }
    return pieces, note, shown, ShapeGen.joints(pieces, perPair), middle -- joints from the placed pieces
end

-- Preview: the pieces Generate would add and their joints' anchors, drawn by utils/highlight.lua while
-- the Generate tab is open. Planned again only when a field's text, Align or the view line changes, the
-- draw hook asks every frame
local previewKey, previewPieces, previewAnchors
---@type number[]? the middle of the preview's bounds (planFromFields), where camera follow looks
local previewMiddle
local previewShown = false -- false while the tab is closed, opening it takes the view line again
---@type string[] placeholders of the Position row: where the shape is, empty fields keep it there
local positionHints = { "0.00", "0.00", "0.00" }

---@type number[]? the gizmo drag in progress: the preview is drawn moved by it, planned when released
local liveOffset = nil
---@type number[]? a Scale drag in progress: the preview is planned with these factors every frame
local liveFactors = nil

---@param list UIElement[]?
---@param parts string[] texts are added to it
local function addTexts(list, parts)
    for _, field in ipairs(list or {}) do
        table.insert(parts, field.destroyed and "" or field.textfieldstr[1])
    end
end

---@return string everything the plan depends on
local function fieldsKey()
    ---@type string[]
    local parts = { align .. "#" .. anchorVersion, table.concat(moved, ","), limitsKey() }
    addTexts(inwuts.generateAmount, parts)
    addTexts(inwuts.generate, parts)
    addTexts(inwuts.generatePos, parts)
    return table.concat(parts, "|")
end

---Camera follow on: the camera looks at the preview, keeping its distance when the shape still fits,
---like moving objects does. At the middle of its bounds, where it was placed: the next placement goes on
---the point the camera looks at (Camera.spawnPoint), so opening the tab again leaves it where it is
local function followPreview()
    if not MGE.Camera.followMoves or not previewPieces then return end
    local center, radius = previewMiddle or piecesCenter(previewPieces), 0
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

---Position row placeholders follow the planned shape (rebuilt block, typed text is kept over it)
---@param center number[]? Pos-row style center from planFromFields
local function showPosition(center)
    if not center then return end
    local hints = formatHints(center)
    if hints[1] == positionHints[1] and hints[2] == positionHints[2] and hints[3] == positionHints[3] then return end
    positionHints = hints
    Rows.refreshBlocks({ "generatePos" })
end

---Plans the preview for the fields as they are now (tab opened, To view, any value, a gizmo move),
---the camera follows it (Camera follow on)
local function replan()
    previewKey = fieldsKey()
    local center, joints, _
    -- one default object when the values can't make a shape
    previewPieces, _, center, joints, previewMiddle = planFromFields()
    previewAnchors = {}
    for i, joint in ipairs(joints or {}) do previewAnchors[i] = joint.pos end
    showPosition(center)
    followPreview()
end

---@return boolean the Generate tab is open on the Objects or Atmo list in MGE's shown window, its preview is drawn.
---The shown list's own active tab (Main.activeTabs): Main.activeTab is only the Objects list's, the Atmo list's
---Generate showed no preview unless the Objects list was on Generate too
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
        liveOffset, liveFactors = nil, nil
        return nil
    end
    if not previewShown then -- the tab just opened: the shape goes where the camera looks now
        previewShown = true
        anchorToView() -- a new key: planned again below, and the camera looks at it
    end
    -- the Amount row was built for the other list (the tab is shared): joints field there or not
    if amountForAtmo ~= forAtmo() then
        local joints = (inwuts.generateAmount or {})[JOINTS]
        if joints and not joints.destroyed then keptJoints = joints.textfieldstr[1] or "" end
        Rows.refreshBlocks({ "generateAmount" })
    end
    if fieldsKey() ~= previewKey then replan() end
    if liveFactors and previewPieces then -- a Scale drag: the shape as it would be, planned each frame
        local pieces, _, _, joints = planFromFields(liveFactors)
        local anchors = {}
        for i, joint in ipairs(joints or {}) do anchors[i] = joint.pos end
        return pieces, anchors
    end
    if not (liveOffset and previewPieces) then return previewPieces, previewAnchors end
    -- a gizmo drag in progress: drawn where it's dragged to
    local add = MGE.GizmoMath.add
    local boxes, anchors = {}, {}
    for i, piece in ipairs(previewPieces) do
        boxes[i] = { pos = add(piece.pos, liveOffset), frame = piece.frame, sides = piece.sides }
    end
    for i, p in ipairs(previewAnchors) do anchors[i] = add(p, liveOffset) end
    return boxes, anchors
end

---Gizmo Move released on the preview: typed Position axes get the move in their text, the others keep
---it in moved. Planned again right away, so the gizmo is at the new place on the next frame
---@param offset number[]
local function moveBy(offset)
    liveOffset = nil
    if not tabOpen() then return end -- closed mid drag: the next opening takes the view line anyway
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

---Field text for a size: up to 4 decimals, no trailing zeros
---@param value number
---@return string
local function sizeText(value)
    local s = string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end

---Gizmo Scale released on the preview: Size gets the factors in its text (empty fields: the default
---object's size scaled), typed Increment axes too, so stairs and pyramids keep their shape
---@param factors number[] along the first piece's axes, which are Size's x y z
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

-- While the preview is shown it has the gizmo (not the selection): Move drags it, Scale sizes its
-- pieces (the Size and Increment fields) along the first piece's axes, Rotate shows no gizmo. After
-- Generate there's no preview until a value changes, the gizmo is back on the selection (the
-- generated pieces)
MGE.Gizmo.previewTarget = function(mode)
    if not (previewShown and previewPieces and tabOpen()) then return nil end
    if mode ~= "move" and mode ~= "scale" then return false end
    local pieces = previewPieces -- the pivot stays where the drag started, even if the plan changes
    local function clear() liveOffset, liveFactors = nil, nil end
    return {
        scalable = true,
        pivot = function() return piecesCenter(pieces) end,
        -- Scale: the first piece's axes, its sides are the Size fields. Move: the world's
        frame = function() return mode == "scale" and pieces[1].frame or MGE.Mat3.IDENTITY end,
        previewMove = function(offset) liveOffset = offset end,
        previewRotate = function() end,
        previewScale = function(factors) liveFactors = factors end,
        liveSides = function() return nil end,
        restoreLive = clear,
        moveBy = moveBy,
        rotateByMatrix = clear,
        scaleBy = scaleBy,
    }
end

---The pieces as atmo objects, the default object's look lines (as the Atmo list's New makes them)
---@param pieces GeneratePiece[]
---@return FileParserEnvObj[]
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

---Generate button / Enter: adds the shape, made of the default object: static, or dynamic when joints
---join the pieces (static ones wouldn't move at the joints). The joints come in the same undo step.
---On the Atmo list the pieces go to the atmo instead (one undo step, no reload)
local function generate()
    local pieces, note, _, joints = planFromFields()
    -- no room at all: nothing to add (not even the one default object the preview shows)
    if maxGenerate(forAtmo(), 0) == 0 then
        MGE.say("Generate: " .. tostring(note))
        return
    end
    -- what the preview shows is what's added: say why it's one object instead of the shape
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
        -- a ramp stays in place, and static ids are plenty. Joined pieces move: dynamic
        obj.props.flag = #joints > 0 and "0" or tostring(MGE.FLAGS.STATIC)
        Transforms.writeVector(obj, "pos", piece.pos)
        Transforms.writeVector(obj, "rot", piece.rot)
        Transforms.writeVector(obj, "sides", piece.sides)
        objects[i] = obj
    end
    -- the pieces' ids here are their indexes, the import gives them and the joints real ids. Visible so
    -- the joints show in game (the Joints list's Properties tab can hide them)
    local jointBlocks = {}
    for i, joint in ipairs(joints) do
        jointBlocks[i] = { kind = "env_obj_joint", id = i, obj1 = joint.a, obj2 = joint.b, lines = {},
            props = { pos = MGE.FileHandler.formatNumbers(joint.pos[1], joint.pos[2], joint.pos[3]), visible = MGE.Joints.NEW_VISIBLE } }
    end
    -- selected and saved like an import, the tab stays so values can be tried again after Undo
    MGE.Assets.addObjects(objects, true, nil, jointBlocks)
    -- the shape is there now (highlighted as the selection), the preview comes back when a value changes
    previewKey, previewPieces, previewAnchors = fieldsKey(), nil, nil
end

---Align row (generate panel), rebuilt on a click so the current choice is highlighted
---@param holder UIElement
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

---Amount row (rebuilt: the tab is on both lists): pieces, and on the Objects list the joints between
---each two neighbours. The Atmo list has no joints field, atmos have no joints
---@param holder UIElement
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
        keptJoints = "" -- back in the field: later rebuilds (selection changes) keep the field's own text
    end
end

---Generate panel: gap, angle, piece size and increment. Nothing depends on the selection,
---placeholders show the values empty fields use
---@param holder UIElement
local function buildGenerate(holder)
    Rows.begin()
    local function apply() generate() end
    local inputs = {}
    local function add(row)
        for _, input in ipairs(row) do table.insert(inputs, input) end
    end
    add(createInputRow("Gap", holder, apply, { "0.00" }, "Space between pieces, negative overlaps.", nil, FORM))
    add(createInputRow("Angle", holder, apply, { tostring(GENERATE_ANGLE) },
        "Total bend: 0 line, 90 quarter pipe, 360 loop.", nil, { mode = "form", angle = true }))
    add(createInputRow("Size", holder, apply, formatHints(defaultSides()),
        "First piece's size, empty: the default object's.\nThe Scale gizmo on the preview sets it too.", nil, FORM))
    add(createInputRow("Increment", holder, apply, { "0.00", "0.00", "0.00" },
        "Added to each next piece's size, negative shrinks.\nThe Scale gizmo scales it along with Size.", nil, FORM))
    inwuts.generate = inputs
end

---Position row (rebuilt when the shape moves): placeholders show where the shape is now
---@param holder UIElement
local function buildPosition(holder)
    Rows.begin()
    inwuts.generatePos = createInputRow("Position", holder, function() generate() end, positionHints,
        "Center from the dojo center, empty: in front of\nthe camera. The Move gizmo drags the preview too.", nil, FORM)
end

---Empties the tab's fields: the preview goes back to the defaults (placeholders). Its fields keep their text
---(form fields, ui/editor_rows.lua), this is how they're cleared
local function resetFields()
    for _, key in ipairs({ "generate", "generateAmount", "generatePos" }) do
        for _, input in ipairs(inwuts[key] or {}) do
            if not input.destroyed then input:clearTextfield() end
        end
    end
    keptJoints = ""
end

---Generate, To view and Reset buttons
---@param holder UIElement
local function buildButtons(holder)
    Rows.begin()
    createToggleButtonRow("", holder, {
        { label = "Reset", active = false, onClick = resetFields }, -- backing out on the left, like Cancel / Off
        { label = "To view", active = false, onClick = toView },
        { label = "Generate", active = false, onClick = generate },
    }, "Reset: back to the defaults. To view: moves the\npreview in front of the camera. Generate: adds it.")
end


---@type EditorPanelModule
return {
    fixed = {
        { build = buildGenerate, panel = "generate", row = 2, rows = 4 },
        { build = buildButtons, panel = "generate", row = 7, rows = 1 },
    },
    blocks = {
        { name = "generateAlign", build = buildAlign, panel = "generate", row = 0, rows = 1 },
        { name = "generateAmount", build = buildAmount, panel = "generate", row = 1, rows = 1 },
        { name = "generatePos", build = buildPosition, panel = "generate", row = 6, rows = 1 },
    },
    inputs = { fixed = { "generate" }, rebuilt = { "generateAmount", "generatePos" } },
}
