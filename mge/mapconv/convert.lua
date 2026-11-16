





MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Vec = MapConv.Vec
local Mat3 = MGE.Mat3
local FileHandler = MGE.FileHandler
local formatNumbers = FileHandler.formatNumbers




























MapConv.DEFAULTS = {
    scale = 0.035,
    budget = 200,
    minSize = 4,
    clips = true,
    skyClips = false,
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
    simplifyFill = 0.75,
    dropHidden = true,
    dropCovered = false,
}


local FLOOR_WEIGHT = 3


local COVERED_SHARE = 0.95
MapConv.COVERED_SHARE = COVERED_SHARE



local DROP_CLASSES = {
    func_buyzone = true, func_bomb_target = true, func_hostage_rescue = true, func_no_defuse = true,
    func_areaportal = true, func_areaportalwindow = true, func_illusionary = true, func_occluder = true,
    func_precipitation = true, func_dustmotes = true, func_dustcloud = true, func_smokevolume = true,
    func_viscluster = true, func_ladder = true, func_clip_vphysics = true, func_vehicleclip = true,
}
local DROP_PREFIXES = { "trigger_", "env_", "info_", "fog_", "light", "point_" }



local DROP_ANY = {
    TOOLSTRIGGER = true, TOOLSSKYBOX = true, TOOLSSKYBOX2D = true, TOOLSHINT = true,
    TOOLSAREAPORTAL = true, TOOLSOCCLUDER = true, TOOLSFOG = true,
}

local DROP_ALL = {
    TOOLSSKIP = true, TOOLSBLOCKLIGHT = true, TOOLSBLOCKBULLETS = true, TOOLSNPCCLIP = true,
    TOOLSBLOCK_LOS = true, TOOLSINVISIBLELADDER = true,
}

local CLIP_ALL = { TOOLSPLAYERCLIP = true, TOOLSCLIP = true }

local SKY_ANY = { TOOLSSKYBOX = true, TOOLSSKYBOX2D = true }




local function shortName(material)
    return (material:match("([^/\\]+)$") or material):upper()
end



