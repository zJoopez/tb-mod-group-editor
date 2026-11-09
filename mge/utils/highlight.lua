-- Draws a highlight around selected objects, based on rph's selection highlight (replayhacks_selection.lua),
-- and boxes that don't exist yet (the Generate tab's preview)
require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

local ModData = MGE.ModData
local SHAPE = MGE.SHAPE

---@class HighlightBox
---@field pos number[]
---@field sides number[]
---@field frame number[][] rotation, columns are the box's axes in world space

local Highlight = {
    color = { 0.0, 0.333, 1.0 },
    fillAlpha = 0.25,
    previewColor = { 1.0, 0.6, 0.0 },
    previewAlpha = 0.2,
    ---@type (fun(): HighlightBox[]?)? set by the Generate tab, boxes to draw this frame
    preview = nil,
    errorShown = false,
}
MGE.Highlight = Highlight

---Rotation matrix as get_obj_rot gives it (row-major, r0 r1 r2 = first row), for draw_*_m
---@param m number[][]
---@return MatrixTB
local function toMatrixTB(m)
    return Utils3D.MatrixToMatrixTB({
        m[1][1], m[1][2], m[1][3], 0,
        m[2][1], m[2][2], m[2][3], 0,
        m[3][1], m[3][2], m[3][3], 0,
    })
end

---Translucent box with an outline, for boxes that aren't objects
---@param box HighlightBox
local function drawPreviewBox(box)
    local p, s, c = box.pos, box.sides, Highlight.previewColor
    local rot = toMatrixTB(box.frame)
    set_color(c[1], c[2], c[3], Highlight.previewAlpha)
    draw_box_m(p[1], p[2], p[3], s[1], s[2], s[3], rot)
    set_color(c[1], c[2], c[3], 1.0)
    draw_box_m(p[1], p[2], p[3], -(s[1] + 0.02), -(s[2] + 0.02), -(s[3] + 0.02), rot)
end

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
    local shape = get_obj_shape(id)
    local rot = getObjRotTB(id)
    local c = Highlight.color

    set_color(c[1], c[2], c[3], Highlight.fillAlpha)
    if shape == SHAPE.SPHERE then -- sx = radius
        draw_sphere_m(x, y, z, sx + 0.01, rot)
        set_color(c[1], c[2], c[3], 1.0)
        draw_sphere_m(x, y, z, -(sx + 0.02), rot)
    elseif shape == SHAPE.BOX then
        draw_box_m(x, y, z, sx + 0.02, sy + 0.02, sz + 0.01, rot)
        set_color(c[1], c[2], c[3], 1.0)
        draw_box_m(x, y, z, -(sx + 0.04), -(sy + 0.04), -(sz + 0.02), rot)
    elseif shape == SHAPE.CAPSULE then -- sx = radius, sy = length
        draw_capsule_m(x, y, z, sy + 0.01, sx + 0.01, rot)
        set_color(c[1], c[2], c[3], 1.0)
        draw_capsule_m(x, y, z, -(sy + 0.02), -(sx + 0.02), rot)
    end
end

add_hook("draw3d", MGE.hookname, function()
    local Main = MGE.Main -- created after this module loads
    if not Main or not Main.window or not Main.window.displayed then return end
    local ok, err = pcall(function()
        for _, obj in ipairs(ModData.parsed.env_obj) do
            if obj.selected then
                drawObjectHighlight(obj.id - 1)
            end
        end
        local boxes = Highlight.preview and Highlight.preview()
        for _, box in ipairs(boxes or {}) do drawPreviewBox(box) end
    end)
    if not ok and not Highlight.errorShown then -- report once instead of spamming every frame
        Highlight.errorShown = true
        echo("[MGE] highlight error: " .. tostring(err))
    end
end)
