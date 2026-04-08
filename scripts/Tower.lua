-- ============================================================================
-- Tower.lua - 塔楼创建、楼层叠加、吧台与火柴人
-- ============================================================================

local Cfg = require("Config")
local Mat = require("Materials")
local Builders = require("Builders")
local CONFIG = Cfg.CONFIG
local COLORS = Cfg.COLORS

local M = {}

-- 塔楼运行时状态
M.towers = {}

---@type Node
M.leftRoofNode = nil
---@type Node
M.rightRoofNode = nil

-- 所有火柴人节点（用于每帧朝向相机）
M.stickFigures = {}

-- 正在播放消除动画的果冻列表
M.clearingJellies = {}

-- 正在播放下落动画的果冻列表
M.fallingJellies = {}

-- U 型管转移动画状态
M.transferAnim = nil

-- 积分
M.score = 0
M.onScoreChanged = nil
M.onJellyCleared = nil  -- function() 消除匹配回调（播放音效）

-- 游戏状态
M.gameOver = false
M.onGameOver = nil  -- function() 游戏失败回调

-- 喝酒动画状态
M.drinkingAnims = {}   -- { figNode, armNode, glassNode, timer, duration, phase, ... }
M.sadFaceAnims = {}    -- { mouthSegs, timer, holdDuration, fadeDuration, phase }

-- 倾倒动画状态（从楼顶倒入的果汁液柱）
M.pouringAnims = {}    -- { streamNode, splashNodes, towerData, wineIdx, phase, ... }
M.onPourStart = nil    -- function() 倒入开始回调（播放音效）
M.onDrinkStart = nil   -- function() 喝酒开始回调（播放音效）
M.onDrinkEnd = nil     -- function() 喝完回调（打嗝音效）

-- 楼层庆祝特效状态（干杯后的发光光环 + 星星粒子）
M.floorCelebrations = {}

-- 前向声明（定义在 U 型管部分）
local CheckMatchesAfterTransfer

-- ============================================================================
-- 火柴人（坐姿）
-- ============================================================================

--- 创建火柴人（坐姿，放大版 + 眼睛）
---@param parent Node
---@param name string
---@param basePos Vector3 火柴人脚底世界坐标
---@param facingAngle number 朝向角度（绕 Y 轴）
---@param bodyColor Color|nil 身体颜色（nil 则用默认）
local function CreateStickFigure(parent, name, basePos, facingAngle, bodyColor)
    local fig = parent:CreateChild(name)
    fig.position = basePos
    fig.rotation = Quaternion(facingAngle, Vector3.UP)

    local s = 1.8
    local bc = bodyColor or COLORS.StickBody
    local hc = COLORS.StickHead
    local eyeColor = Color(0.02, 0.02, 0.02, 1.0)

    -- 双腿（站立姿态，直立向下）
    local legH = 0.65 * s
    local legBaseY = legH / 2
    Builders.CreatePart(fig, "LLeg", Vector3(-0.12 * s, legBaseY, 0), Vector3(0.08 * s, legH, 0.08 * s), bc)
    Builders.CreatePart(fig, "RLeg", Vector3(0.12 * s, legBaseY, 0), Vector3(0.08 * s, legH, 0.08 * s), bc)

    -- 躯干
    local torsoH = 0.55 * s
    local torsoY = legH + torsoH / 2
    Builders.CreatePart(fig, "Torso", Vector3(0, torsoY, 0.05 * s), Vector3(0.28 * s, torsoH, 0.15 * s), bc)

    -- 头部组（头+眼睛统一旋转，面向摄像机）
    local headR = 0.16 * s
    local headY = torsoY + torsoH / 2 + headR
    local headGroup = fig:CreateChild("HeadGroup")
    headGroup.position = Vector3(0, headY, 0.05 * s)  -- 头部中心位置

    -- 头（球形，HeadGroup 子节点）
    local headNode = headGroup:CreateChild("Head")
    headNode.position = Vector3(0, 0, 0)
    headNode.scale = Vector3(headR * 2, headR * 2, headR * 2)
    local headModel = headNode:CreateComponent("StaticModel")
    headModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    headModel:SetMaterial(Mat.CreatePBR(hc, 0.0, 0.65))
    headModel.castShadows = true

    -- 眼睛（HeadGroup 子节点，相对头部中心定位）
    local eyeR = 0.03 * s
    local eyeSpacing = 0.06 * s
    local eyeForward = headR + eyeR * 0.5  -- 方块表面 = headR，眼睛微凸
    local eyeUp = headR * 0.15

    local lEye = headGroup:CreateChild("LEye")
    lEye.position = Vector3(-eyeSpacing, eyeUp, eyeForward)
    lEye.scale = Vector3(eyeR * 2, eyeR * 2, eyeR * 2)
    local lEyeModel = lEye:CreateComponent("StaticModel")
    lEyeModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    lEyeModel:SetMaterial(Mat.CreatePBR(eyeColor, 0.0, 0.3))

    local rEye = headGroup:CreateChild("REye")
    rEye.position = Vector3(eyeSpacing, eyeUp, eyeForward)
    rEye.scale = Vector3(eyeR * 2, eyeR * 2, eyeR * 2)
    local rEyeModel = rEye:CreateComponent("StaticModel")
    rEyeModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    rEyeModel:SetMaterial(Mat.CreatePBR(eyeColor, 0.0, 0.3))

    -- 嘴巴（5 段小方块组成横线，喝酒时变弯成笑脸）
    local mouthY = -headR * 0.25         -- 嘴巴在头部中心偏下
    local mouthZ = headR + 0.005 * s     -- 方块表面 = headR，微凸确保可见
    local mSegW = 0.028 * s              -- 每段宽度（加大）
    local mSegH = 0.014 * s              -- 每段高度
    local mSegD = 0.020 * s              -- 每段深度（加厚，穿透球面）
    local mSpacing = 0.024 * s           -- 段间距
    local mouthMat = Mat.CreatePBR(eyeColor, 0.0, 0.3)  -- 与眼睛同色

    for seg = 1, 5 do
        local xOff = (seg - 3) * mSpacing  -- seg 1~5 → -2,-1,0,1,2 × spacing
        local mNode = headGroup:CreateChild("Mouth_" .. seg)
        mNode.position = Vector3(xOff, mouthY, mouthZ)
        mNode.scale = Vector3(mSegW, mSegH, mSegD)
        local mModel = mNode:CreateComponent("StaticModel")
        mModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        mModel:SetMaterial(mouthMat)
        mModel.castShadows = false
    end

    -- 上臂（自然下垂，左臂不变，右臂作为可动部件）
    local armLen = 0.30 * s
    local armY = torsoY - torsoH * 0.05
    Builders.CreatePart(fig, "LArm", Vector3(-0.22 * s, armY - armLen / 2, 0.05 * s), Vector3(0.07 * s, armLen, 0.07 * s), bc)

    -- 右臂：用子节点作为关节点，方便干杯动画旋转
    -- 默认姿势：抬起 -70 度，单手举杯在胸前
    local HOLD_ANGLE = -70  -- 默认举杯角度
    local rArmPivot = fig:CreateChild("RArmPivot")
    rArmPivot.position = Vector3(0.22 * s, armY, 0.05 * s)  -- 肩膀位置
    rArmPivot.rotation = Quaternion(HOLD_ANGLE, Vector3.RIGHT)

    local rArmMesh = rArmPivot:CreateChild("RArmMesh")
    rArmMesh.position = Vector3(0, -armLen / 2, 0)  -- 从肩膀往下延伸
    rArmMesh.scale = Vector3(0.07 * s, armLen, 0.07 * s)
    local rArmModel = rArmMesh:CreateComponent("StaticModel")
    rArmModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    rArmModel:SetMaterial(Mat.CreatePBR(bc, 0.0, 0.55))
    rArmModel.castShadows = true

    -- 啤酒杯（挂在右手末端）
    local glassParent = rArmPivot:CreateChild("GlassHolder")
    glassParent.position = Vector3(0, -armLen, 0.02 * s)  -- 手的位置

    -- 杯身（矮胖圆柱）
    local mugH = 0.16 * s
    local mugR = 0.065 * s
    local mugBody = glassParent:CreateChild("MugBody")
    mugBody.position = Vector3(0, mugH / 2, 0)
    mugBody.scale = Vector3(mugR * 2, mugH, mugR * 2)
    local mugModel = mugBody:CreateComponent("StaticModel")
    mugModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    mugModel:SetMaterial(Mat.CreateGlass(Color(0.75, 0.82, 0.90, 0.12)))
    mugModel.castShadows = false

    -- 啤酒液体（黄色不透明圆柱，略小于杯身）
    local beerH = mugH * 0.7
    local beerNode = glassParent:CreateChild("Beer")
    beerNode.position = Vector3(0, beerH / 2 + 0.01 * s, 0)
    beerNode.scale = Vector3(mugR * 1.7, beerH, mugR * 1.7)
    local beerModel = beerNode:CreateComponent("StaticModel")
    beerModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    beerModel:SetMaterial(Mat.CreatePBR(Color(1.0, 0.75, 0.0, 1.0), 0.0, 0.30))
    beerModel.castShadows = false

    -- 泡沫层（白色扁圆柱在液面上）
    local foamNode = glassParent:CreateChild("Foam")
    foamNode.position = Vector3(0, beerH + 0.01 * s + 0.015 * s, 0)
    foamNode.scale = Vector3(mugR * 1.8, 0.04 * s, mugR * 1.8)
    local foamModel = foamNode:CreateComponent("StaticModel")
    foamModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    foamModel:SetMaterial(Mat.CreatePBR(Color(1.0, 1.0, 1.0, 1.0), 0.0, 0.40))
    foamModel.castShadows = false

    -- 杯口（薄环）
    local rimNode = glassParent:CreateChild("MugRim")
    rimNode.position = Vector3(0, mugH, 0)
    rimNode.scale = Vector3(mugR * 2.4, 0.015 * s, mugR * 2.4)
    local rimModel = rimNode:CreateComponent("StaticModel")
    rimModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    rimModel:SetMaterial(Mat.CreateGlass(Color(0.75, 0.82, 0.90, 0.10)))
    rimModel.castShadows = false

    -- 把手（用小方块模拟）
    local handleW = 0.025 * s
    local handleH = mugH * 0.55
    local handleNode = glassParent:CreateChild("MugHandle")
    handleNode.position = Vector3(mugR + handleW / 2 + 0.005 * s, mugH * 0.45, 0)
    handleNode.scale = Vector3(handleW, handleH, handleW)
    local handleModel = handleNode:CreateComponent("StaticModel")
    handleModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    handleModel:SetMaterial(Mat.CreateGlass(Color(0.75, 0.82, 0.90, 0.10)))
    handleModel.castShadows = false

    table.insert(M.stickFigures, fig)
