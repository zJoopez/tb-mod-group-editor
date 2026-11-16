

require("toriui.uielement3d")

local ModData = MGE.ModData
local SHAPE = MGE.SHAPE






local Highlight = {
    color = { 0.0, 0.333, 1.0 },
    fillAlpha = 0.25,
    previewColor = { 1.0, 0.6, 0.0 },
    previewAlpha = 0.2,




    drawRoom = 256,

    preview = nil,

    placement = nil,
    errorShown = false,
}
MGE.Highlight = Highlight




local function toMatrixTB(m)
    return Utils3D.MatrixToMatrixTB({
        m[1][1], m[1][2], m[1][3], 0,
        m[2][1], m[2][2], m[2][3], 0,
        m[3][1], m[3][2], m[3][3], 0,
    })
end

Highlight.toMatrixTB = toMatrixTB





local rotCache = setmetatable({}, { __mode = "k" })







function Highlight.drawBox(box, color, fillAlpha, outline)
    local p, s, c = box.pos, box.sides, color
    local rot = rotCache[box.frame]
    if not rot then
        rot = toMatrixTB(box.frame)
        rotCache[box.frame] = rot
    end
    if fillAlpha > 0 then
        set_color(c[1], c[2], c[3], fillAlpha)
        draw_box_m(p[1], p[2], p[3], s[1], s[2], s[3], rot)
    end
    if outline ~= false then
        set_color(c[1], c[2], c[3], 1.0)
        draw_box_m(p[1], p[2], p[3], -(s[1] + 0.02), -(s[2] + 0.02), -(s[3] + 0.02), rot)
    end
end



local function drawPreviewBox(box)
    Highlight.drawBox(box, Highlight.previewColor, Highlight.previewAlpha, true)
end




local function getObjRotTB(id)
    local rot = get_obj_rot(id)
    if type(rot) ~= "table" then return nil end
    return Utils3D.MatrixToMatrixTB(rot)
end




