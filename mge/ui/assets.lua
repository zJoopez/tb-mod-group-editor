require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

local assetsView = {}

local Main = MGE.Main
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local ScrollList = MGE.ScrollList
local FileHandler = MGE.FileHandler
local SHAPE = MGE.SHAPE

local selectedAssetName = nil -- last picked asset, the default name for the next export

local ASSET_DIR = MGE.scriptPath .. "assets" -- scriptPath ends with "/"
-- object groups and player models are kept in their own folders, the list shows one kind at a time
local ASSET_FOLDERS = { obj = "obj", player = "player" }
---@type "obj"|"player"
local assetKind = "obj" -- set from the list tab when exporting / opening the import overlay

-- the game shifts mod file positions by this much when a mod loads (world = file - shift),
-- exported assets subtract it again so they hold the values a mod file would
local LOAD_SHIFT_X = -1
local LOAD_SHIFT_Y = 0.1

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

---@type table<string, string[]> cached folder listing per kind, search filters this instead of reading the folder per key
local assetFiles = {}

---@return string[] asset file names of the shown kind, sorted
local function getAssetFiles()
    if assetFiles[assetKind] then return assetFiles[assetKind] end
    local files = {}
    assetFiles[assetKind] = files
    for _, fileName in ipairs(get_files("data/script/" .. ASSET_DIR .. "/" .. ASSET_FOLDERS[assetKind], "")) do
        local name = tostring(fileName):gsub("^.*[/\\]", "")
        if name:match("%.tbm$") then table.insert(files, name) end
    end
    table.sort(files)
    return files
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

            -- positions read from the game are shifted from the file values, undo that so the
            -- asset file holds file coordinates
            local centerX = totalX / #positions + LOAD_SHIFT_X
            local centerY = totalY / #positions + LOAD_SHIFT_Y
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
                assetFiles[assetKind] = nil -- re-read the folder to show the new asset
                return true
            end
            print("failed to save asset")
            return false
        end
    }
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end

