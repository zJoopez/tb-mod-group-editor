


local Mat3 = {
    IDENTITY = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
}




function Mat3.mul(a, b)
    local r = {}
    for i = 1, 3 do
        r[i] = {}
        for j = 1, 3 do
            r[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
        end
    end
    return r
end



function Mat3.transpose(a)
    return {
        { a[1][1], a[2][1], a[3][1] },
        { a[1][2], a[2][2], a[3][2] },
        { a[1][3], a[2][3], a[3][3] },
    }
end




function Mat3.apply(m, v)
    return {
        m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
        m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
        m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
    }
end


function Mat3.rotX(t)
    local c, s = math.cos(t), math.sin(t)
    return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } }
end


function Mat3.rotY(t)
    local c, s = math.cos(t), math.sin(t)
    return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } }
end


function Mat3.rotZ(t)
    local c, s = math.cos(t), math.sin(t)
    return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } }
end







function Mat3.fromEulerDegrees(x, y, z)
    return Mat3.mul(Mat3.rotX(math.rad(x)), Mat3.mul(Mat3.rotY(math.rad(y)), Mat3.rotZ(math.rad(z))))
end





function Mat3.toEulerXYZ(m)
    local sy = math.max(-1, math.min(1, m[1][3]))
    local y = math.asin(sy)
    local atan2 = math.atan2 or math.atan
    if math.abs(sy) < 0.999999 then
        return atan2(-m[2][3], m[3][3]), y, atan2(-m[1][2], m[1][1])
    end

    return atan2(m[3][2], m[2][2]), y, 0
end

MGE.Mat3 = Mat3
