-- Map converter pipeline: a map (.vmf text or Source .bsp, MapConv.parse) to static env_obj boxes for
-- MGE. Brushes are
-- filtered (triggers, sky, hints... are left out, clips are kept), each kept one becomes a box
-- (boxfit.lua), the biggest ones fit the object budget, then everything is scaled and moved so the
-- anchor ends up at the dojo center on the ground. Needs vmf.lua, bsp.lua, brush.lua, boxfit.lua, MGE.Mat3,
-- MGE.FileHandler and mod_export.lua's constants loaded first. Plan: docs/map-import-plan.md
MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Vec = MapConv.Vec
local Mat3 = MGE.Mat3
local FileHandler = MGE.FileHandler
local formatNumbers = FileHandler.formatNumbers

---@class MapConvOptions
---@field scale number Toribash units per map unit. Source: a player is 72 units, a tori about 2.5
---@field budget integer most boxes written, the biggest are kept
---@field minSize number map units, brushes whose box is smaller on every side are left out (detail)
---@field clips boolean keep player clip brushes (the map's invisible walls), drawn see-through red
---@field props boolean solid props (crates, doors, cars) as boxes, sized by their models (props.lua)
---@field invisible boolean keep solid brushes nobody sees (only nodraw and other undrawn tool textures)
---@field ungrippable boolean flag the boxes ungrippable too
---@field slabError number see BoxFitOptions
---@field slabThickness number map units
---@field yaw number degrees the map is turned around the anchor
---@field region { min: number[], max: number[] }? map units, only brushes centered inside are kept
---@field anchor number[]? map point that goes to the dojo center at ground height
---@field anchorEntity string? without anchor: the first entity of this class is the anchor
---@field terrain boolean convert terrain (.bsp displacements) to slabs
---@field terrainTolerance number see TerrainFitOptions
---@field merge boolean join boxes that make one bigger box (merge.lua) before the budget
---@field simplify boolean also join nearly flat neighbouring slabs (Merge.flat): terrain floors, floor tiles
---@field simplifyTolerance number map units a joined slab may be thicker than its parts (bumps, tilt)
---@field simplifyFill number share of a joined slab its parts must cover, 0-1
---@field simplifyShell number map units: strips of one ledge (top, face, lip) join into a solid block up to this big across, 0 off
---@field floorsFirst boolean budget order: what can be stood on counts extra (MapConv.priority)
---@field centerFirst boolean budget order: the nearer the region's middle the better (MapConv.priority)
---@field source string? file name written in the header

---@type MapConvOptions
MapConv.DEFAULTS = {
    scale = 0.035,
    budget = 200,
    minSize = 4,
    clips = false, -- invisible walls are rarely useful in Toribash
    props = true,
    invisible = false,
    ungrippable = false,
    slabError = 0.2,
    slabThickness = 8,
    yaw = 0,
    anchorEntity = "info_player_terrorist",
    terrain = true,
    terrainTolerance = 8,
    merge = true,
    simplify = true,
    simplifyTolerance = 12,
    simplifyFill = 0.75, -- edges must line up, so this only limits gaps between parts
    simplifyShell = 96, -- the strips must touch, so it only fills a ledge's inside corner, never a corridor
    floorsFirst = true,
    centerFirst = false,
}

-- floorsFirst: the walkable top's area counts this many times extra
local FLOOR_WEIGHT = 3

-- marks an asset file whose objects keep their positions on import (ui/assets.lua)
local KEEP_POSITION_TAG = MGE.KEEP_POSITION_TAG

-- brush entities that aren't solid for players: volumes, markers, effects
local DROP_CLASSES = {
    func_buyzone = true, func_bomb_target = true, func_hostage_rescue = true, func_no_defuse = true,
    func_areaportal = true, func_areaportalwindow = true, func_illusionary = true, func_occluder = true,
    func_precipitation = true, func_dustmotes = true, func_dustcloud = true, func_smokevolume = true,
    func_viscluster = true, func_ladder = true, func_clip_vphysics = true, func_vehicleclip = true,
}
local DROP_PREFIXES = { "trigger_", "env_", "info_", "fog_", "light", "point_" }

-- tool materials, by the last part of the name in upper case. Any side with one of these drops the
-- brush (sky shells and hints come with nodraw / skip on their other sides)
local DROP_ANY = {
    TOOLSTRIGGER = true, TOOLSSKYBOX = true, TOOLSSKYBOX2D = true, TOOLSHINT = true,
    TOOLSAREAPORTAL = true, TOOLSOCCLUDER = true, TOOLSFOG = true,
}
-- drop the brush when all its sides are these: not solid for players
local DROP_ALL = {
    TOOLSSKIP = true, TOOLSBLOCKLIGHT = true, TOOLSBLOCKBULLETS = true, TOOLSNPCCLIP = true,
    TOOLSBLOCK_LOS = true, TOOLSINVISIBLELADDER = true,
}
-- all sides these: an invisible wall
local CLIP_ALL = { TOOLSPLAYERCLIP = true, TOOLSCLIP = true }

---@param material string
---@return string last part of the name, upper case
local function shortName(material)
    return (material:match("([^/\\]+)$") or material):upper()
end

---@param class string
---@return boolean
local function droppedClass(class)
    if DROP_CLASSES[class] then return true end
    for _, prefix in ipairs(DROP_PREFIXES) do
        if class:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- tool textures that are seen in the game: a brush with only these isn't invisible
local VISIBLE_TOOLS = { TOOLSBLACK = true, TOOLSWHITE = true }

---Every side has a tool texture that isn't drawn (nodraw, invisible, block...): nobody sees the
---brush in the game. The map's sealing shell, roof caps, the backs of terrain walls
---@param brush MapBrush
---@return boolean
local function invisible(brush)
    if #brush.sides == 0 then return false end
    for _, side in ipairs(brush.sides) do
        if not side.material:upper():find("^TOOLS/") or VISIBLE_TOOLS[shortName(side.material)] then return false end
    end
    return true
end

---What a brush is for. Trigger, sky, hint... textures drop it whatever the map's flags say (a .bsp
---can have trigger volumes marked solid, dust2 has big ones high up), an invisible solid brush is
---dropped unless options.invisible
---@param brush MapBrush
---@param options MapConvOptions?
---@return "solid"|"clip"|"drop" role
---@return string? reason when dropped
function MapConv.brushRole(brush, options)
    if droppedClass(brush.entity) then return "drop", "entity" end
    local allDrop, allClip = true, true
    for _, side in ipairs(brush.sides) do
        local name = shortName(side.material)
        if DROP_ANY[name] then return "drop", "tool" end
        if not DROP_ALL[name] then allDrop = false end
        if not CLIP_ALL[name] then allClip = false end
    end
    ---@type "solid"|"clip"|"drop", string?
    local role, reason
    if brush.role then
        role, reason = brush.role, brush.reason -- the reader knew (.bsp contents flags)
    elseif allDrop then
        role, reason = "drop", "tool"
    elseif allClip then
        role = "clip"
    else
        role = "solid"
    end
    if role == "solid" and not (options and options.invisible) and invisible(brush) then return "drop", "invisible" end
    return role --[[@as "solid"|"clip"|"drop"]], reason
