--- /ls tb-move-stuff/test.lua
--- /lm mge-modmaker.tbm
--- overwrite during dev

local devMode = true
if (MGE == nil or devMode) then
---@class MGE
---@field tmpName string
---@field modName string?
---@field modPath string
---@field atmosphere Atmosphere?
---@field hookname string
---@field window UIElement?
---@field windowContainer UIElement?
MGE = {
    tmpName = "mge-modmaker.tbm",
    modName = get_game_rules().mod,
    modPath = "../data/mod/",
    hookname = "mge",
    window = nil,
    windowContainer = nil,
    atmosphere = nil,
}
end
MGE.window, MGE.windowContainer = TBMenu:spawnMoveableWindow({
    x = 10,
    y = 100,
    w = 300,
    h = 50
})

function MGE.quit()
    remove_hooks(MGE.hookname)
end

MGE.window.killAction = MGE.quit

local function debugCheckAtmo()
    print(MGE.atmosphere)
    if (not MGE.atmosphere) then return end
    for index, value in ipairs(MGE.atmosphere.shaderopts) do
        print_r(value)
    end
end

function MGE.updateSource()
    runCmd("clear")
    MGE.modName = get_game_rules().mod
    local path = find_mod(MGE.modName)
    MGE.atmosphere = Atmospheres.ParseFile(MGE.modPath .. path) -- Does't work for some mods (bad mod or old format?)
    if devMode then debugCheckAtmo() end
end

function MGE.SaveFile()
    local file = Files.Open(MGE.modPath .. MGE.tmpName, FILES_MODE_WRITE)
    if not file.data then
        print("Save Failed: Missing File")
        return false
    end

    if MGE.atmosphere.shader then
        file:writeLine("shader " .. MGE.atmosphere.shader)
    end

    for _, e in ipairs(MGE.atmosphere.entities or {}) do  --doesn't seem to have all required data
        file:writeLine("env_obj " .. e.name)
        if e.shape then
            local shape = "box"
            if e.shape == CAPSULE then
                shape = "cylinder"
            elseif e.shape == SPHERE then
                shape = "sphere"
            elseif e.shape == CUSTOMOBJ then
                shape = "custom " .. (e.model or "")
            end
            file:writeLine("   shape " .. shape)
        end
        if e.pos then file:writeLine("   pos " .. e.pos[1] .. " " .. e.pos[2] .. " " .. e.pos[3]) end
        if e.weight then file:writeLine("   count " .. e.weight) end
        if e.color then
            file:writeLine("   color " ..
                e.color[1] .. " " .. e.color[2] .. " " .. e.color[3] .. " " .. e.color[4])
        end
        if e.rot then file:writeLine("   rot " .. e.rot[1] .. " " .. e.rot[2] .. " " .. e.rot[3]) end
        if e.size then file:writeLine("   sides " .. e.size[1] .. " " .. e.size[2] .. " " .. e.size[3]) end
    end

    file:close()
    print("Save Complete")
    return true
end

MGE.updateSource()
if MGE.atmosphere then
    MGE.SaveFile()
end

add_hook("match_begin", MGE.hookname, function()
    MGE.updateSource()
end)
