-- Created by joopez
-- Project: Mod Group Editor v.1.0
-- Built for Toribash v.5.76

-- Everything the script shares lives in the MGE table (modules register themselves on it),
-- so quitting only needs to clear MGE.

---@class MGE
---@field scriptPath string set by mge.lua
---@field modName string
---@field modPath string?
---@field modFolder string
---@field outputName string
---@field secondaryOutputName string
---@field activeOutputName string
---@field hookname string
---@field running boolean? true once startup finished, blocks starting a second instance
---@field quitting boolean? set while quitting, makes quit run once
---@field cameraChanged boolean? camera was switched to look-at mode, reset on quit
---@field reloadPending boolean? next match_begin comes from our own save
---@field keptSelection table<integer, boolean>? selected object ids restored after our own save
---@field onQuit function[] cleanup callbacks registered by modules, run on quit
---@field Main Main main window, set by ui/main.lua
---@field FileHandler table utils/file_handler.lua
---@field ModData ModData utils/mod_export.lua
---@field History History utils/history.lua
---@field Joints Joints utils/joints.lua
---@field Mat3 Mat3 utils/mat3.lua
---@field ScrollList ScrollList ui/scroll_list.lua
---@field FLAGS table
---@field SHAPE table get_obj_shape values
---@field MAX_ENV_OBJECTS integer
---@field MAX_NONSTATIC_OBJECTS integer
---@field MAX_ENV_JOINTS integer env_obj_joint ids 1-24
---@field MIN_SIDE number smallest object side written, zero sides crash physics
---@field saveOverlay UIElement? open name prompt (ui/save_overlay.lua)
---@field confirmOverlay UIElement? open confirmation popup (TBMenu:showConfirmationWindow)
---@field saveOverlayContext table? options for the next name prompt
MGE = MGE or { scriptPath = "mge/" }
MGE.hookname = "mge"
MGE.onQuit = {}
MGE.outputName = "mge-modmaker.tbm"
MGE.secondaryOutputName = "mge-modmaker1.tbm"
MGE.modName = get_game_rules().mod
MGE.modPath = find_mod(get_game_rules().mod)
MGE.modFolder = "../data/mod/"

local function loadModule(path)
    return dofile(MGE.scriptPath .. path)
end

runCmd("reset") --Fixes sync if there are unsaved rotations
loadModule("utils/mat3.lua")
loadModule("utils/file_handler.lua")
loadModule("utils/mod_export.lua")
loadModule("utils/history.lua")
loadModule("utils/joints.lua")
loadModule("utils/highlight.lua")

local FileHandler = MGE.FileHandler
local ModData = MGE.ModData
local History = MGE.History

function MGE.updateSource()
    MGE.modName = get_game_rules().mod
    MGE.modPath = find_mod(MGE.modName)
    if (MGE.modPath == "modmaker/modmaker.tbm") then MGE.modPath = "modmaker.tbm" end --fixes modmaker setting a wrong path
    ModData.reloadObjects()
end

function MGE.loadMod(outputName)
    runCmd("lm " .. outputName)
end

function MGE.save()
    local outputName = MGE.modName == MGE.outputName and MGE.secondaryOutputName or MGE.outputName  --bypass for lm not loaading updates without mod swap
    FileHandler.WriteMod(ModData.parsed, MGE.modFolder .. outputName)
    print("save complete")
    MGE.reloadPending = true -- keeps undo history and selection over the reload caused by our own save
    MGE.keptSelection = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.selected then MGE.keptSelection[obj.id] = true end
    end
    MGE.loadMod(outputName)
end

---@param path string?
---@return boolean
local function isSaveOutput(path)
    local name = tostring(path):gsub("^.*[/\\]", "")
    return name == MGE.outputName or name == MGE.secondaryOutputName
end

---Removes hooks, UI and the MGE global. Safe to call more than once and on a partially started script
---@param fromWindow boolean? true when called by the main window's killAction (window is already closing)
function MGE.quit(fromWindow)
    if MGE.quitting then return end
    MGE.quitting = true

    remove_hooks(MGE.hookname)
    for _, callback in ipairs(MGE.onQuit or {}) do
        pcall(callback)
    end
    for _, overlay in ipairs({ MGE.saveOverlay, MGE.confirmOverlay }) do
        if overlay and not overlay.destroyed then
            pcall(function() overlay:kill() end)
        end
    end
    local window = MGE.Main and MGE.Main.window
    -- our text fields and toggles would otherwise stay in toriui's keyboard list after quitting
    if window and MGE.Widgets then pcall(MGE.Widgets.releaseKeyboard, window) end
    if not fromWindow and window and not window.destroyed then
        window.killAction = nil
        pcall(function() window:kill() end)
    end
    if MGE.cameraChanged then set_camera_mode(0) end -- look-at camera set by editor/object list

    MGE = nil
    echo("^04[MGE] closed")
end

add_hook("match_begin", MGE.hookname, function()
    local path = MGE.modPath
    MGE.updateSource()
    -- saves alternate between the two output files, that isn't a mod switch
    local switchedMod = path ~= MGE.modPath and not (isSaveOutput(path) and isSaveOutput(MGE.modPath))
    if switchedMod then set_camera_mode(0) end

    if MGE.reloadPending then
        -- our own save: same objects, restore selection and keep the list page
        for _, obj in ipairs(ModData.parsed.env_obj) do
            obj.selected = MGE.keptSelection and MGE.keptSelection[obj.id] or nil
        end
        MGE.Main.updateWindow()
    else
        -- other reloads (new mod, game restart) re-read the file, older states no longer match
        History.reset()
        MGE.Main.resetWindow()
    end
    MGE.reloadPending = false
    MGE.keptSelection = nil
end)

-- Shift+Z undo, Shift+Y redo (Ctrl+Z/Y are taken by the game)
add_hook("key_down", MGE.hookname, function(key)
    if TB_MENU_INPUT_ISACTIVE then return end -- typing in a text field
    if get_keyboard_shift() == 0 or get_keyboard_ctrl() ~= 0 or get_keyboard_alt() ~= 0 then return end
    if not MGE.Main.window.displayed then return end
    if key == string.byte("z") then
        History.undo()
        return 1 -- consume so the game doesn't also handle the key
    elseif key == string.byte("y") then
        History.redo()
        return 1
    end
end)

add_hook("key_up", MGE.hookname, function(key)
    if key ~= 282 then return end --F1
    local Main = MGE.Main
    if Main.window.displayed then
        Main.window:hide(false)
    else
        Main.window:show(false)
        Main.updateWindow()
    end
end)

---start
MGE.updateSource()
History.reset()
loadModule("ui/main.lua")
MGE.running = true -- set last so a failed start isn't treated as running
