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
    ---@type (fun(): HighlightBox[]?, number[][]?)? set by the Generate tab, boxes and joint anchors to draw this frame
    preview = nil,
    ---@type fun()? set while the map placement view is open (ui/map_place.lua), draws with Highlight.drawBox
    placement = nil,
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

Highlight.toMatrixTB = toMatrixTB -- also used by the gizmo

---Box that isn't an object: translucent fill, and an outline (a negative-size pass) unless outline is
---false. fillAlpha 0 draws only the outline
---@param box HighlightBox
---@param color number[]
---@param fillAlpha number
---@param outline boolean?
function Highlight.drawBox(box, color, fillAlpha, outline)
    local p, s, c = box.pos, box.sides, color
    local rot = toMatrixTB(box.frame)
    if fillAlpha > 0 then
        set_color(c[1], c[2], c[3], fillAlpha)
        draw_box_m(p[1], p[2], p[3], s[1], s[2], s[3], rot)
    end
    if outline ~= false then
        set_color(c[1], c[2], c[3], 1.0)
        draw_box_m(p[1], p[2], p[3], -(s[1] + 0.02), -(s[2] + 0.02), -(s[3] + 0.02), rot)
    end
end

---The Generate tab's preview boxes
---@param box HighlightBox
local function drawPreviewBox(box)
    Highlight.drawBox(box, Highlight.previewColor, Highlight.previewAlpha, true)
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
---@param color number[]? defaults to Highlight.color
local function drawObjectHighlight(id, color)
    local x, y, z = get_obj_pos(id)
    if x == nil then return end
    local sx, sy, sz = get_obj_sides(id)
    local shape = get_obj_shape(id)
    local rot = getObjRotTB(id)
    local c = color or Highlight.color

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

-- player body part shapes (BodyInfo.shape): sphere x radius, box sides, cylinder (pill) x radius y length
local BODY_SPHERE, BODY_CYLINDER = 0, 2 -- 1 is a box, the default branch

---Same highlight as objects, on every body part and joint of a player (Players list). With scale (a
---scale drag, Players.scalePreview) the player is drawn scaled around the pivot in the preview color:
---the bodies can't be resized live, this shows what the release will make
---@param player integer 0-based
---@param scale { pivot: number[], factor: number }?
local function drawPlayerHighlight(player, scale)
    local c = scale and Highlight.previewColor or Highlight.color
    local f = scale and scale.factor or 1
    ---@param x number
    ---@param y number
    ---@param z number
    ---@return table
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
-- the halo's radius: what a click on a joint's anchor hits (utils/world_select.lua, WorldSelect.pickJoint)
Highlight.anchorPickRadius = JOINT_ANCHOR_RADIUS * 2

---A joint's anchor: a solid core in the preview color, a translucent halo so it reads inside objects.
---Faint: an unselected joint on the Joints list, there to be clicked
---@param faint boolean?
local function drawAnchor(x, y, z, faint)
    local c = Highlight.previewColor
    set_color(c[1], c[2], c[3], faint and 0.35 or 1.0)
    draw_sphere(x, y, z, JOINT_ANCHOR_RADIUS)
    set_color(c[1], c[2], c[3], faint and 0.1 or 0.3)
    draw_sphere(x, y, z, JOINT_ANCHOR_RADIUS * 2)
end

---A joint's anchor, where a Move gizmo drag has it so far (Joints.anchorOf)
---@param joint FileParserEnvObjJoint
---@param faint boolean?
local function drawJointAnchor(joint, faint)
    local p = MGE.Joints.anchorOf(joint)
    if p then drawAnchor(p[1], p[2], p[3], faint) end
end

---Joints list: every object a selected joint links gets the object highlight, each selected joint's
---anchor (its pos line, where the game joins the two) a sphere in the preview color. The other joints'
---anchors are faint, a click on one selects it
---@param joints FileParserEnvObjJoint[] the selected ones
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

local HOVER_COLOR = { 1.0, 1.0, 1.0 } -- what a click would pick (or take out)

---The Link tab's draft (Joints.draftFor): the picked objects in the selection color, the object under
---the cursor in white. A joint shows its anchor (Update keeps it), a new one where Create would put it
---(halfway between the two). The other selected joints' anchors are bright too, the unselected ones
---faint (a click on one selects it)
---@param slot integer
local function drawLinkHighlights(slot)
    local Joints = MGE.Joints
    local draft = Joints.draftFor(slot)
    local hover = MGE.WorldSelect and MGE.WorldSelect.hover
    if draft.obj1 then drawObjectHighlight(draft.obj1 - 1) end
    if draft.obj2 then drawObjectHighlight(draft.obj2 - 1) end
    if hover then drawObjectHighlight(hover.id - 1, HOVER_COLOR) end
    -- the other selected joints bright (Update links them all to the picked pair), the rest faint
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
    local Main = MGE.Main -- created after this module loads
    if not Main or not Main.window then return end
    local ok, err = pcall(function()
        -- asked every frame, also when it isn't drawn (another list, window hidden): that's how it sees
        -- the Generate tab being left, coming back looks at the shape again
        local boxes, anchors
        if Highlight.preview then boxes, anchors = Highlight.preview() end
        if Highlight.placement then Highlight.placement() end -- map placement, on any list
        if not Main.window.displayed then return end -- the placement view hides the window, only it draws
        if Main.listTab == "players" then
            -- the players list: the selected players, not the objects (they aren't what's edited there).
            -- During a scale drag the scaled players instead
            local Players = MGE.Players
            local scale = Players and Players.scalePreview
            for _, player in ipairs(scale and scale.players or Main.selectedPlayerList()) do
                if Players and Players.exists(player) then drawPlayerHighlight(player, scale) end
            end
            return
        end
        if Main.listTab == "joints" then
            -- the Joints list: the selected joints, their objects and anchors (not the object selection).
            -- On the Link tab the selected slot's draft instead
            local slot = Main.linkSlot()
            if slot then drawLinkHighlights(slot) else drawJointHighlights(Main.selectedJointList()) end
            return
        end
        for _, obj in ipairs(ModData.parsed.env_obj) do
            if obj.selected then
                drawObjectHighlight(obj.id - 1)
            end
        end
        -- a pick in progress (the Core tab's color picker): the object a click would take, in white
        local WorldSelect = MGE.WorldSelect
        if WorldSelect and WorldSelect.picking and WorldSelect.hover then
            drawObjectHighlight(WorldSelect.hover.id - 1, HOVER_COLOR)
        end
        for _, box in ipairs(boxes or {}) do drawPreviewBox(box) end
        for _, p in ipairs(anchors or {}) do drawAnchor(p[1], p[2], p[3]) end -- Generate's joints
    end)
    if not ok and not Highlight.errorShown then -- report once instead of spamming every frame
        Highlight.errorShown = true
        echo("[MGE] highlight error: " .. tostring(err))
    end
end)
