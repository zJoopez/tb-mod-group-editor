-- Popup that browses a folder for files of one type: title, a bar with the current folder and a back
-- button, rows for subfolders and files, Cancel / confirm buttons. Folders keep things organized, so
-- there's no search or paging.
-- Used by the asset import (ui/assets.lua) and the Model row (ui/editor.lua, data/mod_assets).
-- Click a folder to open it, click a file to select it, double click or the confirm button picks it

---@class FilePickerOptions
---@field title string
---@field root string folder to browse, e.g. "data/mod_assets" (get_files / get_folders paths)
---@field rootLabel string? shown for the root in the folder bar, defaults to root
---@field extension string file type listed, without the dot, e.g. "obj"
---@field keepExtension boolean? picked paths keep the extension (asset files) or not (model names)
---@field selected string? path relative to root (as passed to onConfirm), opens in its folder selected
---@field confirmLabel string?
---@field emptyText string? shown in a folder without subfolders or matching files
---@field onConfirm fun(path: string) path relative to root, "/" separated; the popup is closed first

local FilePicker = {}
MGE.FilePicker = FilePicker

local ScrollList = MGE.ScrollList

local OVERLAY_W = 420
local OVERLAY_H = 460
local PADDING = 10
local TITLE_H = 44
local BUTTON_H = 40
local DOUBLE_CLICK_TIME = 0.35
local FOLDER_ICON = "../textures/menu/general/folder.tga" -- the game's own, shown in front of folder rows

---@param path string? "" for the root
---@return string[]
local function split(path)
    local parts = {}
    for part in tostring(path or ""):gmatch("[^/\\]+") do table.insert(parts, part) end
    return parts
end

---Subfolders and matching files of a folder, sorted, hidden (dot) names left out
---@param dir string
---@param extension string
---@return string[] folders, string[] files file names with extension
local function listFolder(dir, extension)
    local folders, files = {}, {}
    for _, name in ipairs(get_folders(dir) or {}) do
        if not name:find("^%.") then table.insert(folders, name) end
    end
    local suffix = "%." .. extension:lower() .. "$"
    for _, fileName in ipairs(get_files(dir, "") or {}) do
        local name = tostring(fileName):gsub("^.*[/\\]", "")
        if not name:find("^%.") and name:lower():find(suffix) then table.insert(files, name) end
    end
    table.sort(folders, function(a, b) return a:lower() < b:lower() end)
    table.sort(files, function(a, b) return a:lower() < b:lower() end)
    return folders, files
end

