-- ============================================================================
-- Connector.lua - 圆弧连接通道 + TapTap 酒馆招牌
-- ============================================================================

local Cfg = require("Config")
local Mat = require("Materials")
local Builders = require("Builders")
local CONFIG = Cfg.CONFIG
local COLORS = Cfg.COLORS

local M = {}

-- 连接处果冻状态
M.filled = false         -- 连接处是否已填满酒
M.filledWineIdx = nil    -- 填充的酒类索引
M.jellyNodes = {}        -- 所有果冻节点
M.fillingAnim = nil      -- 正在播放的填充动画（nil = 无动画）

-- ============================================================================
-- 辅助：直线栏杆
-- ============================================================================

local function CreateStraightBars(scene_, prefix, from, to, fixedCoord, axis, tunnelH, barThick, count)
    local barH = tunnelH - 0.3
    local beamH = 0.12

    for b = 0, count do
        local t = from + (to - from) * b / count
        local bx, bz
        if axis == "x" then
            bx = t
            bz = fixedCoord
        else
            bx = fixedCoord
            bz = t
        end

        local barNode = scene_:CreateChild(prefix .. "_" .. b)
        barNode.position = Vector3(bx, tunnelH / 2, bz)
        barNode.scale = Vector3(barThick, barH, barThick)
        local barModel = barNode:CreateComponent("StaticModel")
        barModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        barModel:SetMaterial(Mat.CreatePBR(COLORS.TunnelBar, 0.0, 0.65))
        barModel.castShadows = true
    end

    local beamLen = math.abs(to - from)
    local beamCx, beamCz
    if axis == "x" then
        beamCx = (from + to) / 2
        beamCz = fixedCoord
    else
        beamCx = fixedCoord
        beamCz = (from + to) / 2
    end
    local beamNode = scene_:CreateChild(prefix .. "_TopBeam")
    beamNode.position = Vector3(beamCx, tunnelH - beamH / 2, beamCz)
    if axis == "x" then
        beamNode.scale = Vector3(beamLen, beamH, barThick * 2)
    else
        beamNode.scale = Vector3(barThick * 2, beamH, beamLen)
    end
    local beamModel = beamNode:CreateComponent("StaticModel")
    beamModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    beamModel:SetMaterial(Mat.CreatePBR(COLORS.TunnelBar, 0.0, 0.65))
    beamModel.castShadows = true
end

-- ============================================================================
-- 辅助：隧道地板/天花板
-- ============================================================================

local function CreateTunnelFloor(scene_, name, cx, cz, sizeX, sizeZ, tunnelH)
    local node = scene_:CreateChild(name)
    node.position = Vector3(cx, 0, cz)
    node.scale = Vector3(sizeX, 0.15, sizeZ)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(Mat.CreatePBR(COLORS.TunnelFloor, 0.0, 0.75))
    model.castShadows = true

    local body = node:CreateComponent("RigidBody")
    body.mass = 0
    body.friction = 0.5
    body.restitution = 0.3
    local shape = node:CreateComponent("CollisionShape")
    shape:SetBox(Vector3(1, 1, 1))
end

local function CreateTunnelCeiling(scene_, name, cx, cz, sizeX, sizeZ, tunnelH)
    local node = scene_:CreateChild(name)
    node.position = Vector3(cx, tunnelH, cz)
    node.scale = Vector3(sizeX, 0.15, sizeZ)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(Mat.CreatePBR(COLORS.TunnelFloor, 0.0, 0.75))
    model.castShadows = true

    local body = node:CreateComponent("RigidBody")
    body.mass = 0
    local shape = node:CreateComponent("CollisionShape")
    shape:SetBox(Vector3(1, 1, 1))
end

-- ============================================================================
-- TapTap 酒馆 3D 弧面立体文字
-- ============================================================================

