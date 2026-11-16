








local Rows = MGE.EditorRows
local Widgets = MGE.Widgets
local ModData = MGE.ModData
local History = MGE.History
local createRow = Rows.createRow
local createToggleButtonRow = Rows.createToggleButtonRow




local function findMessage()
    for i, line in ipairs(ModData.parsed.ignores or {}) do
        if line:match("^%s*message%s") or line:match("^%s*message$") then
            return i, line:match("^%s*message%s*(.-)%s*$")
        end
    end
    return nil, nil
end



local function setMessage(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not ModData.parsed.ignores then return end
    local i, current = findMessage()
    if (current or "") == text then return end


    local ignores = {}
    for k, line in ipairs(ModData.parsed.ignores) do ignores[k] = line end
    ModData.parsed.ignores = ignores
    if text == "" then
        table.remove(ignores, i)
    elseif i then
        ignores[i] = "message " .. text
    else

        local at = 1
        while ignores[at] and (ignores[at]:match("^#!") or ignores[at]:match("^%s*version%s")) do at = at + 1 end
        table.insert(ignores, at, "message " .. text)
    end
    History.commit()
    MGE.apply()
end




local function findShader()
    for i, line in ipairs(MGE.Atmo.state.header) do
        local name = line:match("^%s*shader%s+(.-)%s*$")
        if name then return i, name end
    end
    return nil, nil
end




local function setShader(name)
    local header = MGE.Atmo.state.header
    local i = findShader()
    if name and name ~= "" then
        if i then header[i] = "shader " .. name else table.insert(header, 1, "shader " .. name) end
    elseif i then
        table.remove(header, i)
    end
    MGE.Atmo.headerVersion = MGE.Atmo.headerVersion + 1
    MGE.Atmo.applyShader()
    Rows.refreshBlocks({ "miscFile" })
end







local function createTextInput(container, text, placeholder, onEnter)
    local input = TBMenu:spawnTextField2(container, nil, text, placeholder, {
        inputType = KEYBOARD_INPUT.ASCII,
        textfield = true,
        returnKeyType = KEYBOARD_RETURN.SEND,
        textAlign = CENTER,
        fontId = Widgets.FONT,
        darkerMode = true,
        textScale = Widgets.TEXT_SCALE_SMALL,
    })
    input:addKeyboardHandlers(nil, function(key)
        if key == 13 then onEnter(input.textfieldstr[1] or "") end
    end)
    return input
end



local function buildFileRows(holder)
    Rows.begin()
    local row, contentX, contentW = createRow("Message", holder,
        "Shown in chat when the mod loads (its message line).\nEnter applies it, empty removes it.")
    local container = row:addChild({ pos = { contentX, 0 }, size = { contentW, row.size.h } })
    local _, message = findMessage()
    createTextInput(container, message or "", "No message", setMessage)

    local _, shader = findShader()
    row, contentX, contentW = createRow("Shader", holder,
        "The atmo's shader, saved with it.\nTrash icon: no shader.")
    local gap, inset = Widgets.GAP, Widgets.INSET
    local h = row.size.h - inset * 2
    local noneW = h
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
    Widgets.popupBelow(none, "No shader (remove)")
end



local function buildMapRow(holder)
    Rows.begin()
    createToggleButtonRow("Map", holder, {
        { label = "Convert map", active = false, onClick = function()
            if MGE.overlayOpen() then return end

            local ok, err = pcall(MGE.loadMapConv)
            if not ok then
                MGE.say("the map converter didn't load: " .. tostring(err))
                return
            end
            dofile(MGE.scriptPath .. "ui/map_overlay.lua")
        end },
    }, "Turns a .vmf (Hammer) or Source .bsp map (CS:S,\n" ..
        "CS:GO, TF2...) into static boxes, added where\nthe map puts them. Maps go in assets/maps.")
end



local function resetAll()
    if MGE.overlayOpen() then return end
    local function load()
        MGE.say("loading classic")
        MGE.loadMod("classic")
    end
    if MGE.hasUnsavedChanges() then
        MGE.confirm("Load the classic mod? Unsaved changes to this mod and its atmo are lost.", load)
    else
        load()
    end
end



local function buildModRow(holder)
    Rows.begin()
    createToggleButtonRow("Mod", holder, {
        { label = "Reset all", active = false, onClick = resetAll },
    }, "Loads the classic mod (/lm classic): a fresh start.\nAsks first when there are unsaved changes.")
end



local function buildCredits(holder)
    local line = holder:addChild({ pos = { 0, 0 }, size = { holder.size.w, holder.size.h } })
    line:addAdaptedText("Project Mod Group Editor by joopez", nil, nil, Widgets.FONT, CENTERMID, Widgets.TEXT_SCALE_SMALL)
end


return {
    fixed = {
        { build = buildMapRow, panel = "misc", row = 2, rows = 1 },
        { build = buildModRow, panel = "misc", row = 3, rows = 1 },
        { build = buildCredits, panel = "misc", row = 8, rows = 1 },
    },
    blocks = {
        { name = "miscFile", build = buildFileRows, panel = "misc", row = 0, rows = 2 },
    },
}
