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
---@field objectBudget integer? in game only (ui/map_overlay.lua): how many of the budget's boxes become
---objects, the rest are parked (utils/parking.lua). nil: all of them. The converter itself ignores it
---@field minSize number map units, brushes whose box is smaller on every side are left out (detail)
---@field clips boolean keep player clip brushes (the map's invisible walls, ramps over stairs), colored like
---the map geometry they cover (borrowMaterials)
---@field skyClips boolean with clips: also keep sky clips, the big lids under the open sky (see SKY_CLIP)
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
---@field dropHidden boolean leave out boxes entirely inside another box (Merge.hidden): nothing changes in game
---@field dropCovered boolean also leave out boxes COVERED_SHARE covered by other boxes together
---@field floorsFirst boolean budget order: what can be stood on counts extra (MapConv.priority)
---@field centerFirst boolean budget order: the nearer the region's middle the better (MapConv.priority)
---@field source string? file name written in the header

---@type MapConvOptions
MapConv.DEFAULTS = {
    scale = 0.035,
    budget = 200,
    minSize = 4,
    clips = true, -- ramps over stairs, smoothed corners: much of what players actually walk on
    skyClips = false, -- lids over the map: never what's wanted from clips
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
    dropHidden = true, -- dust2 B site and its approaches: 60 of 247 boxes, mostly stairs inside their ramp clips
    dropCovered = false, -- 33 more there, but the uncovered 5% can be a visible ledge: check the preview
    floorsFirst = true,
    centerFirst = false,
}

-- floorsFirst: the walkable top's area counts this many times extra
local FLOOR_WEIGHT = 3

-- dropCovered: a box goes when at least this share of its inside is covered by other boxes together
local COVERED_SHARE = 0.95
MapConv.COVERED_SHARE = COVERED_SHARE

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
-- a side with one of these: a sky brush (a .bsp marks them itself, MapBrush.sky)
local SKY_ANY = { TOOLSSKYBOX = true, TOOLSSKYBOX2D = true }

-- Sky clips: mappers fill the open parts of the map with huge clip brushes, so players can't jump
-- onto the roofs or out of the map. In Toribash they're giant lids (dust2: up to 2650 x 3100 units,
-- office and nuke: thin 16 unit sheets 250-1150 under the sky). A clip is one when it's
--   wide:     both horizontal sides at least `width` map units (walls and pillars stay)
--   flat:     lower than it is wide (a tall block next to the sky is a wall)
-- and either
--   close:    sky starts at most `gap` above its top over at least `cover` of it (blocks filling
--             the air from the roofs up to the sky, dust2's lids, inferno's roof caps)
-- or
--   floating: on at least `floating` of its footprint nothing solid (terrain too) from `clearance`
--             under it up to its top: nothing to stand on under it, it's not a floor or a ramp
--   open:     on at least `open` of its footprint sky right over it, nothing solid in between (a
--             ceiling clip under a roof stays)
-- Checked on `samples` x `samples` points of its footprint. Measured: the sheets of office and nuke
-- float on 75-100% and are open on 78-100%; dust2's ceiling clip over CT spawn is open on 47%,
-- nuke's clips under roofs on 0%, its clips lying on geometry float on 0-11%
local SKY_CLIP = { width = 256, gap = 256, cover = 0.5, clearance = 72, floating = 0.5, open = 0.5, samples = 6 }

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
---@field lookMaterial string? clips: material of the solid geometry they cover (borrowMaterials)

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
            invisible = 0, skyClip = 0, hidden = 0, covered = 0 },
        simplified = 0,
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

