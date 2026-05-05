--- /ls tb-move-stuff/test.lua
if (MGE == nil) then
    ---@class MGE
    ---@field tmpName string
    ---@field modName string?
    ---@field modPath string
    ---@field atmoData Atmosphere?
    ---@field hookname string
    ---@field window UIElement?
    ---@field windowContainer UIElement?
    MGE = {
        tmpName = "MGE-TMP.tbm",
        modName = get_game_rules().mod,
        modPath = "./data/mod/",
        hookname = "mge",
        window = nil,
        windowContainer = nil,
        atmoData = nil,
    }
end
MGE.window, MGE.windowContainer = TBMenu:spawnMoveableWindow({
    x = 10,
    y = 100,
    w = 300,
    h = 50
})

function MGE.quit()
    remove_hooks(MGE.hookname)
end

MGE.window.killAction = MGE.quit

local function debugCheckAtmo()
    print(MGE.atmoData)
    if (not MGE.atmoData) then return end
    for index, value in ipairs(MGE.atmoData.entities) do
        print_r(value.color)
    end
end

function MGE.updateSource()
    runCmd("clear")
    MGE.modName = get_game_rules().mod
    -- local path = find_mod(MGE.modName) --update path if needed
    MGE.atmoData = Atmospheres.ParseFile(MGE.modPath .. MGE.modName) -- Does't work for some mods (bad mod or old format?)
    debugCheckAtmo()
end

MGE.updateSource()

add_hook("match_begin", MGE.hookname, function()
    MGE.updateSource()
end)