end

-- ============================================================================
-- 吧台 & 顾客
-- ============================================================================

--- 在指定楼层创建吧台和顾客
---@param scene_ Scene
---@param towerName string
---@param floorIdx number 楼层索引 (0-based)
---@param floorY number 楼层搁板顶面 Y（世界坐标）
---@param towerW number 塔宽
---@param towerD number 塔深
---@param openFace string 开口面
---@param centerX number 塔中心 X
---@param centerZ number 塔中心 Z
---@param wineIdx number 该楼层对应的酒类索引
local function CreateBarAndCustomers(scene_, towerName, floorIdx, floorY, towerW, towerD, openFace, centerX, centerZ, wineIdx)
    local st = CONFIG.ShelfThickness
    local baseY = floorY + st / 2

    local barH = 1.1
    local barThick = 0.4
    local barTopH = 0.08

    local barLen, barX, barZ, barRotY, seatDir
    barX = centerX
    barZ = centerZ
    if towerW >= towerD then
        barLen = towerW * 0.6
        barRotY = 0
        seatDir = { x = 0, z = 1 }
    else
        barLen = towerD * 0.6
        barRotY = 90
        seatDir = { x = -1, z = 0 }
    end

    local sceneRoot = scene_

    -- 吧台主体
    local counterPos = Vector3(barX, baseY + barH / 2, barZ)
    Builders.CreatePart(sceneRoot, towerName .. "_Bar_" .. floorIdx,
        counterPos, Vector3(barLen, barH, barThick),
        COLORS.BarCounter, barRotY ~= 0 and Quaternion(barRotY, Vector3.UP) or nil)

    -- 吧台台面
    local topPos = Vector3(barX, baseY + barH + barTopH / 2, barZ)
    Builders.CreatePart(sceneRoot, towerName .. "_BarTop_" .. floorIdx,
        topPos, Vector3(barLen + 0.15, barTopH, barThick + 0.1),
        COLORS.BarTop, barRotY ~= 0 and Quaternion(barRotY, Vector3.UP) or nil)

    -- 吧台灯（冷白强发光）
    local lampPos = Vector3(barX, baseY + barH + 1.5, barZ)
    local lampNode = sceneRoot:CreateChild(towerName .. "_BarLamp_" .. floorIdx)
    lampNode.position = lampPos
    lampNode.scale = Vector3(0.12, 0.12, 0.12)
    local lampModel = lampNode:CreateComponent("StaticModel")
    lampModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    lampModel:SetMaterial(Mat.CreateEmissive(
        Color(0.95, 0.95, 1.0, 1.0),
        Color(0.9, 0.9, 1.1)
    ))

    -- 顾客（身体颜色 = 对应酒类颜色）
    local wine = Cfg.WINE_TYPES[wineIdx]
    local figBodyColor = Color(wine.color.r, wine.color.g, wine.color.b, 1.0)

    -- 吧台前方3人 + 吧台后方3人 = 共6人，对称排列
    local custPerSide = barLen > 4.0 and 3 or 2
    local figBaseY = baseY
    local custIdx = 0

    for side = 1, 2 do
        local sideSign = (side == 1) and 1 or -1  -- 前方 / 后方

        for c = 1, custPerSide do
            custIdx = custIdx + 1
            local t = c / (custPerSide + 1) - 0.5

            local cx, cz
            if barRotY == 0 then
                cx = barX + t * barLen
                cz = barZ + sideSign * (barThick / 2 + 0.5)
            else
                cx = barX + sideSign * (barThick / 2 + 0.5)
                cz = barZ + t * barLen
            end

            local figAngle
            if barRotY == 0 then
                figAngle = sideSign > 0 and 0 or 180
            else
                figAngle = sideSign > 0 and 90 or -90
            end
            CreateStickFigure(sceneRoot, towerName .. "_Cust_" .. floorIdx .. "_" .. custIdx,
                Vector3(cx, figBaseY, cz), figAngle, figBodyColor)
        end
    end
end

-- ============================================================================
-- 创建单座塔楼
-- ============================================================================

