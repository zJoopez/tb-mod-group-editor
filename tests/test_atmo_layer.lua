-- utils/atmo_layer.lua: objects over the game's limit (the atmo layer, its file is utils/atmo.lua), To atmo /
-- To objects, ghosts, editing them with the gizmo
local T = ...
local FileHandler = MGE.FileHandler
local ModData = MGE.ModData
local AtmoLayer = MGE.AtmoLayer

-- To atmo / To objects on a small mod: world reads stubbed, MGE.apply only counted
local function setup(objects, joints)
    ModData.parsed = { env_obj = objects, env_obj_joint = joints or {}, atmo = {}, ignores = {}, trailer = {} }
    ModData.freeIds = { nonStatic = {}, static = {} }
    local used = {}
    for _, obj in ipairs(objects) do used[obj.id] = true end
    for id = 1, MGE.MAX_ENV_OBJECTS do
        if not used[id] then table.insert(id <= MGE.MAX_NONSTATIC_OBJECTS and ModData.freeIds.nonStatic or ModData.freeIds.static, id) end
    end
    ModData.jointIds = {}
    MGE.History.reset()
end
local applied = 0
MGE.apply = function() applied = applied + 1 end
get_obj_flag = function() return 0 end
get_obj_color = function() return 0.2, 0.4, 0.6, 1 end

local function object(id, props)
    props = props or {}
    props.pos = props.pos or (id .. " 0 0")
    return { kind = "env_obj", id = id, lines = {}, props = props }
end

