local RotatingOld = {}

local function rotateX(x, y, z, angle)
    local cosA, sinA = math.cos(angle), math.sin(angle)
    return x, cosA * y - sinA * z, sinA * y + cosA * z
end


local function rotateY(x, y, z, angle)
    local cosA, sinA = math.cos(angle), math.sin(angle)
    return cosA * x + sinA * z, y, -sinA * x + cosA * z
end


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


local GIMBAL_LIMIT = 1 - 1e-7

local function quaternionToEuler(q)
    local sinp = 2 * (q.w * q.y - q.z * q.x)
    if math.abs(sinp) >= GIMBAL_LIMIT then



        local sign = sinp < 0 and -1 or 1
        local yaw = -2 * sign * math.atan2(q.x, q.w)
        return { 0, math.deg(sign * math.pi / 2), math.deg(yaw) }
    end

    local sinr_cosp = 2 * (q.w * q.x + q.y * q.z)
    local cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y)
    local roll = math.atan2(sinr_cosp, cosr_cosp)

    local pitch = math.asin(sinp)

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

    local currentQuat = eulerToQuaternion(x, y, z)
    local offsetQuat = eulerToQuaternion(-ox, -oy, -oz)
    local resultQuat = quaternionMultiply(currentQuat, offsetQuat)


    return quaternionToEuler(resultQuat)
end

function RotatingOld.SetRotPos(x, y, z, px, py, pz, ox, oy, oz)

    local x, y, z = x - px, y - py, z - pz


    x, y, z = rotateZ(x, y, z, oz)
    x, y, z = rotateY(x, y, z, oy)
    x, y, z = rotateX(x, y, z, ox)


    return { x + px, y + py, z + pz }
end

return RotatingOld
