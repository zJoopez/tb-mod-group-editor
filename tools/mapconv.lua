-- MGE map converter, command line: turns a brush map (.vmf, or a Source .bsp) into an MGE object asset (.tbm) of static
-- boxes. Import it in MGE (Objects list > Import): it keeps its positions, the anchor lands at the
-- dojo center on the ground. Plan and status: ../docs/map-import-plan.md
--
--   lua5.1 mge/tools/mapconv.lua <map.vmf|map.bsp> [options]       (any Lua 5.1 or newer)
--
-- .bsp: compiled Source maps (CS:S, CS:GO, TF2, HL2, Garry's Mod), read directly. Not GoldSrc (CS 1.6)
-- or Source 2 (CS2) maps.
if not arg then -- loaded in game with /ls
    echo("^04[MGE] mapconv runs outside the game: lua5.1 mge/tools/mapconv.lua <map.vmf|map.bsp>")
    return
end

local USAGE = [[
usage: mapconv.lua <map.vmf|map.bsp> [options]
  -o, --out <file>          output .tbm (default: mge/mge/assets/obj/<map>.tbm, Import lists it)
  --scale <n>               Toribash units per map unit (default 0.035: Source player 72 -> tori 2.5)
  --budget <n>              most boxes written, biggest first (default 200, a mod holds 256 objects)
  --min-size <n>            leave out brushes smaller than this on every side, map units (default 4)
  --region <x1 y1 z1 x2 y2 z2>  only brushes centered in this box, map units (e.g. one site)
  --anchor <x y z>          map point placed at the dojo center on the ground
  --anchor-entity <class>   else the first entity of this class (default info_player_terrorist),
                            else the middle of the boxes at their lowest point
  --yaw <deg>               turn the map around the anchor
  --no-clips                leave out player clips (invisible walls, ramps over stairs). On by default,
                            colored like the map geometry each one covers
  --sky-clips               also keep sky clips: the big lids between the roofs and the sky
  --invisible               keep solid brushes nobody sees (only nodraw-like tool textures), off by default
  --no-terrain              leave out terrain (.bsp displacements), converted to slabs by default
  --terrain-tolerance <n>   how bumpy a terrain slab may be, map units (default 8, smaller: more slabs)
  --no-merge                don't join boxes that make one bigger box
  --no-simplify             don't join nearly flat neighbouring slabs (terrain floors, floor tiles)
  --simplify-tolerance <n>  how much thicker a joined slab may get (bumps, tilt), map units (default 12)
  --simplify-fill <0-1>     how much of a joined slab its parts must cover (default 0.75)
  --drop-covered            also leave out boxes 95% covered by other boxes together (boxes entirely
                            inside another box are always left out)
  --no-floors-first         budget order by size only (default: what can be stood on counts extra)
  --center-first            budget order: the region's middle first, its edges left out first
  --ungrippable             boxes can't be grabbed
  --slab-thickness <n>      ramp slab thickness, map units (default 8)
  -h, --help]]

local toolDir = arg[0]:match("^(.*[/\\])") or "./"
MGE = { scriptPath = toolDir .. "../mge/" }
for _, module in ipairs({ "utils/mat3.lua", "utils/file_handler.lua", "utils/mod_export.lua",
    "mapconv/vmf.lua", "mapconv/bsp.lua", "mapconv/brush.lua", "mapconv/boxfit.lua",
    "mapconv/merge.lua", "mapconv/convert.lua" }) do
    dofile(MGE.scriptPath .. module)
end
local MapConv = MGE.MapConv

local function fail(message)
    io.stderr:write("mapconv: " .. message .. "\n")
    os.exit(1)
end

local options, input, output = {}, nil, nil
local i = 1
local function number()
    i = i + 1
    local value = tonumber(arg[i])
    if not value then fail("number expected after " .. tostring(arg[i - 1])) end
    return value
end
local function numbers(count)
    local list = {}
    for k = 1, count do list[k] = number() end
    return list
end
while i <= #arg do
    local a = arg[i]
    if a == "-h" or a == "--help" then
        print(USAGE)
        os.exit(0)
    elseif a == "-o" or a == "--out" then
        i = i + 1
        output = arg[i] or fail("file expected after " .. a)
    elseif a == "--scale" then
        options.scale = number()
    elseif a == "--budget" then
        options.budget = math.floor(number())
    elseif a == "--min-size" then
        options.minSize = number()
    elseif a == "--region" then
        local v = numbers(6)
        options.region = {
            min = { math.min(v[1], v[4]), math.min(v[2], v[5]), math.min(v[3], v[6]) },
            max = { math.max(v[1], v[4]), math.max(v[2], v[5]), math.max(v[3], v[6]) },
        }
    elseif a == "--anchor" then
        options.anchor = numbers(3)
    elseif a == "--anchor-entity" then
        i = i + 1
        options.anchorEntity = arg[i] or fail("class name expected after " .. a)
    elseif a == "--yaw" then
        options.yaw = number()
    elseif a == "--no-terrain" then
        options.terrain = false
    elseif a == "--terrain-tolerance" then
        options.terrainTolerance = number()
    elseif a == "--no-merge" then
        options.merge = false
    elseif a == "--no-simplify" then
        options.simplify = false
    elseif a == "--simplify-tolerance" then
        options.simplifyTolerance = number()
    elseif a == "--simplify-fill" then
        options.simplifyFill = number()
        if options.simplifyFill <= 0 or options.simplifyFill > 1 then fail("--simplify-fill must be above 0, at most 1") end
    elseif a == "--drop-covered" then
        options.dropCovered = true
    elseif a == "--no-floors-first" then
        options.floorsFirst = false
    elseif a == "--center-first" then
        options.centerFirst = true
    elseif a == "--no-clips" then
        options.clips = false
    elseif a == "--invisible" then
        options.invisible = true
    elseif a == "--clips" then
        options.clips = true
    elseif a == "--sky-clips" then
        options.skyClips = true
    elseif a == "--ungrippable" then
        options.ungrippable = true
    elseif a == "--slab-thickness" then
        options.slabThickness = number()
    elseif a:sub(1, 1) == "-" then
        fail("unknown option " .. a .. "\n" .. USAGE)
    elseif input then
        fail("one map at a time: " .. input .. ", " .. a)
    else
        input = a
    end
    i = i + 1
end
if not input then
    print(USAGE)
    os.exit(1)
end
if options.scale and options.scale <= 0 then fail("--scale must be above 0") end
if options.budget and (options.budget < 1 or options.budget > MGE.MAX_ENV_OBJECTS) then
    fail("--budget must be 1-" .. MGE.MAX_ENV_OBJECTS)
end

local name = input:match("([^/\\]+)$"):gsub("%.[^%.]*$", "")
if not (input:lower():find("%.vmf$") or input:lower():find("%.bsp$")) then
    fail(input .. ": .vmf or .bsp maps only")
end
local file = io.open(input, "rb") or fail("can't read " .. input)
---@cast file -nil
output = output or (MGE.scriptPath .. "assets/obj/" .. name .. ".tbm")

local clock = os.clock()
local ok, map = pcall(MapConv.parse, file, input) -- a .bsp is read in parts, not whole
file:close()
if not ok then fail(input .. ": " .. tostring(map)) end
options.source = input:match("([^/\\]+)$")
local result = MapConv.convert(map, options)

for _, line in ipairs(MapConv.reportLines(result.report)) do print(line) end
if result.report.boxes == 0 then fail("no boxes, nothing written") end
local out = io.open(output, "wb") or fail("can't write " .. output)
out:write(MapConv.toText(result))
out:close()
print(string.format("wrote %s (%.1f s)", output, os.clock() - clock))
