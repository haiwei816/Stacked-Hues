-- ============================================================================
-- Builders.lua - 场景基础构建（底座、马路、树木、装饰、墙壁/物理辅助）
-- ============================================================================

local Cfg = require("Config")
local Mat = require("Materials")
local CONFIG = Cfg.CONFIG
local COLORS = Cfg.COLORS

local M = {}

-- ============================================================================
-- 通用构建辅助
-- ============================================================================

--- 创建一个简单 Box 模型节点（用于组装火柴人和吧台零件）
---@param parent Node
---@param name string
---@param pos Vector3 世界坐标
---@param scale Vector3
---@param color Color
---@param rot Quaternion|nil
---@return Node
function M.CreatePart(parent, name, pos, scale, color, rot)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    if rot then node.rotation = rot end
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(Mat.CreatePBR(color, 0.0, 0.70))
    model.castShadows = true
    return node
end

--- 创建搁板（视觉 + 选择性物理）
---@param parent Node
---@param name string
---@param y number
---@param width number
---@param depth number
---@param height number
---@param hasPhysics boolean
---@return Node
function M.CreateFloorSlab(parent, name, y, width, depth, height, hasPhysics, overrideColor)
    local scene_ = parent:GetScene()
    local node = scene_:CreateChild(parent:GetName() .. "_" .. name)
    node.position = Vector3(parent.position.x, y, parent.position.z)
    node.scale = Vector3(width, height, depth)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))

    local isRoof = name == "Roof"
    local color = overrideColor or (isRoof and COLORS.TowerRoof or COLORS.TowerFloor)
    model:SetMaterial(Mat.CreatePBR(color, 0.0, 0.75))
    model.castShadows = true

    if hasPhysics then
        local body = node:CreateComponent("RigidBody")
        body.mass = 0
        body.friction = 0.7
        body.restitution = 0.15
        local shape = node:CreateComponent("CollisionShape")
        shape:SetBox(Vector3(1, 1, 1))
    end

    return node
end

--- 创建视觉墙壁（相对于 parent 定位）
---@param parent Node
---@param name string
---@param localPos Vector3
---@param size Vector3
---@param color Color
---@param isGlass boolean
---@return Node
function M.CreateWall(parent, name, localPos, size, color, isGlass)
    local scene_ = parent:GetScene()
    local node = scene_:CreateChild(parent:GetName() .. "_" .. name)
    node.position = Vector3(
        parent.position.x + localPos.x,
        localPos.y,
        parent.position.z + localPos.z
    )
    node.scale = size
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))

    if isGlass then
        model:SetMaterial(Mat.CreateGlass(color))
    else
        model:SetMaterial(Mat.CreatePBR(color, 0.0, 0.70))
    end
    model.castShadows = not isGlass
    return node
end

--- 创建物理墙壁（相对于 parent 定位）
---@param parent Node
---@param name string
---@param localPos Vector3
---@param size Vector3
---@return Node
function M.CreatePhysicsWall(parent, name, localPos, size)
    local scene_ = parent:GetScene()
    local node = scene_:CreateChild(parent:GetName() .. "_" .. name)
    node.position = Vector3(
        parent.position.x + localPos.x,
        localPos.y,
        parent.position.z + localPos.z
    )
    local body = node:CreateComponent("RigidBody")
    body.mass = 0
    body.friction = 0.3
    body.restitution = 0.4
    local shape = node:CreateComponent("CollisionShape")
    shape:SetBox(size)
    return node
end

--- 创建视觉墙壁（世界坐标）
function M.CreateWallWorld(scene_, name, worldPos, size, color, isGlass)
    local node = scene_:CreateChild(name)
    node.position = worldPos
    node.scale = size
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    if isGlass then
        model:SetMaterial(Mat.CreateGlass(color))
    else
        model:SetMaterial(Mat.CreatePBR(color, 0.0, 0.70))
    end
    model.castShadows = not isGlass
    return node