T.test("to atmo", function()
    local a = object(60, { flag = "8" })
    local b = object(2) -- no flag or color line: read from the game
    local c = object(3)
    local d = object(70, { flag = "8" })
    setup({ b, c, a, d }, { { kind = "env_obj_joint", id = 1, obj1 = 3, obj2 = 70, props = {}, lines = {} } })
    a.selected, b.selected, c.selected = true, true, true
    applied = 0
    AtmoLayer.moveIn()
    T.eq(#ModData.parsed.env_obj, 2, "joined object stays")
    T.eq(ModData.parsed.env_obj[1], c, "the joined one is c")
    T.eq(#ModData.parsed.atmo, 2, "two in the atmo")
    T.eq(ModData.parsed.atmo[1], b, "atmo in id order")
    T.eq(b.id, 1, "atmo ids are their place")
    T.eq(a.id, 2, "second")
    T.ok(a.selected and b.selected, "still selected")
    T.eq(b.props.flag, "0", "missing flag read from the game")
    T.eq(b.props.color, "0.2 0.4 0.6 1", "missing color read from the game")
    local freed = false
    for _, id in ipairs(ModData.freeIds.nonStatic) do if id == 2 then freed = true end end
    T.ok(freed, "id 2 is free again")
    T.eq(applied, 1, "saved once")
    T.eq(#MGE.History.states, 2, "one undo step")
end)

T.test("to objects", function()
    local a, b, c = object(1, { flag = "8" }), object(2, { flag = "0" }), object(3, { flag = "8" })
    setup({})
    ModData.parsed.atmo = { a, b, c }
    a.selected, c.selected = true, true
    -- one free static id only: a comes back, c stays
    ModData.freeIds = { nonStatic = {}, static = { 100 } }
    applied = 0
    AtmoLayer.moveOut()
    T.eq(#ModData.parsed.env_obj, 1, "one back")
    T.eq(ModData.parsed.env_obj[1], a, "the first selected")
    T.eq(a.id, 100, "on the free id")
    T.eq(#ModData.parsed.atmo, 2, "two stay in the atmo")
    T.eq(b.id, 1, "renumbered")
    T.eq(c.id, 2, "renumbered")
    T.ok(c.selected, "the one left over stays selected")
    T.eq(applied, 1, "saved")

    ModData.freeIds = { nonStatic = {}, static = {} }
    applied = 0
    AtmoLayer.moveOut()
    T.eq(applied, 0, "no free ids: nothing changes")
    T.eq(#ModData.parsed.atmo, 2, "still in the atmo")
end)

T.test("delete atmo objects", function()
    local a, b = object(1), object(2)
    setup({})
    ModData.parsed.atmo = { a, b }
    a.selected = true
    T.eq(AtmoLayer.removeSelected(), 1, "one removed")
    T.eq(ModData.parsed.atmo[1], b, "the other stays")
    T.eq(b.id, 1, "renumbered")
end)

T.test("atmo over a save and undo", function()
    local a = object(5, { flag = "8" })
    setup({ a })
    a.selected = true
    AtmoLayer.moveIn()
    T.eq(ModData.parsed.atmo[1], a, "in the atmo layer")
    T.eq(a.props.pos, "5 0 0", "with its lines")
    local text = FileHandler.modText(ModData.parsed)
    T.ok(not text:find("env_obj 5", 1, true), "not an object any more")
    T.ok(not text:find("#mge", 1, true), "nor in the mod file at all")
    MGE.History.undo()
    T.eq(#ModData.parsed.env_obj, 1, "undo: back in the game")
    T.eq(#ModData.parsed.atmo, 0, "undo: atmo empty")
end)

-- Ghosts and exported atmos turn like the object. What the game draws an object with is get_obj_rot,
-- measured in game (mge/tools/rotcheck.lua, 2026-11-14) for rot 10 -20 30:
local MEASURED = { rot = { 10, -20, 30 },
    rows = { { 0.8138, 0.4698, 0.3420 }, { -0.5438, 0.8232, 0.1632 }, { -0.2049, -0.3188, 0.9254 } } }

T.test("ghost rotation is the game's", function()
    local frame = AtmoLayer.frameOf(MEASURED.rot)
    local a, b = {}, {}
    for i = 1, 3 do
        for j = 1, 3 do a[#a + 1], b[#b + 1] = frame[i][j], MEASURED.rows[i][j] end
    end
    T.nearList(a, b, 1e-4, "rot 10 -20 30 as get_obj_rot gave it")
    -- and the transform code's orientation (what the gizmo and Rot row turn), for any rot
    local r, Mat3 = math.rad, MGE.Mat3
    for _, rot in ipairs({ { 10, -20, 30 }, { 0, 90, 0 }, { 45, 0, 0 }, { -170, 33, 81 }, { 30, 90, -45 } }) do
        local orientation = Mat3.mul(Mat3.rotX(-r(rot[1])), Mat3.mul(Mat3.rotY(-r(rot[2])), Mat3.rotZ(-r(rot[3]))))
        frame = AtmoLayer.frameOf(rot)
        a, b = {}, {}
        for i = 1, 3 do
            for j = 1, 3 do a[#a + 1], b[#b + 1] = frame[i][j], orientation[i][j] end
        end
        T.nearList(a, b, 1e-12, "rot " .. table.concat(rot, " "))
    end
end)

-- the atmo file's rot (the mod's rot line unchanged, utils/atmo.lua), turned into a rotation the way the
-- game's atmo loader does it (Atmospheres.SpawnObject: UIElement3D's EulerRotation of the file's
-- angles), is the object's (AtmoLayer.frameOf). Uses the game's own toriui/uielement3d.lua when it's next to
-- MGE (data/script/toriui), otherwise this check is skipped
T.test("atmo rotation matches the mod file", function()
    local path = T.dir .. "../../toriui/uielement3d.lua"
    local file = io.open(path, "r")
    if not file then
        print("  (skipped: " .. path .. " not found)")
        return
    end
    file:close()
    package.preload["toriui.uielement"] = package.preload["toriui.uielement"] or function()
        UIElement = UIElement or setmetatable({}, { __index = function() return function() end end })
        return UIElement
    end
    dofile(path)
    for _, rot in ipairs({ { 10, -20, 30 }, { 0, 90, 0 }, { 45, 0, 0 }, { -170, 33, 81 }, { 30, 90, -45 } }) do
        local frame = AtmoLayer.frameOf(rot)
        -- what the atmo file gets: written by Atmo.text, read back the way the game reads the line
        local text = MGE.Atmo.text({ objects = { { kind = "env_obj", id = 1, props = { rot = table.concat(rot, " ") } } } })
        local x, y, z = text:match("\n%s*rot%s+(%S+)%s+(%S+)%s+(%S+)")
        local m = Utils3D.MatrixToMatrixTB(EulerRotation.New(tonumber(x), tonumber(y), tonumber(z)):toMatrix())
        -- MGE's highlight hands the frame over row by row (Highlight.toMatrixTB): r0 r1 r2 = first row
        local expected = { frame[1][1], frame[1][2], frame[1][3], frame[2][1], frame[2][2], frame[2][3],
            frame[3][1], frame[3][2], frame[3][3] }
        T.nearList({ m.r0, m.r1, m.r2, m.r4, m.r5, m.r6, m.r8, m.r9, m.r10 }, expected, 1e-9,
            "rot " .. table.concat(rot, " "))
    end
end)

-- Atmo objects through the same transforms as objects (utils/transforms.lua: the rows and the gizmo): the
-- same lines, and the game never touched for them, also with an object of the same id in the world.
-- transforms.lua is loaded here with the world stubbed: one object in the world (its id 1), everything
-- else isn't. AtmoLayer.moveBy / rotateBy / scaleBy (what a gizmo drag's preview draws) write the same lines
if not MGE.Transforms then
    MGE.Joints = MGE.Joints or { idSet = function() return {} end, getLinked = function() return {} end }
    MGE.Camera = MGE.Camera or { followMoves = false }
    MGE.POS_ORIGIN = MGE.POS_ORIGIN or { 0, 0, 0 }
    dofile(MGE.scriptPath .. "utils/transforms.lua")
end
local Transforms = MGE.Transforms
local Mat3 = MGE.Mat3

local worldCalls = 0 -- set_obj_* calls, an atmo object must never make one
---World stubs for one object in the world with these sides and shape (box when nil)
local function world(id, sides, shape)
    get_obj_pos = function(i) if i == id - 1 then return 0, 0, 0 end return nil end
    get_obj_sides = function() return sides[1], sides[2], sides[3] end
    get_obj_shape = function() return shape or MGE.SHAPE.BOX end
    local function count() worldCalls = worldCalls + 1 end
    set_obj_pos, set_obj_rot, set_obj_sides = count, count, count
end

---An atmo copy of an object (same lines, same id: the clash the transforms must stay clear of), in the
---atmo list next to it
local function atmoTwin(obj)
    local twin = { kind = "atmo", id = obj.id, lines = {}, props = ModData.copy(obj.props) }
    ModData.parsed = { env_obj = { obj }, env_obj_joint = {}, atmo = { twin }, ignores = {}, trailer = {} }
    return twin
end

---A second copy for the preview path (AtmoLayer.*By)
local function copyOf(twin)
    return { kind = "atmo", id = twin.id, lines = {}, props = ModData.copy(twin.props) }
end

T.test("atmo objects are told apart from objects with the same id", function()
    local obj = object(1)
    local twin = atmoTwin(obj)
    T.ok(AtmoLayer.isAtmo(twin), "the atmo one")
    T.ok(not AtmoLayer.isAtmo(obj), "the object with the same id isn't")
end)

T.test("atmo move, rotate and scale write what the objects' own would, without touching the game", function()
    local cases = {
        { pos = "1 2 3", rot = "10 -20 30", sides = "2 1 0.5" },
        { pos = "-4 0.5 7", rot = "0 0 45", sides = "1 1 1" },
        { pos = "0 0 0", rot = "0 90 0", sides = "3 0.2 1" },
    }
    for i, props in ipairs(cases) do
        -- move
        local obj = object(1, { pos = props.pos, rot = props.rot, sides = props.sides })
        local twin = atmoTwin(obj)
        local preview = copyOf(twin)
        world(1, { 2, 1, 0.5 })
        Transforms.moveBy({ obj }, { 1, -2, 0.25 })
        worldCalls = 0
        Transforms.moveBy({ twin }, { 1, -2, 0.25 })
        T.eq(worldCalls, 0, "move " .. i .. ": the game untouched")
        AtmoLayer.moveBy({ preview }, { 1, -2, 0.25 })
        T.eq(twin.props.pos, obj.props.pos, "move " .. i)
        T.eq(preview.props.pos, obj.props.pos, "move " .. i .. ": the preview")

        -- rotate around the pivot: rotBy's offsets from the matrix, like the gizmo's rotateByMatrix
        obj = object(1, { pos = props.pos, rot = props.rot, sides = props.sides })
        twin = atmoTwin(obj)
        preview = copyOf(twin)
        local rotation = Mat3.mul(Mat3.mul(Mat3.rotX(0.3), Mat3.rotY(-0.7)), Mat3.rotZ(1.1))
        local pivot = { Transforms.getSelectionPivot({ obj }) }
        T.nearList({ Transforms.getSelectionPivot({ twin }) }, pivot, 1e-12, "rotate " .. i .. ": the same pivot")
        Transforms.rotateByMatrix({ obj }, rotation)
        worldCalls = 0
        Transforms.rotateByMatrix({ twin }, rotation)
        T.eq(worldCalls, 0, "rotate " .. i .. ": the game untouched")
        AtmoLayer.rotateBy({ preview }, rotation, pivot)
        T.eq(twin.props.rot, obj.props.rot, "rotate " .. i .. ": rot line")
        T.eq(twin.props.pos, obj.props.pos, "rotate " .. i .. ": pos line")
        T.eq(preview.props.rot, obj.props.rot, "rotate " .. i .. ": the preview")

        -- scale along the group frame (an object alone: its own axes)
        local s = {}
        for n in props.sides:gmatch("%S+") do s[#s + 1] = tonumber(n) end
        obj = object(1, { pos = props.pos, rot = props.rot, sides = props.sides })
        twin = atmoTwin(obj)
        preview = copyOf(twin)
        world(1, s)
        local frame = Transforms.groupFrame({ obj })
        pivot = { Transforms.getSelectionPivot({ obj }) }
        T.nearList(Transforms.groupExtents({ twin }), Transforms.groupExtents({ obj }), 1e-9,
            "scale " .. i .. ": the Scale row's size from the sides line")
        Transforms.scaleBy({ obj }, { 2, 0.5, 1.5 })
        worldCalls = 0
        Transforms.scaleBy({ twin }, { 2, 0.5, 1.5 })
        T.eq(worldCalls, 0, "scale " .. i .. ": the game untouched")
        AtmoLayer.scaleBy({ preview }, { 2, 0.5, 1.5 }, pivot, frame)
        T.eq(twin.props.sides, obj.props.sides, "scale " .. i .. ": sides line")
        T.eq(twin.props.pos, obj.props.pos, "scale " .. i .. ": pos line")
        T.eq(preview.props.sides, obj.props.sides, "scale " .. i .. ": the preview")
    end
end)

T.test("atmo spheres and pills scale like the objects' shapes", function()
    for _, case in ipairs({ { "sphere", MGE.SHAPE.SPHERE, "0.5 0.5 0.5" }, { "capsule", MGE.SHAPE.CAPSULE, "0.3 2 0" } }) do
        local obj = object(1, { pos = "0 0 0", rot = "0 0 30", sides = case[3], shape = case[1] })
        local twin = atmoTwin(obj)
        local s = {}
        for n in case[3]:gmatch("%S+") do s[#s + 1] = tonumber(n) end
        world(1, s, case[2])
        Transforms.scaleBy({ obj }, { 2, 1, 3 })
        Transforms.scaleBy({ twin }, { 2, 1, 3 })
        T.eq(twin.props.sides, obj.props.sides, case[1])
    end
end)

T.test("a drag's preview leaves the atmo objects as they are", function()
    local a = object(1, { pos = "1 1 1", rot = "0 0 0", sides = "1 1 1" })
    a.kind = "atmo"
    local b = object(2, { pos = "5 5 5" })
    ModData.parsed = { env_obj = {}, env_obj_joint = {}, atmo = { a, b }, ignores = {}, trailer = {} }
    a.selected = true
    AtmoLayer.live = { move = { 0, 0, 2 } }
    local copies = AtmoLayer.liveCopies()
    T.eq(copies[a].props.pos, "1 1 3", "the copy moved")
    T.eq(a.props.pos, "1 1 1", "the object didn't")
    T.eq(copies[b], nil, "unselected ones aren't copied")
    AtmoLayer.live = nil
    T.eq(AtmoLayer.liveCopies(), nil, "no drag, no copies")
    T.nearList(AtmoLayer.center({ a, b }), { 3, 3, 3 }, 1e-9, "center of the pos lines")
end)

T.test("unloading the game's loaded atmo (MGE's start)", function()
    local unloads = 0
    local savedManager, savedAtmo = rawget(_G, "Atmospheres"), rawget(_G, "_ATMO")
    Atmospheres = { Unload = function() unloads = unloads + 1; _ATMO = nil end }
    _ATMO = nil
    T.eq(AtmoLayer.unloadGameAtmo(), false, "nothing loaded: nothing unloaded (the shader isn't reset)")
    T.eq(unloads, 0, "Unload not called")
    _ATMO = {}
    T.eq(AtmoLayer.unloadGameAtmo(), true, "loaded: unloaded")
    T.eq(unloads, 1, "Unload called once")
    T.eq(rawget(_G, "_ATMO"), nil, "the manager's flag is cleared")
    _ATMO = {}
    setup({})
    AtmoLayer.add({ object(1) })
    T.eq(unloads, 1, "adding to the atmo leaves the game's atmo alone")
    Atmospheres = { Unload = function() error("broken") end }
    T.eq(AtmoLayer.unloadGameAtmo(), false, "a failing Unload is caught")
    Atmospheres, _ATMO = savedManager, savedAtmo
end)

T.test("undo / redo of atmo changes: restored without a reload", function()
    local obj = object(1)
    local atmoObj = { kind = "atmo", id = 1, lines = {}, props = { shape = "box", pos = "0 0 0", sides = "1 1 1" } }
    ModData.parsed = { env_obj = { obj }, env_obj_joint = {}, atmo = { atmoObj }, ignores = {}, trailer = {} }
    MGE.History.reset()
    atmoObj.selected = true
    MGE.Transforms.moveBy({ atmoObj }, { 2, 0, 0 }) -- commits, like a gizmo move
    T.eq(atmoObj.props.pos, "2 0 0", "moved")
    applied = 0
    MGE.History.undo()
    local restored = ModData.parsed.atmo[1]
    T.eq(restored.props.pos, "0 0 0", "undo: the old pos line")
    T.eq(restored.kind, "atmo", "undo: still an atmo object")
    T.eq(restored.selected, true, "undo: the selection stays")
    T.eq(applied, 0, "undo: atmo only, no reload")
    MGE.History.redo()
    T.eq(ModData.parsed.atmo[1].props.pos, "2 0 0", "redo: moved again")
    T.eq(applied, 0, "redo: no reload")

    -- New / Delete in the atmo: the list itself changes, still no reload
    ModData.parsed.atmo[2] = { kind = "atmo", id = 2, lines = {}, props = { shape = "box", pos = "5 5 5" } }
    MGE.History.commit()
    MGE.History.undo()
    T.eq(#ModData.parsed.atmo, 1, "undo: the added one is gone")
    T.eq(applied, 0, "undo of an add: no reload")

    -- an object change with it still reloads when it has to (a deleted object)
    ModData.parsed.env_obj = {}
    MGE.History.commit()
    MGE.History.undo()
    T.eq(#ModData.parsed.env_obj, 1, "undo: the object is back")
    T.eq(applied, 1, "an object list change reloads")
end)
