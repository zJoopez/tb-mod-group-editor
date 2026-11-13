-- Map converter (mapconv): reads Valve Map Format files (.vmf: Hammer's map sources, or a .bsp
-- decompiled with BSPSource) into brushes and point entities. Pure Lua, no game calls: the command
-- line tool (tools/mapconv.lua) runs it too. Plan and status: docs/map-import-plan.md
MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Vmf = {}
MapConv.Vmf = Vmf

---@class VmfNode
---@field name string block name, e.g. "world", "solid", "side"
---@field props table<string, string> key values, a repeated key keeps its first value
---@field children VmfNode[]

---KeyValues text to a tree. Tokens are "quoted strings", bare words, { and }, and // comments
---@param text string
---@return VmfNode root its children are the file's top level blocks
function Vmf.parseTree(text)
    local root = { name = "", props = {}, children = {} }
    local stack = { root }
    local pos, len = 1, #text
    local pending -- a block name or key waiting for its { or value
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

---@class MapSide
---@field points number[][]? the three points of its plane, as written (.vmf)
---@field plane { n: number[], d: number }? the plane itself, normal pointing out (.bsp, bsp.lua)
---@field material string as written, e.g. "DE_DUST/DUSTWALL01" or "TOOLS/TOOLSNODRAW"
---@field displacement boolean has a dispinfo block (terrain mesh over the face)

---@class MapBrush
---@field id string the solid's id in the file
---@field entity string classname of the entity it belongs to, "worldspawn" for world brushes
---@field sides MapSide[]
---@field role "solid"|"clip"|"drop"? set by readers that know it (bsp.lua: contents flags)
---@field reason string? why a dropped brush is dropped
---@field sky boolean? a sky brush (bsp.lua: sky surface flags; .vmf sky brushes are found by material)

---@class MapEntity
---@field classname string
---@field origin number[]?
---@field props table<string, string>

---@class MapFile
---@field brushes MapBrush[]
---@field entities MapEntity[]
---@field terrain MapTerrain[]? terrain grids (displacements) that aren't brushes (.bsp, bsp.lua)

---@param s string? "x y z"
---@return number[]?
local function readVector(s)
    local x, y, z = tostring(s or ""):match("^%s*(%S+)%s+(%S+)%s+(%S+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and y and z then return { x, y, z } end
end
Vmf.readVector = readVector

---@param s string "(x y z) (x y z) (x y z)"
---@return number[][]? points
local function readPlane(s)
    local points = {}
    for inner in s:gmatch("%(([^%)]*)%)") do
        local p = readVector(inner)
        if not p then return nil end
        points[#points + 1] = p
    end
    if #points == 3 then return points end
end

---@param node VmfNode
---@param name string
---@return boolean
local function hasChild(node, name)
    for _, child in ipairs(node.children) do
        if child.name == name then return true end
    end
    return false
end

---@param node VmfNode a solid block
---@param entity string
---@return MapBrush
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

---Solids of a world or entity block. Solids hidden in the editor (hidden blocks) are still compiled
---into the map, so they count
---@param node VmfNode
---@param entity string
---@param brushes MapBrush[]
local function collectSolids(node, entity, brushes)
    for _, child in ipairs(node.children) do
        if child.name == "solid" then
            table.insert(brushes, readSolid(child, entity))
        elseif child.name == "hidden" then
            collectSolids(child, entity, brushes)
        end
    end
end

---@param node VmfNode
---@param map MapFile
local function readBlocks(node, map)
    for _, child in ipairs(node.children) do
        if child.name == "world" then
            collectSolids(child, "worldspawn", map.brushes)
        elseif child.name == "entity" then
            local classname = child.props.classname or ""
            collectSolids(child, classname, map.brushes)
            table.insert(map.entities, { classname = classname, origin = readVector(child.props.origin), props = child.props })
        elseif child.name == "hidden" then -- a whole entity hidden in the editor
            readBlocks(child, map)
        end
    end
end

---@param text string the .vmf file's contents
---@return MapFile
function Vmf.parse(text)
    local map = { brushes = {}, entities = {} }
    readBlocks(Vmf.parseTree(text), map)
    return map
end

return Vmf