---Bounds of the map's sky brushes, for sky clips (SKY_CLIP)
---@param map MapFile
---@return { min: number[], max: number[] }[]
local function skyBounds(map)
    local skies = {}
    for _, brush in ipairs(map.brushes) do
        local sky = brush.sky
        for _, side in ipairs(brush.sides) do
            if SKY_ANY[shortName(side.material)] then sky = true end
        end
        local geometry = sky and MapConv.Brush.build(brush.sides)
        if geometry then skies[#skies + 1] = { min = geometry.min, max = geometry.max } end
    end
    return skies
end

---World-axis bounds of a box (map units)
---@param box MapBox
---@return number[] min, number[] max
local function boundsOf(box)
    local min, max = {}, {}
    for k = 1, 3 do
        local half = 0
        for j = 1, 3 do half = half + math.abs(box.frame[k][j]) * box.sides[j] / 2 end
        min[k], max[k] = box.center[k] - half, box.center[k] + half
    end
    return min, max
end

local SKY_CELL = 512 -- grid of the solids' footprints, map units

---Leaves out the clips that are lids over the map (SKY_CLIP), once every piece is there: what's under
---a clip can be terrain
---@param pieces MapConvPiece[]
---@param skies { min: number[], max: number[] }[] skyBounds
---@return MapConvPiece[] kept, integer lids
local function dropSkyClips(pieces, skies)
    local candidates = {}
    for _, piece in ipairs(pieces) do
        if piece.role == "clip" then
            local min, max = boundsOf(piece)
            local across = math.min(max[1] - min[1], max[2] - min[2])
            if across >= SKY_CLIP.width and max[3] - min[3] < across then
                candidates[#candidates + 1] = { piece = piece, min = min, max = max }
            end
        end
    end
    if #candidates == 0 or #skies == 0 then return pieces, 0 end

    -- solids by footprint cell
    local grid = {}
    for _, piece in ipairs(pieces) do
        if piece.role ~= "clip" then
            local min, max = boundsOf(piece)
            local entry = { min = min, max = max }
            for x = math.floor(min[1] / SKY_CELL), math.floor(max[1] / SKY_CELL) do
                for y = math.floor(min[2] / SKY_CELL), math.floor(max[2] / SKY_CELL) do
                    local key = x .. "," .. y
                    grid[key] = grid[key] or {}
                    table.insert(grid[key], entry)
                end
            end
        end
    end

    ---Close under the sky: sky starting at most SKY_CLIP.gap over its top covers enough of it
    local function close(min, max)
        local covered = 0
        for _, sky in ipairs(skies) do
            local above = sky.min[3] - max[3]
            if above >= -1 and above <= SKY_CLIP.gap then
                local ox = math.min(sky.max[1], max[1]) - math.max(sky.min[1], min[1])
                local oy = math.min(sky.max[2], max[2]) - math.max(sky.min[2], min[2])
                if ox > 0 and oy > 0 then covered = covered + ox * oy end
            end
        end
        return covered >= SKY_CLIP.cover * (max[1] - min[1]) * (max[2] - min[2])
    end

    local n = SKY_CLIP.samples
    local lids = {}
    for _, c in ipairs(candidates) do
        local min, max = c.min, c.max
        if close(min, max) then lids[c.piece] = true end
        local floating, open = 0, 0
        for i = 0, n - 1 do
            for j = 0, n - 1 do
                local x = min[1] + (i + 0.5) * (max[1] - min[1]) / n
                local y = min[2] + (j + 0.5) * (max[2] - min[2]) / n
                local skyZ = math.huge -- lowest sky bottom over this point
                for _, sky in ipairs(skies) do
                    if x >= sky.min[1] and x <= sky.max[1] and y >= sky.min[2] and y <= sky.max[2]
                        and sky.min[3] >= max[3] - 1 and sky.min[3] < skyZ then skyZ = sky.min[3] end
                end
                local free, clear = true, skyZ < math.huge
                for _, s in ipairs(grid[math.floor(x / SKY_CELL) .. "," .. math.floor(y / SKY_CELL)] or {}) do
                    if x >= s.min[1] and x <= s.max[1] and y >= s.min[2] and y <= s.max[2] then
                        if s.max[3] > min[3] - SKY_CLIP.clearance and s.min[3] < max[3] then free = false end
                        if s.max[3] > max[3] + 1 and s.min[3] < skyZ - 1 then clear = false end
                    end
                end
                if free then floating = floating + 1 end
                if clear then open = open + 1 end
            end
        end
        if floating >= SKY_CLIP.floating * n * n and open >= SKY_CLIP.open * n * n then lids[c.piece] = true end
    end

    local kept, count = {}, 0
    for _, piece in ipairs(pieces) do
        if lids[piece] then count = count + 1 else kept[#kept + 1] = piece end
    end
    return kept, count
end

-- clips borrow the material of solid geometry within this many map units (touching walls, the stairs
-- under a ramp clip); the grid that finds it has cells this wide
local BORROW_MARGIN, BORROW_CELL = 8, 512

---Gives every clip piece the material of the solid piece it overlaps most, counting solids within
---BORROW_MARGIN (a clip along a wall touches it): clip.lookMaterial, the clip's color. Clips have only
---tool textures, but they mostly cover real geometry: stairs, rails, wall corners
---@param pieces MapConvPiece[]
local function borrowMaterials(pieces)
    local grid = {}
    local function cells(min, max, fn)
        for x = math.floor(min[1] / BORROW_CELL), math.floor(max[1] / BORROW_CELL) do
            for y = math.floor(min[2] / BORROW_CELL), math.floor(max[2] / BORROW_CELL) do fn(x .. "," .. y) end
        end
    end
    local clips = {}
    for _, piece in ipairs(pieces) do
        local min, max = boundsOf(piece)
        if piece.role == "clip" then
            clips[#clips + 1] = { piece = piece, min = min, max = max }
        elseif not piece.material:upper():find("^TOOLS/") then
            local entry = { piece = piece, min = min, max = max }
            cells(min, max, function(key)
                grid[key] = grid[key] or {}
                table.insert(grid[key], entry)
            end)
        end
    end
    for _, clip in ipairs(clips) do
        local min, max = {}, {}
        for k = 1, 3 do min[k], max[k] = clip.min[k] - BORROW_MARGIN, clip.max[k] + BORROW_MARGIN end
        local best, bestScore, seen = nil, 0, {}
        cells(min, max, function(key)
            for _, solid in ipairs(grid[key] or {}) do
                if not seen[solid] then
                    seen[solid] = true
                    local volume = 1
                    for k = 1, 3 do
                        local overlap = math.min(max[k], solid.max[k]) - math.max(min[k], solid.min[k])
                        volume = overlap > 0 and volume * overlap or 0
                    end
                    if volume > bestScore then best, bestScore = solid, volume end
                end
            end
        end)
        clip.piece.lookMaterial = best and best.piece.material or nil
    end
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

    -- sky brushes, only needed to leave out sky clips
    local skies = opts.clips and not opts.skyClips and skyBounds(map) or nil

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
    if skies then
        local lids
        pieces, lids = dropSkyClips(pieces, skies)
        report.dropped.skyClip = report.dropped.skyClip + lids
    end
    if opts.clips then borrowMaterials(pieces) end
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
        })
    end
    -- after merging (a merged wall hides more), before the budget (hidden boxes would take its places)
    if opts.dropHidden or opts.dropCovered then
        local hidden, covered
        boxes, hidden, covered = MapConv.Merge.hidden(boxes, opts.dropCovered and COVERED_SHARE or 0)
        report.dropped.hidden = report.dropped.hidden + hidden
        report.dropped.covered = report.dropped.covered + covered
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
        -- clips: the material borrowed from what they cover, plain grey when they touch nothing
        local color = MapConv.colorFor(box.role == "clip" and (box.lookMaterial or "") or box.material)
        objects[i] = {
            kind = "env_obj",
            id = i,
            lines = { { raw = "# " .. (box.brushId:find("^disp") and "" or "brush ") .. box.brushId
                .. (box.merged and (" + " .. (box.merged - 1) .. " merged") or "") .. " "
                .. (box.role == "clip" and ("clip" .. (box.lookMaterial and (" by " .. box.lookMaterial) or "")) or box.material) } },
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
    return map
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
    if d.skyClip > 0 then
        lines[#lines + 1] = d.skyClip .. " sky clips left out (big lids between the roofs and the sky)"
    end
    if d.hidden > 0 or d.covered > 0 then
        lines[#lines + 1] = d.hidden .. " boxes left out inside other boxes"
            .. (d.covered > 0 and (", " .. d.covered .. " covered by others") or "")
    end
    return lines
end

return MapConv
