-- ============================================================================
-- GameUI.lua - UI 创建与状态更新（画廊级毛玻璃风格）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Cfg = require("Config")
local Tower = require("Tower")
local CardSystem = require("CardSystem")
local WINE_TYPES = Cfg.WINE_TYPES
local CONFIG = Cfg.CONFIG

local M = {}

-- 外部回调（由 main 注入）
M.onAddFloor = nil    -- function()
M.onRestart = nil     -- function() 重新开始回调

-- ============================================================================
-- 风格常量
-- ============================================================================

-- 高对比度主色调（亮青色）
local ACCENT = {0, 200, 255, 255}
local ACCENT_DIM = {0, 160, 220, 160}
local ACCENT_BRIGHT = {0, 220, 255, 255}
-- 高对比度辅助色（亮红）
local ROSE = {255, 60, 80, 255}
local ROSE_DIM = {200, 50, 60, 140}
-- 亮白文字
local TEXT_PRIMARY = {240, 240, 245, 240}
local TEXT_DIM = {160, 165, 175, 180}
-- 深色半透明背景
local GLASS_BG = {20, 20, 28, 210}
local GLASS_BORDER = {60, 60, 75, 120}

-- ============================================================================
-- 初始化 UI 系统
-- ============================================================================

function M.Init()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function M.Shutdown()
    UI.Shutdown()
end

-- ============================================================================
-- 创建游戏 UI
-- ============================================================================

function M.Create()
    local root = UI.Panel {
        id = "gameUI",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 顶部栏：毛玻璃条 + Score 居中
            UI.Panel {
                position = "absolute",
                top = 8,
                left = 16,
                right = 16,
                height = 40,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                backgroundColor = GLASS_BG,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = GLASS_BORDER,
                paddingLeft = 16,
                paddingRight = 16,
                pointerEvents = "box-none",
                children = {
                    -- 左侧标题
                    UI.Label {
                        text = "Stacked Hues",
                        fontSize = 14,
                        fontColor = ACCENT_DIM,
                        textAlign = "left",
                    },
                    -- 中央积分
                    UI.Label {
                        id = "scoreLabel",
                        text = "Score: 0",
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = TEXT_PRIMARY,
                        textAlign = "center",
                    },
                    -- 右侧加层按钮
                    UI.Panel {
                        height = 28,
                        paddingLeft = 12,
                        paddingRight = 12,
                        borderRadius = 14,
                        backgroundColor = {0, 180, 230, 40},
                        borderWidth = 1,
                        borderColor = {0, 200, 255, 140},
                        justifyContent = "center",
                        alignItems = "center",
                        cursor = "pointer",
                        onPointerDown = function(event, widget)
                            if M.onAddFloor then M.onAddFloor() end
                        end,
                        children = {
                            UI.Label {
                                text = "+1 Floor (1000)",
                                fontSize = 11,
                                fontColor = ACCENT,
                            },
                        },
                    },
                },
            },

            -- 左侧果汁列表（仅横屏显示）
            CONFIG.IsPortrait and nil or UI.Panel {
                id = "wineListPanel",
                position = "absolute",
                top = 60,
                left = 12,
                width = 150,
                backgroundColor = GLASS_BG,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = GLASS_BORDER,
                paddingTop = 10,
                paddingBottom = 10,
                paddingLeft = 12,
                paddingRight = 12,
                flexDirection = "column",
                children = (function()
                    local items = {}
                    for i, w in ipairs(WINE_TYPES) do
                        local wr = math.floor(w.color.r * 255)
                        local wg = math.floor(w.color.g * 255)
                        local wb = math.floor(w.color.b * 255)
                        table.insert(items, UI.Panel {
                            id = "wineRow_" .. i,
                            flexDirection = "row",
                            alignItems = "center",
                            marginBottom = (i < #WINE_TYPES) and 6 or 0,
                            children = {
                                UI.Panel {
                                    width = 8, height = 8, borderRadius = 4,
                                    backgroundColor = {wr, wg, wb, 220},
                                    marginRight = 8,
                                },
                                UI.Label {
                                    id = "wineItem_" .. i,
                                    text = w.shortName .. " " .. w.name,
                                    fontSize = 11,
                                    fontColor = (i == CardSystem.currentWineIdx)
                                        and {wr, wg, wb, 255} or TEXT_DIM,
                                },
                            },
                        })
                    end
                    return items
                end)(),
            },

            -- 底部卡片区域：毛玻璃底栏
            UI.Panel {
                position = "absolute",
                bottom = 12,
                left = CONFIG.IsPortrait and 8 or 16,
                right = CONFIG.IsPortrait and 8 or 16,
                height = CONFIG.IsPortrait and 120 or 150,
                backgroundColor = GLASS_BG,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = GLASS_BORDER,
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        id = "cardContainer",
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        pointerEvents = "box-none",
                        children = (function()
                            local cards = {}
                            for i = 1, CONFIG.CardCount do
                                table.insert(cards, CardSystem.CreateCardWidget(i))
                            end
                            -- 分隔线
                            local sep = CONFIG.IsPortrait and 10 or 16
                            table.insert(cards, UI.Panel {
                                width = 1,
                                height = CONFIG.IsPortrait and 55 or 70,
                                backgroundColor = ACCENT_DIM,
                                marginLeft = sep,
                                marginRight = sep,
                            })
                            -- 下一张卡牌预览区域
                            table.insert(cards, UI.Panel {
                                id = "nextCardArea",
                                flexDirection = "column",
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "NEXT",
                                        fontSize = 9,
                                        fontColor = ACCENT_DIM,
                                        textAlign = "center",
                                        marginBottom = 4,
                                    },
                                    CardSystem.CreateNextCardWidget(),
                                },
                            })
                            return cards
                        end)(),
                    },
                },
            },
        }
    }

    UI.SetRoot(root)
