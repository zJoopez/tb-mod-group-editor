-- utils/joints.lua: the Joints panel's pos edits on the parsed mod. Loads its own copy of the module with
-- stand-ins for what it reaches (ModData, Transforms, History, apply), and puts the originals back
local T = ...

---Runs fn with a fresh Joints over `parsed`, objects placed at `positions` (id -> {x, y, z})
---@param parsed table
---@param positions table<integer, number[]>
---@param fn fun(Joints: Joints, commits: { n: integer })
local function withJoints(parsed, positions, fn)
    local saved = { Joints = MGE.Joints, ModData = MGE.ModData, Transforms = MGE.Transforms,
        History = MGE.History, apply = MGE.apply, Camera = MGE.Camera }
    local commits = { n = 0 }
    MGE.ModData = { parsed = parsed }
    MGE.Transforms = { positionOf = function(obj) return positions[obj.id] end }
    MGE.History = { commit = function() commits.n = commits.n + 1 end }
    MGE.apply = function() end
    local ok, err = pcall(function()
        dofile(MGE.scriptPath .. "utils/joints.lua")
        fn(MGE.Joints, commits)
    end)
    MGE.Joints, MGE.ModData, MGE.Transforms = saved.Joints, saved.ModData, saved.Transforms
    MGE.History, MGE.apply, MGE.Camera = saved.History, saved.apply, saved.Camera
    if not ok then error(err, 0) end
end

local function mod()
    return {
        env_obj = { { id = 1, props = {} }, { id = 2, props = {} }, { id = 3, props = {} } },
        env_obj_joint = {
            { kind = "env_obj_joint", id = 1, obj1 = 1, obj2 = 2, lines = {}, props = { pos = "0 0 2" } },
            { kind = "env_obj_joint", id = 2, obj1 = 2, obj2 = 3, lines = {}, props = { pos = "2 0 4" } },
            { kind = "env_obj_joint", id = 3, obj1 = 1, obj2 = 3, lines = {}, props = {} }, -- locked: no pos
        },
    }
end
local POSITIONS = { [1] = { 0, 0, 0 }, [2] = { 4, 0, 0 }, [3] = { 0, 6, 2 } }

T.test("joints: typed Pos moves anchored joints by their center", function()
    local parsed = mod()
    withJoints(parsed, POSITIONS, function(Joints, commits)
        local j = parsed.env_obj_joint
        T.ok(Joints.setPosAxis({ j[1], j[2] }, 1, 5), "changed")
        T.eq(j[1].props.pos, "4 0 2", "center x 1 -> 5: moved by 4")
        T.eq(j[2].props.pos, "6 0 4", "the other moved the same")
        T.eq(commits.n, 1, "one undo step")
        T.ok(not Joints.setPosAxis({ j[1], j[2] }, 1, 5), "same value: nothing to do")
        T.eq(commits.n, 1, "no extra step")
    end)
end)

T.test("joints: a locked joint (no pos) starts from its objects' midpoint", function()
    local parsed = mod()
    withJoints(parsed, POSITIONS, function(Joints)
        local j = parsed.env_obj_joint
        Joints.setPosAxis({ j[3] }, 3, 7)
        T.eq(j[3].props.pos, "0 3 7", "midpoint 0 3 1, z typed")
        -- mixed: anchored ones move by the center's change, the locked one gets the typed value
        parsed = mod()
        MGE.ModData.parsed = parsed
        j = parsed.env_obj_joint
        Joints.setPosAxis(j, 2, 1)
        T.eq(j[1].props.pos, "0 1 2", "anchored: y 0 -> 1")
        T.eq(j[2].props.pos, "2 1 4", "anchored: y 0 -> 1")
        T.eq(j[3].props.pos, "0 1 1", "locked: midpoint with y 1")
    end)
end)

T.test("joints: camera follow looks at moved anchors", function()
    local parsed = mod()
    withJoints(parsed, POSITIONS, function(Joints)
        local looked
        MGE.Camera = { followMoves = true, focusOn = function(center, radius) looked = { center = center, radius = radius } end }
        local j = parsed.env_obj_joint
        Joints.setPosAxis({ j[1] }, 3, 5)
        T.ok(looked ~= nil, "looked at after a Pos change")
        T.nearList(looked and looked.center or {}, { 0, 0, 5 }, 1e-9, "at the moved anchor")
        looked = nil
        Joints.setProps({ j[1] }, "axis", function() return "0 0 1" end)
        T.eq(looked, nil, "not after an axis change")
        MGE.Camera.followMoves = false
        Joints.setPosAxis({ j[2] }, 1, 9)
        T.eq(looked, nil, "camera follow off: stays")
    end)
end)

T.test("joints: Joints.target leaves locked joints out", function()
    local parsed = mod()
    withJoints(parsed, POSITIONS, function(Joints)
        local j = parsed.env_obj_joint
        T.eq(Joints.target({ j[3] }), nil, "only a locked one: nothing to drag")
        local pivot = Joints.target(j).pivot()
        T.eq(pivot[1], 1, "center of the two anchors")
        T.eq(pivot[3], 3, "center z")
    end)
end)