end

--- 创建物理墙壁（世界坐标）
function M.CreatePhysicsWallWorld(scene_, name, worldPos, size)
    local node = scene_:CreateChild(name)
    node.position = worldPos
    local body = node:CreateComponent("RigidBody")
    body.mass = 0
    body.friction = 0.3
    body.restitution = 0.4
    local shape = node:CreateComponent("CollisionShape")
    shape:SetBox(size)
    return node
end

-- ============================================================================
-- 底座
-- ============================================================================

function M.CreateBase(scene_)
    local baseNode = scene_:CreateChild("Base")
    baseNode.position = Vector3(CONFIG.BaseCenterX, -CONFIG.BaseHeight / 2, CONFIG.BaseCenterZ)
    baseNode.scale = Vector3(CONFIG.BaseWidth, CONFIG.BaseHeight, CONFIG.BaseDepth)
    local baseModel = baseNode:CreateComponent("StaticModel")
    baseModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    baseModel:SetMaterial(Mat.CreatePBR(COLORS.Ground, 0.0, 0.80))
    baseModel.castShadows = true

    local baseBody = baseNode:CreateComponent("RigidBody")
    baseBody.mass = 0
    baseBody.friction = 0.8
    baseBody.restitution = 0.2
    local baseShape = baseNode:CreateComponent("CollisionShape")
    baseShape:SetBox(Vector3(1, 1, 1))

    print("[Scene] Base created")
end

-- ============================================================================
-- 马路
-- ============================================================================

function M.CreateRoad(scene_)
    local bcx = CONFIG.BaseCenterX
    local bcz = CONFIG.BaseCenterZ

    local roadZ = bcz + CONFIG.BaseDepth * 0.35
    local roadNode = scene_:CreateChild("Road_H")
    roadNode.position = Vector3(bcx, 0.01, roadZ)
    roadNode.scale = Vector3(CONFIG.BaseWidth, 0.02, CONFIG.RoadWidth)
    local roadModel = roadNode:CreateComponent("StaticModel")
    roadModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    roadModel:SetMaterial(Mat.CreatePBR(COLORS.Road, 0.0, 0.75))

    -- 道路标线（柔和淡金色）
    local lineNode = scene_:CreateChild("RoadLine_H")
    lineNode.position = Vector3(bcx, 0.02, roadZ)
    lineNode.scale = Vector3(CONFIG.BaseWidth * 0.8, 0.01, 0.15)
    local lineModel = lineNode:CreateComponent("StaticModel")
    lineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    lineModel:SetMaterial(Mat.CreatePBR(COLORS.RoadLine, 0.0, 0.65))

    local roadX = bcx - CONFIG.BaseWidth * 0.35
    local roadNode2 = scene_:CreateChild("Road_V")
    roadNode2.position = Vector3(roadX, 0.01, bcz)
    roadNode2.scale = Vector3(CONFIG.RoadWidth, 0.02, CONFIG.BaseDepth)
    local roadModel2 = roadNode2:CreateComponent("StaticModel")
    roadModel2:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    roadModel2:SetMaterial(Mat.CreatePBR(COLORS.Road, 0.0, 0.75))

    for i, dz in ipairs({-1, 1}) do
        local swZ = roadZ + dz * (CONFIG.RoadWidth / 2 + CONFIG.SidewalkWidth / 2)
        local swNode = scene_:CreateChild("Sidewalk_H" .. i)
        swNode.position = Vector3(bcx, 0.05, swZ)
        swNode.scale = Vector3(CONFIG.BaseWidth, 0.1, CONFIG.SidewalkWidth)
        local swModel = swNode:CreateComponent("StaticModel")
        swModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        swModel:SetMaterial(Mat.CreatePBR(COLORS.Sidewalk, 0.0, 0.75))
    end

    print("[Scene] Roads created")
end

-- ============================================================================
-- 行道树
-- ============================================================================