local function droppedClass(class)
    if DROP_CLASSES[class] then return true end
    for _, prefix in ipairs(DROP_PREFIXES) do
        if class:sub(1, #prefix) == prefix then return true end
    end
    return false
end


local VISIBLE_TOOLS = { TOOLSBLACK = true, TOOLSWHITE = true }





local function invisible(brush)
    if #brush.sides == 0 then return false end
    for _, side in ipairs(brush.sides) do
        if not side.material:upper():find("^TOOLS/") or VISIBLE_TOOLS[shortName(side.material)] then return false end
    end
    return true
end








function MapConv.brushRole(brush, options)

    if droppedClass(brush.entity) or brush.nonSolid then return "drop", "entity" end
    local allDrop, allClip = true, true
    for _, side in ipairs(brush.sides) do
        local name = shortName(side.material)
        if DROP_ANY[name] then return "drop", "tool" end
        if not DROP_ALL[name] then allDrop = false end
        if not CLIP_ALL[name] then allClip = false end
    end

    local role, reason
    if brush.role then
        role, reason = brush.role, brush.reason
    elseif allDrop then
        role, reason = "drop", "tool"
    elseif allClip then
        role = "clip"
    else
        role = "solid"
    end
    if role == "solid" and not (options and options.invisible) and invisible(brush) then return "drop", "invisible" end
    return role , reason
end


local COLOR_RULES = {
    { "sand", { 0.86, 0.76, 0.54 } }, { "dirt", { 0.62, 0.48, 0.33 } }, { "ground", { 0.62, 0.48, 0.33 } },
    { "grass", { 0.40, 0.55, 0.28 } }, { "wood", { 0.55, 0.38, 0.22 } }, { "crate", { 0.55, 0.38, 0.22 } },
    { "metal", { 0.46, 0.49, 0.53 } }, { "brick", { 0.66, 0.40, 0.30 } }, { "stone", { 0.62, 0.60, 0.56 } },
    { "concrete", { 0.62, 0.62, 0.60 } }, { "rock", { 0.55, 0.52, 0.48 } }, { "tile", { 0.80, 0.78, 0.72 } },
    { "plaster", { 0.88, 0.82, 0.70 } }, { "wall", { 0.84, 0.76, 0.60 } },
}
local DEFAULT_COLOR = { 0.70, 0.70, 0.70, 1 }
local TOOL_COLOR = { 0.35, 0.35, 0.35, 1 }



function MapConv.colorFor(material)
    local name = material:lower()
    if name:find("^tools/") then return TOOL_COLOR end
    for _, rule in ipairs(COLOR_RULES) do
        if name:find(rule[1], 1, true) then return { rule[2][1], rule[2][2], rule[2][3], 1 } end
    end
    return DEFAULT_COLOR
end




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




local function inRegion(geometry, region)
    for k = 1, 3 do
        local c = (geometry.min[k] + geometry.max[k]) / 2
        if c < region.min[k] or c > region.max[k] then return false end
    end
    return true
end












local function halfHeight(box)
    local h = 0
    for k = 1, 3 do h = h + math.abs(box.frame[3][k]) * box.sides[k] / 2 end
    return h
end
MapConv.halfHeight = halfHeight








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



























function MapConv.withDefaults(options)
    local opts = {}
    for k, v in pairs(MapConv.DEFAULTS) do opts[k] = v end
    for k, v in pairs(options or {}) do opts[k] = v end
    return opts
end


local function newReport()
    return {
        brushes = 0,
        dropped = { entity = 0, tool = 0, clip = 0, region = 0, broken = 0, small = 0, budget = 0, terrain = 0,
            invisible = 0, skyClip = 0, hidden = 0, covered = 0 },
        simplified = 0,
        displacements = 0, terrain = 0, terrainSlabs = 0, terrainBoxes = 0, merged = 0, boxes = 0, slabs = 0,
        roughFits = 0, belowGround = 0, anchor = { 0, 0, 0 }, anchorFrom = "", roofs = 0,
    }
end



local function copyReport(report)
    local copy = {}
    for k, v in pairs(report) do copy[k] = v end
    copy.dropped = {}
    for k, v in pairs(report.dropped) do copy.dropped[k] = v end
    return copy
end




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

local boundsMemo




local function boundsOf(box)
    local known = boundsMemo and boundsMemo[box]
    if known then return known[1], known[2] end
    local min, max = {}, {}
    for k = 1, 3 do
        local half = 0
        for j = 1, 3 do half = half + math.abs(box.frame[k][j]) * box.sides[j] / 2 end
        min[k], max[k] = box.center[k] - half, box.center[k] + half
    end
    if boundsMemo then boundsMemo[box] = { min, max } end
    return min, max
end

local SKY_CELL = 512
local cellKey = MapConv.Merge.cellKey

MapConv.boundsOf = boundsOf












local ROOF = { open = 0.5, samples = 6, support = 8 }





function MapConv.solidsGrid(pieces)
    local grid = {}
    for _, piece in ipairs(pieces) do
        if piece.role ~= "clip" then
            local min, max = boundsOf(piece)
            local entry = { min = min, max = max }
            for x = math.floor(min[1] / SKY_CELL), math.floor(max[1] / SKY_CELL) do
                for y = math.floor(min[2] / SKY_CELL), math.floor(max[2] / SKY_CELL) do
                    local key = cellKey(x, y)
                    grid[key] = grid[key] or {}
                    table.insert(grid[key], entry)
                end
            end
        end
    end
    return grid
end

local NO_SOLIDS = {}



function MapConv.solidsAt(grid, x, y)
    return grid[cellKey(math.floor(x / SKY_CELL), math.floor(y / SKY_CELL))] or NO_SOLIDS
end






local function keepRoofs(pieces, candidates, skies)
    if #candidates == 0 or #skies == 0 then return 0 end
    local grid = MapConv.solidsGrid(pieces)
    local n, kept = ROOF.samples, 0
    for _, piece in ipairs(candidates) do
        local min, max = boundsOf(piece)
        local top, open = max[3], 0
        for i = 0, n - 1 do
            for j = 0, n - 1 do
                local x = min[1] + (i + 0.5) * (max[1] - min[1]) / n
                local y = min[2] + (j + 0.5) * (max[2] - min[2]) / n
                local skyZ = math.huge
                for _, sky in ipairs(skies) do
                    if x >= sky.min[1] and x <= sky.max[1] and y >= sky.min[2] and y <= sky.max[2]
                        and sky.min[3] >= top - 1 and sky.min[3] < skyZ then skyZ = sky.min[3] end
                end
                local clear = skyZ < math.huge
                if clear then
                    for _, s in ipairs(MapConv.solidsAt(grid, x, y)) do
                        if x >= s.min[1] and x <= s.max[1] and y >= s.min[2] and y <= s.max[2]
                            and s.max[3] > top + 1 and s.min[3] < skyZ then
                            clear = false
                            break
                        end
                    end
                end
                if clear then open = open + 1 end
            end
        end

        local supported = false
        if open >= ROOF.open * n * n then
            local bottom = min[3]
            for x = math.floor(min[1] / SKY_CELL), math.floor(max[1] / SKY_CELL) do
                for y = math.floor(min[2] / SKY_CELL), math.floor(max[2] / SKY_CELL) do
                    for _, s in ipairs(grid[cellKey(x, y)] or {}) do
                        if s.min[1] < max[1] and s.max[1] > min[1] and s.min[2] < max[2] and s.max[2] > min[2]
                            and s.min[3] < bottom - 1 and s.max[3] >= bottom - ROOF.support then
                            supported = true
                            break
                        end
                    end
                    if supported then break end
                end
                if supported then break end
            end
        end
        if supported then
            piece.role, piece.roof = "solid", true
            pieces[#pieces + 1] = piece
            kept = kept + 1
        end
    end
    return kept
end



local BORROW_MARGIN, BORROW_CELL = 8, 512





local function borrowMaterials(pieces)
    local grid = {}
    local function cells(min, max, fn)
        for x = math.floor(min[1] / BORROW_CELL), math.floor(max[1] / BORROW_CELL) do
            for y = math.floor(min[2] / BORROW_CELL), math.floor(max[2] / BORROW_CELL) do fn(cellKey(x, y)) end
        end
    end
    local clips = {}
    for _, piece in ipairs(pieces) do
        local min, max = boundsOf(piece)
        if piece.role == "clip" or piece.roof then
            clips[#clips + 1] = { piece = piece, min = min, max = max }
        elseif not piece.material:upper():find("^TOOLS/") then
            local entry = { piece = piece, min = min, max = max }
            cells(min, max, function(key)
                grid[key] = grid[key] or {}
                table.insert(grid[key], entry)
            end)
        end
    end
    local floor, mmin, mmax = math.floor, math.min, math.max
    for _, clip in ipairs(clips) do
        local min, max = {}, {}
        for k = 1, 3 do min[k], max[k] = clip.min[k] - BORROW_MARGIN, clip.max[k] + BORROW_MARGIN end
        local best, bestScore, seen = nil, 0, {}
        for x = floor(min[1] / BORROW_CELL), floor(max[1] / BORROW_CELL) do
            for y = floor(min[2] / BORROW_CELL), floor(max[2] / BORROW_CELL) do
                for _, solid in ipairs(grid[cellKey(x, y)] or {}) do
                    if not seen[solid] then
                        seen[solid] = true

                        local volume = 1
                        for k = 1, 3 do
                            local overlap = mmin(max[k], solid.max[k]) - mmax(min[k], solid.min[k])
                            if overlap <= 0 then
                                volume = 0
                                break
                            end
                            volume = volume * overlap
                        end
                        if volume > bestScore then best, bestScore = solid, volume end
                    end
                end
            end
        end
        clip.piece.lookMaterial = best and best.piece.material or nil
    end
end








function MapConv.pieces(map, options)
    local opts = MapConv.withDefaults(options)
    local report = newReport()
    report.brushes = #map.brushes
    local function drop(reason) report.dropped[reason] = report.dropped[reason] + 1 end
    local function middle(bounds)
        return { (bounds.min[1] + bounds.max[1]) / 2, (bounds.min[2] + bounds.max[2]) / 2, (bounds.min[3] + bounds.max[3]) / 2 }
    end


    local allSkies = skyBounds(map)
    local skies = opts.clips and not opts.skyClips and allSkies or nil


    local pieces = {}

    local roofCandidates = {}
    for _, brush in ipairs(map.brushes) do
        local role, reason = MapConv.brushRole(brush, opts)
        local capGeometry = role == "drop" and reason == "invisible" and MapConv.Brush.build(brush.sides) or nil
        local flat = false
        if capGeometry then
            local across = math.min(capGeometry.max[1] - capGeometry.min[1], capGeometry.max[2] - capGeometry.min[2])
            flat = capGeometry.max[3] - capGeometry.min[3] < across
        end
        if flat then
            local box = MapConv.BoxFit.fit(capGeometry, opts)
            box.material = mainMaterial(capGeometry)
            box.brushId = brush.id
            box.at = middle(capGeometry)
            roofCandidates[#roofCandidates + 1] = box
        elseif role == "drop" then
            drop(reason)
        elseif role == "clip" and not opts.clips then
            drop("clip")
        else
            local geometry = MapConv.Brush.build(brush.sides)
            if not geometry then
                drop("broken")
            else
                local box = MapConv.BoxFit.fit(geometry, opts)
                box.role = role
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


    for _, terrain in ipairs(map.terrain or {}) do
        if not opts.terrain then
            drop("terrain")
        else
            local x0, y0, z0 = math.huge, math.huge, math.huge
            local x1, y1, z1 = -math.huge, -math.huge, -math.huge
            for _, p in ipairs(terrain.points) do
                local x, y, z = p[1], p[2], p[3]
                if x < x0 then x0 = x end
                if x > x1 then x1 = x end
                if y < y0 then y0 = y end
                if y > y1 then y1 = y end
                if z < z0 then z0 = z end
                if z > z1 then z1 = z end
            end
            local at = middle({ min = { x0, y0, z0 }, max = { x1, y1, z1 } })
            report.terrain = report.terrain + 1
            for _, slab in ipairs(MapConv.BoxFit.terrain(terrain, opts)) do
                local box = slab
                box.role, box.material, box.brushId, box.at = "solid", terrain.material, terrain.id, at
                pieces[#pieces + 1] = box
                report.terrainSlabs = report.terrainSlabs + 1
            end
        end
    end


    boundsMemo = {}
    report.roofs = keepRoofs(pieces, roofCandidates, allSkies)
    report.dropped.invisible = report.dropped.invisible + #roofCandidates - report.roofs
    if skies then
        local lids
        pieces, lids = MapConv.SkyClips.drop(pieces, skies)
        report.dropped.skyClip = report.dropped.skyClip + lids
    end
    if opts.clips or report.roofs > 0 then borrowMaterials(pieces) end
    boundsMemo = nil
    return pieces, report
end





function MapConv.score(box)
    local s = { box.sides[1], box.sides[2], box.sides[3] }
    table.sort(s)
    return s[2] * s[3]
end





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






function MapConv.priority(box)
    return MapConv.score(box) + FLOOR_WEIGHT * MapConv.walkableArea(box)
end









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

        boxes, report.simplified = MapConv.Merge.flat(boxes, {
            tolerance = opts.simplifyTolerance, fill = opts.simplifyFill, gap = 16, align = 32, maxThickness = 32,
        })
    end

    if opts.dropHidden or opts.dropCovered then
        local hidden, covered
        boxes, hidden, covered = MapConv.Merge.hidden(boxes, opts.dropCovered and COVERED_SHARE or 0)
        report.dropped.hidden = report.dropped.hidden + hidden
        report.dropped.covered = report.dropped.covered + covered
    end

    local sized = {}
    for _, box in ipairs(boxes) do
        if math.max(box.sides[1], box.sides[2], box.sides[3]) < opts.minSize then
            drop("small")
        else
            sized[#sized + 1] = box
        end
    end
    local scores = {}
    for _, box in ipairs(sized) do scores[box] = MapConv.priority(box) end
    table.sort(sized, function(a, b) return scores[a] > scores[b] end)
    local kept, cut = {}, {}
    for i, box in ipairs(sized) do
        if i <= opts.budget then kept[#kept + 1] = box else cut[#cut + 1] = box end
    end
    report.dropped.budget = report.dropped.budget + #cut
    return kept, cut, report
end







function MapConv.anchorFor(map, boxes, options)
    return pickAnchor(map, boxes, MapConv.withDefaults(options))
end









function MapConv.toWorld(box, anchor, options)
    local turn = Mat3.rotZ(math.rad(options.yaw))
    local p = Mat3.apply(turn, Vec.scale(Vec.sub(box.center, anchor), options.scale))
    local origin = MGE.POS_ORIGIN
    local sides = {}
    for k = 1, 3 do sides[k] = math.max(box.sides[k] * options.scale, MGE.MIN_SIDE) end
    return { p[1] + origin[1], p[2] + origin[2], p[3] }, Mat3.mul(turn, box.frame), sides
end











function MapConv.anchorAround(anchor, options, point, turn, factor)
    local origin = MGE.POS_ORIGIN
    local d = { point[1] - origin[1], point[2] - origin[2], 0 }
    local moved = Vec.scale(Mat3.apply(turn, d), factor)
    local newFrame = Mat3.mul(turn, Mat3.rotZ(math.rad(options.yaw)))
    local back = Vec.scale(Mat3.apply(Mat3.transpose(newFrame), Vec.sub(d, moved)), 1 / (options.scale * factor))
    return { anchor[1] - back[1], anchor[2] - back[2], anchor[3] }
end






function MapConv.toMap(point, anchor, options)
    local origin = MGE.POS_ORIGIN
    local back = Mat3.apply(Mat3.transpose(Mat3.rotZ(math.rad(options.yaw))),
        { point[1] - origin[1], point[2] - origin[2], point[3] })
    return Vec.add(anchor, Vec.scale(back, 1 / options.scale))
end







function MapConv.objects(boxes, anchor, options, report)
    local opts = MapConv.withDefaults(options)
    local flag = MGE.FLAGS.STATIC + (opts.ungrippable and MGE.FLAGS.UNGRIPPABLE or 0)
    local objects = {}
    for i, box in ipairs(boxes) do
        local pos, frame, sides = MapConv.toWorld(box, anchor, opts)

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


        local color = MapConv.colorFor(box.role == "clip" and (box.lookMaterial or "") or (box.lookMaterial or box.material))
        objects[i] = {
            kind = "env_obj",
            id = i,
            lines = { { raw = "# " .. (box.brushId:find("^disp") and "" or "brush ") .. box.brushId
                .. (box.merged and (" + " .. (box.merged - 1) .. " merged") or "") .. " "
                .. (box.role == "clip" and ("clip" .. (box.lookMaterial and (" by " .. box.lookMaterial) or ""))
                    or box.roof and ("roof cap" .. (box.lookMaterial and (" by " .. box.lookMaterial) or ""))
                    or box.material) } },
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







function MapConv.convert(map, options, pieces, piecesReport)
    local opts = MapConv.withDefaults(options)
    if not pieces then pieces, piecesReport = MapConv.pieces(map, opts) end
    local kept, _, report = MapConv.select(pieces, opts, piecesReport)
    local anchor, anchorFrom = pickAnchor(map, kept, opts)
    report.anchor, report.anchorFrom = anchor, anchorFrom
    local objects = MapConv.objects(kept, anchor, opts, report)
    return { objects = objects, report = report }
end






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


MapConv.EXTENSIONS = { "vmf", "bsp" }




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
    if (report.roofs or 0) > 0 then
        lines[#lines + 1] = report.roofs .. " roof caps kept (invisible tops under the open sky)"
    end
    if d.hidden > 0 or d.covered > 0 then
        lines[#lines + 1] = d.hidden .. " boxes left out inside other boxes"
            .. (d.covered > 0 and (", " .. d.covered .. " covered by others") or "")
    end
    return lines
end

return MapConv
