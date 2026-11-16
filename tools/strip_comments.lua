-- Removes the comments from a Lua 5.1 file for the release zip (tools/package.ps1):
--
--   lua5.1 tools/strip_comments.lua in.lua out.lua
--
-- Every line is kept (a comment's line stays, empty, a long comment keeps its newlines), so an error in
-- the release names the same line as the source. Strings and long strings are copied as they are: a "--"
-- inside one isn't a comment. Trailing spaces go, and the lines that end up empty at the end of the file.
-- package.ps1 checks the result: `luac -s` (no line info) of both must give the same bytes, which only
-- holds when nothing but comments and spacing changed.
local inPath, outPath = arg[1], arg[2]
if not inPath or not outPath then
    io.stderr:write("usage: lua5.1 tools/strip_comments.lua in.lua out.lua\n")
    os.exit(2)
end

local f = assert(io.open(inPath, "rb"))
local src = f:read("*a")
f:close()

local out = {}
local i, n = 1, #src

---Level of a long bracket opening at position p ("[[" 0, "[=[" 1...), nil when there's none
local function longOpen(p)
    local eq = src:match("^%[(=*)%[", p)
    return eq and #eq or nil
end

---Position just after the long bracket of `level` closing from p on, or the end
local function longClose(p, level)
    local close = "]" .. string.rep("=", level) .. "]"
    local s, e = src:find(close, p, true)
    if not s then error(inPath .. ": unfinished long string or comment") end
    return e + 1
end

while i <= n do
    local c = src:sub(i, i)
    if c == "-" and src:sub(i + 1, i + 1) == "-" then
        -- a comment: long ("--[[", "--[==[") keeps only its newlines, a line comment goes up to its newline
        local level = longOpen(i + 2)
        if level then
            local after = longClose(i + 2 + level + 2, level)
            local _, newlines = src:sub(i, after - 1):gsub("\n", "")
            out[#out + 1] = string.rep("\n", newlines)
            i = after
        else
            local nl = src:find("\n", i, true)
            i = nl or n + 1 -- the newline itself is copied by the next pass
        end
    elseif c == '"' or c == "'" then
        -- a quoted string, escapes skipped over (\" doesn't end it)
        local j = i + 1
        while j <= n do
            local d = src:sub(j, j)
            if d == "\\" then
                j = j + 2
            elseif d == c then
                break
            elseif d == "\n" then
                error(inPath .. ": unfinished string")
            else
                j = j + 1
            end
        end
        out[#out + 1] = src:sub(i, j)
        i = j + 1
    elseif c == "[" and longOpen(i) then
        local level = longOpen(i)
        local after = longClose(i + level + 2, level)
        out[#out + 1] = src:sub(i, after - 1)
        i = after
    else
        -- plain code up to the next character that could start a comment or a string
        local j = src:find("[%-\"'%[]", i + 1) or n + 1
        out[#out + 1] = src:sub(i, j - 1)
        i = j
    end
end

local text = table.concat(out)
-- trailing spaces (code lines and the leftovers of removed comments), not inside long strings: none of
-- MGE's long strings end lines with spaces, and the luac check catches it if one ever does
text = text:gsub("[ \t]+\r?\n", "\n"):gsub("\r\n", "\n")
text = text:gsub("%s+$", "") .. "\n"

local o = assert(io.open(outPath, "wb"))
o:write(text)
o:close()