--- @param assignedWineTypes table|nil 外部指定的酒类列表（0-based key），nil 则随机
function M.CreateSingleTower(scene_, name, centerX, centerZ, towerW, towerD, openFace, isLeft, assignedWineTypes)
    local towerParent = scene_:CreateChild(name)
    towerParent.position = Vector3(centerX, 0, centerZ)

    local tw = towerW
    local td = towerD
    local wt = CONFIG.WallThickness
    local tunnelH = CONFIG.TunnelHeight
    local st = CONFIG.ShelfThickness
    local so = CONFIG.ShelfOverhang
    local spacing = CONFIG.FloorSpacing
    local floorCount = CONFIG.FloorCount
    local th = floorCount * spacing

    -- 使用外部分配的酒类列表，或回退随机
    local floorWineTypes = {}
    for f = 0, floorCount - 1 do
        floorWineTypes[f] = assignedWineTypes and assignedWineTypes[f] or math.random(1, #Cfg.WINE_TYPES)
    end

    for f = 0, floorCount do
        local floorY = f * spacing
        local shelfW = tw + so * 2
        local shelfD = td + so * 2

        -- 楼层地板颜色与该层 NPC（酒类）颜色一致
        local floorColor = nil
        if f < floorCount then
            local wine = Cfg.WINE_TYPES[floorWineTypes[f]]
            floorColor = Color(wine.color.r, wine.color.g, wine.color.b, 1.0)
        end

        if f == floorCount then
            local roofNode = Builders.CreateFloorSlab(towerParent, "Roof", floorY, shelfW + 0.2, shelfD + 0.2, st, true)
            if isLeft then
                M.leftRoofNode = roofNode
            else
                M.rightRoofNode = roofNode
            end
        elseif f == 0 then
            Builders.CreateFloorSlab(towerParent, "Shelf_" .. f, floorY, shelfW, shelfD, st, true, floorColor)
        else
            Builders.CreateFloorSlab(towerParent, "Shelf_" .. f, floorY, shelfW, shelfD, st, false, floorColor)
        end

        if f < floorCount then
            CreateBarAndCustomers(scene_, name, f, floorY, tw, td, openFace, centerX, centerZ, floorWineTypes[f])
        end
    end

    -- 墙壁
    local wallBandH = spacing - st
    if wallBandH < 0.3 then wallBandH = 0.3 end

    local wallDefs = {
        { face = "north", px = 0, pz = td/2 - wt/2, sx = tw, sz = wt },
        { face = "south", px = 0, pz = -td/2 + wt/2, sx = tw, sz = wt },
        { face = "east",  px = tw/2 - wt/2, pz = 0, sx = wt, sz = td },
        { face = "west",  px = -tw/2 + wt/2, pz = 0, sx = wt, sz = td },
    }

    -- 外侧面：openFace 的对面，用不透明果汁颜色
    local outerFace = ({ north = "south", south = "north", east = "west", west = "east" })[openFace]

    for _, wd in ipairs(wallDefs) do
        for f = 0, floorCount - 1 do
            local bandY = f * spacing + st / 2 + wallBandH / 2

            if wd.face == openFace and bandY < tunnelH then
                -- 隧道开口
            elseif wd.face == outerFace then
                -- 外侧面：不透明果汁颜色
                local wine = Cfg.WINE_TYPES[floorWineTypes[f]]
                local wallColor = Color(wine.color.r, wine.color.g, wine.color.b, 1.0)
                Builders.CreateWall(towerParent, wd.face .. "_Band_" .. f,
                    Vector3(wd.px, bandY, wd.pz),
                    Vector3(wd.sx, wallBandH, wd.sz),
                    wallColor, false)

                Builders.CreatePhysicsWall(towerParent, "Phys_" .. wd.face .. "_B" .. f,
                    Vector3(wd.px, bandY, wd.pz),
                    Vector3(wd.sx, wallBandH, wd.sz))
            else
                Builders.CreateWall(towerParent, wd.face .. "_Band_" .. f,
                    Vector3(wd.px, bandY, wd.pz),
                    Vector3(wd.sx, wallBandH, wd.sz),
                    COLORS.TowerGlass, true)

                Builders.CreatePhysicsWall(towerParent, "Phys_" .. wd.face .. "_B" .. f,
                    Vector3(wd.px, bandY, wd.pz),
                    Vector3(wd.sx, wallBandH, wd.sz))
            end
        end

        if wd.face == openFace then
            local upperH = th - tunnelH
            if upperH > 0 then
                local upperY = tunnelH + upperH / 2
                Builders.CreateWall(towerParent, wd.face .. "_UpperGlass",
                    Vector3(wd.px, upperY, wd.pz),
                    Vector3(wd.sx, upperH, wd.sz),
                    COLORS.TowerGlass, true)
                Builders.CreatePhysicsWall(towerParent, "Phys_" .. wd.face .. "_Upper",
                    Vector3(wd.px, upperY, wd.pz),
                    Vector3(wd.sx, upperH, wd.sz))
            end
        end
    end

    local towerData = {
        name = name,
        parent = towerParent,
        centerX = centerX,
        centerZ = centerZ,
        towerW = tw,
        towerD = td,
        openFace = openFace,
        isLeft = isLeft,
        currentFloors = floorCount,
        wallDefs = wallDefs,
        filledFloors = 0,
        jellyNodes = {},
        floorWineTypes = floorWineTypes,
        actualWineTypes = {},   -- 实际填入的酒类 [floorIdx(0-based)] = wineIdx
    }
    table.insert(M.towers, towerData)
end

-- ============================================================================
-- 创建双子楼
-- ============================================================================

function M.CreateTowers(scene_)
    -- 打乱 6 种酒类，前 3 种分配给右塔，后 3 种分配给左塔
    local indices = {}
    for i = 1, #Cfg.WINE_TYPES do
        indices[i] = i
    end
    -- Fisher-Yates 洗牌
    for i = #indices, 2, -1 do
        local j = math.random(1, i)
        indices[i], indices[j] = indices[j], indices[i]
    end

    -- 构建 0-based assignedWineTypes 表（与楼层索引对齐）
    local rightWines = {}
    local leftWines = {}
    for f = 0, CONFIG.FloorCount - 1 do
        rightWines[f] = indices[f + 1]           -- 前 3 种给右塔
        leftWines[f] = indices[f + 1 + CONFIG.FloorCount]  -- 后 3 种给左塔
    end

    M.CreateSingleTower(scene_, "RightTower", CONFIG.RightTowerX, CONFIG.RightTowerZ,
        CONFIG.RightTowerW, CONFIG.RightTowerD, CONFIG.RightOpenFace, false, rightWines)

    M.CreateSingleTower(scene_, "LeftTower", CONFIG.LeftTowerX, CONFIG.LeftTowerZ,
        CONFIG.LeftTowerW, CONFIG.LeftTowerD, CONFIG.LeftOpenFace, true, leftWines)

    print("[Scene] Towers created (diagonal layout, " .. CONFIG.FloorCount .. " floors × 2 towers, 6 wine types shuffled)")
end

-- ============================================================================
-- 动态楼层叠加
-- ============================================================================

--- 为某座塔楼添加一层
---@param data table towers 中的一项
---@param updateCamera function(y) 回调：更新相机目标 Y
function M.AddFloorToTower(data, updateCamera)
    local scene_ = data.parent:GetScene()
    if data.currentFloors >= CONFIG.MaxFloors then
        print("[Tower] " .. data.name .. " reached max floors (" .. CONFIG.MaxFloors .. ")")
        return
    end

    local tw = data.towerW
    local td = data.towerD
    local st = CONFIG.ShelfThickness
    local so = CONFIG.ShelfOverhang
    local spacing = CONFIG.FloorSpacing
    local tunnelH = CONFIG.TunnelHeight
    local parent = data.parent
    local f = data.currentFloors

    -- 1. 删除旧天台
    local oldRoofName = data.name .. "_Roof"
    local oldRoof = scene_:GetChild(oldRoofName, true)
    if oldRoof then
        oldRoof:Remove()
    end

    -- 2. 旧天台位置放中间搁板
    local oldRoofY = f * spacing
    local shelfW = tw + so * 2
    local shelfD = td + so * 2

    -- 2.5 新楼层分配酒类、吧台和顾客
    data.floorWineTypes[f] = math.random(1, #Cfg.WINE_TYPES)
    local wine = Cfg.WINE_TYPES[data.floorWineTypes[f]]
    local floorColor = Color(wine.color.r, wine.color.g, wine.color.b, 1.0)
    Builders.CreateFloorSlab(parent, "Shelf_" .. f, oldRoofY, shelfW, shelfD, st, false, floorColor)
    CreateBarAndCustomers(scene_, data.name, f, oldRoofY, tw, td, data.openFace, data.centerX, data.centerZ, data.floorWineTypes[f])

    -- 3. 墙带
    local wallBandH = spacing - st
    if wallBandH < 0.3 then wallBandH = 0.3 end
    local bandY = f * spacing + st / 2 + wallBandH / 2

    local outerFace = ({ north = "south", south = "north", east = "west", west = "east" })[data.openFace]

    for _, wd in ipairs(data.wallDefs) do
        if wd.face == data.openFace and bandY < tunnelH then
            -- 隧道开口
        elseif wd.face == outerFace then
            -- 外侧面：不透明果汁颜色
            local wallColor = Color(wine.color.r, wine.color.g, wine.color.b, 1.0)
            Builders.CreateWall(parent, wd.face .. "_Band_" .. f,
                Vector3(wd.px, bandY, wd.pz),
                Vector3(wd.sx, wallBandH, wd.sz),
                wallColor, false)

            Builders.CreatePhysicsWall(parent, "Phys_" .. wd.face .. "_B" .. f,
                Vector3(wd.px, bandY, wd.pz),
                Vector3(wd.sx, wallBandH, wd.sz))
        else
            Builders.CreateWall(parent, wd.face .. "_Band_" .. f,
                Vector3(wd.px, bandY, wd.pz),
                Vector3(wd.sx, wallBandH, wd.sz),
                COLORS.TowerGlass, true)

            Builders.CreatePhysicsWall(parent, "Phys_" .. wd.face .. "_B" .. f,
                Vector3(wd.px, bandY, wd.pz),
                Vector3(wd.sx, wallBandH, wd.sz))
        end
    end

    -- 4. 新天台
    data.currentFloors = f + 1
    local newRoofY = data.currentFloors * spacing
    local roofNode = Builders.CreateFloorSlab(parent, "Roof", newRoofY, shelfW + 0.2, shelfD + 0.2, st, true)

    if data.isLeft then
        M.leftRoofNode = roofNode
    else
        M.rightRoofNode = roofNode
    end

    -- 5. 更新开口面上方墙
    local oldUpperName = data.name .. "_" .. data.openFace .. "_UpperGlass"
    local oldUpper = scene_:GetChild(oldUpperName, true)
    if oldUpper then oldUpper:Remove() end
    local oldUpperPhys = scene_:GetChild(data.name .. "_Phys_" .. data.openFace .. "_Upper", true)
    if oldUpperPhys then oldUpperPhys:Remove() end

    local newTh = data.currentFloors * spacing
    local upperH = newTh - tunnelH
    if upperH > 0 then
        local upperY = tunnelH + upperH / 2
        for _, wd in ipairs(data.wallDefs) do
            if wd.face == data.openFace then
                Builders.CreateWall(parent, data.openFace .. "_UpperGlass",
                    Vector3(wd.px, upperY, wd.pz),
                    Vector3(wd.sx, upperH, wd.sz),
                    COLORS.TowerGlass, true)
                Builders.CreatePhysicsWall(parent, "Phys_" .. data.openFace .. "_Upper",
                    Vector3(wd.px, upperY, wd.pz),
                    Vector3(wd.sx, upperH, wd.sz))
                break
            end
        end
    end

    if updateCamera then
        updateCamera(data.currentFloors * spacing * 0.5)
    end

    print("[Tower] " .. data.name .. " now has " .. data.currentFloors .. " floors")
end

--- 为所有塔楼添加一层
---@param updateCamera function(y)
function M.AddFloorToAllTowers(updateCamera)
    for _, towerData in ipairs(M.towers) do
        M.AddFloorToTower(towerData, updateCamera)
    end
end

-- ============================================================================
-- 果冻填充
-- ============================================================================

--- 正在播放填充动画的果冻列表
M.fillingJellies = {}

--- 填满塔楼的下一层果冻（现在先启动倾倒动画，动画完成后再填充）
---@param towerData table towers 中的一项
---@param wineIdx number 当前酒类索引
---@return boolean matched 是否匹配该楼层需求
function M.FillTowerFloor(towerData, wineIdx)
    local scene_ = towerData.parent:GetScene()
    local f = towerData.filledFloors
    if f >= towerData.currentFloors then
        print("[Jelly] " .. towerData.name .. " is full!")
        return false
    end

    -- 检测是否匹配该楼层需求
    local floorWantIdx = towerData.floorWineTypes[f]
    local matched = (wineIdx == floorWantIdx)

    -- 先占位（标记楼层已被使用，防止重复填充）
    towerData.filledFloors = f + 1
    towerData.actualWineTypes[f] = wineIdx

    -- 启动倾倒动画（液柱从楼顶流到目标楼层）
    M.StartPouringAnim(scene_, towerData, wineIdx, f, matched)

    if matched then
        M.score = M.score + 100
        if M.onScoreChanged then M.onScoreChanged() end
        if M.onJellyCleared then M.onJellyCleared() end
        print("[Jelly] MATCH! Floor " .. f .. " of " .. towerData.name .. " +100 pts (Score: " .. M.score .. ")")
    else
        print("[Jelly] No match. Floor " .. f .. " wants " .. Cfg.WINE_TYPES[floorWantIdx].name .. ", got " .. Cfg.WINE_TYPES[wineIdx].name)
    end

    return matched
end

-- ============================================================================
-- 倾倒动画（从楼顶倒入果汁）
-- ============================================================================

--- 启动倾倒动画
---@param scene_ Scene
---@param towerData table
---@param wineIdx number
---@param floorIdx number 目标楼层 (0-based)
---@param matched boolean
function M.StartPouringAnim(scene_, towerData, wineIdx, floorIdx, matched)
    local wine = Cfg.WINE_TYPES[wineIdx]
    local spacing = CONFIG.FloorSpacing
    local st = CONFIG.ShelfThickness

    -- 楼顶 Y 坐标
    local roofY = towerData.currentFloors * spacing + st / 2
    -- 目标楼层底部 Y
    local targetBottomY = floorIdx * spacing + st / 2

    -- 液柱参数
    local streamRadius = 0.35  -- 液柱半径
    local streamStartY = roofY + 2.5  -- 液柱从楼顶上方开始
    local streamEndY = targetBottomY  -- 液柱最终到达目标楼层

    -- 创建液柱节点（圆柱，从楼顶上方开始，初始高度为 0）
    local streamNode = scene_:CreateChild(towerData.name .. "_PourStream_" .. floorIdx)
    streamNode.position = Vector3(towerData.centerX, streamStartY, towerData.centerZ)
    streamNode.scale = Vector3(streamRadius * 2, 0.01, streamRadius * 2)

    local model = streamNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(Mat.CreateJelly(wine))
    model.castShadows = false

    -- 飞溅粒子节点列表（到达底部时产生小水花）
    local splashNodes = {}

    local anim = {
        streamNode = streamNode,
        splashNodes = splashNodes,
        towerData = towerData,
        wineIdx = wineIdx,
        floorIdx = floorIdx,
        matched = matched,
        wine = wine,
        -- 阶段: "pour_down" → "fill" → "retract" → done
        phase = "pour_down",
        timer = 0,
        -- 液柱从上方下延的参数
        streamTopY = streamStartY,  -- 液柱顶端固定
        streamBottomY = streamStartY,  -- 液柱底端（向下延伸）
        streamTargetBottomY = streamEndY,
        streamRadius = streamRadius,
        pourSpeed = math.max((streamStartY - streamEndY) / 0.5, 35.0),  -- 动态速度：保证 0.5s 内落完，最低 35m/s
        -- 缩回阶段参数
        retractSpeed = math.max((streamStartY - streamEndY) / 0.4, 40.0),  -- 动态速度：保证 0.4s 内缩回
        -- 飞溅效果
        splashSpawned = false,
    }

    table.insert(M.pouringAnims, anim)

    -- 触发倾倒开始回调（播放音效）
    if M.onPourStart then M.onPourStart() end

    print("[Pour] Start pouring " .. wine.name .. " into " .. towerData.name .. " floor " .. floorIdx)
end

--- 在目标楼层创建果冻并启动填充动画（倾倒到达后调用）
---@param anim table pouringAnims 中的一项
local function StartFloorFill(anim)
    local scene_ = anim.towerData.parent:GetScene()
    local towerData = anim.towerData
    local f = anim.floorIdx
    local wineIdx = anim.wineIdx
    local wine = anim.wine

    local spacing = CONFIG.FloorSpacing
    local st = CONFIG.ShelfThickness
    local wt = CONFIG.WallThickness

    local jellyH = spacing - st
    local bottomY = f * spacing + st / 2
    local targetY = bottomY + jellyH / 2
    local jellyW = towerData.towerW - wt * 2 - 0.2
    local jellyD = towerData.towerD - wt * 2 - 0.2

    local jellyNode = scene_:CreateChild(towerData.name .. "_Jelly_" .. f)
    jellyNode.position = Vector3(towerData.centerX, bottomY, towerData.centerZ)
    jellyNode.scale = Vector3(jellyW, 0.01, jellyD)

    local model = jellyNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(Mat.CreateJelly(wine))
    model.castShadows = true

    table.insert(M.fillingJellies, {
        node = jellyNode,
        bottomY = bottomY,
        targetH = jellyH,
        targetY = targetY,
        currentH = 0.01,
        width = jellyW,
        depth = jellyD,
        speed = jellyH / 0.6,
        matched = anim.matched,
        towerData = towerData,
        floorIdx = f,
    })

    table.insert(towerData.jellyNodes, jellyNode)
end

--- 创建飞溅效果（小球四散）
---@param scene_ Scene
---@param anim table
local function SpawnSplashParticles(scene_, anim)
    local wine = anim.wine
    local cx = anim.towerData.centerX
    local cz = anim.towerData.centerZ
    local splashY = anim.streamTargetBottomY + 0.3

    local particleCount = 6
    for i = 1, particleCount do
        local angle = (i / particleCount) * math.pi * 2 + math.random() * 0.5
        local dist = 0.3 + math.random() * 0.5
        local px = cx + math.cos(angle) * dist
        local pz = cz + math.sin(angle) * dist
        local size = 0.08 + math.random() * 0.12

        local pNode = scene_:CreateChild("Splash_" .. i)
        pNode.position = Vector3(px, splashY, pz)
        pNode.scale = Vector3(size, size, size)

        local pModel = pNode:CreateComponent("StaticModel")
        pModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        pModel:SetMaterial(Mat.CreateJelly(wine))
        pModel.castShadows = false

        table.insert(anim.splashNodes, {
            node = pNode,
            startY = splashY,
            velY = 2.0 + math.random() * 3.0,  -- 向上初速度
            velX = math.cos(angle) * (1.5 + math.random() * 1.5),
            velZ = math.sin(angle) * (1.5 + math.random() * 1.5),
            timer = 0,
            lifetime = 0.4 + math.random() * 0.3,
            startSize = size,
        })
    end
end

--- 更新倾倒动画（每帧调用）
---@param dt number
function M.UpdatePouringAnims(dt)
    local i = 1
    while i <= #M.pouringAnims do
        local anim = M.pouringAnims[i]
        anim.timer = anim.timer + dt

        if anim.phase == "pour_down" then
            -- 液柱底端向下延伸
            anim.streamBottomY = anim.streamBottomY - anim.pourSpeed * dt

            if anim.streamBottomY <= anim.streamTargetBottomY then
                anim.streamBottomY = anim.streamTargetBottomY

                -- 生成飞溅效果
                if not anim.splashSpawned then
                    anim.splashSpawned = true
                    local scene_ = anim.towerData.parent:GetScene()
                    SpawnSplashParticles(scene_, anim)
                end

                -- 开始楼层果冻填充
                StartFloorFill(anim)

                -- 进入填充阶段（液柱保持一小会儿）
                anim.phase = "fill"
                anim.timer = 0
            end

            -- 更新液柱视觉
            local streamH = anim.streamTopY - anim.streamBottomY
            if streamH < 0.01 then streamH = 0.01 end
            local centerY = (anim.streamTopY + anim.streamBottomY) / 2
            anim.streamNode.position = Vector3(
                anim.towerData.centerX, centerY, anim.towerData.centerZ
            )
            anim.streamNode.scale = Vector3(
                anim.streamRadius * 2, streamH, anim.streamRadius * 2
            )

        elseif anim.phase == "fill" then
            -- 液柱保持 0.3 秒，然后开始从底部缩回
            if anim.timer >= 0.3 then
                anim.phase = "retract"
                anim.timer = 0
            end

        elseif anim.phase == "retract" then
            -- 液柱底端向上缩回
            anim.streamBottomY = anim.streamBottomY + anim.retractSpeed * dt

            if anim.streamBottomY >= anim.streamTopY then
                -- 缩回完成，移除液柱
                anim.streamNode:Remove()

                -- 移除所有飞溅粒子
                for _, sp in ipairs(anim.splashNodes) do
                    if sp.node then
                        sp.node:Remove()
                    end
                end

                table.remove(M.pouringAnims, i)
                print("[Pour] Pour animation complete for " .. anim.towerData.name)
                goto continue
            end

            -- 更新液柱视觉
            local streamH = anim.streamTopY - anim.streamBottomY
            if streamH < 0.01 then streamH = 0.01 end
            local centerY = (anim.streamTopY + anim.streamBottomY) / 2
            anim.streamNode.position = Vector3(
                anim.towerData.centerX, centerY, anim.towerData.centerZ
            )
            anim.streamNode.scale = Vector3(
                anim.streamRadius * 2, streamH, anim.streamRadius * 2
            )
        end

        -- 更新飞溅粒子（重力 + 缩小消失）
        local si = 1
        while si <= #anim.splashNodes do
            local sp = anim.splashNodes[si]
            sp.timer = sp.timer + dt

            if sp.timer >= sp.lifetime then
                if sp.node then sp.node:Remove() end
                table.remove(anim.splashNodes, si)
            else
                -- 物理模拟：抛物线运动
                sp.velY = sp.velY - 15.0 * dt  -- 重力
                local pos = sp.node.position
                sp.node.position = Vector3(
                    pos.x + sp.velX * dt,
                    pos.y + sp.velY * dt,
                    pos.z + sp.velZ * dt
                )
                -- 逐渐缩小
                local lifeRatio = 1.0 - sp.timer / sp.lifetime
                local curSize = sp.startSize * lifeRatio
                if curSize < 0.01 then curSize = 0.01 end
                sp.node.scale = Vector3(curSize, curSize, curSize)

                si = si + 1
            end
        end

        i = i + 1
        ::continue::
    end
end

-- 默认举杯角度（与 CreateStickFigure 中 HOLD_ANGLE 保持一致）
local HOLD_ANGLE = -70
local CHEERS_ANGLE = -150  -- 干杯最高角度
local OVERHEAD_ANGLE = -195 -- 举过头顶角度

--- 设置嘴巴形态（0=直线，1=笑脸弧线，-1=哭脸弧线）
---@param mouthSegs table 嘴巴段数组 { node, origY, origX, origZ }
---@param smile number -1~1 表情程度
local function SetMouthShape(mouthSegs, smile)
    if #mouthSegs ~= 5 then return end
    local offsets = { 2, 1, 0, 1, 2 }
    local maxLift = 0.025
    local maxRot = 45
    local rotSigns = { 1, 0.5, 0, -0.5, -1 }

    for idx, seg in ipairs(mouthSegs) do
        local lift = smile * offsets[idx] * maxLift
        seg.node.position = Vector3(seg.origX, seg.origY + lift, seg.origZ)
        local rot = smile * rotSigns[idx] * maxRot
        seg.node.rotation = Quaternion(rot, Vector3.FORWARD)
    end
end

--- 清除指定角色已有的嘴巴动画（避免叠加冲突）
---@param figNode Node 火柴人节点
local function ClearExistingMouthAnims(figNode)
    -- 清除该角色的哭脸动画
    for i = #M.sadFaceAnims, 1, -1 do
        local anim = M.sadFaceAnims[i]
        if anim.mouthSegs[1] and anim.mouthSegs[1].node:GetParent() and
           anim.mouthSegs[1].node:GetParent():GetParent() == figNode then
            SetMouthShape(anim.mouthSegs, 0)
            table.remove(M.sadFaceAnims, i)
        end
    end
    -- 清除该角色的笑脸动画（仅清除 smile_hold / smile_fade 阶段）
    for i = #M.drinkingAnims, 1, -1 do
        local anim = M.drinkingAnims[i]
        if anim.figNode == figNode and (anim.phase == "smile_hold" or anim.phase == "smile_fade") then
            SetMouthShape(anim.mouthSegs, 0)
            table.remove(M.drinkingAnims, i)
        end
    end
end

--- 触发指定楼层的顾客干杯庆祝动画
---@param towerData table 塔楼数据
---@param floorIdx number 楼层索引 (0-based)
local function TriggerDrinkingAnim(towerData, floorIdx)
    -- 找到该楼层的所有火柴人（通过名字匹配）
    local prefix = towerData.name .. "_Cust_" .. floorIdx .. "_"
    for _, fig in ipairs(M.stickFigures) do
        local figName = fig:GetName()
        if string.find(figName, prefix, 1, true) then
            -- 清除该角色已有的嘴巴动画，避免叠加冲突
            ClearExistingMouthAnims(fig)
            -- 找到右臂关节点
            local rArmPivot = fig:GetChild("RArmPivot", false)
            if rArmPivot then
                local headGroup = fig:GetChild("HeadGroup", false)
                -- 收集嘴巴节点（5 段）及其默认 Y 位置
                local mouthSegs = {}
                if headGroup then
                    for seg = 1, 5 do
                        local mNode = headGroup:GetChild("Mouth_" .. seg, false)
                        if mNode then
                            table.insert(mouthSegs, {
                                node = mNode,
                                origY = mNode.position.y,
                                origX = mNode.position.x,
                                origZ = mNode.position.z,
                            })
                        end
                    end
                end
                table.insert(M.drinkingAnims, {
                    pivotNode = rArmPivot,
                    figNode = fig,
                    headGroup = headGroup,
                    mouthSegs = mouthSegs,
                    origY = fig.position.y,
                    origYaw = fig.rotation:YawAngle(),
                    bodyTimer = 0,      -- 全身动作计时器
                    timer = 0,
                    -- 干杯动画：举高 → 蹦跳摇摆(多拍) → 回位
                    phase = "raise",
                    raiseDuration = 0.25,
                    danceDuration = 1.2, -- 魔性蹦跳持续时间
                    lowerDuration = 0.30,
                })
            end
        end
    end
    -- 触发喝酒音效回调
    if M.onDrinkStart then M.onDrinkStart() end
end

--- 触发指定楼层顾客的哭脸动画（果汁类型不匹配时）
---@param towerData table 塔楼数据
---@param floorIdx number 楼层索引 (0-based)
local function TriggerSadFace(towerData, floorIdx)
    local prefix = towerData.name .. "_Cust_" .. floorIdx .. "_"
    for _, fig in ipairs(M.stickFigures) do
        local figName = fig:GetName()
        if string.find(figName, prefix, 1, true) then
            -- 清除该角色已有的嘴巴动画，避免叠加冲突
            ClearExistingMouthAnims(fig)
            local headGroup = fig:GetChild("HeadGroup", false)
            if headGroup then
                local mouthSegs = {}
                for seg = 1, 5 do
                    local mNode = headGroup:GetChild("Mouth_" .. seg, false)
                    if mNode then
                        table.insert(mouthSegs, {
                            node = mNode,
                            origY = mNode.position.y,
                            origX = mNode.position.x,
                            origZ = mNode.position.z,
                        })
                    end
                end
                if #mouthSegs == 5 then
                    table.insert(M.sadFaceAnims, {
                        mouthSegs = mouthSegs,
                        timer = 0,
                        phase = "sad_in",       -- 渐变到哭脸
                        fadeDuration = 0.3,     -- 渐入时间
                        holdDuration = 2.0,     -- 保持哭脸时间
                        fadeOutDuration = 0.5,  -- 渐出时间
                    })
                end
            end
        end
    end
end

-- ============================================================================
-- 楼层庆祝特效（干杯时触发）
-- ============================================================================

--- 触发楼层庆祝特效
---@param towerData table 塔楼数据
---@param wineIdx number 果汁类型索引
---@param floorCenterY number 楼层中心 Y 坐标
local function TriggerFloorCelebration(towerData, wineIdx, floorCenterY)
    local scene_ = towerData.parent:GetScene()
    local wine = Cfg.WINE_TYPES[wineIdx]
    local wineColor = wine.color

    local cx = towerData.centerX
    local cz = towerData.centerZ

    -- === 1) 发光光环（Torus，从中心扩散） ===
    local ringCount = 2
    local ringNodes = {}
    for r = 1, ringCount do
        local ringNode = scene_:CreateChild("CelebRing_" .. math.floor(floorCenterY * 100) .. "_" .. r)
        ringNode.position = Vector3(cx, floorCenterY, cz)
        ringNode.scale = Vector3(0.01, 0.01, 0.01)  -- 初始极小

        local model = ringNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Torus.mdl"))
        -- 发光材质，颜色为该楼层果汁颜色的 HDR 版本
        model:SetMaterial(Mat.CreateEmissive(
            Color(wineColor.r, wineColor.g, wineColor.b, 0.6),
            Color(wineColor.r * 2.5, wineColor.g * 2.5, wineColor.b * 2.5)
        ))
        model.castShadows = false

        table.insert(ringNodes, {
            node = ringNode,
            delay = (r - 1) * 0.15,  -- 第二个环稍延迟
            timer = 0,
            expandDuration = 0.6,
            maxScale = 3.5 + r * 1.5,  -- 每个环扩散到不同大小
            fadeDuration = 0.4,
            phase = "expand",
        })
    end

    -- === 2) 星星粒子（发光小球向上漂浮） ===
    local starCount = 10
    local starNodes = {}
    for s = 1, starCount do
        local angle = (s / starCount) * math.pi * 2 + math.random() * 0.8
        local dist = 0.5 + math.random() * 2.0
        local px = cx + math.cos(angle) * dist
        local pz = cz + math.sin(angle) * dist
        local py = floorCenterY - 0.5 + math.random() * 1.0
        local size = 0.06 + math.random() * 0.10

        local starNode = scene_:CreateChild("CelebStar_" .. math.floor(floorCenterY * 100) .. "_" .. s)
        starNode.position = Vector3(px, py, pz)
        starNode.scale = Vector3(size, size, size)

        local model = starNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        -- 明亮发光材质
        local brightness = 1.5 + math.random() * 2.0
        model:SetMaterial(Mat.CreateEmissive(
            Color(wineColor.r, wineColor.g, wineColor.b, 1.0),
            Color(wineColor.r * brightness, wineColor.g * brightness, wineColor.b * brightness)
        ))
        model.castShadows = false

        table.insert(starNodes, {
            node = starNode,
            startY = py,
            riseSpeed = 1.5 + math.random() * 2.5,
            swaySpeed = 2.0 + math.random() * 3.0,
            swayAmp = 0.2 + math.random() * 0.3,
            swayPhase = math.random() * math.pi * 2,
            baseX = px,
            baseZ = pz,
            timer = 0,
            delay = math.random() * 0.2,  -- 随机延迟出现
            lifetime = 1.0 + math.random() * 0.8,
            startSize = size,
        })
    end

    table.insert(M.floorCelebrations, {
        ringNodes = ringNodes,
        starNodes = starNodes,
        timer = 0,
        totalDuration = 2.5,
    })

    print("[Celebration] " .. towerData.name .. " celebration triggered at Y=" .. string.format("%.1f", floorCenterY))
