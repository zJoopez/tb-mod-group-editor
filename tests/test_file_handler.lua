-- utils/file_handler.lua: number formatting, mod parsing and writing back
local T = ...
local FileHandler = MGE.FileHandler

T.test("formatNumber", function()
    T.eq(FileHandler.formatNumber(1), "1", "integer")
    T.eq(FileHandler.formatNumber(1.5), "1.5", "trailing zeros dropped")
    T.eq(FileHandler.formatNumber(0.0001), "0.0001", "small sides kept")
    T.eq(FileHandler.formatNumber(-0.00000000001), "0", "negative zero")
    T.eq(FileHandler.formatNumber(1e-12), "0", "below the decimals")
    T.ok(not FileHandler.formatNumber(123456789.25):find("e"), "never an exponent")
    T.eq(FileHandler.formatNumbers(1, 2.5, -3), "1 2.5 -3", "formatNumbers")
end)

local MOD = table.concat({
    "#comment at the top",
    "gamerule",
    "    matchframes 500",
    "",
    "env_obj 1",
    "    shape box",
    "    pos 1 2 3",
    "    # a note kept in place",
    "    sides 0.5 0.5 0.5",
    "    flag 1",
    "env_obj 2",
    "    shape sphere",
    "    pos 4 5 6",
    "    pos 7 8 9",
    "    #mge_frame 1 0 0 0 1 0 0 0 1",
    "env_obj_joint 1 1 2",
    "    pos 2 2 2",
    "player 0",
    "    body head",
    "",
}, "\n")

T.test("ParseMod", function()
    T.files["mod.tbm"] = MOD
    local p = FileHandler.ParseMod("mod.tbm")
    T.eq(#p.env_obj, 2, "objects")
    T.eq(#p.env_obj_joint, 1, "joints")
    T.eq(p.ignores[1], "#comment at the top", "header kept")
    T.eq(#p.ignores, 4, "lines before the first object, blank line included")
    T.eq(p.trailer[1], "player 0", "player section after the objects")
    T.eq(#p.trailer, 2, "trailing blank line trimmed")

    local a, b = p.env_obj[1], p.env_obj[2]
    T.eq(a.id, 1, "id")
    T.eq(a.props.pos, "1 2 3", "pos")
    T.eq(a.props.sides, "0.5 0.5 0.5", "sides")
    T.eq(a.lines[3].raw, "# a note kept in place", "comment kept between props")
    T.eq(b.props.pos, "7 8 9", "duplicate key: the later value wins")
    local posLines = 0
    for _, line in ipairs(b.lines) do
        if line.key == "pos" then posLines = posLines + 1 end
        T.ok(not (line.raw or ""):find("#mge_frame"), "old frame tag dropped")
    end
    T.eq(posLines, 1, "duplicate key written once")

    local j = p.env_obj_joint[1]
    T.eq(j.id, 1, "joint id")
    T.eq(j.obj1, 1, "joint obj1")
    T.eq(j.obj2, 2, "joint obj2")
end)

T.test("ParseMod missing file", function()
    local p = FileHandler.ParseMod("nope.tbm")
    T.eq(#p.env_obj, 0, "no objects")
    T.ok(p.ignores and p.trailer, "lists still there")
end)

T.test("modText round trip", function()
    T.files["mod.tbm"] = MOD
    local text = FileHandler.modText(FileHandler.ParseMod("mod.tbm"))
    T.ok(text:find("env_obj 1\n   shape box\n   pos 1 2 3\n   # a note kept in place\n", 1, true),
        "props in original order, comment in place")
    T.ok(text:find("env_obj_joint 1 1 2", 1, true), "joint header")
    T.ok(text:find("player 0", 1, true) > text:find("env_obj_joint", 1, true), "trailer after the objects")
    T.files["again.tbm"] = text
    T.eq(FileHandler.modText(FileHandler.ParseMod("again.tbm")), text, "a second round changes nothing")
end)

T.test("new props in key order", function()
    local obj = { kind = "env_obj", id = 3, lines = {}, props = { mass = "1", shape = "box", pos = "0 0 0", zzz = "x" } }
    local text = FileHandler.modText({ ignores = {}, env_obj = { obj }, env_obj_joint = {} })
    -- each object block ends with a blank line
    T.eq(text, "env_obj 3\n   shape box\n   pos 0 0 0\n   mass 1\n   zzz x\n", "KEY_ORDER, then unknown keys")
end)