local function CreateTree(scene_, name, position, scale)
    local treeNode = scene_:CreateChild(name)
    treeNode.position = position

    local trunkNode = treeNode:CreateChild("Trunk")
    trunkNode.position = Vector3(0, 0.6 * scale, 0)
    trunkNode.scale = Vector3(0.2 * scale, 1.2 * scale, 0.2 * scale)
    local trunkModel = trunkNode:CreateComponent("StaticModel")
    trunkModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    trunkModel:SetMaterial(Mat.CreatePBR(COLORS.TreeTrunk, 0.0, 0.75))
    trunkModel.castShadows = true

    -- 柔和树冠球体
    local leafNode = treeNode:CreateChild("Leaf")
    leafNode.position = Vector3(0, 1.6 * scale, 0)
    leafNode.scale = Vector3(1.4 * scale, 1.2 * scale, 1.4 * scale)
    local leafModel = leafNode:CreateComponent("StaticModel")
    leafModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local leafColor = (math.random() > 0.5) and COLORS.TreeLeaf or COLORS.TreeLeafAlt
    leafModel:SetMaterial(Mat.CreatePBR(leafColor, 0.0, 0.70))
    leafModel.castShadows = true

    local leaf2Node = treeNode:CreateChild("Leaf2")
    leaf2Node.position = Vector3(0.2 * scale, 2.1 * scale, 0.1 * scale)
    leaf2Node.scale = Vector3(0.9 * scale, 0.8 * scale, 0.9 * scale)
    local leaf2Model = leaf2Node:CreateComponent("StaticModel")
    leaf2Model:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local altColor = COLORS.TreeLeafAlt
    leaf2Model:SetMaterial(Mat.CreatePBR(altColor, 0.0, 0.70))
    leaf2Model.castShadows = true
end

function M.CreateTrees(scene_)
    local treePositions = {
        Vector3(16, 0, 5),
        Vector3(16, 0, -4),
        Vector3(4, 0, 6),
        Vector3(-10, 0, -10),
        Vector3(-10, 0, -18),
        Vector3(0, 0, -21),
        Vector3(4, 0, -8),
        Vector3(-10, 0, -4),
    }

    for i, pos in ipairs(treePositions) do
        CreateTree(scene_, "Tree_" .. i, pos, 0.8 + math.random() * 0.4)
    end

    print("[Scene] Trees created")
end

-- ============================================================================
-- 其他装饰
-- ============================================================================

-- ============================================================================
-- 路灯
-- ============================================================================

local function CreateStreetLamp(scene_, name, pos)
    local lampNode = scene_:CreateChild(name)
    lampNode.position = pos

    -- 灯杆（冷银色）
    local poleNode = lampNode:CreateChild("Pole")
    poleNode.position = Vector3(0, 1.25, 0)
    poleNode.scale = Vector3(0.06, 2.5, 0.06)
    local poleModel = poleNode:CreateComponent("StaticModel")
    poleModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    poleModel:SetMaterial(Mat.CreatePBR(Color(0.70, 0.70, 0.72, 1.0), 0.1, 0.40))
    poleModel.castShadows = true

    -- 灯环（亮银色）
    local ringNode = lampNode:CreateChild("Ring")
    ringNode.position = Vector3(0, 2.40, 0)
    ringNode.scale = Vector3(0.20, 0.06, 0.20)
    local ringModel = ringNode:CreateComponent("StaticModel")
    ringModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    ringModel:SetMaterial(Mat.CreatePBR(Color(0.80, 0.80, 0.82, 1.0), 0.1, 0.35))
    ringModel.castShadows = true

    -- 灯头（冷白强发光）
    local bulbNode = lampNode:CreateChild("Bulb")
    bulbNode.position = Vector3(0, 2.65, 0)
    bulbNode.scale = Vector3(0.25, 0.25, 0.25)
    local bulbModel = bulbNode:CreateComponent("StaticModel")
    bulbModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    bulbModel:SetMaterial(Mat.CreateEmissive(
        Color(0.95, 0.95, 1.0, 1.0),
        Color(1.0, 1.0, 1.2)
    ))
    bulbModel.castShadows = false