end

--- 更新楼层庆祝特效（每帧调用）
---@param dt number
function M.UpdateFloorCelebrations(dt)
    local i = 1
    while i <= #M.floorCelebrations do
        local celeb = M.floorCelebrations[i]
        celeb.timer = celeb.timer + dt

        -- 更新光环
        local ri = 1
        while ri <= #celeb.ringNodes do
            local ring = celeb.ringNodes[ri]
            ring.timer = ring.timer + dt

            local t = ring.timer - ring.delay
            if t < 0 then
                -- 还在延迟中
                ri = ri + 1
            elseif ring.phase == "expand" then
                -- 扩散阶段
                local progress = math.min(t / ring.expandDuration, 1.0)
                -- ease-out: 快速扩张后减速
                local ease = 1 - (1 - progress) * (1 - progress)
                local s = ease * ring.maxScale
                ring.node.scale = Vector3(s, s * 0.3, s)  -- Y 压扁成薄环

                if progress >= 1.0 then
                    ring.phase = "fade"
                    ring.timer = 0
                    ring.delay = 0
                end
                ri = ri + 1

            elseif ring.phase == "fade" then
                -- 淡出阶段：逐渐缩小 Y 并消失
                local progress = math.min(ring.timer / ring.fadeDuration, 1.0)
                local fadeScale = ring.maxScale * (1.0 + progress * 0.3)  -- 继续微微扩大
                local yScale = ring.maxScale * 0.3 * (1.0 - progress)    -- Y 趋近 0
                if yScale < 0.001 then yScale = 0.001 end
                ring.node.scale = Vector3(fadeScale, yScale, fadeScale)

                if progress >= 1.0 then
                    ring.node:Remove()
                    table.remove(celeb.ringNodes, ri)
                else
                    ri = ri + 1
                end
            else
                ri = ri + 1
            end
        end

        -- 更新星星粒子
        local si = 1
        while si <= #celeb.starNodes do
            local star = celeb.starNodes[si]
            star.timer = star.timer + dt

            local t = star.timer - star.delay
            if t < 0 then
                -- 延迟中，保持不可见
                star.node.scale = Vector3(0, 0, 0)
                si = si + 1
            elseif t >= star.lifetime then
                -- 生命周期结束
                star.node:Remove()
                table.remove(celeb.starNodes, si)
            else
                local lifeRatio = t / star.lifetime
                -- 上升
                local curY = star.startY + star.riseSpeed * t
                -- 左右轻微摆动
                local sway = math.sin(star.swaySpeed * t + star.swayPhase) * star.swayAmp
                local curX = star.baseX + sway
                star.node.position = Vector3(curX, curY, star.baseZ)

                -- 先增大后缩小（前 20% 增大，后 80% 缩小）
                local scaleMul
                if lifeRatio < 0.2 then
                    scaleMul = lifeRatio / 0.2  -- 0 → 1
                else
                    scaleMul = 1.0 - (lifeRatio - 0.2) / 0.8  -- 1 → 0
                end
                local curSize = star.startSize * scaleMul
                if curSize < 0.005 then curSize = 0.005 end
                star.node.scale = Vector3(curSize, curSize, curSize)

                si = si + 1
            end
        end

        -- 所有节点都已移除，清理此庆祝特效
        if #celeb.ringNodes == 0 and #celeb.starNodes == 0 then
            table.remove(M.floorCelebrations, i)
        else
            i = i + 1
        end
    end
