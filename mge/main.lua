















































































MGE = MGE or { scriptPath = "mge/" }
MGE.hookname = "mge"
MGE.onQuit = {}




function MGE.say(text)
    text = tostring(text)
    echo("^04[MGE] " .. text)
    if MGE.onMessage then pcall(MGE.onMessage, text) end
end
MGE.outputName = "mge-modmaker.tbm"
MGE.secondaryOutputName = "mge-modmaker1.tbm"
MGE.modName = get_game_rules().mod
MGE.modPath = find_mod(get_game_rules().mod)
MGE.modFolder = "../data/mod/"

local function loadModule(path)
    return dofile(MGE.scriptPath .. path)
end




function MGE.isPlacing()
    return MGE.MapPlace ~= nil and MGE.MapPlace.active == true
end


local MAPCONV_MODULES = dofile(MGE.scriptPath .. "mapconv/modules.lua")




function MGE.loadMapConv()
    if MGE.MapConv and MGE.MapConv.loaded then return MGE.MapConv end
    MGE.MapConv = nil
    for _, path in ipairs(MAPCONV_MODULES) do loadModule(path) end
    MGE.MapConv.loaded = true
    return MGE.MapConv
end

runCmd("reset")

loadModule("utils/config.lua")
MGE.Config.load()
loadModule("utils/mat3.lua")
loadModule("utils/file_handler.lua")
loadModule("utils/mod_export.lua")
loadModule("utils/history.lua")
loadModule("utils/atmo_layer.lua")
loadModule("utils/atmo.lua")
loadModule("utils/joints.lua")
loadModule("utils/highlight.lua")
loadModule("utils/world_select.lua")
loadModule("utils/camera.lua")
loadModule("utils/transforms.lua")
loadModule("utils/shape_gen.lua")
loadModule("utils/players.lua")
loadModule("utils/gizmo_math.lua")
loadModule("utils/gizmo.lua")
MGE.Config.apply()

local FileHandler = MGE.FileHandler
local ModData = MGE.ModData
local History = MGE.History
local Atmo = MGE.Atmo











local function resolveModPath(name)
    name = tostring(name or "")
    if name == "" or not name:match("%.tbm$") then return nil end
    if Files.Exists(MGE.modFolder .. name) then return name end
    return find_mod(name)
end

function MGE.updateSource()
    MGE.modName = get_game_rules().mod
    MGE.modPath = resolveModPath(MGE.modName)
    ModData.reloadObjects()
end

function MGE.loadMod(outputName)
    runCmd("lm " .. outputName)
end


local function readGamerules()
    local values = {}
    for name in pairs(get_game_rules()) do
        if name ~= "mod" then values[name] = tostring(get_gamerule(name)) end
    end
    return values
end


function MGE.snapshotGamerules()
    MGE.loadedGamerules = readGamerules()
end



function MGE.syncGamerules()
    local current = readGamerules()
    local changed, names = {}, {}
    for name, value in pairs(current) do
        if value ~= (MGE.loadedGamerules or {})[name] then
            changed[name] = value
            table.insert(names, name)
        end
    end
    if #names == 0 then return end
    FileHandler.setGamerules(ModData.parsed, changed, current)
    table.sort(names)
    MGE.say("gamerules saved: " .. table.concat(names, ", "))
end















MGE_SOURCE = MGE_SOURCE




MGE_ATMO = MGE_ATMO



local function isSaveOutput(path)
    local name = tostring(path):gsub("^.*[/\\]", "")
    return name == MGE.outputName or name == MGE.secondaryOutputName
end


function MGE.apply()
    local outputName = MGE.modName == MGE.outputName and MGE.secondaryOutputName or MGE.outputName
    MGE.syncGamerules()
    FileHandler.WriteMod(ModData.parsed, MGE.modFolder .. outputName)
    MGE.reloadPending = true
    MGE.keptSelection = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.selected then MGE.keptSelection[obj.id] = true end
    end
    for i, obj in ipairs(ModData.parsed.atmo) do
        if obj.selected then MGE.keptSelection[-i] = true end
    end
    MGE.loadMod(outputName)
end




local function splitModPath(path)
    local folder, file = tostring(path or ""):match("^(.-)([^/\\]*)$")
    return folder or "", ((file or ""):gsub("%.tbm$", ""))