end

-- box colors by material name: first rule whose word is in the (lower case) name
local COLOR_RULES = {
    { "sand", { 0.86, 0.76, 0.54 } }, { "dirt", { 0.62, 0.48, 0.33 } }, { "ground", { 0.62, 0.48, 0.33 } },
    { "grass", { 0.40, 0.55, 0.28 } }, { "wood", { 0.55, 0.38, 0.22 } }, { "crate", { 0.55, 0.38, 0.22 } },
    { "metal", { 0.46, 0.49, 0.53 } }, { "brick", { 0.66, 0.40, 0.30 } }, { "stone", { 0.62, 0.60, 0.56 } },
    { "concrete", { 0.62, 0.62, 0.60 } }, { "rock", { 0.55, 0.52, 0.48 } }, { "tile", { 0.80, 0.78, 0.72 } },
    { "plaster", { 0.88, 0.82, 0.70 } }, { "wall", { 0.84, 0.76, 0.60 } },
}
local DEFAULT_COLOR = { 0.70, 0.70, 0.70, 1 }
local TOOL_COLOR = { 0.35, 0.35, 0.35, 1 } -- nodraw and other tool faces, solid but never seen in the map
local CLIP_COLOR = { 1.00, 0.20, 0.20, 0.30 }

---@param material string
---@return number[] r g b a
function MapConv.colorFor(material)
    local name = material:lower()
    if name:find("^tools/") then return TOOL_COLOR end
    for _, rule in ipairs(COLOR_RULES) do
        if name:find(rule[1], 1, true) then return { rule[2][1], rule[2][2], rule[2][3], 1 } end
    end
    return DEFAULT_COLOR
