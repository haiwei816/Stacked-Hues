-- ============================================================================
-- 倒果汁大楼 - Stacked Hues
-- 2.5D 等距视角物理游戏
-- 画风：基础白模 + 圆弧连接布局
-- ============================================================================
--
-- 玩法说明:
--   - 右键按住左/右大楼天台，酒液从天台倾泻而下，填充到最底层
--   - 数字键 1-6 切换六种果汁（橙汁/葡萄汁/西瓜汁/猕猴桃汁/蓝莓汁/柠檬汁）
--   - 鼠标左键拖动旋转视角，滚轮缩放
--   - 按 F 键或点击按钮为两座塔叠加楼层
--
-- ============================================================================

local Cfg = require("Config")
local Builders = require("Builders")
local Tower = require("Tower")
local Connector = require("Connector")
local CardSystem = require("CardSystem")
local GameUI = require("GameUI")

local CONFIG = Cfg.CONFIG

-- ============================================================================
-- 场景与相机
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
---@type Camera
local camera_ = nil
---@type PhysicsWorld
local physicsWorld_ = nil

-- 相机控制
local camYaw_ = 45.0
local camPitch_ = 30.0
local camDistance_ = 50.0
local camTarget_ = Vector3(1, 6, -7)

-- 左键拖拽判定
local leftDragDist_ = 0

-- 积分里程碑（用于按钮加层后同步状态）
local lastScoreMilestone_ = 0

-- 音频
---@type Node
local bgmNode_ = nil
---@type SoundSource
local bgmSource_ = nil

-- ============================================================================
-- 辅助
-- ============================================================================

local function Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

-- 播放一次性音效
local function PlaySFX(path, gain)
    local sound = cache:GetResource("Sound", path)
    if not sound then return end
    local node = scene_:CreateChild("SFX")
    local source = node:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source.gain = gain or 0.6
    source.autoRemoveMode = REMOVE_NODE
    source:Play(sound)
end

-- ============================================================================
-- 相机
-- ============================================================================

local function UpdateCameraPosition()
    local yawRad = math.rad(camYaw_)
    local pitchRad = math.rad(camPitch_)

    local cosP = math.cos(pitchRad)
    local sinP = math.sin(pitchRad)
    local cosY = math.cos(yawRad)
    local sinY = math.sin(yawRad)

    local offset = Vector3(
        camDistance_ * cosP * sinY,
        camDistance_ * sinP,
        -camDistance_ * cosP * cosY
    )

    cameraNode_.position = Vector3(
        camTarget_.x + offset.x,
        camTarget_.y + offset.y,
        camTarget_.z + offset.z
    )
    cameraNode_:LookAt(camTarget_)
end

local function HandleCameraControl(dt)
    local wheel = input.mouseMoveWheel
    if wheel ~= 0 then
        camera_.orthoSize = Clamp(
            camera_.orthoSize - wheel * CONFIG.CameraZoomSpeed,
            CONFIG.CameraMinOrtho,
            CONFIG.CameraMaxOrtho
        )
    end

    if input:GetMouseButtonDown(MOUSEB_LEFT) and not CardSystem.IsDragging() then
        local dx = input.mouseMoveX
        local dy = input.mouseMoveY
        leftDragDist_ = leftDragDist_ + math.abs(dx) + math.abs(dy)
        camYaw_ = camYaw_ - dx * CONFIG.CameraRotateSpeed
        camPitch_ = Clamp(camPitch_ + dy * CONFIG.CameraRotateSpeed, 5.0, 85.0)
        UpdateCameraPosition()
    end
end

-- ============================================================================
-- 重新开始
-- ============================================================================

local function RestartGame()
    -- 1) 重置各模块状态
    Tower.Reset()
    Connector.Reset()
    CardSystem.InitHandCards()

    -- 2) 移除场景中除 Camera 和 LightGroup 之外的所有子节点
    local children = {}
    for i = 0, scene_:GetNumChildren(false) - 1 do
        local child = scene_:GetChild(i)
        local name = child:GetName()
        if name ~= "Camera" and name ~= "LightGroup" and name ~= "Zone" then
            table.insert(children, child)
        end
    end
    for _, child in ipairs(children) do
        child:Remove()
    end

    -- 3) 重建场景
    Builders.CreateBase(scene_)
    Builders.CreateRoad(scene_)
    Tower.CreateTowers(scene_)
    Connector.Create(scene_)
    Builders.CreateTrees(scene_)
    Builders.CreateDecorations(scene_)

    -- 3.5) 通道默认填充
    Connector.Fill(1, false)
    for _ = 1, 200 do
        Connector.UpdateFilling(0.1)
        if Connector.filled then break end
    end

    -- 4) 重置积分里程碑
    lastScoreMilestone_ = 0

    -- 5) 重置相机
    camYaw_ = 45.0
    camPitch_ = 30.0
    camTarget_ = Vector3(1, 6, -7)
    camera_.orthoSize = CONFIG.CameraOrthoSize
    UpdateCameraPosition()

    -- 6) 重建 UI
    GameUI.Create()

    print("=== Game Restarted ===")
end

-- ============================================================================
-- 叠加楼层
-- ============================================================================

