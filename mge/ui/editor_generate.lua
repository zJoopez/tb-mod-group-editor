-- Generate tab: lines, ramps, loops, stairs and pyramids made of default objects (geometry in utils/shape_gen.lua),
-- placed in front of the camera, or where the Position row says. The Move gizmo drags the preview
-- (Camera follow on: the camera looks at the shape when the tab opens and after every change). Amount's
-- second field joins each two
-- neighbouring pieces: 1 joint between their centers, 2 at their edges like a door's hinges
-- (ShapeGen.joints). Joined pieces are made dynamic, static ones wouldn't move at the joints
local Rows = MGE.EditorRows
local inwuts = Rows.inputs
local formatHints = Rows.formatHints
local createInputRow = Rows.createInputRow
local createChoiceRow = Rows.createChoiceRow
local createToggleButtonRow = Rows.createToggleButtonRow

local Transforms = MGE.Transforms

-- used for empty Generate fields, shown as their placeholders
local GENERATE_AMOUNT = 8
local GENERATE_JOINTS = 0 -- joints between each two neighbouring pieces: 0, 1 or 2
local GENERATE_ANGLE = 90

-- inwuts.generate indexes: Amount (pieces, joints), Gap, Angle, Size x y z, Increment x y z
local FIELD = { amount = 1, joints = 2, gap = 3, angle = 4, size = 4, increment = 7 } -- size / increment: + axis
local MAX_GENERATE = 200 -- more than any mod has room for, stops a typo from planning thousands

---@type GenerateAlign kept while the script runs
local align = "out"

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
---@type { origin: number[], dir: number[], point: number[]? }?
local anchor = nil
local anchorVersion = 0 -- part of the preview's key: a new view line plans the preview again
-- the gizmo's Move on the preview: how far it was moved from the view line, on the axes without a
-- typed Position value (a typed one gets the move in its text instead). Back to 0 with the view line
local moved = { 0, 0, 0 }

---Takes the camera's current view line as the place for the shape
local function anchorToView()
    local origin, dir = MGE.Camera.viewRay()
    anchor = { origin = origin, dir = dir }
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
---@return GeneratePiece[] pieces
---@return string? note why it's one default object instead of the shape (nil for Amount 1 or less)
---@return number[] center where the shape is, Pos-row style
---@return GenerateJoint[] joints between neighbouring pieces, where they end up
local function planFromFields()
    local fields = inwuts.generate or {}
    local function typed(i) return fields[i] and not fields[i].destroyed and tonumber(fields[i].textfieldstr[1]) end
    local amount = math.floor((typed(FIELD.amount) or GENERATE_AMOUNT) + 0.5)
    local perPair = math.floor((typed(FIELD.joints) or GENERATE_JOINTS) + 0.5)
    local sides, increment = defaultSides(), {}
    for i = 1, 3 do
        local value = typed(FIELD.size + i)
        if value and value > 0 then sides[i] = math.max(value, MGE.MIN_SIDE) end
        increment[i] = typed(FIELD.increment + i) or 0
    end
    local note
    if amount > MAX_GENERATE then
        note = "amount must be at most " .. MAX_GENERATE
    elseif amount >= 2 and (perPair < 0 or perPair > 2) then
        note = "joints between two pieces must be 0, 1 or 2"
    elseif amount >= 2 then
        local jointCount, free = (amount - 1) * perPair, #MGE.Joints.freeIds()
        local most = MGE.ShapeGen.maxPieces(sides, increment)
        if jointCount > free then
            note = jointCount .. " joints needed, " .. free .. " free (max " .. MGE.MAX_ENV_JOINTS .. "), use fewer pieces"
        elseif most and amount > most then
            note = "the increment shrinks pieces to nothing after " .. most .. " pieces, use fewer or a smaller increment"
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
    anchor.point = anchor.point or MGE.Camera.spawnPoint(bounds, anchor.origin, anchor.dir)
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
    return pieces, note, shown, ShapeGen.joints(pieces, perPair) -- from the placed pieces
end

-- Preview: the pieces Generate would add and their joints' anchors, drawn by utils/highlight.lua while
-- the Generate tab is open. Planned again only when a field's text, Align or the view line changes, the
-- draw hook asks every frame
local previewKey, previewPieces, previewAnchors
local previewShown = false -- false while the tab is closed, opening it takes the view line again
---@type string[] placeholders of the Position row: where the shape is, empty fields keep it there
local positionHints = { "0.00", "0.00", "0.00" }

---@type number[]? the gizmo drag in progress: the preview is drawn moved by it, planned when released
local liveOffset = nil

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
    local parts = { align .. "#" .. anchorVersion, table.concat(moved, ",") }
    addTexts(inwuts.generate, parts)
    addTexts(inwuts.generatePos, parts)
    return table.concat(parts, "|")
end

---Camera follow on: the camera looks at the preview, keeping its distance when the shape still fits,
---like moving objects does
local function followPreview()
    if not MGE.Camera.followMoves or not previewPieces then return end
    local center, radius = piecesCenter(previewPieces), 0
    for _, piece in ipairs(previewPieces) do
        local d, half = 0, 0
        for k = 1, 3 do
            d = d + (piece.pos[k] - center[k]) ^ 2
            half = half + piece.sides[k] ^ 2
        end
        radius = math.max(radius, math.sqrt(d) + math.sqrt(half) / 2)
    end
    MGE.Camera.focusOn(center, math.min(radius, MGE.Camera.maxObjectRadius), true)
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
    previewPieces, _, center, joints = planFromFields() -- one default object when the values can't make a shape
    previewAnchors = {}
    for i, joint in ipairs(joints or {}) do previewAnchors[i] = joint.pos end
    showPosition(center)
    followPreview()