end

---Material of the biggest face that isn't a tool texture, else of the biggest face
---@param geometry MapGeometry
---@return string
local function mainMaterial(geometry)
    local best, bestTool
    for _, face in ipairs(geometry.faces) do
        local tool = face.material:upper():find("^TOOLS/") ~= nil
        if tool then
            if not bestTool or face.area > bestTool.area then bestTool = face end
        elseif not best or face.area > best.area then
            best = face
        end
    end
    return (best or bestTool or { material = "" }).material
end

---@param geometry { min: number[], max: number[] } bounds (MapGeometry has them)
---@param region { min: number[], max: number[] }
---@return boolean
local function inRegion(geometry, region)
    for k = 1, 3 do
        local c = (geometry.min[k] + geometry.max[k]) / 2
        if c < region.min[k] or c > region.max[k] then return false end
    end
    return true
end

---@class MapConvBox: MapBox
---@field role "solid"|"clip"
---@field material string
---@field brushId string
---@field merged integer? how many pieces merge.lua joined into it

---Highest point of a box above its center, along world Z
---@param box MapBox
---@return number
local function halfHeight(box)
    local h = 0
    for k = 1, 3 do h = h + math.abs(box.frame[3][k]) * box.sides[k] / 2 end
    return h
end
MapConv.halfHeight = halfHeight -- the placement view puts the lowest point on the ground

---Where the map goes: the given point, else the anchor entity (inside the region, when there is one),
---else the middle of the kept boxes at their lowest point
---@param map MapFile
---@param boxes MapConvBox[]
---@param options MapConvOptions
---@return number[] anchor
---@return string how it was picked
local function pickAnchor(map, boxes, options)
    if options.anchor then return options.anchor, "given" end
    if options.anchorEntity then
        for _, entity in ipairs(map.entities) do
            local o = entity.origin
            if entity.classname == options.anchorEntity and o then
                local r = options.region
                if not r or (o[1] >= r.min[1] and o[1] <= r.max[1] and o[2] >= r.min[2] and o[2] <= r.max[2]
                        and o[3] >= r.min[3] and o[3] <= r.max[3]) then
                    return o, options.anchorEntity
                end
            end
        end
    end
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, box in ipairs(boxes) do
        local h = halfHeight(box)
        for k = 1, 2 do
            min[k] = math.min(min[k], box.center[k])
            max[k] = math.max(max[k], box.center[k])
        end
        min[3] = math.min(min[3], box.center[3] - h)
    end
    if #boxes == 0 then return { 0, 0, 0 }, "none" end
    return { (min[1] + max[1]) / 2, (min[2] + max[2]) / 2, min[3] }, "lowest point"
end