local function AddFloorToAllTowers()
    Tower.AddFloorToAllTowers(function(y)
        camTarget_.y = y
        UpdateCameraPosition()
    end)
    GameUI.UpdateFloorCount()
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = CONFIG.Title

    -- 初始化 UI
    GameUI.Init()

    -- 创建场景
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    -- 高对比度冷白光照预设
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Dusk.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    -- 高对比度氛围：冷白环境光 + 深色远景
    local zoneNode = scene_:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-1000, -1000, -1000), Vector3(1000, 1000, 1000))
    zone.ambientColor = Color(0.65, 0.65, 0.70)
    zone.fogColor = Color(0.08, 0.08, 0.10)
    zone.fogStart = 400.0
    zone.fogEnd = 600.0

    physicsWorld_ = scene_:CreateComponent("PhysicsWorld")
    physicsWorld_:SetGravity(CONFIG.Gravity)

    -- 设置相机
    cameraNode_ = scene_:CreateChild("Camera")
    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.orthographic = true
    camera_.nearClip = 0.1
    camera_.farClip = 200.0

    -- 检测屏幕比例：竖屏(手机) vs 横屏(平板/电脑)
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    CONFIG.IsPortrait = screenH > screenW
    if CONFIG.IsPortrait then
        camera_.orthoSize = 38.0
    else
        camera_.orthoSize = CONFIG.CameraOrthoSize
    end
    UpdateCameraPosition()

    local viewport = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true

    -- 构建场景
    Builders.CreateBase(scene_)
    Builders.CreateRoad(scene_)
    Tower.CreateTowers(scene_)
    Connector.Create(scene_)
    Builders.CreateTrees(scene_)
    Builders.CreateDecorations(scene_)

    -- 连接通道开局默认填充第一种果汁（橙汁）
    Connector.Fill(1, false)
    -- 立即完成填充动画（跳过逐段动画）
    for _ = 1, 200 do
        Connector.UpdateFilling(0.1)
        if Connector.filled then break end
    end

    -- 初始化背景音乐
    local bgm = cache:GetResource("Sound", "audio/bgm_healing.ogg")
    if bgm then
        bgm.looped = true
        bgmNode_ = scene_:CreateChild("BGM")
        bgmSource_ = bgmNode_:CreateComponent("SoundSource")
        bgmSource_.soundType = "Music"
        bgmSource_.gain = 0.25
        bgmSource_:Play(bgm)
    end

    -- 初始化卡片系统
    CardSystem.InitHandCards()

    -- 注册回调
    CardSystem.onFillStatusChanged = function() GameUI.UpdateFillStatus() end
    CardSystem.onWineTypeChanged   = function() GameUI.UpdateWineType() end
    CardSystem.onCardUIChanged     = function() GameUI.UpdateCards() end
    Tower.onScoreChanged           = function()
        GameUI.UpdateScore()
    end
    Tower.onJellyCleared           = function()
        PlaySFX("audio/sfx/jelly_clear.ogg", 0.5)
    end
    Tower.onPourStart              = function()
        PlaySFX("audio/sfx/juice_pour.ogg", 0.7)
    end
    Tower.onDrinkStart             = function()
        PlaySFX("audio/sfx/juice_drink.ogg", 0.6)
    end
    Tower.onDrinkEnd               = function()
        PlaySFX("audio/sfx/juice_burp.ogg", 0.7)
    end
    Tower.onGameOver               = function() GameUI.ShowGameOver() end
    GameUI.onAddFloor              = function()
        if Tower.score >= 1000 then
            Tower.score = Tower.score - 1000
            lastScoreMilestone_ = math.floor(Tower.score / 1000)
            GameUI.UpdateScore()
            AddFloorToAllTowers()
            PlaySFX("audio/sfx/floor_add.ogg", 0.5)
            print("[+1 Floor] Spent 1000 points, remaining: " .. Tower.score)
        else
            print("[+1 Floor] Not enough points! Need 1000, have " .. Tower.score)
        end
    end
    GameUI.onRestart               = RestartGame

    -- 创建 UI
    GameUI.Create()

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")

    print("=== Stacked Hues Started ===")
    print("Drag cards to towers to fill jelly!")
    print("Keys 1-6 to switch juice type, F to add floors")
end

function Stop()
    GameUI.Shutdown()
end

-- ============================================================================
-- 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    HandleCameraControl(dt)
    Tower.UpdateStickFiguresFacing(camYaw_, camPitch_)
    CardSystem.UpdateDrag(camera_, physicsWorld_)
    CardSystem.HandleWineTypeSwitch()
    Tower.UpdatePouringAnims(dt)
    Tower.UpdateFillingJellies(dt)
    Tower.UpdateClearingJellies(dt)
    Tower.UpdateFallingJellies(dt)
    Tower.UpdateDrinkingAnims(dt)
    Tower.UpdateSadFaceAnims(dt)
    Tower.UpdateFloorCelebrations(dt)
    Tower.UpdateTransfer(dt)
    Tower.CheckUTubeBalance()
    Connector.UpdateFilling(dt)
    Tower.CheckGameOver()

    if input:GetKeyPress(KEY_F) then
        AddFloorToAllTowers()
    end
end

function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        leftDragDist_ = 0
    end
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        -- 有选中卡牌且不在拖拽中，且鼠标没有大幅移动（排除相机旋转）
        if CardSystem.HasSelected() and not CardSystem.IsDragging() and leftDragDist_ < 10 then
            CardSystem.TryDropSelectedOnTower(camera_, physicsWorld_)
        end
    end
end
