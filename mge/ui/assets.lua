local assetsView = {}

local Main = MGE.Main
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local ScrollList = MGE.ScrollList
local FileHandler = MGE.FileHandler
local SHAPE = MGE.SHAPE

local selectedAssetName = nil -- last picked asset's file name, the default name for the next export
---@type table<string, string> last imported path per kind (relative to its folder), selected when Import opens
local lastImported = {}

local ASSET_DIR = MGE.scriptPath .. "assets" -- scriptPath ends with "/"
-- object groups and player models are kept in their own folders, the list shows one kind at a time
local ASSET_FOLDERS = { obj = "obj", player = "player" }
---@type "obj"|"player"
local assetKind = "obj" -- set from the list tab when exporting / opening the import overlay


---File name for an asset: spaces become _, other unsafe characters are dropped, .tbm is added
---@param name string?
---@return string "" when nothing usable is left
local function sanitizeAssetName(name)
    local sanitized = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "_"):gsub("[^%w%-%_%.]+", "")
    if sanitized ~= "" and not sanitized:find("%.") then
        sanitized = sanitized .. ".tbm"
    end
    return sanitized
end

---@param name string?
---@return string?
local function getAssetPath(name)
    local fileName = sanitizeAssetName(name)
    if fileName == "" then return nil end
    return ASSET_DIR .. "/" .. ASSET_FOLDERS[assetKind] .. "/" .. fileName
end

---Path of an asset picked in the import popup: relative to the kind's folder, may be in subfolders
---@param relative string e.g. "vehicles/scooter.tbm"
---@return string?
local function getImportPath(relative)
    if relative:find("%.%.") then return nil end -- stays inside the asset folder
    return ASSET_DIR .. "/" .. ASSET_FOLDERS[assetKind] .. "/" .. relative
end

---Distance from object center to its lowest point in world space, accounts for rotation. Rotation
---comes from the rot line like the editor's transforms, not the live world (see utils/transforms.lua)
---@param obj FileParserEnvObj
---@return number?
local function getObjHalfHeight(obj)
    local id = obj.id - 1
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    if sx == nil or shape == nil then return nil end
    -- third row: world z component of the local x, y, z axes
    local rot = MGE.Transforms.orientationOf(obj)
    local zx, zy, zz = math.abs(rot[3][1]), math.abs(rot[3][2]), math.abs(rot[3][3])

    if shape == SHAPE.SPHERE then
        return sx -- x is radius
    elseif shape == SHAPE.CAPSULE then
        return zz * sy / 2 + sx -- x radius, y length of the straight part along local z, caps add radius
    end
    return (zx * sx + zy * sy + zz * sz) / 2 -- box: projected half extents
end

local function saveSelectedToAsset()
    local selectedObjects = ModData.getSelected()
    if #selectedObjects == 0 then
        print("No objects selected")
        return
    end

    MGE.saveOverlayContext = {
        title = "Asset Name",
        placeholder = "Enter asset name",
        defaultName = selectedAssetName or "",
        sanitize = sanitizeAssetName,
        validate = function(name)
            if name == "" then
                return false, "Enter an asset name"
            end
            return true
        end,
        onSave = function(name)
            local path = getAssetPath(name)
            local parser = { env_obj = {}, env_obj_joint = {}, ignores = {} }
            local positions = {}
            local totalX, totalY, minZ = 0, 0, nil

            for i, obj in ipairs(selectedObjects) do
                local x, y, z
                if get_obj_pos(obj.id - 1) ~= nil then -- exists in the world, position as the file has it
                    local pos = MGE.Transforms.positionOf(obj)
                    x, y, z = pos[1], pos[2], pos[3]
                end
                local halfHeight = getObjHalfHeight(obj)
                if x == nil or y == nil or z == nil or halfHeight == nil then
                    print("Unable to read selected object position or scale")
                    return false
                end
                positions[i] = { x = x, y = y, z = z }
                totalX = totalX + x
                totalY = totalY + y
                minZ = minZ and math.min(minZ, z - halfHeight) or z - halfHeight
            end

            -- the group is stored centered on the dojo center (MGE.POS_ORIGIN) with its lowest point
            -- at z 0, so imports (which use the file positions as they are) land there
            local centerX = totalX / #positions - MGE.POS_ORIGIN[1]
            local centerY = totalY / #positions - MGE.POS_ORIGIN[2]
            for i, obj in ipairs(selectedObjects) do
                local assetObj = { kind = "env_obj", id = obj.id, props = ModData.copy(obj.props) }
                local pos = positions[i]
                assetObj.props.pos = FileHandler.formatNumbers(pos.x - centerX, pos.y - centerY, pos.z - minZ)
                table.insert(parser.env_obj, assetObj)
            end
            -- joints between selected objects get the same offset, ids stay as in the mod
            for _, joint in ipairs(Joints.getLinked(Joints.idSet(selectedObjects))) do
                local assetJoint = Joints.copy(joint, joint.id, joint.obj1, joint.obj2)
                Joints.transformPos(assetJoint, function(x, y, z)
                    return x - centerX, y - centerY, z - minZ
                end)
                table.insert(parser.env_obj_joint, assetJoint)
            end
            if FileHandler.WriteMod(parser, path) then
                print("asset saved: " .. path)
                return true
            end
            print("failed to save asset")
            return false
        end
    }
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end