end

--- 更新果冻填充动画（每帧调用）
function M.UpdateFillingJellies(dt)
    local i = 1
    while i <= #M.fillingJellies do
        local j = M.fillingJellies[i]
        j.currentH = j.currentH + j.speed * dt

        if j.currentH >= j.targetH then
            j.node.scale = Vector3(j.width, j.targetH, j.depth)
            j.node.position = Vector3(j.node.position.x, j.targetY, j.node.position.z)

            -- 匹配成功：启动消除动画 + 喝酒动画
            if j.matched then
                local spacing_ = CONFIG.FloorSpacing
                local st_ = CONFIG.ShelfThickness
                table.insert(M.clearingJellies, {
                    node = j.node,
                    towerData = j.towerData,
                    width = j.width,
                    depth = j.depth,
                    bottomY = j.bottomY,
                    currentH = j.targetH,
                    maxH = j.targetH,
                    timer = 0,
                    delay = 0.5,
                    clearSpeed = j.targetH / 0.4,
                    floorIdx = j.floorIdx,
                    -- 庆祝特效用：保存原始数据（消除过程中 floorIdx 会变）
                    celebWineIdx = j.towerData.floorWineTypes[j.floorIdx],
                    celebFloorCenterY = j.floorIdx * spacing_ + st_ / 2 + (spacing_ - st_) / 2,
                })
                -- 触发该楼层顾客的喝酒动画
                TriggerDrinkingAnim(j.towerData, j.floorIdx)
            else
                -- 果汁类型不匹配：触发哭脸动画
                TriggerSadFace(j.towerData, j.floorIdx)
            end

            table.remove(M.fillingJellies, i)
        else
            j.node.scale = Vector3(j.width, j.currentH, j.depth)
            j.node.position = Vector3(
                j.node.position.x,
                j.bottomY + j.currentH / 2,
                j.node.position.z
            )
            i = i + 1
        end
    end
