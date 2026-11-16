local assetsView = {}

local Main = MGE.Main
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local ScrollList = MGE.ScrollList
local FileHandler = MGE.FileHandler
local SHAPE = MGE.SHAPE

local selectedAssetName = nil

local lastImported = {}

local ASSET_DIR = MGE.scriptPath .. "assets"

local ASSET_FOLDERS = { obj = "obj", player = "player" }

local assetKind = "obj"





local function sanitizeAssetName(name)
    local sanitized = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "_"):gsub("[^%w%-%_%.]+", "")
    if sanitized ~= "" and not sanitized:find("%.") then
        sanitized = sanitized .. ".tbm"
    end
    return sanitized
end



local function getAssetPath(name)
    local fileName = sanitizeAssetName(name)
    if fileName == "" then return nil end
    return ASSET_DIR .. "/" .. ASSET_FOLDERS[assetKind] .. "/" .. fileName
end




local function getImportPath(relative)
    if relative:find("%.%.") then return nil end
    return ASSET_DIR .. "/" .. ASSET_FOLDERS[assetKind] .. "/" .. relative
end





local function getObjHalfHeight(obj)
    local id = obj.id - 1
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    if sx == nil or shape == nil then return nil end

    local rot = MGE.Transforms.orientationOf(obj)
    local zx, zy, zz = math.abs(rot[3][1]), math.abs(rot[3][2]), math.abs(rot[3][3])

    if shape == SHAPE.SPHERE then
        return sx
    elseif shape == SHAPE.CAPSULE then
        return zz * sy / 2 + sx
    end
    return (zx * sx + zy * sy + zz * sz) / 2
end

local function saveSelectedToAsset()
    local selectedObjects = ModData.getSelected()
    if #selectedObjects == 0 then
        MGE.say("No objects selected")
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
                if get_obj_pos(obj.id - 1) ~= nil then
                    local pos = MGE.Transforms.positionOf(obj)
                    x, y, z = pos[1], pos[2], pos[3]
                end
                local halfHeight = getObjHalfHeight(obj)
                if x == nil or y == nil or z == nil or halfHeight == nil then
                    MGE.say("Unable to read selected object position or scale")
                    return false
                end
                positions[i] = { x = x, y = y, z = z }
                totalX = totalX + x
                totalY = totalY + y
                minZ = minZ and math.min(minZ, z - halfHeight) or z - halfHeight
            end



            local centerX = totalX / #positions - MGE.POS_ORIGIN[1]
            local centerY = totalY / #positions - MGE.POS_ORIGIN[2]
            for i, obj in ipairs(selectedObjects) do
                local assetObj = { kind = "env_obj", id = obj.id, props = ModData.copy(obj.props) }
                local pos = positions[i]
                assetObj.props.pos = FileHandler.formatNumbers(pos.x - centerX, pos.y - centerY, pos.z - minZ)
                table.insert(parser.env_obj, assetObj)
            end

            for _, joint in ipairs(Joints.getLinked(Joints.idSet(selectedObjects))) do
                local assetJoint = Joints.copy(joint, joint.id, joint.obj1, joint.obj2)
                Joints.transformPos(assetJoint, function(x, y, z)
                    return x - centerX, y - centerY, z - minZ
                end)
                table.insert(parser.env_obj_joint, assetJoint)
            end
            if FileHandler.WriteMod(parser, path) then
                MGE.say("asset saved: " .. path)
                return true
            end
            MGE.say("failed to save asset")
            return false
        end
    }
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end