end



MGE.saveFolder = "modmaker/"




function MGE.saveTarget()
    local path = MGE.sourcePath
    if not path then return nil end
    if path:sub(1, #MGE.saveFolder) == MGE.saveFolder then return path end
    local _, name = splitModPath(path)
    return MGE.saveFolder .. name .. ".tbm"
end





function MGE.setSource(path, text)
    MGE.sourcePath = path
    MGE.savedText = path and (text or FileHandler.modText(ModData.parsed)) or nil
    MGE_SOURCE = path and { path = path, text = MGE.savedText } or nil
end




function MGE.hasUnsavedChanges()
    return MGE.savedText == nil or MGE.savedText ~= FileHandler.modText(ModData.parsed) or Atmo.hasChanges()
end



local function writeMod(path)
    MGE.syncGamerules()

    if not FileHandler.WriteMod(ModData.parsedFor(path), MGE.modFolder .. path) then
        MGE.say("couldn't save " .. path)
        return
    end
    MGE.setSource(path)
    MGE.say("saved " .. path)
    Atmo.saveFor(path)

    local warning = MGE.Main and MGE.Main.dynamicWarning()
    if warning then MGE.say("saved with " .. warning) end
    MGE.apply()
end





local function wouldReplace(path)
    return path ~= MGE.sourcePath and Files.Exists(MGE.modFolder .. path)
end


local confirmActions = nil








function MGE.confirm(message, onConfirm, onCancel)
    if MGE.confirmOverlay and not MGE.confirmOverlay.destroyed then return false end
    local actions
    local function finish(action)
        return function()
            if confirmActions == actions then confirmActions = nil end
            MGE.confirmOverlay = nil
            if action then action() end
        end
    end

    actions = { confirm = finish(onConfirm), cancel = finish(onCancel), frame = UIElement and UIElement.frameIndex }
    confirmActions = actions
    MGE.confirmOverlay = TBMenu:showConfirmationWindow(message, actions.confirm, actions.cancel)
    return true
end




function MGE.saveAs()
    local folder = MGE.saveFolder
    local _, defaultName = splitModPath(MGE.saveTarget())
    MGE.saveOverlayContext = {
        title = "Save mod (" .. folder .. ")",
        placeholder = "Mod name",
        defaultName = defaultName,
        onSave = function(name)
            local path = folder .. name .. ".tbm"
            if wouldReplace(path) then
                MGE.confirm(name .. ".tbm already exists. Overwrite it?", function() writeMod(path) end)
            else
                writeMod(path)
            end
            return true
        end,
    }
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end



function MGE.save()
    local target = MGE.saveTarget()
    if not target or wouldReplace(target) then
        MGE.saveAs()
    else
        writeMod(target)
    end
end




local OVERLAY_KEYS = { "confirmOverlay", "colorOverlay", "saveOverlay", "pickerOverlay", "settingsOverlay", "mapOverlay" }




local function topOverlay()
    for _, key in ipairs(OVERLAY_KEYS) do
        local overlay = MGE[key]
        if overlay and not overlay.destroyed then return key, overlay end
    end
    return nil, nil
end



function MGE.quit(fromWindow)
    if MGE.quitting then return end
    MGE.quitting = true

    remove_hooks(MGE.hookname)
    for _, callback in ipairs(MGE.onQuit or {}) do
        pcall(callback)
    end
    for _, key in ipairs(OVERLAY_KEYS) do
        local overlay = MGE[key]
        if overlay and not overlay.destroyed then
            pcall(function() overlay:kill() end)
        end
    end
    local window = MGE.Main and MGE.Main.window

    if window and MGE.Widgets then pcall(MGE.Widgets.releaseKeyboard, window) end
    if not fromWindow and window and not window.destroyed then
        window.killAction = nil
        pcall(function() window:kill() end)
    end
    if MGE.cameraChanged then set_camera_mode(0) end

    MGE = nil
    MGE.say("closed")
end

add_hook("match_begin", MGE.hookname, function()
    local path = MGE.modPath
    MGE.updateSource()

    local switchedMod = path ~= MGE.modPath and not (isSaveOutput(path) and isSaveOutput(MGE.modPath))
    if switchedMod then
        set_camera_mode(0)

        if not isSaveOutput(MGE.modPath) then
            MGE.setSource(MGE.modPath)
            Atmo.load(MGE.modPath)
            Atmo.applyShader()
        end
    end


    if switchedMod or MGE.reloadPending then MGE.snapshotGamerules() end

    if MGE.reloadPending then

        for _, obj in ipairs(ModData.parsed.env_obj) do
            obj.selected = MGE.keptSelection and MGE.keptSelection[obj.id] or nil
        end
        for i, obj in ipairs(ModData.parsed.atmo) do
            obj.selected = MGE.keptSelection and MGE.keptSelection[-i] or nil
        end
        MGE.Main.updateWindow()

        if MGE.focusAfterReload then MGE.Camera.followSelection() end
    else

        History.reset()
        MGE.Main.resetWindow()
    end
    MGE.reloadPending = false
    MGE.keptSelection = nil
    MGE.focusAfterReload = nil
    MGE.AtmoLayer.reapplySeeThrough()
end)



local TOOL_KEYS = {
    [string.byte("q")] = "move",
    [string.byte("w")] = "rotate",
    [string.byte("e")] = "scale",
}

local KEY_DELETE = 127




local function listAction(action)
    local tab, actions = MGE.Main.listTab, nil
    if tab == "misc" then return end
    if tab == "players" then
        local L = MGE.PlayerList
        actions = { new = L.newPlayer, duplicate = L.duplicate, delete = L.deleteSelected }
    elseif tab == "joints" then
        local L = MGE.JointList
        actions = { new = L.newJoint, duplicate = L.duplicate, delete = L.deleteSelected }
    elseif tab == "atmo" then
        actions = { new = MGE.Assets.newAtmo, duplicate = MGE.Editor.duplicate, delete = MGE.Editor.deleteSelected }
    else
        actions = { new = MGE.Assets.newObject, duplicate = MGE.Editor.duplicate, delete = MGE.Editor.deleteSelected }
    end
    actions[action]()
end
local OBJECT_KEYS = {
    [string.byte("n")] = function() listAction("new") end,
    [string.byte("d")] = function() listAction("duplicate") end,
}





local function overlayOpen()
    if topOverlay() then return true end
    return TB_MENU_POPUPS_DISABLED == true
end
MGE.overlayOpen = overlayOpen

local KEY_ESCAPE = 27
local KEY_RETURN, KEY_KEYPAD_ENTER = 13, 271
local escFrame = nil






function MGE.closeTopOverlay()
    local frame = UIElement and UIElement.frameIndex
    if frame and frame == escFrame then return true end
    local key, overlay = topOverlay()
    if overlay then
        overlay:kill()

        if key == "confirmOverlay" then
            local actions = confirmActions
            MGE.confirmOverlay = nil
            if actions then actions.cancel() end
        end
        escFrame = frame
        return true
    end

    if MGE.WorldSelect and MGE.WorldSelect.cancelPick() then
        MGE.say("pick cancelled")
        escFrame = frame
        return true
    end

    if MGE.isPlacing() then
        MGE.MapPlace.cancel()
        escFrame = frame
        return true
    end
    return false
end





add_hook("key_down", MGE.hookname, function(key)

    if key == KEY_ESCAPE then
        if MGE.closeTopOverlay() then return 1 end
        return
    end
    if (key == KEY_RETURN or key == KEY_KEYPAD_ENTER) and topOverlay() == "confirmOverlay" then
        local actions = confirmActions
        local frame = UIElement and UIElement.frameIndex
        if actions and not (frame and frame == actions.frame) then
            MGE.confirmOverlay:kill()
            actions.confirm()
        end
        return 1
    end
    if (key == KEY_RETURN or key == KEY_KEYPAD_ENTER) and topOverlay() == "colorOverlay" then
        if MGE.ColorPicker.confirm then MGE.ColorPicker.confirm() end
        return 1
    end
    if TB_MENU_INPUT_ISACTIVE then return end
    local shift, ctrl = get_keyboard_shift() ~= 0, get_keyboard_ctrl() ~= 0
    if get_keyboard_alt() ~= 0 then

        if not shift and not ctrl and TOOL_KEYS[key] and (MGE.isPlacing() or MGE.Main.window.displayed) then
            MGE.Gizmo.toggle(TOOL_KEYS[key])
            return 1
        end
        return
    end

    if MGE.isPlacing() then return end
    if not MGE.Main.window.displayed then return end
    if key == KEY_DELETE and not shift and not ctrl then
        if not overlayOpen() then listAction("delete") end
        return 1
    elseif ctrl and not shift and OBJECT_KEYS[key] then
        if not overlayOpen() then OBJECT_KEYS[key]() end
        return 1
    end
    if shift and not ctrl then
        if key == string.byte("z") then
            History.undo()
            return 1
        elseif key == string.byte("y") then
            History.redo()
            return 1
        end
    elseif ctrl and not shift and key == string.byte("s") then
        MGE.save()
        return 1
    elseif ctrl and shift and key == string.byte("s") then
        if not overlayOpen() then MGE.saveAs() end
        return 1
    elseif ctrl and not shift and key == string.byte("a") then

        local tab = MGE.Main.listTab
        if tab == "players" then
            MGE.Main.toggleSelectAllPlayers()
        elseif tab == "joints" then
            MGE.Main.toggleSelectAllJoints()
        elseif tab == "atmo" then
            MGE.Main.toggleSelectAllAtmo()
        elseif tab ~= "misc" then
            MGE.Main.toggleSelectAll()
        end
        return 1
    end
end)




MGE_HUD_BEFORE = MGE_HUD_BEFORE or get_option("hud")


function MGE.hideGameHud(hidden)
    set_option("hud", hidden and 0 or (MGE_HUD_BEFORE or 1))
end
table.insert(MGE.onQuit, function()
    MGE.hideGameHud(false)
    MGE_HUD_BEFORE = nil
end)


add_hook("unload", MGE.hookname, function() MGE.hideGameHud(false) end)



local HUD_START_HOOK = MGE.hookname .. "_hudStart"
function MGE.hideGameHudNextFrame()
    add_hook("draw2d", HUD_START_HOOK, function()
        remove_hooks(HUD_START_HOOK)
        if MGE and MGE.Main and MGE.Main.window and MGE.Main.window.displayed then MGE.hideGameHud(true) end
    end)
end
table.insert(MGE.onQuit, function() remove_hooks(HUD_START_HOOK) end)
MGE.hideGameHudNextFrame()




local HUD_MENU_HOOK = MGE.hookname .. "_hudMenu"
local menuWasOpen = TB_MENU_MAIN_ISOPEN == 1
add_hook("draw2d", HUD_MENU_HOOK, function()
    local open = TB_MENU_MAIN_ISOPEN == 1
    if menuWasOpen and not open and MGE.Main and MGE.Main.window and MGE.Main.window.displayed then
        MGE.hideGameHud(true)
    end
    menuWasOpen = open
end)
table.insert(MGE.onQuit, function() remove_hooks(HUD_MENU_HOOK) end)

add_hook("key_up", MGE.hookname, function(key)
    if key ~= 282 then return end
    if MGE.isPlacing() then return end
    local Main = MGE.Main
    if Main.window.displayed then
        Main.window:hide(false)
        MGE.hideGameHud(false)
    else
        Main.window:show(false)
        MGE.hideGameHud(true)
        Main.updateWindow()
    end
end)


MGE.updateSource()
MGE.snapshotGamerules()


if MGE.modPath and not isSaveOutput(MGE.modPath) then
    MGE.setSource(MGE.modPath)
    Atmo.load(MGE.modPath)
else
    if MGE_SOURCE then MGE.setSource(MGE_SOURCE.path, MGE_SOURCE.text) end

    if MGE_ATMO then
        local ok, objects = pcall(MGE_ATMO.objects)
        local okState, state = pcall(MGE_ATMO.state)
        if ok and type(objects) == "table" then ModData.parsed.atmo = objects end
        if okState and type(state) == "table" then Atmo.state = state end
    end
end

History.reset()
MGE_ATMO = {
    objects = function() return ModData.parsed.atmo end,
    state = function() return Atmo.state end,
}
MGE.AtmoLayer.unloadGameAtmo()

Atmo.rememberShader()
Atmo.applyShader()
table.insert(MGE.onQuit, function()
    Atmo.applyShader(true)
    MGE_SHADER_BEFORE = nil
end)
loadModule("ui/main.lua")
MGE.running = true
