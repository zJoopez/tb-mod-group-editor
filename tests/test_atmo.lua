-- utils/atmo.lua: the atmo layer's .atmo file per mod (reader, writer, Save's decision), and how the layer
-- lives next to the mod data (reloads)
local T = ...
local Atmo = MGE.Atmo
local ModData = MGE.ModData
local FileHandler = MGE.FileHandler

---@param text string
---@return string[]
local function lines(text)
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line:gsub("\r$", "") end
    if out[#out] == "" then out[#out] = nil end -- like the game's readAll
    return out
end

local SAMPLE = table.concat({
    "shader sky.inc",
    "shaderopt FLOOR_COLOR 1 1 1 1",
    "opt reflection 0",
    "",
    "env_obj lamp",
    "   shape box",
    "   pos 1 2 3",
    "   rot 10 -20 30",
    "   sides 0.5 0.5 2",
    "   color 0.8 0.7 0.2 1",
    "   # a note",
    "   no_depth 1",
    "env_obj shade",
    "\tparent lamp",
    "\tshape cylinder",
    "\tsize 0.2 1 0",
    "\tcount 5",
    "\trandompos 1 1 0",
    "",
    "player 0",
    "   body head",
}, "\n")

T.test("atmo files read", function()
    local file = Atmo.parse(lines(SAMPLE))
    T.eq(#file.header, 3, "the file's own lines (shader, shaderopt, opt)")
    T.eq(#file.objects, 2, "objects")
    local lamp, shade = file.objects[1], file.objects[2]
    T.eq(lamp.atmoName, "lamp", "names kept")
    T.eq(lamp.id, 1, "ids are their place")
    T.eq(lamp.props.rot, "10 -20 30", "rot as written")
    T.eq(lamp.props.sides, "0.5 0.5 2", "sides")
    T.eq(lamp.props.no_depth, "1", "lines MGE doesn't edit are kept")
    T.eq(shade.props.sides, "0.2 1 0", "size read as sides")
    T.eq(shade.props.size, nil, "no size left")
    T.eq(shade.props.parent, "lamp", "parent")
    T.eq(shade.props.count, "5", "count")
    T.eq(file.trailer[1], "player 0", "a player section kept after the objects")
end)

T.test("atmo files written", function()
    local text = Atmo.text(Atmo.parse(lines(SAMPLE)))
    T.ok(text:find("^shader sky%.inc\nshaderopt FLOOR_COLOR 1 1 1 1\nopt reflection 0\n\nenv_obj lamp\n"), "header first, then the objects")
    T.ok(text:find("env_obj lamp\n   shape box\n   pos 1 2 3\n   rot 10 -20 30\n   size 0.5 0.5 2\n   color 0.8 0.7 0.2 1\n   # a note\n   no_depth 1\n", 1, true),
        "lines in their order, sides written as size, comments kept")
    T.ok(text:find("env_obj shade\n   parent lamp\n   shape cylinder\n   size 0.2 1 0\n   count 5\n   randompos 1 1 0\n", 1, true),
        "the second object")
    T.ok(text:find("\nplayer 0\n   body head$"), "the player section last")
    T.eq(Atmo.text(Atmo.parse(lines(text))), text, "a second round changes nothing")
end)

T.test("objects without a name get free mge_ names", function()
    local named = { kind = "env_obj", id = 1, props = { pos = "0 0 0" }, atmoName = "mge_1" }
    local new = { kind = "env_obj", id = 2, props = { pos = "1 0 0", shape = "box", sides = "1 1 1", color = "1 1 1 1", rot = "0 0 5" } }
    local text = Atmo.text({ objects = { named, new } })
    T.ok(text:find("env_obj mge_1\n", 1, true) and text:find("env_obj mge_2\n", 1, true), "mge_1 is taken, the new one is mge_2")
    T.ok(text:find("env_obj mge_2\n   shape box\n   pos 1 0 0\n   rot 0 0 5\n   size 1 1 1\n   color 1 1 1 1\n", 1, true),
        "a new object's lines in the usual order")
end)

T.test("objects from the mod: colors in the range atmos read", function()
    local obj = { props = { color = "3 0.5 -1 1.5" } }
    Atmo.fromMod(obj)
    T.eq(obj.props.color, "2 0.5 0 1", "clamped (above 2 the game would read 0-256)")
    obj = { props = { color = "0.25 0.5 1 1" } }
    Atmo.fromMod(obj)
    T.eq(obj.props.color, "0.25 0.5 1 1", "a usual color is left as written")
    obj = { props = {} }
    Atmo.fromMod(obj)
    T.eq(obj.props.color, nil, "no color, nothing added")
end)

T.test("the mod's atmo file name", function()
    T.eq(Atmo.fileName("modmaker/stairs.tbm"), "MGE - stairs.atmo", "folder and .tbm dropped")
    T.eq(Atmo.fileName("aikido.tbm"), "MGE - aikido.atmo", "no folder")
    T.eq(Atmo.fileName(nil), nil, "no mod, no name")
end)

T.test("Save writes the atmo only when it changed", function()
    local saved = { name = "MGE - a.atmo", text = "X" }
    T.eq(Atmo.saveAction("X", 3, "MGE - a.atmo", saved, true), "none", "unchanged")
    T.eq(Atmo.saveAction("Y", 3, "MGE - a.atmo", saved, true), "write", "changed")
    T.eq(Atmo.saveAction("X", 3, "MGE - b.atmo", saved, false), "write", "saved under a new name")
    T.eq(Atmo.saveAction("X", 3, "MGE - a.atmo", saved, false), "write", "the file was deleted meanwhile")
    T.eq(Atmo.saveAction("", 0, "MGE - a.atmo", saved, true), "empty", "emptied: asks, then empties the file")
    T.eq(Atmo.saveAction("", 0, "MGE - a.atmo", saved, false), "none", "empty and no file: nothing to do")
    T.eq(Atmo.saveAction("", 0, "MGE - a.atmo", { name = "MGE - a.atmo", text = "" }, true), "none",
        "already emptied: not asked again")
    T.eq(Atmo.saveAction("X", 3, "MGE - a.atmo", { header = {} }, false), "write", "nothing read yet")
end)

T.test("opening a mod reads its atmo, edits count as changes", function()
    ModData.parsed = { env_obj = {}, env_obj_joint = {}, atmo = {}, ignores = {} }
    T.files["../data/atmospheres/MGE - lamp.atmo"] = SAMPLE
    Atmo.load("modmaker/lamp.tbm")
    T.eq(#ModData.parsed.atmo, 2, "the layer is the file's objects")
    T.eq(Atmo.state.name, "MGE - lamp.atmo", "its file")
    T.ok(not Atmo.hasChanges(), "just read: no changes")
    ModData.parsed.atmo[1].props.pos = "5 5 5"
    T.ok(Atmo.hasChanges(), "an edit is a change")
    Atmo.load("modmaker/nothing.tbm")
    T.eq(#ModData.parsed.atmo, 0, "a mod without an atmo file: an empty layer")
    T.ok(not Atmo.hasChanges(), "empty and no file: no changes")
end)

T.test("reloads keep the layer: mod files have none", function()
    T.files["work.tbm"] = "env_obj 1\n   pos 0 0 0\n"
    MGE.modFolder, MGE.modPath = "", "work.tbm"
    get_obj_pos = function() return nil end
    local layer = { { kind = "env_obj", id = 1, props = { pos = "1 1 1" } } }
    ModData.parsed = { env_obj = {}, env_obj_joint = {}, atmo = layer, ignores = {} }
    ModData.reloadObjects()
    T.eq(ModData.parsed.atmo, layer, "the same layer after the reload")
    T.eq(#ModData.parsed.env_obj, 1, "the objects from the file")
    T.ok(not FileHandler.modText(ModData.parsed):find("pos 1 1 1", 1, true), "and the mod text without it")
end)

-- every atmo in data/atmospheres (the game's own and the players'): read and written again, nothing the
-- game reads is lost. Needs the folder next to MGE (data/script/mge -> data/atmospheres) and a shell for
-- the listing, otherwise skipped
T.test("every atmo in data/atmospheres reads and writes back", function()
    local dir = T.dir .. "../../../atmospheres/"
    local ok, pipe = pcall(io.popen, 'dir /b "' .. dir:gsub("/", "\\") .. '*.atmo" 2>nul')
    local names = {}
    if ok and pipe then
        for name in pipe:lines() do names[#names + 1] = name end
        pipe:close()
    end
    if #names == 0 then
        print("  (skipped: no .atmo files found in " .. dir .. ")")
        return
    end
    local files, objects = 0, 0
    for _, name in ipairs(names) do
        local f = io.open(dir .. name, "rb")
        local raw = f and f:read("*a")
        if f then f:close() end
        if raw then
            files = files + 1
            local original = lines(raw)
            local text = Atmo.text(Atmo.parse(original))
            T.eq(Atmo.text(Atmo.parse(lines(text))), text, name .. ": a second round changes nothing")
            -- each object's lines, as the game reads them (trimmed, size and sides the same word)
            local function blocks(list)
                local out, current = {}, nil
                for _, line in ipairs(list) do
                    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
                    if trimmed:match("^env_obj%s") then
                        current = { name = trimmed, lines = {} }
                        out[#out + 1] = current
                    elseif trimmed:match("^player%s") then
                        current = nil
                    elseif current and trimmed ~= "" then
                        local key, rest = trimmed:match("^(%S+)%s*(.*)$")
                        if key == "sides" then key = "size" end
                        current.lines[#current.lines + 1] = key .. " " .. rest:gsub("%s+", " ")
                    end
                end
                return out
            end
            local before, after = blocks(original), blocks(lines(text))
            T.eq(#after, #before, name .. ": objects")
            objects = objects + #before
            for i, b in ipairs(before) do
                local a = after[i]
                if a then
                    T.eq(a.name, b.name, name .. ": object " .. i .. " name")
                    local have = {}
                    for _, l in ipairs(a.lines) do have[l] = true end
                    -- a key written twice: the game takes the last value, so does the reader. Comments all stay
                    local last = {}
                    for idx, l in ipairs(b.lines) do
                        local key = l:match("^(%S+)")
                        if key:match("^[%a_]") then last[key] = idx end
                    end
                    for idx, l in ipairs(b.lines) do
                        local key = l:match("^(%S+)")
                        if not key:match("^[%a_]") or last[key] == idx then
                            T.ok(have[l], name .. ": " .. b.name .. " keeps \"" .. l .. "\"")
                        end
                    end
                end
            end
            -- the file's own lines (shader, opt...) before the first object
            for _, line in ipairs(original) do
                if line:match("^%s*env_obj%s") then break end
                if not line:match("^%s*$") then
                    T.ok(text:find(line, 1, true) ~= nil, name .. ": keeps \"" .. line .. "\"")
                end
            end
        end
    end
    print(string.format("  (%d atmos, %d objects)", files, objects))
end)