local function CreateTavernSign(scene_, arcCX, arcCZ, R, halfW, tunnelH)
    local thetaMid = math.pi * 3 / 4
    local innerBarR = (R - halfW) + CONFIG.WallThickness
    local signY = tunnelH + 1.2
    local charScale = 1.6

    local font = cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")
    local fontSize = 48
    local depthLayers = 6
    local layerStep = 0.04

    local text = "TapTap 酒馆"
    local chars = {}
    for _, code in utf8.codes(text) do
        table.insert(chars, utf8.char(code))
    end
    local charCount = #chars

    local arcUsage = (math.pi / 2) * 0.90
    local startTheta = thetaMid + arcUsage / 2
    local endTheta   = thetaMid - arcUsage / 2

    local polePositions = {}

    for ci, char in ipairs(chars) do
        local t = (ci - 0.5) / charCount
        local theta = startTheta + (endTheta - startTheta) * t

        local cx = arcCX + innerBarR * math.cos(theta)
        local cz = arcCZ + innerBarR * math.sin(theta)

        local outX = cx - arcCX
        local outZ = cz - arcCZ
        local faceAngle = math.deg(math.atan(outX, outZ)) + 180

        local charNode = scene_:CreateChild("SignChar_" .. ci)
        charNode.position = Vector3(cx, signY, cz)
        charNode.rotation = Quaternion(faceAngle, Vector3.UP) * Quaternion(30, Vector3.RIGHT)
        charNode.scale = Vector3(charScale, charScale, charScale)

        for i = depthLayers, 1, -1 do
            local layerNode = charNode:CreateChild("Depth_" .. i)
            layerNode.position = Vector3(0, 0, -i * layerStep)

            local text3d = layerNode:CreateComponent("Text3D")
            text3d:SetFont(font, fontSize)
            text3d.text = char
            text3d:SetAlignment(HA_CENTER, VA_CENTER)
            text3d.textEffect = TE_NONE

            local s = (depthLayers - i) / depthLayers
            text3d.color = Color(0.03 + 0.05 * s, 0.10 + 0.10 * s, 0.15 + 0.10 * s, 1.0)
            text3d.castShadows = true
        end

        local frontNode = charNode:CreateChild("Front")
        local frontText = frontNode:CreateComponent("Text3D")
        frontText:SetFont(font, fontSize)
        frontText.text = char
        frontText:SetAlignment(HA_CENTER, VA_CENTER)
        frontText.textEffect = TE_STROKE
        frontText.effectColor = Color(0.0, 0.15, 0.35, 1.0)
        frontText.color = Color(0.10, 0.65, 1.0, 1.0)
        frontText.castShadows = true

        if ci == 1 or ci == charCount then
            table.insert(polePositions, { x = cx, z = cz })
        end
    end

    -- 支撑柱
    local poleR = 0.06
    local poleBot = tunnelH
    local poleTop = signY - 0.8
    local poleH = poleTop - poleBot
    local poleCenterY = (poleTop + poleBot) / 2

    for _, pp in ipairs(polePositions) do
        local poleNode = scene_:CreateChild("SignPole")
        poleNode.position = Vector3(pp.x, poleCenterY, pp.z)
        poleNode.scale = Vector3(poleR * 2, poleH, poleR * 2)
        local poleModel = poleNode:CreateComponent("StaticModel")
        poleModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        poleModel:SetMaterial(Mat.CreatePBR(COLORS.TunnelBar, 0.0, 0.65))
        poleModel.castShadows = true
    end

    print("[Scene] TapTap Tavern arc text created (cyan-blue, " .. charCount .. " chars)")
end

-- ============================================================================
-- 主入口：创建完整圆弧连接通道
-- ============================================================================

