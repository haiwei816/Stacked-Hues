-- ============================================================================
-- Materials.lua - PBR / 玻璃 / 果冻 / 发光材质工厂
-- ============================================================================

local M = {}

--- 创建不透明 PBR 材质
---@param color Color
---@param metallic number
---@param roughness number
---@return Material
function M.CreatePBR(color, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.4, 0.4, 0.4, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    return mat
end

--- 创建透明玻璃材质
---@param color Color
---@return Material
function M.CreateGlass(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.05))
    mat:SetShaderParameter("Roughness", Variant(0.15))
    return mat
end

--- 创建果冻材质（半透明、光滑、微发光）
---@param wine table WINE_TYPES 中的一项
---@return Material
function M.CreateJelly(wine)
    local color = wine.color
    local jellyColor = Color(color.r, color.g, color.b, 0.85)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(jellyColor))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.25))
    local em = wine.emitMul or 0.15
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(
        color.r * em, color.g * em, color.b * em
    )))
    return mat
end

--- 创建自发光材质（路灯、装饰灯等）
---@param color Color 基础颜色
---@param emissiveColor Color 发光颜色（HDR，可超过 1.0）
---@return Material
function M.CreateEmissive(color, emissiveColor)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.4, 0.4, 0.4, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(0.4))
    mat:SetShaderParameter("MatEmissiveColor", Variant(emissiveColor))
    return mat
end

return M