local function readVector(line)
    local x, y, z = (line or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and y and z then return { x, y, z } end
    return nil
end





local function propsBounds(objects)
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    local any = false
    for _, obj in ipairs(objects) do
        local pos = readVector(obj.props.pos)
        if pos then
            any = true
            local s = readVector(obj.props.sides) or { 0.5, 0.5, 0.5 }
            local shape = (obj.props.shape or "box"):lower()
            local rot = MGE.Transforms.orientationOf(obj)
            for k = 1, 3 do
                local extent
                if shape == "sphere" then
                    extent = s[1]
                elseif shape == "cylinder" then
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








local function fillJointAnchors(parser)
    local byId = {}
    for _, obj in ipairs(parser.env_obj) do byId[obj.id] = obj end
    local filled = 0
    for _, joint in ipairs(parser.env_obj_joint) do
        local a, b = byId[joint.obj1], byId[joint.obj2]

        if not joint.props.pos and a and b and readVector(a.props.pos) and readVector(b.props.pos) then
            joint.props.pos = Joints.midpoint(a, b)
            filled = filled + 1
        end
    end
    return filled
end











local function importObjects(parser, keepTab, inView, jointIds, atmoExcess)

    local linkedJoints = Joints.getLinked(Joints.idSet(parser.env_obj), parser.env_obj_joint)
    if not Joints.haveRoom(#linkedJoints) then return false end
    local linkedIds = Joints.getObjectIds(linkedJoints)

    local excess = {}
    if atmoExcess and #linkedJoints == 0 then
        local free = #ModData.freeIds.static + #ModData.freeIds.nonStatic
        if type(atmoExcess) == "number" then free = math.max(0, math.min(free, atmoExcess)) end
        local over = #parser.env_obj - free
        if over > MGE.AtmoLayer.room() then
            MGE.say("Not enough room: " .. over .. " objects for the atmo, " .. MGE.AtmoLayer.room() .. " more fit there")
            return false
        end
        for _ = 1, over do table.insert(excess, 1, table.remove(parser.env_obj)) end
    end
    local plans = {}
    for i, assetObj in ipairs(parser.env_obj) do
        plans[i] = { pool = ModData.isStatic(assetObj) and "static" or "nonStatic", linked = linkedIds[assetObj.id] or false }
    end
    local ids = ModData.allocateIds(plans)
    if not ids then return false end
    local filled = fillJointAnchors(parser)
    if filled > 0 then MGE.say("" .. filled .. " joints had no anchor (pos), placed between their objects") end
    if inView then placeInView(parser) end


    for _, obj in ipairs(ModData.parsed.env_obj) do
        obj.selected = nil
    end
    for _, obj in ipairs(ModData.parsed.atmo) do
        obj.selected = nil
    end

    local idMap = {}
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


    if not keepTab then MGE.Main.setTab("core") end
    MGE.focusAfterReload = true
    MGE.apply()
    MGE.say("imported " .. #parser.env_obj .. " objects, " .. importedJoints .. " joints" ..
        (#atmoObjs > 0 and (", " .. #atmoObjs .. " atmo objects") or ""))
    return true
end


local function importAssetFromFile(assetName)
    local path = getImportPath(assetName)
    if not path or not Files.Exists(path) then
        MGE.say("Asset not found")
        return
    end

    local parser = FileHandler.ParseMod(path)
    if #parser.env_obj == 0 then
        MGE.say("Asset file contains no objects")
        return
    end
    importObjects(parser, false, true)
end





function assetsView.playerParts(playerId)
    return FileHandler.getPlayerLines(ModData.parsed, playerId) or FileHandler.getSharedPlayerLines(ModData.parsed)
end





local function savePlayerToAsset(playerId)
    Main.getPlayerCount()
    playerId = playerId or Main.selectedPlayer
    local parts = assetsView.playerParts(playerId)
    if not parts then
        MGE.say("Player " .. playerId .. " uses the default body, the mod has no body or joint changes for it")
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

            local lines = { "player 0" }
            for _, line in ipairs(parts) do table.insert(lines, line) end
            if FileHandler.WriteMod({ env_obj = {}, env_obj_joint = {}, ignores = lines }, path) then
                MGE.say("player model saved: " .. path)
                return true
            end
            MGE.say("failed to save player model")
            return false
        end
    }
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end




local function replacePlayerFromFile(assetName)
    local path = getImportPath(assetName)
    if not path or not Files.Exists(path) then
        MGE.say("Asset not found")
        return
    end


    local assetParser = FileHandler.ParseMod(path)
    local parts = FileHandler.getPlayerLines(assetParser) or FileHandler.getSharedPlayerLines(assetParser)
    if not parts then
        MGE.say("Asset file contains no body or joint changes")
        return
    end

    local players = Main.selectedPlayerList()
    if #players == 0 then
        MGE.say("Select the players to import the model to first")
        return
    end
    for _, playerId in ipairs(players) do
        FileHandler.setPlayerLines(ModData.parsed, playerId, parts)
    end
    History.commit()
    MGE.apply()
    MGE.say((#players == 1 and "player " or "players ") .. table.concat(players, ", ") .. " replaced with " .. assetName)
end




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


function assetsView.defaultProps()
    local props = {}
    for _, entry in ipairs(DEFAULT_OBJECT) do props[entry[1]] = entry[2] end
    return props
end









function assetsView.addObjects(objects, keepTab, inView, joints, atmoExcess)
    return importObjects({ env_obj = objects, env_obj_joint = joints or {}, ignores = {} }, keepTab, inView, nil, atmoExcess)
end





local ATMO_DIR = ASSET_DIR .. "/atmo"
local ATMO_ROOTS = {
    { root = "data/script/" .. ATMO_DIR, label = "assets/atmo" },
    { root = "data/atmospheres", label = "data/atmospheres" },
}

local lastAtmo = nil





local function addAtmo(objects, inView)
    if #objects == 0 then return false end
    local room = MGE.AtmoLayer.room()
    if #objects > room then
        MGE.say("" .. #objects .. " atmo objects, room for " .. room .. " (Settings > Max atmo objects)")
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
assetsView.addAtmo = addAtmo


function assetsView.newAtmo()
    local all = assetsView.defaultProps()
    local props = { shape = all.shape, pos = all.pos, rot = all.rot, sides = all.sides, color = all.color }
    addAtmo({ { kind = "atmo", id = 1, props = props } }, true)
end



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

            local filePath = root == ATMO_ROOTS[1].root and (ATMO_DIR .. "/" .. path) or ("../data/atmospheres/" .. path)
            local file = Files.Open(filePath, FILES_MODE_READONLY)
            if not file or not file.data then
                MGE.say("couldn't read " .. path)
                return
            end
            local lines = file:readAll()
            file:close()
            local atmo = MGE.Atmo.parse(lines)
            if #atmo.objects == 0 then
                MGE.say("no objects in " .. path)
                return
            end
            local state = MGE.Atmo.state
            local headerTaken = #atmo.header > 0 and #state.header == 0
            if addAtmo(atmo.objects, false) then
                if headerTaken then state.header = atmo.header end
                MGE.say("imported " .. #atmo.objects .. " atmo objects from " .. path ..
                    (headerTaken and " (with its shader / options lines)" or ""))
            end
        end,
    })
end


function assetsView.exportAtmo()
    local selected = ModData.getSelectedAtmo()
    if #selected == 0 then
        MGE.say("select the atmo objects to export first")
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
                MGE.say("couldn't write assets/atmo/" .. fileName)
                return false
            end
            local text = MGE.Atmo.text({ objects = selected })
            for line in (text .. "\n"):gmatch("(.-)\n") do file:writeLine(line) end
            file:close()
            lastAtmo = fileName
            MGE.say("saved assets/atmo/" .. fileName .. " (" .. #selected .. " atmo objects)")
            return true
        end,
    }
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end


function assetsView.newObject()
    assetsView.addObjects({ { kind = "env_obj", id = 1, props = assetsView.defaultProps() } }, false, true)
end





function assetsView.newPair(jointId)
    local objects = {}
    for i, dx in ipairs({ -0.25, 0.25 }) do
        local props = assetsView.defaultProps()
        local x, y, z = props.pos:match("(%S+)%s+(%S+)%s+(%S+)")
        props.pos = FileHandler.formatNumbers(tonumber(x) + dx, tonumber(y), tonumber(z))
        objects[i] = { kind = "env_obj", id = i, props = props }
    end
    local joint = { kind = "env_obj_joint", id = jointId, obj1 = 1, obj2 = 2, lines = {},
        props = { pos = assetsView.defaultProps().pos, visible = Joints.NEW_VISIBLE } }
    return importObjects({ env_obj = objects, env_obj_joint = { joint }, ignores = {} }, true, true, { jointId })
end


local function listKind()
    return Main.listTab == "players" and "player" or "obj"
end


function assetsView.export()
    assetKind = listKind()
    if assetKind == "obj" then saveSelectedToAsset() else savePlayerToAsset() end
end



function assetsView.exportPlayer(playerId)
    assetKind = "player"
    savePlayerToAsset(playerId)
end



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

assetsView.placeInView = placeInView

MGE.Assets = assetsView
return assetsView