function M.Create(scene_)
    local wt = CONFIG.WallThickness
    local th = CONFIG.TunnelHeight
    local barThick = 0.10

    -- Arm A
    local armAx = CONFIG.ArmACenterX
    local armAz = CONFIG.ArmACenterZ
    local armAW = CONFIG.ArmAWidth
    local armAD = CONFIG.ArmADepth

    CreateTunnelFloor(scene_, "ArmA_Floor", armAx, armAz, armAW, armAD, th)
    CreateTunnelCeiling(scene_, "ArmA_Ceil", armAx, armAz, armAW, armAD, th)

    local armASouthZ = armAz - armAD / 2
    CreateStraightBars(scene_, "ArmA_SouthBar", armAx - armAW/2, armAx + armAW/2,
        armASouthZ, "x", th, barThick, 6)
    Builders.CreatePhysicsWallWorld(scene_, "ArmA_SouthPhys",
        Vector3(armAx, th/2, armASouthZ),
        Vector3(armAW, th, wt))

    local armANorthZ = armAz + armAD / 2
    CreateStraightBars(scene_, "ArmA_NorthBar", armAx - armAW/2, armAx + armAW/2,
        armANorthZ, "x", th, barThick, 6)
    Builders.CreatePhysicsWallWorld(scene_, "ArmA_NorthPhys",
        Vector3(armAx, th/2, armANorthZ),
        Vector3(armAW, th, wt))

    -- Arm B
    local armBx = CONFIG.ArmBCenterX
    local armBz = CONFIG.ArmBCenterZ
    local armBW = CONFIG.ArmBWidth
    local armBD = CONFIG.ArmBDepth

    CreateTunnelFloor(scene_, "ArmB_Floor", armBx, armBz, armBW, armBD, th)
    CreateTunnelCeiling(scene_, "ArmB_Ceil", armBx, armBz, armBW, armBD, th)

    local armBEastX = armBx + armBW / 2
    CreateStraightBars(scene_, "ArmB_EastBar", armBz - armBD/2, armBz + armBD/2,
        armBEastX, "z", th, barThick, 8)
    Builders.CreatePhysicsWallWorld(scene_, "ArmB_EastPhys",
        Vector3(armBEastX, th/2, armBz),
        Vector3(wt, th, armBD))

    local armBWestX = armBx - armBW / 2
    CreateStraightBars(scene_, "ArmB_WestBar", armBz - armBD/2, armBz + armBD/2,
        armBWestX, "z", th, barThick, 8)
    Builders.CreatePhysicsWallWorld(scene_, "ArmB_WestPhys",
        Vector3(armBWestX, th/2, armBz),
        Vector3(wt, th, armBD))

    -- 四分之一圆弧
    local arcCX = CONFIG.ArcCenterX
    local arcCZ = CONFIG.ArcCenterZ
    local R = CONFIG.ArcRadius
    local halfW = CONFIG.ArcWidth / 2
    local arcSegs = CONFIG.ArcSegments
    local barCount = CONFIG.BarCount

    local R_inner = R - halfW

    for i = 0, arcSegs - 1 do
        local t0 = math.pi / 2 + (math.pi / 2) * i / arcSegs
        local t1 = math.pi / 2 + (math.pi / 2) * (i + 1) / arcSegs
        local tMid = (t0 + t1) / 2

        local x0 = arcCX + R * math.cos(t0)
        local z0 = arcCZ + R * math.sin(t0)
        local x1 = arcCX + R * math.cos(t1)
        local z1 = arcCZ + R * math.sin(t1)
        local xM = (x0 + x1) / 2
        local zM = (z0 + z1) / 2

        local dx = x1 - x0
        local dz = z1 - z0
        local segLen = math.sqrt(dx * dx + dz * dz)
        local angle = math.deg(math.atan(dx, dz))

        local nxM = math.cos(tMid)
        local nzM = math.sin(tMid)

        -- 地板
        local floorW = CONFIG.ArcWidth
        local floorNode = scene_:CreateChild("Arc_Floor_" .. i)
        floorNode.position = Vector3(xM, 0, zM)
        floorNode.rotation = Quaternion(angle, Vector3.UP)
        floorNode.scale = Vector3(floorW, 0.15, segLen + 0.05)
        local floorModel = floorNode:CreateComponent("StaticModel")
        floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        floorModel:SetMaterial(Mat.CreatePBR(COLORS.TunnelFloor, 0.0, 0.75))
        floorModel.castShadows = true
        local floorBody = floorNode:CreateComponent("RigidBody")
        floorBody.mass = 0
        floorBody.friction = 0.5
        floorBody.restitution = 0.3
        local floorShape = floorNode:CreateComponent("CollisionShape")
        floorShape:SetBox(Vector3(1, 1, 1))

        -- 天花板
        local ceilNode = scene_:CreateChild("Arc_Ceil_" .. i)
        ceilNode.position = Vector3(xM, th, zM)
        ceilNode.rotation = Quaternion(angle, Vector3.UP)
        ceilNode.scale = Vector3(floorW, 0.15, segLen + 0.05)
        local ceilModel = ceilNode:CreateComponent("StaticModel")
        ceilModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        ceilModel:SetMaterial(Mat.CreatePBR(COLORS.TunnelFloor, 0.0, 0.75))
        ceilModel.castShadows = true
        local ceilBody = ceilNode:CreateComponent("RigidBody")
        ceilBody.mass = 0
        local ceilShape = ceilNode:CreateComponent("CollisionShape")
        ceilShape:SetBox(Vector3(1, 1, 1))

        -- 外墙（栏杆 + 物理碰撞）
        local outerX = xM + nxM * halfW
        local outerZ = zM + nzM * halfW

        -- 外墙栏杆柱
        local outerBarH = th - 0.3
        local outerBarNode = scene_:CreateChild("Arc_OuterBar_" .. i)
        outerBarNode.position = Vector3(outerX, th / 2, outerZ)
        outerBarNode.scale = Vector3(barThick, outerBarH, barThick)
        local outerBarModel = outerBarNode:CreateComponent("StaticModel")
        outerBarModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        outerBarModel:SetMaterial(Mat.CreatePBR(COLORS.TunnelBar, 0.0, 0.65))
        outerBarModel.castShadows = true

        -- 外墙物理（保留碰撞）
        local outerPhys = scene_:CreateChild("Arc_OuterPhys_" .. i)
        outerPhys.position = Vector3(outerX, th/2, outerZ)
        outerPhys.rotation = Quaternion(angle, Vector3.UP)
        local outerBody = outerPhys:CreateComponent("RigidBody")
        outerBody.mass = 0
        outerBody.friction = 0.3
        outerBody.restitution = 0.4
        local outerShape = outerPhys:CreateComponent("CollisionShape")
        outerShape:SetBox(Vector3(wt, th, segLen + 0.05))

        -- 内墙物理
        local innerX = xM - nxM * halfW
        local innerZ = zM - nzM * halfW
        local innerPhys = scene_:CreateChild("Arc_InnerPhys_" .. i)
        innerPhys.position = Vector3(innerX, th/2, innerZ)
        innerPhys.rotation = Quaternion(angle, Vector3.UP)
        local innerBody = innerPhys:CreateComponent("RigidBody")
        innerBody.mass = 0
        innerBody.friction = 0.3
        innerBody.restitution = 0.4
        local innerShape = innerPhys:CreateComponent("CollisionShape")
        innerShape:SetBox(Vector3(wt, th, segLen + 0.05))
    end

    -- 内弧栏杆
    local innerBarR = R_inner + wt
    local barH = th - 0.3
    for b = 0, barCount - 1 do
        local t = math.pi / 2 + (math.pi / 2) * b / barCount
        local bx = arcCX + innerBarR * math.cos(t)
        local bz = arcCZ + innerBarR * math.sin(t)

        local barNode = scene_:CreateChild("Arc_Bar_" .. b)
        barNode.position = Vector3(bx, th / 2, bz)
        barNode.scale = Vector3(barThick, barH, barThick)
        local barModel = barNode:CreateComponent("StaticModel")
        barModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
        barModel:SetMaterial(Mat.CreatePBR(COLORS.TunnelBar, 0.0, 0.65))
        barModel.castShadows = true
    end

    -- 内弧顶横梁
    local beamH = 0.12
    for i = 0, arcSegs - 1 do
        local t0 = math.pi / 2 + (math.pi / 2) * i / arcSegs
        local t1 = math.pi / 2 + (math.pi / 2) * (i + 1) / arcSegs
        local bx0 = arcCX + innerBarR * math.cos(t0)
        local bz0 = arcCZ + innerBarR * math.sin(t0)
        local bx1 = arcCX + innerBarR * math.cos(t1)
        local bz1 = arcCZ + innerBarR * math.sin(t1)
        local mx = (bx0 + bx1) / 2
        local mz = (bz0 + bz1) / 2
        local ddx = bx1 - bx0
        local ddz = bz1 - bz0
        local bLen = math.sqrt(ddx * ddx + ddz * ddz)
        local bAngle = math.deg(math.atan(ddx, ddz))

        local beamNode = scene_:CreateChild("Arc_Beam_" .. i)
        beamNode.position = Vector3(mx, th - beamH / 2, mz)
        beamNode.rotation = Quaternion(bAngle, Vector3.UP)
        beamNode.scale = Vector3(barThick * 2, beamH, bLen + 0.02)
        local beamModel = beamNode:CreateComponent("StaticModel")
        beamModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        beamModel:SetMaterial(Mat.CreatePBR(COLORS.TunnelBar, 0.0, 0.65))
        beamModel.castShadows = true
    end

    -- 外弧顶横梁
    local outerBarR = R + halfW
    for i = 0, arcSegs - 1 do
        local t0 = math.pi / 2 + (math.pi / 2) * i / arcSegs
        local t1 = math.pi / 2 + (math.pi / 2) * (i + 1) / arcSegs
        local bx0 = arcCX + outerBarR * math.cos(t0)
        local bz0 = arcCZ + outerBarR * math.sin(t0)
        local bx1 = arcCX + outerBarR * math.cos(t1)
        local bz1 = arcCZ + outerBarR * math.sin(t1)
        local mx = (bx0 + bx1) / 2
        local mz = (bz0 + bz1) / 2
        local ddx = bx1 - bx0
        local ddz = bz1 - bz0
        local bLen = math.sqrt(ddx * ddx + ddz * ddz)
        local bAngle = math.deg(math.atan(ddx, ddz))

        local obNode = scene_:CreateChild("Arc_OuterBeam_" .. i)
        obNode.position = Vector3(mx, th - beamH / 2, mz)
        obNode.rotation = Quaternion(bAngle, Vector3.UP)
        obNode.scale = Vector3(barThick * 2, beamH, bLen + 0.02)
        local obModel = obNode:CreateComponent("StaticModel")
        obModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        obModel:SetMaterial(Mat.CreatePBR(COLORS.TunnelBar, 0.0, 0.65))
        obModel.castShadows = true
    end

    -- 招牌
    -- CreateTavernSign(scene_, arcCX, arcCZ, R, halfW, th)

    -- 保存场景引用和关键尺寸，供后续填充使用
    M._scene = scene_
    M._tunnelH = th

    print("[Scene] Connector created: ArmA + QuarterArc + ArmB")
