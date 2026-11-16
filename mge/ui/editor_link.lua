-- Joints list's Link tab: which two objects the current joint slot (Main.jointSlot, always one) links.
-- Clicks only change a draft (Joints.draft, utils/joints.lua): a click on an object in the grid, or in
-- the world while Pick from world is on (Joints.worldPick, utils/world_select.lua), picks it, a click on a
-- picked one takes it out, at most two. Off, a world click selects the object on the Objects list. Which
-- one is first doesn't matter to the game. Nothing changes in the mod until Create (an empty slot) or
-- Update (a joint's new objects), so a stray click can't rewire a joint.
--   rows 0-6: every object, picked ones pale, static ones faint, on pages when there are more than
--             fit. Linking one above id MAX_NONSTATIC_OBJECTS reindexes it down (Joints.linkSlots)
--                                                                               (block jointLinkGrid)
--   row 7:    Pick from world (its popup is the tab's help)
--   row 8:    Reset (the saved link; Delete is in the list's bar), Create / Update: its popup says what
--             it would do. Create with nothing picked makes two default objects joined in the slot
--                                                                     (rows 7-8: block jointLinkButtons)
-- A pick only rebuilds the buttons, the grid restyles its cells in place: rebuilding it would scroll it
-- back to the top. Selecting another slot rebuilds both.
-- Has its own buttons (Reset: the draft back to the saved link).
-- Like the Properties tab, a click on a joint's anchor selects that joint (it becomes the current
-- slot) and the Move gizmo drags the selected joints' anchors: those come before picking objects

local Rows = MGE.EditorRows
local Widgets = MGE.Widgets
local Joints = MGE.Joints
local ModData = MGE.ModData

local ROW_H = MGE.Widgets.ROW_H

---@type fun()? restyles the grid's cells from the current draft (ObjSelector.grid), set by its build
local restyleGrid = nil
-- the grid's page when there are more objects than fit: pages, not scrolling. A scrolled list shows
-- rows half out of its area and needs bars drawn over them, here those would cover the heading and
-- the Create / Reset row (objects spilled over them in a big mod: a converted map)
local gridPage = 1

-- a click in the grid or the world changed the draft: only this tab shows it (no reload, nothing saved)
Joints.onDraftChanged = function()
    Rows.refreshBlocks({ "jointLinkButtons" })
    if restyleGrid then restyleGrid() end
end

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

---The selected slots, in id order: Create / Update links all of them to the current slot's draft
---@return integer[]
local function selectedSlots()
    local slots = {}
    for id in pairs(MGE.Main.selectedJoints) do table.insert(slots, id) end
    table.sort(slots)
    return slots
end

---@param slots integer[]
---@return boolean any of them is a joint already (the button reads Update, not Create)
local function anyJoint(slots)
    for _, id in ipairs(slots) do
        if Joints.find(id) then return true end
    end
    return false
end

---What Create / Update would do with the current slot's draft, for its button's popup
---@param slot integer
---@param slots integer[] the selected slots
---@return string
local function statusText(slot, slots)
    local draft, state = Joints.draftFor(slot), Joints.draftState(slot, slots)
    local many = #slots > 1
    local joint = Joints.find(slot)
    local pair = pairText(draft.obj1, draft.obj2)
    if makesPair(slot, draft) then
        return "Nothing picked: two new default objects side\nby side, joined, in front of the camera"
    elseif (state == "new" or state == "changed") and many then
        return "Links all " .. #slots .. " joints to objects " .. pair
    elseif state == "new" then
        return "Joint " .. slot .. ": joins objects " .. pair
    elseif state == "changed" and joint then
        return "Joint " .. slot .. ": links " .. pair .. " (now " .. pairText(joint.obj1, joint.obj2) .. ")"
    elseif state == "unchanged" then
        return (many and "All of them link objects " or "Joint " .. slot .. " links objects ") .. pair
    elseif draft.obj1 then
        return "Picked " .. draft.obj1 .. ", pick one more"
    end
    return "Pick 2 objects"
end

---Every object, a click picks or unpicks one. Picked ones read from the draft on every restyle (the
---draft is replaced when it's first edited, see Joints.editDraft). The same list as the Objects list
---(ui/obj_selector.lua): its columns, Main.pageSize objects a page with the pager above only when there's
---more than one page, it scrolls. Picks are kept across pages
---@param holder UIElement
local function buildGrid(holder)
    restyleGrid = nil
    local slot = MGE.Main.selectedSlot()
    local objects = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do table.insert(objects, obj) end
    table.sort(objects, function(a, b) return a.id < b.id end)
    local rect = { x = 0, y = 0, w = holder.size.w, h = holder.size.h }
    if #objects == 0 then
        local empty = holder:addChild({ pos = { rect.x, rect.y }, size = { rect.w, rect.h } })
        empty:addAdaptedText("Mod has no objects\nLinking needs 2", nil, nil, MGE.Widgets.FONT, CENTERMID, MGE.Widgets.TEXT_SCALE_SMALL, nil, nil)
        return
    end
    local ScrollList = MGE.ScrollList
    local rowH = ScrollList.rowHeight
    local pageCount
    objects, gridPage, pageCount = ScrollList.paginate(objects, gridPage, MGE.Main.pageSize)
    if pageCount > 1 then
        local pagerRow = holder:addChild({ pos = { 0, 0 }, size = { holder.size.w, rowH } })
        ScrollList.createPager(pagerRow, { x = 0, y = 0, w = holder.size.w, h = rowH }, gridPage, pageCount,
            function(page)
                gridPage = page
                Rows.refreshBlocks({ "jointLinkGrid" })
            end)
        rect.y = rowH
    end
    -- as tall as the Objects list (Main.LIST_ROWS rows, the pager's one of them), within the block
    local listH = math.min(MGE.Main.LIST_ROWS * rowH, math.floor(holder.size.h / rowH) * rowH)
    rect.h = listH - rect.y
    local max = MGE.MAX_NONSTATIC_OBJECTS
    restyleGrid = MGE.ObjSelector.grid(holder, rect, objects, {
        label = function(obj) return tostring(obj.id) end,
        isSelected = function(obj) return Joints.draftHas(Joints.draftFor(slot), obj.id) end,
        isDimmed = function(obj) return ModData.isStatic(obj, true) end,
        onClick = function(obj) Joints.offerDraft(slot, obj.id) end,
        popup = function(obj)
            return "Object " .. obj.id .. (ModData.isStatic(obj, true) and " (static)" or "") ..
                (obj.id > max and "\nAbove id " .. max .. ": linking it reindexes it down" or "")
        end,
    })
end

---Create / Update: every selected slot gets the draft's link (Joints.commitDraft), or with nothing
---picked in an empty current slot two new default objects joined there, in front of the camera. New
---joints show the Properties tab next. Camera follow then frames the linked objects (Main.followJoints)
---@param slot integer
local function commit(slot)
    local slots = selectedSlots()
    local draft = Joints.draftFor(slot)
    local state = Joints.draftState(slot, slots)
    local creating = not anyJoint(slots)
    if makesPair(slot, draft) then
        if MGE.Assets.newPair(slot) then
            Joints.resetDraft()
            MGE.Main.setTab("joint") -- next: its values
        end
    elseif state == "incomplete" then
        MGE.say("pick 2 objects first")
    elseif state == "unchanged" then
        MGE.say("" .. (#slots > 1 and "the selected joints already link" or "joint " .. slot .. " already links")
            .. " those objects")
    elseif Joints.commitDraft(slot, slots) then
        MGE.Main.followJoints() -- camera follow frames the linked objects, like selecting the joint does
        if creating then MGE.Main.setTab("joint") end
    end
end

---The last two rows: Pick from world (lit while on), then Reset and Create / Update (lit when it would do
---something, its popup says what)
---@param holder UIElement
local function buildButtons(holder)
    Rows.begin()
    local slot, slots = MGE.Main.selectedSlot(), selectedSlots()
    local draft, state = Joints.draftFor(slot), Joints.draftState(slot, slots)
    ---A full-width row of buttons, inset like the number fields
    local function buttonsAt(index, items)
        local row = holder:addChild({ pos = { Widgets.INSET, index * ROW_H + Widgets.INSET },
            size = { holder.size.w - Widgets.INSET * 2, ROW_H - Widgets.INSET * 2 } })
        return Widgets.buttonRow(row, 0, row.size.h, items, Widgets.GAP, nil, Widgets.PANEL_STYLE)
    end
    local pick = buttonsAt(0, {
        { label = "Pick from world", onClick = function()
            Joints.worldPick = not Joints.worldPick
            if not Joints.worldPick then MGE.WorldSelect.hover = nil end -- no object lit as pickable
            Rows.refreshBlocks({ "jointLinkButtons" })
        end },
    })[1]
    Rows.setHighlighted(pick, Joints.worldPick)
    Widgets.popupBelow(pick, "Pick the joint's 2 objects in the list, or in the\n" ..
        "world while this is lit. Click a picked one to unpick.\n" ..
        "Off: a world click selects the object on the Objects list.")
    -- Reset on the left like the other backing-out buttons
    local buttons = buttonsAt(1, {
        { label = "Reset", onClick = function()
            Joints.worldPick = false
            Joints.resetDraft()
            Joints.onDraftChanged()
        end },
        { label = anyJoint(slots) and "Update" or "Create", onClick = function()
            Joints.worldPick = false
            commit(slot)
        end },
    })
    Rows.setHighlighted(buttons[2], state == "new" or state == "changed" or makesPair(slot, draft))
    Widgets.popupBelow(buttons[2], statusText(slot, slots))
end

---@type EditorPanelModule
return {
    blocks = {
        { name = "jointLinkGrid", build = buildGrid, panel = "jointLink", row = 0, rows = 7 },
        { name = "jointLinkButtons", build = buildButtons, panel = "jointLink", row = 7, rows = 2 },
    },
}