end

-- ============================================================================
-- UI 更新函数
-- ============================================================================

function M.UpdateFillStatus()
    -- 移除了右侧 fillStatus，不再需要
end

function M.UpdateFloorCount()
    -- 移除了右侧 floorCount，不再需要
end

function M.UpdateWineType()
    if CONFIG.IsPortrait then return end
    local root = UI.GetRoot()
    if not root then return end
    for i, w in ipairs(WINE_TYPES) do
        local item = root:FindById("wineItem_" .. i)
        if item then
            local wr = math.floor(w.color.r * 255)
            local wg = math.floor(w.color.g * 255)
            local wb = math.floor(w.color.b * 255)
            if i == CardSystem.currentWineIdx then
                item.fontColor = {wr, wg, wb, 255}
            else
                item.fontColor = TEXT_DIM
            end
        end
    end
end

function M.UpdateScore()
    local root = UI.GetRoot()
    if root then
        local label = root:FindById("scoreLabel")
        if label then
            label.text = "Score: " .. Tower.score
        end
    end
end

function M.UpdateCards()
    local root = UI.GetRoot()
    if not root then return end

    local container = root:FindById("cardContainer")
    if not container then return end

    container:ClearChildren()

    for i = 1, CONFIG.CardCount do
        container:AddChild(CardSystem.CreateCardWidget(i))
    end

    -- 分隔线
    local sep = CONFIG.IsPortrait and 10 or 16
    container:AddChild(UI.Panel {
        width = 1,
        height = CONFIG.IsPortrait and 55 or 70,
        backgroundColor = ACCENT_DIM,
        marginLeft = sep,
        marginRight = sep,
    })

    -- 下一张卡牌预览区域
    container:AddChild(UI.Panel {
        id = "nextCardArea",
        flexDirection = "column",
        alignItems = "center",
        children = {
            UI.Label {
                text = "NEXT",
                fontSize = 9,
                fontColor = ACCENT_DIM,
                textAlign = "center",
                marginBottom = 4,
            },
            CardSystem.CreateNextCardWidget(),
        },
    })
end

-- ============================================================================
-- 游戏失败遮罩
-- ============================================================================

function M.ShowGameOver()
    local root = UI.GetRoot()
    if not root then return end

    local overlay = UI.Panel {
        id = "gameOverOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = {10, 10, 15, 180},
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = {25, 25, 35, 240},
                borderRadius = 20,
                borderWidth = 1,
                borderColor = {255, 60, 80, 140},
                flexDirection = "column",
                alignItems = "center",
                paddingTop = 40,
                paddingBottom = 40,
                paddingLeft = 32,
                paddingRight = 32,
                children = {
                    UI.Label {
                        text = "GAME OVER",
                        fontSize = 28,
                        fontWeight = "bold",
                        fontColor = ROSE,
                        textAlign = "center",
                        marginBottom = 12,
                    },
                    UI.Label {
                        text = "All towers are full!",
                        fontSize = 14,
                        fontColor = TEXT_DIM,
                        textAlign = "center",
                        marginBottom = 28,
                    },
                    UI.Label {
                        text = "Final Score",
                        fontSize = 12,
                        fontColor = ACCENT_DIM,
                        textAlign = "center",
                        marginBottom = 4,
                    },
                    UI.Label {
                        id = "gameOverScore",
                        text = tostring(Tower.score),
                        fontSize = 42,
                        fontWeight = "bold",
                        fontColor = TEXT_PRIMARY,
                        textAlign = "center",
                        marginBottom = 32,
                    },
                    UI.Panel {
                        height = 40,
                        width = 140,
                        borderRadius = 20,
                        backgroundColor = {0, 180, 230, 60},
                        borderWidth = 1,
                        borderColor = {0, 200, 255, 200},
                        justifyContent = "center",
                        alignItems = "center",
                        cursor = "pointer",
                        onPointerDown = function(event, widget)
                            if M.onRestart then M.onRestart() end
                        end,
                        children = {
                            UI.Label {
                                text = "Restart",
                                fontSize = 15,
                                fontWeight = "bold",
                                fontColor = ACCENT_BRIGHT,
                                textAlign = "center",
                            },
                        },
                    },
                },
            },
        },
    }

    root:AddChild(overlay)
end

return M
