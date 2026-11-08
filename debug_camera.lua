-- One-off test 2: can MGE keep the camera further away than the orbital camera's 13.5 limit?
-- Run with: /ls mge/debug_camera.lua  (close MGE first). Results go to chat / chatlog.txt.
-- Follow the instructions it prints (drag the camera when asked). Delete this file afterwards.
local HOOK = "mge_debug_camera"
remove_hooks(HOOK)

local TARGET = 25 -- distance we try to hold

local function info()
    local c = get_camera_info()
    local dx, dy, dz = c.pos.x - c.lookat.x, c.pos.y - c.lookat.y, c.pos.z - c.lookat.z
    return c, math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function report(label)
    local c, dist = info()
    echo(string.format("^07[cam2] %s: dist %.2f  pos %.1f %.1f %.1f  hyp %.2f  mode %s", label, dist,
        c.pos.x, c.pos.y, c.pos.z, c.other and c.other.hyp or -1, tostring(get_camera_mode())))
end

local function placeAt(d)
    local c, dist = info()
    local s = d / math.max(dist, 1e-6)
    set_camera_pos(c.lookat.x + (c.pos.x - c.lookat.x) * s, c.lookat.y + (c.pos.y - c.lookat.y) * s,
        c.lookat.z + (c.pos.z - c.lookat.z) * s)
end

local hold, holdReturn = false, nil -- per-frame placement inside the camera hook, and what it returns
local frame, step, nextStepAt = 0, 0, 30

local steps = {
    function()
        set_camera_mode(4); hold, holdReturn = true, nil
        report("A1 mode 4, hook places at 25 every frame, returns nothing")
    end,
    function() report("A2 one second later (held at 25?)") end,
    function()
        holdReturn = 1
        report("B1 same, hook now returns 1")
    end,
    function()
        report("B2 one second later (held at 25?)")
        echo("^07[cam2] B3 DRAG / orbit the camera with the mouse now for 4 seconds (does it still turn?)")
    end,
    function() report("B4 after dragging (did pos change direction while dist stayed 25?)") end,
    function()
        hold = false
        set_camera_mode(3)
        report("C1 hook off, mode 3 (free)")
        placeAt(TARGET)
        report("C1 right after placing at 25")
    end,
    function()
        report("C2 one second later (free camera held at 25?)")
        echo("^07[cam2] C3 DRAG the camera and scroll the mouse wheel now for 4 seconds")
    end,
    function() report("C4 after dragging / scrolling in free mode") end,
    function()
        set_camera_mode(4)
        report("D1 back to mode 4, hook off")
    end,
    function() report("D2 one second later") end,
}
local waits = { 60, 60, 60, 240, 30, 60, 240, 30, 60, 1 }

add_hook("camera", HOOK, function()
    frame = frame + 1
    if frame >= nextStepAt then
        step = step + 1
        if step > #steps then
            remove_hooks(HOOK)
            echo("^07[cam2] done, the lines are in chatlog.txt")
            return
        end
        steps[step]()
        nextStepAt = frame + waits[step]
    end
    if hold then
        placeAt(TARGET)
        return holdReturn
    end
end)
echo("^07[cam2] camera test 2 started")