local function colorOf(obj)


    local line = obj.props.color or "1 1 1 1"
    local cached = obj.colorCache
    if cached and cached.line == line then return cached.color end
    local c = {}
    for n in tostring(line):gmatch("%S+") do c[#c + 1] = tonumber(n) or 1 end
    for k = 1, 4 do c[k] = math.min(math.max(c[k] or 1, 0), 1) end
    obj.colorCache = { line = line, color = c }
    return c
end






local function drawGhost(g, c, alpha, outline)
    local p, s = g.pos, g.sides
    if g.shape == "box" then
        Highlight.drawBox(g, c, alpha, outline)
        return
    end
    local rot = rotCache[g.frame]
    if not rot then
        rot = toMatrixTB(g.frame)
        rotCache[g.frame] = rot
    end
    set_color(c[1], c[2], c[3], alpha)
    if g.shape == "sphere" then
        draw_sphere_m(p[1], p[2], p[3], s[1], rot)
    else
        draw_capsule_m(p[1], p[2], p[3], s[2], s[1], rot)
    end
end















local function drawShapeHighlight(shape, x, y, z, sx, sy, sz, rot, color, fillOnly)
    local c = color
    set_color(c[1], c[2], c[3], Highlight.fillAlpha)
    if shape == "sphere" then
        draw_sphere_m(x, y, z, sx + 0.01, rot)
        if fillOnly then return end
        set_color(c[1], c[2], c[3], 1.0)
        draw_sphere_m(x, y, z, -(sx + 0.02), rot)
    elseif shape == "box" then
        draw_box_m(x, y, z, sx + 0.02, sy + 0.02, sz + 0.01, rot)
        if fillOnly then return end
        set_color(c[1], c[2], c[3], 1.0)
        draw_box_m(x, y, z, -(sx + 0.04), -(sy + 0.04), -(sz + 0.02), rot)
    else
        draw_capsule_m(x, y, z, sy + 0.01, sx + 0.01, rot)
        if fillOnly then return end
        set_color(c[1], c[2], c[3], 1.0)
        draw_capsule_m(x, y, z, -(sy + 0.02), -(sx + 0.02), rot)
    end
end


local SELECTED_ALPHA = 0.75


local view = nil






local function onScreen(g)
    local v = view
    if not v then return true end
    local e, f = v.eye, v.forward
    local rx, ry, rz = g.pos[1] - e[1], g.pos[2] - e[2], g.pos[3] - e[3]
    local r = g.radius or 0
    local depth = rx * f[1] + ry * f[2] + rz * f[3]
    if depth < -r then return false end
    if depth <= r then return true end
    local a = (rx * v.right[1] + ry * v.right[2] + rz * v.right[3]) / depth
    local b = (rx * v.up[1] + ry * v.up[2] + rz * v.up[3]) / depth
    local x, y = v.cx + v.m11 * a + v.m12 * b, v.cy + v.m21 * a + v.m22 * b

    local sr = r / depth * math.sqrt(v.m11 * v.m11 + v.m21 * v.m21) * 1.5 + 8
    return x + sr >= 0 and x - sr <= WIN_W and y + sr >= 0 and y - sr <= WIN_H
end










local function drawAtmo(full)
    local AtmoLayer = MGE.AtmoLayer
    local list = ModData.parsed.atmo or {}
    if not full then
        for _, obj in ipairs(list) do
            local g = AtmoLayer.ghost(obj)
            if g and onScreen(g) then drawGhost(g, AtmoLayer.color, AtmoLayer.alpha, false) end
        end
        return
    end


    local live = AtmoLayer.live
    for _, atmoObj in ipairs(list) do
        local g = AtmoLayer.ghost(atmoObj)
        local selected = atmoObj.selected
        if g and live and selected then g = AtmoLayer.liveGhost(g, live) end
        if g and onScreen(g) then
            local c = colorOf(atmoObj)
            if selected then

                drawGhost(g, Highlight.color, math.max(c[4], SELECTED_ALPHA), false)
            else
                drawGhost(g, c, c[4], false)
            end
        end
    end
end





local function drawObjectHighlight(id, color, fillOnly)
    local x, y, z = get_obj_pos(id)
    if x == nil then return end
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    local name = shape == SHAPE.SPHERE and "sphere" or shape == SHAPE.BOX and "box"
        or shape == SHAPE.CAPSULE and "pill" or nil
    if not name then return end
    drawShapeHighlight(name, x, y, z, sx, sy, sz, getObjRotTB(id), color or Highlight.color, fillOnly)
end








local function highlightPlan(count, room)
    room = math.max(0, room)
    if count * 2 <= room then return false, count end
    return true, math.min(count, room)
end
Highlight.highlightPlan = highlightPlan


local BODY_SPHERE, BODY_CYLINDER = 0, 2






local function drawPlayerHighlight(player, scale)
    local c = scale and Highlight.previewColor or Highlight.color
    local f = scale and scale.factor or 1




    local function at(x, y, z)
        if not scale then return { x = x, y = y, z = z } end
        local q = scale.pivot
        return { x = q[1] + (x - q[1]) * f, y = q[2] + (y - q[2]) * f, z = q[3] + (z - q[3]) * f }
    end
    for _, id in pairs(BODYPARTS) do
        local b = get_body_info(player, id)
        local p, rot = at(b.pos.x, b.pos.y, b.pos.z), b.rot
        local s = { x = b.sides.x * f, y = b.sides.y * f, z = b.sides.z * f }
        set_color(c[1], c[2], c[3], Highlight.fillAlpha)
        if b.shape == BODY_SPHERE then
            draw_sphere_m(p.x, p.y, p.z, s.x + 0.01, rot)
            set_color(c[1], c[2], c[3], 1.0)
            draw_sphere_m(p.x, p.y, p.z, -(s.x + 0.02), rot)
        elseif b.shape == BODY_CYLINDER then
            draw_capsule_m(p.x, p.y, p.z, s.y + 0.01, s.x + 0.01, rot)
            set_color(c[1], c[2], c[3], 1.0)
            draw_capsule_m(p.x, p.y, p.z, -(s.y + 0.02), -(s.x + 0.02), rot)
        else
            draw_box_m(p.x, p.y, p.z, s.x + 0.02, s.y + 0.02, s.z + 0.02, rot)
            set_color(c[1], c[2], c[3], 1.0)
            draw_box_m(p.x, p.y, p.z, -(s.x + 0.04), -(s.y + 0.04), -(s.z + 0.04), rot)
        end
    end
    set_color(c[1], c[2], c[3], Highlight.fillAlpha)
    for _, id in pairs(JOINTS) do
        local x, y, z = get_joint_pos(player, id)
        if x then
            local p = at(x, y, z)
            draw_sphere(p.x, p.y, p.z, (get_joint_radius(player, id) or 0.1) * f + 0.01)
        end
    end
end

local JOINT_ANCHOR_RADIUS = 0.12

Highlight.anchorPickRadius = JOINT_ANCHOR_RADIUS * 2




local function drawAnchor(x, y, z, faint)
    local c = Highlight.previewColor
    set_color(c[1], c[2], c[3], faint and 0.35 or 1.0)
    draw_sphere(x, y, z, JOINT_ANCHOR_RADIUS)
    set_color(c[1], c[2], c[3], faint and 0.1 or 0.3)
    draw_sphere(x, y, z, JOINT_ANCHOR_RADIUS * 2)
end




local function drawJointAnchor(joint, faint)
    local p = MGE.Joints.anchorOf(joint)
    if p then drawAnchor(p[1], p[2], p[3], faint) end
end





local function drawJointHighlights(joints)
    local objects, selected = {}, {}
    for _, joint in ipairs(joints) do
        selected[joint] = true
        if joint.obj1 then objects[joint.obj1] = true end
        if joint.obj2 then objects[joint.obj2] = true end
    end
    for id in pairs(objects) do drawObjectHighlight(id - 1) end
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        if not selected[joint] then drawJointAnchor(joint, true) end
    end
    for _, joint in ipairs(joints) do drawJointAnchor(joint) end
end

local HOVER_COLOR = { 1.0, 1.0, 1.0 }






local function drawLinkHighlights(slot)
    local Joints = MGE.Joints
    local draft = Joints.draftFor(slot)
    local hover = MGE.WorldSelect and MGE.WorldSelect.hover
    if draft.obj1 then drawObjectHighlight(draft.obj1 - 1) end
    if draft.obj2 then drawObjectHighlight(draft.obj2 - 1) end
    if hover then drawObjectHighlight(hover.id - 1, HOVER_COLOR) end

    local selected = MGE.Main.selectedJoints
    for _, other in ipairs(ModData.parsed.env_obj_joint) do
        if other.id ~= slot then drawJointAnchor(other, not selected[other.id]) end
    end
    local joint = Joints.find(slot)
    if joint then
        drawJointAnchor(joint)
    elseif draft.obj1 and draft.obj2 then
        local ax, ay, az = get_obj_pos(draft.obj1 - 1)
        local bx, by, bz = get_obj_pos(draft.obj2 - 1)
        if ax and bx then drawAnchor((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2) end
    end
end

add_hook("draw3d", MGE.hookname, function()
    local Main = MGE.Main
    if not Main or not Main.window then return end
    local ok, err = pcall(function()


        view = MGE.WorldSelect and MGE.WorldSelect.measureProjection() or nil


        local boxes, anchors
        if Highlight.preview then boxes, anchors = Highlight.preview() end
        if Highlight.placement then Highlight.placement() end
        if not Main.window.displayed then return end
        if Main.listTab == "players" then


            local Players = MGE.Players
            local scale = Players and Players.scalePreview
            for _, player in ipairs(scale and scale.players or Main.selectedPlayerList()) do
                if Players and Players.exists(player) then drawPlayerHighlight(player, scale) end
            end
            return
        end
        if Main.listTab == "joints" then


            local slot = Main.linkSlot()
            if slot then drawLinkHighlights(slot) else drawJointHighlights(Main.selectedJointList()) end
            return
        end



        for _, box in ipairs(boxes or {}) do drawPreviewBox(box) end
        for _, p in ipairs(anchors or {}) do drawAnchor(p[1], p[2], p[3]) end
        local atmo = Main.listTab == "atmo"
        drawAtmo(atmo)

        local WorldSelect = MGE.WorldSelect
        if WorldSelect and WorldSelect.picking and WorldSelect.hover then
            drawObjectHighlight(WorldSelect.hover.id - 1, HOVER_COLOR)
        end
        if not atmo then
            local ids = {}
            for _, obj in ipairs(ModData.parsed.env_obj) do
                if obj.selected then ids[#ids + 1] = obj.id - 1 end
            end
            local fillOnly, drawn = highlightPlan(#ids, Highlight.drawRoom)
            for i = 1, drawn do drawObjectHighlight(ids[i], nil, fillOnly) end
        end
    end)
    if not ok and not Highlight.errorShown then
        Highlight.errorShown = true
        MGE.say("highlight error: " .. tostring(err))
    end
end)
