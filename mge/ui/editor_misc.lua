-- Misc list tab's panel: things about the whole mod, not the selected objects
--   Message: the mod's `message` line (the game shows it in chat when the mod loads), one of the mod file's
--            lines before its objects (ModData.parsed.ignores). Typed, Enter applies it, empty removes it
--   Shader:  the atmo file's `shader` line (utils/atmo.lua: Atmo.state.header), a data/shader/<name>.inc. Loaded
--            in the game right away (Atmo.applyShader); players get it when they load the mod's atmo (Shaders &
--            Atmos > Atmos), Save writes it
--   Ids:     Reindex (it was on the Advanced tab: acts on all objects, not the selection)
--   Map:     Convert map (it was on the Advanced tab: adds a whole map, not about the selection)
local Rows = MGE.EditorRows
local Widgets = MGE.Widgets
local ModData = MGE.ModData
local History = MGE.History
local createRow = Rows.createRow
local createToggleButtonRow = Rows.createToggleButtonRow

---The mod's message line
---@return integer? index in ModData.parsed.ignores, nil without one
---@return string? text
local function findMessage()
    for i, line in ipairs(ModData.parsed.ignores or {}) do
        if line:match("^%s*message%s") or line:match("^%s*message$") then
            return i, line:match("^%s*message%s*(.-)%s*$")
        end
    end
    return nil, nil
end

