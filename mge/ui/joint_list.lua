-- Joints tab of the list area: all MGE.MAX_ENV_JOINTS joint slots (ids) in the object list's grid
-- (ui/obj_selector.lua), used slots bright, empty ones faint, selected ones pale. The game has no more
-- joints than that, so they always fit and the grid shows how full the mod is.
-- One slot is always selected, the current one (Main.jointSlot): a click makes a slot current and
-- selects only it, Shift + click adds / removes slots (the Properties tab edits all of them), Select
-- all (Ctrl + A) selects every joint or goes back to the current slot. An empty slot opens the Link tab
-- (ui/editor_link.lua), where its two objects are picked and Create makes the joint. New / Duplicate /
-- Delete like objects' (the bottom bar, Ctrl + N / D, Del). The selection is Main.selectedJoints (slot
-- ids, empty ones too), the highlight shows the selected joints' anchors and the objects they link
-- (utils/highlight.lua)

local joint_list = {}
MGE.JointList = joint_list -- the shortcuts (main.lua) use its New / Duplicate / Delete

local Main = MGE.Main
local ModData = MGE.ModData
local Joints = MGE.Joints
local ScrollList = MGE.ScrollList
local Widgets = MGE.Widgets

---@class JointSlot
---@field id integer
---@field joint FileParserEnvObjJoint? nil for an empty slot

---@return JointSlot[] every slot in id order
local function slots()
    local list = {}
    for id = 1, MGE.MAX_ENV_JOINTS do list[id] = { id = id, joint = Joints.find(id) } end
    return list
end

---@return boolean every joint is selected (false without joints)
local function allSelected()
    local joints = ModData.parsed.env_obj_joint
    if #joints == 0 then return false end
    for _, joint in ipairs(joints) do
        if not Main.selectedJoints[joint.id] then return false end
    end
    return true
end

---New (Ctrl + N on the Joints list): selects the lowest empty slot on the Link tab. Objects selected
---on the Objects list are picked already (one or two of them, Create then makes the joint)
function joint_list.newJoint()
    local id = Joints.nextId()
    if not id then
        Joints.haveRoom(1) -- prints that the joints are full
        return
    end
    Main.selectJointsOnly({ id })
    Joints.resetDraft()
    local draft = Joints.editDraft(id)
    local objects = ModData.getSelected()
    if #objects >= 1 and #objects <= 2 then
        draft.obj1 = objects[1].id
        draft.obj2 = objects[2] and objects[2].id or nil
    end
    Main.setTab("jointLink")
    Main.updateWindow()
end

---Duplicate (Ctrl + D on the Joints list): copies of the selected joints in the lowest empty slots, selected
function joint_list.duplicate()
    local ids = Joints.duplicate(Main.selectedJoints)
    if ids then Main.selectJointsOnly(ids) end
end

---Delete (Del on the Joints list, the Link tab): asks first, like objects. The slots stay selected, now
---empty: the Link tab can link them again
function joint_list.deleteSelected()
    local joints = Main.selectedJointList()
    local count = #joints
    if count == 0 or (MGE.confirmOverlay and not MGE.confirmOverlay.destroyed) then return end
    local message = "Delete " .. (count == 1 and "joint " .. joints[1].id or count .. " selected joints") ..
        "?\nUndo can bring them back."
    MGE.confirmOverlay = TBMenu:showConfirmationWindow(message, function()
        MGE.confirmOverlay = nil
        Joints.resetDraft()
        Joints.remove(Main.selectedJoints)
    end, function()
        MGE.confirmOverlay = nil
    end)
end

---@param view UIElement list area, emptied by the caller
function joint_list.create(view)
    local toReload = view:addChild({
        pos = { 0, 0 },
        size = { view.size.w, view.size.h },
    })
    -- the object list's bottom bar, same icons and order: Select all, New, Duplicate, Delete (no
    -- Import / Export: joints come with the objects they link)
    local barH = ScrollList.rowHeight
    local botBar = toReload:addChild({
        pos = { 0, -barH },
        size = { view.size.w, barH },
        bgColor = Widgets.TAB_PANEL_SOLID, -- list bars match the tab panel they sit in
        interactive = true,
    })
    local barIcons = Widgets.barButtons(botBar, {
        { label = "Select all joints, or only the current slot (Ctrl + A)", icon = MGE.scriptPath .. "textures/selectall.tga", wide = true,
            onClick = function() Main.toggleSelectAllJoints() end },
        { label = "New joint (Ctrl + N): the lowest empty slot\non the Link tab. 1 or 2 objects selected on\nthe Objects list are picked already",
            icon = "../textures/menu/general/buttons/addsign.tga", wide = true, onClick = joint_list.newJoint },
        { label = "Duplicate selected joints (Ctrl + D)", icon = MGE.scriptPath .. "textures/duplicate.tga", wide = true,
            onClick = joint_list.duplicate },
        -- last, away from the others
        { label = "Delete selected joints (Del)", icon = "../textures/menu/general/buttons/trash.tga", wide = true,
            onClick = joint_list.deleteSelected }, -- asks first
    })
    -- lit while every joint is selected, like the object list's (after the hover popup, same slot)
    local selectAllButton = barIcons[1] --[[@as UIElement]]
    Widgets.addDrawBefore(selectAllButton, function()
        selectAllButton.bgColor = allSelected() and TB_MENU_DEFAULT_LIGHTER_COLOR or Widgets.STYLE.bg
    end)

    MGE.ObjSelector.grid(view, { x = 0, y = 0, w = view.size.w, h = view.size.h - barH }, slots(), {
        label = function(slot) return tostring(slot.id) end,
        isSelected = function(slot) return Main.selectedJoints[slot.id] end,
        isDimmed = function(slot) return slot.joint == nil end,
        onClick = function(slot, additive) Main.selectJoint(slot.id, additive) end,
        popup = function(slot)
            if not slot.joint then return "Joint " .. slot.id .. ": empty, link 2 objects on the Link tab" end
            return "Joint " .. slot.id .. ": objects " .. tostring(slot.joint.obj1) .. " and " .. tostring(slot.joint.obj2)
        end,
    }, toReload)
end

return joint_list