end

-- ============================================================================
-- 连接处果冻填充
-- ============================================================================

--- 计算连接处所有果冻段的几何信息（位置、大小、旋转）
---@return table[] segments
local function CalcConnectorSegments()
    local th = CONFIG.TunnelHeight
    local wt = CONFIG.WallThickness
    local st = 0.15  -- 地板厚度
    local jellyH = th - st - 0.15  -- 地板到天花板之间
    local bottomY = st / 2

    local segments = {}

    -- Arm A（水平廊道）
    local armAW = CONFIG.ArmAWidth - wt * 2 - 0.2
    local armAD = CONFIG.ArmADepth - wt * 2 - 0.2
    table.insert(segments, {
        cx = CONFIG.ArmACenterX,
        cz = CONFIG.ArmACenterZ,
        w = armAW,
        d = armAD,
        h = jellyH,
        bottomY = bottomY,
        rot = nil,
    })

    -- 弧形段
    local arcCX = CONFIG.ArcCenterX
    local arcCZ = CONFIG.ArcCenterZ
    local R = CONFIG.ArcRadius
    local halfW = CONFIG.ArcWidth / 2
    local arcSegs = CONFIG.ArcSegments

    for i = 0, arcSegs - 1 do
        local t0 = math.pi / 2 + (math.pi / 2) * i / arcSegs
        local t1 = math.pi / 2 + (math.pi / 2) * (i + 1) / arcSegs
        local tMid = (t0 + t1) / 2

        local x0 = arcCX + R * math.cos(t0)
        local z0 = arcCZ + R * math.sin(t0)
        local x1 = arcCX + R * math.cos(t1)
        local z1 = arcCZ + R * math.sin(t1)
        local xM = (x0 + x1) / 2
        local zM = (z0 + z1) / 2

        local dx = x1 - x0
        local dz = z1 - z0
        local segLen = math.sqrt(dx * dx + dz * dz)
        local angle = math.deg(math.atan(dx, dz))

        local segW = CONFIG.ArcWidth - wt * 2 - 0.2

        table.insert(segments, {
            cx = xM,
            cz = zM,
            w = segW,
            d = segLen + 0.02,
            h = jellyH,
            bottomY = bottomY,
            rot = Quaternion(angle, Vector3.UP),
        })
    end

    -- Arm B（垂直廊道）
    local armBW = CONFIG.ArmBWidth - wt * 2 - 0.2
    local armBD = CONFIG.ArmBDepth - wt * 2 - 0.2
    table.insert(segments, {
        cx = CONFIG.ArmBCenterX,
        cz = CONFIG.ArmBCenterZ,
        w = armBW,
        d = armBD,
        h = jellyH,
        bottomY = bottomY,
        rot = nil,
    })

    return segments
