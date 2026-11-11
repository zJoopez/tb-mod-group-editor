-- Joints list's Link tab: which two objects the current joint slot (Main.jointSlot, always one) links.
-- Clicks only change a draft (Joints.draft, utils/joints.lua): a click on an object in the grid or in
-- the world (utils/world_select.lua) picks it, a click on a picked one takes it out, at most two. Which
-- one is first doesn't matter to the game. Nothing changes in the mod until Create (an empty slot) or
-- Update (a joint's new objects), so a stray click can't rewire a joint.
--   row 0:    the slot and what the draft would do
--   rows 1-6: objects 1-MAX_NONSTATIC_OBJECTS (the ones the game joins), picked ones pale. Higher ids
--             can be clicked in the world (Reindex moves them down)
--   row 7:    Create / Update, Reset (the saved link; Delete is in the list's bar). Create with nothing picked makes two
--             default objects joined in the slot
-- Has its own buttons instead of the editor's Reset inputs footer (PANELS in ui/editor.lua).
-- Like the Properties tab, a click on a joint's anchor selects that joint (it becomes the current
-- slot) and the Move gizmo drags the selected joints' anchors: those come before picking objects

local Rows = MGE.EditorRows
local Widgets = MGE.Widgets
local Joints = MGE.Joints
local ModData = MGE.ModData

local ROWS = 8 -- the panel's height in rows (PANELS in ui/editor.lua)
local ROW_H = 30
local GRID_ROWS = 6 -- panel rows the object grid takes, rows 1-6
local GRID_COLUMNS = 8 -- 48 objects in 6 grid rows, no scrolling

-- a click in the grid or the world changed the draft: only this tab shows it (no reload, nothing saved)
Joints.onDraftChanged = function() Rows.refreshBlocks({ "jointLink" }) end

---Create with nothing picked in an empty slot: two new default objects joined there
---@param slot integer
---@param draft JointDraft
---@return boolean
local function makesPair(slot, draft)
    return not Joints.find(slot) and not draft.obj1
end

---"3 and 5", the picked objects of a draft or a joint
---@param a integer?
---@param b integer?
---@return string
local function pairText(a, b)
    return tostring(a or "-") .. " and " .. tostring(b or "-")
end

---First row: the slot and what Create / Update would do
---@param holder UIElement
---@param slot integer
---@param draft JointDraft
---@param state string Joints.draftState
local function buildHeading(holder, slot, draft, state)
    local row, x, w = Rows.createRow("Joint " .. slot, holder,
        "Click two objects in the list below or in the world.\n" ..
        "A click on a picked one takes it out. Nothing changes\n" ..
        "until Create / Update, Reset goes back to the saved\n" ..
        "link. Objects above id " .. MGE.MAX_NONSTATIC_OBJECTS .. " aren't joined by the game.")
    local joint = Joints.find(slot)
    local text
    if state == "new" then
        text = "Create joins " .. pairText(draft.obj1, draft.obj2)
    elseif state == "changed" and joint then
        text = "Update to " .. pairText(draft.obj1, draft.obj2) .. " (now " .. pairText(joint.obj1, joint.obj2) .. ")"
    elseif state == "unchanged" then
        text = "Links objects " .. pairText(draft.obj1, draft.obj2)
    elseif draft.obj1 then
        text = "Picked " .. draft.obj1 .. ", pick one more"
    else
        text = joint and "Pick 2 objects" or "Empty: pick 2 objects, or Create 2 new ones"
    end
    local textHolder = row:addChild({ pos = { x + 4, 0 }, size = { w - 8, row.size.h } })
    textHolder:addAdaptedText(text, nil, nil, nil, LEFTMID, 0.65, nil, nil)
end

---Objects the game joins, a click picks or unpicks one
---@param holder UIElement
---@param slot integer
---@param draft JointDraft
local function buildGrid(holder, slot, draft)
    local objects = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.id <= MGE.MAX_NONSTATIC_OBJECTS then table.insert(objects, obj) end
    end
    table.sort(objects, function(a, b) return a.id < b.id end)
    local rect = { x = 0, y = ROW_H, w = holder.size.w, h = GRID_ROWS * ROW_H }
    if #objects == 0 then
        local empty = holder:addChild({ pos = { rect.x, rect.y }, size = { rect.w, rect.h } })
        empty:addAdaptedText("No objects with ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS ..
            ": click them in the world, or Create 2 new ones", nil, nil, nil, CENTERMID, 0.65, nil, nil)
        return
    end
    MGE.ObjSelector.grid(holder, rect, objects, {
        columns = GRID_COLUMNS,
        label = function(obj) return tostring(obj.id) end,
        isSelected = function(obj) return Joints.draftHas(draft, obj.id) end,
        isDimmed = function(obj) return ModData.isStatic(obj, true) end,
        onClick = function(obj) Joints.offerDraft(slot, obj.id) end,
        popup = function(obj) return "Object " .. obj.id .. (ModData.isStatic(obj, true) and " (static)" or "") end,
    }, holder)
end

---Create / Update: the draft's link, or with nothing picked in an empty slot two new default objects
---joined there, in front of the camera. A new joint shows the Properties tab next
---@param slot integer
local function commit(slot)
    local draft = Joints.draftFor(slot)
    local state = Joints.draftState(slot)
    if makesPair(slot, draft) then
        if MGE.Assets.newPair(slot) then
            Joints.resetDraft()
            MGE.Main.setTab("joint") -- next: its values
        end
    elseif state == "incomplete" then
        echo("^04[MGE] pick 2 objects first")
    elseif state == "unchanged" then
        echo("^04[MGE] joint " .. slot .. " already links those objects")
    elseif Joints.commitDraft(slot) and state == "new" then
        MGE.Main.setTab("joint")
    end
end

---Last row: Create / Update (lit when it would do something), Reset
---@param holder UIElement
---@param slot integer
---@param draft JointDraft
---@param state string Joints.draftState
local function buildButtons(holder, slot, draft, state)
    local joint = Joints.find(slot)
    local row = holder:addChild({ pos = { 0, (ROWS - 1) * ROW_H + 2 }, size = { holder.size.w, ROW_H - 4 } })
    local buttons = Widgets.buttonRow(row, 0, row.size.h, {
        { label = joint and "Update" or "Create", onClick = function() commit(slot) end },
        { label = "Reset", onClick = function()
            Joints.resetDraft()
            Joints.onDraftChanged()
        end },
    }, 4, nil, Widgets.PANEL_STYLE)
    Rows.setHighlighted(buttons[1], state == "new" or state == "changed" or makesPair(slot, draft))
    if makesPair(slot, draft) then
        TBMenu:displayPopup(buttons[1], "Nothing picked: two new default objects side\nby side, joined, in front of the camera")
    end
end

---@param holder UIElement
local function buildLink(holder)
    Rows.begin()
    local slot = MGE.Main.selectedSlot()
    local draft = Joints.draftFor(slot)
    local state = Joints.draftState(slot)
    buildHeading(holder, slot, draft, state)
    buildGrid(holder, slot, draft)
    buildButtons(holder, slot, draft, state)
end

---@type EditorPanelModule
return {
    blocks = { { name = "jointLink", build = buildLink, panel = "jointLink", row = 0, rows = ROWS } },
}