---Opens the picker, does nothing while another MGE popup is open
---@param options FilePickerOptions
function FilePicker.open(options)
    if MGE.pickerOverlay or MGE.saveOverlay then return end
    local selectedPath = options.selected
    -- start in the selected file's folder when it still exists
    local startParts = split(selectedPath)
    table.remove(startParts)
    local folder = table.concat(startParts, "/")
    if folder ~= "" and not is_folder(options.root .. "/" .. folder) then folder = "" end

    local overlay = TBMenu:spawnWindowOverlay()
    MGE.pickerOverlay = overlay -- lets MGE.quit close it
    local defaultKillAction = overlay.killAction
    overlay.killAction = function()
        if defaultKillAction then defaultKillAction() end
        if MGE and MGE.Widgets then MGE.Widgets.releaseKeyboard(overlay) end
        if MGE then MGE.pickerOverlay = nil end
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
    local innerW = w - PADDING * 2
    local listY = TITLE_H + barH
    local listH = h - listY - BUTTON_H - PADDING * 2

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
    header:addChild({
        pos = { PADDING, 0 },
        size = { innerW, TITLE_H },
    }):addAdaptedText(true, options.title, nil, nil, FONTS.BIG, nil, 0.6)
    local folderBar = header:addChild({
        pos = { PADDING, TITLE_H },
        size = { innerW, barH },
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
    })
    local footer = toReload:addChild({
        pos = { 0, listY + listH },
        size = { w, h - listY - listH },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
    })
    local rowsHolder = box:addChild({
        pos = { PADDING, listY },
        size = { innerW, listH },
    })

    local function confirm()
        if selectedPath == nil then
            TBMenu:showStatusMessage("Select a file from the list")
            return
        end
        close()
        options.onConfirm(selectedPath)
    end

    local rebuild
    ---@type { path: string, time: number }?
    local lastClick = nil -- a double click on a file confirms

    local function openFolder(path)
        folder = path
        lastClick = nil
        rebuild()
    end

    rebuild = function()
        -- folder bar: back button (not at the root) and the folder shown
        folderBar:kill(true)
        local backW = folder ~= "" and barH * 2 or 0
        if folder ~= "" then
            MGE.Widgets.button(folderBar, { x = 2, y = 2, w = backW - 4, h = barH - 4 }, "< back", function()
                local parts = split(folder)
                table.remove(parts)
                openFolder(table.concat(parts, "/"))
            end, nil, MGE.Widgets.PANEL_STYLE) -- lighter than the dark folder bar
        end
        folderBar:addChild({
            pos = { backW + 5, 0 },
            size = { innerW - backW - 10, barH },
        }):addAdaptedText((options.rootLabel or options.root) .. (folder ~= "" and "/" .. folder or ""),
            nil, nil, nil, LEFTMID, 0.6, nil, nil)

        local dir = folder == "" and options.root or options.root .. "/" .. folder
        local prefix = folder == "" and "" or folder .. "/"
        local folders, files = listFolder(dir, options.extension)
        local items = {}
        for _, name in ipairs(folders) do table.insert(items, { label = name, folder = prefix .. name }) end
        for _, name in ipairs(files) do
            local shown = options.keepExtension and name or name:gsub("%.[^%.]*$", "")
            table.insert(items, { label = shown, path = prefix .. shown })
        end

        -- kill(true) keeps the holder, kill() would leave destroyed elements in the parent's child list
        rowsHolder:kill(true)
        ---@type { row: UIElement, index: integer }?
        local selectedRow = nil
        ScrollList.create(rowsHolder, { x = 0, y = 0, w = innerW, h = listH }, items, function(row, item, index)
            if item.folder then
                -- folder icon in front of the name, file rows keep their text at the same spot
                local iconSize = row.size.h - 8
                row:addChild({
                    pos = { 5, (row.size.h - iconSize) / 2 },
                    size = { iconSize, iconSize },
                    bgImage = FOLDER_ICON,
                })
                row:addChild({
                    pos = { iconSize + 11, 0 },
                    size = { row.size.w - iconSize - 16, row.size.h },
                }):addAdaptedText(item.label, nil, nil, nil, LEFTMID, 0.6, nil, nil)
                row:addMouseUpHandler(function() openFolder(item.folder) end)
                return
            end
            row:addAdaptedText(item.label, 5, nil, nil, LEFTMID, 0.6, nil, nil)
            local function select()
                if selectedRow then
                    selectedRow.row.bgColor = ScrollList.getRowColor(selectedRow.index)
                end
                selectedRow = { row = row, index = index }
                selectedPath = item.path
                row.bgColor = ScrollList.selectedColor
            end
            if item.path == selectedPath then select() end
            row:addMouseUpHandler(function()
                local now = UIElement.clock or os.clock()
                local double = lastClick ~= nil and lastClick.path == item.path and now - lastClick.time <= DOUBLE_CLICK_TIME
                lastClick = { path = item.path, time = now }
                select()
                if double then confirm() end
            end)
        end, toReload, options.emptyText or ("No folders or ." .. options.extension .. " files here"))
    end

    local buttonW = (innerW - PADDING) / 2
    for i, info in ipairs({
        { label = TB_MENU_LOCALIZED.BUTTONCANCEL, onClick = close },
        { label = options.confirmLabel or "OK", onClick = confirm },
    }) do
        local btn = footer:addChild({
            pos = { PADDING + (i - 1) * (buttonW + PADDING), PADDING },
            size = { buttonW, BUTTON_H },
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

    rebuild()
end

return FilePicker
