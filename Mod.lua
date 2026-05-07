local Types = dofile(MgePath .. "ModTypes.lua")
local Parser = dofile(MgePath .. "ModParser.lua")
local Saver = dofile(MgePath .. "ModSaver.lua")

Mod = Types.Mod

function Mod.ParseFile(path)
    print("start parse " ..path)
    return Parser.ParseFile(path)
end

function Mod:save(path)
    return Saver.Save(path, self)
end

return Mod