-- ui/color_picker.lua: its HSV <-> RGB conversion (the overlay itself is checked in game)
local T = ...

-- the module reads its sizes at load: a stand-in for ui/widgets.lua's px is all it needs
local hadWidgets = MGE.Widgets
MGE.Widgets = MGE.Widgets or { px = function(n) return n end }
dofile(MGE.scriptPath .. "ui/color_picker.lua")
MGE.Widgets = hadWidgets
local ColorPicker = MGE.ColorPicker

T.test("hsv to rgb: the primaries and grays", function()
    local cases = {
        { { 0, 1, 1 }, { 1, 0, 0 } },
        { { 1 / 3, 1, 1 }, { 0, 1, 0 } },
        { { 2 / 3, 1, 1 }, { 0, 0, 1 } },
        { { 1 / 6, 1, 1 }, { 1, 1, 0 } },
        { { 0.5, 0, 0.4 }, { 0.4, 0.4, 0.4 } }, -- no saturation: gray whatever the hue
        { { 0.3, 1, 0 }, { 0, 0, 0 } },
    }
    for _, c in ipairs(cases) do
        local r, g, b = ColorPicker.hsvToRgb(c[1][1], c[1][2], c[1][3])
        local name = table.concat(c[1], " ")
        T.near(r, c[2][1], 1e-9, "r of " .. name)
        T.near(g, c[2][2], 1e-9, "g of " .. name)
        T.near(b, c[2][3], 1e-9, "b of " .. name)
    end
end)

T.test("rgb to hsv and back gives the same color", function()
    -- every 0-255 channel step of 17, the colors the fields can hold (as 1 for 255)
    for r = 0, 255, 17 do
        for g = 0, 255, 17 do
            for b = 0, 255, 17 do
                local h, s, v = ColorPicker.rgbToHsv(r / 255, g / 255, b / 255)
                T.ok(h >= 0 and h < 1 and s >= 0 and s <= 1 and v >= 0 and v <= 1, "hsv in range " .. r .. " " .. g .. " " .. b)
                local r2, g2, b2 = ColorPicker.hsvToRgb(h, s, v)
                T.eq(math.floor(r2 * 255 + 0.5), r, "r back " .. r .. " " .. g .. " " .. b)
                T.eq(math.floor(g2 * 255 + 0.5), g, "g back " .. r .. " " .. g .. " " .. b)
                T.eq(math.floor(b2 * 255 + 0.5), b, "b back " .. r .. " " .. g .. " " .. b)
            end
        end
    end
end)

T.test("hue at the top of the bar stays red", function()
    -- the bar's drag stops just under 1 (1 wraps back to the bottom's red, fine either way)
    local r, g, b = ColorPicker.hsvToRgb(0.9999, 1, 1)
    T.ok(r > 0.99 and g < 0.01 and b < 0.01, "near 1 is red")
end)

T.test("palette: add, same color once, full", function()
    local list = {}
    T.eq(ColorPicker.addToPalette(list, { 1, 0.5, 0, 1 }, 2), "added", "first")
    -- the picker's color isn't on the 0-255 steps: the same step is the same color
    T.eq(ColorPicker.addToPalette(list, { 1, 0.5 + 0.0005, 0, 1 }, 2), "exists", "same 0-255 color")
    T.eq(ColorPicker.addToPalette(list, { 0, 0, 0, 1 }, 2), "added", "second")
    T.eq(ColorPicker.addToPalette(list, { 1, 1, 1, 1 }, 2), "full", "third")
    T.eq(#list, 2, "two kept")
    T.eq(MGE.Config.format({}, list), "palette 255 128 0 255\npalette 0 0 0 255\n", "stored on the 0-255 steps")
end)
