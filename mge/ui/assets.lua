require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

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

---Distance from object center to its lowest point in world space, accounts for rotation
---@param id integer 0-based object id
---@return number?
local function getObjHalfHeight(id)
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    local rawRot = get_obj_rot(id)
    if sx == nil or shape == nil or type(rawRot) ~= "table" then return nil end
    -- get_obj_rot is row-major, so the third row r8 r9 r10 holds the world z component of local x, y, z axes
    local rot = Utils3D.MatrixToMatrixTB(rawRot)
    local zx, zy, zz = math.abs(rot.r8), math.abs(rot.r9), math.abs(rot.r10)

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
                local x, y, z = get_obj_pos(obj.id - 1)
                local halfHeight = getObjHalfHeight(obj.id - 1)
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
                -- frame keeps the group's axes so the asset scales properly after import
                local assetObj = { kind = "env_obj", id = obj.id, props = ModData.copy(obj.props), frame = obj.frame }
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

---Adds an asset's objects (and joints between them) to the mod, selected, then saves and reloads
---@param parser FileParserResult asset contents, positions relative to the spawn point
---@param keepTab boolean? stay on the shown editor tab instead of switching to Core
local function importObjects(parser, keepTab)
    -- only joints with both objects in the asset are imported, so only those objects need low ids
    local linkedJoints = Joints.getLinked(Joints.idSet(parser.env_obj), parser.env_obj_joint)
    if not Joints.haveRoom(#linkedJoints) then return end
    local linkedIds = Joints.getObjectIds(linkedJoints)
    local plans = {}
    for i, assetObj in ipairs(parser.env_obj) do
        plans[i] = { pool = ModData.isStatic(assetObj) and "static" or "nonStatic", linked = linkedIds[assetObj.id] or false }
    end
    local ids = ModData.allocateIds(plans) -- all or nothing
    if not ids then return end

    -- selection moves to the imported objects so they can be moved right away
    for _, obj in ipairs(ModData.parsed.env_obj) do
        obj.selected = nil
    end

    local idMap = {} -- asset object id -> id in the mod
    for i, assetObj in ipairs(parser.env_obj) do
        local newId = ids[i]
        table.insert(ModData.parsed.env_obj, { kind = "env_obj", id = newId, props = ModData.copy(assetObj.props),
            frame = assetObj.frame, selected = true })
        idMap[assetObj.id] = newId
    end
    local importedJoints = Joints.copyLinked(parser.env_obj_joint, idMap)

    ModData.sortObjects()
    History.commit()
    -- imports land at the spawn point, which doesn't move: show the editor to move them right away and
    -- look at them once they're in the world (after the reload, if the camera button is on)
    if not keepTab then MGE.Main.setTab("core") end
    MGE.focusAfterReload = true
    MGE.save() -- the reload refreshes the window
    print("imported " .. #parser.env_obj .. " objects, " .. importedJoints .. " joints")
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
    importObjects(parser)
end

---Saves the mod's `player N` section (body/joint parts, the player's model) as a player asset.
---Player values are relative to the player's own spawn, so the section is copied as is
local function savePlayerToAsset()
    Main.getPlayerCount() -- resets a player id the mod doesn't have
    local playerId = Main.selectedPlayer
    -- no player section: parts written for all players (fatkido.tbm style) are what this player uses
    local parts = FileHandler.getPlayerLines(ModData.parsed, playerId) or FileHandler.getSharedPlayerLines(ModData.parsed)
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

---Replaces the mod's `player N` section with the selected player asset (added if the mod has none)
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

    Main.getPlayerCount() -- resets a player id the mod doesn't have
    local playerId = Main.selectedPlayer
    FileHandler.setPlayerLines(ModData.parsed, playerId, parts)
    History.commit()
    MGE.save() -- body changes need a reload
    print("player " .. playerId .. " replaced with " .. assetName)
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

---Adds objects like an import: new ids, selected, saved. Used by the Generate tab
---@param objects FileParserEnvObj[]
---@param keepTab boolean? see importObjects
function assetsView.addObjects(objects, keepTab)
    importObjects({ env_obj = objects, env_obj_joint = {}, ignores = {} }, keepTab)
end

---New button of the object list: adds DEFAULT_OBJECT, placed like an imported asset
function assetsView.newObject()
    assetsView.addObjects({ { kind = "env_obj", id = 1, props = assetsView.defaultProps() } })
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

---Import button of the object / player list: opens a list of the saved assets of that kind.
---Objects are added at the spawn point, a player model replaces the picked player's model
function assetsView.openImport()
    assetKind = listKind()
    local kind = assetKind
    MGE.FilePicker.open({
        title = kind == "obj" and "Import Objects" or ("Import Model to Player " .. Main.selectedPlayer),
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

MGE.Assets = assetsView
return assetsView
