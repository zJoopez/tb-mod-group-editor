

















local Rows = MGE.EditorRows
local Widgets = MGE.Widgets
local Joints = MGE.Joints
local ModData = MGE.ModData

local ROW_H = MGE.Widgets.ROW_H


local restyleGrid = nil



local gridPage = 1


Joints.onDraftChanged = function()
    Rows.refreshBlocks({ "jointLinkButtons" })
    if restyleGrid then restyleGrid() end
end





local function makesPair(slot, draft)
    return not Joints.find(slot) and not draft.obj1
end





local function pairText(a, b)
    return tostring(a or "-") .. " and " .. tostring(b or "-")
end



local function selectedSlots()
    local slots = {}
    for id in pairs(MGE.Main.selectedJoints) do table.insert(slots, id) end
    table.sort(slots)
    return slots
end



local function anyJoint(slots)
    for _, id in ipairs(slots) do
        if Joints.find(id) then return true end
    end
    return false
end





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





local function commit(slot)
    local slots = selectedSlots()
    local draft = Joints.draftFor(slot)
    local state = Joints.draftState(slot, slots)
    local creating = not anyJoint(slots)
    if makesPair(slot, draft) then
        if MGE.Assets.newPair(slot) then
            Joints.resetDraft()
            MGE.Main.setTab("joint")
        end
    elseif state == "incomplete" then
        MGE.say("pick 2 objects first")
    elseif state == "unchanged" then
        MGE.say("" .. (#slots > 1 and "the selected joints already link" or "joint " .. slot .. " already links")
            .. " those objects")
    elseif Joints.commitDraft(slot, slots) then
        MGE.Main.followJoints()
        if creating then MGE.Main.setTab("joint") end
    end
end




local function buildButtons(holder)
    Rows.begin()
    local slot, slots = MGE.Main.selectedSlot(), selectedSlots()
    local draft, state = Joints.draftFor(slot), Joints.draftState(slot, slots)

    local function buttonsAt(index, items)
        local row = holder:addChild({ pos = { Widgets.INSET, index * ROW_H + Widgets.INSET },
            size = { holder.size.w - Widgets.INSET * 2, ROW_H - Widgets.INSET * 2 } })
        return Widgets.buttonRow(row, 0, row.size.h, items, Widgets.GAP, nil, Widgets.PANEL_STYLE)
    end
    local pick = buttonsAt(0, {
        { label = "Pick from world", onClick = function()
            Joints.worldPick = not Joints.worldPick
            if not Joints.worldPick then MGE.WorldSelect.hover = nil end
            Rows.refreshBlocks({ "jointLinkButtons" })
        end },
    })[1]
    Rows.setHighlighted(pick, Joints.worldPick)
    Widgets.popupBelow(pick, "Pick the joint's 2 objects in the list, or in the\n" ..
        "world while this is lit. Click a picked one to unpick.\n" ..
        "Off: a world click selects the object on the Objects list.")

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


return {
    blocks = {
        { name = "jointLinkGrid", build = buildGrid, panel = "jointLink", row = 0, rows = 7 },
        { name = "jointLinkButtons", build = buildButtons, panel = "jointLink", row = 7, rows = 2 },
    },
}
