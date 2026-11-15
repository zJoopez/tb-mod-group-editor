-- don't start a second instance, show the running one instead
if MGE and MGE.running then
    echo("^04[MGE] already running, F1 shows/hides the window")
    local Main = MGE.Main
    if Main and Main.window and not Main.window.displayed then
        Main.window:show(false)
        -- like F1 showing it, a frame later: this /ls fires "unload" after this runs, which puts the HUD back
        if MGE.hideGameHudNextFrame then MGE.hideGameHudNextFrame() end
        Main.updateWindow()
    end
    return
end
-- leftovers from a start that failed halfway (hooks, window)
if MGE and MGE.quit then pcall(MGE.quit) end

local devPrefix = ""
devPrefix = "mge/" --dev

MGE = { scriptPath = devPrefix .. "mge/" }
dofile(MGE.scriptPath .. "main.lua")

--- /ls mge/mge.lua
--- /lm mge-modmaker.tbm
--- /lm mge-modmaker1.tbm
