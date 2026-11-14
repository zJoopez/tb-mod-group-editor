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
    -- draws a frame MGE has for itself next to the game's 256 objects and the atmo's 256: the Generate
    -- preview first, then the selection highlights fit in what's left (highlightPlan)
    drawRoom = 256,
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

-- drawBox's rotations by frame table: the boxes drawn every frame (the map placement view's up to
-- MapPlace.maxDraws, atmo ghosts) keep their frames, so each is converted once instead of making two
-- tables per box per frame. Frames are never changed in place (Mat3 makes new ones); weak keys let
-- dropped boxes go
local rotCache = setmetatable({}, { __mode = "k" })

---Box that isn't an object: translucent fill, and an outline (a negative-size pass) unless outline is
---false. fillAlpha 0 draws only the outline
---@param box HighlightBox
---@param color number[]
---@param fillAlpha number
---@param outline boolean?
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

---An atmo object's own color, r g b a in 0-1 (atmo colors go up to 2: brighter, drawn as 1)
---@param obj FileParserEnvObj
---@return number[]
local function colorOf(obj)
    local c = {}
    for n in tostring(obj.props.color or "1 1 1 1"):gmatch("%S+") do c[#c + 1] = tonumber(n) or 1 end
    for k = 1, 4 do c[k] = math.min(math.max(c[k] or 1, 0), 1) end
    return c
end

---One atmo object's shape in a color: a box through drawBox (outline when asked), spheres and pills filled
---@param g AtmoGhost
---@param c number[]
---@param alpha number
---@param outline boolean
local function drawGhost(g, c, alpha, outline)
    local p, s = g.pos, g.sides
    if g.shape == "box" then
        Highlight.drawBox(g, c, alpha, outline)
        return
    end
    local rot = rotCache[g.frame] -- like drawBox: the ghost keeps its frame
    if not rot then
        rot = toMatrixTB(g.frame)
        rotCache[g.frame] = rot
    end
    set_color(c[1], c[2], c[3], alpha)
    if g.shape == "sphere" then
        draw_sphere_m(p[1], p[2], p[3], s[1], rot)
    else -- pill: x radius, y length
        draw_capsule_m(p[1], p[2], p[3], s[2], s[1], rot)
    end
end

---The selection highlight on a shape: a translucent fill slightly larger than it, then a bigger
---inverted shell that reads as an outline (2 draws). fillOnly: the fill alone (1 draw), when the
---full one doesn't fit the frame's draws for every selected one. An outline alone, just around the
---shape, would stay hidden behind its own (often opaque) fill
---@param shape "box"|"sphere"|"pill"
---@param x number
---@param y number
---@param z number
---@param sx number box x side, sphere and pill radius
---@param sy number box y side, pill length
---@param sz number box z side
---@param rot MatrixTB?
---@param color number[]
---@param fillOnly boolean?
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
    else -- pill
        draw_capsule_m(x, y, z, sy + 0.01, sx + 0.01, rot)
        if fillOnly then return end
        set_color(c[1], c[2], c[3], 1.0)
        draw_capsule_m(x, y, z, -(sy + 0.02), -(sx + 0.02), rot)
    end
end

---A selected atmo object's highlight, the same as objects get
---@param g AtmoGhost
---@param fillOnly boolean?
local function drawAtmoHighlight(g, fillOnly)
    local p, s = g.pos, g.sides
    local rot = rotCache[g.frame]
    if not rot then
        rot = toMatrixTB(g.frame)
        rotCache[g.frame] = rot
    end
    local shape = g.shape == "cylinder" and "pill" or g.shape
    drawShapeHighlight(shape, p[1], p[2], p[3], s[1], s[2], s[3], rot, Highlight.color, fillOnly)
end

---Atmo objects (utils/atmo_layer.lua): not in the game, MGE draws them, every one. The atmo's size
---(AtmoLayer.maxAtmo, 256) has its own share of the shapes the game draws a frame: 256 objects, 256
---atmo objects and 256 for the rest (Highlight.drawRoom: the Generate preview first, highlights)
--- full false (Objects list): translucent ghosts in AtmoLayer.color
--- full true (the Atmo list): in their own color, the selected ones where a gizmo drag has them
---   (AtmoLayer.liveCopies)
---@param full boolean
---@return AtmoGhost[] selected the Atmo list's selected ones, for their highlights (drawn after)
local function drawAtmo(full)
    local AtmoLayer = MGE.AtmoLayer
    local list = ModData.parsed.atmo or {}
    local selected = {}
    if not full then
        for _, obj in ipairs(list) do
            local g = AtmoLayer.ghost(obj)
            if g then drawGhost(g, AtmoLayer.color, AtmoLayer.alpha, false) end
        end
        return selected
    end
    local copies = AtmoLayer.liveCopies()
    for _, atmoObj in ipairs(list) do
        local obj = copies and copies[atmoObj] or atmoObj
        local g = AtmoLayer.ghost(obj)
        if g then
            local c = colorOf(obj)
            drawGhost(g, c, c[4], false)
            if obj.selected then selected[#selected + 1] = g end
        end
    end
    return selected
end

---The object highlight (drawShapeHighlight) on a game object, read from the game
---@param id integer 0-based object id
---@param color number[]? defaults to Highlight.color
---@param fillOnly boolean?
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

---How the selection highlights fit in what's left of the frame's draws: full ones (2 draws each)
---when all of them fit, else the fill alone (1 draw) on as many as fit
---@param count integer selected shapes
---@param room integer draws left
---@return boolean fillOnly
---@return integer drawn how many get one
local function highlightPlan(count, room)
    room = math.max(0, room)
    if count * 2 <= room then return false, count end
    return true, math.min(count, room)
end
Highlight.highlightPlan = highlightPlan -- tests

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
        -- the game draws only so many shapes a frame: the Generate preview first, then the atmo (its own
        -- share), then the selection highlights in what's left of Highlight.drawRoom. Selecting every
        -- object then thins the highlights to fills instead of pushing the atmo out
        local room = Highlight.drawRoom
        for _, box in ipairs(boxes or {}) do drawPreviewBox(box) end
        for _, p in ipairs(anchors or {}) do drawAnchor(p[1], p[2], p[3]) end -- Generate's joints
        room = room - #(boxes or {}) * 2 - #(anchors or {}) * 2
        local atmo = Main.listTab == "atmo"
        local selectedGhosts = drawAtmo(atmo)
        -- a pick in progress (the Core tab's color picker): the object a click would take, in white
        local WorldSelect = MGE.WorldSelect
        if WorldSelect and WorldSelect.picking and WorldSelect.hover then
            drawObjectHighlight(WorldSelect.hover.id - 1, HOVER_COLOR)
            room = room - 2
        end
        if atmo then -- the Atmo list shows the atmo selection, not the objects'
            local fillOnly, drawn = highlightPlan(#selectedGhosts, room)
            for i = 1, drawn do drawAtmoHighlight(selectedGhosts[i], fillOnly) end
        else
            local ids = {}
            for _, obj in ipairs(ModData.parsed.env_obj) do
                if obj.selected then ids[#ids + 1] = obj.id - 1 end
            end
            local fillOnly, drawn = highlightPlan(#ids, room)
            for i = 1, drawn do drawObjectHighlight(ids[i], nil, fillOnly) end
        end
    end)
    if not ok and not Highlight.errorShown then -- report once instead of spamming every frame
        Highlight.errorShown = true
        echo("[MGE] highlight error: " .. tostring(err))
    end
end)
