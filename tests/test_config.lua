-- utils/config.lua: the config file's text (settings and the palette). Reading and writing the file and
-- putting the values on the modules are checked in game
local T = ...
local Config = MGE.Config

T.test("config: read, written back the same", function()
    local text = "uiScale 1.5\ncameraFollow 0\nsnapStep 0.25\nrotateStep 15\nmaxAtmo 512\n" ..
        "palette 255 0 0 255\npalette 0 128 255 100\n"
    local values, palette = Config.parse(text)
    T.eq(values.uiScale, 1.5, "uiScale")
    T.eq(values.cameraFollow, false, "cameraFollow off")
    T.eq(values.snapStep, 0.25, "snapStep")
    T.eq(values.maxAtmo, 512, "maxAtmo")
    T.eq(#palette, 2, "two colors")
    T.near(palette[2][2], 128 / 255, 1e-12, "palette green")
    T.eq(Config.format(values, palette), text, "written back")
end)

T.test("config: bad and unknown lines skipped, CRLF", function()
    local values, palette = Config.parse("# comment\r\nuiScale big\r\nsnapStep -1\r\nmaxAtmo 300.7\r\n" ..
        "cameraFollow yes\r\nsomething 5\r\npalette 1 2 3\r\npalette 300 -5 10 255\r\n\r\n")
    T.eq(values.uiScale, nil, "not a number")
    T.eq(values.snapStep, nil, "below the smallest step")
    T.eq(values.maxAtmo, 300, "whole number")
    T.eq(values.cameraFollow, nil, "not 0 / 1")
    T.eq(values.something, nil, "unknown key")
    T.eq(#palette, 1, "one usable color")
    T.eq(Config.format(values, palette), "maxAtmo 300\npalette 255 0 10 255\n", "only what's valid")
end)

T.test("config: no file", function()
    local values, palette = Config.parse(nil)
    T.eq(next(values), nil, "no values")
    T.eq(#palette, 0, "no colors")
end)

T.test("config: apply and save reach the modules", function()
    -- stand-ins for the modules the entries read and set
    local saved = { Camera = MGE.Camera, Gizmo = MGE.Gizmo, AtmoLayer = MGE.AtmoLayer, ui = MGE_UI_SCALE }
    MGE.Camera = { followMoves = true }
    MGE.Gizmo = { step = 1, rotateStep = 45 }
    MGE.AtmoLayer = { maxAtmo = 256 }
    MGE_UI_SCALE = 1.15 -- a restart's choice: the file's doesn't replace it
    Config.values = Config.parse("cameraFollow 0\nrotateStep 10\nuiScale 1.75\n")
    Config.apply()
    T.eq(MGE.Camera.followMoves, false, "camera follow set")
    T.eq(MGE.Gizmo.rotateStep, 10, "rotate step set")
    T.eq(MGE.Gizmo.step, 1, "not in the file: default stays")
    T.eq(MGE_UI_SCALE, 1.15, "restart's UI size kept")
    MGE.Gizmo.step = 0.2
    -- what save writes: every current value
    local entries = {}
    for _, entry in ipairs(Config.ENTRIES) do entries[entry.key] = entry.get() end
    T.eq(entries.snapStep, 0.2, "current snap step")
    T.eq(entries.uiScale, 1.15, "current UI size")
    MGE.Camera, MGE.Gizmo, MGE.AtmoLayer, MGE_UI_SCALE = saved.Camera, saved.Gizmo, saved.AtmoLayer, saved.ui
    Config.values = {}
end)

T.test("config: the wheel steps", function()
    local saved = { Config.wheelStep, Config.wheelFineStep }
    Config.values = Config.parse("wheelStep 1\nwheelFineStep 0.01\n")
    Config.apply()
    T.eq(Config.wheelStep, 1, "step set")
    T.eq(Config.wheelFineStep, 0.01, "fine step set")
    local values = Config.parse("wheelStep 0\nwheelFineStep -1\n")
    T.eq(values.wheelStep, nil, "0 isn't a step")
    T.eq(values.wheelFineStep, nil, "negative isn't a step")
    T.eq(Config.format({ wheelStep = 0.5, wheelFineStep = 0.05 }, {}), "wheelStep 0.5\nwheelFineStep 0.05\n", "written")
    Config.wheelStep, Config.wheelFineStep = saved[1], saved[2]
    Config.values = {}
end)
