-- Sky clips (MapConv.SkyClips.drop, used by MapConv.pieces in convert.lua): leaves out the clips that
-- are lids over the map. Loaded after convert.lua: it shares its piece bounds (MapConv.boundsOf, memoized
-- while MapConv.pieces runs) and footprint grid (MapConv.SKY_CELL, MapConv.Merge.cellKey) with the roof caps.
-- tools/mapconv_baseline.lua check shows which clips a change here drops or keeps on every map.
local MapConv = MGE.MapConv
local boundsOf, SKY_CELL, cellKey = MapConv.boundsOf, MapConv.SKY_CELL, MapConv.Merge.cellKey

-- Sky clips: mappers fill the open parts of the map with huge clip brushes, so players can't jump
-- onto the roofs or out of the map. In Toribash they're giant lids (dust2: up to 2650 x 3100 units,
-- office and nuke: thin 16 unit sheets 250-1150 under the sky). A clip is one when it's
--   wide:    both horizontal sides at least `width` map units (walls and pillars stay)
--   flat:     lower than it is wide (a tall block next to the sky is a wall)
-- and either
--   close:    sky starts at most `gap` above its top over at least `cover` of it (blocks filling
--             the air from the roofs up to the sky, dust2's lids, inferno's roof caps)
-- or
--   floating: on at least `floating` of its footprint nothing solid (terrain too) from `clearance`
--             under it up to its top: nothing to stand on under it, it's not a floor or a ramp
--   open:     on at least `open` of its footprint sky right over it, nothing solid in between (a
--             ceiling clip under a roof stays)
-- or
--   ceiling:  its top is the map's clip ceiling: at least `ceilingCount` clips (both horizontal sides
--             `ceilingWidth` or more) share that top height, at least `ceilingBelow` of the solid
--             pieces end below it, and sky is over at least `ceilingSky` of its footprint. Such a
--             clip only needs both horizontal sides `ceilingWidth` and to be lower than `ceilingTall`
--             times its longest side (an invisible wall at the map's edge from the ground up stays;
--             2 would take 10 more of Italy's blocks between roofs and ceiling, but also 8-20 tall
--             blocks on inferno, lake, anubis, stmarc that weren't looked at). Italy fills the air
--             between its roofs up to one height (z 512, 44 clips, 336 under the sky, roofs poking
--             through so neither close nor open catches them); militia, anubis, inferno, mirage...
--             have such layers too. Low shared heights (floors, water: Italy's -152, 5-15% of the
--             solids below) aren't ceilings. A solid wholly above it on `ceilingRoofed` of its
--             footprint keeps it: an indoor clip under a roof (nuke's at z 64)
-- Checked on `samples` x `samples` points of its footprint. Measured: the sheets of office and nuke
-- float on 75-100% and are open on 78-100%; dust2's ceiling clip over CT spawn is open on 47%,
-- nuke's clips under roofs on 0%, its clips lying on geometry float on 0-11%
local SKY_CLIP = { width = 256, gap = 256, cover = 0.5, clearance = 72, floating = 0.5, open = 0.5, samples = 6,
    ceilingCount = 8, ceilingWidth = 128, ceilingBelow = 0.85, ceilingSky = 0.5, ceilingRoofed = 0.5,
    ceilingTall = 1 }

---Leaves out the clips that are lids over the map (SKY_CLIP), once every piece is there: what's under
---a clip can be terrain
---@param pieces MapConvPiece[]
---@param skies { min: number[], max: number[] }[] skyBounds
---@return MapConvPiece[] kept, integer lids
local function drop(pieces, skies)
    if #skies == 0 then return pieces, 0 end
    local candidates, clips = {}, {}
    for _, piece in ipairs(pieces) do
        if piece.role == "clip" then
            local min, max = boundsOf(piece)
            local across = math.min(max[1] - min[1], max[2] - min[2])
            local clip = { piece = piece, min = min, max = max, across = across,
                long = math.max(max[1] - min[1], max[2] - min[2]) }
            clips[#clips + 1] = clip
            if across >= SKY_CLIP.width and max[3] - min[3] < across then candidates[#candidates + 1] = clip end
        end
    end
    local lids = {}

    -- solids by footprint cell
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

    -- clip ceilings: top heights many wide clips share, above nearly all the solid pieces
    local shared = {}
    for _, c in ipairs(clips) do
        if c.across >= SKY_CLIP.ceilingWidth then
            local top = math.floor(c.max[3] + 0.5)
            shared[top] = (shared[top] or 0) + 1
        end
    end
    local ceilings = {}
    for top, count in pairs(shared) do
        if count >= SKY_CLIP.ceilingCount then ceilings[#ceilings + 1] = { top = top, below = 0 } end
    end
    if #ceilings > 0 then
        local solids = 0
        for _, piece in ipairs(pieces) do
            if piece.role ~= "clip" then
                solids = solids + 1
                local _, max = boundsOf(piece)
                for _, ceiling in ipairs(ceilings) do
                    if max[3] <= ceiling.top + 1 then ceiling.below = ceiling.below + 1 end
                end
            end
        end
        local isCeiling = {}
        for _, ceiling in ipairs(ceilings) do
            if solids > 0 and ceiling.below >= SKY_CLIP.ceilingBelow * solids then isCeiling[ceiling.top] = true end
        end
        local n = SKY_CLIP.samples
        for _, c in ipairs(clips) do
            local min, max = c.min, c.max
            if c.across >= SKY_CLIP.ceilingWidth and max[3] - min[3] < SKY_CLIP.ceilingTall * c.long and isCeiling[math.floor(max[3] + 0.5)] then
                -- footprint points with sky somewhere over them, and with a solid wholly above the
                -- clip (a roof: indoor clips stay; Italy's roofs poke through its ceiling, they start below)
                local under, roofed = 0, 0
                for i = 0, n - 1 do
                    for j = 0, n - 1 do
                        local x = min[1] + (i + 0.5) * (max[1] - min[1]) / n
                        local y = min[2] + (j + 0.5) * (max[2] - min[2]) / n
                        for _, sky in ipairs(skies) do
                            if x >= sky.min[1] and x <= sky.max[1] and y >= sky.min[2] and y <= sky.max[2]
                                and sky.min[3] >= max[3] - 1 then
                                under = under + 1
                                break
                            end
                        end
                        for _, s in ipairs(grid[cellKey(math.floor(x / SKY_CELL), math.floor(y / SKY_CELL))] or {}) do
                            if x >= s.min[1] and x <= s.max[1] and y >= s.min[2] and y <= s.max[2] and s.min[3] >= max[3] - 1 then
                                roofed = roofed + 1
                                break
                            end
                        end
                    end
                end
                if under >= SKY_CLIP.ceilingSky * n * n and roofed < SKY_CLIP.ceilingRoofed * n * n then
                    lids[c.piece] = true
                end
            end
        end
    end
    if #candidates == 0 and not next(lids) then return pieces, 0 end

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
                for _, s in ipairs(grid[cellKey(math.floor(x / SKY_CELL), math.floor(y / SKY_CELL))] or {}) do
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

---@class MapConvSkyClips
MapConv.SkyClips = { RULES = SKY_CLIP, drop = drop }
return MapConv.SkyClips
