-- Helpers for env_obj_joint blocks linked to selected objects.
-- There is no API to move env joints live, changes are stored in props and applied when the mod is saved.

---@class Joints
local Joints = {}
MGE.Joints = Joints
local ModData = MGE.ModData

---@param value string?
---@return number, number, number
local function parseVector(value)
    local x, y, z = tostring(value or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
end

---@return string
local function formatVector(x, y, z)
    return MGE.FileHandler.formatNumbers(x, y, z)
end

---@param objects { id: integer }[]
---@return table<integer, boolean>
function Joints.idSet(objects)
    local set = {}
    for _, obj in ipairs(objects) do set[obj.id] = true end
    return set
end

---Joints whose both linked objects are in ids
---@param ids table<integer, boolean>
---@param joints FileParserEnvObjJoint[]?
---@return FileParserEnvObjJoint[]
function Joints.getLinked(ids, joints)
    local linked = {}
    for _, joint in ipairs(joints or ModData.parsed.env_obj_joint) do
        if ids[joint.obj1] and ids[joint.obj2] then
            table.insert(linked, joint)
        end
    end
    return linked
end

---Object ids that are linked to any joint in the list
---@param joints FileParserEnvObjJoint[]
---@return table<integer, boolean>
function Joints.getObjectIds(joints)
    local ids = {}
    for _, joint in ipairs(joints or {}) do
        ids[joint.obj1] = true
        ids[joint.obj2] = true
    end
    return ids
end

---Unused joint ids (1-MAX_ENV_JOINTS), lowest first
---@return integer[]
function Joints.freeIds()
    local used = {}
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        if joint.id then used[joint.id] = true end
    end
    local free = {}
    for id = 1, MGE.MAX_ENV_JOINTS do
        if not used[id] then table.insert(free, id) end
    end
    return free
end

---Lowest unused joint id, nil when all MAX_ENV_JOINTS ids are taken
---@return integer?
function Joints.nextId()
    return Joints.freeIds()[1]
end

---Number of joints that copyLinked would add (both ends in ids)
---@param joints FileParserEnvObjJoint[]
---@param ids table<integer, boolean>
---@return integer
function Joints.countLinked(joints, ids)
    return #Joints.getLinked(ids, joints)
end

---Prints a message and returns false if `count` more joints don't fit the joint limit
---@param count integer
---@return boolean
function Joints.haveRoom(count)
    local free = #Joints.freeIds()
    if count <= free then return true end
    print("Not enough joints available: " .. count .. " needed, " .. free .. " free (max " .. MGE.MAX_ENV_JOINTS .. ")")
    return false
end

---Copy of a joint with new ids, props are copied so edits don't affect the original
---@param joint FileParserEnvObjJoint
---@param id integer
---@param obj1 integer
---@param obj2 integer
---@return FileParserEnvObjJoint
function Joints.copy(joint, id, obj1, obj2)
    local props = {}
    for k, v in pairs(joint.props) do props[k] = v end
    return { kind = "env_obj_joint", id = id, obj1 = obj1, obj2 = obj2, props = props, lines = joint.lines }
end

---Copies joints linked between objects in idMap (old id -> new id) and adds them to the mod
---@param joints FileParserEnvObjJoint[]
---@param idMap table<integer, integer>
---@param jointIds integer[]? ids for the copies in order (a slot picked on the Joints list), free ones
---only; missing entries take the lowest free id
---@return integer count
function Joints.copyLinked(joints, idMap, jointIds)
    local count = 0
    for _, joint in ipairs(joints) do
        local obj1, obj2 = idMap[joint.obj1], idMap[joint.obj2]
        local wanted = jointIds and jointIds[count + 1]
        -- callers check Joints.haveRoom first, nil only guards the limit
        local id = wanted and not Joints.find(wanted) and wanted or Joints.nextId()
        if obj1 and obj2 and id then
            table.insert(ModData.parsed.env_obj_joint, Joints.copy(joint, id, obj1, obj2))
            count = count + 1
        end
    end
    return count
end

---Removes joints linked to any of the ids, used when objects are deleted
---@param ids table<integer, boolean>
function Joints.removeLinkedToAny(ids)
    local joints = ModData.parsed.env_obj_joint
    for i = #joints, 1, -1 do
        if ids[joints[i].obj1] or ids[joints[i].obj2] then
            table.remove(joints, i)
        end
    end
end

---Moves joint anchor: fn receives x, y, z and returns new x, y, z
---@param joint FileParserEnvObjJoint
---@param fn fun(x: number, y: number, z: number): number, number, number
function Joints.transformPos(joint, fn)
    if not joint.props.pos then return end
    joint.props.pos = formatVector(fn(parseVector(joint.props.pos)))
end

---Rotates joint axis direction: fn receives x, y, z and returns new x, y, z
---@param joint FileParserEnvObjJoint
---@param fn fun(x: number, y: number, z: number): number, number, number
function Joints.transformAxis(joint, fn)
    if not joint.props.axis then return end
    joint.props.axis = formatVector(fn(parseVector(joint.props.axis)))
end

-- Joints list buttons (ui/joint_list.lua): New, Duplicate, Delete. Each is one undo step and a reload,
-- the joints stay in id order in the file

local function sortJoints()
    table.sort(ModData.parsed.env_obj_joint, function(a, b) return (a.id or 0) < (b.id or 0) end)
end

---@param ids table<integer, boolean>|integer[] joint ids, as a set or a list
---@return table<integer, boolean>
local function asSet(ids)
    local set = {}
    for k, v in pairs(ids) do
        if v == true then set[k] = true elseif type(v) == "number" then set[v] = true end
    end
    return set
end

---@param id integer? object id (1-based)
---@return FileParserEnvObj? the mod's object with that id
function Joints.objectById(id)
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.id == id then return obj end
    end
    return nil
end

---@param id integer? joint id
---@return FileParserEnvObjJoint?
function Joints.find(id)
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        if joint.id == id then return joint end
    end
    return nil
end

---Anchor halfway between two objects, as a pos line value
---@param obj1 FileParserEnvObj
---@param obj2 FileParserEnvObj
---@return string
function Joints.midpoint(obj1, obj2)
    local a, b = MGE.Transforms.positionOf(obj1), MGE.Transforms.positionOf(obj2)
    return formatVector((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2)
end

---The game doesn't join two static objects (the joint isn't shown and nothing moves): when a new link
---joins two, both are made dynamic (the static bit cleared, other flags kept). One static object is
---fine, the joint then holds the dynamic one to it. Call after the joints changed and before
---fitLinkedIds (dynamic objects need ids 1-MAX_NONSTATIC_OBJECTS too) and History.commit. The flag is
---read by the game when the mod loads, MGE.apply's reload applies it
---@param obj1 integer object id
---@param obj2 integer object id
local function unstaticLinked(obj1, obj2)
    local a, b = Joints.objectById(obj1), Joints.objectById(obj2)
    if not a or not b or not ModData.isStatic(a, true) or not ModData.isStatic(b, true) then return end
    local STATIC = MGE.FLAGS.STATIC
    for _, obj in ipairs({ a, b }) do
        local flag = tonumber(obj.props.flag) or get_obj_flag(obj.id - 1) or 0
        obj.props.flag = tostring(flag - bit.band(flag, STATIC))
    end
    echo("^04[MGE] objects " .. obj1 .. " and " .. obj2 .. " were both static, made dynamic: the game doesn't join two static objects")
end

---The game ignores joints to objects above the dynamic ids (mod_export.lua's id rules). A new link to
---such an object reindexes right away, like the Advanced tab's Reindex: joint-linked objects move to
---ids 1-MAX_NONSTATIC_OBJECTS, static ones up, the joints follow. Call after the joints changed and
---before History.commit, so it's the same undo step as the link. Acts on all objects, like Reindex
---@param jointId integer for the message
---@param obj1 integer
---@param obj2 integer
local function fitLinkedIds(jointId, obj1, obj2)
    local max = MGE.MAX_NONSTATIC_OBJECTS
    if not max or (obj1 <= max and obj2 <= max) then return end
    ModData.refreshJointIds() -- the new link counts before the reload
    local moved, left = ModData.reindex()
    if left > 0 then
        echo("^04[MGE] joint " .. jointId .. ": the game only joins objects 1-" .. max .. ", " .. left ..
            " dynamic or joined objects still above (no lower ids left), make some static")
    elseif moved > 0 then
        echo("^04[MGE] joint " .. jointId .. ": reindexed, " .. moved .. " objects moved so the joined ones are on ids 1-" .. max)
    end
end

-- the visible line of every joint MGE makes (Create, New pair, Generate): shown in game, and clickable
-- from any list (utils/world_select.lua). The Properties tab can hide them
Joints.NEW_VISIBLE = "1"

---New joint between two objects, its anchor (pos) halfway between their positions, visible. Nothing
---else is set: the game's defaults for the rest
---@param obj1 FileParserEnvObj
---@param obj2 FileParserEnvObj
---@param id integer? the joint id (an empty slot), default the lowest free one
---@return integer? id of the new joint, nil when the objects are the same, the id is taken or the joints are full
function Joints.addBetween(obj1, obj2, id)
    if obj1 == obj2 or obj1.id == obj2.id then return nil end
    if id then
        if id < 1 or id > MGE.MAX_ENV_JOINTS or Joints.find(id) then return nil end
    else
        id = Joints.haveRoom(1) and Joints.nextId() or nil
    end
    if not id then return nil end
    local joint = { kind = "env_obj_joint", id = id, obj1 = obj1.id, obj2 = obj2.id, lines = {},
        props = { pos = Joints.midpoint(obj1, obj2), visible = Joints.NEW_VISIBLE } }
    table.insert(ModData.parsed.env_obj_joint, joint)
    sortJoints()
    unstaticLinked(obj1.id, obj2.id)
    fitLinkedIds(id, obj1.id, obj2.id)
    MGE.History.commit()
    MGE.apply()
    return id
end

-- Joints panel edits (ui/editor_joint.lua). Each is one undo step and a reload: env joints have no live
-- setter, the game only reads them when the mod loads

---Numbers in a prop value, missing ones 0 ("3.6 -3.6" for range, "0 0 1" for axis)
---@param value string?
---@param count integer
---@return number[]
function Joints.parseNumbers(value, count)
    local numbers, i = {}, 0
    for word in tostring(value or ""):gmatch("%S+") do
        i = i + 1
        if i > count then break end
        numbers[i] = tonumber(word) or 0
    end
    for k = i + 1, count do numbers[k] = 0 end
    return numbers
end

---Writes a prop on joints, one undo step for all of them
---@param joints FileParserEnvObjJoint[]
---@param key string
---@param valueOf fun(joint: FileParserEnvObjJoint): string? new value, nil leaves that joint as it is
---@return boolean changed
function Joints.setProps(joints, key, valueOf)
    local changed = false
    for _, joint in ipairs(joints) do
        local value = valueOf(joint)
        if value ~= nil and joint.props[key] ~= value then
            joint.props[key] = value
            changed = true
        end
    end
    if not changed then return false end
    MGE.History.commit()
    MGE.apply()
    return true
end

---Sets one number of a prop on joints (x of pos, low of range...), the other numbers stay
---@param joints FileParserEnvObjJoint[]
---@param key string
---@param index integer
---@param count integer numbers in the prop
---@param value number
---@return boolean changed
function Joints.setComponent(joints, key, index, count, value)
    return Joints.setProps(joints, key, function(joint)
        local numbers = Joints.parseNumbers(joint.props[key], count)
        numbers[index] = value
        local words = {}
        for i, number in ipairs(numbers) do words[i] = MGE.FileHandler.formatNumber(number) end
        return table.concat(words, " ")
    end)
end

-- Move gizmo on the Joints list, both tabs (utils/gizmo.lua): drags the selected joints' anchors.
-- Joints have no live position, so a drag only offsets the drawn anchors (Joints.posPreview, read by
-- Joints.anchorOf and utils/highlight.lua); the release writes the pos lines, one undo step and a reload

---@class JointPosPreview
---@field ids table<integer, boolean> joints being dragged
---@field offset number[]

---@type JointPosPreview?
Joints.posPreview = nil

---A joint's anchor as drawn: its pos line, moved by a gizmo drag in progress. nil without a pos line
---@param joint FileParserEnvObjJoint
---@return number[]?
function Joints.anchorOf(joint)
    if not joint.props.pos then return nil end
    local p = Joints.parseNumbers(joint.props.pos, 3)
    local preview = Joints.posPreview
    if preview and preview.ids[joint.id] then
        local o = preview.offset
        p = { p[1] + o[1], p[2] + o[2], p[3] + o[3] }
    end
    return p
end

---Gizmo target for joints' anchors: Move only, world axes, around their average anchor. Joints
---without a pos line are left out (the game puts them itself, there's nothing to move from)
---@param joints FileParserEnvObjJoint[]
---@return GizmoTarget?
function Joints.target(joints)
    local list, ids = {}, {}
    local sx, sy, sz = 0.0, 0.0, 0.0
    for _, joint in ipairs(joints) do
        if joint.props.pos then
            local p = Joints.parseNumbers(joint.props.pos, 3)
            table.insert(list, joint)
            ids[joint.id] = true
            sx, sy, sz = sx + p[1], sy + p[2], sz + p[3]
        end
    end
    if #list == 0 then return nil end
    local n = #list
    local pivot = { sx / n, sy / n, sz / n } -- measured when made: stays put while dragging
    local t = { joints = list } ---@type table
    function t.pivot() return pivot end
    function t.frame() return MGE.Mat3.IDENTITY end
    function t.previewMove(offset) Joints.posPreview = { ids = ids, offset = offset } end
    function t.previewRotate() end -- Move only (gizmo.lua shows no other tool for joints)
    function t.restoreLive() Joints.posPreview = nil end
    function t.moveBy(offset)
        t.restoreLive()
        Joints.setProps(list, "pos", function(joint)
            local p = Joints.parseNumbers(joint.props.pos, 3)
            return formatVector(p[1] + offset[1], p[2] + offset[2], p[3] + offset[3])
        end)
    end
    function t.rotateByMatrix() t.restoreLive() end
    return t --[[@as GizmoTarget]]
end

---Moves joints' anchors halfway between the two objects each links
---@param joints FileParserEnvObjJoint[]
---@return boolean changed
function Joints.centerPos(joints)
    return Joints.setProps(joints, "pos", function(joint)
        local a, b = Joints.objectById(joint.obj1), Joints.objectById(joint.obj2)
        return a and b and Joints.midpoint(a, b) or nil
    end)
end

---Changes which objects a joint links. The anchor stays where it is (Joints.centerPos moves it)
---@param joint FileParserEnvObjJoint
---@param obj1 integer object id
---@param obj2 integer object id
---@return boolean changed
function Joints.setObjects(joint, obj1, obj2)
    if obj1 == obj2 then
        echo("^04[MGE] a joint links two different objects")
        return false
    end
    for _, id in ipairs({ obj1, obj2 }) do
        if not Joints.objectById(id) then
            echo("^04[MGE] this mod has no object " .. tostring(id))
            return false
        end
    end
    if joint.obj1 == obj1 and joint.obj2 == obj2 then return false end
    joint.obj1, joint.obj2 = obj1, obj2
    unstaticLinked(obj1, obj2)
    fitLinkedIds(joint.id, obj1, obj2)
    MGE.History.commit()
    MGE.apply()
    return true
end

-- Link tab of the Joints list (ui/editor_link.lua): the two objects of one joint slot are picked into a
-- draft (clicks in the world, utils/world_select.lua, or in the tab's object grid). The game doesn't
-- care which end is which, so the pick is a pair: a click adds an object, a click on a picked one takes
-- it out, at most two. Nothing changes in the mod until Create (an empty slot) or Update (a joint's new
-- objects): a stray click only changes the draft. Selecting another slot or Reset drops it, the next
-- draft starts from the saved link

---@class JointDraft
---@field jointId integer the slot (joint id) the draft is for
---@field obj1 integer? first picked object, set whenever obj2 is
---@field obj2 integer? second picked object

---@type JointDraft?
Joints.draft = nil
---Set by ui/editor_link.lua: the draft changed (the tab shows it)
---@type fun()
Joints.onDraftChanged = function() end

---The draft for a slot: the edited one, else the saved link (empty for an empty slot). Reading doesn't
---keep it (the highlight reads every frame): an undo or reload then shows the new saved link
---@param slotId integer
---@return JointDraft
function Joints.draftFor(slotId)
    local draft = Joints.draft
    if draft and draft.jointId == slotId then return draft end
    local joint = Joints.find(slotId)
    return { jointId = slotId, obj1 = joint and joint.obj1, obj2 = joint and joint.obj2 }
end

---The slot's draft, kept for changing it (a draft for another slot is dropped)
---@param slotId integer
---@return JointDraft
function Joints.editDraft(slotId)
    local draft = Joints.draftFor(slotId)
    Joints.draft = draft
    return draft
end

---Drops the draft, the slot's saved link shows again (Reset, another mod, after Create / Update)
function Joints.resetDraft()
    Joints.draft = nil
end

---@param draft JointDraft
---@param objId integer
---@return boolean
function Joints.draftHas(draft, objId)
    return draft.obj1 == objId or draft.obj2 == objId
end

---A clicked object: added to the pair, or taken out when it's picked already
---@param slotId integer
---@param objId integer
---@return boolean used false when the object can't be used (says why)
function Joints.offerDraft(slotId, objId)
    if not Joints.objectById(objId) then return false end
    local draft = Joints.editDraft(slotId)
    if draft.obj1 == objId then
        draft.obj1, draft.obj2 = draft.obj2, nil -- obj1 stays the one set first
    elseif draft.obj2 == objId then
        draft.obj2 = nil
    elseif not draft.obj1 then
        draft.obj1 = objId
    elseif not draft.obj2 then
        draft.obj2 = objId
    else
        echo("^04[MGE] a joint links two objects: click a picked one to take it out first")
        return false
    end
    Joints.onDraftChanged()
    return true
end

---@param joint FileParserEnvObjJoint
---@param obj1 integer
---@param obj2 integer
---@return boolean the joint links these two, in either order
local function linksPair(joint, obj1, obj2)
    return (joint.obj1 == obj1 and joint.obj2 == obj2) or (joint.obj1 == obj2 and joint.obj2 == obj1)
end

---Links every listed slot to the same two objects: a joint gets them (its anchor stays), an empty slot
---becomes a joint there (its anchor halfway between the two). One undo step for all of them
---@param slotIds integer[]
---@param obj1 integer object id
---@param obj2 integer object id
---@return integer changed slots that changed, 0 when none did or the objects can't be linked (says why)
function Joints.linkSlots(slotIds, obj1, obj2)
    if obj1 == obj2 then
        echo("^04[MGE] a joint links two different objects")
        return 0
    end
    local a, b = Joints.objectById(obj1), Joints.objectById(obj2)
    if not a or not b then
        echo("^04[MGE] the picked objects are gone, pick them again")
        return 0
    end
    local changed, anchor = 0, nil
    for _, id in ipairs(slotIds) do
        local joint = Joints.find(id)
        if joint then
            if not linksPair(joint, obj1, obj2) then
                joint.obj1, joint.obj2 = obj1, obj2
                changed = changed + 1
            end
        elseif id >= 1 and id <= MGE.MAX_ENV_JOINTS then
            anchor = anchor or Joints.midpoint(a, b)
            table.insert(ModData.parsed.env_obj_joint, { kind = "env_obj_joint", id = id, obj1 = obj1, obj2 = obj2,
                lines = {}, props = { pos = anchor, visible = Joints.NEW_VISIBLE } })
            changed = changed + 1
        end
    end
    if changed == 0 then return 0 end
    sortJoints()
    unstaticLinked(obj1, obj2)
    fitLinkedIds(slotIds[1], obj1, obj2)
    MGE.History.commit()
    MGE.apply()
    return changed
end

---What Create / Update would do with the current slot's draft for all the listed slots (the selection).
---The same two objects in either order are the same link
---@param slotId integer the current slot, its draft
---@param slotIds integer[]? the slots Create / Update links, default only slotId
---@return "incomplete"|"new"|"changed"|"unchanged" new: the current slot is empty
function Joints.draftState(slotId, slotIds)
    local draft = Joints.draftFor(slotId)
    if not draft.obj1 or not draft.obj2 then return "incomplete" end
    local any = false
    for _, id in ipairs(slotIds or { slotId }) do
        local joint = Joints.find(id)
        if not joint or not linksPair(joint, draft.obj1, draft.obj2) then any = true end
    end
    if not any then return "unchanged" end
    return Joints.find(slotId) and "changed" or "new"
end

---Create / Update: links all the listed slots to the current slot's draft (Joints.linkSlots), one undo
---step, the draft is dropped after
---@param slotId integer the current slot, its draft
---@param slotIds integer[]? the slots to link, default only slotId
---@return boolean done
function Joints.commitDraft(slotId, slotIds)
    local state = Joints.draftState(slotId, slotIds)
    if state == "incomplete" or state == "unchanged" then return false end
    local draft = Joints.draftFor(slotId)
    local done = Joints.linkSlots(slotIds or { slotId }, draft.obj1, draft.obj2) > 0
    if done then Joints.resetDraft() end
    return done
end

---Copies of joints (same objects and lines), new ids
---@param ids table<integer, boolean>|integer[] joint ids
---@return integer[]? new ids in the order of the copied ids, nil when nothing was copied
function Joints.duplicate(ids)
    local set = asSet(ids)
    local sources = {}
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        if set[joint.id] then table.insert(sources, joint) end
    end
    if #sources == 0 or not Joints.haveRoom(#sources) then return nil end
    table.sort(sources, function(a, b) return a.id < b.id end)
    local newIds = {}
    for _, joint in ipairs(sources) do
        local id = Joints.nextId()
        table.insert(ModData.parsed.env_obj_joint, Joints.copy(joint, id, joint.obj1, joint.obj2))
        table.insert(newIds, id)
    end
    sortJoints()
    MGE.History.commit()
    MGE.apply()
    return newIds
end

---Removes joints, the other joints keep their ids (free ids are reused by the next New / Duplicate)
---@param ids table<integer, boolean>|integer[] joint ids
---@return integer removed
function Joints.remove(ids)
    local set = asSet(ids)
    local joints, removed = ModData.parsed.env_obj_joint, 0
    for i = #joints, 1, -1 do
        if set[joints[i].id] then
            table.remove(joints, i)
            removed = removed + 1
        end
    end
    if removed == 0 then return 0 end
    MGE.History.commit()
    MGE.apply()
    return removed
end
