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

-- Shared player parts (fatkido.tbm: body/joint lines outside player sections, every player gets them):
-- read as every player's own section, written back shared while they're all the same, as full sections for
-- every player once they differ (FileHandler.splitSharedPlayers)
local SHARED = table.concat({
    "#!/usr/bin/toribash",
    "gamerule",
    "   matchframes 350",
    "",
    "# for all players",
    "",
    "   body chest",
    "      pos 1 0.9 2.2",
    "      sides 0.6 0.15 0.26",
    "",
    "   body head",
    "      sides 0.16 0 0",
    "",
}, "\n")

local function count(text, pattern)
    local n = 0
    for _ in text:gmatch(pattern) do n = n + 1 end
    return n
end

T.test("shared player parts: read per player, written back shared", function()
    T.files["fat.tbm"] = SHARED
    local p = FileHandler.ParseMod("fat.tbm")
    FileHandler.splitSharedPlayers(p, 2)
    T.ok(p.sharedPlayers, "remembered as shared")
    T.eq(FileHandler.getSharedPlayerLines(p), nil, "no shared lines left in the data")
    local zero, one = FileHandler.getPlayerLines(p, 0), FileHandler.getPlayerLines(p, 1)
    T.ok(zero and one, "both players have a section")
    T.eq(table.concat(zero, "|"), table.concat(one, "|"), "the same model")
    T.eq(#zero, 5, "both parts with their lines")
    local text = FileHandler.modText(p)
    T.eq(count(text, "player %d"), 0, "all the same: no player sections written")
    T.eq(count(text, "body chest"), 1, "the shared parts once")
    -- reading what was written gives the same again
    T.files["again.tbm"] = text
    local p2 = FileHandler.ParseMod("again.tbm")
    FileHandler.splitSharedPlayers(p2, 2)
    T.eq(FileHandler.modText(p2), text, "a second round changes nothing")
end)

T.test("shared player parts: one player changed, every player written in full", function()
    T.files["fat.tbm"] = SHARED
    local p = FileHandler.ParseMod("fat.tbm")
    FileHandler.splitSharedPlayers(p, 2)
    FileHandler.renumberPlayers(p, { [1] = false }) -- player 1 reset to the default body
    local text = FileHandler.modText(p)
    T.eq(count(text, "player 0"), 1, "player 0 written")
    T.eq(count(text, "player 1"), 0, "player 1 on the default body")
    T.eq(count(text, "body chest"), 1, "player 0's model in its section, nothing shared left")
    local p2 = FileHandler.ParseMod("fat.tbm")
    FileHandler.splitSharedPlayers(p2, 2)
    FileHandler.setPlayerLines(p2, 1, { "   body head", "      sides 0.3 0 0" })
    text = FileHandler.modText(p2)
    T.eq(count(text, "player 0"), 1, "differing models: player 0's section")
    T.eq(count(text, "player 1"), 1, "and player 1's")
    T.eq(count(text, "body chest"), 1, "player 0's full model (player 1's has no chest)")
end)

T.test("shared player parts: a player's own section wins for its parts", function()
    T.files["mixed.tbm"] = SHARED .. "\nplayer 1\n   body head\n      sides 0.5 0 0\n"
    local p = FileHandler.ParseMod("mixed.tbm")
    FileHandler.splitSharedPlayers(p, 2)
    local one = table.concat(FileHandler.getPlayerLines(p, 1), "|")
    T.ok(one:find("body chest", 1, true), "the shared chest")
    T.ok(one:find("sides 0.5 0 0", 1, true), "its own head")
    T.ok(not one:find("sides 0.16 0 0", 1, true), "not the shared head")
end)

T.test("player sections as written stay as they are", function()
    local text = "player 0\n   body head\n      sides 0.3 0 0\n\nplayer 1\n   body head\n      sides 0.3 0 0\n"
    T.files["own.tbm"] = text
    local p = FileHandler.ParseMod("own.tbm")
    FileHandler.splitSharedPlayers(p, 2)
    T.ok(not p.sharedPlayers, "no shared parts: nothing changes")
    T.eq(count(FileHandler.modText(p), "player %d"), 2, "the same models still in their own sections")
end)

T.test("ensureVersion: a mod without a version line gets the modmaker's", function()
    T.files["old.tbm"] = "#!/usr/bin/toribash\ngamerule\n   engageplayerpos 0\n"
    local p = FileHandler.ParseMod("old.tbm")
    T.ok(FileHandler.ensureVersion(p), "added")
    local lines = {}
    for line in (FileHandler.modText(p) .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    T.eq(lines[1], "#!/usr/bin/toribash", "the #! line stays first")
    T.eq(lines[2], "version " .. FileHandler.MOD_VERSION, "version right after it")
    T.ok(not FileHandler.ensureVersion(p), "not added twice")
    T.files["plain.tbm"] = "gamerule\n   sumo 1\n"
    local q = FileHandler.ParseMod("plain.tbm")
    FileHandler.ensureVersion(q)
    T.ok(FileHandler.modText(q):match("^version " .. FileHandler.MOD_VERSION .. "\n"), "no #! line: version first")
    T.files["v12.tbm"] = "#!/usr/bin/toribash\nversion 12\ngamerule\n   sumo 1\n"
    local r = FileHandler.ParseMod("v12.tbm")
    T.ok(not FileHandler.ensureVersion(r), "a mod's own version is kept")
    T.eq(count(FileHandler.modText(r), "version"), 1, "one version line")
end)