---@class MapConvReport
---@field brushes integer count in the map
---@field dropped table<string, integer> reason: entity, tool, clip, region, broken, small, budget
---@field displacements integer kept brushes with terrain on a face (converted as their plain brush)
---@field terrain integer terrain grids of a .bsp converted (or left out with the terrain option off)
---@field terrainSlabs integer slabs they made, before merging
---@field merged integer boxes that went into another (merge.lua)
---@field simplified integer slabs that went into another by Simplify (Merge.flat)
---@field props integer props made into boxes
---@field propsNoModel integer solid props whose model size wasn't found (game files not read)
---@field boxes integer written
---@field slabs integer of them, ramps (brushes)
---@field terrainBoxes integer of them, from terrain
---@field roughFits integer of them, boxes more than half empty
---@field belowGround integer of them, entirely under the ground (z 0), the game's floor can't be removed
---@field anchor number[]
---@field anchorFrom string

---@class MapConvResult
---@field objects FileParserEnvObj[] static boxes, ids 1..n (the import gives them real ids)
---@field report MapConvReport
---@field header string[] comment lines for the asset file

---@class MapConvPiece: MapConvBox
---@field at number[] middle of the brush / terrain grid it came from, what the region tests

---@param options MapConvOptions?
---@return MapConvOptions options with MapConv.DEFAULTS for the missing fields
function MapConv.withDefaults(options)
    local opts = {}
    for k, v in pairs(MapConv.DEFAULTS) do opts[k] = v end
    for k, v in pairs(options or {}) do opts[k] = v end
    return opts
end

---@return MapConvReport empty counts
local function newReport()
    return {
        brushes = 0,
        dropped = { entity = 0, tool = 0, clip = 0, region = 0, broken = 0, small = 0, budget = 0, terrain = 0,
            propsOff = 0, propNotSolid = 0, propSkipped = 0, invisible = 0 },
        props = 0, propsNoModel = 0, simplified = 0,
        displacements = 0, terrain = 0, terrainSlabs = 0, terrainBoxes = 0, merged = 0, boxes = 0, slabs = 0,
        roughFits = 0, belowGround = 0, anchor = { 0, 0, 0 }, anchorFrom = "",
    }
end

---@param report MapConvReport
---@return MapConvReport copy with its own dropped counts
local function copyReport(report)
    local copy = {}
    for k, v in pairs(report) do copy[k] = v end
    copy.dropped = {}
    for k, v in pairs(report.dropped) do copy.dropped[k] = v end
    return copy
end

