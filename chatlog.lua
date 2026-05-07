local hookname = "chatlog"
local filePath = "../data/script/tb-move-stuff/chatlog.txt"
remove_hooks(hookname)

local file = Files.Open(filePath, FILES_MODE_WRITE)
if not file then
    echo("failed to open file")
    return
else
    echo("chat logging started")
end
file:close()

local function kys()
    file:close()
    remove_hooks(hookname)
end

add_hook("console", hookname, function(event)
    if event == "kys" then
        kys()
    elseif event == "ping" then
        echo("pong")
    else
        file = Files.Open(filePath, FILES_MODE_APPEND)
        file:writeLine(tostring(event))
        file:close()
    end
end)