end

--- 填充连接处（从外部调用）
---@param wineIdx number 酒类索引
---@param reverse boolean|nil true = 从 ArmB 向 ArmA 填充（左→右），nil/false = 从 ArmA 向 ArmB（右→左）
---@return boolean 是否成功开始填充
function M.Fill(wineIdx, reverse)
    if M.filled or M.fillingAnim then
        return false
    end

    local scene_ = M._scene
    if not scene_ then return false end

    local wine = Cfg.WINE_TYPES[wineIdx]
    local segs = CalcConnectorSegments()

    -- 反向填充：将段列表翻转
    if reverse then
        local reversed = {}
        for i = #segs, 1, -1 do
            table.insert(reversed, segs[i])
        end
        segs = reversed
    end

    M.fillingAnim = {
        segments = segs,
        wineIdx = wineIdx,
        wine = wine,
        currentSeg = 1,
        segProgress = 0,
        speed = 12.0,  -- 段/秒（填充速度）
    }

    M.filledWineIdx = wineIdx

    local dirStr = reverse and "ArmB→ArmA" or "ArmA→ArmB"
    print("[Connector] Start filling with " .. wine.name .. " (" .. dirStr .. ")")
    return true
end

--- 更新连接处填充动画（每帧调用）
---@param dt number
function M.UpdateFilling(dt)
    local anim = M.fillingAnim
    if not anim then return end

    local scene_ = M._scene
    if not scene_ then return end

    -- 每帧推进若干段
    anim.segProgress = anim.segProgress + anim.speed * dt

    while anim.currentSeg <= #anim.segments and anim.segProgress >= 1.0 do
        local seg = anim.segments[anim.currentSeg]

        -- 创建该段果冻节点
        local jellyNode = scene_:CreateChild("Connector_Jelly_" .. anim.currentSeg)
        jellyNode.position = Vector3(seg.cx, seg.bottomY + seg.h / 2, seg.cz)
        if seg.rot then
            jellyNode.rotation = seg.rot
        end
        jellyNode.scale = Vector3(seg.w, seg.h, seg.d)

        local model = jellyNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(Mat.CreateJelly(anim.wine))
        model.castShadows = true

        table.insert(M.jellyNodes, jellyNode)

        anim.currentSeg = anim.currentSeg + 1
        anim.segProgress = anim.segProgress - 1.0
    end

    -- 全部段填充完成
    if anim.currentSeg > #anim.segments then
        M.filled = true
        M.fillingAnim = nil
        print("[Connector] Filling complete!")
    end
end

--- 判断连接处是否为空（未填充且无动画）
---@return boolean
function M.IsEmpty()
    return not M.filled and not M.fillingAnim
end

--- 更换连接处酒液类型（视觉 + 数据同步更新）
---@param newWineIdx number 新的酒类索引
function M.ChangeWineType(newWineIdx)
    if not M.filled then return end
    local wine = Cfg.WINE_TYPES[newWineIdx]
    M.filledWineIdx = newWineIdx
    local newMat = Mat.CreateJelly(wine)
    for _, node in ipairs(M.jellyNodes) do
        local model = node:GetComponent("StaticModel")
        if model then
            model:SetMaterial(newMat)
        end
    end
end

-- ============================================================================
-- 重置（重新开始时调用）
-- ============================================================================

function M.Reset()
    M.filled = false
    M.filledWineIdx = nil
    M.jellyNodes = {}
    M.fillingAnim = nil
    M._scene = nil
    M._tunnelH = nil
end

return M