---Every brush and terrain slab of the map as a box in map units, before region, merging and budget.
---The slow part (brush geometry, terrain): done once per map and options, MapConv.select then picks
---from the pieces as often as needed (the map placement view does on every region change)
---@param map MapFile
---@param options MapConvOptions? uses clips, terrain, terrainTolerance, slabError, slabThickness
---@return MapConvPiece[] pieces
---@return MapConvReport report counts so far, MapConv.select and MapConv.objects add theirs
function MapConv.pieces(map, options)
    local opts = MapConv.withDefaults(options)
    local report = newReport()
    report.brushes = #map.brushes
    local function drop(reason) report.dropped[reason] = report.dropped[reason] + 1 end
    local function middle(bounds)
        return { (bounds.min[1] + bounds.max[1]) / 2, (bounds.min[2] + bounds.max[2]) / 2, (bounds.min[3] + bounds.max[3]) / 2 }
    end

    ---@type MapConvPiece[]
    local pieces = {}
    for _, brush in ipairs(map.brushes) do
        local role, reason = MapConv.brushRole(brush, opts)
        if role == "drop" then
            drop(reason)
        elseif role == "clip" and not opts.clips then
            drop("clip")
        else
            local geometry = MapConv.Brush.build(brush.sides)
            if not geometry then
                drop("broken")
            else
                local box = MapConv.BoxFit.fit(geometry, opts) --[[@as MapConvPiece]]
                box.role = role --[[@as "solid"|"clip"]]
                box.material = mainMaterial(geometry)
                box.brushId = brush.id
                box.at = middle(geometry)
                for _, side in ipairs(brush.sides) do
                    if side.displacement then
                        report.displacements = report.displacements + 1
                        break
                    end
                end
                pieces[#pieces + 1] = box
            end
        end
    end

    -- terrain (.bsp displacements): slabs under each grid
    for _, terrain in ipairs(map.terrain or {}) do
        if not opts.terrain then
            drop("terrain")
        else
            local bounds = { min = { math.huge, math.huge, math.huge }, max = { -math.huge, -math.huge, -math.huge } }
            for _, p in ipairs(terrain.points) do
                for k = 1, 3 do
                    if p[k] < bounds.min[k] then bounds.min[k] = p[k] end
                    if p[k] > bounds.max[k] then bounds.max[k] = p[k] end
                end
            end
            local at = middle(bounds)
            report.terrain = report.terrain + 1
            for _, slab in ipairs(MapConv.BoxFit.terrain(terrain, opts)) do
                local box = slab --[[@as MapConvPiece]]
                box.role, box.material, box.brushId, box.at = "solid", terrain.material, terrain.id, at
                pieces[#pieces + 1] = box
                report.terrainSlabs = report.terrainSlabs + 1
            end
        end
    end
    -- props (crates, doors, cars): a box each from its model's size (props.lua, Props.resolve sets them)
    for _, prop in ipairs(map.props or {}) do
        if not opts.props then
            drop("propsOff")
        elseif not prop.solid then
            drop("propNotSolid")
        elseif MapConv.Props.skipped(prop.model) then
            drop("propSkipped")
        elseif not prop.mins then
            report.propsNoModel = report.propsNoModel + 1
        else
            local box = MapConv.Props.box(prop) --[[@as MapConvPiece]]
            box.role, box.material, box.brushId, box.at = "solid", prop.model, prop.id, box.center
            pieces[#pieces + 1] = box
            report.props = report.props + 1
        end
    end
    return pieces, report
end

---Score for the budget: the biggest surface of a box. Floors and walls make the map, small details
---go when it's full
---@param box MapBox
---@return number
function MapConv.score(box)
    local s = { box.sides[1], box.sides[2], box.sides[3] }
    table.sort(s)
    return s[2] * s[3]
end

---Area of the box's top that can be stood on: the face whose normal is within ~45 degrees of up (a
---floor's or ramp's top; a wall's thin top edge gives little), 0 when no face points that way
---@param box MapBox
---@return number
function MapConv.walkableArea(box)
    local area = 0
    for k = 1, 3 do
        if math.abs(box.frame[3][k]) >= 0.7 then
            local a, b = k % 3 + 1, (k + 1) % 3 + 1
            area = math.max(area, box.sides[a] * box.sides[b])
        end
    end
    return area
end

---Budget order of a box, bigger first: MapConv.score. With floorsFirst its walkable top counts
---FLOOR_WEIGHT times extra, so a floor beats an equally big wall (a ceiling slab's top counts too:
---a lower region leaves those out). With centerFirst it's divided down by its distance across from
---the region's middle: half at the middle of the region's side, a third at its corner
---@param box MapBox
---@param options MapConvOptions
---@return number
function MapConv.priority(box, options)
    local score = MapConv.score(box)
    if options.floorsFirst then score = score + FLOOR_WEIGHT * MapConv.walkableArea(box) end
    local r = options.region
    if options.centerFirst and r then
        local cx, cy = (r.min[1] + r.max[1]) / 2, (r.min[2] + r.max[2]) / 2
        local reach = math.max(r.max[1] - r.min[1], r.max[2] - r.min[2], 1) / 2
        local dx, dy = box.center[1] - cx, box.center[2] - cy
        score = score / (1 + (dx * dx + dy * dy) / (reach * reach))
    end
    return score
end

---The boxes a conversion writes: pieces in the region (by where they came from), merged, without
---the small ones, the biggest first up to the budget
---@param pieces MapConvPiece[]
---@param options MapConvOptions? uses region, merge, minSize, budget
---@param report MapConvReport? from MapConv.pieces, copied with this step's counts added
---@return MapConvBox[] kept the biggest, at most options.budget
---@return MapConvBox[] cut over the budget, biggest first
---@return MapConvReport report
function MapConv.select(pieces, options, report)
    local opts = MapConv.withDefaults(options)
    report = report and copyReport(report) or newReport()
    local function drop(reason) report.dropped[reason] = report.dropped[reason] + 1 end

    local boxes = {}
    local region = opts.region
    for _, piece in ipairs(pieces) do
        if region and not inRegion({ min = piece.at, max = piece.at }, region) then
            drop("region")
        else
            boxes[#boxes + 1] = piece
        end
    end
    report.merged, report.simplified = 0, 0
    if opts.merge then boxes, report.merged = MapConv.Merge.boxes(boxes) end
    if opts.simplify then
        -- slab thickness limit: terrain slabs and floor brushes, not crates or wall blocks
        boxes, report.simplified = MapConv.Merge.flat(boxes, {
            tolerance = opts.simplifyTolerance, fill = opts.simplifyFill, gap = 16, align = 32, maxThickness = 32,
            shell = opts.simplifyShell,
        })
    end
    -- small ones go after merging: a row of small pieces can make one big box
    local sized = {}
    for _, box in ipairs(boxes) do
        if math.max(box.sides[1], box.sides[2], box.sides[3]) < opts.minSize then
            drop("small")
        else
            sized[#sized + 1] = box
        end
    end
    local scores = {}
    for _, box in ipairs(sized) do scores[box] = MapConv.priority(box, opts) end
    table.sort(sized, function(a, b) return scores[a] > scores[b] end)
    local kept, cut = {}, {}
    for i, box in ipairs(sized) do
        if i <= opts.budget then kept[#kept + 1] = box else cut[#cut + 1] = box end
    end
    report.dropped.budget = report.dropped.budget + #cut
    return kept, cut, report
end

---Where the map goes in the world, see pickAnchor
---@param map MapFile
---@param boxes MapConvBox[] the kept ones, for the fallback
---@param options MapConvOptions?
---@return number[] anchor
---@return string how it was picked
function MapConv.anchorFor(map, boxes, options)
    return pickAnchor(map, boxes, MapConv.withDefaults(options))
end

---A map box in the world: the anchor goes to the dojo center on the ground, turned by yaw around it
---and scaled
---@param box MapBox
---@param anchor number[]
---@param options { scale: number, yaw: number }
---@return number[] pos
---@return number[][] frame
---@return number[] sides
function MapConv.toWorld(box, anchor, options)
    local turn = Mat3.rotZ(math.rad(options.yaw))
    local p = Mat3.apply(turn, Vec.scale(Vec.sub(box.center, anchor), options.scale))
    local origin = MGE.POS_ORIGIN
    local sides = {}
    for k = 1, 3 do sides[k] = math.max(box.sides[k] * options.scale, MGE.MIN_SIDE) end
    return { p[1] + origin[1], p[2] + origin[2], p[3] }, Mat3.mul(turn, box.frame), sides
end

---A world point back in map units, the inverse of MapConv.toWorld's placement
---@param point number[]
---@param anchor number[]
---@param options { scale: number, yaw: number }
---@return number[]
function MapConv.toMap(point, anchor, options)
    local origin = MGE.POS_ORIGIN
    local back = Mat3.apply(Mat3.transpose(Mat3.rotZ(math.rad(options.yaw))),
        { point[1] - origin[1], point[2] - origin[2], point[3] })
    return Vec.add(anchor, Vec.scale(back, 1 / options.scale))
end

---Static env_obj objects for kept boxes
---@param boxes MapConvBox[]
---@param anchor number[]
---@param options MapConvOptions?
---@param report MapConvReport? its written-box counts are filled in
---@return FileParserEnvObj[]
function MapConv.objects(boxes, anchor, options, report)
    local opts = MapConv.withDefaults(options)
    local flag = MGE.FLAGS.STATIC + (opts.ungrippable and MGE.FLAGS.UNGRIPPABLE or 0)
    local objects = {}
    for i, box in ipairs(boxes) do
        local pos, frame, sides = MapConv.toWorld(box, anchor, opts)
        -- the game reads rot x y z as Rx(-x) Ry(-y) Rz(-z) (Transforms.orientationOf)
        local ax, ay, az = Mat3.toEulerXYZ(frame)
        if report then
            if pos[3] + halfHeight(box) * opts.scale < 0 then report.belowGround = report.belowGround + 1 end
            if box.brushId:find("^disp") then
                report.terrainBoxes = report.terrainBoxes + 1
            elseif box.kind == "slab" then
                report.slabs = report.slabs + 1
            end
            if box.kind == "box" and box.fitError > 0.5 then report.roughFits = report.roughFits + 1 end
        end
        local color = box.role == "clip" and CLIP_COLOR or MapConv.colorFor(box.material)
        objects[i] = {
            kind = "env_obj",
            id = i,
            lines = { { raw = "# " .. ((box.brushId:find("^disp") or box.brushId:find("^prop") or box.brushId:find("^entity")) and "" or "brush ") .. box.brushId
                .. (box.merged and (" + " .. (box.merged - 1) .. " merged") or "") .. " "
                .. (box.role == "clip" and "clip" or box.material) } },
            props = {
                shape = "box",
                pos = formatNumbers(pos[1], pos[2], pos[3]),
                rot = formatNumbers(-math.deg(ax), -math.deg(ay), -math.deg(az)),
                sides = formatNumbers(sides[1], sides[2], sides[3]),
                color = formatNumbers(color[1], color[2], color[3], color[4]),
                flag = tostring(flag),
                mass = "0.1000",
                bounce = "0.100000",
                friction = "10000.00",
                visible = "1",
            },
        }
    end
    if report then report.boxes = #objects end
    return objects
end

---Whole conversion: pieces, select, anchor, objects
---@param map MapFile
---@param options MapConvOptions? missing fields come from MapConv.DEFAULTS
---@param pieces MapConvPiece[]? from MapConv.pieces with the same options, saves redoing them
---@param piecesReport MapConvReport? the report that came with those pieces
---@return MapConvResult
function MapConv.convert(map, options, pieces, piecesReport)
    local opts = MapConv.withDefaults(options)
    if not pieces then pieces, piecesReport = MapConv.pieces(map, opts) end
    local kept, _, report = MapConv.select(pieces, opts, piecesReport)
    local anchor, anchorFrom = pickAnchor(map, kept, opts)
    report.anchor, report.anchorFrom = anchor, anchorFrom
    local objects = MapConv.objects(kept, anchor, opts, report)
    local header = {
        "# converted by MGE mapconv" .. (opts.source and (" from " .. opts.source) or ""),
        "# scale " .. FileHandler.formatNumber(opts.scale) .. ", yaw " .. FileHandler.formatNumber(opts.yaw)
            .. ", anchor " .. formatNumbers(anchor[1], anchor[2], anchor[3]) .. " (" .. anchorFrom .. ")",
        KEEP_POSITION_TAG,
        "",
    }
    return { objects = objects, report = report, header = header }
end

---The asset file's text (FileHandler writes it like any mod)
---@param result MapConvResult
---@return string
function MapConv.toText(result)
    return FileHandler.modText({ ignores = result.header, env_obj = result.objects, env_obj_joint = {} }) .. "\n"
end

---Map to brushes and entities, by format: Source .bsp (a .bsp name or a VBSP header, errors on a
---broken one) or .vmf. From an open file (binary mode) only the parts a .bsp needs are read
---@param source string|userdata the whole file's contents, or the open file (io.open)
---@param name string? file name, a .bsp never goes to the .vmf reader
---@return MapFile
function MapConv.parse(source, name)
    local Bsp = MapConv.Bsp
    local read, size
    if type(source) == "string" then
        read, size = Bsp.stringReader(source)
    else
        read, size = Bsp.fileReader(source)
    end
    local map
    if read(0, 4) == "VBSP" or tostring(name or ""):lower():find("%.bsp$") then
        map = Bsp.parse(read, size)
    else
        map = MapConv.Vmf.parse(read(0, size))
    end
    MapConv.Props.addEntityProps(map) -- prop entities (doors, physics crates; .vmf: static props too)
    return map
end

---Gives the map's props their model sizes (props.lua): from the cache text, else from the map's own
---packed files and the game archives at archivePaths (opened with open). Call it while the map's
---file is still open when it's a .bsp read from a file (the packed files are read from it)
---@param map MapFile
---@param source string|any the same source MapConv.parse had
---@param options { cacheText: string?, archivePaths: string[]?, open: (fun(path: string): any?)? }
---@return PropResolveResult result
---@return string? cacheText new text for the cache file when it changed
function MapConv.resolveProps(map, source, options)
    local Props = MapConv.Props
    local cache = Props.readCache(options.cacheText)
    local result = Props.resolve(map.props or {}, cache, function()
        local sources, closers = {}, {}
        if map.pakfile then
            local read = type(source) == "string" and MapConv.Bsp.stringReader(source) or MapConv.Bsp.fileReader(source)
            local zip = Props.zipSource(read, map.pakfile.offset, map.pakfile.length)
            if zip then sources[#sources + 1] = zip end
        end
        for _, path in ipairs(options.archivePaths or {}) do
            local vpk, close = Props.vpkSource(path, options.open or function(p) return io.open(p, "rb") end)
            if vpk then
                sources[#sources + 1] = vpk
                closers[#closers + 1] = close
            end
        end
        return sources, function() for _, close in ipairs(closers) do close() end end
    end)
    return result, result.read and Props.cacheText(cache) or nil
end

-- file types MapConv.parse reads, for file pickers and checks
MapConv.EXTENSIONS = { "vmf", "bsp" }

---Summary lines for the console
---@param report MapConvReport
---@return string[]
function MapConv.reportLines(report)
    local d = report.dropped
    local lines = {
        report.brushes .. " brushes, " .. report.boxes .. " boxes written (" .. report.terrainBoxes .. " terrain, "
            .. report.slabs .. " ramp slabs, "
            .. report.roughFits .. " rough fits)",
        "left out: " .. d.budget .. " over the budget, " .. d.small .. " small, " .. d.region .. " outside the region, "
            .. d.entity .. " non-solid entities, " .. d.tool .. " tool brushes, " .. d.invisible .. " invisible brushes, "
            .. d.clip .. " clips, " .. d.broken .. " broken",
        "anchor " .. formatNumbers(report.anchor[1], report.anchor[2], report.anchor[3]) .. " (" .. report.anchorFrom .. ")"
            .. (report.belowGround > 0 and (", " .. report.belowGround .. " boxes are under the ground: lower the anchor") or ""),
    }
    if report.displacements > 0 then
        lines[#lines + 1] = report.displacements .. " brushes have terrain (displacements), converted as plain brushes"
    end
    if report.simplified > 0 then
        lines[#lines + 1] = "simplify joined " .. report.simplified .. " nearly flat slabs (floors, terrain) into bigger ones"
    end
    if report.terrain > 0 or report.merged > 0 then
        lines[#lines + 1] = report.terrain .. " terrain grids made " .. report.terrainSlabs .. " slabs, merging joined "
            .. report.merged .. " boxes into others"
    end
    if d.terrain > 0 then lines[#lines + 1] = d.terrain .. " terrain grids left out (terrain off)" end
    if report.props > 0 or report.propsNoModel > 0 then
        lines[#lines + 1] = report.props .. " props (crates, doors, cars...) as boxes, " .. d.propNotSolid .. " not solid, "
            .. d.propSkipped .. " plants, cables, frames, arches left out"
            .. (report.propsNoModel > 0 and (", " .. report.propsNoModel .. " without a model size (game files not found)") or "")
    end
    return lines
end

return MapConv
