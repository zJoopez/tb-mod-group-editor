-- Draws a highlight around selected objects, based on rph's selection highlight (replayhacks_selection.lua)
require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

Highlight = {
    color = { 0.0, 0.333, 1.0 },
    fillAlpha = 0.25,
    errorShown = false,
}

---get_obj_rot can return a flat number array, draw_*_m expects a MatrixTB (r0..r15)
---@param id integer 0-based object id
---@return MatrixTB?
local function getObjRotTB(id)
    local rot = get_obj_rot(id)
    if type(rot) ~= "table" then return nil end
    return Utils3D.MatrixToMatrixTB(rot)
end

---Draws translucent fill slightly larger than the object, then a negative-size pass
---which renders the inverted shell and reads as an outline
---@param id integer 0-based object id
local function drawObjectHighlight(id)
    local x, y, z = get_obj_pos(id)
    if x == nil then return end
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id) -- 0 sphere, 1 box, 2 capsule
    local rot = getObjRotTB(id)
    local c = Highlight.color

    set_color(c[1], c[2], c[3], Highlight.fillAlpha)
    if shape == 0 then -- sx = radius
        draw_sphere_m(x, y, z, sx + 0.01, rot)
        set_color(c[1], c[2], c[3], 1.0)
        draw_sphere_m(x, y, z, -(sx + 0.02), rot)
    elseif shape == 1 then
        draw_box_m(x, y, z, sx + 0.02, sy + 0.02, sz + 0.01, rot)
        set_color(c[1], c[2], c[3], 1.0)
        draw_box_m(x, y, z, -(sx + 0.04), -(sy + 0.04), -(sz + 0.02), rot)
    elseif shape == 2 then -- sx = radius, sy = length
        draw_capsule_m(x, y, z, sy + 0.01, sx + 0.01, rot)
        set_color(c[1], c[2], c[3], 1.0)
        draw_capsule_m(x, y, z, -(sy + 0.02), -(sx + 0.02), rot)
    end
end

add_hook("draw3d", MGE.hookname, function()
    if not Main or not Main.window or not Main.window.displayed then return end
    local ok, err = pcall(function()
        for _, obj in ipairs(ModData.parsed.env_obj) do
            if obj.selected then
                drawObjectHighlight(obj.id - 1)
            end
        end
    end)
    if not ok and not Highlight.errorShown then -- report once instead of spamming every frame
        Highlight.errorShown = true
        echo("[MGE] highlight error: " .. tostring(err))
    end
end)