end

---@return boolean the Generate tab is open on the Objects list in MGE's shown window, its preview is drawn
local function tabOpen()
    local Main = MGE.Main
    return Main.activeTab == "generate" and Main.listTab == "objects" and inwuts.generate ~= nil
        and Main.window ~= nil and Main.window.displayed == true
end

MGE.Highlight.preview = function()
    if not tabOpen() then
        previewShown = false
        liveOffset = nil
        return nil
    end
    if not previewShown then -- the tab just opened: the shape goes where the camera looks now
        previewShown = true
        anchorToView() -- a new key: planned again below, and the camera looks at it
    end
    if fieldsKey() ~= previewKey then replan() end
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

-- While the preview is shown it has the gizmo: Move works on it (not on the selection), Rotate and
-- Scale show no gizmo. After Generate there's no preview until a value changes, the gizmo is back
-- on the selection (the generated pieces)
MGE.Gizmo.previewTarget = function(mode)
    if not (previewShown and previewPieces and tabOpen()) then return nil end
    if mode ~= "move" then return false end
    local pieces = previewPieces -- the pivot stays where the drag started, even if the plan changes
    local function clear() liveOffset = nil end
    return {
        pivot = function() return piecesCenter(pieces) end,
        frame = function() return MGE.Mat3.IDENTITY end,
        previewMove = function(offset) liveOffset = offset end,
        previewRotate = function() end,
        liveSides = function() return nil end,
        restoreLive = clear,
        moveBy = moveBy,
        rotateByMatrix = clear,
    }
end

---Generate button / Enter: adds the shape, made of the default object: static, or dynamic when joints
---join the pieces (static ones wouldn't move at the joints). The joints come in the same undo step
local function generate()
    local pieces, note, _, joints = planFromFields()
    -- what the preview shows is what's added: say why it's one object instead of the shape
    if note then echo("^04[MGE] Generate: " .. note .. ", added one default object instead") end

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
        "Edge the pieces line up on. In: inside of the bend (top).\n" ..
        "Out: outside (bottom), Increment Z 0.3: stairs.\n" ..
        "Center: middles, Increment Y, Z 0.3: pyramid.")
end

---Generate panel: amount, gap, angle, piece size and increment. Nothing depends on the selection,
---placeholders show the values empty fields use
---@param holder UIElement
local function buildGenerate(holder)
    Rows.begin()
    local function apply() generate() end
    local inputs = {}
    local function add(row)
        for _, input in ipairs(row) do table.insert(inputs, input) end
    end
    add(createInputRow("Amount", holder, apply, { GENERATE_AMOUNT .. " obj", GENERATE_JOINTS .. " joint" },
        "Pieces in the shape, max " .. MAX_GENERATE .. " (1, or values that\ncan't make a shape: one default object),\nand joints between each two\n" ..
        "neighbours: 1 between their centers, 2 at their\n" ..
        "edges (a hinge). Joined pieces are made dynamic.\n" ..
        "Enter in any field generates."))
    add(createInputRow("Gap", holder, apply, { "0.00" }, "Space between pieces, negative overlaps."))
    add(createInputRow("Angle", holder, apply, { tostring(GENERATE_ANGLE) },
        "Total bend: 0 line, 90 quarter pipe, 360 loop."))
    add(createInputRow("Size", holder, apply, formatHints(defaultSides()),
        "First piece's size, empty: the default object's."))
    add(createInputRow("Increment", holder, apply, { "0.00", "0.00", "0.00" },
        "Added to each next piece's size, negative shrinks."))
    inwuts.generate = inputs
end

---Position row (rebuilt when the shape moves): placeholders show where the shape is now
---@param holder UIElement
local function buildPosition(holder)
    Rows.begin()
    inwuts.generatePos = createInputRow("Position", holder, function() generate() end, positionHints,
        "Shape's center like Pos shows it (from the dojo center).\n" ..
        "Empty: in front of the camera, typed axes stay put.\n" ..
        "The Move gizmo drags the preview too.\n" ..
        "To view clears it and the gizmo's moves.")
end

---Generate and To view buttons
---@param holder UIElement
local function buildButtons(holder)
    Rows.begin()
    createToggleButtonRow("", holder, {
        { label = "Generate", active = false, onClick = generate },
        { label = "To view", active = false, onClick = toView },
    }, "Generate: adds the orange preview (static pieces, or\ndynamic ones joined) and selects them.\n" ..
        "To view: moves the preview in front of the camera\n(also done when this tab opens), clears Position.")
end


---@type EditorPanelModule
return {
    fixed = {
        { build = buildGenerate, panel = "generate", row = 1, rows = 5 },
        { build = buildButtons, panel = "generate", row = 7, rows = 1 },
    },
    blocks = {
        { name = "generateAlign", build = buildAlign, panel = "generate", row = 0, rows = 1 },
        { name = "generatePos", build = buildPosition, panel = "generate", row = 6, rows = 1 },
    },
    inputs = { fixed = { "generate" }, rebuilt = { "generatePos" } },
}