---Numbers of a vector property line ("1 -0.1 0.25"), nil when it isn't three numbers
---@param line string?
---@return number[]?
local function readVector(line)
    local x, y, z = (line or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and y and z then return { x, y, z } end
    return nil
end

---Box around objects as their props have them (assets aren't in the world yet), rotation included
---like getObjHalfHeight. Objects without a pos line are left out
---@param objects FileParserEnvObj[]
---@return SpawnBounds?
local function propsBounds(objects)
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    local any = false
    for _, obj in ipairs(objects) do
        local pos = readVector(obj.props.pos)
        if pos then
            any = true
            local s = readVector(obj.props.sides) or { 0.5, 0.5, 0.5 }
            local shape = (obj.props.shape or "box"):lower()
            local rot = MGE.Transforms.orientationOf(obj) -- rot[k][j]: world axis k of the object's axis j
            for k = 1, 3 do
                local extent
                if shape == "sphere" then
                    extent = s[1] -- x is the radius
                elseif shape == "cylinder" then -- capsule: x radius, y length along the object's z
                    extent = math.abs(rot[k][3]) * s[2] / 2 + s[1]
                else
                    extent = (math.abs(rot[k][1]) * s[1] + math.abs(rot[k][2]) * s[2] + math.abs(rot[k][3]) * s[3]) / 2
                end
                min[k] = math.min(min[k], pos[k] - extent)
                max[k] = math.max(max[k], pos[k] + extent)
            end
        end
    end
    return any and { min = min, max = max } or nil
end

---Moves asset objects and their joints in front of the camera (Camera.spawnPoint), the same way the
---Generate tab places its shapes, keeping their layout. Changes the parser's props in place
---@param parser FileParserResult
local function placeInView(parser)
    local bounds = propsBounds(parser.env_obj)
    if not bounds then return end
    local shift = MGE.Camera.spawnShift(bounds, MGE.Camera.spawnPoint(bounds))
    for _, obj in ipairs(parser.env_obj) do
        local pos = readVector(obj.props.pos)
        if pos then
            obj.props.pos = FileHandler.formatNumbers(pos[1] + shift[1], pos[2] + shift[2], pos[3] + shift[3])
        end
    end
    for _, joint in ipairs(parser.env_obj_joint) do
        Joints.transformPos(joint, function(x, y, z) return x + shift[1], y + shift[2], z + shift[3] end)
    end
end

---Gives the asset's joints without a pos line one, halfway between the two objects each links (like a
---joint MGE makes), before the objects move. Mods always write it (every shipped mod with object joints
---does); without it the anchor isn't where the asset's objects are: MGE can't show or select it, and an
---asset placed away from the dojo center (in front of the camera on a converted map) folded up, its
---rigid joints holding the parts to a far point. Changes the parser's joints in place
---@param parser FileParserResult
---@return integer filled
local function fillJointAnchors(parser)
    local byId = {}
    for _, obj in ipairs(parser.env_obj) do byId[obj.id] = obj end
    local filled = 0
    for _, joint in ipairs(parser.env_obj_joint) do
        local a, b = byId[joint.obj1], byId[joint.obj2]
        -- only from the asset's own pos lines: these objects aren't in the world yet
        if not joint.props.pos and a and b and readVector(a.props.pos) and readVector(b.props.pos) then
            joint.props.pos = Joints.midpoint(a, b)
            filled = filled + 1
        end
    end
    return filled
end

---Adds an asset's objects (and joints between them) to the mod, selected, then saves and reloads
---@param parser FileParserResult asset contents, positions relative to the spawn point
---@param keepTab boolean? stay on the shown editor tab instead of switching to Core
---@param inView boolean? move them in front of the camera first (imports, New), otherwise they keep
---their positions (Generate places its own)
---@param jointIds integer[]? ids for the asset's joints in order (newPair: the Link tab's slot)
---@param atmoExcess (boolean|integer)? objects past the free ids go to the atmo (utils/atmo_layer.lua) instead of
---the import failing: the last ones, so objects should come most important first (the map converter's
---do). A number: only that many become objects (at most the free ids), the rest go to the atmo
---@return boolean added
local function importObjects(parser, keepTab, inView, jointIds, atmoExcess)
    -- only joints with both objects in the asset are imported, so only those objects need low ids
    local linkedJoints = Joints.getLinked(Joints.idSet(parser.env_obj), parser.env_obj_joint)
    if not Joints.haveRoom(#linkedJoints) then return false end
    local linkedIds = Joints.getObjectIds(linkedJoints)
    ---@type FileParserEnvObj[] the ones that go to the atmo, in order
    local excess = {}
    if atmoExcess and #linkedJoints == 0 then
        local free = #ModData.freeIds.static + #ModData.freeIds.nonStatic
        if type(atmoExcess) == "number" then free = math.max(0, math.min(free, atmoExcess)) end
        local over = #parser.env_obj - free
        if over > MGE.AtmoLayer.room() then
            print("Not enough room: " .. over .. " objects for the atmo, " .. MGE.AtmoLayer.room() .. " more fit there")
            return false
        end
        for _ = 1, over do table.insert(excess, 1, table.remove(parser.env_obj)) end
    end
    local plans = {}
    for i, assetObj in ipairs(parser.env_obj) do
        plans[i] = { pool = ModData.isStatic(assetObj) and "static" or "nonStatic", linked = linkedIds[assetObj.id] or false }
    end
    local ids = ModData.allocateIds(plans) -- all or nothing
    if not ids then return false end
    local filled = fillJointAnchors(parser) -- before placeInView: the anchors move with the objects
    if filled > 0 then echo("^04[MGE] " .. filled .. " joints had no anchor (pos), placed between their objects") end
    if inView then placeInView(parser) end

    -- selection moves to the imported objects so they can be moved right away
    for _, obj in ipairs(ModData.parsed.env_obj) do
        obj.selected = nil
    end
    for _, obj in ipairs(ModData.parsed.atmo) do
        obj.selected = nil
    end

    local idMap = {} -- asset object id -> id in the mod
    for i, assetObj in ipairs(parser.env_obj) do
        local newId = ids[i]
        table.insert(ModData.parsed.env_obj, { kind = "env_obj", id = newId, props = ModData.copy(assetObj.props),
            selected = true })
        idMap[assetObj.id] = newId
    end
    local importedJoints = Joints.copyLinked(parser.env_obj_joint, idMap, jointIds)
    local atmoObjs = {}
    for i, assetObj in ipairs(excess) do
        atmoObjs[i] = { kind = "env_obj", id = 0, props = ModData.copy(assetObj.props) }
    end
    MGE.AtmoLayer.add(atmoObjs)

    ModData.sortObjects()
    History.commit()
    -- show the editor to move them right away and look at them once they're in the world (after the
    -- reload, if camera follow is on)
    if not keepTab then MGE.Main.setTab("core") end
    MGE.focusAfterReload = true
    MGE.apply() -- the reload refreshes the window
    print("imported " .. #parser.env_obj .. " objects, " .. importedJoints .. " joints" ..
        (#atmoObjs > 0 and (", " .. #atmoObjs .. " atmo objects") or ""))
    return true
end

---@param assetName string
local function importAssetFromFile(assetName)
    local path = getImportPath(assetName)
    if not path or not Files.Exists(path) then
        print("Asset not found")
        return
    end

    local parser = FileHandler.ParseMod(path)
    if #parser.env_obj == 0 then
        print("Asset file contains no objects")
        return
    end
    -- converted maps say where they go (MGE.KEEP_POSITION_TAG), other assets go in front of the camera
    local keepPosition = false
    for _, line in ipairs(parser.ignores) do
        if line:match("^%s*(%S+)") == MGE.KEEP_POSITION_TAG then keepPosition = true end
    end
    importObjects(parser, false, not keepPosition)
end

---The model parts a player uses: its own `player N` section, or parts written for all players
---(fatkido.tbm style), nil for the default body
---@param playerId integer
---@return string[]?
function assetsView.playerParts(playerId)
    return FileHandler.getPlayerLines(ModData.parsed, playerId) or FileHandler.getSharedPlayerLines(ModData.parsed)
end

---Saves the mod's `player N` section (body/joint parts, the player's model) as a player asset.
---Player values are relative to the player's own spawn, so the section is copied as is. One player:
---the Players list's Export saves the first selected one
---@param playerId integer? default the last picked player
local function savePlayerToAsset(playerId)
    Main.getPlayerCount() -- resets a player id the mod doesn't have
    playerId = playerId or Main.selectedPlayer
    local parts = assetsView.playerParts(playerId)
    if not parts then
        print("Player " .. playerId .. " uses the default body, the mod has no body or joint changes for it")
        return
    end

    MGE.saveOverlayContext = {
        title = "Player Model Name",
        placeholder = "Enter model name",
        defaultName = selectedAssetName or "",
        sanitize = sanitizeAssetName,
        validate = function(name)
            if name == "" then
                return false, "Enter a model name"
            end
            return true
        end,
        onSave = function(name)
            local path = getAssetPath(name)
            if not path then return false end
            -- stored as player 0, replacing writes the parts under the chosen player
            local lines = { "player 0" }
            for _, line in ipairs(parts) do table.insert(lines, line) end
            if FileHandler.WriteMod({ env_obj = {}, env_obj_joint = {}, ignores = lines }, path) then
                print("player model saved: " .. path)
                return true
            end
            print("failed to save player model")
            return false
        end
    }
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end

---Replaces the selected players' `player N` sections with the player asset (added if the mod has
---none), every selected player gets the model, one undo step
---@param assetName string
local function replacePlayerFromFile(assetName)
    local path = getImportPath(assetName)
    if not path or not Files.Exists(path) then
        print("Asset not found")
        return
    end
    -- first player section in the file, or parts for all players, so mods like fatkido.tbm can be
    -- copied into the player folder as they are
    local assetParser = FileHandler.ParseMod(path)
    local parts = FileHandler.getPlayerLines(assetParser) or FileHandler.getSharedPlayerLines(assetParser)
    if not parts then
        print("Asset file contains no body or joint changes")
        return
    end

    local players = Main.selectedPlayerList()
    if #players == 0 then
        print("Select the players to import the model to first")
        return
    end
    for _, playerId in ipairs(players) do
        FileHandler.setPlayerLines(ModData.parsed, playerId, parts)
    end
    History.commit()
    MGE.apply() -- body changes need a reload
    print((#players == 1 and "player " or "players ") .. table.concat(players, ", ") .. " replaced with " .. assetName)
end


-- the object the New button adds (same as assets/obj/default.tbm), kept here so New works without
-- the asset file
local DEFAULT_OBJECT = {
    { "shape", "box" },
    { "pos", "1 -0.1 0.25" },
    { "rot", "0.00 0.00 0.00" },
    { "sides", "0.50 0.50 0.50" },
    { "color", "0.00000000 1.00000000 0.00000000 1.00000000" },
    { "flag", "0" },
    { "mass", "0.1000" },
    { "bounce", "0.100000" },
    { "friction", "10000.00" },
    { "force", "0.00 0.00 0.00" },
    { "visible", "1" },
    { "model_name", "env_obj1" },
    { "use_model", "0" },
    { "hardness", "0.000000" },
}

---@return table<string, string> a new copy of DEFAULT_OBJECT's properties
function assetsView.defaultProps()
    local props = {}
    for _, entry in ipairs(DEFAULT_OBJECT) do props[entry[1]] = entry[2] end
    return props
end

---Adds objects like an import: new ids, selected, saved. Used by the Generate tab and New
---@param objects FileParserEnvObj[]
---@param keepTab boolean? see importObjects
---@param inView boolean? see importObjects
---@param joints FileParserEnvObjJoint[]? joints between the objects (their obj1 / obj2 are the objects'
---ids here), they get new ids with them (Generate's joined pieces)
---@param atmoExcess (boolean|integer)? see importObjects (map conversions)
---@return boolean added
function assetsView.addObjects(objects, keepTab, inView, joints, atmoExcess)
    return importObjects({ env_obj = objects, env_obj_joint = joints or {}, ignores = {} }, keepTab, inView, nil, atmoExcess)
end

-- Atmo pieces (the Atmo list's Import / Export, utils/atmo.lua): .atmo files. Export writes the selected atmo
-- objects to assets/atmo, Import reads one from there or from data/atmospheres (the game's atmos and the
-- players' own). They're added to the atmo layer as they are: their lines, names (parent lines) and
-- positions, an atmo's own colors (0-2 or 0-256) untouched. No reload: atmo objects aren't in the .tbm
local ATMO_DIR = ASSET_DIR .. "/atmo"
local ATMO_ROOTS = {
    { root = "data/script/" .. ATMO_DIR, label = "assets/atmo" },
    { root = "data/atmospheres", label = "data/atmospheres" },
}
---@type string? last imported .atmo, relative to its root
local lastAtmo = nil

---Adds atmo objects to the atmo layer, selected (the others not), one undo step
---@param objects FileParserEnvObj[] atmo objects (their lines as they'll be written)
---@param inView boolean? moved in front of the camera first, keeping their layout
---@return boolean added
local function addAtmo(objects, inView)
    if #objects == 0 then return false end
    local room = MGE.AtmoLayer.room()
    if #objects > room then
        echo("^04[MGE] " .. #objects .. " atmo objects, room for " .. room .. " (Settings > Most atmo objects)")
        return false
    end
    if inView then placeInView({ env_obj = objects, env_obj_joint = {}, ignores = {} }) end
    local layer = ModData.parsed.atmo
    for _, obj in ipairs(layer) do obj.selected = nil end
    for _, obj in ipairs(objects) do
        obj.kind, obj.selected = "atmo", true
        layer[#layer + 1] = obj
        obj.id = #layer
    end
    History.commit()
    Main.updateWindow()
    MGE.Camera.followSelection()
    return true
end
assetsView.addAtmo = addAtmo -- Generate on the Atmo list (ui/editor_generate.lua)

---New on the Atmo list: a default box in front of the camera, in the atmo (its look lines only)
function assetsView.newAtmo()
    local all = assetsView.defaultProps()
    local props = { shape = all.shape, pos = all.pos, rot = all.rot, sides = all.sides, color = all.color }
    addAtmo({ { kind = "atmo", id = 1, props = props } }, true)
end

---Import on the Atmo list: picks an .atmo from assets/atmo or data/atmospheres, its objects join the atmo
---where the file has them. The file's own lines (shader, opt...) become the atmo's when it has none yet
function assetsView.openAtmoImport()
    MGE.FilePicker.open({
        title = "Import Atmo",
        roots = ATMO_ROOTS,
        extension = "atmo",
        keepExtension = true,
        selected = lastAtmo,
        confirmLabel = "Import",
        emptyText = "No .atmo files here. Export (Atmo list) saves to assets/atmo",
        onConfirm = function(path, root)
            if path:find("%.%.") then return end
            lastAtmo = path
            -- Files paths start at data/script, ../ at the Toribash folder
            local filePath = root == ATMO_ROOTS[1].root and (ATMO_DIR .. "/" .. path) or ("../data/atmospheres/" .. path)
            local file = Files.Open(filePath, FILES_MODE_READONLY)
            if not file or not file.data then
                echo("^04[MGE] couldn't read " .. path)
                return
            end
            local lines = file:readAll()
            file:close()
            local atmo = MGE.Atmo.parse(lines)
            if #atmo.objects == 0 then
                echo("^04[MGE] no objects in " .. path)
                return
            end
            local state = MGE.Atmo.state
            local headerTaken = #atmo.header > 0 and #state.header == 0
            if addAtmo(atmo.objects, false) then
                if headerTaken then state.header = atmo.header end
                echo("^04[MGE] imported " .. #atmo.objects .. " atmo objects from " .. path ..
                    (headerTaken and " (with its shader / options lines)" or ""))
            end
        end,
    })
end

---Export on the Atmo list: the selected atmo objects as an .atmo in assets/atmo, as they are
function assetsView.exportAtmo()
    local selected = ModData.getSelectedAtmo()
    if #selected == 0 then
        echo("^04[MGE] select the atmo objects to export first")
        return
    end
    MGE.saveOverlayContext = {
        title = "Atmo Piece Name",
        placeholder = "Enter a name",
        defaultName = "",
        sanitize = function(name) return (sanitizeAssetName(name):gsub("%.tbm$", ".atmo")) end,
        validate = function(name)
            if name == "" then return false, "Enter a name" end
            return true
        end,
        onSave = function(name)
            local fileName = sanitizeAssetName(name):gsub("%.tbm$", ""):gsub("%.atmo$", "") .. ".atmo"
            local path = ATMO_DIR .. "/" .. fileName
            local file = Files.Open(path, FILES_MODE_WRITE)
            if not file or not file.data then
                echo("^04[MGE] couldn't write assets/atmo/" .. fileName)
                return false
            end
            local text = MGE.Atmo.text({ objects = selected })
            for line in (text .. "\n"):gmatch("(.-)\n") do file:writeLine(line) end
            file:close()
            lastAtmo = fileName
            echo("^04[MGE] saved assets/atmo/" .. fileName .. " (" .. #selected .. " atmo objects)")
            return true
        end,
    }
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end

---New button of the object list: adds DEFAULT_OBJECT in front of the camera, like an import
function assetsView.newObject()
    assetsView.addObjects({ { kind = "env_obj", id = 1, props = assetsView.defaultProps() } }, false, true)
end

---Create with nothing picked (the Joints list's Link tab): two DEFAULT_OBJECTs side by side, touching, in front of the
---camera, and a joint between them with its anchor on the face they share. One undo step
---@param jointId integer the joint's id (the picked empty slot)
---@return boolean added
function assetsView.newPair(jointId)
    local objects = {}
    for i, dx in ipairs({ -0.25, 0.25 }) do -- DEFAULT_OBJECT is 0.5 wide: the two touch at its pos
        local props = assetsView.defaultProps()
        local x, y, z = props.pos:match("(%S+)%s+(%S+)%s+(%S+)")
        props.pos = FileHandler.formatNumbers(tonumber(x) + dx, tonumber(y), tonumber(z))
        objects[i] = { kind = "env_obj", id = i, props = props }
    end
    local joint = { kind = "env_obj_joint", id = jointId, obj1 = 1, obj2 = 2, lines = {},
        props = { pos = assetsView.defaultProps().pos, visible = Joints.NEW_VISIBLE } }
    return importObjects({ env_obj = objects, env_obj_joint = { joint }, ignores = {} }, true, true, { jointId })
end

---@return "obj"|"player" asset kind for what the list shows
local function listKind()
    return Main.listTab == "players" and "player" or "obj"
end

---Export button of the object / player list: saves the selected objects or the picked player's model
function assetsView.export()
    assetKind = listKind()
    if assetKind == "obj" then saveSelectedToAsset() else savePlayerToAsset() end
end

---Export on the Players list: saves that player's model as a player asset
---@param playerId integer
function assetsView.exportPlayer(playerId)
    assetKind = "player"
    savePlayerToAsset(playerId)
end

---Import button of the object / player list: opens a list of the saved assets of that kind.
---Objects are added in view, a player model replaces the selected players' models
function assetsView.openImport()
    assetKind = listKind()
    local kind = assetKind
    local players = kind == "player" and Main.selectedPlayerList() or {}
    if kind == "player" and #players == 0 then
        TBMenu:showStatusMessage("Select the players to import the model to first")
        return
    end
    MGE.FilePicker.open({
        title = kind == "obj" and "Import Objects"
            or ("Import Model to Player" .. (#players > 1 and "s " or " ") .. table.concat(players, ", ")),
        root = "data/script/" .. ASSET_DIR .. "/" .. ASSET_FOLDERS[kind],
        rootLabel = "assets/" .. ASSET_FOLDERS[kind],
        extension = "tbm",
        keepExtension = true,
        selected = lastImported[kind],
        confirmLabel = "Import",
        emptyText = "No folders or assets here, Export saves to assets/" .. ASSET_FOLDERS[kind],
        onConfirm = function(path)
            lastImported[kind] = path
            selectedAssetName = path:gsub("^.*/", "")
            assetKind = kind
            if kind == "obj" then importAssetFromFile(path) else replacePlayerFromFile(path) end
        end,
    })
end

assetsView.placeInView = placeInView -- for the offline tests

MGE.Assets = assetsView
return assetsView
