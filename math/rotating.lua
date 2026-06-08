RotatingOld = {}
-- Function to rotate a point around the X axis
local function rotateX(x, y, z, angle)
    local cosA, sinA = math.cos(angle), math.sin(angle)
    return x, cosA * y - sinA * z, sinA * y + cosA * z
end

-- Function to rotate a point around the Y axis
local function rotateY(x, y, z, angle)
    local cosA, sinA = math.cos(angle), math.sin(angle)
    return cosA * x + sinA * z, y, -sinA * x + cosA * z
end

-- Function to rotate a point around the Z axis
local function rotateZ(x, y, z, angle)
    local cosA, sinA = math.cos(angle), math.sin(angle)
    return cosA * x - sinA * y, sinA * x + cosA * y, z
end



local function eulerToQuaternion(x, y, z)
    local cx, cy, cz = math.cos(x / 2), math.cos(y / 2), math.cos(z / 2)
    local sx, sy, sz = math.sin(x / 2), math.sin(y / 2), math.sin(z / 2)

    return {
        w = cx * cy * cz + sx * sy * sz,
        x = sx * cy * cz - cx * sy * sz,
        y = cx * sy * cz + sx * cy * sz,
        z = cx * cy * sz - sx * sy * cz,
    }
end

local function quaternionToEuler(q)
    local sinr_cosp = 2 * (q.w * q.x + q.y * q.z)
    local cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y)
    local roll = math.atan2(sinr_cosp, cosr_cosp)

    local sinp = 2 * (q.w * q.y - q.z * q.x)
    local pitch
    if math.abs(sinp) >= 1 then
        pitch = math.pi / 2 * (sinp < 0 and -1 or 1) -- Clamp
    else
        pitch = math.asin(sinp)
    end

    local siny_cosp = 2 * (q.w * q.z + q.x * q.y)
    local cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z)
    local yaw = math.atan2(siny_cosp, cosy_cosp)

    return { math.deg(roll), math.deg(pitch), math.deg(yaw) }
end

local function quaternionMultiply(q1, q2)
    return {
        w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
        x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
        y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
        z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
    }
end

function RotatingOld.SetRotOffset(x, y, z, ox, oy, oz)
    -- print("SetRotOffset input: " .. x .. ", " .. y .. ", " .. z .. ", " .. ox .. ", " .. oy .. ", " .. oz)
    local currentQuat = eulerToQuaternion(x, y, z)
    local offsetQuat = eulerToQuaternion(-ox, -oy, -oz)
    local resultQuat = quaternionMultiply(currentQuat, offsetQuat)

    -- Convert the result quaternion back to Euler angles
    return quaternionToEuler(resultQuat)
end

function RotatingOld.SetRotPos(x, y, z, px, py, pz, ox, oy, oz)
    -- Translate object to origin (relative to the center of rotation)
    local x, y, z = x - px, y - py, z - pz

    -- Apply rotations in 3D space
    x, y, z = rotateX(x, y, z, ox) -- Rotate around X axis
    x, y, z = rotateY(x, y, z, oy) -- Rotate around Y axis
    x, y, z = rotateZ(x, y, z, oz) -- Rotate around Z axis

    -- Translate object back to its new position
    return { x + px, y + py, z + pz }
end

function RotateObjectAroundPivot(obj, pivot, rx, ry, rz)
    -- 1. offset vector
    local ox = obj.pos.x - pivot.x
    local oy = obj.pos.y - pivot.y
    local oz = obj.pos.z - pivot.z

    -- 2. rotation matrix from Euler offset
    local R = Utils3D.GetMatrixFromEuler(
        math.rad(rx), math.rad(ry), math.rad(rz),
        EULER_XYZ
    )

    -- 3. rotate offset vector
    local rotated = Utils3D.MatrixMultiply({ { ox, oy, oz } }, R)[1]

    -- 4. new world position
    obj.pos.x = pivot.x + rotated[1]
    obj.pos.y = pivot.y + rotated[2]
    obj.pos.z = pivot.z + rotated[3]

    -- 5. rotate object’s rotation matrix
    local Rdelta = R
    local newRotMatrix = Utils3D.MatrixMultiply(Rdelta, obj.rotMatrix)

    -- 6. apply rotation
    obj.rotMatrix = newRotMatrix
    obj.rotMatrixTB = Utils3D.MatrixToMatrixTB(newRotMatrix)
end

return RotatingOld
