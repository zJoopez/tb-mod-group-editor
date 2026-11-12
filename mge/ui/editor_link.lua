-- Joints list's Link tab: which two objects the current joint slot (Main.jointSlot, always one) links.
-- Clicks only change a draft (Joints.draft, utils/joints.lua): a click on an object in the grid or in
-- the world (utils/world_select.lua) picks it, a click on a picked one takes it out, at most two. Which
-- one is first doesn't matter to the game. Nothing changes in the mod until Create (an empty slot) or
-- Update (a joint's new objects), so a stray click can't rewire a joint.
--   row 0:    the slot and what the draft would do                             (block jointLinkHead)
--   rows 1-6: every object, picked ones pale, static ones faint, on pages when there are more than
--             fit. Linking one above id MAX_NONSTATIC_OBJECTS reindexes it down (Joints.linkSlots)
--                                                                               (block jointLinkGrid)
--   row 7:    Create / Update, Reset (the saved link; Delete is in the list's bar). Create with nothing
--             picked makes two default objects joined in the slot              (block jointLinkButtons)
-- A pick only rebuilds the heading and the buttons, the grid restyles its cells in place: rebuilding it
-- would scroll it back to the top. Selecting another slot rebuilds all three.
-- Has its own buttons instead of the editor's Reset inputs footer (PANELS in ui/editor.lua).
-- Like the Properties tab, a click on a joint's anchor selects that joint (it becomes the current
-- slot) and the Move gizmo drags the selected joints' anchors: those come before picking objects

local Rows = MGE.EditorRows
local Widgets = MGE.Widgets
local Joints = MGE.Joints
local ModData = MGE.ModData

local ROW_H = 30
local GRID_COLUMNS = 8

---@type fun()? restyles the grid's cells from the current draft (ObjSelector.grid), set by its build
local restyleGrid = nil
-- the grid's page when there are more objects than fit: pages, not scrolling. A scrolled list shows
-- rows half out of its area and needs bars drawn over them, here those would cover the heading and
-- the Create / Reset row (objects spilled over them in a big mod: a converted map)
local gridPage = 1

-- a click in the grid or the world changed the draft: only this tab shows it (no reload, nothing saved)
Joints.onDraftChanged = function()
    Rows.refreshBlocks({ "jointLinkHead", "jointLinkButtons" })
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

---First row: the slot (or how many are selected) and what Create / Update would do
---@param holder UIElement
local function buildHeading(holder)
    Rows.begin()
    local slot, slots = MGE.Main.selectedSlot(), selectedSlots()
    local draft, state = Joints.draftFor(slot), Joints.draftState(slot, slots)
    local many = #slots > 1
    local row, x, w = Rows.createRow(many and #slots .. " joints" or "Joint " .. slot, holder,
        "Click two objects in the list below or in the world.\n" ..
        "A click on a picked one takes it out. Nothing changes\n" ..
        "until Create / Update, Reset goes back to the saved\n" ..
        "link. With several joints selected Update links them\n" ..
        "all, empty slots too. An object above id " .. MGE.MAX_NONSTATIC_OBJECTS .. " is\n" ..
        "reindexed down when linked, the game joins only those.")
    local joint = Joints.find(slot)
    local pair = pairText(draft.obj1, draft.obj2)
    local text
    if (state == "new" or state == "changed") and many then
        text = "Link all " .. #slots .. " to " .. pair
    elseif state == "new" then
        text = "Create joins " .. pair
    elseif state == "changed" and joint then
        text = "Update to " .. pair .. " (now " .. pairText(joint.obj1, joint.obj2) .. ")"
    elseif state == "unchanged" then
        text = (many and "All link objects " or "Links objects ") .. pair
    elseif draft.obj1 then
        text = "Picked " .. draft.obj1 .. ", pick one more"
    else
        text = joint and "Pick 2 objects" or "Empty: pick 2 objects, or Create 2 new ones"
    end
    local textHolder = row:addChild({ pos = { x + 4, 0 }, size = { w - 8, row.size.h } })
    textHolder:addAdaptedText(text, nil, nil, nil, LEFTMID, 0.65, nil, nil)
end

---Every object, a click picks or unpicks one. Picked ones read from the draft on every restyle (the
---draft is replaced when it's first edited, see Joints.editDraft). As many rows as fit the block
---(7: 56 objects), more objects go on pages with a pager under them, picks are kept across pages
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
        empty:addAdaptedText("No objects: Create 2 new ones", nil, nil, nil, CENTERMID, 0.65, nil, nil)
        return
    end
    local ScrollList = MGE.ScrollList
    local rowH = ScrollList.rowHeight
    local rows = math.floor(holder.size.h / rowH)
    if #objects > rows * GRID_COLUMNS then
        rows = math.floor((holder.size.h - rowH) / rowH) -- one row for the pager
        local pageCount
        objects, gridPage, pageCount = ScrollList.paginate(objects, gridPage, rows * GRID_COLUMNS)
        ScrollList.createPager(holder, { x = 0, y = rows * rowH, w = holder.size.w, h = rowH }, gridPage, pageCount,
            function(page)
                gridPage = page
                Rows.refreshBlocks({ "jointLinkGrid" })
            end)
    end
    rect.h = rows * rowH -- whole rows only: nothing scrolls, nothing shows outside the block
    local max = MGE.MAX_NONSTATIC_OBJECTS
    restyleGrid = MGE.ObjSelector.grid(holder, rect, objects, {
        columns = GRID_COLUMNS,
        label = function(obj) return tostring(obj.id) end,
        isSelected = function(obj) return Joints.draftHas(Joints.draftFor(slot), obj.id) end,
        isDimmed = function(obj) return ModData.isStatic(obj, true) end,
        onClick = function(obj) Joints.offerDraft(slot, obj.id) end,
        popup = function(obj)
            return "Object " .. obj.id .. (ModData.isStatic(obj, true) and " (static)" or "") ..
                (obj.id > max and "\nAbove id " .. max .. ": linking it reindexes it down" or "")
        end,
    }, holder)
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
        echo("^04[MGE] pick 2 objects first")
    elseif state == "unchanged" then
        echo("^04[MGE] " .. (#slots > 1 and "the selected joints already link" or "joint " .. slot .. " already links")
            .. " those objects")
    elseif Joints.commitDraft(slot, slots) then
        MGE.Main.followJoints() -- camera follow frames the linked objects, like selecting the joint does
        if creating then MGE.Main.setTab("joint") end
    end
end

---Last row: Create / Update (lit when it would do something), Reset
---@param holder UIElement
local function buildButtons(holder)
    Rows.begin()
    local slot, slots = MGE.Main.selectedSlot(), selectedSlots()
    local draft, state = Joints.draftFor(slot), Joints.draftState(slot, slots)
    local row = holder:addChild({ pos = { 0, 2 }, size = { holder.size.w, ROW_H - 4 } })
    local buttons = Widgets.buttonRow(row, 0, row.size.h, {
        { label = anyJoint(slots) and "Update" or "Create", onClick = function() commit(slot) end },
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

---@type EditorPanelModule
return {
    blocks = {
        { name = "jointLinkHead", build = buildHeading, panel = "jointLink", row = 0, rows = 1 },
        { name = "jointLinkGrid", build = buildGrid, panel = "jointLink", row = 1, rows = 6 },
        { name = "jointLinkButtons", build = buildButtons, panel = "jointLink", row = 7, rows = 1 },
    },
}
