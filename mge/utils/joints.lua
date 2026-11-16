



local Joints = {}
MGE.Joints = Joints
local ModData = MGE.ModData



local function parseVector(value)
    local x, y, z = tostring(value or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
end


local function formatVector(x, y, z)
    return MGE.FileHandler.formatNumbers(x, y, z)
end



function Joints.idSet(objects)
    local set = {}
    for _, obj in ipairs(objects) do set[obj.id] = true end
    return set
end





function Joints.getLinked(ids, joints)
    local linked = {}
    for _, joint in ipairs(joints or ModData.parsed.env_obj_joint) do
        if ids[joint.obj1] and ids[joint.obj2] then
            table.insert(linked, joint)
        end
    end
    return linked
end




function Joints.getObjectIds(joints)
    local ids = {}
    for _, joint in ipairs(joints or {}) do
        ids[joint.obj1] = true
        ids[joint.obj2] = true
    end
    return ids
end



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



function Joints.nextId()
    return Joints.freeIds()[1]
end





function Joints.countLinked(joints, ids)
    return #Joints.getLinked(ids, joints)
end




function Joints.haveRoom(count)
    local free = #Joints.freeIds()
    if count <= free then return true end
    MGE.say("Not enough joints available: " .. count .. " needed, " .. free .. " free (max " .. MGE.MAX_ENV_JOINTS .. ")")
    return false
end







function Joints.copy(joint, id, obj1, obj2)
    local props = {}
    for k, v in pairs(joint.props) do props[k] = v end
    return { kind = "env_obj_joint", id = id, obj1 = obj1, obj2 = obj2, props = props, lines = joint.lines }
end







function Joints.copyLinked(joints, idMap, jointIds)
    local count = 0
    for _, joint in ipairs(joints) do
        local obj1, obj2 = idMap[joint.obj1], idMap[joint.obj2]
        local wanted = jointIds and jointIds[count + 1]

        local id = wanted and not Joints.find(wanted) and wanted or Joints.nextId()
        if obj1 and obj2 and id then
            table.insert(ModData.parsed.env_obj_joint, Joints.copy(joint, id, obj1, obj2))
            count = count + 1
        end
    end
    return count
end



function Joints.removeLinkedToAny(ids)
    local joints = ModData.parsed.env_obj_joint
    for i = #joints, 1, -1 do
        if ids[joints[i].obj1] or ids[joints[i].obj2] then
            table.remove(joints, i)
        end
    end
end




function Joints.transformPos(joint, fn)
    if not joint.props.pos then return end
    joint.props.pos = formatVector(fn(parseVector(joint.props.pos)))
end




function Joints.transformAxis(joint, fn)
    if not joint.props.axis then return end
    joint.props.axis = formatVector(fn(parseVector(joint.props.axis)))
end




local function sortJoints()
    table.sort(ModData.parsed.env_obj_joint, function(a, b) return (a.id or 0) < (b.id or 0) end)
end



local function asSet(ids)
    local set = {}
    for k, v in pairs(ids) do
        if v == true then set[k] = true elseif type(v) == "number" then set[v] = true end
    end
    return set
end



function Joints.objectById(id)
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.id == id then return obj end
    end
    return nil
end



function Joints.find(id)
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        if joint.id == id then return joint end
    end
    return nil
end





function Joints.midpoint(obj1, obj2)
    local a, b = MGE.Transforms.positionOf(obj1), MGE.Transforms.positionOf(obj2)
    return formatVector((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2)
end





function Joints.jointMidpoint(joint)
    local a, b = Joints.objectById(joint.obj1), Joints.objectById(joint.obj2)
    if not a or not b then return nil end
    local p, q = MGE.Transforms.positionOf(a), MGE.Transforms.positionOf(b)
    return { (p[1] + q[1]) / 2, (p[2] + q[2]) / 2, (p[3] + q[3]) / 2 }
end








local function unstaticLinked(obj1, obj2)
    local a, b = Joints.objectById(obj1), Joints.objectById(obj2)
    if not a or not b or not ModData.isStatic(a, true) or not ModData.isStatic(b, true) then return end
    local STATIC = MGE.FLAGS.STATIC
    for _, obj in ipairs({ a, b }) do
        local flag = tonumber(obj.props.flag) or get_obj_flag(obj.id - 1) or 0
        obj.props.flag = tostring(flag - bit.band(flag, STATIC))
    end
    MGE.say("objects " .. obj1 .. " and " .. obj2 .. " were both static, made dynamic: the game doesn't join two static objects")
end








local function fitLinkedIds(jointId, obj1, obj2)
    local max = MGE.MAX_NONSTATIC_OBJECTS
    if not max or (obj1 <= max and obj2 <= max) then return end
    ModData.refreshJointIds()
    local moved, left = ModData.reindex()
    if left > 0 then
        MGE.say("joint " .. jointId .. ": the game only joins objects 1-" .. max .. ", " .. left ..
            " dynamic or joined objects still above (no lower ids left), make some static")
    elseif moved > 0 then
        MGE.say("joint " .. jointId .. ": reindexed, " .. moved .. " objects moved so the joined ones are on ids 1-" .. max)
    end
end



Joints.NEW_VISIBLE = "1"







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




local function followAnchors(joints)
    local Camera = MGE.Camera
    if not Camera or not Camera.followMoves then return end
    local target = Joints.target(joints)
    if not target then return end
    local center = target.pivot()
    local radius = 0.5
    for _, joint in ipairs(target.joints) do
        local p = Joints.parseNumbers(joint.props.pos, 3)
        local d = math.sqrt((p[1] - center[1]) ^ 2 + (p[2] - center[2]) ^ 2 + (p[3] - center[3]) ^ 2)
        radius = math.max(radius, d + 0.5)
    end
    Camera.focusOn(center, radius)
end






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






function Joints.moveAnchors(joints, posOf)
    local changed = Joints.setProps(joints, "pos", posOf)
    if changed then followAnchors(joints) end
    return changed
end








function Joints.setComponent(joints, key, index, count, value)
    return Joints.setProps(joints, key, function(joint)
        local numbers = Joints.parseNumbers(joint.props[key], count)
        numbers[index] = value
        local words = {}
        for i, number in ipairs(numbers) do words[i] = MGE.FileHandler.formatNumber(number) end
        return table.concat(words, " ")
    end)
end










Joints.posPreview = nil




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
    local pivot = { sx / n, sy / n, sz / n }
    local t = { joints = list }
    function t.pivot() return pivot end
    function t.frame() return MGE.Mat3.IDENTITY end
    function t.previewMove(offset) Joints.posPreview = { ids = ids, offset = offset } end
    function t.previewRotate() end
    function t.restoreLive() Joints.posPreview = nil end
    function t.moveBy(offset)
        t.restoreLive()
        Joints.moveAnchors(list, function(joint)
            local p = Joints.parseNumbers(joint.props.pos, 3)
            return formatVector(p[1] + offset[1], p[2] + offset[2], p[3] + offset[3])
        end)
    end
    function t.rotateByMatrix() t.restoreLive() end
    return t
end









function Joints.setPosAxis(joints, index, value)
    local target = Joints.target(joints)
    local delta = target and value - target.pivot()[index] or 0
    return Joints.moveAnchors(joints, function(joint)
        local p
        if joint.props.pos then
            p = Joints.parseNumbers(joint.props.pos, 3)
            p[index] = p[index] + delta
        else
            p = Joints.jointMidpoint(joint)
            if not p then return nil end
            p[index] = value
        end
        return formatVector(p[1], p[2], p[3])
    end)
end




function Joints.centerPos(joints)
    return Joints.moveAnchors(joints, function(joint)
        local m = Joints.jointMidpoint(joint)
        return m and formatVector(m[1], m[2], m[3]) or nil
    end)
end






function Joints.setObjects(joint, obj1, obj2)
    if obj1 == obj2 then
        MGE.say("a joint links two different objects")
        return false
    end
    for _, id in ipairs({ obj1, obj2 }) do
        if not Joints.objectById(id) then
            MGE.say("this mod has no object " .. tostring(id))
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














Joints.draft = nil




Joints.worldPick = false


Joints.onDraftChanged = function() end





function Joints.draftFor(slotId)
    local draft = Joints.draft
    if draft and draft.jointId == slotId then return draft end
    local joint = Joints.find(slotId)
    return { jointId = slotId, obj1 = joint and joint.obj1, obj2 = joint and joint.obj2 }
end




function Joints.editDraft(slotId)
    local draft = Joints.draftFor(slotId)
    Joints.draft = draft
    return draft
end


function Joints.resetDraft()
    Joints.draft = nil
end




function Joints.draftHas(draft, objId)
    return draft.obj1 == objId or draft.obj2 == objId
end





function Joints.offerDraft(slotId, objId)
    if not Joints.objectById(objId) then return false end
    local draft = Joints.editDraft(slotId)
    if draft.obj1 == objId then
        draft.obj1, draft.obj2 = draft.obj2, nil
    elseif draft.obj2 == objId then
        draft.obj2 = nil
    elseif not draft.obj1 then
        draft.obj1 = objId
    elseif not draft.obj2 then
        draft.obj2 = objId
    else
        MGE.say("a joint links two objects: click a picked one to take it out first")
        return false
    end
    Joints.onDraftChanged()
    return true
end





local function linksPair(joint, obj1, obj2)
    return (joint.obj1 == obj1 and joint.obj2 == obj2) or (joint.obj1 == obj2 and joint.obj2 == obj1)
end







function Joints.linkSlots(slotIds, obj1, obj2)
    if obj1 == obj2 then
        MGE.say("a joint links two different objects")
        return 0
    end
    local a, b = Joints.objectById(obj1), Joints.objectById(obj2)
    if not a or not b then
        MGE.say("the picked objects are gone, pick them again")
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






function Joints.commitDraft(slotId, slotIds)
    local state = Joints.draftState(slotId, slotIds)
    if state == "incomplete" or state == "unchanged" then return false end
    local draft = Joints.draftFor(slotId)
    local done = Joints.linkSlots(slotIds or { slotId }, draft.obj1, draft.obj2) > 0
    if done then Joints.resetDraft() end
    return done
end




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
