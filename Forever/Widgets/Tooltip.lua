local _, Cell = ...
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

-----------------------------------------
-- Tooltip
-----------------------------------------
local function CreateTooltip(name, hasIcon)
    local tooltip = CreateFrame("GameTooltip", name, CellParent, "CellTooltipTemplate,BackdropTemplate")
    tooltip:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = 1})
    tooltip:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    tooltip:SetBackdropBorderColor(Cell.GetAccentColorRGB())
    tooltip:SetOwner(CellParent, "ANCHOR_NONE")

    if hasIcon then
        local iconBG = tooltip:CreateTexture(nil, "BACKGROUND")
        tooltip.iconBG = iconBG
        iconBG:SetSize(35, 35)
        iconBG:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -1, 0)
        iconBG:SetColorTexture(Cell.GetAccentColorRGB())
        iconBG:Hide()

        local icon = tooltip:CreateTexture(nil, "ARTWORK")
        tooltip.icon = icon
        P.Point(icon, "TOPLEFT", iconBG, 1, -1)
        P.Point(icon, "BOTTOMRIGHT", iconBG, -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:Hide()

        -- WoW Forever's GameTooltip doesn't have SetSpellByID at all.
        if not Cell.isForever then
            hooksecurefunc(tooltip, "SetSpellByID", function(self, id, tex)
                if tex then
                    iconBG:Show()
                    icon:SetTexture(tex)
                    icon:Show()
                end
            end)
        end
    end

    if Cell.isRetail then
        tooltip:RegisterEvent("TOOLTIP_DATA_UPDATE")
        tooltip:SetScript("OnEvent", function(self, event)
            if event ~= "TOOLTIP_DATA_UPDATE" then return end
            if not self:IsShown() then return end
            if not pcall(self.RefreshData, self) then
                self:Hide()
            end
        end)
    end

    tooltip:SetScript("OnTooltipCleared", function()
        -- reset border color
        tooltip:SetBackdropBorderColor(Cell.GetAccentColorRGB())
    end)

    -- tooltip:SetScript("OnTooltipSetItem", function()
    --     -- color border with item quality color
    --     tooltip:SetBackdropBorderColor(_G[name.."TextLeft1"]:GetTextColor())
    -- end)

    tooltip:SetScript("OnHide", function()
        -- SetX with invalid data may or may not clear the tooltip's contents.
        tooltip:ClearLines()

        if hasIcon then
            tooltip.iconBG:Hide()
            tooltip.icon:Hide()
        end
    end)

    function tooltip:UpdatePixelPerfect()
        tooltip:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
        tooltip:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        tooltip:SetBackdropBorderColor(Cell.GetAccentColorRGB())
        if hasIcon then
            P.Repoint(tooltip.icon)
            tooltip.iconBG:SetColorTexture(Cell.GetAccentColorRGB())
        end
    end
end

CreateTooltip("CellTooltip")
CreateTooltip("CellSpellTooltip", true)
-- CreateTooltip("CellScanningTooltip")

function F.ShowSpellTooltips(tooltip, spellID)
    local tooltipInfo = CreateBaseTooltipInfo("GetSpellByID", spellID)
    if not pcall(tooltip.ProcessInfo, tooltip, tooltipInfo) then
        tooltip:Hide()
        return
    end
    tooltip:Show()
end

local playerInCombat = false
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            playerInCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            playerInCombat = false
        else
            local ok, v = pcall(InCombatLockdown)
            playerInCombat = ok and v == true
        end
    end)
end

local function IsPlayerInCombat()
    if playerInCombat then return true end
    local ok, v = pcall(InCombatLockdown)
    return ok and v == true
end

local function UnitTooltipsEnabled()
    return CellDB and CellDB["general"] and CellDB["general"]["enableTooltips"] and true or false
end

local function HideUnitTooltipsInCombat()
    return CellDB and CellDB["general"] and CellDB["general"]["hideTooltipsInCombat"] and true or false
end

function F.ShouldShowUnitTooltip()
    if not UnitTooltipsEnabled() then return false end
    if HideUnitTooltipsInCombat() and IsPlayerInCombat() then return false end
    return true
end

