local ShapeGen = {}
MGE.ShapeGen = ShapeGen

local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")
local Mat3 = MGE.Mat3

-- Shape generator (Generate tab): a chain of boxes along X that bends up (toward Z) as it goes.
-- Angle is how far it turns in total: 0 is a straight line, 90 a quarter pipe, 360 a closed loop.
-- The pieces are chords of that arc. They line up and touch along one line: the inside of the bend
-- (align "in", their top edge), the outside ("out", bottom edge) or their middle ("center"), Gap is
-- the space between them along that line.
-- Increment is added to the sides of each next piece, so piece i (from 0) has sides + i * increment:
-- with angle 0, a Z increment and out alignment the pieces are stairs, adding the same Y increment
-- with center alignment makes a stepped pyramid lying along X. Y is always centered.
-- The Generate tab then moves the shape in front of the camera (Camera.spawnPoint, moveTo).

---Rotation by t radians around the unit vector u (Rodrigues)
---@param u number[]
---@param t number
---@return number[][]
local function rotationAbout(u, t)
    local c, s = math.cos(t), math.sin(t)
    local k = 1 - c
    local x, y, z = u[1], u[2], u[3]
    return {
        { c + x * x * k, x * y * k - z * s, x * z * k + y * s },
        { y * x * k + z * s, c + y * y * k, y * z * k - x * s },
        { z * x * k - y * s, z * y * k + x * s, c + z * z * k },
    }
end

---@class GeneratePiece
---@field pos number[]
---@field rot number[] degrees, as written in the file
---@field frame number[][] orientation the rot line gives, columns are the piece's axes (preview drawing)
---@field sides number[]

---@alias GenerateAlign "in"|"out"|"center"

-- where each piece's center sits from the line they touch along, in halves of its thickness (along its Z)
local ALIGN_LIFT = { ["in"] = -1, out = 1, center = 0 }

---@class GenerateOptions
---@field increment number[]? added to the sides of each next piece, default 0 0 0
---@field align GenerateAlign? default "out"

---Sides of piece i (from 0)
---@param sides number[]
---@param increment number[]
---@param i integer
---@return number[]
local function pieceSides(sides, increment, i)
    return { sides[1] + increment[1] * i, sides[2] + increment[2] * i, sides[3] + increment[3] * i }
end

---Pieces left before a side shrinks below MGE.MIN_SIDE, nil when increments never shrink anything
---@param sides number[]
---@param increment number[]
---@return integer?
local function maxPieces(sides, increment)
    local most
    for k = 1, 3 do
        if increment[k] < 0 then
            -- piece i is fine while sides + increment * i >= MIN_SIDE
            local n = math.floor((sides[k] - MGE.MIN_SIDE) / -increment[k] + 1e-9) + 1
            most = math.min(most or n, n)
        end
    end
    return most
end

---@class GenerateBounds: SpawnBounds box around the whole shape, world axes (utils/camera.lua)

---Where the pieces go: the shape's lowest point at z 0, centered on `center` in x and y
---@param amount integer
---@param gap number
---@param angle number degrees turned in total
---@param sides number[] box sides of the first piece: length (x), width (y), thickness (z)
---@param center number[] x y
---@param options GenerateOptions?
---@return GeneratePiece[] pieces, GenerateBounds bounds where the pieces ended up
local function planGenerate(amount, gap, angle, sides, center, options)
    options = options or {}
    local increment = options.increment or { 0, 0, 0 }
    local liftHalves = ALIGN_LIFT[options.align] or ALIGN_LIFT.out
    local step = math.rad(angle) / amount
    local axis = { 0, -1, 0 } -- turning around -Y tilts X up toward Z
    local vertex = { 0, 0, 0 } -- on the line the pieces touch along, each piece starts where it is
    local pieces = {}
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for i = 0, amount - 1 do
        local s = pieceSides(sides, increment, i)
        local turn = rotationAbout(axis, step * (i + 0.5))
        local dir, up = Mat3.apply(turn, { 1, 0, 0 }), Mat3.apply(turn, { 0, 0, 1 })
        local lift = liftHalves * s[3] / 2 -- out: the piece sits on the line, in: hangs under it
        local pos = {}
        for k = 1, 3 do pos[k] = vertex[k] + dir[k] * s[1] / 2 + up[k] * lift end
        for k = 1, 3 do vertex[k] = vertex[k] + dir[k] * (s[1] + gap) end
        -- box corners, for the shape's bounds
        for cx = -1, 1, 2 do
            for cy = -1, 1, 2 do
                for cz = -1, 1, 2 do
                    local corner = Mat3.apply(turn, { cx * s[1] / 2, cy * s[2] / 2, cz * s[3] / 2 })
                    for k = 1, 3 do
                        min[k] = math.min(min[k], pos[k] + corner[k])
                        max[k] = math.max(max[k], pos[k] + corner[k])
                    end
                end
            end
        end
        local offsets = { Mat3.toEulerXYZ(turn) }
        table.insert(pieces, {
            pos = pos,
            rot = RotatingOld.SetRotOffset(0, 0, 0, offsets[1], offsets[2], offsets[3]),
            frame = turn,
            sides = s,
        })
    end
    local shift = { center[1] - (min[1] + max[1]) / 2, center[2] - (min[2] + max[2]) / 2, -min[3] }
    for _, piece in ipairs(pieces) do
        for k = 1, 3 do piece.pos[k] = piece.pos[k] + shift[k] end
    end
    for k = 1, 3 do
        min[k], max[k] = min[k] + shift[k], max[k] + shift[k]
    end
    return pieces, { min = min, max = max }
end

---Moves planned pieces so the shape's center (x y) and lowest point (z) are at point
---@param pieces GeneratePiece[]
---@param bounds GenerateBounds where the pieces are now
---@param point number[] from Camera.spawnPoint
function ShapeGen.moveTo(pieces, bounds, point)
    local shift = {
        point[1] - (bounds.min[1] + bounds.max[1]) / 2,
        point[2] - (bounds.min[2] + bounds.max[2]) / 2,
        point[3] - bounds.min[3],
    }
    for _, piece in ipairs(pieces) do
        for k = 1, 3 do piece.pos[k] = piece.pos[k] + shift[k] end
    end
end


ShapeGen.plan = planGenerate
ShapeGen.maxPieces = maxPieces

return ShapeGen
