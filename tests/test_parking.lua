-- utils/parking.lua and the parked blocks in utils/file_handler.lua: objects over the game's limit,
-- kept in the mod file as comments, Park / Unpark, the atmo export
local T = ...
local FileHandler = MGE.FileHandler
local ModData = MGE.ModData
local Parking = MGE.Parking

local MOD = table.concat({
    "gamerule",
    "    matchframes 500",
    "",
    "env_obj 1",
    "   shape box",
    "   pos 1 2 3",
    "",
    "env_obj_joint 1 1 1",
    "   pos 2 2 2",
    "",
    "#mge parked 1",
    "#mge   shape sphere",
    "#mge   pos 4 5 6",
    "#mge   # a note kept in place",
    "#mge   sides 0.5 0 0",
    "",
    "#mge parked 2",
    "#mge   pos 7 8 9",
    "#mge   rot 0 90 0",
    "",
    "player 0",
    "    body head",
}, "\n")

T.test("parked blocks parse", function()
    T.files["parked.tbm"] = MOD
    local p = FileHandler.ParseMod("parked.tbm")
    T.eq(#p.env_obj, 1, "objects")
    T.eq(#p.env_obj_joint, 1, "joints")
    T.eq(#p.parked, 2, "parked")
    T.eq(p.env_obj_joint[1].props.pos, "2 2 2", "the joint before them keeps only its own lines")
    T.eq(#p.env_obj_joint[1].lines, 1, "no parked line in the joint")
    local a, b = p.parked[1], p.parked[2]
    T.eq(a.id, 1, "parked id")
    T.eq(a.kind, "env_obj", "parked kind")
    T.eq(a.props.shape, "sphere", "shape")
    T.eq(a.props.pos, "4 5 6", "pos")
    T.eq(a.lines[3].raw, "# a note kept in place", "comment kept")
    T.eq(b.props.rot, "0 90 0", "second block")
    T.eq(p.trailer[1], "player 0", "player section after them")
end)

T.test("parked blocks round trip", function()
    T.files["parked.tbm"] = MOD
    local text = FileHandler.modText(FileHandler.ParseMod("parked.tbm"))
    T.ok(text:find("#mge parked 1\n#mge   shape sphere\n#mge   pos 4 5 6\n#mge   # a note kept in place\n", 1, true),
        "every line tagged, order kept")
    local joint, parked, player = text:find("env_obj_joint", 1, true), text:find("#mge parked", 1, true), text:find("player 0", 1, true)
    T.ok(joint < parked and parked < player, "after the joints, before the player sections")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        T.ok(not line:match("^%s*parked") and not line:match("^%s+pos 4"), "nothing parked is left untagged: " .. line)
    end
    T.files["again.tbm"] = text
    T.eq(FileHandler.modText(FileHandler.ParseMod("again.tbm")), text, "a second round changes nothing")
end)

T.test("only parked objects", function()
    T.files["only.tbm"] = "gamerule\n    matchframes 500\n\n#mge parked 1\n#mge   pos 1 1 1\n"
    local p = FileHandler.ParseMod("only.tbm")
    T.eq(#p.env_obj, 0, "no objects")
    T.eq(#p.parked, 1, "one parked")
    T.eq(p.ignores[#p.ignores], "", "the blank line before them stays with the header")
end)

-- Park / Unpark on a small mod: world reads stubbed, MGE.apply only counted
local function setup(objects, joints)
    ModData.parsed = { env_obj = objects, env_obj_joint = joints or {}, parked = {}, ignores = {}, trailer = {} }
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

T.test("park", function()
    local a = object(60, { flag = "8" })
    local b = object(2) -- no flag or color line: read from the game
    local c = object(3)
    local d = object(70, { flag = "8" })
    setup({ b, c, a, d }, { { kind = "env_obj_joint", id = 1, obj1 = 3, obj2 = 70, props = {}, lines = {} } })
    a.selected, b.selected, c.selected = true, true, true
    applied = 0
    Parking.park()
    T.eq(#ModData.parsed.env_obj, 2, "joined object stays")
    T.eq(ModData.parsed.env_obj[1], c, "the joined one is c")
    T.eq(#ModData.parsed.parked, 2, "two parked")
    T.eq(ModData.parsed.parked[1], b, "parked in id order")
    T.eq(b.id, 1, "parked ids are their place")
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

T.test("unpark", function()
    local a, b, c = object(1, { flag = "8" }), object(2, { flag = "0" }), object(3, { flag = "8" })
    setup({})
    ModData.parsed.parked = { a, b, c }
    a.selected, c.selected = true, true
    -- one free static id only: a comes back, c stays
    ModData.freeIds = { nonStatic = {}, static = { 100 } }
    applied = 0
    Parking.unpark()
    T.eq(#ModData.parsed.env_obj, 1, "one back")
    T.eq(ModData.parsed.env_obj[1], a, "the first selected")
    T.eq(a.id, 100, "on the free id")
    T.eq(#ModData.parsed.parked, 2, "two stay parked")
    T.eq(b.id, 1, "renumbered")
    T.eq(c.id, 2, "renumbered")
    T.ok(c.selected, "the one left over stays selected")
    T.eq(applied, 1, "saved")

    ModData.freeIds = { nonStatic = {}, static = {} }
    applied = 0
    Parking.unpark()
    T.eq(applied, 0, "no free ids: nothing changes")
    T.eq(#ModData.parsed.parked, 2, "still parked")
end)

T.test("delete parked", function()
    local a, b = object(1), object(2)
    setup({})
    ModData.parsed.parked = { a, b }
    a.selected = true
    T.eq(Parking.removeSelected(), 1, "one removed")
    T.eq(ModData.parsed.parked[1], b, "the other stays")
    T.eq(b.id, 1, "renumbered")
end)

T.test("parked over a save and undo", function()
    local a = object(5, { flag = "8" })
    setup({ a })
    a.selected = true
    Parking.park()
    local text = FileHandler.modText(ModData.parsed)
    T.ok(text:find("#mge parked 1\n#mge   pos 5 0 0\n", 1, true), "written as a parked block")
    T.ok(not text:find("env_obj 5", 1, true), "not an object any more")
    MGE.History.undo()
    T.eq(#ModData.parsed.env_obj, 1, "undo: back in the game")
    T.eq(#ModData.parsed.parked, 0, "undo: nothing parked")
end)

T.test("atmo text", function()
    local a = object(1, { shape = "box", pos = "1 2 3", rot = "10 -20 30", sides = "1 2 3", color = "3 0.5 -1 0.5" })
    local b = object(2, { shape = "cylinder", pos = "0 0 1", sides = "0.5 2 0", visible = "0" })
    local c = object(3, { shape = "sphere", pos = "0 0 2", sides = "0.25 0 0", use_model = "1" })
    local text, written, models = Parking.atmoText({ a, b, c }, "test.tbm")
    T.eq(written, 2, "invisible object left out")
    T.eq(models, 1, "model counted")
    T.ok(text:find("env_obj mge_1\n\tshape box\n\tpos 1 2 3\n\trot -10 20 -30\n\tsize 1 2 3\n\tcolor 2 0.5 0 0.5\n", 1, true),
        "block: rot negated, color clamped to 0-2")
    T.ok(text:find("env_obj mge_2\n\tshape sphere\n", 1, true), "numbered without gaps")
    T.ok(text:find("^# made by MGE from test.tbm"), "comment at the top")
end)

-- the atmo's rot, drawn the way toriui's UIElement3D draws atmo objects, is the mod file's orientation
-- (Parking.frameOf, what MGE's highlight draws). Uses the game's own toriui/uielement3d.lua when it's
-- next to MGE (data/script/toriui), otherwise this check is skipped
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
    for _, rot in ipairs({ { 10, -20, 30 }, { 0, 90, 0 }, { 45, 0, 0 }, { -170, 33, 81 } }) do
        local frame = Parking.frameOf(rot)
        local r = math.rad
        local m = Utils3D.MatrixToMatrixTB(Utils3D.GetMatrixFromEuler(r(-rot[1]), r(-rot[2]), r(-rot[3]), EULER_XYZ))
        -- MGE's highlight hands the frame over row by row (Highlight.toMatrixTB): r0 r1 r2 = first row
        local expected = { frame[1][1], frame[1][2], frame[1][3], frame[2][1], frame[2][2], frame[2][3],
            frame[3][1], frame[3][2], frame[3][3] }
        T.nearList({ m.r0, m.r1, m.r2, m.r4, m.r5, m.r6, m.r8, m.r9, m.r10 }, expected, 1e-9,
            "rot " .. table.concat(rot, " "))
    end
end)
