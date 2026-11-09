-- Picks a 3d model (.obj) from data/mod_assets for an object's model_name, browsing folders in the
-- shared list overlay (ui/list_overlay.lua). model_name paths: ModData.toModelName / fromModelName.
-- A texture with the model's name next to it (.tga) is used by the game, nothing to pick for it.

local ModelPicker = {}
MGE.ModelPicker = ModelPicker

local ROOT = "data/mod_assets"

---@param path string? "" for the root
---@return string[]
local function split(path)
    local parts = {}
    for part in tostring(path or ""):gmatch("[^/\\]+") do table.insert(parts, part) end
    return parts
end

---Opens the picker in the folder of `current`, or mod_assets itself
---@param current string? model path the selection uses now (selected in the list)
---@param onPick fun(model: string) model path in mod_assets without .obj
function ModelPicker.open(current, onPick)
    local currentParts = split(current)
    table.remove(currentParts) -- the folder the current model is in
    local folder = table.concat(currentParts, "/")
    if folder ~= "" and not is_folder(ROOT .. "/" .. folder) then folder = "" end

    MGE.ListOverlay.open({
        title = function() return "Model: mod_assets/" .. folder end,
        confirmLabel = "Use model",
        selected = current,
        getItems = function()
            local dir = folder == "" and ROOT or ROOT .. "/" .. folder
            local prefix = folder == "" and "" or folder .. "/"
            local items = {}
            if folder ~= "" then
                table.insert(items, { label = "< back", onClick = function()
                    local parts = split(folder)
                    table.remove(parts)
                    folder = table.concat(parts, "/")
                end })
            end
            local folders = get_folders(dir) or {}
            table.sort(folders)
            for _, name in ipairs(folders) do
                if not name:find("^%.") then
                    table.insert(items, { label = name .. "/", onClick = function() folder = prefix .. name end })
                end
            end
            local files = {}
            for _, fileName in ipairs(get_files(dir, "obj") or {}) do
                local name = tostring(fileName):gsub("^.*[/\\]", "")
                if name:lower():match("%.obj$") then table.insert(files, (name:gsub("%.[oO][bB][jJ]$", ""))) end
            end
            table.sort(files)
            for _, name in ipairs(files) do
                table.insert(items, { label = name, value = prefix .. name })
            end
            return items
        end,
        emptyText = "No folders or .obj models here",
        onConfirm = onPick,
    })
end

return ModelPicker