function F.ApplyEngineAuraButtonTooltip(button, noTooltip)
    if not button then return end
    if noTooltip ~= nil then
        button._cellNoAuraTooltip = noTooltip and true or false
    end
    local cfg = button._cellAuraTooltipCfg
    if type(cfg) == "table" then
        button._cellNoAuraTooltip = cfg.showTooltip ~= true
    end
    local wantMotion = (not button._cellNoAuraTooltip) and UnitTooltipsEnabled()
    if button.SetMouseMotionEnabled then
        pcall(button.SetMouseMotionEnabled, button, wantMotion)
    end
    if button.SetHideTooltipInCombat then
        pcall(button.SetHideTooltipInCombat, button, wantMotion and HideUnitTooltipsInCombat())
    end
end

function F.SetupEngineAuraButtonMouse(button, noTooltip, cfg)
    if not button then return end
    pcall(button.SetMouseClickEnabled, button, false)
    if cfg ~= nil then
        button._cellAuraTooltipCfg = type(cfg) == "table" and cfg or nil
    end
    F.ApplyEngineAuraButtonTooltip(button, noTooltip and true or false)
end

function F.RefreshEngineAuraButtonTooltips()
    if not F.IterateAllUnitButtons then return end
    local function walk(frame)
        if not frame then return end
        if frame._cellNoAuraTooltip ~= nil then
            F.ApplyEngineAuraButtonTooltip(frame)
        end
        if frame.GetChildren then
            local ok, children = pcall(function()
                return { frame:GetChildren() }
            end)
            if ok then
                for i = 1, #children do
                    walk(children[i])
                end
            end
        end
    end
    F.IterateAllUnitButtons(function(b)
        walk(b)
    end)
end

function F.ShowTooltips(anchor, tooltipType, unit, aura, filter)
    if tooltipType == "unit" then
        if not F.ShouldShowUnitTooltip() then return end
    elseif not UnitTooltipsEnabled() then
        return
    end

    if CellDB["general"]["tooltipsPosition"][2] == "Default" then
        GameTooltip_SetDefaultAnchor(GameTooltip, anchor)
    elseif CellDB["general"]["tooltipsPosition"][2] == "Cell" then
        GameTooltip:SetOwner(Cell.frames.mainFrame, "ANCHOR_NONE")
        GameTooltip:SetPoint(CellDB["general"]["tooltipsPosition"][1], Cell.frames.mainFrame, CellDB["general"]["tooltipsPosition"][3], CellDB["general"]["tooltipsPosition"][4], CellDB["general"]["tooltipsPosition"][5])
    elseif CellDB["general"]["tooltipsPosition"][2] == "Unit Button" then
        GameTooltip:SetOwner(anchor, "ANCHOR_NONE")
        GameTooltip:SetPoint(CellDB["general"]["tooltipsPosition"][1], anchor, CellDB["general"]["tooltipsPosition"][3], CellDB["general"]["tooltipsPosition"][4], CellDB["general"]["tooltipsPosition"][5])
    elseif CellDB["general"]["tooltipsPosition"][2] == "Cursor" then
        GameTooltip:SetOwner(anchor, "ANCHOR_CURSOR")
    elseif CellDB["general"]["tooltipsPosition"][2] == "Cursor Left" then
        GameTooltip:SetOwner(anchor, "ANCHOR_CURSOR_LEFT", CellDB["general"]["tooltipsPosition"][4], CellDB["general"]["tooltipsPosition"][5])
    elseif CellDB["general"]["tooltipsPosition"][2] == "Cursor Right" then
        GameTooltip:SetOwner(anchor, "ANCHOR_CURSOR_RIGHT", CellDB["general"]["tooltipsPosition"][4], CellDB["general"]["tooltipsPosition"][5])
    end

    if tooltipType == "unit" then
        GameTooltip:SetUnit(unit)
    elseif tooltipType == "spell" and unit and aura then
        -- GameTooltip:SetSpellByID(aura)
        GameTooltip:SetUnitAura(unit, aura, filter)
    elseif tooltipType == "aura" and unit and aura then
        if filter == "HARMFUL" then
            GameTooltip:SetUnitDebuffByAuraInstanceID(unit, aura)
        elseif filter == "HELPFUL" then
            GameTooltip:SetUnitBuffByAuraInstanceID(unit, aura)
        end
    end
end