end

-- ============================================================================
-- 花丛
-- ============================================================================

local FLOWER_COLORS = {
    Color(1.0, 0.20, 0.40, 1.0),     -- 鲜红玫瑰
    Color(0.70, 0.15, 0.90, 1.0),    -- 电紫
    Color(1.0, 0.90, 0.0, 1.0),      -- 明黄
    Color(1.0, 0.50, 0.0, 1.0),      -- 鲜橘
}

local function CreateFlowerBush(scene_, name, pos)
    local bushNode = scene_:CreateChild(name)
    bushNode.position = pos

    -- 深绿叶丛底座
    local leafBase = bushNode:CreateChild("LeafBase")
    leafBase.position = Vector3(0, 0.08, 0)
    leafBase.scale = Vector3(0.45, 0.16, 0.45)
    local leafModel = leafBase:CreateComponent("StaticModel")
    leafModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    leafModel:SetMaterial(Mat.CreatePBR(Color(0.10, 0.35, 0.15, 1.0), 0.0, 0.50))

    -- 花朵小球（3-5 个）
    local count = 3 + math.random(0, 2)
    for i = 1, count do
        local angle = math.rad(i * 360 / count + math.random(-20, 20))
        local radius = 0.10 + math.random() * 0.08
        local fx = math.cos(angle) * radius
        local fz = math.sin(angle) * radius
        local fy = 0.15 + math.random() * 0.08
        local fs = 0.10 + math.random() * 0.06

        local fNode = bushNode:CreateChild("Flower_" .. i)
        fNode.position = Vector3(fx, fy, fz)
        fNode.scale = Vector3(fs, fs, fs)
        local fModel = fNode:CreateComponent("StaticModel")
        fModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
        local flowerColor = FLOWER_COLORS[math.random(1, #FLOWER_COLORS)]
        fModel:SetMaterial(Mat.CreatePBR(flowerColor, 0.0, 0.35))
    end
end

-- ============================================================================
-- 长椅
-- ============================================================================

local function CreateBench(scene_, name, pos, rotY)
    local benchNode = scene_:CreateChild(name)
    benchNode.position = pos
    benchNode.rotation = Quaternion(rotY or 0, Vector3.UP)

    local woodColor = Color(0.15, 0.12, 0.10, 1.0)
    local woodMat = Mat.CreatePBR(woodColor, 0.0, 0.45)

    -- 座面
    local seat = benchNode:CreateChild("Seat")
    seat.position = Vector3(0, 0.38, 0)
    seat.scale = Vector3(1.2, 0.08, 0.4)
    local seatModel = seat:CreateComponent("StaticModel")
    seatModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    seatModel:SetMaterial(woodMat)
    seatModel.castShadows = true

    -- 靠背
    local back = benchNode:CreateChild("Back")
    back.position = Vector3(0, 0.65, -0.17)
    back.scale = Vector3(1.2, 0.5, 0.06)
    local backModel = back:CreateComponent("StaticModel")
    backModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    backModel:SetMaterial(woodMat)
    backModel.castShadows = true

    -- 腿 x4
    local legPositions = {
        Vector3(-0.5, 0.19, 0.15),
        Vector3(0.5, 0.19, 0.15),
        Vector3(-0.5, 0.19, -0.15),
        Vector3(0.5, 0.19, -0.15),
    }
    for i, lp in ipairs(legPositions) do
        local leg = benchNode:CreateChild("Leg_" .. i)
        leg.position = lp
        leg.scale = Vector3(0.06, 0.38, 0.06)
        local legModel = leg:CreateComponent("StaticModel")
        legModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        legModel:SetMaterial(woodMat)
        legModel.castShadows = true
    end
end

-- ============================================================================
-- 装饰总入口
-- ============================================================================

function M.CreateDecorations(scene_)
    -- 深色装饰柱（高对比度风格）
    local decoStoneColors = {
        Color(0.15, 0.15, 0.18, 1.0),    -- 深炭灰
        Color(0.20, 0.18, 0.22, 1.0),    -- 暗紫灰
        Color(0.12, 0.12, 0.15, 1.0),    -- 近黑
        Color(0.18, 0.18, 0.20, 1.0),    -- 深灰
    }
    local decoPositions = {
        {pos = Vector3(6, 0.4, 4),    color = decoStoneColors[1], s = 0.3},
        {pos = Vector3(-6, 0.4, -8),  color = decoStoneColors[2], s = 0.3},
        {pos = Vector3(0, 0.3, -15),  color = decoStoneColors[3], s = 0.4},
        {pos = Vector3(14, 0.3, -2),  color = decoStoneColors[4], s = 0.3},
    }

    for i, d in ipairs(decoPositions) do
        local node = scene_:CreateChild("Deco_" .. i)
        node.position = d.pos
        node.scale = Vector3(d.s, d.s * 1.6, d.s)
        local model = node:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(Mat.CreatePBR(d.color, 0.0, 0.40))
        model.castShadows = true
    end

    -- 栏杆柱（亮银色）
    local bcx = CONFIG.BaseCenterX
    local bcz = CONFIG.BaseCenterZ
    local halfW = CONFIG.BaseWidth / 2
    local halfD = CONFIG.BaseDepth / 2
    local fenceSpacing = 8.0
    for x = bcx - halfW + 2, bcx + halfW - 2, fenceSpacing do
        for _, z in ipairs({bcz - halfD + 0.2, bcz + halfD - 0.2}) do
            local fNode = scene_:CreateChild("Fence")
            fNode.position = Vector3(x, 0.25, z)
            fNode.scale = Vector3(0.08, 0.5, 0.08)
            local fModel = fNode:CreateComponent("StaticModel")
            fModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
            fModel:SetMaterial(Mat.CreatePBR(COLORS.TowerFrame, 0.0, 0.70))
            fModel.castShadows = true
        end
    end

    -- 路灯 x4（人行道两侧）
    local roadZ = bcz + CONFIG.BaseDepth * 0.35
    local swOffset = CONFIG.RoadWidth / 2 + CONFIG.SidewalkWidth / 2
    CreateStreetLamp(scene_, "Lamp_1", Vector3(5, 0, roadZ + swOffset))
    CreateStreetLamp(scene_, "Lamp_2", Vector3(12, 0, roadZ + swOffset))
    CreateStreetLamp(scene_, "Lamp_3", Vector3(5, 0, roadZ - swOffset))
    CreateStreetLamp(scene_, "Lamp_4", Vector3(-5, 0, roadZ - swOffset))

    -- 花丛 x6（沿人行道和建筑旁散布）
    local flowerPositions = {
        Vector3(8, 0, roadZ + swOffset + 1.0),
        Vector3(15, 0, roadZ + swOffset + 0.8),
        Vector3(-3, 0, roadZ - swOffset - 1.0),
        Vector3(10, 0, roadZ - swOffset - 0.8),
        Vector3(-8, 0, -15),
        Vector3(3, 0, -19),
    }
    for i, fp in ipairs(flowerPositions) do
        CreateFlowerBush(scene_, "FlowerBush_" .. i, fp)
    end

    -- 长椅 x2（人行道旁）
    CreateBench(scene_, "Bench_1", Vector3(9, 0, roadZ + swOffset + 0.5), 0)
    CreateBench(scene_, "Bench_2", Vector3(-2, 0, roadZ - swOffset - 0.5), 180)

    print("[Scene] Decorations created (High Contrast style)")
end

return M
