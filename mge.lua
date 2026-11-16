-- don't start a second instance, show the running one instead
if MGE and MGE.running then
    echo("^04[MGE] already running, F1 shows/hides the window")
    local Main = MGE.Main
    if Main and Main.window and not Main.window.displayed then
        Main.window:show(false)
        -- like F1 showing it, a frame later: this /ls fires "unload" after this runs, which puts the HUD back
        if MGE.hideGameHudNextFrame then MGE.hideGameHudNextFrame() end
        Main.updateWindow()
    end
    return
end
-- leftovers from a start that failed halfway (hooks, window)
if MGE and MGE.quit then pcall(MGE.quit) end

-- the folder this file is in, under data/script: "mge/", a renamed copy ("mgeDev/"), or "mge/mge/" when
-- the zip was extracted into a folder of its own. The code is in its mge/ subfolder.
local function isRoot(dir)
    local file = io.open(dir .. "mge/main.lua", "r")
    if file then file:close() end
    return file ~= nil
end

local function findRoot()
    -- the path /ls loaded this file from
    local info = debug and debug.getinfo and debug.getinfo(1, "S") -- level 1: this function, in this file
    local source = (info and info.source or ""):gsub("^@", ""):gsub("\\", "/")
    source = source:match("data/script/(.*)$") or source:gsub("^%./", "")
    local dir = source:match("^(.*)mge%.lua$")
    if dir and isRoot(dir) then return dir end

    -- no usable path: look for the folder, also one level down (extracted into its own folder)
    local found = {}
    for _, name in ipairs(get_folders and get_folders("data/script") or {}) do
        if isRoot(name .. "/") then found[#found + 1] = name .. "/" end
        for _, sub in ipairs(get_folders("data/script/" .. name) or {}) do
            if isRoot(name .. "/" .. sub .. "/") then found[#found + 1] = name .. "/" .. sub .. "/" end
        end
    end
    for _, root in ipairs(found) do
        if root == "mge/" then return root end
    end
    if found[1] then
        echo("^04[MGE] running from " .. found[1] .. (#found > 1 and " (more copies in data/script)" or ""))
        return found[1]
    end
    return "mge/"
end

MGE = { scriptPath = findRoot() .. "mge/" }
dofile(MGE.scriptPath .. "main.lua")

--- /ls mge/mge.lua (or the folder it's in: /ls mgeDev/mge.lua)
--- /lm mge-modmaker.tbm
--- /lm mge-modmaker1.tbm