end

--- 更新果冻消除动画（每帧调用）
function M.UpdateClearingJellies(dt)
    local i = 1
    while i <= #M.clearingJellies do
        local c = M.clearingJellies[i]
        c.timer = c.timer + dt

        if c.timer < c.delay then
            -- 等待阶段：果冻保持满状态
            i = i + 1
        else
            -- 消除阶段：果冻缩回
            c.currentH = c.currentH - c.clearSpeed * dt

            if c.currentH <= 0 then
                -- 消除完成：触发庆祝特效，然后移除节点，上层果冻下落
                if c.celebWineIdx then
                    TriggerFloorCelebration(c.towerData, c.celebWineIdx, c.celebFloorCenterY)
                end

                local clearedFloor = c.floorIdx or 0
                local td = c.towerData
                local spacing = CONFIG.FloorSpacing
                local st = CONFIG.ShelfThickness
                local jellyH = spacing - st

                c.node:Remove()

                -- 从 jellyNodes 中移除（1-based: clearedFloor + 1）
                table.remove(td.jellyNodes, clearedFloor + 1)

                -- actualWineTypes 向下平移
                for f = clearedFloor, td.filledFloors - 2 do
                    td.actualWineTypes[f] = td.actualWineTypes[f + 1]
                end
                td.actualWineTypes[td.filledFloors - 1] = nil
                td.filledFloors = td.filledFloors - 1

                -- 更新同塔其他正在消除的条目的 floorIdx/bottomY
                for _, other in ipairs(M.clearingJellies) do
                    if other ~= c and other.towerData == td and other.floorIdx > clearedFloor then
                        other.floorIdx = other.floorIdx - 1
                        other.bottomY = other.floorIdx * spacing + st / 2
                    end
                end

                -- 对上方的非消除中果冻启动下落动画，完成后检查新匹配
                M._fallCheckPending = true
                for i2 = clearedFloor + 1, #td.jellyNodes do
                    local node = td.jellyNodes[i2]
                    if node then
                        -- 跳过正在消除中的节点（它们的 bottomY 已更新）
                        local isClearing = false
                        for _, other in ipairs(M.clearingJellies) do
                            if other.node == node then
                                isClearing = true
                                break
                            end
                        end
                        if not isClearing then
                            local targetFloor = i2 - 1  -- 0-based
                            local targetBottomY = targetFloor * spacing + st / 2
                            local targetY = targetBottomY + jellyH / 2
                            table.insert(M.fallingJellies, {
                                node = node,
                                startY = node.position.y,
                                targetY = targetY,
                                timer = 0,
                                duration = 0.3,
                                towerData = td,
                            })
                        end
                    end
                end

                table.remove(M.clearingJellies, i)
            else
                c.node.scale = Vector3(c.width, c.currentH, c.depth)
                c.node.position = Vector3(
                    c.node.position.x,
                    c.bottomY + c.currentH / 2,
                    c.node.position.z
                )
                i = i + 1
            end
        end
    end
end

-- ============================================================================
-- 果冻下落动画
-- ============================================================================

--- 更新果冻下落动画（每帧调用）
function M.UpdateFallingJellies(dt)
    local i = 1
    while i <= #M.fallingJellies do
        local f = M.fallingJellies[i]
        f.timer = f.timer + dt
        local t = math.min(f.timer / f.duration, 1.0)
        -- ease-out 缓动
        local ease = 1 - (1 - t) * (1 - t)

        local curY = f.startY + (f.targetY - f.startY) * ease
        f.node.position = Vector3(f.node.position.x, curY, f.node.position.z)

        if t >= 1.0 then
            f.node.position = Vector3(f.node.position.x, f.targetY, f.node.position.z)
            table.remove(M.fallingJellies, i)
        else
            i = i + 1
        end
    end

    -- 所有下落完成后，检查是否有新的匹配
    if #M.fallingJellies == 0 and M._fallCheckPending then
        M._fallCheckPending = false
        for _, towerData in ipairs(M.towers) do
            CheckMatchesAfterTransfer(towerData)
        end
    end
end

-- ============================================================================
-- 喝酒动画
-- ============================================================================

local function LerpAngle(a, b, t)
    return a + (b - a) * t
end

