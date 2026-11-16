


MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Vmf = {}
MapConv.Vmf = Vmf









function Vmf.parseTree(text)
    local root = { name = "", props = {}, children = {} }
    local stack = { root }
    local pos, len = 1, #text
    local pending
    while true do
        local s = text:find("%S", pos)
        if not s then break end
        local c = text:sub(s, s)
        local token
        if c == "/" and text:sub(s + 1, s + 1) == "/" then
            pos = (text:find("\n", s, true) or len) + 1
        elseif c == '"' then
            local e = text:find('"', s + 1, true)
            if not e then error("unclosed quote at byte " .. s) end
            token = text:sub(s + 1, e - 1)
            pos = e + 1
        elseif c == "{" then
            local node = { name = pending or "", props = {}, children = {} }
            local parent = stack[#stack]
            parent.children[#parent.children + 1] = node
            stack[#stack + 1] = node
            pending = nil
            pos = s + 1
        elseif c == "}" then
            if #stack == 1 then error("unexpected } at byte " .. s) end
            stack[#stack] = nil
            pending = nil
            pos = s + 1
        else
            local e = text:find('[%s{}"]', s) or len + 1
            token = text:sub(s, e - 1)
            pos = e
        end
        if token then
            if pending then
                local props = stack[#stack].props
                if props[pending] == nil then props[pending] = token end
                pending = nil
            else
                pending = token
            end
        end
    end
    return root
end





























local function readVector(s)
    local x, y, z = tostring(s or ""):match("^%s*(%S+)%s+(%S+)%s+(%S+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and y and z then return { x, y, z } end
end
Vmf.readVector = readVector



local function readPlane(s)
    local points = {}
    for inner in s:gmatch("%(([^%)]*)%)") do
        local p = readVector(inner)
        if not p then return nil end
        points[#points + 1] = p
    end
    if #points == 3 then return points end
end




local function hasChild(node, name)
    for _, child in ipairs(node.children) do
        if child.name == name then return true end
    end
    return false
end




local function readSolid(node, entity)
    local brush = { id = node.props.id or "?", entity = entity, sides = {} }
    for _, child in ipairs(node.children) do
        if child.name == "side" and child.props.plane then
            local points = readPlane(child.props.plane)
            if points then
                table.insert(brush.sides, {
                    points = points,
                    material = child.props.material or "",
                    displacement = hasChild(child, "dispinfo"),
                })
            end
        end
    end
    return brush
end






function Vmf.nonSolidEntity(props)
    if tonumber(props.StartDisabled or props.startdisabled) == 1 then return true end
    return props.classname == "func_brush" and tonumber(props.Solidity or props.solidity) == 1
end







local function collectSolids(node, entity, brushes, nonSolid)
    for _, child in ipairs(node.children) do
        if child.name == "solid" then
            local brush = readSolid(child, entity)
            brush.nonSolid = nonSolid or nil
            table.insert(brushes, brush)
        elseif child.name == "hidden" then
            collectSolids(child, entity, brushes, nonSolid)
        end
    end
end



local function readBlocks(node, map)
    for _, child in ipairs(node.children) do
        if child.name == "world" then
            collectSolids(child, "worldspawn", map.brushes)
        elseif child.name == "entity" then
            local classname = child.props.classname or ""
            collectSolids(child, classname, map.brushes, Vmf.nonSolidEntity(child.props))
            table.insert(map.entities, { classname = classname, origin = readVector(child.props.origin), props = child.props })
        elseif child.name == "hidden" then
            readBlocks(child, map)
        end
    end
end



function Vmf.parse(text)
    local map = { brushes = {}, entities = {} }
    readBlocks(Vmf.parseTree(text), map)
    return map
end

return Vmf
