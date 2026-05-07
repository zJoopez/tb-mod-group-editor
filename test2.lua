--- /ls tb-move-stuff/test.lua
--- /lm mge-modmaker.tbm
MgePath = "tb-move-stuff/"
local Mods = dofile(MgePath .. "Mod.lua")
require("toriui.uielement")

---@class MGE
---@field scriptPath string
---@field modNameOutput string
---@field modName string?
---@field modPath string
---@field mod Mod?
---@field hookname string
---@field window UIElement?
---@field windowContainer UIElement?
MGE = {
    scriptPath = "tb-move-stuff/",
    modNameOutput = "mge-modmaker.tbm",
    modName = get_game_rules().mod,
    modPath = "../data/mod/",
    hookname = "mge",
    window = nil,
    windowContainer = nil,
    mod = nil,
}
local debug = true

MGE.window, MGE.windowContainer = TBMenu:spawnMoveableWindow({
    x = 10,
    y = 100,
    w = 300,
    h = 500
})
local content = MGE.windowContainer:addChild({
    pos = { 10, 10 },
    size = { MGE.windowContainer.size.w - 20, MGE.windowContainer.size.h - 20 },
}, true)

local btn = content:addChild({
    w = content.size.w,
    h = 25,
    interactive = true,
    bgColor = TB_MENU_DEFAULT_BG_COLOR,
    hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
    pressedColor = TB_MENU_DEFAULT_DARKER_COLOR,

}):addAdaptedText("save")
function MGE.quit()
    remove_hooks(MGE.hookname)
end

MGE.window.killAction = MGE.quit

local function debugCheckMod()
    if (MGE.mod) then
        print("read complete:")
        print_r(MGE.mod)
    else
        print("mod not found")
    end
end

function MGE.updateSource()
    runCmd("clear")
    MGE.modName = get_game_rules().mod
    local path = find_mod(MGE.modName)
    if path then
        print("reading mod")
        MGE.mod = Mods.ParseFile(MGE.modPath .. path)
    else
        MGE.mod = nil
    end
    if debug then debugCheckMod() end
    print("update finished")
end

function MGE.save()
    if MGE.mod then
        local ok, err = Mods:save(MGE.modPath .. MGE.modNameOutput)
        if not ok then
            print("save failed: " .. tostring(err))
        end
    end
end

MGE.updateSource()

add_hook("match_begin", MGE.hookname, function()
    MGE.updateSource()
end)
