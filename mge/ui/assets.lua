require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

local assetsView = {}

local Main = MGE.Main
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local ScrollList = MGE.ScrollList
local FileHandler = MGE.FileHandler
local SHAPE = MGE.SHAPE

---@type UIElement
local content = nil
local selectedAssetName = nil
---@type { row: UIElement, index: integer }?
local selectedRow = nil
local searchText = ""
local assetPage = 1
local assetPageSize = 64
local refreshAssetList

local function getAssetDirectory()
    if MGE and type(MGE.scriptPath) == "string" and MGE.scriptPath ~= "" then
        return (MGE.scriptPath:gsub("/$", "")) .. "/assets"
    end
    return "mge/mge/assets"
end

local function getAssetPath(name)
    local assetName = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if assetName == "" then return nil end
    assetName = assetName:gsub("%s+", "_")
    assetName = assetName:gsub("[^%w%-%_%.]+", "")
    if not assetName:find("%.") then
        assetName = assetName .. ".tbm"
    end
    return getAssetDirectory() .. "/" .. assetName
end

local function copyProps(source)
    local props = {}
    for key, value in pairs(source or {}) do
        props[key] = value
    end
    return props
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

    if shape == SHAPE.SPHERE - 1 then
        return sx -- x is radius
    elseif shape == SHAPE.CAPSULE - 1 then
        return zz * sy / 2 + sx -- x radius, y length of the straight part along local z, caps add radius
    end
    return (zx * sx + zy * sy + zz * sz) / 2 -- box: projected half extents
end

local function getSelectedObjects()
    local selectedObjects = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.selected then
            table.insert(selectedObjects, obj)
        end
    end
    return selectedObjects
end

local function getAssetFiles()
    local assetFiles = {}
    local seen = {}
    local basePath = getAssetDirectory()

    for _, fileName in ipairs(get_files("data/script/".. MGE.scriptPath .."/assets", "")) do
        local name = tostring(fileName):gsub("^.*[/\\]", "")
        if name ~= "" and name:match("%.tbm$") and not seen[name] then
            seen[name] = true
            table.insert(assetFiles, name)
        end
    end

    table.sort(assetFiles)
    return assetFiles
end

