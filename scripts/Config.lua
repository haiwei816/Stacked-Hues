-- ============================================================================
-- Config.lua - 配置常量、酒类定义、色板
-- ============================================================================

local M = {}

-- ============================================================================
-- 六种果汁定义（高对比度鲜艳饱和色，带微发光）
-- ============================================================================
M.WINE_TYPES = {
    {
        name = "橙汁 Orange",
        shortName = "OR",
        genre = "烈焰",
        desc = "浓烈鲜橙",
        color = Color(1.0, 0.55, 0.0, 1.0),
        metallic = 0.0,
        roughness = 0.30,
        emitMul = 0.15,
    },
    {
        name = "葡萄汁 Grape",
        shortName = "PU",
        genre = "深紫",
        desc = "浓郁葡萄紫",
        color = Color(0.60, 0.15, 0.80, 1.0),
        metallic = 0.0,
        roughness = 0.30,
        emitMul = 0.15,
    },
    {
        name = "西瓜汁 Watermelon",
        shortName = "RD",
        genre = "鲜红",
        desc = "浓烈西瓜红",
        color = Color(1.0, 0.15, 0.25, 1.0),
        metallic = 0.0,
        roughness = 0.30,
        emitMul = 0.15,
    },
    {
        name = "猕猴桃汁 Kiwi",
        shortName = "GR",
        genre = "翠绿",
        desc = "鲜亮翠绿",
        color = Color(0.20, 0.85, 0.15, 1.0),
        metallic = 0.0,
        roughness = 0.30,
        emitMul = 0.15,
    },
    {
        name = "蓝莓汁 Blueberry",
        shortName = "BL",
        genre = "湛蓝",
        desc = "明亮宝蓝",
        color = Color(0.10, 0.45, 1.0, 1.0),
        metallic = 0.0,
        roughness = 0.30,
        emitMul = 0.15,
    },
    {
        name = "柠檬汁 Lemon",
        shortName = "YL",
        genre = "明黄",
        desc = "耀眼柠檬黄",
        color = Color(0.95, 1.0, 0.15, 1.0),
        metallic = 0.0,
        roughness = 0.30,
        emitMul = 0.15,
    },
}

-- ============================================================================
-- 游戏配置
-- ============================================================================
M.CONFIG = {
    Title = "Stacked Hues",

    -- 相机
    CameraOrthoSize = 28.0,
    CameraMinOrtho = 12.0,
    CameraMaxOrtho = 60.0,
    CameraZoomSpeed = 0.1,
    CameraRotateSpeed = 0.15,

    -- 大楼通用参数
    WallThickness = 0.15,
    FloorSpacing = 4.0,
    FloorCount = 3,
    MaxFloors = 20,
    ShelfThickness = 0.5,
    ShelfOverhang = 0.35,

    -- 右上塔: 12×7, center(8, 0)
    RightTowerW = 12.0,
    RightTowerD = 7.0,
    RightTowerX = 8.0,
    RightTowerZ = 0.0,
    RightOpenFace = "west",

    -- 左下塔: 7×12, center(-5, -13)
    LeftTowerW = 7.0,
    LeftTowerD = 12.0,
    LeftTowerX = -5.0,
    LeftTowerZ = -13.0,
    LeftOpenFace = "north",

    -- Arm A（水平廊道）
    ArmAWidth = 3.0,
    ArmADepth = 3.0,
    ArmACenterX = 0.5,
    ArmACenterZ = 1.0,

    -- 四分之一弧
    ArcCenterX = -1.0,
    ArcCenterZ = -3.0,
    ArcRadius = 4.0,
    ArcWidth = 3.0,
    ArcSegments = 20,
    BarCount = 16,

    -- Arm B（垂直廊道）
    ArmBWidth = 3.0,
    ArmBDepth = 4.0,
    ArmBCenterX = -5.0,
    ArmBCenterZ = -5.0,

    -- 通道通用
    TunnelHeight = 4.0,

    -- 底座
    BaseWidth = 40.0,
    BaseDepth = 42.0,
    BaseHeight = 0.3,
    BaseCenterX = 1.0,
    BaseCenterZ = -7.0,
    SidewalkWidth = 1.5,
    RoadWidth = 4.0,

    -- 酒液参数
    DropRadius = 0.18,
    DropSpawnOffset = 0.5,
    DropRestitution = 0.25,
    DropFriction = 0.7,
    DropMass = 0.4,
    DropSpread = 3.0,

    -- 物理
    Gravity = Vector3(0, -9.81, 0),

    -- 卡片
    CardCount = 3,

    -- 运行时由 main.lua 设置（竖屏手机 vs 横屏平板/电脑）
    IsPortrait = false,
}

-- ============================================================================
-- 高对比度色板（深底+亮色，黑白灰+鲜艳点缀）
-- ============================================================================
M.COLORS = {
    -- 建筑：深灰/炭黑 + 亮白边框
    TowerWall     = Color(0.18, 0.18, 0.20, 1.0),   -- 深炭灰墙面
    TowerGlass    = Color(0.70, 0.80, 0.90, 0.06),   -- 微透明玻璃质感
    TowerFrame    = Color(0.90, 0.90, 0.92, 1.0),    -- 亮白边框
    TowerRoof     = Color(0.12, 0.12, 0.14, 1.0),    -- 近黑屋顶
    TowerFloor    = Color(0.22, 0.22, 0.25, 1.0),    -- 深灰楼板

    -- 通道：深色 + 金属感
    TunnelWall    = Color(0.20, 0.20, 0.22, 1.0),    -- 深灰石墙
    TunnelGlass   = Color(0.60, 0.70, 0.80, 0.15),   -- 冷蓝透明
    TunnelFloor   = Color(0.15, 0.15, 0.18, 1.0),    -- 深色地板
    TunnelBar     = Color(0.85, 0.85, 0.88, 1.0),    -- 亮银栏杆

    -- 环境：深色底面
    Ground        = Color(0.10, 0.10, 0.12, 1.0),    -- 近黑地面
    Road          = Color(0.08, 0.08, 0.10, 1.0),    -- 黑色柏油路
    Sidewalk      = Color(0.20, 0.20, 0.22, 1.0),    -- 深灰人行道
    RoadLine      = Color(1.0, 1.0, 1.0, 1.0),       -- 纯白路标

    -- 树木：深干+亮冠
    TreeTrunk     = Color(0.25, 0.20, 0.15, 1.0),    -- 深棕树干
    TreeLeaf      = Color(0.10, 0.80, 0.30, 1.0),    -- 鲜绿树冠
    TreeLeafAlt   = Color(0.90, 0.25, 0.40, 1.0),    -- 鲜红树冠

    -- 吧台：深色实木
    BarCounter    = Color(0.15, 0.12, 0.10, 1.0),    -- 深黑吧台
    BarTop        = Color(0.25, 0.22, 0.18, 1.0),    -- 深棕台面
    BarStool      = Color(0.12, 0.10, 0.08, 1.0),    -- 深色凳

    -- 火柴人：纯白 + 黑眼
    StickBody     = Color(0.95, 0.95, 0.95, 1.0),    -- 纯白身体
    StickHead     = Color(1.0, 1.0, 1.0, 1.0),       -- 纯白面部
}

return M
