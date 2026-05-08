--- /ls tb-move-stuff/test2.lua
--- /lm mge-modmaker.tbm
---@class MGE
---@field scriptPath string
---@field outputName string
---@field modName string
---@field modPath string?
---@field modFolder string
---@field objects table
---@field hookname string
---@field window UIElement?
MGE = {
    scriptPath = "mge/",
    outputName = "mge-modmaker.tbm",
    modName = get_game_rules().mod,
    modPath = find_mod(get_game_rules().mod),
    modFolder = "../data/mod/",
    objects = {},
    hookname = "mge",
    window = nil,
}
FileHandler = dofile(MGE.scriptPath .. "file_handler.lua")

function MGE.updateSource()
    MGE.modName = get_game_rules().mod
    MGE.modPath = find_mod(MGE.modName)
    if MGE.modPath then
        MGE.objects = FileHandler.ParseMod(MGE.modFolder .. MGE.modPath)
        print("Parse complete")
    else
        MGE.objects = nil
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
dofile(MGE.scriptPath .. "ui.lua")
MGE.initUI()