local function saveSelectedToAsset()
    local selectedObjects = getSelectedObjects()
    if #selectedObjects == 0 then
        print("No objects selected")
        return
    end

    MGE.saveOverlayContext = {
        title = "Asset Name",
        placeholder = "Enter asset name",
        defaultName = selectedAssetName or "",
        sanitize = function(name)
            local sanitized = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            sanitized = sanitized:gsub("%s+", "_")
            sanitized = sanitized:gsub("[^%w%-%_%.]+", "")
            if sanitized == "" then return "" end
            if not sanitized:find("%.") then
                sanitized = sanitized .. ".tbm"
            end
            return sanitized
        end,
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

            local centerX = totalX / #positions - 1
            local centerY = totalY / #positions + 0.1
            for i, obj in ipairs(selectedObjects) do
                -- frame keeps the group's axes so the asset scales properly after import
                local assetObj = { kind = "env_obj", id = obj.id, props = copyProps(obj.props), frame = obj.frame }
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
                refreshAssetList()
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

    -- objects linked by the asset's own joints need non static ids
    local assetJointIds = Joints.getObjectIds(parser.env_obj_joint)
    local requiredIds = { static = 0, nonStatic = 0 }
    for _, assetObj in ipairs(parser.env_obj) do
        if assetObj.props.flag ~= "0" and not assetJointIds[assetObj.id] then
            requiredIds.static = requiredIds.static + 1
        else
            requiredIds.nonStatic = requiredIds.nonStatic + 1
        end
    end
    if requiredIds.static > #ModData.freeIds.static or requiredIds.nonStatic > #ModData.freeIds.nonStatic then
        print("Not enough objects available")
        return
    end

    -- selection moves to the imported objects so they can be moved right away
    for _, obj in ipairs(ModData.parsed.env_obj) do
        obj.selected = nil
    end

    local imported = 0
    local idMap = {} -- asset object id -> id in the mod
    for _, assetObj in ipairs(parser.env_obj) do
        local freeIds
        if assetObj.props.flag ~= "0" and not assetJointIds[assetObj.id] then
            freeIds = ModData.freeIds.static
        else
            freeIds = ModData.freeIds.nonStatic
        end

        local newId = freeIds[1]
        if not newId then
            print("Not enough objects available")
            return
        end

        local importedObj = { kind = "env_obj", id = newId, props = copyProps(assetObj.props), frame = assetObj.frame,
            selected = true }
        table.insert(ModData.parsed.env_obj, importedObj)
        table.remove(freeIds, 1)
        idMap[assetObj.id] = newId
        imported = imported + 1
    end
    local importedJoints = Joints.copyLinked(parser.env_obj_joint, idMap)

    table.sort(ModData.parsed.env_obj, function(a, b)
        return a.id < b.id
    end)
    History.commit()
    MGE.save()
    if Main and Main.updateWindow then
        Main.updateWindow()
        Main.resetEditor()
    end
    print("imported " .. imported .. " objects, " .. importedJoints .. " joints")
end

local function filterAssets()
    local assets = getAssetFiles()
    local searchTerm = string.lower(tostring(searchText or ""))
    if searchTerm == "" then return assets, searchTerm end

    local filteredAssets = {}
    for _, assetName in ipairs(assets) do
        if string.find(string.lower(assetName), searchTerm, 1, true) then
            table.insert(filteredAssets, assetName)
        end
    end
    return filteredAssets, searchTerm
end

---@class AssetListElements
---@field pagerHolder UIElement right half of the top bar, pager is rebuilt in here
---@field rowsHolder UIElement rows are rebuilt in here
---@field toReload UIElement bars redrawn over rows that scroll past the list edges
local list = nil

---Rebuilds pager and rows, the list frame and search field stay as they are
local function buildAssetList()
    local filteredAssets, searchTerm = filterAssets()
    local pageAssets, page, pageCount = ScrollList.paginate(filteredAssets, assetPage, assetPageSize)
    assetPage = page

    -- kill(true) keeps the holders, kill() would leave destroyed elements in the parent's child list
    list.pagerHolder:kill(true)
    list.rowsHolder:kill(true)

    ScrollList.createPager(list.pagerHolder, { x = 0, y = 0, w = list.pagerHolder.size.w, h = list.pagerHolder.size.h },
        assetPage, pageCount, function(newPage)
            assetPage = newPage
            refreshAssetList()
        end)

    selectedRow = nil
    ScrollList.create(list.rowsHolder, {
        x = 0,
        y = 0,
        w = list.rowsHolder.size.w,
        h = list.rowsHolder.size.h
    }, pageAssets, function(row, assetName, index)
        row:addAdaptedText(assetName, 5, nil, nil, LEFTMID, 0.6, nil, nil)

        local function select()
            if selectedRow then
                selectedRow.row.bgColor = ScrollList.getRowColor(selectedRow.index)
            end
            selectedRow = { row = row, index = index }
            selectedAssetName = assetName
            row.bgColor = ScrollList.selectedColor
        end
        if assetName == selectedAssetName then select() end

        -- selecting only highlights, importing is done with the import button
        row:addMouseUpHandler(select)
    end, list.toReload, searchTerm ~= "" and "No matching assets" or "No assets saved yet")
end

refreshAssetList = function()
    buildAssetList()
    -- new children are displayed on creation, re-apply tab visibility in case this tab is hidden
    if Main and Main.applyTab then Main.applyTab() end
end


---Creates the list frame once: pager bar on top, rows, search field in the bottom bar
---@param y number
---@param h number
---Creates the list frame once: search + pager on top, rows, export/import buttons on the bottom
local function createListFrame()
    local barHeight = ScrollList.rowHeight
    local bottomH = barHeight -- same height as the object list's bars
    local listView = content:addChild({
        pos = { 0, 0 },
        size = { content.size.w, content.size.h },
    }, true)

    local toReload = listView:addChild({
        pos = { 0, 0 },
        size = { listView.size.w, listView.size.h },
    }, true)
    local topBar = toReload:addChild({
        pos = { 0, 0 },
        size = { listView.size.w, barHeight },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
    }, true)
    -- bars live in toReload so they are redrawn over rows that scroll past the list edges
    local bottomBar = toReload:addChild({
        pos = { 0, -bottomH },
        size = { listView.size.w, bottomH },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
    }, true)
    MGE.Widgets.barButtons(bottomBar, {
        { label = "Export selected", onClick = saveSelectedToAsset },
        { label = "Import asset", onClick = function()
            if selectedAssetName then
                importAssetFromFile(selectedAssetName)
            else
                print("Select an asset from the list")
            end
        end },
    })

    -- top bar: search on the left half, pager on the right half (same split as the object list)
    local halfW = topBar.size.w / 2
    local searchHolder = topBar:addChild({
        pos = { 0, 0 },
        size = { halfW, barHeight },
    })
    local pagerHolder = topBar:addChild({
        pos = { halfW, 0 },
        size = { topBar.size.w - halfW, barHeight },
    })

    -- created once so typing doesn't rebuild the text field, only the pager and rows.
    -- keepFocusOnHide keeps focus when toReload is hidden/shown on scroll
    local search = TBMenu:spawnTextField2(searchHolder, {
        x = 2, y = 2,
        w = searchHolder.size.w - 4, h = searchHolder.size.h - 4
    }, nil, "Search assets", {
        fontId = 4,
        textScale = 0.65,
        textAlign = LEFTMID,
        keepFocusOnHide = true,
    })
    if searchText ~= "" then
        search:setText(searchText)
    end
    search:addInputCallback(function()
        searchText = tostring(search.textfieldstr[1] or "")
        assetPage = 1
        refreshAssetList()
    end)
    -- keepFocusOnHide keeps the keyboard captured after the window is killed, release it on quit
    table.insert(MGE.onQuit, function()
        if search.menuKeyboardId then search:disableMenuKeyboard() end
    end)

    local rowsHolder = listView:addChild({
        pos = { 0, barHeight },
        size = { listView.size.w, listView.size.h - barHeight - bottomH },
    })

    list = { pagerHolder = pagerHolder, rowsHolder = rowsHolder, toReload = toReload }
end

---Layout: list frame fills the area (search + pager, rows, export/import)
---@param container UIElement
function assetsView.create(container)
    content = container
    selectedRow = nil
    createListFrame()
    buildAssetList()
end

return assetsView
