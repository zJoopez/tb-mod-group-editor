require("toriui.uielement3d")
Rotating = {}
local function mulMat3Vec3(m, v)
    return {
        x = m[1][1] * v.x + m[1][2] * v.y + m[1][3] * v.z,
        y = m[2][1] * v.x + m[2][2] * v.y + m[2][3] * v.z,
        z = m[3][1] * v.x + m[3][2] * v.y + m[3][3] * v.z
    }
end

---@param pos XYZ
---@param rotDeg XYZ
---@param pivot XYZ
---@param deltaDeg XYZ
---@param convention EulerRotationConvention
function Rotating.RotateObjectAroundPivot(pos, rotDeg, pivot, deltaDeg, convention)
    convention = convention or EULER_XYZ

    print_r(rotDeg)
    local currentRotMatrix = EulerRotation.New(
        rotDeg.x, rotDeg.y, rotDeg.z, convention
    ):toMatrix()

    local deltaRotMatrix = EulerRotation.New(
        deltaDeg.x, deltaDeg.y, deltaDeg.z, convention
    ):toMatrix()

    local offset = {
        x = pos.x - pivot.x,
        y = pos.y - pivot.y,
        z = pos.z - pivot.z
    }

    local rotatedOffset = mulMat3Vec3(deltaRotMatrix, offset)

    local newPos = {
        x = pivot.x + rotatedOffset.x,
        y = pivot.y + rotatedOffset.y,
        z = pivot.z + rotatedOffset.z
    }

    local newRotMatrix = Utils3D.MatrixMultiply(deltaRotMatrix, currentRotMatrix)
    local newRot = Utils3D.GetEulerFromMatrix(newRotMatrix, convention)

    return {
        pos = newPos,
        rot = {
            x = newRot.x,
            y = newRot.y,
            z = newRot.z
        }
    }
end

function Rotating.matrix4ToPosRot(matrix4, convention)
    convention = convention or EULER_XYZ

    local rotMatrix = {
        { matrix4[1], matrix4[5], matrix4[9] },
        { matrix4[2], matrix4[6], matrix4[10] },
        { matrix4[3], matrix4[7], matrix4[11] }
    }

    local pos = {
        x = matrix4[13] or 0,
        y = matrix4[14] or 0,
        z = matrix4[15] or 0
    }

    local rot = Utils3D.GetEulerFromMatrix(rotMatrix, convention)

    return pos, {
        x = rot.x,
        y = rot.y,
        z = rot.z
    }
end

function Rotating.GetSelectionPivot()
    local sumX, sumY, sumZ = 0, 0, 0
    local n = 0

    for _, p in ipairs(MGE.modData.objects) do
        if p.selected then
            sumX = sumX + p.pos[1]
            sumY = sumY + p.pos[2]
            sumZ = sumZ + p.pos[3]
            n = n + 1
        end
    end

    if n == 0 then
        return { x = 0, y = 0, z = 0 }
    end

    return {
        x = sumX / n,
        y = sumY / n,
        z = sumZ / n
    }
end

function Rotating.degToRad(d)
    return d * math.pi / 180
end
return Rotating