--- 更新干杯庆祝动画（每帧调用）
--- 动画流程：举杯位(-70) → 举高(-150) → 左晃(-130) → 右晃(-160) → 左晃(-135) → 回到举杯位(-70)
---@param dt number
function M.UpdateDrinkingAnims(dt)
    local i = 1
    while i <= #M.drinkingAnims do
        local anim = M.drinkingAnims[i]
        anim.timer = anim.timer + dt

        if anim.phase == "raise" then
            -- 从默认举杯(-70)举高到干杯位(-150)
            local t = math.min(anim.timer / anim.raiseDuration, 1.0)
            local ease = 1 - (1 - t) * (1 - t)  -- ease-out
            local angle = LerpAngle(HOLD_ANGLE, CHEERS_ANGLE, ease)
            anim.pivotNode.rotation = Quaternion(angle, Vector3.RIGHT)
            if t >= 1.0 then
                anim.phase = "toast"
                anim.timer = 0
            end
            i = i + 1

        elseif anim.phase == "toast" then
            -- 举过头顶（0.25s 举起 + 0.2s 停顿）
            local liftDur = 0.25
            local holdDur = 0.2
            local totalDur = liftDur + holdDur
            local t = math.min(anim.timer / totalDur, 1.0)
            if anim.timer < liftDur then
                -- 举起阶段
                local lt = anim.timer / liftDur
                local ease = 1 - (1 - lt) * (1 - lt)
                local angle = LerpAngle(CHEERS_ANGLE, OVERHEAD_ANGLE, ease)
                anim.pivotNode.rotation = Quaternion(angle, Vector3.RIGHT)
            else
                -- 停顿在头顶
                anim.pivotNode.rotation = Quaternion(OVERHEAD_ANGLE, Vector3.RIGHT)
            end
            if t >= 1.0 then
                anim.phase = "dance"
                anim.timer = 0
                anim.bodyTimer = 0
            end
            i = i + 1

        elseif anim.phase == "dance" then
            -- 转圈阶段：原地转圈 + 笑脸
            local t = math.min(anim.timer / anim.danceDuration, 1.0)
            anim.bodyTimer = anim.bodyTimer + dt

            local bt = anim.bodyTimer

            -- 手臂保持举过头顶
            anim.pivotNode.rotation = Quaternion(OVERHEAD_ANGLE, Vector3.RIGHT)

            -- 原地转圈（绕 Y 轴持续旋转）
            local spinSpeed = 360.0  -- 每秒转一圈
            local spinYaw = anim.origYaw + bt * spinSpeed
            anim.figNode.rotation = Quaternion(spinYaw, Vector3.UP)

            -- 笑脸（快速切到笑脸并保持）
            local smileT = math.min(anim.timer / 0.15, 1.0)
            SetMouthShape(anim.mouthSegs, smileT)

            if t >= 1.0 then
                anim.phase = "lower"
                anim.timer = 0
            end
            i = i + 1

        elseif anim.phase == "lower" then
            -- 回到默认举杯位(-70)，身体回正
            local t = math.min(anim.timer / anim.lowerDuration, 1.0)
            local ease = t * t  -- ease-in

            -- 手臂从头顶回位
            local angle = LerpAngle(OVERHEAD_ANGLE, HOLD_ANGLE, ease)
            anim.pivotNode.rotation = Quaternion(angle, Vector3.RIGHT)

            -- 转圈减速回到初始朝向
            local spinSpeed = 360.0 * (1 - ease)
            local spinYaw = anim.figNode.rotation:YawAngle() + spinSpeed * dt
            if ease > 0.9 then spinYaw = anim.origYaw end
            anim.figNode.rotation = Quaternion(spinYaw, Vector3.UP)

            -- 笑脸渐退回直线
            SetMouthShape(anim.mouthSegs, 1 - ease)

            if t >= 1.0 then
                -- 身体完全复位，但保持笑脸
                anim.pivotNode.rotation = Quaternion(HOLD_ANGLE, Vector3.RIGHT)
                local pos = anim.figNode.position
                anim.figNode.position = Vector3(pos.x, anim.origY, pos.z)
                anim.figNode.rotation = Quaternion(anim.origYaw, Vector3.UP)
                if anim.headGroup then
                    anim.headGroup.rotation = Quaternion(0, 0, 0)
                end
                -- 进入笑脸保持阶段（保持1秒）
                SetMouthShape(anim.mouthSegs, 1)
                anim.phase = "smile_hold"
                anim.timer = 0
                -- 喝完打嗝
                if M.onDrinkEnd then M.onDrinkEnd() end
            end
            i = i + 1

        elseif anim.phase == "smile_hold" then
            -- 保持笑脸1秒（身体已复位，只保持笑脸）
            local t = math.min(anim.timer / 1.0, 1.0)
            SetMouthShape(anim.mouthSegs, 1)
            if t >= 1.0 then
                anim.phase = "smile_fade"
                anim.timer = 0
            end
            i = i + 1

        elseif anim.phase == "smile_fade" then
            -- 笑脸渐退回直线（0.3秒）
            local t = math.min(anim.timer / 0.3, 1.0)
            local ease = t * t
            SetMouthShape(anim.mouthSegs, 1 - ease)
            if t >= 1.0 then
                SetMouthShape(anim.mouthSegs, 0)
                table.remove(M.drinkingAnims, i)
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

--- 更新哭脸动画（每帧调用）
---@param dt number
function M.UpdateSadFaceAnims(dt)
    local i = 1
    while i <= #M.sadFaceAnims do
        local anim = M.sadFaceAnims[i]
        anim.timer = anim.timer + dt

        if anim.phase == "sad_in" then
            -- 渐变到哭脸（0.3s）
            local t = math.min(anim.timer / anim.fadeDuration, 1.0)
            local ease = t * t
            SetMouthShape(anim.mouthSegs, -ease)
            if t >= 1.0 then
                SetMouthShape(anim.mouthSegs, -1)
                anim.phase = "sad_hold"
                anim.timer = 0
            end
            i = i + 1

        elseif anim.phase == "sad_hold" then
            -- 保持哭脸（2s）
            if anim.timer >= anim.holdDuration then
                anim.phase = "sad_out"
                anim.timer = 0
            end
            i = i + 1

        elseif anim.phase == "sad_out" then
            -- 渐退回直线（0.5s）
            local t = math.min(anim.timer / anim.fadeOutDuration, 1.0)
            local ease = t * t
            SetMouthShape(anim.mouthSegs, -(1 - ease))
            if t >= 1.0 then
                SetMouthShape(anim.mouthSegs, 0)
                table.remove(M.sadFaceAnims, i)
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- U 型管平衡机制
-- ============================================================================

--- 转移完成后检查指定塔楼所有已填充楼层的匹配情况
---@param towerData table 塔楼数据
CheckMatchesAfterTransfer = function(towerData)
    local spacing = CONFIG.FloorSpacing
    local st = CONFIG.ShelfThickness
    local wt = CONFIG.WallThickness
    local jellyH = spacing - st

    for f = 0, towerData.filledFloors - 1 do
        local actualIdx = towerData.actualWineTypes[f]
        local wantIdx = towerData.floorWineTypes[f]
        if actualIdx and wantIdx and actualIdx == wantIdx then
            -- 检查该楼层是否已在消除列表中（避免重复）
            local alreadyClearing = false
            local jellyNode = towerData.jellyNodes[f + 1]  -- 1-based
            if jellyNode then
                for _, c in ipairs(M.clearingJellies) do
                    if c.node == jellyNode then
                        alreadyClearing = true
                        break
                    end
                end
            end

            if not alreadyClearing and jellyNode then
                local bottomY = f * spacing + st / 2
                local jW = towerData.towerW - wt * 2 - 0.2
                local jD = towerData.towerD - wt * 2 - 0.2

                table.insert(M.clearingJellies, {
                    node = jellyNode,
                    towerData = towerData,
                    width = jW,
                    depth = jD,
                    bottomY = bottomY,
                    currentH = jellyH,
                    maxH = jellyH,
                    timer = 0,
                    delay = 0.5,
                    clearSpeed = jellyH / 0.4,
                    floorIdx = f,
                    -- 庆祝特效用：保存原始数据（消除过程中 floorIdx 会变）
                    celebWineIdx = towerData.floorWineTypes[f],
                    celebFloorCenterY = f * spacing + st / 2 + (spacing - st) / 2,
                })
                TriggerDrinkingAnim(towerData, f)

                M.score = M.score + 100
                if M.onScoreChanged then M.onScoreChanged() end
                if M.onJellyCleared then M.onJellyCleared() end
                print("[UTube] MATCH after transfer! Floor " .. f .. " of " .. towerData.name .. " +100 pts (Score: " .. M.score .. ")")
            end
        end
    end
end

--- 检查两塔酒液高度差，超过 1 层则启动转移
function M.CheckUTubeBalance()
    -- 有转移动画进行中时不检查
    if M.transferAnim then return end
    -- 有倾倒/填充/下落动画进行中时不检查
    if #M.pouringAnims > 0 then return end
    if #M.fillingJellies > 0 then return end
    if #M.fallingJellies > 0 then return end
    -- 消除动画：只在实际缩回阶段阻塞，延迟等待阶段不阻塞
    for _, c in ipairs(M.clearingJellies) do
        if c.timer >= c.delay then
            return  -- 正在缩回，阻塞
        end
    end

    -- 需要连接处已填满酒（U 型管原理需要管内有液体）
    local Connector = require("Connector")
    if not Connector.filled then return end

    if #M.towers < 2 then return end

    local t1 = M.towers[1]
    local t2 = M.towers[2]

    -- 计算有效填充层数（减去正在消除的层数）
    local t1Clearing = 0
    local t2Clearing = 0
    for _, c in ipairs(M.clearingJellies) do
        if c.towerData == t1 then t1Clearing = t1Clearing + 1 end
        if c.towerData == t2 then t2Clearing = t2Clearing + 1 end
    end
    local t1Effective = t1.filledFloors - t1Clearing
    local t2Effective = t2.filledFloors - t2Clearing

    local diff = t1Effective - t2Effective

    if math.abs(diff) <= 1 then return end

    local fromTower, toTower
    if diff > 0 then
        fromTower = t1
        toTower = t2
    else
        fromTower = t2
        toTower = t1
    end

    -- 目标塔满了则不转移
    if toTower.filledFloors >= toTower.currentFloors then return end
    -- 源塔没酒则不转移
    if fromTower.filledFloors <= 0 then return end

    M.StartTransfer(fromTower, toTower)
end

