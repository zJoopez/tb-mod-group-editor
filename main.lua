-- Created by joopez
-- Project: Mod Group Editor v.1.0
-- Built for Toribash v.5.76

--- /ls mge/main.lua
--- /lm mge-modmaker.tbm

---@class MGE
---@field scriptPath string
---@field modName string
---@field modPath string?
---@field modFolder string
---@field outputName string
---@field secondaryOutputName string
---@field activeOutputName string
---@field hookname string
---@field window Main
---@field assetWindow UIElement?
MGE = {
    hookname = "mge",
    scriptPath = "mge/",
    outputName = "mge-modmaker.tbm",
    secondaryOutputName = "mge-modmaker1.tbm",
    modName = get_game_rules().mod,
    modPath = find_mod(get_game_rules().mod),
    modFolder = "../data/mod/",
}
dofile(MGE.scriptPath .. "utils/file_handler.lua")
dofile(MGE.scriptPath .. "utils/mod_export.lua")

function MGE.updateSource()
    MGE.modName = get_game_rules().mod
    MGE.modPath = find_mod(MGE.modName)
    if (MGE.modPath == "modmaker/modmaker.tbm") then MGE.modPath = "modmaker.tbm" end --fixes modmaker setting a wrong source
    ModData.reloadObjects()
end

function MGE.loadMod(outputName)
    runCmd("lm " .. outputName)
end

function MGE.save()
    --Written twice to keep potential custom name always uptodate
    FileHandler.WriteMod(ModData.parsed, MGE.modFolder .. MGE.outputName)
    FileHandler.WriteMod(ModData.parsed, MGE.modFolder .. MGE.secondaryOutputName)
    print("saved")
    --Need to swap between mods for lm to load updates
    local outputName = MGE.modName == MGE.outputName and MGE.secondaryOutputName or MGE.outputName
    MGE.loadMod(outputName)
end

function MGE.quit()
    remove_hooks(MGE.hookname)
end

add_hook("match_begin", MGE.hookname, function()
    local path = MGE.modPath
    MGE.updateSource()
    if path ~= MGE.modPath then set_camera_mode(0) end
    MGE.window.resetWindow()
end)

add_hook("key_up", MGE.hookname, function(key)
    if key ~= 282 then return end --F1
    if Main.window.displayed then
        Main.window:hide(false)
    else
        Main.window:show(false)
        MGE.window.updateWindow()
    end
end)

---start
MGE.updateSource()

MGE.window = dofile(MGE.scriptPath .. "ui/main.lua")

-- debug junk
-- dofile("chatlog/chatlog.lua")
-- runCmd("lm torii.tbm")
