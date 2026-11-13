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
---@field focusAfterReload boolean? look at the selection after our own save reloads (asset import)
---@field loadedGamerules table<string, string>? gamerules when the mod file was loaded, see syncGamerules
---@field onQuit function[] cleanup callbacks registered by modules, run on quit
---@field Main Main main window, set by ui/main.lua
---@field Editor table editor panels and duplicate/delete, set by ui/editor.lua
---@field Widgets Widgets shared button helpers, ui/widgets.lua
---@field WorldSelect WorldSelect click objects in the world to select them, utils/world_select.lua
---@field Camera Camera frames objects on screen, utils/camera.lua
---@field FileHandler table utils/file_handler.lua
---@field ModData ModData utils/mod_export.lua
---@field History History utils/history.lua
---@field Joints Joints utils/joints.lua
---@field Mat3 Mat3 utils/mat3.lua
---@field Transforms table move / rotate / scale for the selection, utils/transforms.lua
---@field ShapeGen table Generate tab geometry, utils/shape_gen.lua
---@field Gizmo Gizmo drag handles in the world, utils/gizmo.lua
---@field Parking Parking objects over the game's limit, kept in the file as comments, utils/parking.lua
---@field Players Players players' start positions and rotations (engageplayerpos), utils/players.lua
---@field GizmoMath GizmoMath utils/gizmo_math.lua
---@field Highlight table selection highlight and generate preview, utils/highlight.lua
---@field EditorRows EditorRows shared editor row widgets, ui/editor_rows.lua
---@field POS_ORIGIN number[] dojo center, set by utils/mod_export.lua
---@field ScrollList ScrollList ui/scroll_list.lua
---@field FLAGS table
---@field SHAPE table get_obj_shape values
---@field MAX_ENV_OBJECTS integer
---@field MAX_NONSTATIC_OBJECTS integer
---@field MAX_ENV_JOINTS integer env_obj_joint ids 1-24
---@field MIN_SIDE number smallest object side written, zero sides crash physics
---@field KEEP_POSITION_TAG string asset file line: Import keeps the objects' positions (converted maps)
---@field MapConv table map converter (mapconv/*.lua), nil in game until MGE.loadMapConv: Advanced tab's Map row, also tools/mapconv.lua
---@field loadMapConv fun(): table loads the map converter the first time it's needed, returns MGE.MapConv
---@field isPlacing fun(): boolean the map placement view is open (it hides the window, gizmo and camera keep working)
---@field saveOverlay UIElement? open name prompt (ui/save_overlay.lua)
---@field confirmOverlay UIElement? open confirmation popup (TBMenu:showConfirmationWindow)
---@field saveOverlayContext table? options for the next name prompt
---@field pickerOverlay UIElement? open file picker: asset import, Model row (ui/file_picker.lua)
---@field settingsOverlay UIElement? open settings: camera follow, world clicking (ui/settings_overlay.lua)
---@field mapOverlay UIElement? open Convert Map overlay (ui/map_overlay.lua)
---@field MapPlace table? map placement view (ui/map_place.lua), loaded by the overlay's Place button
---@field closeTopOverlay fun(): boolean Esc: closes the topmost of the overlays above
---@field overlayOpen fun(): boolean one of the overlays above, or a game overlay, is open
---@field apply fun() writes the working copy and reloads it (shows edits), not a save of the mod
---@field save fun() Save button / Ctrl + S: writes the mod to saveTarget()
---@field saveAs fun() Rename: asks the name to save the mod as
---@field setSource fun(path: string?, text: string?) the data belongs to that file now
---@field saveTarget fun(): string? where Save writes, under data/mod, always in saveFolder
---@field hasUnsavedChanges fun(): boolean
---@field saveFolder string Save only writes here (under data/mod), "modmaker/" like the game's modmaker
---@field sourcePath string? file the data belongs to (loaded or last written), path under data/mod
---@field savedText string? that file's text, compared for unsaved changes
---@field FilePicker table ui/file_picker.lua
---@field Assets table export / import, ui/assets.lua
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

---True while the map placement view (ui/map_place.lua) is open: it hides MGE's window, but its gizmo,
---the camera and its own drawing keep working
---@return boolean
function MGE.isPlacing()
    return MGE.MapPlace ~= nil and MGE.MapPlace.active == true
end

-- map converter, pure Lua shared with tools/mapconv.lua. Needs mat3 / file_handler / mod_export
local MAPCONV_MODULES = { "mapconv/vmf.lua", "mapconv/bsp.lua", "mapconv/brush.lua",
    "mapconv/boxfit.lua", "mapconv/merge.lua", "mapconv/convert.lua" }

---Loads the map converter the first time it's needed (Advanced tab > Map), not at startup: the rest of
---MGE starts faster and doesn't depend on it. Throws when a module fails to load, the next call tries again
---@return table MapConv
function MGE.loadMapConv()
    if MGE.MapConv and MGE.MapConv.loaded then return MGE.MapConv end
    MGE.MapConv = nil -- a failed earlier try left it half built
    for _, path in ipairs(MAPCONV_MODULES) do loadModule(path) end
    MGE.MapConv.loaded = true
    return MGE.MapConv
end

runCmd("reset") --Fixes sync if there are unsaved rotations
loadModule("utils/mat3.lua")
loadModule("utils/file_handler.lua")
loadModule("utils/mod_export.lua")
loadModule("utils/history.lua")
loadModule("utils/parking.lua") -- objects over the game's limit, after history
loadModule("utils/joints.lua")
loadModule("utils/highlight.lua")
loadModule("utils/world_select.lua")
loadModule("utils/camera.lua")
loadModule("utils/transforms.lua")
loadModule("utils/shape_gen.lua")
loadModule("utils/players.lua") -- players' start positions (engageplayerpos), after highlight and history
loadModule("utils/gizmo_math.lua")
loadModule("utils/gizmo.lua") -- after world_select, highlight and transforms

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

---@return table<string, string> current gamerule values by name, as the game would write them
local function readGamerules()
    local values = {}
    for name in pairs(get_game_rules()) do
        if name ~= "mod" then values[name] = tostring(get_gamerule(name)) end -- mod is the file itself
    end
    return values
end

---Remembers the gamerules a mod file loaded with, later differences were made in the game's menu
function MGE.snapshotGamerules()
    MGE.loadedGamerules = readGamerules()
end

---Puts gamerules changed in the game's menu (Rules button) into the mod data, so saves keep them.
---Only changed rules are written, rules the mod leaves at their default stay out of the file
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
    print("gamerules saved: " .. table.concat(names, ", "))
end

-- Saving. Edits are applied to a working copy that the game loads (MGE.apply: mge-modmaker.tbm and
-- mge-modmaker1.tbm, alternating so lm reloads it), many edits do that to show their result. The
-- mod itself is only written by Save and Rename, always into data/mod/modmaker/ (MGE.saveFolder) so
-- other mods are never replaced.
--   MGE.sourcePath: the file the data belongs to, the loaded mod or the last one written
--   MGE.savedText:  that file's text, the footer compares it with the data for "unsaved changes"
--   Save (MGE.save, Ctrl + S): writes MGE.saveTarget(): the source itself when it's in modmaker/,
--                   otherwise a copy there with its name. Asks the name only when there's no source,
--                   or that copy would replace an existing file
--   Rename (MGE.saveAs, Ctrl + Shift + S): asks the name, the written file becomes the source
-- A file counts as ours (overwritten without asking) only when it's the source.

---@type { path: string, text: string }? the source, kept over a script restart (MGE is rebuilt, this
---isn't): the working copy loaded then doesn't say which mod it is
MGE_SOURCE = MGE_SOURCE

---@param path string?
---@return boolean
local function isSaveOutput(path)
    local name = tostring(path):gsub("^.*[/\\]", "")
    return name == MGE.outputName or name == MGE.secondaryOutputName
end

---Writes the working copy and reloads it, so the game shows the edits. Not a save of the mod (MGE.save)
function MGE.apply()
    local outputName = MGE.modName == MGE.outputName and MGE.secondaryOutputName or MGE.outputName  --bypass for lm not loaading updates without mod swap
    MGE.syncGamerules()
    FileHandler.WriteMod(ModData.parsed, MGE.modFolder .. outputName)
    MGE.reloadPending = true -- keeps undo history and selection over the reload caused by our own save
    MGE.keptSelection = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.selected then MGE.keptSelection[obj.id] = true end
    end
    for i, obj in ipairs(ModData.parsed.parked) do -- parked ones by their place in the list, negative
        if obj.selected then MGE.keptSelection[-i] = true end
    end
    MGE.loadMod(outputName)
end

---Folder part of a path under data/mod ("" or "folder/") and the file name without .tbm
---@param path string?
---@return string folder, string name
local function splitModPath(path)
    local folder, file = tostring(path or ""):match("^(.-)([^/\\]*)$")
    return folder or "", ((file or ""):gsub("%.tbm$", ""))
end

-- Save only writes into data/mod/modmaker/, like the game's own modmaker: mods elsewhere (the game's,
-- downloaded ones) are never replaced, saving one makes a copy there
MGE.saveFolder = "modmaker/"

---Where Save writes: the source itself when it's in the save folder, otherwise a file with its name
---there, nil without a source
---@return string?
function MGE.saveTarget()
    local path = MGE.sourcePath
    if not path then return nil end
    if path:sub(1, #MGE.saveFolder) == MGE.saveFolder then return path end
    local _, name = splitModPath(path)
    return MGE.saveFolder .. name .. ".tbm"
end

---The data belongs to the file at path now (loaded, or just written): Save goes there (or to its copy
---in modmaker/), and the data counts as saved
---@param path string? under data/mod, nil: no file (Save asks the name)
---@param text string? the file's text, default the current data's
function MGE.setSource(path, text)
    MGE.sourcePath = path
    MGE.savedText = path and (text or FileHandler.modText(ModData.parsed)) or nil
    MGE_SOURCE = path and { path = path, text = MGE.savedText } or nil -- global: kept over a script restart
end

---True when the data differs from the source file (always, without one)
---@return boolean
function MGE.hasUnsavedChanges()
    return MGE.savedText == nil or MGE.savedText ~= FileHandler.modText(ModData.parsed)
end

---Writes the mod to path (in the save folder), which becomes the source, then applies (reload)
---@param path string
local function writeMod(path)
    MGE.syncGamerules() -- rules changed in the game's menu
    -- models written for the file's folder, the data keeps them for data/mod (ModData.parsedFor)
    if not FileHandler.WriteMod(ModData.parsedFor(path), MGE.modFolder .. path) then
        echo("^04[MGE] couldn't save " .. path)
        return
    end
    MGE.setSource(path)
    echo("^04[MGE] saved " .. path)
    -- the saved mod is what gets shared, say so if dynamic objects won't fully work in it
    local warning = MGE.Main and MGE.Main.dynamicWarning()
    if warning then echo("^04[MGE] saved with " .. warning) end
    MGE.apply()
end

---True when writing path would replace a file that isn't ours (the source): an earlier copy or
---another mod
---@param path string
---@return boolean
local function wouldReplace(path)
    return path ~= MGE.sourcePath and Files.Exists(MGE.modFolder .. path)
end

---Rename (Ctrl + Shift + S), and Save when it can't write directly: asks the name (prefilled with
---where Save writes), saves into the save folder. Replacing a file that isn't ours asks first. The
---old file stays
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
                MGE.confirmOverlay = TBMenu:showConfirmationWindow(name .. ".tbm already exists. Overwrite it?",
                    function()
                        MGE.confirmOverlay = nil
                        writeMod(path)
                    end, function() MGE.confirmOverlay = nil end)
            else
                writeMod(path)
            end
            return true -- the prompt closes
        end,
    }
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end

---Save button / Ctrl + S: writes the mod where MGE.saveTarget says. Asks the name instead when
---there's no source, or the copy would replace a file that isn't ours
function MGE.save()
    local target = MGE.saveTarget()
    if not target or wouldReplace(target) then
        MGE.saveAs()
    else
        writeMod(target)
    end
end

-- MGE's overlays (fields holding an open UIElement), topmost first: Esc closes them in this order
-- (the picker can be open over the map overlay, the confirmation over anything). A new overlay only
-- needs adding here for quit, Esc and overlayOpen to handle it
local OVERLAY_KEYS = { "confirmOverlay", "saveOverlay", "pickerOverlay", "settingsOverlay", "mapOverlay" }

---The topmost open overlay
---@return string? key its MGE field
---@return UIElement? overlay
local function topOverlay()
    for _, key in ipairs(OVERLAY_KEYS) do
        local overlay = MGE[key]
        if overlay and not overlay.destroyed then return key, overlay end
    end
    return nil, nil
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
    for _, key in ipairs(OVERLAY_KEYS) do
        local overlay = MGE[key]
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
    if switchedMod then
        set_camera_mode(0)
        -- a mod file was loaded (not our working copy): the data belongs to it now
        if not isSaveOutput(MGE.modPath) then MGE.setSource(MGE.modPath) end
    end
    -- a mod file was loaded: its rules are the new baseline. Applying gamerules in the game's menu
    -- also starts a new match, that one keeps the old baseline so the change is saved later
    if switchedMod or MGE.reloadPending then MGE.snapshotGamerules() end

    if MGE.reloadPending then
        -- our own save: same objects, restore selection and keep the list page
        for _, obj in ipairs(ModData.parsed.env_obj) do
            obj.selected = MGE.keptSelection and MGE.keptSelection[obj.id] or nil
        end
        for i, obj in ipairs(ModData.parsed.parked) do
            obj.selected = MGE.keptSelection and MGE.keptSelection[-i] or nil
        end
        MGE.Main.updateWindow()
        -- e.g. an asset import: the new objects are selected and only exist in the world now
        if MGE.focusAfterReload then MGE.Camera.followSelection() end
    else
        -- other reloads (new mod, game restart) re-read the file, older states no longer match
        History.reset()
        MGE.Main.resetWindow()
    end
    MGE.reloadPending = false
    MGE.keptSelection = nil
    MGE.focusAfterReload = nil -- only for the reload it was set for
end)

-- Shift + Q / W / E: Move / Rotate / Scale gizmo on / off, same as the toolbar toggles (ui/main.lua).
-- Not R: the game handles Shift + R before this hook can consume it
local TOOL_KEYS = {
    [string.byte("q")] = "move",
    [string.byte("w")] = "rotate",
    [string.byte("e")] = "scale",
}

local KEY_DELETE = 127 -- SDLK_DELETE (toriui's text fields use the same code)

-- Ctrl + N / D and Delete: the shown list's New, Duplicate and Delete buttons: objects, or the
-- Players / Joints list's own (ui/player_list.lua, ui/joint_list.lua)
---@param action "new"|"duplicate"|"delete"
local function listAction(action)
    local tab, actions = MGE.Main.listTab, nil
    if tab == "players" then
        local L = MGE.PlayerList
        actions = { new = L.newPlayer, duplicate = L.duplicate, delete = L.deleteSelected }
    elseif tab == "joints" then
        local L = MGE.JointList
        actions = { new = L.newJoint, duplicate = L.duplicate, delete = L.deleteSelected }
    else
        actions = { new = MGE.Assets.newObject, duplicate = MGE.Editor.duplicate, delete = MGE.Editor.deleteSelected }
    end
    actions[action]()
end
local OBJECT_KEYS = {
    [string.byte("n")] = function() listAction("new") end,
    [string.byte("d")] = function() listAction("duplicate") end,
}

---True while a prompt, popup or picker of MGE's is open, or one of the game's overlays
---(TBMenu:spawnWindowOverlay sets TB_MENU_POPUPS_DISABLED while it's up): object shortcuts wait
---until it's closed, so a key doesn't change the list behind it, and the gizmo isn't drawn over it
---@return boolean
local function overlayOpen()
    if topOverlay() then return true end
    return TB_MENU_POPUPS_DISABLED == true
end
MGE.overlayOpen = overlayOpen

local KEY_ESCAPE = 27
local escFrame = nil -- UIElement.frameIndex of the last Esc close

---Closes MGE's topmost overlay, for Esc: the delete confirmation (like its Cancel), else the name
---prompt, the file picker, the settings. Esc reaches both this module's key hook and the overlay's
---focused text field (Widgets.closeOnEscape), so one press closes only one overlay: a second call in
---the same frame does nothing
---@return boolean handled an overlay was open (and is closed now)
function MGE.closeTopOverlay()
    local frame = UIElement and UIElement.frameIndex
    if frame and frame == escFrame then return true end
    local key, overlay = topOverlay()
    if overlay then
        overlay:kill() -- their killActions clean up (keyboard, MGE.*Overlay, camera movement)
        -- the confirmation's Cancel callback clears it, killing it doesn't call that
        if key == "confirmOverlay" then MGE.confirmOverlay = nil end
        escFrame = frame
        return true
    end
    -- a pick in progress (the Core tab's color picker)
    if MGE.WorldSelect and MGE.WorldSelect.cancelPick() then
        echo("^04[MGE] pick cancelled")
        escFrame = frame
        return true
    end
    -- the map placement view isn't an overlay (the gizmo works under it), Esc goes back to its settings
    if MGE.isPlacing() then
        MGE.MapPlace.cancel()
        escFrame = frame
        return true
    end
    return false
end

-- Shift+Z undo, Shift+Y redo (Ctrl+Z/Y are taken by the game), Ctrl+S saves the mod (MGE.save),
-- Ctrl+A selects / deselects all objects, Shift + Q / W / E toggles a gizmo tool,
-- Ctrl + N / D new / duplicate, Delete deletes the selection (asks first), Esc closes MGE's overlays.
add_hook("key_down", MGE.hookname, function(key)
    -- before the text field check: the name prompt focuses its field
    if key == KEY_ESCAPE then
        if MGE.closeTopOverlay() then return 1 end -- consumed, the game doesn't open its menu too
        return
    end
    if TB_MENU_INPUT_ISACTIVE then return end -- typing in a text field
    if get_keyboard_alt() ~= 0 then return end
    local shift, ctrl = get_keyboard_shift() ~= 0, get_keyboard_ctrl() ~= 0
    -- the map placement view hides the window: only its gizmo tools work, the rest acts on objects
    if MGE.isPlacing() then
        if shift and not ctrl and TOOL_KEYS[key] then
            MGE.Gizmo.toggle(TOOL_KEYS[key])
            return 1
        end
        return
    end
    if not MGE.Main.window.displayed then return end
    if key == KEY_DELETE and not shift and not ctrl then
        if not overlayOpen() then listAction("delete") end -- confirmation popup
        return 1
    elseif ctrl and not shift and OBJECT_KEYS[key] then
        if not overlayOpen() then OBJECT_KEYS[key]() end
        return 1
    end
    if shift and not ctrl then
        if key == string.byte("z") then
            History.undo()
            return 1 -- consume so the game doesn't also handle the key
        elseif key == string.byte("y") then
            History.redo()
            return 1
        elseif TOOL_KEYS[key] then
            MGE.Gizmo.toggle(TOOL_KEYS[key])
            return 1
        end
    elseif ctrl and not shift and key == string.byte("s") then
        MGE.save() -- writes the mod into modmaker/, then reloads
        return 1
    elseif ctrl and shift and key == string.byte("s") then
        if not overlayOpen() then MGE.saveAs() end -- save under another name
        return 1
    elseif ctrl and not shift and key == string.byte("a") then
        -- same as the list's select all icon. On the Players / Joints list: those, not the objects
        local tab = MGE.Main.listTab
        if tab == "players" then
            MGE.Main.toggleSelectAllPlayers()
        elseif tab == "joints" then
            MGE.Main.toggleSelectAllJoints()
        else
            MGE.Main.toggleSelectAll()
        end
        return 1
    end
end)

add_hook("key_up", MGE.hookname, function(key)
    if key ~= 282 then return end --F1
    if MGE.isPlacing() then return end -- the placement view shows it again when it ends
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
MGE.snapshotGamerules()
History.reset()
-- source: the loaded mod. Started on a working copy (script restarted after editing): the source from
-- before the restart, compared with its text
if MGE.modPath and not isSaveOutput(MGE.modPath) then
    MGE.setSource(MGE.modPath)
elseif MGE_SOURCE then
    MGE.setSource(MGE_SOURCE.path, MGE_SOURCE.text)
end
loadModule("ui/main.lua")
MGE.running = true -- set last so a failed start isn't treated as running
