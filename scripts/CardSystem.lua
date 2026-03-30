-- ============================================================================
-- CardSystem.lua - 卡片系统（手牌管理、拖拽交互、投放逻辑）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Cfg = require("Config")
local Tower = require("Tower")
local Connector = require("Connector")
local WINE_TYPES = Cfg.WINE_TYPES
local CONFIG = Cfg.CONFIG

local M = {}

-- 运行时状态
M.currentWineIdx = 1
M.handCards = {}          -- 当前手牌 {wineIdx, wineIdx, wineIdx}
M.nextCardWineIdx = nil   -- 下一张卡牌预览

-- 拖拽状态（内部）
local dragCardIdx = nil   -- 正在拖拽的卡片槽位
local dragWineIdx = nil   -- 拖拽中的酒类索引
local dragGhost = nil     -- 跟随鼠标的幽灵卡片 UI
local dragActive = false  -- 是否正在拖拽

-- 点击选中状态
local selectedCardIdx = nil  -- 当前选中的卡片槽位

-- 外部回调（由 main 注入）
M.onFillStatusChanged = nil   -- function()
M.onWineTypeChanged = nil     -- function()
M.onCardUIChanged = nil       -- function()

-- ============================================================================
-- 手牌管理
-- ============================================================================

--- 随机生成一张卡片
local function RandomWineCard()
    return math.random(1, #WINE_TYPES)
end

--- 初始化手牌
function M.InitHandCards()
    M.handCards = {}
    for i = 1, CONFIG.CardCount do
        M.handCards[i] = RandomWineCard()
    end
    M.nextCardWineIdx = RandomWineCard()
end

-- ============================================================================
-- 卡片颜色
-- ============================================================================

--- 获取卡片的颜色信息（画廊级毛玻璃风格）
---@param wineIdx number
---@return number r, number g, number b
function M.GetCardColors(wineIdx)
    local wine = WINE_TYPES[wineIdx]
    local r = math.floor(wine.color.r * 255)
    local g = math.floor(wine.color.g * 255)
    local b = math.floor(wine.color.b * 255)
    return r, g, b
end

-- ============================================================================
-- 拖拽逻辑
-- ============================================================================

--- 隐藏幽灵卡片
local function HideDragGhost()
    if dragGhost then
        dragGhost:Destroy()
        dragGhost = nil
    end
end

--- 显示跟随鼠标的幽灵卡片
---@param wineIdx number
local function ShowDragGhost(wineIdx)
    local root = UI.GetRoot()
    if not root then return end

    local wine = WINE_TYPES[wineIdx]
    local r, g, b = M.GetCardColors(wineIdx)

    HideDragGhost()

    local p = CONFIG.IsPortrait
    dragGhost = UI.Panel {
        id = "dragGhost",
        position = "absolute",
        top = 0,
        left = 0,
        width = p and 70 or 90,
        height = p and 95 or 120,
        borderRadius = p and 10 or 12,
        backgroundColor = {20, 20, 28, 230},
        borderWidth = 1,
        borderColor = {r, g, b, 200},
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        opacity = 0.9,
        pointerEvents = "none",
        children = {
            UI.Panel {
                width = p and 24 or 28,
                height = p and 24 or 28,
                borderRadius = p and 12 or 14,
                backgroundColor = {r, g, b, 255},
                marginBottom = p and 6 or 8,
                pointerEvents = "none",
            },
            UI.Label {
                text = wine.shortName,
                fontSize = p and 16 or 18,
                fontWeight = "bold",
                fontColor = {240, 240, 245, 240},
                textAlign = "center",
                pointerEvents = "none",
            },
        },
    }
    root:AddChild(dragGhost)
end

--- 更新幽灵卡片位置
local function UpdateDragGhostPosition()
    if not dragGhost or not dragActive then return end

    local mousePos = input:GetMousePosition()
    local dpr = graphics:GetDPR()
    local halfW = CONFIG.IsPortrait and 35 or 45
    local halfH = CONFIG.IsPortrait and 48 or 60
    local uiX = mousePos.x / dpr - halfW
    local uiY = mousePos.y / dpr - halfH

    dragGhost.top = uiY
    dragGhost.left = uiX
end

--- 选中卡牌的高亮样式
local function ApplySelectedStyle(cardIdx)
    local root = UI.GetRoot()
    if not root then return end
    local card = root:FindById("card_" .. cardIdx)
    if card then
        local r, g, b = M.GetCardColors(M.handCards[cardIdx])
        card:SetStyle({ scale = 1.15, translateY = -10, borderColor = {r, g, b, 255} })
    end
end

--- 恢复卡牌默认样式
local function ClearSelectedStyle(cardIdx)
    local root = UI.GetRoot()
    if not root then return end
    local card = root:FindById("card_" .. cardIdx)
    if card then
        local r, g, b = M.GetCardColors(M.handCards[cardIdx])
        card:SetStyle({ scale = 1.0, translateY = 0, borderColor = {r, g, b, 120}, opacity = 1.0 })
    end
end

-- 拖拽起始鼠标位置
local dragStartX = 0
local dragStartY = 0

--- 开始拖拽卡片
---@param cardIdx number 卡片槽位 (1~CardCount)
function M.StartDragCard(cardIdx)
    if dragActive then return end
    if Tower.gameOver then return end
    -- 动画进行中时禁止拖放，防止并发修改状态导致 bug
    if Tower.transferAnim then return end
    if #Tower.clearingJellies > 0 then return end
    if #Tower.fillingJellies > 0 then return end
    if #Tower.fallingJellies > 0 then return end
    if #Tower.pouringAnims > 0 then return end
    if Connector.fillingAnim then return end

    -- 如果已有选中的卡牌，先清除
    if selectedCardIdx then
        ClearSelectedStyle(selectedCardIdx)
        selectedCardIdx = nil
    end

    dragCardIdx = cardIdx
    dragWineIdx = M.handCards[cardIdx]
    dragActive = true

    local mousePos = input:GetMousePosition()
    dragStartX = mousePos.x
    dragStartY = mousePos.y

    ShowDragGhost(dragWineIdx)

    local root = UI.GetRoot()
    if root then
        local card = root:FindById("card_" .. cardIdx)
        if card then
            card:SetStyle({ opacity = 0.3 })
        end
    end

    print("[Drag] Started dragging card #" .. cardIdx .. " (" .. WINE_TYPES[dragWineIdx].name .. ")")
end

--- 结束拖拽：尝试将卡片投放到塔楼
---@param camera Camera
---@param physicsWorld PhysicsWorld
function M.EndDragCard(camera, physicsWorld)
    if not dragActive then return end

    -- 判断是点击还是拖拽（移动距离 < 10 像素视为点击）
    local mousePos = input:GetMousePosition()
    local dx = mousePos.x - dragStartX
    local dy = mousePos.y - dragStartY
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist < 10 then
        -- 点击 → 转为选中模式
        HideDragGhost()
        local clickedIdx = dragCardIdx
        dragCardIdx = nil
        dragWineIdx = nil
        dragActive = false
        M.SelectCard(clickedIdx)
        return
    end

    -- 恢复原卡片样式（透明度、缩放、位移、边框）
    local root = UI.GetRoot()
    if root and dragCardIdx then
        local card = root:FindById("card_" .. dragCardIdx)
        if card then
            local r, g, b = M.GetCardColors(M.handCards[dragCardIdx])
            card:SetStyle({ opacity = 1.0, scale = 1.0, translateY = 0, borderColor = {r, g, b, 120} })
        end
    end

    -- Raycast 检测
    mousePos = input:GetMousePosition()
    local normalizedX = mousePos.x / graphics:GetWidth()
    local normalizedY = mousePos.y / graphics:GetHeight()

    local ray = camera:GetScreenRay(normalizedX, normalizedY)
    local result = physicsWorld:RaycastSingle(ray, 200.0)

    local droppedOnTower = false

    if result.body ~= nil then
        local hitNode = result.body:GetNode()
        local nodeName = hitNode:GetName()

        -- 检测是否命中塔楼或连接处
        local hitTower = false
        for _, towerData in ipairs(Tower.towers) do
            if string.find(nodeName, towerData.name, 1, true) then
                hitTower = true
                break
            end
        end
        local hitConnector = string.find(nodeName, "Arm", 1, true)
            or string.find(nodeName, "Arc_", 1, true)

        if hitTower or hitConnector then
            -- 连接处为空时，优先填充连接处
            if Connector.IsEmpty() then
                M.currentWineIdx = dragWineIdx
                if M.onWineTypeChanged then M.onWineTypeChanged() end

                -- 根据命中位置判断填充方向
                -- LeftTower 或 ArmB 侧 → 从 ArmB 向 ArmA 填充（reverse）
                -- RightTower 或 ArmA 侧 → 从 ArmA 向 ArmB 填充（正向）
                local fillReverse = false
                if string.find(nodeName, "LeftTower", 1, true)
                    or string.find(nodeName, "ArmB", 1, true) then
                    fillReverse = true
                end

                Connector.Fill(dragWineIdx, fillReverse)
                if M.onFillStatusChanged then M.onFillStatusChanged() end

                local oldWine = WINE_TYPES[dragWineIdx].name
                M.handCards[dragCardIdx] = M.nextCardWineIdx
                M.nextCardWineIdx = RandomWineCard()
                if M.onCardUIChanged then M.onCardUIChanged() end

                local dirStr = fillReverse and "ArmB→ArmA" or "ArmA→ArmB"
                print("[Drag] Connector empty → filling " .. dirStr .. " with " .. oldWine)
                droppedOnTower = true
            else
                -- 连接处已满，正常填充塔楼
                for _, towerData in ipairs(Tower.towers) do
                    if string.find(nodeName, towerData.name, 1, true) then
                        if towerData.filledFloors < towerData.currentFloors then
                            M.currentWineIdx = dragWineIdx
                            if M.onWineTypeChanged then M.onWineTypeChanged() end

                            Tower.FillTowerFloor(towerData, dragWineIdx)
                            if M.onFillStatusChanged then M.onFillStatusChanged() end

                            local oldWine = WINE_TYPES[dragWineIdx].name
                            M.handCards[dragCardIdx] = M.nextCardWineIdx
                            M.nextCardWineIdx = RandomWineCard()
                            if M.onCardUIChanged then M.onCardUIChanged() end

                            local newWine = WINE_TYPES[M.handCards[dragCardIdx]].name
                            print("[Drag] Dropped on " .. towerData.name .. " (" .. oldWine .. ") → new card: " .. newWine)
                            droppedOnTower = true
                        else
                            print("[Drag] " .. towerData.name .. " is full!")
                        end
                        break
                    end
                end

                -- 如果命中的是连接处但连接处已满，提示
                if not droppedOnTower and hitConnector then
                    print("[Drag] Connector already filled!")
                end
            end
        end
    end

    if not droppedOnTower then
        print("[Drag] Dropped outside tower - cancelled")
    end

    HideDragGhost()
    dragCardIdx = nil
    dragWineIdx = nil
    dragActive = false
end

--- 是否正在拖拽
---@return boolean
function M.IsDragging()
    return dragActive
end

--- 是否有选中的卡牌
---@return boolean
function M.HasSelected()
    return selectedCardIdx ~= nil
end

--- 选中/取消选中卡牌
function M.SelectCard(cardIdx)
    if dragActive then return end
    if Tower.gameOver then return end
    if Tower.transferAnim then return end
    if #Tower.clearingJellies > 0 then return end
    if #Tower.fillingJellies > 0 then return end
    if #Tower.fallingJellies > 0 then return end
    if #Tower.pouringAnims > 0 then return end
    if Connector.fillingAnim then return end

    if selectedCardIdx == cardIdx then
        -- 点击已选中的卡牌 → 取消选中
        ClearSelectedStyle(cardIdx)
        selectedCardIdx = nil
        print("[Select] Deselected card #" .. cardIdx)
        return
    end

    -- 取消旧的选中
    if selectedCardIdx then
        ClearSelectedStyle(selectedCardIdx)
    end

    -- 选中新卡牌
    selectedCardIdx = cardIdx
    ApplySelectedStyle(cardIdx)
    print("[Select] Selected card #" .. cardIdx .. " (" .. WINE_TYPES[M.handCards[cardIdx]].name .. ")")
end

--- 点击塔楼投放选中的卡牌
---@param camera Camera
---@param physicsWorld PhysicsWorld
---@return boolean 是否成功投放
function M.TryDropSelectedOnTower(camera, physicsWorld)
    if not selectedCardIdx then return false end

    local mousePos = input:GetMousePosition()
    local normalizedX = mousePos.x / graphics:GetWidth()
    local normalizedY = mousePos.y / graphics:GetHeight()

    local ray = camera:GetScreenRay(normalizedX, normalizedY)
    local result = physicsWorld:RaycastSingle(ray, 200.0)

    if result.body == nil then return false end

    local hitNode = result.body:GetNode()
    local nodeName = hitNode:GetName()

    local hitTower = false
    for _, towerData in ipairs(Tower.towers) do
        if string.find(nodeName, towerData.name, 1, true) then
            hitTower = true
            break
        end
    end
    local hitConnector = string.find(nodeName, "Arm", 1, true)
        or string.find(nodeName, "Arc_", 1, true)

    if not hitTower and not hitConnector then return false end

    local wineIdx = M.handCards[selectedCardIdx]
    local droppedOk = false

    if Connector.IsEmpty() then
        M.currentWineIdx = wineIdx
        if M.onWineTypeChanged then M.onWineTypeChanged() end

        local fillReverse = false
        if string.find(nodeName, "LeftTower", 1, true)
            or string.find(nodeName, "ArmB", 1, true) then
            fillReverse = true
        end

        Connector.Fill(wineIdx, fillReverse)
        if M.onFillStatusChanged then M.onFillStatusChanged() end

        M.handCards[selectedCardIdx] = M.nextCardWineIdx
        M.nextCardWineIdx = RandomWineCard()
        if M.onCardUIChanged then M.onCardUIChanged() end

        print("[Select] Connector filled with " .. WINE_TYPES[wineIdx].name)
        droppedOk = true
    else
        for _, towerData in ipairs(Tower.towers) do
            if string.find(nodeName, towerData.name, 1, true) then
                if towerData.filledFloors < towerData.currentFloors then
                    M.currentWineIdx = wineIdx
                    if M.onWineTypeChanged then M.onWineTypeChanged() end

                    Tower.FillTowerFloor(towerData, wineIdx)
                    if M.onFillStatusChanged then M.onFillStatusChanged() end

                    M.handCards[selectedCardIdx] = M.nextCardWineIdx
                    M.nextCardWineIdx = RandomWineCard()
                    if M.onCardUIChanged then M.onCardUIChanged() end

                    print("[Select] Dropped on " .. towerData.name .. " (" .. WINE_TYPES[wineIdx].name .. ")")
                    droppedOk = true
                else
                    print("[Select] " .. towerData.name .. " is full!")
                end
                break
            end
        end
    end

    -- 清除选中状态
    ClearSelectedStyle(selectedCardIdx)
    selectedCardIdx = nil
    return droppedOk
end

--- 每帧更新拖拽状态
---@param camera Camera
---@param physicsWorld PhysicsWorld
function M.UpdateDrag(camera, physicsWorld)
    if not dragActive then return end

    UpdateDragGhostPosition()

    if not input:GetMouseButtonDown(MOUSEB_LEFT) then
        M.EndDragCard(camera, physicsWorld)
    end
end

-- ============================================================================
-- 创建单张卡片 UI 控件
-- ============================================================================

--- 创建单张卡片 UI
---@param cardIdx number 卡片槽位
---@return table 卡片控件
function M.CreateCardWidget(cardIdx)
    local wineIdx = M.handCards[cardIdx]
    local wine = WINE_TYPES[wineIdx]
    local r, g, b = M.GetCardColors(wineIdx)

    local p = CONFIG.IsPortrait
    return UI.Panel {
        id = "card_" .. cardIdx,
        width = p and 70 or 90,
        height = p and 95 or 120,
        borderRadius = p and 10 or 12,
        backgroundColor = {20, 20, 28, 230},
        borderWidth = 1,
        borderColor = {r, g, b, 120},
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        marginLeft = cardIdx > 1 and (p and 8 or 10) or 0,
        cursor = "pointer",
        transition = "scale 0.15s easeOut, translateY 0.15s easeOut, borderColor 0.15s easeOut, opacity 0.12s easeOut",
        onPointerDown = function(event, widget)
            widget:SetStyle({ scale = 1.15, translateY = -10, borderColor = {r, g, b, 255} })
            M.StartDragCard(cardIdx)
        end,
        children = {
            UI.Panel {
                width = p and 24 or 28,
                height = p and 24 or 28,
                borderRadius = p and 12 or 14,
                backgroundColor = {r, g, b, 255},
                marginBottom = p and 6 or 8,
            },
            UI.Label {
                text = wine.shortName,
                fontSize = p and 16 or 18,
                fontWeight = "bold",
                fontColor = {240, 240, 245, 240},
                textAlign = "center",
            },
        },
    }
end

--- 创建"下一张卡牌"预览控件（较小、半透明）
---@return table
function M.CreateNextCardWidget()
    local wineIdx = M.nextCardWineIdx
    if not wineIdx then return UI.Panel { width = 70, height = 100 } end
    local wine = WINE_TYPES[wineIdx]
    local r, g, b = M.GetCardColors(wineIdx)

    local p = CONFIG.IsPortrait
    return UI.Panel {
        id = "nextCard",
        width = p and 55 or 70,
        height = p and 75 or 100,
        borderRadius = p and 8 or 10,
        backgroundColor = {15, 15, 22, 200},
        borderWidth = 1,
        borderColor = {r, g, b, 80},
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = p and 18 or 22,
                height = p and 18 or 22,
                borderRadius = p and 9 or 11,
                backgroundColor = {r, g, b, 200},
                marginBottom = p and 4 or 6,
            },
            UI.Label {
                text = wine.shortName,
                fontSize = p and 12 or 13,
                fontWeight = "bold",
                fontColor = {200, 200, 210, 210},
                textAlign = "center",
            },
        },
    }
end

--- 数字键 1-6 切换酒类
function M.HandleWineTypeSwitch()
    local keys = { KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6 }
    for i, key in ipairs(keys) do
        if input:GetKeyPress(key) then
            M.currentWineIdx = i
            if M.onWineTypeChanged then M.onWineTypeChanged() end
            local wine = WINE_TYPES[i]
            print("[Wine] Switched to: " .. wine.name .. " (" .. wine.shortName .. " / " .. wine.genre .. ")")
            break
        end
    end
end

return M