---Sets the message line (empty: removes it), one undo step, the mod reloads with it
---@param text string?
local function setMessage(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not ModData.parsed.ignores then return end
    local i, current = findMessage()
    if (current or "") == text then return end
    -- a new list, the old one stays as it is: the undo history shares these lines between its steps and
    -- tells them apart by the table (utils/history.lua: never modified, only replaced)
    local ignores = {}
    for k, line in ipairs(ModData.parsed.ignores) do ignores[k] = line end
    ModData.parsed.ignores = ignores
    if text == "" then
        table.remove(ignores, i)
    elseif i then
        ignores[i] = "message " .. text
    else
        -- after the #! and version lines, where the game's own mods have it
        local at = 1
        while ignores[at] and (ignores[at]:match("^#!") or ignores[at]:match("^%s*version%s")) do at = at + 1 end
        table.insert(ignores, at, "message " .. text)
    end
    History.commit()
    MGE.apply()
end

---The atmo's shader line
---@return integer? index in Atmo.state.header
---@return string? shader name (data/shader/<name>.inc)
local function findShader()
    for i, line in ipairs(MGE.Atmo.state.header) do
        local name = line:match("^%s*shader%s+(.-)%s*$")
        if name then return i, name end
    end
    return nil, nil
end

---Sets the atmo's shader line (nil: removes it). The atmo's own lines aren't in the undo history: Save
---writes them with the atmo (the footer says there are unsaved changes)
---@param name string?
local function setShader(name)
    local header = MGE.Atmo.state.header
    local i = findShader()
    if name and name ~= "" then
        if i then header[i] = "shader " .. name else table.insert(header, 1, "shader " .. name) end
    elseif i then
        table.remove(header, i)
    end
    MGE.Atmo.headerVersion = MGE.Atmo.headerVersion + 1 -- the footer shows the unsaved change
    MGE.Atmo.applyShader() -- shown right away (the player's own shader back when removed)
    Rows.refreshBlocks({ "miscFile" })
end

---A text field for any text (the editor's fields are numbers only), Enter calls onEnter with its text
---@param container UIElement
---@param text string
---@param placeholder string
---@param onEnter fun(text: string)
---@return UIElement
local function createTextInput(container, text, placeholder, onEnter)
    local input = TBMenu:spawnTextField2(container, nil, text, placeholder, {
        inputType = KEYBOARD_INPUT.ASCII,
        textfield = true,
        returnKeyType = KEYBOARD_RETURN.SEND,
        textAlign = CENTER,
        fontId = Widgets.FONT,
        darkerMode = true, -- the window's color, like the editor's other fields
        textScale = Widgets.TEXT_SCALE_SMALL,
    })
    input:addKeyboardHandlers(nil, function(key)
        if key == 13 then onEnter(input.textfieldstr[1] or "") end -- Enter
    end)
    return input
end

---Message and Shader rows, rebuilt with the editor (another mod: its message and atmo)
---@param holder UIElement
local function buildFileRows(holder)
    Rows.begin()
    local row, contentX, contentW = createRow("Message", holder,
        "Shown in chat when the mod loads (its message line).\nEnter applies it, empty removes it.")
    local container = row:addChild({ pos = { contentX, 0 }, size = { contentW, row.size.h } })
    local _, message = findMessage()
    createTextInput(container, message or "", "No message", setMessage)

    local _, shader = findShader()
    row, contentX, contentW = createRow("Shader", holder,
        "The atmo's shader (data/shader), shown right away. Players\n" ..
        "get it with the mod's atmo (Shaders & Atmos > Atmos), Save\n" ..
        "writes it. Trash icon: no shader (your own comes back).")
    local gap, inset = Widgets.GAP, Widgets.INSET -- like the number fields
    local h = row.size.h - inset * 2
    local noneW = h -- square icon button, the shader's name gets the rest
    local pickW = contentW - inset * 2 - gap - noneW
    Widgets.button(row, { x = contentX + inset, y = inset, w = pickW, h = h }, shader or "Pick shader", function()
        MGE.FilePicker.open({
            title = "Pick Shader",
            root = "data/shader",
            rootLabel = "shader",
            extension = "inc",
            selected = shader,
            confirmLabel = "Use shader",
            onConfirm = setShader,
        })
    end, nil, Widgets.PANEL_STYLE)
    local none = Widgets.iconButton(row, { x = contentX + inset + pickW + gap, y = inset, w = noneW, h = h },
        "../textures/menu/general/buttons/trash.tga", function() setShader(nil) end, Widgets.PANEL_STYLE)
    TBMenu:displayPopup(none, "No shader (remove)")
end

---Dynamic objects can end up above id 48 (the footer warns), this moves them down and static
---objects up, as far as ids allow. Acts on all objects, not the selection
local function reindex()
    local moved, left = ModData.reindex()
    if left > 0 then
        print("reindex: " .. left .. " dynamic objects still above id " .. MGE.MAX_NONSTATIC_OBJECTS ..
            ", make some static")
    end
    if moved == 0 then
        print("reindex: nothing to move")
        return
    end
    History.commit()
    MGE.apply()
    print("reindex moved " .. moved .. " objects")
end

---Ids row, built once: its button acts on all objects, nothing to refresh
---@param holder UIElement
local function buildIdRow(holder)
    Rows.begin()
    createToggleButtonRow("Ids", holder, {
        { label = "Reindex", active = false, onClick = reindex },
    }, "Moves dynamic objects to ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS .. ", static above.\n" ..
        "Acts on all objects, joints follow.")
end

---Map row, built once: opens the Convert Map overlay (ui/map_overlay.lua)
---@param holder UIElement
local function buildMapRow(holder)
    Rows.begin()
    createToggleButtonRow("Map", holder, {
        { label = "Convert map", active = false, onClick = function()
            if MGE.overlayOpen() then return end
            -- loaded on first use (MGE.loadMapConv): a broken converter says so and the editor keeps working
            local ok, err = pcall(MGE.loadMapConv)
            if not ok then
                echo("^04[MGE] the map converter didn't load: " .. tostring(err))
                return
            end
            dofile(MGE.scriptPath .. "ui/map_overlay.lua")
        end },
    }, "Turns a .vmf (Hammer) or Source .bsp map (CS:S,\n" ..
        "CS:GO, TF2...) into static boxes, added where\nthe map puts them. Maps go in assets/maps.")
end

---@type EditorPanelModule
return {
    fixed = {
        { build = buildIdRow, panel = "misc", row = 2, rows = 1 },
        { build = buildMapRow, panel = "misc", row = 3, rows = 1 },
    },
    blocks = {
        { name = "miscFile", build = buildFileRows, panel = "misc", row = 0, rows = 2 },
    },
}
