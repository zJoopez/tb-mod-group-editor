local ShapeGen = {}
MGE.ShapeGen = ShapeGen

local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")
local Mat3 = MGE.Mat3
















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










local ALIGN_LIFT = { ["in"] = -1, out = 1, center = 0 }















local function pieceSides(sides, increment, i)
    return { sides[1] + increment[1] * i, sides[2] + increment[2] * i, sides[3] + increment[3] * i }
end





local function maxPieces(sides, increment)
    local most
    for k = 1, 3 do
        if increment[k] < 0 then

            local n = math.floor((sides[k] - MGE.MIN_SIDE) / -increment[k] + 1e-9) + 1
            most = math.min(most or n, n)
        end
    end
    return most
end











local function planGenerate(amount, gap, angle, sides, center, options)
    options = options or {}
    local increment = options.increment or { 0, 0, 0 }
    local liftHalves = ALIGN_LIFT[options.align] or ALIGN_LIFT.out
    local step = math.rad(angle) / amount
    local axis = { 0, -1, 0 }

    local rotation = options.rotation
    if options.firstTurn then

        local bend1 = rotationAbout(axis, step * 0.5)
        local local1 = Mat3.mul(Mat3.transpose(bend1), Mat3.mul(options.firstTurn, bend1))
        rotation = rotation and Mat3.mul(local1, rotation) or local1
    end
    local vertex = { 0, 0, 0 }
    local pieces = {}
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for i = 0, amount - 1 do
        local s = pieceSides(sides, increment, i)
        local bend = rotationAbout(axis, step * (i + 0.5))
        local dir, up = Mat3.apply(bend, { 1, 0, 0 }), Mat3.apply(bend, { 0, 0, 1 })
        local lift = liftHalves * s[3] / 2




        local pos = {}
        for k = 1, 3 do pos[k] = vertex[k] + dir[k] * (s[1] + gap) / 2 + up[k] * lift end
        for k = 1, 3 do vertex[k] = vertex[k] + dir[k] * (s[1] + gap) end

        local turn = rotation and Mat3.mul(bend, rotation) or bend

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













function ShapeGen.joints(pieces, perPair)
    local joints = {}
    if perPair < 1 then return joints end
    for i = 1, #pieces - 1 do
        local p, q = pieces[i], pieces[i + 1]
        local mid = {}
        for k = 1, 3 do mid[k] = (p.pos[k] + q.pos[k]) / 2 end
        if perPair == 1 then
            table.insert(joints, { a = i, b = i + 1, pos = mid })
        else
            local half = math.min(p.sides[2], q.sides[2]) / 2
            local width = { p.frame[1][2], p.frame[2][2], p.frame[3][2] }
            for _, sign in ipairs({ -1, 1 }) do
                local pos = {}
                for k = 1, 3 do pos[k] = mid[k] + sign * half * width[k] end
                table.insert(joints, { a = i, b = i + 1, pos = pos })
            end
        end
    end
    return joints
end

ShapeGen.plan = planGenerate
ShapeGen.maxPieces = maxPieces

return ShapeGen