--- 启动一次 U 型管链式转移（所有酒液向低侧整体平移一格）
--- 链式位置: HighTower[top] → ... → HighTower[0] → Connector → LowTower[0] → ... → LowTower[top]
---@param fromTower table 高侧塔（将减少一格）
---@param toTower table 低侧塔（将增加一格）
function M.StartTransfer(fromTower, toTower)
    local topFloor = fromTower.filledFloors - 1
    local drainWineIdx = fromTower.actualWineTypes[topFloor]
    if not drainWineIdx then
        print("[UTube] WARN: No wine type at top floor " .. topFloor .. " of " .. fromTower.name .. ", skipping transfer")
        return
    end

    -- 获取源塔顶层果冻节点
    local drainNode = fromTower.jellyNodes[#fromTower.jellyNodes]
    if not drainNode then
        print("[UTube] WARN: No jelly node at top of " .. fromTower.name .. " (jellyNodes=" .. #fromTower.jellyNodes .. "), skipping transfer")
        return
    end

    -- 快照：记录链中每个位置当前的酒类，以便同时平移
    -- chainSnapshot[i] 表示从高侧到低侧的第 i 个位置的酒类
    -- 链的布局: highTower[top-1] ... highTower[0], connector, lowTower[0] ... lowTower[top-1]
    -- 平移后: highTower[top]被排空, 其余每个位置获得上一个位置的酒

    local Connector = require("Connector")

    -- 记录转移前连接处的酒类（这将流入低塔 floor 0）
    local connectorOldWineIdx = Connector.filledWineIdx

    -- 记录高塔 floor 0 的酒类（这将流入连接处）
    local highFloor0WineIdx = fromTower.actualWineTypes[0]

    local spacing = CONFIG.FloorSpacing
    local st = CONFIG.ShelfThickness
    local wt = CONFIG.WallThickness
    local jellyH = spacing - st
    local jellyW = fromTower.towerW - wt * 2 - 0.2
    local jellyD = fromTower.towerD - wt * 2 - 0.2
    local drainBottomY = topFloor * spacing + st / 2

    M.transferAnim = {
        phase = "drain",        -- drain → shift → fill
        fromTower = fromTower,
        toTower = toTower,
        drainWineIdx = drainWineIdx,
        connectorOldWineIdx = connectorOldWineIdx,
        highFloor0WineIdx = highFloor0WineIdx,
        -- 排空阶段参数（高塔顶层缩小）
        drainNode = drainNode,
        drainWidth = jellyW,
        drainDepth = jellyD,
        drainBottomY = drainBottomY,
        drainCurrentH = jellyH,
        drainTargetH = jellyH,
        drainSpeed = jellyH / 0.4,
        -- 填充阶段（低塔 floor 0 长出新果冻）
        fillNode = nil,
        fillBottomY = 0,
        fillTargetH = jellyH,
        fillCurrentH = 0,
        fillWidth = 0,
        fillDepth = 0,
        fillSpeed = jellyH / 0.6,
    }

    print("[UTube] Chain shift: " .. fromTower.name .. "(lv" .. fromTower.filledFloors .. ")"
        .. " → " .. toTower.name .. "(lv" .. toTower.filledFloors .. ")")
end

--- 更新 U 型管链式转移动画（每帧调用）
---@param dt number
function M.UpdateTransfer(dt)
    local t = M.transferAnim
    if not t then return end

    if t.phase == "drain" then
        -- 排空阶段：高塔顶层果冻从上往下缩小
        t.drainCurrentH = t.drainCurrentH - t.drainSpeed * dt

        if t.drainCurrentH <= 0 then
            -- 排空完成：移除顶层节点
            t.drainNode:Remove()
            table.remove(t.fromTower.jellyNodes, #t.fromTower.jellyNodes)

            -- ========== 准备 shift 阶段：带过渡动画的链式平移 ==========
            local from = t.fromTower
            local dest = t.toTower
            local Connector = require("Connector")
            local spacing = CONFIG.FloorSpacing
            local st = CONFIG.ShelfThickness
            local wt = CONFIG.WallThickness
            local jellyH = spacing - st

            local topFloor = from.filledFloors - 1  -- 排空前的顶层索引

            -- 1) 高塔材质下移（瞬间完成，视觉上被排空动画遮盖）
            for f = 0, topFloor - 1 do
                local newWineIdx = from.actualWineTypes[f + 1]
                if newWineIdx and from.jellyNodes[f + 1] then
                    from.actualWineTypes[f] = newWineIdx
                    local wine = Cfg.WINE_TYPES[newWineIdx]
                    local model = from.jellyNodes[f + 1]:GetComponent("StaticModel")
                    if model then
                        model:SetMaterial(Mat.CreateJelly(wine))
                    end
                end
            end
            from.actualWineTypes[topFloor] = nil
            from.filledFloors = from.filledFloors - 1

            -- 2) 连接处：获得高塔 floor[0] 原来的酒
            if t.highFloor0WineIdx then
                Connector.ChangeWineType(t.highFloor0WineIdx)
            end

            -- 3) 低塔：记录已有果冻的起止 Y，用于平滑上移
            local destJellyH = spacing - st
            local slidingJellies = {}
            for f = dest.filledFloors - 1, 0, -1 do
                local node = dest.jellyNodes[f + 1]
                if node then
                    local oldY = node.position.y
                    local newFloor = f + 1
                    local newBottomY = newFloor * spacing + st / 2
                    local newY = newBottomY + destJellyH / 2
                    table.insert(slidingJellies, {
                        node = node,
                        startY = oldY,
                        targetY = newY,
                    })
                    dest.actualWineTypes[newFloor] = dest.actualWineTypes[f]
                end
            end

            -- 4) 低塔 floor 0：创建新果冻节点
            local fillWineIdx = t.connectorOldWineIdx
            local jW = dest.towerW - wt * 2 - 0.2
            local jD = dest.towerD - wt * 2 - 0.2
            local bY = 0 * spacing + st / 2

            local scene_ = dest.parent:GetScene()
            local wine = Cfg.WINE_TYPES[fillWineIdx]

            local fillNode = scene_:CreateChild(dest.name .. "_Jelly_0")
            fillNode.position = Vector3(dest.centerX, bY, dest.centerZ)
            fillNode.scale = Vector3(jW, 0.01, jD)

            local model = fillNode:CreateComponent("StaticModel")
            model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            model:SetMaterial(Mat.CreateJelly(wine))
            model.castShadows = true

            dest.actualWineTypes[0] = fillWineIdx
            dest.filledFloors = dest.filledFloors + 1
            table.insert(dest.jellyNodes, 1, fillNode)

            -- 进入 shift 阶段（低塔果冻上滑 + floor 0 涨出 同步进行）
            t.phase = "shift"
            t.shiftProgress = 0
            t.shiftDuration = 0.5  -- 过渡持续时间
            t.slidingJellies = slidingJellies
            t.fillNode = fillNode
            t.fillBottomY = bY
            t.fillCurrentH = 0.01
            t.fillWidth = jW
            t.fillDepth = jD
            t.fillTargetH = destJellyH
            t.fillTargetY = bY + destJellyH / 2
            t.destCenterX = dest.centerX
            t.destCenterZ = dest.centerZ
        else
            t.drainNode.scale = Vector3(t.drainWidth, t.drainCurrentH, t.drainDepth)
            t.drainNode.position = Vector3(
                t.drainNode.position.x,
                t.drainBottomY + t.drainCurrentH / 2,
                t.drainNode.position.z
            )
        end

    elseif t.phase == "shift" then
        -- shift 阶段：低塔已有果冻平滑上移 + floor 0 新果冻涨出
        t.shiftProgress = t.shiftProgress + dt / t.shiftDuration
        if t.shiftProgress > 1 then t.shiftProgress = 1 end

        -- 缓动函数（ease-out）
        local ease = 1 - (1 - t.shiftProgress) * (1 - t.shiftProgress)

        -- 低塔已有果冻平滑上移
        for _, sj in ipairs(t.slidingJellies) do
            local curY = sj.startY + (sj.targetY - sj.startY) * ease
            sj.node.position = Vector3(t.destCenterX, curY, t.destCenterZ)
        end

        -- floor 0 新果冻涨出
        local fillH = 0.01 + (t.fillTargetH - 0.01) * ease
        t.fillNode.scale = Vector3(t.fillWidth, fillH, t.fillDepth)
        t.fillNode.position = Vector3(t.destCenterX, t.fillBottomY + fillH / 2, t.destCenterZ)

        if t.shiftProgress >= 1 then
            -- 确保最终位置精确
            for _, sj in ipairs(t.slidingJellies) do
                sj.node.position = Vector3(t.destCenterX, sj.targetY, t.destCenterZ)
            end
            t.fillNode.scale = Vector3(t.fillWidth, t.fillTargetH, t.fillDepth)
            t.fillNode.position = Vector3(t.destCenterX, t.fillTargetY, t.destCenterZ)

            -- 转移完成后检查两塔所有楼层的匹配情况
            CheckMatchesAfterTransfer(t.fromTower)
            CheckMatchesAfterTransfer(t.toTower)

            M.transferAnim = nil
            print("[UTube] Chain shift complete")
        end
    end
end

-- ============================================================================
-- 游戏失败检测
-- ============================================================================

--- 检查是否两塔全部填满（无动画进行中时判定）
function M.CheckGameOver()
    if M.gameOver then return end
    -- 有动画进行中时不判定
    if M.transferAnim then return end
    if #M.pouringAnims > 0 then return end
    if #M.fillingJellies > 0 or #M.clearingJellies > 0 or #M.fallingJellies > 0 then return end

    local Connector = require("Connector")
    if Connector.fillingAnim then return end

    -- 两塔都必须存在
    if #M.towers < 2 then return end

    -- 检查两塔是否全满
    for _, towerData in ipairs(M.towers) do
        if towerData.filledFloors < towerData.currentFloors then
            return  -- 还有空位
        end
    end

    -- 全部填满 → 游戏失败
    M.gameOver = true
    print("[Game] GAME OVER! All towers are full. Final score: " .. M.score)
    if M.onGameOver then M.onGameOver() end
end

-- ============================================================================
-- 重置（重新开始时调用）
-- ============================================================================

function M.Reset()
    M.towers = {}
    M.leftRoofNode = nil
    M.rightRoofNode = nil
    M.stickFigures = {}
    M.clearingJellies = {}
    M.fallingJellies = {}
    M.fillingJellies = {}
    M.drinkingAnims = {}
    M.sadFaceAnims = {}
    M.pouringAnims = {}
    M.floorCelebrations = {}
    M._fallCheckPending = false
    M.transferAnim = nil
    M.score = 0
    M.gameOver = false
end

-- ============================================================================
-- 火柴人朝向相机（每帧调用，只绕 Y 轴旋转）
-- ============================================================================

--- 让所有火柴人面向相机方向，头部微微跟随俯仰
---@param camYaw number 相机 yaw 角度
---@param camPitch number 相机 pitch 角度
function M.UpdateStickFiguresFacing(camYaw, camPitch)
    for _, fig in ipairs(M.stickFigures) do
        -- 整个火柴人绕 Y 轴旋转，始终正面（+Z 眼睛方向）朝向相机
        -- 相机偏移方向为 (sinY, -cosY)，figure forward = (sin(180-Y), cos(180-Y)) = (sinY, -cosY)
        fig.rotation = Quaternion(180 - camYaw, Vector3.UP)
    end
end

return M
