-- MGE offline tests: the pure-logic modules (file parsing, matrix math, the map converter) under
-- plain Lua 5.1, no game needed. Run from anywhere:
--
--   lua5.1 mge/tests/run.lua            all test files
--   lua5.1 mge/tests/run.lua mapconv    only files whose name contains "mapconv"
--
-- Exit code 0 when everything passes, 1 otherwise. Engine functions are stubbed only where a module
-- needs them; anything touching the world, UI or hooks is for the in-game check (/ls mge.lua).
-- Add a test file: put tests/test_<name>.lua next to this one and add it to FILES below.
if not arg then -- loaded in game with /ls
    echo("^04[MGE] the tests run outside the game: lua5.1 mge/tests/run.lua")
    return
end

local FILES = {
    "test_file_handler.lua",
    "test_parking.lua",
    "test_mat3.lua",
    "test_scroll_list.lua",
    "test_mapconv.lua",
    "test_bsp.lua",
}

-- game libraries plain 5.1 lacks (same shims as the workspace CLAUDE.md harness header)
if not bit then -- BitOp shim (game provides LuaJIT BitOp), results are unsigned
    local function op(a, b, f)
        a, b = a % 2 ^ 32, b % 2 ^ 32
        local r, p = 0, 1
        for _ = 1, 32 do
            local x, y = a % 2, b % 2
            if f(x, y) then r = r + p end
            a, b, p = (a - x) / 2, (b - y) / 2, p * 2
        end
        return r
    end
    bit = {
        band = function(a, b) return op(a, b, function(x, y) return x == 1 and y == 1 end) end,
        bor = function(a, b) return op(a, b, function(x, y) return x == 1 or y == 1 end) end,
        bxor = function(a, b) return op(a, b, function(x, y) return x ~= y end) end,
        lshift = function(a, n) return (a * 2 ^ n) % 2 ^ 32 end,
        rshift = function(a, n) return math.floor((a % 2 ^ 32) / 2 ^ n) end,
    }
end
-- minimal luautf8 stand-in: len is UTF-8 aware, everything else falls back to string (byte-based)
utf8 = utf8 or setmetatable({ len = function(s) local _, n = s:gsub("[^\128-\191]", "") return n end },
    { __index = string })
echo = echo or function(...) print(...) end
add_hook = add_hook or function() end
remove_hooks = remove_hooks or function() end

local testDir = arg[0]:match("^(.*[/\\])") or "./"
MGE = { scriptPath = testDir .. "../mge/", hookname = "mge_test", onQuit = {} }

-- Files (system/iofiles.lua) stand-in: FileHandler.ParseMod reads through it. Tests register file
-- contents by path with T.files[path] = text, nothing touches the disk
FILES_MODE_READONLY, FILES_MODE_WRITE = 0, 1
local fakeFiles = {}
Files = {
    Open = function(path)
        local text = fakeFiles[path]
        local file = { data = text }
        function file:readAll()
            local lines = {}
            for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line:gsub("\r$", "") end
            if lines[#lines] == "" then lines[#lines] = nil end -- like the game: the last empty line is dropped
            return lines
        end
        function file:close() end
        return file
    end,
}

for _, module in ipairs({ "utils/mat3.lua", "utils/file_handler.lua", "utils/mod_export.lua",
    "utils/history.lua", "utils/parking.lua", "mapconv/vmf.lua", "mapconv/bsp.lua", "mapconv/brush.lua", "mapconv/boxfit.lua",
    "mapconv/merge.lua", "mapconv/convert.lua", "ui/scroll_list.lua" }) do
    dofile(MGE.scriptPath .. module)
end

---Assertions shared by the test files. A failed check is counted and reported, the test goes on
local T = { dir = testDir, files = fakeFiles, passed = 0, failed = 0, current = "" }

local function fail(message)
    T.failed = T.failed + 1
    local where = debug.traceback("", 3):match("\n%s*([^\n]*test_[^\n]*)") or "?"
    print(string.format("  FAIL %s: %s\n       at %s", T.current, message, where))
end

function T.ok(cond, message)
    if cond then T.passed = T.passed + 1 else fail(message or "expected true") end
end

function T.eq(actual, expected, message)
    if actual == expected then
        T.passed = T.passed + 1
    else
        fail(string.format("%s: expected %s, got %s", message or "eq", tostring(expected), tostring(actual)))
    end
end

function T.near(actual, expected, eps, message)
    eps = eps or 1e-9
    if type(actual) == "number" and math.abs(actual - expected) <= eps then
        T.passed = T.passed + 1
    else
        fail(string.format("%s: expected %s (+-%g), got %s", message or "near", tostring(expected), eps, tostring(actual)))
    end
end

---Each number in two lists (or a space separated string of numbers) within eps
function T.nearList(actual, expected, eps, message)
    local function list(v)
        if type(v) ~= "string" then return v end
        local out = {}
        for n in v:gmatch("%S+") do out[#out + 1] = tonumber(n) end
        return out
    end
    actual, expected = list(actual), list(expected)
    local same = type(actual) == "table" and #actual == #expected
    for k = 1, same and #expected or 0 do
        if not (actual[k] and math.abs(actual[k] - expected[k]) <= (eps or 1e-9)) then same = false end
    end
    if same then
        T.passed = T.passed + 1
    else
        local shown = type(actual) == "table" and table.concat(actual, " ") or tostring(actual)
        fail(string.format("%s: expected {%s}, got {%s}", message or "nearList", table.concat(expected, " "), shown))
    end
end

---The function must throw, with message containing pattern (plain text) when given
function T.throws(fn, pattern, message)
    local ok, err = pcall(fn)
    if not ok and (not pattern or tostring(err):find(pattern, 1, true)) then
        T.passed = T.passed + 1
    else
        fail((message or "throws") .. (ok and ": didn't throw" or (": wrong error: " .. tostring(err))))
    end
end

---A named group of checks, an error inside counts as one failure and the next test runs
function T.test(name, fn)
    T.current = name
    local ok, err = pcall(fn)
    if not ok then fail("error: " .. tostring(err)) end
end

local filter = arg[1]
local started = os.clock()
for _, name in ipairs(FILES) do
    if not filter or name:find(filter, 1, true) then
        print(name)
        local chunk, err = loadfile(testDir .. name)
        if not chunk then
            T.failed = T.failed + 1
            print("  FAIL can't load: " .. tostring(err))
        else
            local ok, runErr = pcall(chunk, T)
            if not ok then
                T.failed = T.failed + 1
                print("  FAIL " .. name .. ": " .. tostring(runErr))
            end
        end
    end
end
print(string.format("\n%d passed, %d failed (%.2f s)", T.passed, T.failed, os.clock() - started))
os.exit(T.failed == 0 and 0 or 1)
