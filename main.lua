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
---@field objects ModEnvObjects
---@field hookname string
---@field window UIElement?
---@field assetWindow UIElement?
MGE = {
    scriptPath = "mge/",
    outputName = "mge-modmaker.tbm",
    modName = get_game_rules().mod,
    modPath = find_mod(get_game_rules().mod),
    modFolder = "../data/mod/",
    objects = {},
    hookname = "mge",
}
FileHandler = dofile(MGE.scriptPath .. "file_handler.lua")

function MGE.updateSource()
    MGE.modName = get_game_rules().mod
    MGE.modPath = find_mod(MGE.modName)
    if MGE.modPath then
        MGE.objects = dofile(MGE.scriptPath .. "env_obj_extractor.lua")
        print("Object list updated")
    else
        MGE.objects = nil
        print("Failed to update object list")
    end
end

function MGE.loadMod()
    runCmd("lm " .. MGE.outputName)
end

function MGE.save()
    FileHandler.WriteMod(MGE.objects, MGE.modFolder .. MGE.outputName)
    print("saved")
end

function MGE.quit()
    remove_hooks(MGE.hookname)
end

add_hook("match_begin", MGE.hookname, function()
    MGE.updateSource()
end)

---start
MGE.updateSource()

-- Load UI
MGE.window = dofile(MGE.scriptPath .. "ui/main.lua")