local function importAssetFromFile(assetName)
    local path = getAssetPath(assetName)
    if not path or not Files.Exists(path) then
        print("Asset not found")
        return
    end

    local parser = FileHandler.ParseMod(path)
    if #parser.env_obj == 0 then
        print("Asset file contains no objects")
        return
    end

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
    MGE.Main.setTab("core")
    MGE.focusAfterReload = true
    MGE.save() -- the reload refreshes the window
    print("imported " .. #parser.env_obj .. " objects, " .. importedJoints .. " joints")
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
                assetFiles[assetKind] = nil -- re-read the folder to show the new asset
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
    local path = getAssetPath(assetName)
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


-- object the New button adds, edit or replace this asset to change what New spawns
local NEW_OBJECT_ASSET = "default.tbm"

---New button of the object list: adds the default object asset, like importing it
function assetsView.newObject()
    assetKind = "obj"
    if not Files.Exists(getAssetPath(NEW_OBJECT_ASSET) or "") then
        print("New needs " .. ASSET_DIR .. "/" .. ASSET_FOLDERS.obj .. "/" .. NEW_OBJECT_ASSET)
        return
    end
    importAssetFromFile(NEW_OBJECT_ASSET)
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

-- import overlay layout
local OVERLAY_W = 420
local OVERLAY_H = 460
local OVERLAY_PADDING = 10
local OVERLAY_TITLE_H = 44
local OVERLAY_BUTTON_H = 40
local ASSET_PAGE_SIZE = 64
local DOUBLE_CLICK_TIME = 0.35

---Import button of the object / player list: opens a list of the saved assets of that kind.
---Objects are added at the spawn point, a player model replaces the picked player's model
function assetsView.openImport()
    if MGE.importOverlay or MGE.saveOverlay then return end
    assetKind = listKind()
    local kind = assetKind
    local selectedName = nil
    local searchText = ""
    local page = 1

    local overlay = TBMenu:spawnWindowOverlay()
    MGE.importOverlay = overlay -- lets MGE.quit close it
    local defaultKillAction = overlay.killAction
    overlay.killAction = function()
        if defaultKillAction then defaultKillAction() end
        -- the search field would otherwise stay in toriui's keyboard list (see Widgets.releaseKeyboard)
        if MGE and MGE.Widgets then MGE.Widgets.releaseKeyboard(overlay) end
        if MGE then MGE.importOverlay = nil end
        enable_camera_movement()
    end
    local function close() overlay:kill() end

    local w = math.min(OVERLAY_W, WIN_W - 20)
    local h = math.min(OVERLAY_H, WIN_H - 20)
    local box = overlay:addChild({
        pos = { (WIN_W - w) / 2, (WIN_H - h) / 2 },
        size = { w, h },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
        shapeType = ROUNDED,
        rounded = 5,
        interactive = true,
    })
    -- the overlay blocks list scrolling (UIScrollbarIgnore), allow it while the mouse is over the box,
    -- like the game's replay comments. Checked by position: hovering a row takes the box's hover state
    box:addCustomDisplay(function()
        UIScrollbarIgnore = not (MOUSE_X >= box.pos.x and MOUSE_X <= box.pos.x + box.size.w and
            MOUSE_Y >= box.pos.y and MOUSE_Y <= box.pos.y + box.size.h)
    end)

    local barH = ScrollList.rowHeight
    local innerW = w - OVERLAY_PADDING * 2
    local listY = OVERLAY_TITLE_H + barH
    local listH = h - listY - OVERLAY_BUTTON_H - OVERLAY_PADDING * 2

    -- redrawn on scroll: covers rows that scroll past the list edges, holds everything around the list
    local toReload = box:addChild({
        pos = { 0, 0 },
        size = { w, h },
    })
    local header = toReload:addChild({
        pos = { 0, 0 },
        size = { w, listY },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
    })
    local title = header:addChild({
        pos = { OVERLAY_PADDING, 0 },
        size = { innerW, OVERLAY_TITLE_H },
    })
    title:addAdaptedText(true, kind == "obj" and "Import Objects" or ("Import Model to Player " .. Main.selectedPlayer),
        nil, nil, FONTS.BIG, nil, 0.6)
    local topBar = header:addChild({
        pos = { OVERLAY_PADDING, OVERLAY_TITLE_H },
        size = { innerW, barH },
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
    })
    local footer = toReload:addChild({
        pos = { 0, listY + listH },
        size = { w, h - listY - listH },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
    })

    -- search on the left half, pager on the right half (same split as the object list)
    local halfW = innerW / 2
    local searchHolder = topBar:addChild({ pos = { 0, 0 }, size = { halfW, barH } })
    local pagerHolder = topBar:addChild({ pos = { halfW, 0 }, size = { innerW - halfW, barH } })
    local rowsHolder = box:addChild({
        pos = { OVERLAY_PADDING, listY },
        size = { innerW, listH },
    })

    local function importSelected()
        if not selectedName then
            TBMenu:showStatusMessage("Select an asset from the list")
            return
        end
        selectedAssetName = selectedName
        close()
        if kind == "obj" then importAssetFromFile(selectedName) else replacePlayerFromFile(selectedName) end
    end

    local buildList
    local function rebuild() buildList() end
    ---@type { name: string, time: number }?
    local lastClick = nil -- a double click imports

    buildList = function()
        local term = string.lower(searchText)
        local matches = {}
        for _, name in ipairs(getAssetFiles()) do
            if term == "" or string.find(string.lower(name), term, 1, true) then table.insert(matches, name) end
        end
        local pageItems, clamped, pageCount = ScrollList.paginate(matches, page, ASSET_PAGE_SIZE)
        page = clamped

        -- kill(true) keeps the holders, kill() would leave destroyed elements in the parent's child list
        pagerHolder:kill(true)
        rowsHolder:kill(true)
        ScrollList.createPager(pagerHolder, { x = 0, y = 0, w = pagerHolder.size.w, h = barH }, page, pageCount,
            function(newPage)
                page = newPage
                rebuild()
            end)

        ---@type { row: UIElement, index: integer }?
        local selectedRow = nil
        ScrollList.create(rowsHolder, { x = 0, y = 0, w = innerW, h = listH }, pageItems, function(row, name, index)
            row:addAdaptedText(name, 5, nil, nil, LEFTMID, 0.6, nil, nil)
            local function select()
                if selectedRow then
                    selectedRow.row.bgColor = ScrollList.getRowColor(selectedRow.index)
                end
                selectedRow = { row = row, index = index }
                selectedName = name
                row.bgColor = ScrollList.selectedColor
            end
            if name == selectedName then select() end
            row:addMouseUpHandler(function()
                local now = UIElement.clock or os.clock()
                local double = lastClick ~= nil and lastClick.name == name and now - lastClick.time <= DOUBLE_CLICK_TIME
                lastClick = { name = name, time = now }
                select()
                if double then importSelected() end
            end)
        end, toReload, term ~= "" and "No matching assets" or
            ("No assets saved yet, Export saves them in " .. ASSET_DIR .. "/" .. ASSET_FOLDERS[kind]))
    end

    local search = TBMenu:spawnTextField2(searchHolder, {
        x = 2, y = 2,
        w = searchHolder.size.w - 4, h = barH - 4
    }, nil, "Search assets", {
        fontId = 4,
        textScale = 0.65,
        textAlign = LEFTMID,
        keepFocusOnHide = true, -- toReload is hidden/shown on scroll
    })
    search:addInputCallback(function()
        searchText = tostring(search.textfieldstr[1] or "")
        page = 1
        rebuild()
    end)

    local buttonW = (innerW - OVERLAY_PADDING) / 2
    for i, info in ipairs({
        { label = TB_MENU_LOCALIZED.BUTTONCANCEL, onClick = close },
        { label = "Import", onClick = importSelected },
    }) do
        local btn = footer:addChild({
            pos = { OVERLAY_PADDING + (i - 1) * (buttonW + OVERLAY_PADDING), OVERLAY_PADDING },
            size = { buttonW, OVERLAY_BUTTON_H },
            interactive = true,
            bgColor = { 0, 0, 0, 0.1 },
            hoverColor = { 0, 0, 0, 0.3 },
            pressedColor = { 1, 1, 1, 0.2 },
            shapeType = ROUNDED,
            rounded = 4,
        }, true)
        btn:addAdaptedText(false, info.label)
        btn:addMouseHandlers(nil, info.onClick)
    end

    assetFiles[kind] = nil -- re-read the folder, files may have been added outside the game
    buildList()
end

MGE.Assets = assetsView
return assetsView
