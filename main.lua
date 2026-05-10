-- Created by joopez
-- Project: Mod Group Editor v.0.9
-- Built for Toribash v.5.76

--- /ls mge/main.lua
--- /lm mge-modmaker.tbm
---@class MGE
---@field scriptPath string
---@field outputName string
---@field modName string
---@field modPath string?
---@field modFolder string
---@field modData ModExport
---@field hookname string
---@field window Main
---@field assetWindow UIElement?
MGE = {
    scriptPath = "mge/",
    outputName = "mge-modmaker.tbm",
    modName = get_game_rules().mod,
    modPath = find_mod(get_game_rules().mod),
    modFolder = "../data/mod/",
    hookname = "mge",
}
FileHandler = dofile(MGE.scriptPath .. "file_handler.lua")

function MGE.updateSource()
    MGE.modName = get_game_rules().mod
    MGE.modPath = find_mod(MGE.modName)
    if MGE.modPath then
        MGE.modData = dofile(MGE.scriptPath .. "mod_export.lua")
        print("Object list updated")
    else
        MGE.modData = { objects = {}, parsed = {} }
        print("Failed to update object list")
    end
end

function MGE.loadMod()
    runCmd("lm " .. MGE.outputName)
end

function MGE.save()
    FileHandler.WriteMod(MGE.modData.parsed, MGE.modFolder .. MGE.outputName)
    print("saved")
end

function MGE.quit()
    remove_hooks(MGE.hookname)
end

add_hook("match_begin", MGE.hookname, function()
    MGE.updateSource()
    if Main.window.displayed then
        MGE.window.updateWindow(false)
    end
end)

add_hook("key_up", MGE.hookname, function(key)
    if key ~= 282 then return end --F1
    if Main.window.displayed then
        Main.window:hide(false)
    else
        Main.window:show(false)
        MGE.window.updateWindow(false)
    end
end)

---start
MGE.updateSource()

-- Load UI
MGE.window = dofile(MGE.scriptPath .. "ui/main.lua")
