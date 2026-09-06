local _, Cell = ...

(function(Cell)
    local L = Cell.L
    ---@type CellFuncs
    local F = Cell.funcs
    ---@class CellUnitButtonFuncs
    local B = Cell.bFuncs
    ---@type CellIndicatorFuncs
    local I = Cell.iFuncs
    ---@type CellUtilityFuncs
    local U = Cell.uFuncs
    ---@type PixelPerfectFuncs
    local P = Cell.pixelPerfectFuncs
local function BD(b) return F.GetButtonData(b) end
-- Event-offloading disabled: Midnight health/power must stay on the unit button
-- (RegisterEvent/OnUpdate). Keep HookScript(OnAttributeChanged) + header auraContainer.
local useEventHub = false
    ---@type CellAnimations
    local A = Cell.animations
    local LGI = LibStub:GetLibrary("LibGroupInfo")

CELL_FADE_OUT_HEALTH_PERCENT = nil

local UnitGUID = UnitGUID
-- local UnitHealth = LibCLHealth.UnitHealth
local UnitName = UnitName
local GetUnitName = GetUnitName
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitIsFriend = UnitIsFriend
local UnitIsUnit = UnitIsUnit
local UnitIsPlayer = UnitIsPlayer
local UnitIsConnected = UnitIsConnected
local UnitIsAFK = UnitIsAFK
local UnitIsFeignDeath = UnitIsFeignDeath
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGhost = UnitIsGhost
local UnitPowerType = UnitPowerType
local UnitPowerMax = UnitPowerMax
-- local UnitInRange = UnitInRange
-- local UnitIsVisible = UnitIsVisible
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local GetTime = GetTime
local GetRaidTargetIndex = GetRaidTargetIndex
local GetReadyCheckStatus = GetReadyCheckStatus
local GetSpecialization = GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitIsCharmed = UnitIsCharmed
local UnitInPartyIsAI = UnitInPartyIsAI
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitThreatSituation = UnitThreatSituation
local GetThreatStatusColor = GetThreatStatusColor
local UnitExists = UnitExists
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local UnitPhaseReason = UnitPhaseReason
local IsInRaid = IsInRaid
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local _GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
local GetAuraSlots = C_UnitAuras.GetAuraSlots
local _GetAuraDataBySlot = C_UnitAuras.GetAuraDataBySlot
local _GetAuraDispelTypeColor = C_UnitAuras.GetAuraDispelTypeColor
local _IsAuraFilteredOut = C_UnitAuras.IsAuraFilteredOutByInstanceID
local _GetAuraDuration = C_UnitAuras.GetAuraDuration
local GetAuraDataByAuraInstanceID, GetAuraDataBySlot
local IsDelveInProgress = C_PartyInfo.IsDelveInProgress
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local CreateUnitHealPredictionCalculator = CreateUnitHealPredictionCalculator
local UnitHealthPercent = UnitHealthPercent
local CurveConstants = CurveConstants
local AbbreviateNumbers = AbbreviateNumbers
local SBI_ExponentialEaseOut = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local SBI_Immediate = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

local function GetUnitHealthPercent100(unit)
    if not (unit and UnitHealthPercent) then return nil end
    if CurveConstants and CurveConstants.ScaleTo100 then
        return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    end
    return UnitHealthPercent(unit, true)
end

local function SetStatusBarHealth(bar, value, maxValue)
    if not bar then return end
    bar:SetMinMaxValues(0, maxValue)
    local smoothEnum = (barAnimationType == "Smooth" and SBI_ExponentialEaseOut) or SBI_Immediate
    if smoothEnum then
        bar:SetValue(value, smoothEnum)
    else
        bar:SetValue(value)
    end
end

--! for AI followers, UnitClassBase is buggy
local UnitClassBase = function(unit)
    return select(2, UnitClass(unit))
end

local barAnimationType, highlightEnabled, predictionEnabled
local shieldEnabled, overshieldEnabled, overshieldReverseFillEnabled
local absorbEnabled, absorbInvertColor

local SECRET_HELPFUL_CAST_FALLBACK_WINDOW = 1.5
local secretHelpfulCastFallbacks = {
    [116841] = "external",
    [1044] = "external",   -- Blessing of Freedom / Bendición de Libertad (cast spell = buff spell)
    [86150] = "defensive", -- Guardian of Ancient Kings (cast spell)
    [86659] = "defensive", -- Guardian of Ancient Kings (base buff)
    [212641] = "defensive", -- Guardian of Ancient Kings (glyph/model variant)
    [498] = "defensive",   -- Divine Protection / Protección Divina (Holy/Protection, buff = cast)
    [403876] = "defensive", -- Divine Protection / Protección Divina (Retribution, wrapper spell)
    [184662] = "defensive",
    [1261562] = "defensive", -- Shield of Vengeance / Escudo de Venganza (buff aura from Divine Protection)
    [325197] = "external", -- Invoke Chi-Ji / Invocar a Chi-Ji (cast spell, applies Life Cocoon to party)
    [406220] = "external", -- Life Cocoon / Crisálida de Chi (buff aura from Chi-Ji)
    [432472] = "external", -- Holy Armaments / Santos Arreos (cast; NOT in Cell's externals table — explicit fallback needed)
    [360823] = "external", -- Verdant Embrace / Abrazo Verde (Preservation Evoker; signature "0:1:0:0" overlaps with Lifebind — explicit fallback needed)
    [357170] = "external", -- Time Dilation / Dilatación Temporal (Preservation Evoker)
    [102342] = "external", -- Ironbark / Corteza de Hierro (Restoration Druid)
    [33206]  = "external", -- Pain Suppression / Supresión del Dolor (Discipline Priest)
    [10060]  = "external", -- Power Infusion / Infusión de Poder (Discipline/Holy Priest)
    [47788]  = "external", -- Guardian Spirit / Espíritu Guardián (Holy Priest)
    [1022]   = "external", -- Blessing of Protection / Bendición de Protección (Holy Paladin)
    [6940]   = "external", -- Blessing of Sacrifice / Bendición de Sacrificio (Holy Paladin)
}

local secretHelpfulCastSkipOnPlayer = {
    [325197] = true, -- Invoke Chi-Ji: Life Cocoon lands on party member, not caster
    [360823] = true, -- Verdant Embrace: Lifebind lands on party member, not caster
}

local castExpectedBuff = {
    [116841]  = { spellId = 116841 },                  -- Tiger's Lust / Deseo del Tigre (cast = buff)
    [1044]    = { spellId = 1044 },                    -- Blessing of Freedom = Blessing of Freedom
    [86150]   = { spellId = 86150 },                   -- Guardian of Ancient Kings
    [86659]   = { spellId = 86659 },                   -- GoAK base buff
    [212641]  = { spellId = 212641 },                  -- GoAK glyph variant
    [498]     = { spellId = 498 },                                                   -- Divine Protection (Holy/Protection, buff = cast)
    [403876]  = { spellId = 1261562, spellIds = {[1261562]=true, [184662]=true} }, -- Divine Protection (Retribution, buff = Shield of Vengeance)
    [184662]  = { spellId = 184662, spellIds = {[184662]=true, [1261562]=true} },  -- Shield of Vengeance
    [1261562] = { spellId = 1261562, spellIds = {[1261562]=true, [184662]=true} }, -- Shield of Vengeance
    [325197]  = { spellId = 406220 },                  -- Invoke Chi-Ji → Life Cocoon
    [406220]  = { spellId = 406220 },                  -- Life Cocoon
    [432472]  = { spellId = 432472 },                  -- Holy Armaments
    [360823]  = { spellId = 363534 },                  -- Verdant Embrace → Lifebind
    [357170]  = { spellId = 357170 },                   -- Time Dilation
    [102342]  = { spellId = 102342 },                   -- Ironbark
    [33206]   = { spellId = 33206 },                    -- Pain Suppression
    [10060]   = { spellId = 10060 },                    -- Power Infusion
    [47788]   = { spellId = 47788 },                    -- Guardian Spirit
    [1022]    = { spellId = 1022 },                     -- Blessing of Protection
    [6940]    = { spellId = 6940 },                     -- Blessing of Sacrifice
}
local recentSecretHelpfulCasts = {}

Cell._hb = {}
Cell._hb.SECRET_HELPFUL_CAST_FALLBACK_WINDOW = SECRET_HELPFUL_CAST_FALLBACK_WINDOW
Cell._hb.secretHelpfulCastFallbacks = secretHelpfulCastFallbacks
Cell._hb.secretHelpfulCastSkipOnPlayer = secretHelpfulCastSkipOnPlayer
Cell._hb.castExpectedBuff = castExpectedBuff
Cell._hb.recentSecretHelpfulCasts = recentSecretHelpfulCasts
Cell._hb._IsAuraFilteredOut = _IsAuraFilteredOut

local function DoesAuraMatchExpectedBuff(auraInfo, buffInfo, fallbackCastAt, maxAge, allowFullySecretTimeMatch)
    if not buffInfo then return false end

    if F.IsValueNonSecret(auraInfo.spellId) then
        if auraInfo.spellId == buffInfo.spellId then return true end
        return buffInfo.spellIds and buffInfo.spellIds[auraInfo.spellId] or false
    end

    if F.IsValueNonSecret(auraInfo.name) then
        local expectedName = buffInfo.name or F.GetSpellInfo(buffInfo.spellId)
        if expectedName and auraInfo.name == expectedName then return true end

        if buffInfo.spellIds then
            for id in pairs(buffInfo.spellIds) do
                expectedName = F.GetSpellInfo(id)
                if expectedName and auraInfo.name == expectedName then return true end
            end
        end
        return false
    end

    if not allowFullySecretTimeMatch then return false end

    return fallbackCastAt and maxAge and (GetTime() - fallbackCastAt) <= maxAge
end

local fadeOutHealthCurve
local fadeOutHealthCurve_threshold
local fadeOutHealthCurve_alpha

-- Returns the (possibly cached) curve directly, rather than relying only on the
-- shared fadeOutHealthCurve upvalue: this function is bridged into a later,
-- separate chunk via Cell_._rebuildFadeOutHealthCurve (see below), and that
-- chunk only ever imported a one-time snapshot of the plain value locals at
-- load time (nil, since no curve existed yet) -- a snapshot that never updates
-- again no matter how many times this function reassigns them here. Callers
-- everywhere should use the return value, not the bare local.
local function RebuildFadeOutHealthCurve()
    if not Cell.isMidnight or not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local threshold = CELL_FADE_OUT_HEALTH_PERCENT
    local alpha = CellDB and CellDB["appearance"] and CellDB["appearance"]["outOfRangeAlpha"] or 0.4
    if not threshold then
        fadeOutHealthCurve = nil
        fadeOutHealthCurve_threshold = nil
        fadeOutHealthCurve_alpha = nil
        return nil
    end
    if fadeOutHealthCurve and fadeOutHealthCurve_threshold == threshold and fadeOutHealthCurve_alpha == alpha then
        return fadeOutHealthCurve -- no change needed
    end
    -- EvaluateCurrentHealthPercent reads a color curve, not a plain numeric one --
    -- the alpha we actually want comes back through the resolved color's alpha
    -- channel (see UpdateInRange/UpdateHealth below).
    fadeOutHealthCurve = C_CurveUtil.CreateColorCurve()
    local fullColor = CreateColor(1, 1, 1, 1.0)
    local dimColor = CreateColor(1, 1, 1, alpha)
    fadeOutHealthCurve:AddPoint(0.0, fullColor)
    fadeOutHealthCurve:AddPoint(threshold - 0.001, fullColor)
    fadeOutHealthCurve:AddPoint(threshold, dimColor)
    fadeOutHealthCurve:AddPoint(1.0, dimColor)
    fadeOutHealthCurve_threshold = threshold
    fadeOutHealthCurve_alpha = alpha
    return fadeOutHealthCurve
end

local CheckCLEURequired

local function AnnotateAura(aura)
    if not aura then return nil end

    if not F.IsValueNonSecret(aura.auraInstanceID) then return nil end

    aura = F.CopyAuraTable(aura)

    if F.IsValueNonSecret(aura.spellId) then
        aura._hasSecrets = false
        return aura
    end

    aura._hasSecrets = true
    return aura
end

GetAuraDataByAuraInstanceID = function(unit, id)
    return AnnotateAura(_GetAuraDataByAuraInstanceID(unit, id))
end
GetAuraDataBySlot = function(unit, slot)
    return AnnotateAura(_GetAuraDataBySlot(unit, slot))
end


-------------------------------------------------
-- dispel
-------------------------------------------------
local _dispelCurvesReady = false

local _dispelHighlightCurve

local _bracketCurves = {} -- [typeName] = curve

local _dispelTypes = {
    {name = "Magic",   idx = 1,  nextIdx = 2,  r = 0.20, g = 0.60, b = 1.00},
    {name = "Curse",   idx = 2,  nextIdx = 3,  r = 0.60, g = 0.00, b = 1.00},
    {name = "Disease", idx = 3,  nextIdx = 4,  r = 0.60, g = 0.40, b = 0.00},
    {name = "Poison",  idx = 4,  nextIdx = 5,  r = 0.00, g = 0.60, b = 0.00},
    {name = "Bleed",   idx = 11, nextIdx = nil, r = 1.00, g = 0.20, b = 0.60},
}

if C_CurveUtil and C_CurveUtil.CreateColorCurve and _GetAuraDispelTypeColor
    and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
    local stepType = Enum.LuaCurveType.Step
    local transparent = CreateColor(0, 0, 0, 0)

    _dispelHighlightCurve = C_CurveUtil.CreateColorCurve()
    _dispelHighlightCurve:SetType(stepType)
    _dispelHighlightCurve:AddPoint(0, transparent)  -- None
    for _, t in ipairs(_dispelTypes) do
        _dispelHighlightCurve:AddPoint(t.idx, CreateColor(t.r, t.g, t.b, 1))
    end
    _dispelHighlightCurve:AddPoint(9, transparent)  -- Enrage

    for _, t in ipairs(_dispelTypes) do
        local curve = C_CurveUtil.CreateColorCurve()
        curve:SetType(stepType)
        curve:AddPoint(0, transparent)
        curve:AddPoint(t.idx, CreateColor(t.r, t.g, t.b, 1))
        if t.nextIdx then
            curve:AddPoint(t.nextIdx, transparent)
        end
        _bracketCurves[t.name] = curve
    end

    _dispelCurvesReady = true
end

local function _getCurveColor(unit, auraInstanceID, curve)
    if not curve then return nil end
    return _GetAuraDispelTypeColor(unit, auraInstanceID, curve)
end

local GRADIENT_TEXTURE = "Interface\\AddOns\\Cell\\Media\\gradient"
local GRADIENT_SHARP_TEXTURE = "Interface\\AddOns\\Cell\\Media\\gradient-sharp"

local function _ensureGradientOverlay(dispels, sharp)
    local key = sharp and "_secretGradientSharpOverlay" or "_secretGradientOverlay"
    if dispels[key] then return dispels[key] end

    local hlParent = dispels.highlight:GetParent()
    local tex = hlParent:CreateTexture(nil, "ARTWORK", nil, 0)
    tex:SetTexture(sharp and GRADIENT_SHARP_TEXTURE or GRADIENT_TEXTURE)
    tex:SetBlendMode("BLEND")
    tex:Hide()

    dispels[key] = tex
    return tex
end

local function _hideSecretGradientOverlays(dispels)
    if dispels._secretGradientOverlay then
        dispels._secretGradientOverlay:Hide()
    end
    if dispels._secretGradientSharpOverlay then
        dispels._secretGradientSharpOverlay:Hide()
    end
end

local _dispelTraceEnabled = false
if Cell.debug then
    function F.ToggleDispelTrace()
        _dispelTraceEnabled = not _dispelTraceEnabled
        print("|cff00ff00[Cell]|r Dispel trace:", _dispelTraceEnabled and "ON" or "OFF")
    end
    function F.PrintDispelDiag()
        print("|cff00ff00[Cell Dispel Diag]|r")
        print("  GetAuraDispelTypeColor:", _GetAuraDispelTypeColor and "exists" or "MISSING")
        print("  IsAuraFilteredOut:", _IsAuraFilteredOut and "exists" or "MISSING")
        print("  bracketCurves:", _dispelCurvesReady and "initialized" or "NOT READY")
        print("  highlightCurve:", _dispelHighlightCurve and "yes" or "NO")
        print("  InCombatLockdown:", InCombatLockdown() and "YES" or "NO")
    end
end

-------------------------------------------------
-- unit button func declarations
-----------------------------------------------------------------

-------------------------------------------------
-- unit button init indicators
-------------------------------------------------
local enabledIndicators = {}
local indicatorNums, indicatorBooleans, indicatorColors, indicatorCustoms = {}, {}, {}, {}

local function UpdateIndicatorParentVisibility(b, indicatorName, enabled)
    if not (indicatorName == "debuffs" or
            indicatorName == "privateAuras" or
            indicatorName == "defensiveCooldowns" or
            indicatorName == "offensiveCooldowns" or
            indicatorName == "externalCooldowns" or
            indicatorName == "allCooldowns" or
            indicatorName == "dispels" or
            indicatorName == "crowdControls" or
            indicatorName == "missingBuffs") then
        return
    end

    local indicator = BD(b).indicators[indicatorName]
    if indicator then
        if enabled then
            indicator:Show()
        else
            indicator:Hide()
        end
    end
end

local function ResetIndicators()
    wipe(enabledIndicators)
    wipe(indicatorNums)

    for _, t in next, Cell.vars.currentLayoutTable["indicators"] do
        -- update enabled
        if t["enabled"] then
            enabledIndicators[t["indicatorName"]] = true
        end
        -- update num
        if t["num"] then
            indicatorNums[t["indicatorName"]] = t["num"]
        end

        -- update statusIcon
        if t["indicatorName"] == "statusIcon" then
            I.EnableStatusIcon(t["enabled"])

        -- update aoehealing
        elseif t["indicatorName"] == "aoeHealing" then
            I.EnableAoEHealing(t["enabled"])

        -- update targetCounter
        elseif t["indicatorName"] == "targetCounter" then
            I.UpdateTargetCounterFilters(t["filters"], true)
            I.EnableTargetCounter(t["enabled"])

        -- update targetedSpells
        elseif t["indicatorName"] == "targetedSpells" then
            I.UpdateTargetedSpellsNum(t["num"])
            I.ShowAllTargetedSpells(t["showAllSpells"])
            if I.UpdateTargetedSpellsDisplayMode then
                I.UpdateTargetedSpellsDisplayMode(t["displayMode"] or "Both")
            end
            I.EnableTargetedSpells(t["enabled"])

        -- update actions
        elseif t["indicatorName"] == "actions" then
            I.EnableActions(t["enabled"])

        -- update missingBuffs
        elseif t["indicatorName"] == "missingBuffs" then
            I.EnableMissingBuffs(t["enabled"])

        -- update healthThresholds
        elseif t["indicatorName"] == "healthThresholds" then
            I.UpdateHealthThresholds()
        end

        -- update extra
        if t["indicatorName"] == "nameText" or t["indicatorName"] == "powerText" then
            indicatorColors[t["indicatorName"]] = t["color"]
        end
        if t["indicatorName"] == "powerText" then
            indicatorCustoms[t["indicatorName"]] = t["filters"]
        end
        if t["indicatorName"] == "dispels" then
            indicatorBooleans["dispels"] = t["filters"]
        end
        if t["dispellableByMe"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["dispellableByMe"]
        end
        if t["indicatorName"] == "debuffs" then
            indicatorBooleans["debuffsNonPlayer"] = t["nonPlayerAuras"] and true or false
        end
        if t["onlyShowTopGlow"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["onlyShowTopGlow"]
        end
        if t["hideInCombat"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["hideInCombat"]
        end
        if t["onlyEnableNotInCombat"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["onlyEnableNotInCombat"]
        end
        if t["onlyShowOvershields"] ~= nil then
            indicatorBooleans[t["indicatorName"]] = t["onlyShowOvershields"]
        end
    end
end

local function HandleIndicators(b)
    BD(b)._indicatorsReady = nil

    if BD(b)._waitingForIndicatorCreation then
        BD(b)._waitingForIndicatorCreation = nil
        I.CreateDefensiveCooldowns(b)
        I.CreateOffensiveCooldowns(b)
        I.CreateExternalCooldowns(b)
        I.CreateAllCooldowns(b)
        I.CreateDebuffs(b)
    end

    -- NOTE: Remove old
    I.RemoveAllCustomIndicators(b)

    for _, t in next, BD(b)._config do
        local indicator = BD(b).indicators[t["indicatorName"]] or I.CreateIndicator(b, t)
        indicator.configs = t

        -- update position
        if t["position"] then
            if t["indicatorName"] == "statusText" then
                indicator:SetPosition(t["position"][1], t["position"][2], t["position"][3])
            else
                P.ClearPoints(indicator)
                local relativeTo = t["position"][2] == "healthBar" and BD(b).widgets.healthBar or b
                P.Point(indicator, t["position"][1], relativeTo, t["position"][3], t["position"][4], t["position"][5])
            end
        end
        -- update anchor
        if t["anchor"] then
            indicator:SetAnchor(t["anchor"])
        end
        -- update frameLevel
        if t["frameLevel"] then
            indicator:SetFrameLevel(indicator:GetParent():GetFrameLevel()+t["frameLevel"])
        end
        -- update size
        if t["size"] then
            -- NOTE: debuffs: ["size"] = {{normalSize}, {bigSize}}
            if t["indicatorName"] == "debuffs" then
                indicator:SetSize(t["size"][1], t["size"][2])
            else
                P.Size(indicator, t["size"][1], t["size"][2])
            end
        end
        -- update thickness (+ dispel border on/off for debuffs, "off" = 0 thickness)
        if t["thickness"] then
            if t["indicatorName"] == "debuffs" then
                if indicator.SetBorder then
                    local on = t["showDispelBorder"] ~= false
                    indicator:SetBorder(on and t["thickness"] or 0)
                end
            elseif t["indicatorName"] == "dispels" then
                if indicator.SetFrameBorderThickness then
                    indicator:SetFrameBorderThickness(t["thickness"])
                    indicator:SetFrameBorderEnabled(t["showDispelFrameBorder"] == true)
                end
            else
                indicator:SetThickness(t["thickness"])
            end
        end
        -- update border
        if t["border"] and indicator.SetBorder then
            indicator:SetBorder(t["border"])
        end
        -- update height
        if t["height"] then
            P.Height(indicator, t["height"])
        end
        -- update height
        if t["textWidth"] then
            indicator:UpdateTextWidth(t["textWidth"])
        end
        -- update alpha
        if t["alpha"] then
            indicator:SetAlpha(t["alpha"])
        end
        -- update numPerLine
        if t["numPerLine"] then
            indicator:SetNumPerLine(t["numPerLine"])
        end
        -- update spacing
        if t["spacing"] then
            indicator:SetSpacing(t["spacing"])
        end
        -- update orientation
        if t["orientation"] then
            indicator:SetOrientation(t["orientation"])
        end
        -- update font
        if t["font"] then
            indicator:SetFont(unpack(t["font"]))
        end
        -- update format
        if t["format"] then
            indicator:SetFormat(t["format"])
            if t["indicatorName"] == "healthText" then
                B.UpdateHealthText(b)
            elseif t["indicatorName"] == "powerText" then
                local showFn = Cell._shouldShowPowerText or ShouldShowPowerText
                BD(b)._shouldShowPowerText = showFn and showFn(b)
                if BD(b)._shouldShowPowerText then
                    B.UpdatePowerText(b)
                else
                    indicator:Hide()
                end
            end
        end
        -- update color
        if t["color"] and t["indicatorName"] ~= "nameText" and t["indicatorName"] ~="powerText" and indicator.SetColor then
            indicator:SetColor(unpack(t["color"]))
        end
        -- update colors
        if t["colors"] then
            indicator:SetColors(t["colors"])
        end
        -- update texture
        if t["texture"] then
            indicator:SetTexture(t["texture"])
        end
        -- update dispel highlight
        if t["highlightType"] then
            indicator:UpdateHighlight(t["highlightType"])
        end
        -- update icon style
        if t["iconStyle"] then
            indicator:SetIconStyle(t["iconStyle"])
        end
        -- update animation
        if type(t["animationStyle"]) == "string" then
            local style = t["animationStyle"]
            if style == "none" then
                if indicator.ShowAnimation then
                    indicator:ShowAnimation(false)
                end
            else
                if indicator.SetCooldownStyle then
                    indicator:SetCooldownStyle(style == "clock" and "CLOCK" or "VERTICAL")
                end
                if indicator.ShowAnimation then
                    indicator:ShowAnimation(true)
                end
            end
        elseif type(t["showAnimation"]) == "boolean" and indicator.ShowAnimation then
            indicator:ShowAnimation(t["showAnimation"])
        end
        -- update duration
        if type(t["showDuration"]) == "boolean" or type(t["showDuration"]) == "number" then
            indicator:ShowDuration(t["showDuration"])
        end
        -- update stack
        if type(t["showStack"]) == "boolean" and indicator.ShowStack then
            indicator:ShowStack(t["showStack"])
        end
        -- update duration
        if t["duration"] then
            indicator:SetDuration(t["duration"])
        end
        -- update stack
        if t["stack"] then
            indicator:SetStack(t["stack"])
        end
        -- update groupNumber
        if type(t["showGroupNumber"]) == "boolean" then
            indicator:ShowGroupNumber(t["showGroupNumber"])
        end
        -- update vehicleNamePosition
        if t["vehicleNamePosition"] then
            indicator:UpdateVehicleNamePosition(t["vehicleNamePosition"])
        end
        -- update timer
        if type(t["showTimer"]) == "boolean" then
            indicator:SetShowTimer(t["showTimer"])
        end
        -- update background
        if type(t["showBackground"]) == "boolean" then
            indicator:ShowBackground(t["showBackground"])
        end
        -- update role texture
        if t["roleTexture"] then
            indicator:SetRoleTexture(t["roleTexture"])
            indicator:HideDamager(t["hideDamager"])
            UnitButton_UpdateRole(b)
        end
        -- tooltip
        if type(t["showTooltip"]) == "boolean" and indicator.ShowTooltip then
            indicator:ShowTooltip(t["showTooltip"])
        end
        -- blacklist shortcut (only Debuffs has this method)
        if type(t["enableBlacklistShortcut"]) == "boolean" and indicator.EnableBlacklistShortcut then
            indicator:EnableBlacklistShortcut(t["enableBlacklistShortcut"])
        end
        -- speed
        if t["speed"] then
            indicator:SetSpeed(t["speed"])
        end
        -- privateAuraOptions
        if t["privateAuraOptions"] then
            indicator:UpdateOptions(t["privateAuraOptions"])
        end
        -- update fadeOut
        if type(t["fadeOut"]) == "boolean" then
            indicator:SetFadeOut(t["fadeOut"])
        end
        -- update glow
        if t["glowOptions"] then
            indicator:SetupGlow(t["glowOptions"])
        end
        -- update smooth
        if type(t["smooth"]) == "boolean" then
            indicator:EnableSmooth(t["smooth"])
        end
        -- max value
        if t["maxValue"] then
            indicator:SetMaxValue(t["maxValue"])
        end
        -- update hideIfEmptyOrFull
        if type(t["hideIfEmptyOrFull"]) == "boolean" then
            indicator:SetHideIfEmptyOrFull(t["hideIfEmptyOrFull"])
        end

        -- init
        -- update name visibility
        if t["indicatorName"] == "nameText" or t["indicatorName"] == "healthText" then
            if t["enabled"] then
                indicator:Show()
            else
                indicator:Hide()
            end
        elseif t["indicatorName"] == "powerText" then
            local showFn = Cell._shouldShowPowerText or ShouldShowPowerText
            BD(b)._shouldShowPowerText = showFn and showFn(b)
            if BD(b)._shouldShowPowerText then
                B.UpdatePowerText(b)
            else
                indicator:Hide()
            end
        elseif t["indicatorName"] == "playerRaidIcon" then
            B.UpdatePlayerRaidIcon(b, t["enabled"])
        elseif t["indicatorName"] == "targetRaidIcon" then
            B.UpdateTargetRaidIcon(b, t["enabled"])
        elseif t["indicatorName"] == "readyCheckIcon" then
            B.UpdateReadyCheckIcon(b, t["enabled"])
        else
            UpdateIndicatorParentVisibility(b, t["indicatorName"], t["enabled"])
        end

        -- update pixel perfect for built-in widgets
        -- if t["type"] == "built-in" then
        --     if indicator.UpdatePixelPerfect then
        --         indicator:UpdatePixelPerfect()
        --     end
        -- end
    end

    --! update pixel perfect for widgets
    B.UpdatePixelPerfect(b, true)

    BD(b)._indicatorsReady = true
    if I.SyncHealersAuraDisplay then
        I.SyncHealersAuraDisplay(b)
    end
    if I.SyncCustomAuraDisplays then
        I.SyncCustomAuraDisplays(b)
    end
    if I.SyncCombatAuraDisplays then
        I.SyncCombatAuraDisplays(b)
    end
end

-------------------------------------------------
-- indicator update queue
-------------------------------------------------
local updater = CreateFrame("Frame")
updater:Hide()
local queue = {}

local WAITING_FOR_INIT = "WAITING_FOR_INIT"
local WAITING_FOR_UPDATE = "WAITING_FOR_UPDATE"

local function Process(b)
    if b then
        -- print("Process", GetTime(), b:GetName(), BD(b)._status)
        if BD(b)._status == WAITING_FOR_INIT then
            -- print("processing_init", GetTime(), b:GetName())
            BD(b)._status = "processing"
            HandleIndicators(b)
            UnitButton_UpdateAuras(b)
        elseif BD(b)._status == WAITING_FOR_UPDATE then
            -- print("processing_update", GetTime(), b:GetName())
            BD(b)._indicatorsReady = true
            BD(b)._status = "processing"
            UnitButton_UpdateAuras(b)
            if I.SyncHealersAuraDisplay then
                I.SyncHealersAuraDisplay(b)
            end
            if I.SyncCustomAuraDisplays then
                I.SyncCustomAuraDisplays(b)
            end
            if I.SyncCombatAuraDisplays then
                I.SyncCombatAuraDisplays(b)
            end
        end
        CellLoadingBar.current = (CellLoadingBar.current or 0) + 1
        CellLoadingBar:SetValue(CellLoadingBar.current)
        BD(b)._status = nil
        BD(b)._config = nil
        queue[b] = nil
    else
        CellLoadingBar:Hide()
        CellLoadingBar.current = 0
        updater:Hide()
    end
end

-- Time-budgeted instead of a fixed item count per tick, since HandleIndicators()
-- cost varies a lot per layout -- a fixed count either wastes frame time or
-- blows the frame budget.
updater:SetScript("OnUpdate", function()
    local deadline = debugprofilestop() + 3
    while true do
        local b = next(queue)
        if not b then
            Process(nil)
            return
        end
        Process(b)
        if debugprofilestop() > deadline then
            return
        end
    end
end)

hooksecurefunc(updater, "Show", function()
    CellLoadingBar.total = F.Getn(queue)
    CellLoadingBar.current = 0
    CellLoadingBar:SetMinMaxValues(0, CellLoadingBar.total)
    CellLoadingBar:SetValue(0)
    CellLoadingBar:Show()
end)

local function FlushQueue()
    updater:Hide()
    wipe(queue)
end

local function AddToInitQueue(b)
    BD(b)._indicatorsReady = nil
    BD(b)._status = WAITING_FOR_INIT
    BD(b)._config = Cell.vars.currentLayoutTable["indicators"]
    queue[b] = true
end

local function AddToUpdateQueue(b)
    if queue[b] then return end
    BD(b)._indicatorsReady = nil
    BD(b)._status = WAITING_FOR_UPDATE
    queue[b] = true
end

-- Bridged to the later (function(Cell)...end)(Cell) block via Cell._... below --
-- this file is split into several of those to stay under Lua's 200-local cap
-- per function, so a plain upvalue reference from UnitButton_OnShow (which
-- lives in a later block) can't reach AddToInitQueue/updater/queue here at all;
-- it would silently resolve to a global (nil) instead of erroring at load time.
local function EnsureIndicatorsReadyOnShow(b)
    -- Cell.vars.currentLayoutTable isn't set up yet during initial addon load
    -- (buttons show themselves as they're first created, well before that) --
    -- AddToInitQueue reads it unconditionally, so skip until Cell is actually
    -- loaded. Brand-new buttons are already handled separately via
    -- _waitingForIndicatorCreation once loading finishes; this is purely the
    -- later "was hidden, missed a real sweep" case.
    if not (Cell.loaded and Cell.vars.currentLayoutTable) then return end
    if BD(b)._status == nil and not BD(b)._indicatorsReady then
        AddToInitQueue(b)
        updater:Show()
    end
end

-------------------------------------------------
-- combat-enter aura resync queue
-------------------------------------------------
-- Spreads the per-button aura resync on PLAYER_REGEN_DISABLED across frames
-- instead of every button updating synchronously in the same tick.
local combatAuraQueue, combatAuraQueued = {}, setmetatable({}, { __mode = "k" })
local combatAuraPending = false

-- global: called from a later top-level block in this file
function ProcessCombatAuraQueue()
    combatAuraPending = false
    -- fixed count, not a time budget -- a time budget let more work pile
    -- into one tick than this did
    local budget = 4
    while budget > 0 and #combatAuraQueue > 0 do
        local b = tremove(combatAuraQueue)
        combatAuraQueued[b] = nil
        if b:IsShown() then
            UnitButton_UpdateAuras(b)
        end
        budget = budget - 1
    end
    if #combatAuraQueue > 0 then
        combatAuraPending = true
        C_Timer.After(0, ProcessCombatAuraQueue)
    end
end

function EnqueueCombatAuraUpdate(b)
    if combatAuraQueued[b] then return end
    combatAuraQueued[b] = true
    combatAuraQueue[#combatAuraQueue + 1] = b
    if not combatAuraPending then
        combatAuraPending = true
        C_Timer.After(0, ProcessCombatAuraQueue)
    end
end

-------------------------------------------------
-- UpdateIndicators
-------------------------------------------------
local activeLayouts = {
    solo = nil,
    party = nil,
    raid = nil,
}

local function UpdateIndicators(layout, indicatorName, setting, value, value2)
    F.Debug("|cffff7777UpdateIndicators:|r ", layout, indicatorName, setting, value, value2)

    -- FlushQueue()

    local currentLayout = Cell.vars.currentLayout
    local INDEX = Cell.vars.groupType

    if layout then
        -- Cell.Fire("UpdateIndicators", layout): indicators copy/import
        -- Cell.Fire("UpdateIndicators", xxx, ...): indicator updated
        for groupType, groupLayout in next, activeLayouts do
            if groupLayout == layout then
                activeLayouts[groupType] = nil -- update required
                F.Debug("  -> UPDATE REQUIRED:", groupType)
            end
        end

        --! indicator changed, but not current layout
        if layout ~= currentLayout then
            F.Debug("  -> NO UPDATE: not active layout")
            return
        end

    else -- Cell.Fire("UpdateIndicators")
        --! layout/groupType switched, check if update is required
        if activeLayouts[INDEX] == currentLayout then
            I.ResetCustomIndicatorTables()
            ResetIndicators()
            F.Debug("  -> NO FULL UPDATE: only reset custom indicator tables")
            F.IterateAllUnitButtons(AddToUpdateQueue, true, nil, true)
            -- Shared (NPC/spotlight) buttons only need the full init once
            -- (this is also where their first-ever init happens); after
            -- that, just the light update path like the buttons above.
            F.IterateSharedUnitButtons(function(b)
                if F.GetButtonData(b)._indicatorsReady then
                    AddToUpdateQueue(b)
                else
                    AddToInitQueue(b)
                end
            end)
            updater:Show()
            return
        end
    end

    if Cell.vars.isHidden then
        F.Debug("  -> NO UPDATE: Cell is hidden")
        I.ResetCustomIndicatorTables()
        ResetIndicators()
        return
    end

    activeLayouts[INDEX] = currentLayout

    if not indicatorName then -- init
        F.Debug("  -> FULL UPDATE", INDEX, currentLayout)
        I.ResetCustomIndicatorTables()
        ResetIndicators()
        F.IterateAllUnitButtons(AddToInitQueue, true)
        updater:Show()

    else
        -- changed in IndicatorsTab
        if setting == "enabled" then
            enabledIndicators[indicatorName] = value

            if indicatorName == "combatIcon" then
                F.IterateAllUnitButtons(function(b)
                    if not value then
                        BD(b).indicators[indicatorName]:Hide()
                    end
                end, true)
            elseif indicatorName == "aoeHealing" then
                I.EnableAoEHealing(value)
            elseif indicatorName == "targetCounter" then
                I.EnableTargetCounter(value)
            elseif indicatorName == "targetedSpells" then
                I.EnableTargetedSpells(value)
            elseif indicatorName == "actions" then
                I.EnableActions(value)
            elseif indicatorName == "roleIcon" then
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateRole(b)
                end, true)
            elseif indicatorName == "leaderIcon" then
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateLeader(b)
                end, true)
            elseif indicatorName == "playerRaidIcon" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdatePlayerRaidIcon(b, value)
                end, true)
            elseif indicatorName == "targetRaidIcon" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdateTargetRaidIcon(b, value)
                end, true)
            elseif indicatorName == "readyCheckIcon" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdateReadyCheckIcon(b, value)
                end, true)
            elseif indicatorName == "nameText" then
                F.IterateAllUnitButtons(function(b)
                    if value then
                        BD(b).indicators[indicatorName]:Show()
                    else
                        BD(b).indicators[indicatorName]:Hide()
                    end
                end, true)
            elseif indicatorName == "statusText" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdateStatusText(b)
                end, true)
            elseif indicatorName == "healthText" then
                F.IterateAllUnitButtons(function(b)
                    if value then
                        BD(b).indicators[indicatorName]:Show()
                        B.UpdateHealthText(b)
                    else
                        BD(b).indicators[indicatorName]:Hide()
                    end
                end, true)
            elseif indicatorName == "powerText" then
                -- Ensure SetFormat has been called (SetValue is noop until then).
                local fmt
                for _, t in next, Cell.vars.currentLayoutTable["indicators"] do
                    if t["indicatorName"] == "powerText" then
                        fmt = t["format"]
                        break
                    end
                end

                -- IterateAllUnitButtons doesn't reach active party header
                -- children. Use the .units sub-table which maps unit tokens
                -- to the actual visible buttons assigned by the secure header.
                local function UpdatePowerForButton(b)
                    local indicator = BD(b).indicators[indicatorName]
                    if indicator and fmt then
                        indicator:SetFormat(fmt)
                    end
                    BD(b)._shouldShowPowerText = ShouldShowPowerText(b)
                    CheckPowerEventRegistration(b)
                    if BD(b)._shouldShowPowerText then
                        B.UpdatePowerText(b)
                    else
                        if indicator then indicator:Hide() end
                    end
                end

                -- Standard iterator (covers solo, raid, pet, npc, spotlight)
                F.IterateAllUnitButtons(UpdatePowerForButton, true)

                -- Also reach active party/raid buttons via .units tables
                if Cell.unitButtons.party and Cell.unitButtons.party.units then
                    for _, b in pairs(Cell.unitButtons.party.units) do
                        UpdatePowerForButton(b)
                    end
                end
                if Cell.unitButtons.raid then
                    for header, buttons in pairs(Cell.unitButtons.raid) do
                        if type(buttons) == "table" and buttons.units then
                            for _, b in pairs(buttons.units) do
                                UpdatePowerForButton(b)
                            end
                        end
                    end
                end
            elseif indicatorName == "shieldBar" then
                F.IterateAllUnitButtons(function(b)
                    B.UpdateShield(b)
                end, true)
            elseif indicatorName == "healthThresholds" then
                if value then
                    I.UpdateHealthThresholds()
                end
                F.IterateAllUnitButtons(function(b)
                    B.UpdateHealth(b)
                end, true)
            elseif indicatorName == "missingBuffs" then
                I.EnableMissingBuffs(value)
                F.IterateAllUnitButtons(function(b)
                    UpdateIndicatorParentVisibility(b, indicatorName, value)
                end, true)
            else
                -- refresh
                F.IterateAllUnitButtons(function(b)
                    UpdateIndicatorParentVisibility(b, indicatorName, value)
                    if not value then
                        BD(b).indicators[indicatorName]:Hide() -- hide indicators which is shown right now
                        if I.DisableCombatAuraDisplay then
                            I.DisableCombatAuraDisplay(b, indicatorName)
                        end
                    end
                    UnitButton_UpdateAuras(b)
                end, true)
            end
        elseif setting == "position" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                if indicatorName == "statusText" then
                    indicator:SetPosition(value[1], value[2], value[3])
                else
                    P.ClearPoints(indicator)
                    local relativeTo = value[2] == "healthBar" and BD(b).widgets.healthBar or b
                    P.Point(indicator, value[1], relativeTo, value[3], value[4], value[5])
                end
                -- update arrangement
                if indicator.indicatorType == "icons" then
                    indicator:SetOrientation(indicator.orientation)
                end
            end, true)
        elseif setting == "anchor" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetAnchor(value)
            end, true)
        elseif setting == "frameLevel" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetFrameLevel(indicator:GetParent():GetFrameLevel()+value)
            end, true)
        elseif setting == "size" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                if indicatorName == "debuffs" then
                    indicator:SetSize(value[1], value[2])
                    -- update debuffs' normal/big icon sizes
                    UnitButton_UpdateAuras(b)
                else
                    P.Size(indicator, value[1], value[2])
                end
            end, true)
        elseif setting == "size-border" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                P.Size(indicator, value[1], value[2])
                indicator:SetBorder(value[3])
            end, true)
        elseif setting == "thickness" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                if indicatorName == "debuffs" then
                    if indicator.configs then indicator.configs.thickness = value end
                    if indicator.SetBorder then
                        local on = not (indicator.configs and indicator.configs.showDispelBorder == false)
                        indicator:SetBorder(on and value or 0)
                    end
                elseif indicatorName == "dispels" then
                    if indicator.configs then indicator.configs.thickness = value end
                    if indicator.SetFrameBorderThickness then
                        indicator:SetFrameBorderThickness(value)
                    end
                else
                    indicator:SetThickness(value)
                end
            end, true)
        elseif setting == "height" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                P.Height(indicator, value)
            end, true)
        elseif setting == "textWidth" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:UpdateTextWidth(value)
            end, true)
        elseif setting == "alpha" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetAlpha(value)
            end, true)
        elseif setting == "spacing" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetSpacing(value)
            end, true)
        elseif setting == "orientation" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetOrientation(value)
            end, true)
        elseif setting == "font" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetFont(unpack(value))
            end, true)
        elseif setting == "format" then
            if indicatorName == "healthText" then
                F.IterateAllUnitButtons(function(b)
                    local indicator = BD(b).indicators[indicatorName]
                    indicator:SetFormat(value)
                    B.UpdateHealthText(b)
                end, true)
            elseif indicatorName == "powerText" then
                F.IterateAllUnitButtons(function(b)
                    local indicator = BD(b).indicators[indicatorName]
                    indicator:SetFormat(value)
                    B.UpdatePowerText(b)
                end, true)
            end
        elseif setting == "color" then
            if indicatorName == "nameText" then
                indicatorColors[indicatorName] = value
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateNameTextColor(b)
                end, true)
            elseif indicatorName == "powerText" then
                indicatorColors[indicatorName] = value
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdatePowerTextColor(b)
                end, true)
            else
                F.IterateAllUnitButtons(function(b)
                    local indicator = BD(b).indicators[indicatorName]
                    if indicator.SetColor then
                        indicator:SetColor(unpack(value))
                    end
                end, true)
            end
        elseif setting == "colors" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetColors(value) -- update color on next SetCooldown
                UnitButton_UpdateAuras(b) -- call SetCooldown now
            end, true)
        elseif setting == "vehicleNamePosition" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:UpdateVehicleNamePosition(value)
            end, true)
        elseif setting == "statusColors" then
            F.IterateAllUnitButtons(function(b)
                UnitButton_UpdateStatusText(b)
            end, true)
        elseif setting == "num" then
            indicatorNums[indicatorName] = value
            if indicatorName == "targetedSpells" then
                I.UpdateTargetedSpellsNum(value)
            else
                -- refresh
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateAuras(b)
                end, true)
            end
        elseif setting == "numPerLine" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetNumPerLine(value)
            end, true)
        elseif setting == "roleTexture" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetRoleTexture(value)
                UnitButton_UpdateRole(b)
            end, true)
        elseif setting == "texture" then
            F.IterateAllUnitButtons(function(b)
                local indicator = BD(b).indicators[indicatorName]
                indicator:SetTexture(value)
            end, true)
        elseif setting == "duration" or setting == "dispelFilters" then
            F.IterateAllUnitButtons(function(b)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "stack" then
            F.IterateAllUnitButtons(function(b)
                BD(b).indicators[indicatorName]:SetStack(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "highlightType" then
            -- value is {highlightType, opacity} (or a bare legacy string) --
            -- Dispels_UpdateHighlight (Indicators/Built-in.lua) normalizes both.
            F.IterateAllUnitButtons(function(b)
                BD(b).indicators[indicatorName]:UpdateHighlight(value)
                UnitButton_UpdateAuras(b)
            end, true)
            if I.RebuildAllCombatAuraDisplays then
                I.RebuildAllCombatAuraDisplays()
            end
        elseif setting == "thresholds" then
            I.UpdateHealthThresholds()
            F.IterateAllUnitButtons(function(b)
                B.UpdateHealth(b)
            end, true)
        elseif setting == "showDuration" then
            F.IterateAllUnitButtons(function(b)
                BD(b).indicators[indicatorName]:ShowDuration(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "privateAuraOptions" then
            F.IterateAllUnitButtons(function(b)
                BD(b).indicators[indicatorName]:UpdateOptions(value)
            end, true)
        elseif setting == "powerTextFilters" then
            F.IterateAllUnitButtons(function(b)
                BD(b)._shouldShowPowerText = ShouldShowPowerText(b)
                CheckPowerEventRegistration(b)
                if BD(b)._shouldShowPowerText then
                    B.UpdatePowerText(b)
                else
                    BD(b).indicators[indicatorName]:Hide()
                end
            end, true)
        elseif setting == "targetCounterFilters" then
            I.UpdateTargetCounterFilters()
        elseif setting == "maxValue" then
            F.IterateAllUnitButtons(function(b)
                BD(b).indicators[indicatorName]:SetMaxValue(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "glowOptions" then
            F.IterateAllUnitButtons(function(b)
                BD(b).indicators[indicatorName]:SetupGlow(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "iconStyle" then
            F.IterateAllUnitButtons(function(b)
                BD(b).indicators[indicatorName]:SetIconStyle(value)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "animationStyle" then
            F.IterateAllUnitButtons(function(b)
                local ind = BD(b).indicators[indicatorName]
                if not ind then return end
                if value == "none" then
                    if ind.ShowAnimation then
                        ind:ShowAnimation(false)
                    end
                else
                    if ind.SetCooldownStyle then
                        ind:SetCooldownStyle(value == "clock" and "CLOCK" or "VERTICAL")
                    end
                    if ind.ShowAnimation then
                        ind:ShowAnimation(true)
                    end
                end
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "checkbutton" then
            if value == "showGroupNumber" then
                F.IterateAllUnitButtons(function(b)
                    BD(b).indicators[indicatorName]:ShowGroupNumber(value2)
                end, true)
            elseif value == "showTimer" then
                F.IterateAllUnitButtons(function(b)
                    BD(b).indicators[indicatorName]:SetShowTimer(value2)
                    UnitButton_UpdateStatusText(b)
                end, true)
            elseif value == "showBackground" then
                F.IterateAllUnitButtons(function(b)
                    BD(b).indicators[indicatorName]:ShowBackground(value2)
                end, true)
            elseif value == "hideIfEmptyOrFull" then
                if indicatorName == "powerText" then
                    F.IterateAllUnitButtons(function(b)
                        BD(b).indicators[indicatorName]:SetHideIfEmptyOrFull(value2)
                        B.UpdatePowerText(b)
                    end, true)
                end
            elseif value == "hideInCombat" then
                indicatorBooleans[indicatorName] = value2
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateLeader(b)
                end, true)
            elseif value == "onlyEnableNotInCombat" then
                indicatorBooleans[indicatorName] = value2
                F.IterateAllUnitButtons(function(b)
                    BD(b).indicators[indicatorName]:Hide()
                end, true)
            elseif value == "onlyShowOvershields" then
                indicatorBooleans[indicatorName] = value2
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateShieldAbsorbs(b)
                end, true)
            elseif value == "showStack" then
                F.IterateAllUnitButtons(function(b)
                    local ind = BD(b).indicators[indicatorName]
                    if ind and ind.ShowStack then
                        ind:ShowStack(value2)
                    end
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "showAnimation" then
                F.IterateAllUnitButtons(function(b)
                    local ind = BD(b).indicators[indicatorName]
                    if ind and ind.ShowAnimation then
                        ind:ShowAnimation(value2)
                    end
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "showDuration" then
                F.IterateAllUnitButtons(function(b)
                    local ind = BD(b).indicators[indicatorName]
                    if ind and ind.ShowDuration then
                        ind:ShowDuration(value2)
                    end
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "trackByName" then
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "dispellableByMe" then
                indicatorBooleans[indicatorName] = value2
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "nonPlayerAuras" then
                indicatorBooleans["debuffsNonPlayer"] = value2 and true or false
                F.IterateAllUnitButtons(function(b)
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "showTooltip" then
                F.IterateAllUnitButtons(function(b)
                    local ind = BD(b).indicators[indicatorName]
                    if ind and ind.ShowTooltip then
                        ind:ShowTooltip(value2)
                    end
                end, true)
                if F.RefreshEngineAuraButtonTooltips then
                    F.RefreshEngineAuraButtonTooltips()
                end
            elseif value == "enableBlacklistShortcut" then
                F.IterateAllUnitButtons(function(b)
                    BD(b).indicators[indicatorName]:EnableBlacklistShortcut(value2)
                end, true)
            elseif value == "hideDamager" then
                F.IterateAllUnitButtons(function(b)
                    BD(b).indicators[indicatorName]:HideDamager(value2)
                    UnitButton_UpdateRole(b)
                end, true)
            elseif value == "fadeOut" then
                F.IterateAllUnitButtons(function(b)
                    BD(b).indicators[indicatorName]:SetFadeOut(value2)
                    UnitButton_UpdateAuras(b)
                end, true)
            elseif value == "smooth" then
                F.IterateAllUnitButtons(function(b)
                    BD(b).indicators[indicatorName]:EnableSmooth(value2)
                end, true)
            elseif value == "showAllSpells" then
                I.ShowAllTargetedSpells(value2)
            else
                indicatorBooleans[indicatorName] = value2
            end
        elseif setting == "create" then
            I.UpdateIndicatorTable(value)
            F.IterateAllUnitButtons(function(b)
                local indicator = I.CreateIndicator(b, value)
                indicator.configs = value

                -- update position
                if value["position"] then
                    P.ClearPoints(indicator)
                    local relativeTo = value["position"][2] == "healthBar" and BD(b).widgets.healthBar or b
                    P.Point(indicator, value["position"][1], relativeTo, value["position"][3], value["position"][4], value["position"][5])
                end
                -- update anchor
                if value["anchor"] then
                    indicator:SetAnchor(value["anchor"])
                end
                -- update size
                if value["size"] then
                    P.Size(indicator, value["size"][1], value["size"][2])
                end
                -- update thickness
                if value["thickness"] then
                    indicator:SetThickness(value["thickness"])
                end
                -- update frameLevel
                if value["frameLevel"] then
                    indicator:SetFrameLevel(indicator:GetParent():GetFrameLevel()+value["frameLevel"])
                end
                -- update numPerLine
                if value["numPerLine"] then
                    indicator:SetNumPerLine(value["numPerLine"])
                end
                -- update spacing
                if value["spacing"] then
                    indicator:SetSpacing(value["spacing"])
                end
                -- update orientation
                if value["orientation"] then
                    indicator:SetOrientation(value["orientation"])
                end
                -- update font
                if value["font"] then
                    indicator:SetFont(unpack(value["font"]))
                end
                -- update color
                if value["color"] and indicator.SetColor then
                    indicator:SetColor(unpack(value["color"]))
                end
                -- update colors
                if value["colors"] then
                    indicator:SetColors(value["colors"])
                end
                -- update texture
                if value["texture"] then
                    indicator:SetTexture(value["texture"])
                end
                -- update showAnimation
                if type(value["showAnimation"]) == "boolean" and indicator.ShowAnimation then
                    indicator:ShowAnimation(value["showAnimation"])
                end
                -- update showDuration
                if type(value["showDuration"]) ~= "nil" then
                    indicator:ShowDuration(value["showDuration"])
                end
                -- update showStack
                if type(value["showStack"]) ~= "nil" and indicator.ShowStack then
                    indicator:ShowStack(value["showStack"])
                end
                -- update duration
                if value["duration"] then
                    indicator:SetDuration(value["duration"])
                end
                -- update stack
                if value["stack"] then
                    indicator:SetStack(value["stack"])
                end
                -- update fadeOut
                if type(value["fadeOut"]) == "boolean" then
                    indicator:SetFadeOut(value["fadeOut"])
                end
                -- update glow
                if value["glowOptions"] then
                    indicator:SetupGlow(value["glowOptions"])
                end
                -- FirstRun: Healers
                if value["auras"] and #value["auras"] ~= 0 then
                    UnitButton_UpdateAuras(b)
                end
            end, true)
        elseif setting == "remove" then
            F.IterateAllUnitButtons(function(b)
                I.RemoveIndicator(b, indicatorName, value)
            end, true)
        elseif setting == "auras" then
            -- indicator auras changed, hide them all, then recheck whether to show
            F.IterateAllUnitButtons(function(b)
                BD(b).indicators[indicatorName]:Hide()
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "dispelBlacklist" or setting == "defensives" or setting == "externals" or setting == "offensives" or setting == "crowdControls" or setting == "bigDebuffs" or setting == "debuffTypeColor" or setting == "castBy" then
            F.IterateAllUnitButtons(function(b)
                UnitButton_UpdateAuras(b)
            end, true)
        elseif setting == "speed" then
            -- only Actions indicator has this option for now
            F.IterateAllUnitButtons(function(b)
                BD(b).indicators[indicatorName]:SetSpeed(value)
            end, true)
        end
    end
end
Cell.RegisterCallback("UpdateIndicators", "UnitButton_UpdateIndicators", UpdateIndicators)

-------------------------------------------------
-- ForEachAura
-------------------------------------------------
local function ForEachAuraHelper(button, func, ...)
    local n = select('#', ...)
    for i = 1, n do
        local slot = select(i, ...)
        if slot then
            local auraInfo = GetAuraDataBySlot(BD(button).states.displayedUnit, slot)
            if auraInfo then
                func(button, auraInfo)
            end
        end
    end
end

local function ForEachAura(button, filter, func)
    if F.IsLiveAuraScanBlocked and F.IsLiveAuraScanBlocked() then
        return
    end
    if F.IsAuraRestricted and F.IsAuraRestricted() then
        return
    end

    local unit = BD(button).states.displayedUnit
    if not unit then return end

    if GetAuraSlots then
        local ok, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s26, s27, s28, s29, s30, s31, s32, s33, s34, s35, s36, s37, s38, s39, s40 =
            pcall(GetAuraSlots, unit, filter)
        if not ok then
            return
        end
        ForEachAuraHelper(button, func, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s26, s27, s28, s29, s30, s31, s32, s33, s34, s35, s36, s37, s38, s39, s40)
    elseif AuraUtil and AuraUtil.ForEachAura then
        pcall(AuraUtil.ForEachAura, unit, filter, nil, function(auraData)
            if auraData and auraData.auraInstanceID then
                local aura = GetAuraDataByAuraInstanceID(unit, auraData.auraInstanceID)
                if not aura then
                    aura = AnnotateAura(auraData)
                end
                if aura then
                    func(button, aura)
                end
            end
        end, true)
    end
end

-------------------------------------------------
-- ForEachAuraCache
-------------------------------------------------
local function ForEachAuraCache(button, filter, func)
    if filter == "HARMFUL" then
        for auraInstanceID, aura in next, BD(button)._debuffs_cache do
            if F.IsValueNonSecret(auraInstanceID) then
                func(button, aura)
            end
        end
    elseif filter == "HELPFUL" then
        for auraInstanceID, aura in next, BD(button)._buffs_cache do
            if F.IsValueNonSecret(auraInstanceID) then
                func(button, aura)
            end
        end
    end
end

-------------------------------------------------
-- UpdateAuraRefreshState
-------------------------------------------------
local function UpdateAuraRefreshState(auraInfo)
    if Cell.vars.iconAnimation == "duration" then
        local timeIncreased, countIncreased
        if Cell.isMidnight and (
            not F.IsValueNonSecret(auraInfo.expirationTime)
            or not F.IsValueNonSecret(auraInfo.oldExpirationTime)
            or not F.IsValueNonSecret(auraInfo.applications)
            or not F.IsValueNonSecret(auraInfo.oldApplications)
        ) then
            timeIncreased = false
            countIncreased = false
        else
            timeIncreased = auraInfo.oldExpirationTime and ((auraInfo.expirationTime or 0) - auraInfo.oldExpirationTime >= 0.5) or false
            countIncreased = auraInfo.oldApplications and (auraInfo.applications > auraInfo.oldApplications) or false
        end
        auraInfo.refreshing = timeIncreased or countIncreased
    elseif Cell.vars.iconAnimation == "stack" then
        if Cell.isMidnight and (
            not F.IsValueNonSecret(auraInfo.applications)
            or not F.IsValueNonSecret(auraInfo.oldApplications)
        ) then
            auraInfo.refreshing = false
        else
            auraInfo.refreshing = auraInfo.oldApplications and (auraInfo.applications > auraInfo.oldApplications) or false
        end
    else
        auraInfo.refreshing = false
    end

    auraInfo.oldExpirationTime = nil
    auraInfo.oldApplications = nil
end

-------------------------------------------------
-- debuffs
-------------------------------------------------
-- cleuAuras
-- local cleuUnits = {}

-- NOTE: Weakened Soul has been removed in Dragonflight
-- won't show if not a priest, otherwise show mine only
-- local function FilterWeakenedSoul(spellId, caster)
--     if spellId ~= 6788 then return true end

--     if not Cell.vars.playerClassID == 5 then return end
--     return caster == "player"
-- end

local function ResetDebuffVars(self)
    BD(self)._debuffs.resurrectionFound = false
    BD(self)._debuffs.crowdControlsFound = 0
    BD(self)._dispelAuraID = nil
    BD(self)._dispelUnit = nil

    BD(self).states.BGOrb = nil -- TODO: move to _debuffs
end

local function CanPlayerDispelAura(unit, auraInfo, debuffType)
    if Cell.isMidnight and unit and auraInfo and auraInfo.auraInstanceID and _IsAuraFilteredOut then
        local playerDispellable = not _IsAuraFilteredOut(unit, auraInfo.auraInstanceID, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        if playerDispellable then return true end

        if Cell.vars.playerClassID == 7 and debuffType == "Poison" then
            return I.CanDispel("Poison")
        end

        return false
    end

    if auraInfo and auraInfo._hasSecrets then
        return not (auraInfo.dispelName == nil)
    end

    return I.CanDispel(debuffType)
end


local function HandleDebuff(self, auraInfo)
    if not auraInfo or not F.IsValueNonSecret(auraInfo.auraInstanceID) then
        return
    end

    local auraInstanceID = auraInfo.auraInstanceID
    local unit = BD(self).states.displayedUnit

    local name = auraInfo.name
    local icon = auraInfo.icon
    local count = auraInfo.applications
    local spellId = auraInfo.spellId

    -- Blacklist check: skip auras that the user has blacklisted
    if spellId and not auraInfo._hasSecrets and F.IsAuraBlacklisted and F.IsAuraBlacklisted(spellId, "HARMFUL") then return end

    -- Dispel detection
    local isDispellable = not (auraInfo.dispelName == nil)
    local debuffType
    if auraInfo._hasSecrets then
        debuffType = ""
    else
        debuffType = auraInfo.dispelName or ""
    end

    debuffType = I.CheckDebuffType(debuffType, spellId)

    local start, duration
    if auraInfo._hasSecrets then
        start = 0
        duration = 0
    else
        local expirationTime = auraInfo.expirationTime or 0
        duration = auraInfo.duration
        start = expirationTime - duration
    end

    auraInfo.refreshing = false

    if Cell.isMidnight or (duration ~= nil) then
        UpdateAuraRefreshState(auraInfo)
        BD(self)._debuffs_cache[auraInstanceID] = auraInfo

        -- Classification
        local isBig = auraInfo._hasSecrets and _IsAuraFilteredOut and not _IsAuraFilteredOut(unit, auraInstanceID, "HARMFUL|IMPORTANT") or false

        local isBlacklisted = false
        local isDispelBlacklisted = false
        if not auraInfo._hasSecrets and spellId then
            if not isBig then
                isBig = Cell.vars.bigDebuffs[spellId] or false
            end
            -- The old array (CellDB["debuffBlacklist"]) still exists for Classic/Cata backward compat,
            -- but on Retail it would double-block spells the user already unchecked in the AuraBlacklist UI.
            if not Cell.isRetail then
                isBlacklisted = Cell.vars.debuffBlacklist[spellId] or false
            end
            isDispelBlacklisted = Cell.vars.dispelBlacklist[spellId] or false
        end

        local canPlayerDispelAura
        local function GetCanPlayerDispelAura()
            if canPlayerDispelAura == nil then
                canPlayerDispelAura = CanPlayerDispelAura(unit, auraInfo, debuffType) and true or false
            end
            return canPlayerDispelAura
        end

        if enabledIndicators["debuffs"] and not isBlacklisted
            and not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("debuffs", self)) then
            local canShowDebuff = not indicatorBooleans["debuffs"]
            if not canShowDebuff then
                canShowDebuff = GetCanPlayerDispelAura()
            end
            if canShowDebuff and indicatorBooleans["debuffsNonPlayer"] and auraInfo.isFromPlayerOrPlayerPet == true then
                canShowDebuff = false
            end
            if canShowDebuff then
                if isBig then
                    BD(self)._debuffs_big[auraInstanceID] = true
                else
                    BD(self)._debuffs_normal[auraInstanceID] = true
                end
            end
        end

        -- user created indicators
        I.UpdateCustomIndicators(self, auraInfo, "debuff")

        local isBossDebuff = F.IsKnownTrue(auraInfo.isBossAura)

        if enabledIndicators["raidDebuffs"] and isBossDebuff
            and not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("raidDebuffs", self)) then
            auraInfo.raidDebuffOrder = (not auraInfo._hasSecrets and auraInfo.expirationTime) or 0
            tinsert(BD(self)._debuffs_raid, auraInstanceID)

            if not indicatorBooleans["raidDebuffs"] then
                local glowType, glowOptions = I.GetDebuffGlow(name, spellId, count)
                if glowType and glowType ~= "None" then
                    auraInfo.raidDebuffGlowType = glowType
                    auraInfo.raidDebuffGlowOptions = glowOptions
                    BD(self)._debuffs_glow_current[glowType] = glowOptions
                end
            end
        end

        if enabledIndicators["dispels"] then
            local canShowDispel = not indicatorBooleans["dispels"]["dispellableByMe"]
            if not canShowDispel then
                canShowDispel = GetCanPlayerDispelAura()
            end

            if canShowDispel and debuffType and debuffType ~= "" then
                if indicatorBooleans["dispels"][debuffType] then
                    if isDispelBlacklisted then
                        BD(self)._debuffs_dispel[debuffType] = false
                    else
                        BD(self)._debuffs_dispel[debuffType] = true
                    end
                end
            elseif canShowDispel and auraInfo._hasSecrets and isDispellable and unit then
                BD(self)._dispelAuraID = auraInstanceID
                BD(self)._dispelUnit = unit
            end
        end

        -- crowdControls
        if enabledIndicators["crowdControls"] and I.IsCrowdControls(name, spellId) then
            if not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("crowdControls", self))
                and BD(self)._debuffs.crowdControlsFound < indicatorNums["crowdControls"] then
                BD(self)._debuffs.crowdControlsFound = BD(self)._debuffs.crowdControlsFound + 1
                if Cell.isMidnight then
                    BD(self).indicators.crowdControls[BD(self)._debuffs.crowdControlsFound]:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                else
                    BD(self).indicators.crowdControls[BD(self)._debuffs.crowdControlsFound]:SetCooldown(start, duration, debuffType, icon, count, auraInfo.refreshing)
                end
            end
            BD(self)._debuffs_big[auraInstanceID] = nil
            BD(self)._debuffs_normal[auraInstanceID] = nil
        end

        -- specific debuffs
        if not auraInfo._hasSecrets and spellId then
            if spellId == 255234 or spellId == 225080 then
                BD(self)._debuffs.resurrectionFound = true
                BD(self).states.hasRezDebuff = true
            end

            if spellId == 121164 then
                BD(self).states.BGOrb = "blue"
            elseif spellId == 121175 then
                BD(self).states.BGOrb = "purple"
            elseif spellId == 121176 then
                BD(self).states.BGOrb = "green"
            elseif spellId == 121177 then
                BD(self).states.BGOrb = "orange"
            end
        end
    end
end

local RAID_DEBUFFS_GLOW_TYPES = {"Normal", "Pixel", "Shine", "Proc"}

local function UnitButton_UpdateDebuffs(self, isFullUpdate)
    local unit = BD(self).states.displayedUnit

    ResetDebuffVars(self)
    I.ResetCustomIndicators(self, "debuff")

    if isFullUpdate then
        BD(self)._debuffs_cache = {}
        ForEachAura(self, "HARMFUL", HandleDebuff)
    else
        ForEachAuraCache(self, "HARMFUL", HandleDebuff)
    end

    if not BD(self)._debuffs.resurrectionFound then
        BD(self).states.hasRezDebuff = nil
    end

    local startIndex = 1

    -- update raid debuffs
    -- if BD(self)._debuffs.raidDebuffsFound or cleuUnits[unit] then
    if not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("raidDebuffs", self)) then
    -- "Show Highlight Debuffs on Pet Frames" (Layouts -> Pet): pet unit buttons
    -- are flagged by PetFrame.lua (self.isGroupPet).
    if BD(self)._debuffs_raid[1] and not (self.isGroupPet
        and Cell.vars.currentLayoutTable["pet"]["showRaidDebuffs"] == false) then
        BD(self).indicators.raidDebuffs:Show()

        -- cleuAuras
        -- local offset = 0
        -- if cleuUnits[unit] then
        --     offset = 1
        --     startIndex = startIndex + 1
        -- end

        -- sort indices
        sort(BD(self)._debuffs_raid, function(a, b)
            local ca, cb = BD(self)._debuffs_cache[a], BD(self)._debuffs_cache[b]
            if not ca or not cb then return ca ~= nil end
            return ca["raidDebuffOrder"] < cb["raidDebuffOrder"]
        end)

        -- show
        local topAuraInstanceID
        for i = 1, indicatorNums["raidDebuffs"] do
            local auraInstanceID = BD(self)._debuffs_raid[i]
            if auraInstanceID then
                local auraInfo = BD(self)._debuffs_cache[auraInstanceID]
                if auraInfo then
                    if Cell.isMidnight then
                        BD(self).indicators.raidDebuffs[i]:SetCooldownFromAura(
                            unit, auraInstanceID, auraInfo.icon, auraInfo.refreshing)
                        -- Dispel color: border = dispel type color (base), swipe = black
                        -- Same pattern as regular debuffs in showDebuff
                        local frame = BD(self).indicators.raidDebuffs[i]
                        if frame.cooldown and frame.cooldown.SetSwipeColor then
                            frame.cooldown:SetSwipeColor(0, 0, 0)
                        end
                        if auraInfo._hasSecrets and (auraInfo.dispelName == nil) then
                            if frame.border then frame.border:SetColorTexture(1, 0, 0); frame.border:Show() end
                        elseif auraInfo._hasSecrets and _dispelCurvesReady then
                            local hlColor = _getCurveColor(unit, auraInstanceID, _dispelHighlightCurve)
                            if hlColor then
                                local r, g, b = hlColor:GetRGBA()
                                if frame.border then frame.border:SetColorTexture(r, g, b); frame.border:Show() end
                            end
                        elseif not auraInfo._hasSecrets and auraInfo.dispelName then
                            local r, g, b = I.GetDebuffTypeColor(auraInfo.dispelName)
                            if frame.border then frame.border:SetColorTexture(r, g, b); frame.border:Show() end
                        else
                            if frame.border then frame.border:SetColorTexture(1, 0, 0); frame.border:Show() end
                        end
                    else
                        local rdStart = (auraInfo.expirationTime or 0) - auraInfo.duration
                        BD(self).indicators.raidDebuffs[i]:SetCooldown(
                            rdStart, auraInfo.duration,
                            auraInfo.dispelName or "",
                            auraInfo.icon, auraInfo.applications,
                            auraInfo.refreshing,
                            I.IsDebuffUseElapsedTime(auraInfo.name, auraInfo.spellId))
                    end
                    BD(self).indicators.raidDebuffs[i].auraInstanceID = auraInstanceID -- NOTE: for tooltip
                    startIndex = startIndex + 1
                    BD(self)._debuffs_big[auraInstanceID] = nil
                    BD(self)._debuffs_normal[auraInstanceID] = nil

                    if i == 1 then topAuraInstanceID = auraInstanceID end
                end
            end
        end

        BD(self).indicators.raidDebuffs:UpdateSize(startIndex - 1)
        for i = startIndex, 3 do
            BD(self).indicators.raidDebuffs[i].auraInstanceID = nil
        end

        -- update glow
        if not indicatorBooleans["raidDebuffs"] then
            -- to make sure top glow has highest priority
            local topAura = topAuraInstanceID and BD(self)._debuffs_cache[topAuraInstanceID]
            local topGlowType = topAura and topAura["raidDebuffGlowType"]
            local topGlowOptions = topAura and topAura["raidDebuffGlowOptions"]
            if topGlowType and topGlowType ~= "None" then
                BD(self)._debuffs_glow_current[topGlowType] = topGlowOptions
            end
            for t, o in next, BD(self)._debuffs_glow_current do
                BD(self).indicators.raidDebuffs:ShowGlow(t, o, true)
            end
            for _, t in next, RAID_DEBUFFS_GLOW_TYPES do
                if not BD(self)._debuffs_glow_current[t] then
                    BD(self).indicators.raidDebuffs:HideGlow(t)
                end
            end
            wipe(BD(self)._debuffs_glow_current)
        else
            local topAura = topAuraInstanceID and BD(self)._debuffs_cache[topAuraInstanceID]
            if topAura then
                BD(self).indicators.raidDebuffs:ShowGlow(
                    I.GetDebuffGlow(
                        topAura["name"],
                        topAura["spellId"],
                        topAura["applications"]
                    )
                )
            end
        end
    else
        BD(self).indicators.raidDebuffs:Hide()
    end
    end

    -- update debuffs
    startIndex = 1
    -- "Show Debuffs on Pet Frames" (Layouts -> Pet): pet unit buttons are flagged by
    -- PetFrame.lua (self.isGroupPet). When off, skip populating this indicator for
    -- them the same way disabling it does -- startIndex stays 1, so the UpdateSize
    -- call below hides all of the indicator's icons.
    if enabledIndicators["debuffs"] and not (self.isGroupPet
        and Cell.vars.currentLayoutTable["pet"]["showDebuffs"] == false) then
        -- helper to display a debuff indicator
        local function showDebuff(auraInstanceID, auraInfo, isBig)
            if Cell.isMidnight then
                local frame = BD(self).indicators.debuffs[startIndex]
                frame:SetCooldownFromAura(
                    unit, auraInstanceID, auraInfo.icon, auraInfo.refreshing)
                if frame.cooldown and frame.cooldown.SetSwipeColor then
                    frame.cooldown:SetSwipeColor(0, 0, 0)
                end
                local br, bg, bb = 1, 0, 0
                if auraInfo._hasSecrets and (auraInfo.dispelName == nil) then
                    br, bg, bb = 1, 0, 0
                elseif auraInfo._hasSecrets and _dispelCurvesReady then
                    local hlColor = _getCurveColor(unit, auraInstanceID, _dispelHighlightCurve)
                    if hlColor then
                        br, bg, bb = hlColor:GetRGBA()
                    end
                elseif not auraInfo._hasSecrets and auraInfo.dispelName then
                    br, bg, bb = I.GetDebuffTypeColor(auraInfo.dispelName)
                else
                    br, bg, bb = 1, 0, 0
                end
                if frame.border then
                    frame.border:SetColorTexture(br, bg, bb)
                    frame.border:Show()
                end
                local debuffs = BD(self).indicators.debuffs
                if isBig then
                    P.Size(frame, debuffs.bigSize[1], debuffs.bigSize[2])
                else
                    P.Size(frame, debuffs.normalSize[1], debuffs.normalSize[2])
                end
            else
                local dStart = (auraInfo.expirationTime or 0) - auraInfo.duration
                BD(self).indicators.debuffs[startIndex]:SetCooldown(
                    dStart, auraInfo.duration,
                    auraInfo.dispelName or "", auraInfo.icon,
                    auraInfo.applications, auraInfo.refreshing, isBig)
            end
            BD(self).indicators.debuffs[startIndex].auraInstanceID = auraInstanceID
            BD(self).indicators.debuffs[startIndex].spellId = auraInfo.spellId
            startIndex = startIndex + 1
        end

        -- bigDebuffs first
        for auraInstanceID in next, BD(self)._debuffs_big do
            local auraInfo = BD(self)._debuffs_cache[auraInstanceID]
            if auraInfo and startIndex <= indicatorNums["debuffs"] then
                showDebuff(auraInstanceID, auraInfo, true)
            elseif startIndex > indicatorNums["debuffs"] then
                break
            end
        end
        -- then normal debuffs
        for auraInstanceID in next, BD(self)._debuffs_normal do
            local auraInfo = BD(self)._debuffs_cache[auraInstanceID]
            if auraInfo and startIndex <= indicatorNums["debuffs"] then
                showDebuff(auraInstanceID, auraInfo)
            elseif startIndex > indicatorNums["debuffs"] then
                break
            end
        end
    end

    if not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("debuffs", self)) then
        BD(self).indicators.debuffs:UpdateSize(startIndex - 1)
        for i = startIndex, 10 do
            BD(self).indicators.debuffs[i].auraInstanceID = nil
            BD(self).indicators.debuffs[i].spellId = nil
        end
    end

    -- update dispels
    if (F.UnitInGroup(unit) or UnitIsFriend("player", unit))
        and not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("dispels", self)) then
        local dispels = BD(self).indicators.dispels
        if dispels._secretIconsStacked then
            dispels:SetOrientation(dispels._orientation)
            dispels._secretIconsStacked = nil
            for i = 1, 5 do
                dispels[i]:SetAlpha(1)
                dispels[i]:SetVertexColor(1, 1, 1, 1)
            end
        end
        if dispels._secretGradientShown then
            dispels._secretGradientShown = nil
            _hideSecretGradientOverlays(dispels)
        end
        dispels:SetDispels(BD(self)._debuffs_dispel)

        if BD(self)._dispelAuraID and _dispelCurvesReady
            and not dispels.highlight:IsShown()
            and not dispels._secretGradientShown
            and enabledIndicators["dispels"] then

            local sUnit = BD(self)._dispelUnit
            local sAuraID = BD(self)._dispelAuraID
            local hlColor = _getCurveColor(sUnit, sAuraID, _dispelHighlightCurve)
            if hlColor then
                local cr, cg, cb = hlColor:GetRGBA()
                local ht = dispels.highlightType
                if ht == "edge-top" or ht == "edge-bottom" or ht == "gradient-sharp" then
                    local overlay = _ensureGradientOverlay(dispels, true)
                    if ht == "edge-bottom" or ht == "gradient-sharp" then
                        overlay:SetTexture("Interface\\AddOns\\Cell\\Media\\Edge-Fade-Bottom")
                    else
                        overlay:SetTexture("Interface\\AddOns\\Cell\\Media\\Edge-Fade-Top")
                    end
                    overlay:SetTexCoord(0, 1, 0, 1)
                    overlay:ClearAllPoints()
                    overlay:SetAllPoints(dispels.highlight)
                    overlay:SetVertexColor(cr, cg, cb, 1)
                    overlay:Show()
                    dispels._secretGradientShown = true
                elseif ht ~= "none" then
                    dispels.highlight:SetTexture(Cell.vars.whiteTexture)
                    dispels.highlight:SetTexCoord(0, 1, 0, 1)
                    dispels.highlight:SetVertexColor(cr, cg, cb, dispels.highlightOpacity or 0.5)
                    dispels.highlight:Show()
                end

                if dispels.showIcons then
                    for i, t in ipairs(_dispelTypes) do
                        local dIcon = dispels[i]
                        if dIcon then
                            if dIcon.SetDispel then dIcon:SetDispel(t.name) end
                            local bColor = _getCurveColor(sUnit, sAuraID, _bracketCurves[t.name])
                            if bColor then
                                local _, _, _, ba = bColor:GetRGBA()
                                dIcon:SetAlpha(ba)
                            end
                            if i > 1 then
                                dIcon:ClearAllPoints()
                                dIcon:SetAllPoints(dispels[1])
                            end
                            dIcon:Show()
                        end
                    end
                    dispels:UpdateSize(1)
                    dispels._secretIconsStacked = true
                end
            end
        end
    end

    -- update crowdControls
    if not (I.ShouldSkipLegacyCombatAura and I.ShouldSkipLegacyCombatAura("crowdControls", self)) then
        BD(self).indicators.crowdControls:UpdateSize(BD(self)._debuffs.crowdControlsFound)
    end

    -- user created indicators
    I.ShowCustomIndicators(self, "debuff")

    if BD(self).indicators.privateAuras and BD(self).indicators.privateAuras.UpdateDispelOverlayVisibility then
        BD(self).indicators.privateAuras:UpdateDispelOverlayVisibility()
    end

    wipe(BD(self)._debuffs_normal)
    wipe(BD(self)._debuffs_big)
    wipe(BD(self)._debuffs_dispel)
    wipe(BD(self)._debuffs_raid)
end

Cell._debuffs = UnitButton_UpdateDebuffs
Cell._enabledIndicators = enabledIndicators
Cell._indicatorNums = indicatorNums
Cell._indicatorBooleans = indicatorBooleans
Cell._indicatorColors = indicatorColors
Cell._indicatorCustoms = indicatorCustoms
Cell._isAuraFilteredOut = _IsAuraFilteredOut
Cell._rebuildFadeOutHealthCurve = RebuildFadeOutHealthCurve
Cell._forEachAura = ForEachAura
Cell._forEachAuraCache = ForEachAuraCache
Cell._getAuraDataByAuraInstanceID = GetAuraDataByAuraInstanceID
Cell._annotateAura = AnnotateAura
Cell._doesAuraMatchExpectedBuff = DoesAuraMatchExpectedBuff
Cell._updateAuraRefreshState = UpdateAuraRefreshState
Cell._ensureIndicatorsReadyOnShow = EnsureIndicatorsReadyOnShow

end)(Cell)

;(function(Cell)

local Cell_ = Cell

local F = Cell_.funcs
local function BD(b) return F.GetButtonData(b) end
local I = Cell_.iFuncs
local B = Cell_.bFuncs
local A = Cell_.animations
local P = Cell_.pixelPerfectFuncs

local UnitButton_UpdateDebuffs = Cell_._debuffs
local enabledIndicators = Cell_._enabledIndicators
local indicatorNums = Cell_._indicatorNums
local indicatorBooleans = Cell_._indicatorBooleans
local indicatorColors = Cell_._indicatorColors
local indicatorCustoms = Cell_._indicatorCustoms

local _IsAuraFilteredOut = Cell_._isAuraFilteredOut
local GetAuraDataByAuraInstanceID = Cell_._getAuraDataByAuraInstanceID
local AnnotateAura = Cell_._annotateAura
local ForEachAura = Cell_._forEachAura
local ForEachAuraCache = Cell_._forEachAuraCache
local wipe = table.wipe
-- NOTE: only the function is imported here, not the plain curve/threshold/alpha
-- values -- those would just be a one-time nil snapshot from load time (see the
-- comment on RebuildFadeOutHealthCurve's definition). Always use this function's
-- return value instead.
local RebuildFadeOutHealthCurve = Cell_._rebuildFadeOutHealthCurve
local secretHelpfulCastFallbacks = Cell_._hb.secretHelpfulCastFallbacks
local recentSecretHelpfulCasts = Cell_._hb.recentSecretHelpfulCasts
local SECRET_HELPFUL_CAST_FALLBACK_WINDOW = Cell_._hb.SECRET_HELPFUL_CAST_FALLBACK_WINDOW

local SBI_ExponentialEaseOut = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local SBI_Immediate = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local UnitHealthPercent = UnitHealthPercent
local CurveConstants = CurveConstants
local LGI = LibStub:GetLibrary("LibGroupInfo")


local function GetUnitHealthPercent100(unit)
    if not (unit and UnitHealthPercent) then return nil end
    if CurveConstants and CurveConstants.ScaleTo100 then
        return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    end
    return UnitHealthPercent(unit, true)
end

local function SetStatusBarHealth(bar, value, maxValue)
    if not bar then return end
    bar:SetMinMaxValues(0, maxValue)
    local smoothEnum = (barAnimationType == "Smooth" and SBI_ExponentialEaseOut) or SBI_Immediate
    if smoothEnum then
        bar:SetValue(value, smoothEnum)
    else
        bar:SetValue(value)
    end
end

local UnitButton_UpdateHealthColor, UnitButton_UpdateHealthTextColor
local UnitButton_UpdatePowerMax, UnitButton_UpdatePower, UnitButton_UpdatePowerType, UnitButton_UpdatePowerText
local ShouldShowPowerBar

-------------------------------------------------
-- buffs
-------------------------------------------------
local function ResetBuffVars(self)
    BD(self)._buffs.defensiveFound = 0
    BD(self)._buffs.offensiveFound = 0
    BD(self)._buffs.externalFound = 0
    BD(self)._buffs.allFound = 0
    BD(self)._buffs.tankActiveMitigationFound = false
    BD(self)._buffs.drinkingFound = false

    BD(self).states.BGFlag = nil -- TODO: move to _buffs
end

local function RememberSecretHelpfulCast(self, spellId)
    if not F.IsValueNonSecret(spellId) then return end

    local kind = secretHelpfulCastFallbacks[spellId]
    if not kind then
        -- de externals/defensives de Cell por si es un spell conocido.
        if I.IsExternalCooldown(nil, spellId) then
            kind = "external"
        elseif I.IsDefensiveCooldown(nil, spellId) then
            kind = "defensive"
        elseif I.IsOffensiveCooldown and I.IsOffensiveCooldown(nil, spellId) then
            kind = "offensive"
        end
    end
    if not kind then return end

    BD(self)._recentSecretHelpfulCastKind = kind
    BD(self)._recentSecretHelpfulCastAt = GetTime()
    BD(self)._recentSecretHelpfulCastSpellId = spellId

    -- Clean expired entries before adding the new one, keeping the list bounded
    local expireCutoff = BD(self)._recentSecretHelpfulCastAt - SECRET_HELPFUL_CAST_FALLBACK_WINDOW
    for i = #recentSecretHelpfulCasts, 1, -1 do
        if recentSecretHelpfulCasts[i].castAt < expireCutoff then
            tremove(recentSecretHelpfulCasts, i)
        end
    end

    recentSecretHelpfulCasts[#recentSecretHelpfulCasts + 1] = {
        kind = kind,
        spellId = spellId,
        castAt = BD(self)._recentSecretHelpfulCastAt,
    }
end

local function GetRecentSecretHelpfulCastKind(self)
    local castAt = BD(self)._recentSecretHelpfulCastAt
    if not castAt or GetTime() - castAt > SECRET_HELPFUL_CAST_FALLBACK_WINDOW then
        local now = GetTime()
        for i = #recentSecretHelpfulCasts, 1, -1 do
            local cast = recentSecretHelpfulCasts[i]
            if now - cast.castAt > SECRET_HELPFUL_CAST_FALLBACK_WINDOW then
                tremove(recentSecretHelpfulCasts, i)
            elseif cast.kind and cast.spellId then
                return cast.kind, cast.spellId, cast.castAt
            end
        end
        return nil, nil
    end

    return BD(self)._recentSecretHelpfulCastKind, BD(self)._recentSecretHelpfulCastSpellId, BD(self)._recentSecretHelpfulCastAt
end

-- HandleBuff movida a HandleBuff.lua — el cuerpo vive allá, no acá.

local function UnitButton_UpdateBuffs(self, isFullUpdate)
    local unit = BD(self).states.displayedUnit

    ResetBuffVars(self)
    I.ResetCustomIndicators(self, "buff")

    if isFullUpdate then
        BD(self)._buffs_cache = {}
        -- (like Blessing of Freedom, Divine Protection) by tracking newly-added auras
        -- and verifying the cast spell against Cell's tables. Wiping _classified here
        -- causes those auras to lose their classification on subsequent updates since
        -- they're no longer "newly added" and can't be re-classified. Stale entries
        -- in _classified are harmless: they're only checked for auras that still exist
        -- in _buffs_cache, and removed on aura removal events.

        ForEachAura(self, "HELPFUL", Cell.HandleBuff)
    else
        ForEachAuraCache(self, "HELPFUL", Cell.HandleBuff)
    end

    local skipLegacy = I.ShouldSkipLegacyCombatAura

    -- check Mirror Image
    if BD(self)._mirror_image and I.IsDefensiveCooldown(55342) then -- exists and enabled
        if not (skipLegacy and skipLegacy("defensiveCooldowns", self))
            and BD(self)._buffs.defensiveFound < indicatorNums["defensiveCooldowns"] then
            BD(self)._buffs.defensiveFound = BD(self)._buffs.defensiveFound + 1
            BD(self).indicators.defensiveCooldowns[BD(self)._buffs.defensiveFound]:SetCooldown(BD(self)._mirror_image, 40, nil, 135994, 0)
        end
        if not (skipLegacy and skipLegacy("allCooldowns", self))
            and BD(self)._buffs.allFound < indicatorNums["allCooldowns"] then
            BD(self)._buffs.allFound = BD(self)._buffs.allFound + 1
            BD(self).indicators.allCooldowns[BD(self)._buffs.allFound]:SetCooldown(BD(self)._mirror_image, 40, nil, 135994, 0)
        end
    end

    -- check Mass Barrier (self)
    if BD(self)._mass_barrier and I.IsExternalCooldown(414660) then -- exists and enabled
        if not (skipLegacy and skipLegacy("externalCooldowns", self))
            and BD(self)._buffs.externalFound < indicatorNums["externalCooldowns"] then
            BD(self)._buffs.externalFound = BD(self)._buffs.externalFound + 1
            BD(self).indicators.externalCooldowns[BD(self)._buffs.externalFound]:SetCooldown(BD(self)._mass_barrier, 60, nil, BD(self)._mass_barrier_icon, 0)
        end
        if not (skipLegacy and skipLegacy("allCooldowns", self))
            and BD(self)._buffs.allFound < indicatorNums["allCooldowns"] then
            BD(self)._buffs.allFound = BD(self)._buffs.allFound + 1
            BD(self).indicators.allCooldowns[BD(self)._buffs.allFound]:SetCooldown(BD(self)._mass_barrier, 60, nil, BD(self)._mass_barrier_icon, 0)
        end
    end

    -- update defensiveCooldowns
    if not (skipLegacy and skipLegacy("defensiveCooldowns", self)) then
        BD(self).indicators.defensiveCooldowns:UpdateSize(BD(self)._buffs.defensiveFound)
    end

    if not (skipLegacy and skipLegacy("offensiveCooldowns", self)) then
        if BD(self).indicators.offensiveCooldowns then
            BD(self).indicators.offensiveCooldowns:UpdateSize(BD(self)._buffs.offensiveFound or 0)
        end
    end

    -- update externalCooldowns
    if not (skipLegacy and skipLegacy("externalCooldowns", self)) then
        BD(self).indicators.externalCooldowns:UpdateSize(BD(self)._buffs.externalFound)
    end

    -- update allCooldowns
    if not (skipLegacy and skipLegacy("allCooldowns", self)) then
        BD(self).indicators.allCooldowns:UpdateSize(BD(self)._buffs.allFound)
    end

    -- hide tankActiveMitigation
    if Cell.isMidnight or not BD(self)._buffs.tankActiveMitigationFound then
        BD(self).indicators.tankActiveMitigation:Hide()
    end

    -- hide drinking
    if not BD(self)._buffs.drinkingFound and BD(self).indicators.statusText:GetStatus() == "DRINKING" then
        -- BD(self).indicators.statusText:Hide()
        BD(self).indicators.statusText:SetStatus()
    end

    -- user created indicators
    I.ShowCustomIndicators(self, "buff")
end

-------------------------------------------------
-- aura tables
-------------------------------------------------
local function InitAuraTables(self)
    local d = F.GetButtonData(self)
    -- vars
    d._buffs = {}
    d._debuffs = {}

    -- for icon animation only
    d._buffs_cache = {}
    d._debuffs_cache = {}
    d._missing_auras = {}

    -- debuffs
    d._debuffs_normal = {} -- [auraInstanceID] = refreshing
    d._debuffs_big = {} -- [auraInstanceID] = refreshing
    d._debuffs_dispel = {} -- [debuffType] = true/false
    d._debuffs_raid = {} -- {id1, id2, ...}
    d._debuffs_glow_current = {}
end

local function ResetAuraTables(self)
    local d = F.GetButtonData(self)
    wipe(d._buffs_cache)
    wipe(d._debuffs_cache)
    wipe(d._missing_auras)

    -- debuffs
    wipe(d._debuffs_normal)
    wipe(d._debuffs_big)
    wipe(d._debuffs_dispel)
    wipe(d._debuffs_raid)

    -- raid debuffs glow
    wipe(d._debuffs_glow_current)
    if d.indicators and d.indicators.raidDebuffs then
        d.indicators.raidDebuffs:HideGlow()
    end

    d._mirror_image = nil
    d._mass_barrier = nil
    d._mass_barrier_icon = nil
    d._recentSecretHelpfulCastKind = nil
    d._recentSecretHelpfulCastAt = nil
    d._recentSecretHelpfulCastSpellId = nil
end

-------------------------------------------------
-- check auras using CLEU
-------------------------------------------------
local cleu = CreateFrame("Frame")

function CheckCLEURequired()
    if not CombatLogGetCurrentEventInfo then return end

    if (Cell.vars.currentLayoutTable.indicators[Cell.defaults.indicatorIndices.externalCooldowns].enabled
        or Cell.vars.currentLayoutTable.indicators[Cell.defaults.indicatorIndices.defensiveCooldowns].enabled
        or Cell.vars.currentLayoutTable.indicators[Cell.defaults.indicatorIndices.allCooldowns].enabled)
        and (I.IsDefensiveCooldown(55342) or I.IsExternalCooldown(414660)) then
        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

local function UpdateMirrorImage(b, event)
    if event == "SPELL_AURA_APPLIED" then
        BD(b)._mirror_image = GetTime()
    elseif event == "SPELL_AURA_REMOVED" then
        BD(b)._mirror_image = nil
    end
    if BD(b)._indicatorsReady then
        UnitButton_UpdateBuffs(b, false) -- should be no full update needed, indicator update is done
    end
end

local SelfBarriers = {
    [11426] = true, -- å¯'å†°æŠ¤ä½" (self)
    [235313] = true, -- çƒˆç„°æŠ¤ä½" (self)
    [235450] = true, -- æ£±å…‰æŠ¤ä½" (self)
}

local function UpdateMassBarrier(b, event)
    if event == "SPELL_CAST_SUCCESS" then
        BD(b)._mass_barrier = GetTime()
        local info = LGI:GetCachedInfo(BD(b).states.guid)
        if info then
            if info.specId == 62 then -- Arcane
                BD(b)._mass_barrier_icon = 135991
            elseif info.specId == 63 then -- Fire
                BD(b)._mass_barrier_icon = 132221
            elseif info.specId == 64 then -- Frost
                BD(b)._mass_barrier_icon = 135988
            else
                BD(b)._mass_barrier_icon = 1723997
            end
        end
    elseif event == "SPELL_AURA_REMOVED" then
        BD(b)._mass_barrier = nil
        BD(b)._mass_barrier_icon = nil
    end
    if BD(b)._indicatorsReady then
        UnitButton_UpdateBuffs(b, false) -- should be no full update needed, indicator update is done
    end
end

-- CLEU-based indicator tracking (mirror image, mass barrier).
if not Cell.isMidnight then
    cleu:SetScript("OnEvent", function()
        local _, subEvent, _, sourceGUID, _, sourceFlags, _, _, _, destFlags, _, spellId = CombatLogGetCurrentEventInfo()

        -- mirror image
        if spellId == 55342 and F.IsFriend(sourceFlags) then
            F.HandleUnitButton("guid", sourceGUID, UpdateMirrorImage, subEvent)
        end

        -- mass barrier (self), SPELL_CAST_SUCCESS
        if spellId == 414660 and F.IsFriend(sourceFlags) then
            F.HandleUnitButton("guid", sourceGUID, UpdateMassBarrier, "SPELL_CAST_SUCCESS")
        end
        if (subEvent == "SPELL_AURA_REMOVED" or subEvent == "SPELL_AURA_REFRESH") and SelfBarriers[spellId] and F.IsFriend(sourceFlags) then
            F.HandleUnitButton("guid", sourceGUID, UpdateMassBarrier, "SPELL_AURA_REMOVED")
        end
    end)
end

-------------------------------------------------
-- functions
-------------------------------------------------
local function GetTrackedSpells()
    local spells = {}
    -- Externals
    if Cell.vars.builtInExternals then
        for id, _ in pairs(Cell.vars.builtInExternals) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    if Cell.vars.customExternals then
        for id, _ in pairs(Cell.vars.customExternals) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    -- Defensives
    if Cell.vars.builtInDefensives then
        for id, _ in pairs(Cell.vars.builtInDefensives) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    if Cell.vars.customDefensives then
        for id, _ in pairs(Cell.vars.customDefensives) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    -- Offensives
    if Cell.vars.builtInOffensives then
        for id, _ in pairs(Cell.vars.builtInOffensives) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    if Cell.vars.customOffensives then
        for id, _ in pairs(Cell.vars.customOffensives) do
            if type(id) == "number" then spells[id] = "HELPFUL" end
        end
    end
    -- Custom indicators
    if Cell.snippetVars and Cell.snippetVars.customIndicators then
        for auraType, indicators in pairs(Cell.snippetVars.customIndicators) do
            local filter = auraType == "buff" and "HELPFUL" or "HARMFUL"
            for _, indicatorTable in pairs(indicators) do
                if indicatorTable._auras then
                    for _, id in pairs(indicatorTable._auras) do
                        spells[id] = filter
                    end
                end
            end
        end
    end
    -- Layout indicators (including Healers and default class indicators)
    if Cell.vars.currentLayoutTable and Cell.vars.currentLayoutTable["indicators"] then
        for _, t in ipairs(Cell.vars.currentLayoutTable["indicators"]) do
            if t["auras"] then
                local filter = t["auraType"] == "buff" and "HELPFUL" or "HARMFUL"
                for _, id in pairs(t["auras"]) do
                    if type(id) == "number" then
                        spells[id] = filter
                    end
                end
            end
        end
    end
    return spells
end

local function ShouldDeferUnitAura(unit)
    return unit and (UnitIsUnit(unit, "player") or UnitIsUnit(unit, "target"))
end

UnitButton_UpdateAuras = function(self, updateInfo)
    if not BD(self)._indicatorsReady then return end

    local unit = BD(self).states.displayedUnit
    if not unit then return end

    if F.IsLiveAuraScanBlocked and F.IsLiveAuraScanBlocked() then
        return
    end

    if F.IsAuraRestricted and F.IsAuraRestricted() then
        if I.UpdateHealersAuraDisplayUnit then
            I.UpdateHealersAuraDisplayUnit(self)
        end
        if I.UpdateCustomAuraDisplays then
            I.UpdateCustomAuraDisplays(self)
        end
        if I.UpdateCombatAuraDisplays then
            I.UpdateCombatAuraDisplays(self)
        end
        return
    end

    local isFullUpdate = true
    if updateInfo then
        local full = updateInfo.isFullUpdate
        if F.IsValueNonSecret(full) then
            isFullUpdate = full and true or false
        end
    end

    if isFullUpdate then
        -- full update
        UnitButton_UpdateBuffs(self, true)
        UnitButton_UpdateDebuffs(self, true)
    else
        local buffsChanged, debuffsChanged
        local needsFullUpdate
        wipe(BD(self)._missing_auras)

        if updateInfo.addedAuras then
            for _, rawAura in next, updateInfo.addedAuras do
                local auraInstanceID = rawAura and rawAura.auraInstanceID
                local aura = auraInstanceID and AnnotateAura(_GetAuraDataByAuraInstanceID(unit, auraInstanceID))
                if aura then
                    local isHelpful, isHarmful
                    if aura._hasSecrets then
                        if _IsAuraFilteredOut then
                            isHelpful = not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HELPFUL") and true or nil
                            isHarmful = (not isHelpful and not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HARMFUL")) and true or nil
                        end
                        if not isHelpful and not isHarmful and F.IsValueNonSecret(aura.spellId) then
                            if I.IsExternalCooldown(nil, aura.spellId) or I.IsDefensiveCooldown(nil, aura.spellId) then
                                isHelpful = true
                            end
                        end
                    else
                        isHelpful, isHarmful = aura.isHelpful, aura.isHarmful
                        if not isHelpful and not isHarmful and _IsAuraFilteredOut then
                            isHelpful = not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HELPFUL") and true or nil
                            isHarmful = (not isHelpful and not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HARMFUL")) and true or nil
                        end
                    end
                    if aura._hasSecrets then
                        if not BD(self)._recentlyAddedAuraIDs then BD(self)._recentlyAddedAuraIDs = {} end
                        BD(self)._recentlyAddedAuraIDs[aura.auraInstanceID] = true
                    end
                    if not isHelpful and not isHarmful then
                        needsFullUpdate = true
                    elseif isHelpful then
                        buffsChanged = true
                        BD(self)._buffs_cache[aura.auraInstanceID] = aura
                    else
                        debuffsChanged = true
                        BD(self)._debuffs_cache[aura.auraInstanceID] = aura
                    end
                end
            end
        end

        if not needsFullUpdate and updateInfo.updatedAuraInstanceIDs then
            local aura
            for _, auraInstanceID in next, updateInfo.updatedAuraInstanceIDs do
                if BD(self)._buffs_cache[auraInstanceID] then
                    buffsChanged = true
                    aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if aura then
                        if not aura._hasSecrets then
                            local cachedExp = BD(self)._buffs_cache[auraInstanceID].expirationTime
                            local cachedApp = BD(self)._buffs_cache[auraInstanceID].applications
                            aura.oldExpirationTime = (cachedExp and F.IsValueNonSecret(cachedExp)) and cachedExp or 0
                            aura.oldApplications = (cachedApp and F.IsValueNonSecret(cachedApp)) and cachedApp or nil
                        end
                        BD(self)._buffs_cache[auraInstanceID] = aura
                    end
                elseif BD(self)._debuffs_cache[auraInstanceID] then
                    debuffsChanged = true
                    aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if aura then
                        if not aura._hasSecrets then
                            local cachedExp = BD(self)._debuffs_cache[auraInstanceID].expirationTime
                            local cachedApp = BD(self)._debuffs_cache[auraInstanceID].applications
                            aura.oldExpirationTime = (cachedExp and F.IsValueNonSecret(cachedExp)) and cachedExp or 0
                            aura.oldApplications = (cachedApp and F.IsValueNonSecret(cachedApp)) and cachedApp or nil
                        end
                        BD(self)._debuffs_cache[auraInstanceID] = aura
                    end
                else
                    aura = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if aura then
                        BD(self)._missing_auras[auraInstanceID] = aura
                    end
                end
            end
        end

        if not needsFullUpdate and updateInfo.removedAuraInstanceIDs then
            for _, auraInstanceID in next, updateInfo.removedAuraInstanceIDs do
                if BD(self)._buffs_cache[auraInstanceID] then
                    BD(self)._buffs_cache[auraInstanceID] = nil
                    if BD(self)._buffs._classified then BD(self)._buffs._classified[auraInstanceID] = nil end
                    buffsChanged = true
                elseif BD(self)._debuffs_cache[auraInstanceID] then
                    BD(self)._debuffs_cache[auraInstanceID] = nil
                    debuffsChanged = true
                else
                    BD(self)._missing_auras[auraInstanceID] = nil
                end
            end
        end

        if not needsFullUpdate and next(BD(self)._missing_auras) then
            for _, aura in next, BD(self)._missing_auras do
                if aura then
                    local isHelpful, isHarmful
                    if aura._hasSecrets then
                        if _IsAuraFilteredOut then
                            isHarmful = not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HARMFUL") and true or nil
                            isHelpful = (not isHarmful and not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HELPFUL")) and true or nil
                        end
                    else
                        isHelpful, isHarmful = aura.isHelpful, aura.isHarmful
                        if not isHelpful and not isHarmful and _IsAuraFilteredOut then
                            isHarmful = not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HARMFUL") and true or nil
                            isHelpful = (not isHarmful and not _IsAuraFilteredOut(unit, aura.auraInstanceID, "HELPFUL")) and true or nil
                        end
                    end
                    if isHelpful then
                        buffsChanged = true
                        BD(self)._buffs_cache[aura.auraInstanceID] = aura
                    elseif isHarmful then
                        debuffsChanged = true
                        BD(self)._debuffs_cache[aura.auraInstanceID] = aura
                    end
                end
            end
        end

        if needsFullUpdate then
            UnitButton_UpdateBuffs(self, true)
            UnitButton_UpdateDebuffs(self, true)
        else
            if buffsChanged then UnitButton_UpdateBuffs(self) end
            if debuffsChanged then UnitButton_UpdateDebuffs(self) end
        end
        if BD(self)._recentlyAddedAuraIDs then
            wipe(BD(self)._recentlyAddedAuraIDs)
        end
    end

    I.UpdateStatusIcon(self)
end

local function UnitButton_UpdateCalculator(self)
    local unit = BD(self).states.displayedUnit
    if not unit then return end
    local calc = BD(self).widgets.healthCalculator
    if not calc then return end
    if calc.SetDamageAbsorbClampMode then
        calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
    end
    if calc.SetHealAbsorbClampMode then
        calc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.MaximumHealth)
    end
    if UnitExists(unit) then
        UnitGetDetailedHealPrediction(unit, nil, calc)
    end
    if calc.SetMaximumHealthMode then
        calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
    end
end

local function UnitButton_UpdateHealthStates(self, diff)
    local unit = BD(self).states.displayedUnit

    if Cell.isMidnight and BD(self).widgets.healthCalculator then
        UnitButton_UpdateCalculator(self)
        -- Store healthPercent for color logic.
        local health = UnitHealth(unit)
        local healthMax = UnitHealthMax(unit)
        if not F.HasAnySecretValues(health, healthMax) and healthMax > 0 then
            BD(self).states.healthPercent = health / healthMax
            BD(self).states.healthMax = healthMax
        else
            -- class_color / class_color_dark modes don't use percent, so they still work.
            BD(self).states.healthPercent = 0
        end
        BD(self).states.wasDead = BD(self).states.isDead
        BD(self).states.wasDeadOrGhost = BD(self).states.isDeadOrGhost
        local dead = UnitIsDeadOrGhost(unit)
        if F.IsValueNonSecret(dead) then
            BD(self).states.isDead = dead
            BD(self).states.isDeadOrGhost = dead
        end

        if enabledIndicators["healthText"] then
            local calc = BD(self).widgets.healthCalculator
            local health = calc:GetCurrentHealth()
            local maxHealth = calc:GetMaximumHealth()
            local totalAbsorbs = calc:GetDamageAbsorbs()
            local healAbsorbs = calc:GetHealAbsorbs()
            -- use direct UnitHealth/UnitHealthMax for health text display.
            if F.IsValueNonSecret(maxHealth) and maxHealth == 0 and unit then
                health = UnitHealth(unit)
                maxHealth = UnitHealthMax(unit)
                totalAbsorbs = UnitGetTotalAbsorbs(unit) or 0
                healAbsorbs = UnitGetTotalHealAbsorbs(unit) or 0
            end
            BD(self).indicators.healthText:SetValue(health, maxHealth, totalAbsorbs, healAbsorbs, unit)
            BD(self).indicators.healthText:Show()
        else
            BD(self).indicators.healthText:Hide()
        end

        -- Fire death-state change callbacks
        if BD(self).states.wasDead ~= BD(self).states.isDead then
            UnitButton_UpdateStatusText(self)
            I.UpdateStatusIcon_Resurrection(self)
            if not BD(self).states.isDead then
                BD(self).states.hasSoulstone = nil
                I.UpdateStatusIcon(self)
            end
        end
        if BD(self).states.wasDeadOrGhost ~= BD(self).states.isDeadOrGhost then
            I.UpdateStatusIcon_Resurrection(self)
            UnitButton_UpdateHealthColor(self)
        end
    else
        local health = UnitHealth(unit) + (diff or 0)
        local healthMax = UnitHealthMax(unit)
        health = min(health, healthMax) --! diff

        BD(self).states.health = health
        BD(self).states.healthMax = healthMax
        BD(self).states.totalAbsorbs = UnitGetTotalAbsorbs(unit)
        BD(self).states.healAbsorbs = UnitGetTotalHealAbsorbs(unit)

        if healthMax == 0 then
            BD(self).states.healthPercent = 0
        else
            BD(self).states.healthPercent = health / healthMax
        end

        BD(self).states.wasDead = BD(self).states.isDead
        BD(self).states.isDead = health == 0
        if BD(self).states.wasDead ~= BD(self).states.isDead then
            UnitButton_UpdateStatusText(self)
            I.UpdateStatusIcon_Resurrection(self)
            if not BD(self).states.isDead then
                BD(self).states.hasSoulstone = nil
                I.UpdateStatusIcon(self)
            end
        end

        BD(self).states.wasDeadOrGhost = BD(self).states.isDeadOrGhost
        BD(self).states.isDeadOrGhost = UnitIsDeadOrGhost(unit)
        if BD(self).states.wasDeadOrGhost ~= BD(self).states.isDeadOrGhost then
            I.UpdateStatusIcon_Resurrection(self)
            UnitButton_UpdateHealthColor(self)
        end

        if enabledIndicators["healthText"] then -- and not BD(self).states.isDeadOrGhost then
            BD(self).indicators.healthText:SetValue(health, healthMax, BD(self).states.totalAbsorbs, BD(self).states.healAbsorbs, unit)
            BD(self).indicators.healthText:Show()
        else
            BD(self).indicators.healthText:Hide()
        end
    end
end

local function UnitButton_UpdatePowerStates(self)
    local unit = BD(self).states.displayedUnit
    if not unit then return end

    BD(self).states.power = UnitPower(unit)
    BD(self).states.powerMax = UnitPowerMax(unit)
    if F.IsValueNonSecret(BD(self).states.powerMax) then
        if BD(self).states.powerMax <= 0 then BD(self).states.powerMax = 1 end
    end
end

-------------------------------------------------
-- power filter funcs
-------------------------------------------------
local function GetRole(b)
    if BD(b).states.role and F.IsValueNonSecret(BD(b).states.role) and BD(b).states.role ~= "NONE" then
        return BD(b).states.role
    end

    local isPlayer = BD(b).states.unit and UnitIsUnit(BD(b).states.unit, "player")
    if GetSpecialization and GetSpecializationRole
        and BD(b).states.unit and F.IsValueNonSecret(isPlayer) and isPlayer then
        local spec = GetSpecialization()
        if spec then
            local specRole = GetSpecializationRole(spec)
            if specRole and F.IsValueNonSecret(specRole) and specRole ~= "NONE" then
                return specRole
            end
        end
    end

    if BD(b).states.unit then
        local freshRole = UnitGroupRolesAssigned(BD(b).states.unit)
        if freshRole and F.IsValueNonSecret(freshRole) and freshRole ~= "NONE" then
            BD(b).states.role = freshRole
            return freshRole
        end
    end

    local info
    if BD(b).states.guid and F.IsValueNonSecret(BD(b).states.guid) then
        info = LGI:GetCachedInfo(BD(b).states.guid)
    end
    if info and F.IsValueNonSecret(info.role) then
        return info.role
    end
end

local function EvaluateFilterWithoutRole(filterTable)
    if type(filterTable) == "boolean" then
        return filterTable
    end
    for _, enabled in pairs(filterTable) do
        if enabled then
            return true
        end
    end
    -- All roles disabled for this class → hide
    return false
end

-- Determine class and role for a unit button (used by power filter functions)
local function GetClassAndRole(b)
    local class, role
    local guid = BD(b).states.guid
    if guid and not F.IsValueNonSecret(guid) then
        if BD(b).states.class and F.IsValueNonSecret(BD(b).states.class) then
            class = BD(b).states.class
            role = GetRole(b)
        elseif BD(b).states.unit and UnitInPartyIsAI(BD(b).states.unit) then
            class = BD(b).states.class
            role = GetRole(b)
        end
        return class, role
    end
    if BD(b).states.inVehicle then
        class = "VEHICLE"
    elseif F.IsPlayer(guid) then
        class = BD(b).states.class
        role = GetRole(b)
    elseif F.IsPet(guid) then
        class = "PET"
    elseif F.IsNPC(guid) then
        if UnitInPartyIsAI(BD(b).states.unit) then
            class = BD(b).states.class
            role = GetRole(b)
        else
            class = "NPC"
        end
    elseif F.IsVehicle(guid) then
        class = "VEHICLE"
    end
    return class, role
end

ShouldShowPowerText = function(b)
    if not enabledIndicators["powerText"] then return end
    if not (b:IsVisible() or BD(b).isPreview) then return end

    if BD(b).states.guid == nil then
        return true
    end

    local class, role = GetClassAndRole(b)
    if not (class and F.IsValueNonSecret(class)) then
        return true
    end

    local filter = indicatorCustoms["powerText"] and indicatorCustoms["powerText"][class]
    if filter == nil then
        return true
    elseif type(filter) == "boolean" then
        return filter
    elseif role and F.IsValueNonSecret(role) then
        return filter[role]
    else
        return EvaluateFilterWithoutRole(filter)
    end
end

ShouldShowPowerBar = function(b)
    if not (b:IsVisible() or BD(b).isPreview) then return end
    if not BD(b).powerSize or BD(b).powerSize == 0 then return end

    if BD(b).states.guid == nil then
        return true
    end

    local class, role = GetClassAndRole(b)

    if class and F.IsValueNonSecret(class) and Cell.vars.currentLayoutTable then
        local filter = Cell.vars.currentLayoutTable["powerFilters"] and Cell.vars.currentLayoutTable["powerFilters"][class]
        if filter == nil then
            return true
        elseif type(filter) == "boolean" then
            return filter
        else
            if role and F.IsValueNonSecret(role) then
                return filter[role]
            else
                return EvaluateFilterWithoutRole(filter)
            end
        end
    end

    return true
end

CheckPowerEventRegistration = function(b)
    local want = b:IsVisible() and not BD(b).isPreview and (BD(b)._shouldShowPowerText or BD(b)._shouldShowPowerBar)
    if useEventHub then
        BD(b)._wantPowerEvents = want and true or false
        SyncButtonTracker(b)
        return want
    end
    if want then
        b:RegisterEvent("UNIT_POWER_FREQUENT")
        b:RegisterEvent("UNIT_MAXPOWER")
        b:RegisterEvent("UNIT_DISPLAYPOWER")
        return true
    else
        b:UnregisterEvent("UNIT_POWER_FREQUENT")
        b:UnregisterEvent("UNIT_MAXPOWER")
        b:UnregisterEvent("UNIT_DISPLAYPOWER")
        return false
    end
end

local function ShowPowerBar(b)
    BD(b).widgets.powerBar:Show()
    BD(b).widgets.powerBarLoss:Show()
    BD(b).widgets.gapTexture:SetShown(CELL_BORDER_SIZE ~= 0)

    P.ClearPoints(BD(b).widgets.healthBar)
    P.ClearPoints(BD(b).widgets.powerBar)
    if BD(b).orientation == "horizontal" or BD(b).orientation == "vertical_health" then
        P.Point(BD(b).widgets.healthBar, "TOPLEFT", b, "TOPLEFT", CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
        P.Point(BD(b).widgets.healthBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -CELL_BORDER_SIZE, BD(b).powerSize + CELL_BORDER_SIZE * 2)
        P.Point(BD(b).widgets.powerBar, "TOPLEFT", BD(b).widgets.healthBar, "BOTTOMLEFT", 0, -CELL_BORDER_SIZE)
        P.Point(BD(b).widgets.powerBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -CELL_BORDER_SIZE, CELL_BORDER_SIZE)
    else
        P.Point(BD(b).widgets.healthBar, "TOPLEFT", b, "TOPLEFT", CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
        P.Point(BD(b).widgets.healthBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -(BD(b).powerSize + CELL_BORDER_SIZE * 2), CELL_BORDER_SIZE)
        P.Point(BD(b).widgets.powerBar, "TOPLEFT", BD(b).widgets.healthBar, "TOPRIGHT", CELL_BORDER_SIZE, 0)
        P.Point(BD(b).widgets.powerBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -CELL_BORDER_SIZE, CELL_BORDER_SIZE)
    end

    if b:IsVisible() then
        -- update now
        CheckPowerEventRegistration(b)
        UnitButton_UpdatePowerStates(b)
        UnitButton_UpdatePowerType(b)
        UnitButton_UpdatePowerMax(b)
        UnitButton_UpdatePower(b)
    end
end

local function HidePowerBar(b)
    CheckPowerEventRegistration(b)
    BD(b).widgets.powerBar:Hide()
    BD(b).widgets.powerBarLoss:Hide()
    BD(b).widgets.gapTexture:Hide()

    P.ClearPoints(BD(b).widgets.healthBar)
    P.Point(BD(b).widgets.healthBar, "TOPLEFT", b, "TOPLEFT", CELL_BORDER_SIZE, -CELL_BORDER_SIZE)
    P.Point(BD(b).widgets.healthBar, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -CELL_BORDER_SIZE, CELL_BORDER_SIZE)
end

-------------------------------------------------
-- unit button functions
-------------------------------------------------
local function UnitButton_UpdateTarget(self)
    local unit = BD(self).states.displayedUnit
    if not unit then return end

    if F.IsKnownTrue(UnitIsUnit(unit, "target")) then
        if highlightEnabled then BD(self).widgets.targetHighlight:Show() end
    else
        BD(self).widgets.targetHighlight:Hide()
    end
end


local function CheckVehicleRoot(self, petUnit)
    if not petUnit then return end

    local playerUnit = F.GetPlayerUnit(petUnit)

    local isRoot
    for i = 1, UnitVehicleSeatCount(playerUnit) do
        local controlType, occupantName, serverName, ejectable, canSwitchSeats = UnitVehicleSeatInfo(playerUnit, i)
        local pName = UnitName(playerUnit)
        if F.IsValueNonSecret(pName) and pName == occupantName then
            isRoot = controlType == "Root"
            break
        end
    end

    BD(self).indicators.roleIcon:SetRole(isRoot and "VEHICLE-ROOT" or "VEHICLE")
end

UnitButton_UpdateRole = function(self)
    local unit = BD(self).states.unit
    if not unit then return end

    local role = UnitGroupRolesAssigned(unit)
    if F.IsValueNonSecret(role) then
        BD(self).states.role = role
    end

    local roleIcon = BD(self).indicators.roleIcon
    if enabledIndicators["roleIcon"] then

        roleIcon:SetRole(role)

        --! check vehicle root
        if BD(self).states.guid and F.IsValueNonSecret(BD(self).states.guid) and strfind(BD(self).states.guid, "^Vehicle") and not F.IsKnownTrue(UnitInPartyIsAI(unit)) then
            CheckVehicleRoot(self, unit)
        end
    else
        roleIcon:Hide()
    end
end

UnitButton_UpdateLeader = function(self, event)
    local unit = BD(self).states.unit
    if not unit then return end

    local leaderIcon = BD(self).indicators.leaderIcon

    if enabledIndicators["leaderIcon"] then
        if indicatorBooleans["leaderIcon"] and (InCombatLockdown() or event == "PLAYER_REGEN_DISABLED") then
            leaderIcon:Hide()
            return
        end

        local isLeader = UnitIsGroupLeader(unit)
        BD(self).states.isLeader = isLeader
        local isAssistant = UnitIsGroupAssistant(unit) and IsInRaid()
        BD(self).states.isAssistant = isAssistant

        leaderIcon:SetIcon(isLeader, isAssistant)
    else
        leaderIcon:Hide()
    end
end

local function UnitButton_UpdatePlayerRaidIcon(self)
    local unit = BD(self).states.displayedUnit
    if not unit then return end

    local playerRaidIcon = BD(self).indicators.playerRaidIcon

    local index = GetRaidTargetIndex(unit)

    if enabledIndicators["playerRaidIcon"] then
        if index then
            SetRaidTargetIconTexture(playerRaidIcon.tex, index)
            playerRaidIcon:Show()
        else
            playerRaidIcon:Hide()
        end
    else
        playerRaidIcon:Hide()
    end
end

local function UnitButton_UpdateTargetRaidIcon(self)
    local unit = BD(self).states.displayedUnit
    if not unit then return end

    local targetRaidIcon = BD(self).indicators.targetRaidIcon

    local index = GetRaidTargetIndex(unit.."target")

    if enabledIndicators["targetRaidIcon"] then
        if index then
            SetRaidTargetIconTexture(targetRaidIcon.tex, index)
            targetRaidIcon:Show()
        else
            targetRaidIcon:Hide()
        end
    else
        targetRaidIcon:Hide()
    end
end

local function UnitButton_UpdateReadyCheck(self)
    local unit = BD(self).states.unit
    if not unit then return end

    local status = GetReadyCheckStatus(unit)
    BD(self).states.readyCheckStatus = status

    if enabledIndicators["readyCheckIcon"] and status then
        -- BD(self).widgets.readyCheckHighlight:SetVertexColor(unpack(READYCHECK_STATUS[status].c))
        -- BD(self).widgets.readyCheckHighlight:Show()
        BD(self).indicators.readyCheckIcon:SetStatus(status)
    else
        -- BD(self).widgets.readyCheckHighlight:Hide()
        BD(self).indicators.readyCheckIcon:Hide()
    end
end

local function UnitButton_FinishReadyCheck(self)
    if not enabledIndicators["readyCheckIcon"] then return end

    if BD(self).states.readyCheckStatus == "waiting" then
        -- BD(self).widgets.readyCheckHighlight:SetVertexColor(unpack(READYCHECK_STATUS.notready.c))
        BD(self).indicators.readyCheckIcon:SetStatus("notready")
    end
    C_Timer.After(6, function()
        -- BD(self).widgets.readyCheckHighlight:Hide()
        BD(self).indicators.readyCheckIcon:Hide()
    end)
end

local function FitPowerTextFrame(frame)
    local w = frame.text and frame.text:GetStringWidth()
    frame:SetWidth((F.IsValueNonSecret(w) and w > 0) and w or 50)
end

UnitButton_UpdatePowerText = function(self)
    if not BD(self)._shouldShowPowerText then return end

    local frame = BD(self).indicators.powerText
    if not frame then return end

    local power = BD(self).states.power
    local powerMax = BD(self).states.powerMax
    local dead = BD(self).states.isDeadOrGhost
    if power == nil or (F.IsValueNonSecret(dead) and dead) then
        frame:Hide()
        return
    end

    local unit = BD(self).states.displayedUnit
    local fmt = frame._format or "number"
    if not F.HasAnySecretValues(power, powerMax) then
        frame:SetValue(power, powerMax)
    elseif fmt == "percentage" then
        local pct
        if unit and UnitPowerPercent then
            if CurveConstants and CurveConstants.ScaleTo100 then
                pct = UnitPowerPercent(unit, nil, true, CurveConstants.ScaleTo100)
            else
                pct = UnitPowerPercent(unit)
            end
        end
        if pct ~= nil then
            frame.text:SetFormattedText("%d%%", pct)
        else
            frame.text:SetFormattedText("%d", power)
        end
    elseif fmt == "number-short" and AbbreviateNumbers then
        frame.text:SetFormattedText("%s", AbbreviateNumbers(power))
    else
        frame.text:SetFormattedText("%d", power)
    end
    FitPowerTextFrame(frame)
    frame:Show()
end

UnitButton_UpdatePowerTextColor = function(self)
    if not BD(self)._shouldShowPowerText then return end

    local unit = BD(self).states.displayedUnit
    if not unit then return end

    local color = indicatorColors["powerText"]
    if not color then return end

    if color[1] == "power_color" then
        BD(self).indicators.powerText:SetColor(F.GetPowerColor(unit))
    elseif color[1] == "class_color" then
        BD(self).indicators.powerText:SetColor(F.GetUnitClassColor(unit))
    elseif color[2] then
        BD(self).indicators.powerText:SetColor(unpack(color[2]))
    end
end

UnitButton_UpdatePowerMax = function(self)
    if not BD(self)._shouldShowPowerBar then return end
    if BD(self).states.powerMax == nil then return end

    if barAnimationType == "Smooth" and not Cell.isMidnight then
        BD(self).widgets.powerBar:SetMinMaxSmoothedValue(0, BD(self).states.powerMax)
    else
        BD(self).widgets.powerBar:SetMinMaxValues(0, BD(self).states.powerMax)
    end
end

UnitButton_UpdatePower = function(self)
    if not BD(self)._shouldShowPowerBar then return end
    if BD(self).states.power == nil then return end

    if Cell.isMidnight and SBI_ExponentialEaseOut then
        local smoothEnum = (barAnimationType == "Smooth" and SBI_ExponentialEaseOut) or SBI_Immediate
        BD(self).widgets.powerBar:SetValue(BD(self).states.power, smoothEnum)
    else
        BD(self).widgets.powerBar:SetBarValue(BD(self).states.power)
    end
end

UnitButton_UpdatePowerType = function(self)
    if not BD(self)._shouldShowPowerBar then return end

    local unit = BD(self).states.displayedUnit
    if not unit then return end

    local r, g, b, lossR, lossG, lossB
    local a = Cell.loaded and CellDB["appearance"]["lossAlpha"] or 1

    local connected = UnitIsConnected(unit)
    if F.IsValueNonSecret(connected) and not connected then
        r, g, b = 0.4, 0.4, 0.4
        lossR, lossG, lossB = 0.4, 0.4, 0.4
    else
        r, g, b, lossR, lossG, lossB, BD(self).states.powerType = F.GetPowerBarColor(unit, BD(self).states.class)
    end

    BD(self).widgets.powerBar:SetStatusBarColor(r, g, b)
    BD(self).widgets.powerBarLoss:SetVertexColor(lossR, lossG, lossB)
end

local function UnitButton_UpdateHealthMax(self)
    local unit = BD(self).states.displayedUnit
    if not unit then return end

    UnitButton_UpdateHealthStates(self)

    if Cell.isMidnight and BD(self).widgets.healthCalculator then
        local maxHealth = BD(self).widgets.healthCalculator:GetMaximumHealth()
        BD(self).widgets.healthBar:SetMinMaxValues(0, maxHealth)
        -- Also update overlay bar ranges
        if BD(self).widgets.incomingHeal then
            BD(self).widgets.incomingHeal:SetMinMaxValues(0, maxHealth)
        end
        if BD(self).widgets.shieldBar then
            BD(self).widgets.shieldBar:SetMinMaxValues(0, maxHealth)
        end
        if BD(self).widgets.shieldBarR then
            BD(self).widgets.shieldBarR:SetMinMaxValues(0, maxHealth)
        end
        if BD(self).widgets.absorbsBar then
            BD(self).widgets.absorbsBar:SetMinMaxValues(0, maxHealth)
        end
    else
        if barAnimationType == "Smooth" or barAnimationType == "Legacy" or barAnimationType == "Old" then
            BD(self).widgets.healthBar:SetMinMaxSmoothedValue(0, BD(self).states.healthMax)
        else
            BD(self).widgets.healthBar:SetMinMaxValues(0, BD(self).states.healthMax)
        end
    end

    if Cell.vars.useThresholdColor or Cell.vars.useFullColor then
        UnitButton_UpdateHealthColor(self)
    end
end

local function UnitButton_UpdateHealth(self, diff, skipStateUpdates)
    local unit = BD(self).states.displayedUnit
    if not unit then return end

    if not skipStateUpdates then
        UnitButton_UpdateHealthStates(self, diff)
    end

    if Cell.isMidnight and BD(self).widgets.healthCalculator then
        -- "Legacy": same as upstream Cell_beta — immediate SetValue.
        local calc = BD(self).widgets.healthCalculator
        local health = calc:GetCurrentHealth()
        local smoothEnum = (barAnimationType == "Smooth" and SBI_ExponentialEaseOut) or SBI_Immediate
        if smoothEnum then
            BD(self).widgets.healthBar:SetValue(health, smoothEnum)
        else
            BD(self).widgets.healthBar:SetValue(health)
        end

        if Cell.vars.useThresholdColor or Cell.vars.useFullColor then
            UnitButton_UpdateHealthColor(self)
        end

        if enabledIndicators["healthThresholds"] and BD(self).widgets.healthCalculator then
            BD(self).indicators.healthThresholds:CheckThresholdMidnight(BD(self).widgets.healthCalculator)
        else
            BD(self).indicators.healthThresholds:Hide()
        end

        -- CELL_FADE_OUT_HEALTH_PERCENT: use EvaluateMissingHealthPercent with a Curve to fade
        -- frames that are above the health threshold (healthy enough to fade out)
        if CELL_FADE_OUT_HEALTH_PERCENT and BD(self).widgets.healthCalculator then
            local fadeOutHealthCurve = RebuildFadeOutHealthCurve()
            if fadeOutHealthCurve and BD(self).states.inRange then
                -- Curve output: full color if below threshold (needs healing), dimmed
                -- (outOfRangeAlpha) if above -- alpha comes out through the color's
                -- own alpha channel, never a raw number from this call.
                local resultColor = BD(self).widgets.healthCalculator:EvaluateCurrentHealthPercent(fadeOutHealthCurve)
                if resultColor then
                    local _, _, _, targetAlpha = resultColor:GetRGBA()
                    self:SetAlpha(targetAlpha)
                end
            end
        end
    else
        local healthPercent = BD(self).states.healthPercent

        BD(self).widgets.healthBar:SetBarValue(BD(self).states.health)

        if Cell.vars.useThresholdColor or Cell.vars.useFullColor then
            UnitButton_UpdateHealthColor(self)
        end

        BD(self).states.healthPercentOld = healthPercent

        if enabledIndicators["healthThresholds"] then
            BD(self).indicators.healthThresholds:CheckThreshold(healthPercent)
        else
            BD(self).indicators.healthThresholds:Hide()
        end

        if CELL_FADE_OUT_HEALTH_PERCENT then
            if BD(self).states.inRange and healthPercent < CELL_FADE_OUT_HEALTH_PERCENT then
                A.FrameFadeIn(self, 0.25, self:GetAlpha(), 1)
            else
                A.FrameFadeOut(self, 0.25, self:GetAlpha(), CellDB["appearance"]["outOfRangeAlpha"])
            end
        end
    end
end

local function UnitButton_UpdateHealPrediction(self, skipStateUpdates)
    if Cell.isMidnight and BD(self).widgets.healPredictionCalculator then
        -- This keeps clamp/overflow settings isolated from the shared
        -- Bar is anchored to health fill edge (set in SetOrientation).
        if not predictionEnabled then
            BD(self).widgets.incomingHeal:Hide()
            return
        end
        local unit = BD(self).states.displayedUnit
        if not unit then return end
        local calc = BD(self).widgets.healPredictionCalculator
        -- Configure clamp: 0 = MissingHealth (no overheal past frame edge)
        calc:SetIncomingHealClampMode(0)
        calc:SetIncomingHealOverflowPercent(1.0)
        UnitGetDetailedHealPrediction(unit, nil, calc)
        local maxHealth = calc:GetMaximumHealth()
        local incomingHeals = calc:GetIncomingHeals()
        local bar = BD(self).widgets.incomingHeal
        -- Set explicit size: bar fills from health edge across remaining bar space
        if BD(self).orientation == "horizontal" then
            bar:SetWidth(BD(self).widgets.healthBar:GetWidth())
        else
            bar:SetHeight(BD(self).widgets.healthBar:GetHeight())
        end
        bar:SetMinMaxValues(0, maxHealth)
        bar:SetValue(incomingHeals)
        bar:Show()
        return
    end
    if not predictionEnabled then
        BD(self).widgets.incomingHeal:Hide()
        return
    end

    local unit = BD(self).states.displayedUnit
    if not unit then return end

    if not skipStateUpdates then
        UnitButton_UpdateHealthStates(self)
    end

    local incomingHeal = BD(self).widgets.incomingHeal
    -- Set size to match health bar for correct proportions
    if BD(self).orientation == "horizontal" then
        incomingHeal:SetWidth(BD(self).widgets.healthBar:GetWidth())
    else
        incomingHeal:SetHeight(BD(self).widgets.healthBar:GetHeight())
    end

    local calc = BD(self).widgets.healPredictionCalculator
    if calc and UnitGetDetailedHealPrediction then
        if UnitExists(unit) then
            UnitGetDetailedHealPrediction(unit, nil, calc)
        end
        local allHeal
        if calc.GetIncomingHeals then
            allHeal = select(1, calc:GetIncomingHeals())
        end
        incomingHeal:SetMinMaxValues(0, BD(self).states.healthMax)
        incomingHeal:SetValue((allHeal == nil) and 0 or allHeal)
    else
        local value = UnitGetIncomingHeals(unit) or 0
        incomingHeal:SetMinMaxValues(0, BD(self).states.healthMax)
        incomingHeal:SetValue(value)
    end
    incomingHeal:Show()
end

UnitButton_UpdateShieldAbsorbs = function(self, skipStateUpdates)
        if Cell.isMidnight and BD(self).widgets.healthCalculator then
            if not shieldEnabled and not overshieldEnabled then
                BD(self).widgets.shieldBar:Hide()
                BD(self).widgets.shieldBarR:Hide()
                BD(self).widgets.overShieldGlow:Hide()
                BD(self).widgets.overShieldGlowR:Hide()
                BD(self).indicators.shieldBar:Hide()
                return
            end
            local unit = BD(self).states.displayedUnit
            if not unit then return end
            if not skipStateUpdates then
                UnitButton_UpdateCalculator(self)
            end
        local absorbs = BD(self).widgets.healthCalculator:GetDamageAbsorbs()
        local healthMax = BD(self).widgets.healthCalculator:GetMaximumHealth()

        local _, isClamped
        local calc = BD(self).widgets.healPredictionCalculator
        if calc and UnitGetDetailedHealPrediction then
            if calc.SetDamageAbsorbClampMode then
                -- MissingHealth: clamped once the shield would overflow the
                -- health bar, not once it exceeds the unit's entire max health
                calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
            end
            if UnitExists(unit) then
                UnitGetDetailedHealPrediction(unit, nil, calc)
            end
            if calc.GetDamageAbsorbs then
                _, isClamped = calc:GetDamageAbsorbs()
            end
        end

        local function ApplyOverShieldGlow(glow)
            if overshieldEnabled and isClamped ~= nil then
                if glow.SetAlphaFromBoolean then
                    glow:Show()
                    glow:SetAlphaFromBoolean(isClamped, 1, 0)
                elseif F.IsValueNonSecret(isClamped) and isClamped then
                    glow:Show()
                else
                    glow:Hide()
                end
            else
                glow:Hide()
            end
        end

        if not shieldEnabled then
            -- Shield display itself is off -- Overshield alone just marks
            -- the health bar's edge.
            BD(self).widgets.shieldBar:Hide()
            BD(self).widgets.shieldBarR:Hide()
            BD(self).widgets.overShieldGlowR:Hide()
            BD(self).indicators.shieldBar:Hide()
            ApplyOverShieldGlow(BD(self).widgets.overShieldGlow)
            return
        end

        if overshieldReverseFillEnabled then
            BD(self).widgets.shieldBar:Hide()
            BD(self).widgets.shieldBarR:SetMinMaxValues(0, healthMax)
            BD(self).widgets.shieldBarR:SetValue(absorbs)
            BD(self).widgets.shieldBarR:Show()
            ApplyOverShieldGlow(BD(self).widgets.overShieldGlowR)
            BD(self).widgets.overShieldGlow:Hide()
        else
            BD(self).widgets.shieldBar:SetMinMaxValues(0, healthMax)
            BD(self).widgets.shieldBar:SetValue(absorbs)
            BD(self).widgets.shieldBar:Show()
            ApplyOverShieldGlow(BD(self).widgets.overShieldGlow)
            BD(self).widgets.shieldBarR:Hide()
            BD(self).widgets.overShieldGlowR:Hide()
        end

        -- Update shield indicator (user-configurable indicator on top of health bar)
        if enabledIndicators["shieldBar"] then
            local indBar = BD(self).indicators.shieldBar
            indBar:Show()
            indBar:SetAbsorbs(absorbs, healthMax)
            if indicatorBooleans["shieldBar"] then
                -- onlyShowOvershields: GetDamageAbsorbs isClamped is true when absorbs
                if isClamped ~= nil and indBar.SetAlphaFromBoolean then
                    indBar:SetAlphaFromBoolean(isClamped, 1, 0)
                elseif F.IsValueNonSecret(isClamped) and isClamped then
                    indBar:SetAlpha(1)
                else
                    indBar:SetAlpha(0)
                end
            elseif indBar.SetAlpha then
                indBar:SetAlpha(1)
            end
        else
            BD(self).indicators.shieldBar:Hide()
        end
        return
    end

    local unit = BD(self).states.displayedUnit
    if not unit then return end

    if not skipStateUpdates then
        UnitButton_UpdateHealthStates(self)
    end

    local shieldBar = BD(self).widgets.shieldBar
    local _ta = BD(self).states.totalAbsorbs
    local totalAbsorbs = (_ta == nil) and 0 or _ta
    local healthMax = BD(self).states.healthMax
    local health = BD(self).states.health

    local isSecret = F.HasAnySecretValues(totalAbsorbs, healthMax, health)

    if isSecret then
        -- Set size to match health bar for correct proportions
        if BD(self).orientation == "horizontal" then
            shieldBar:SetWidth(BD(self).widgets.healthBar:GetWidth())
        else
            shieldBar:SetHeight(BD(self).widgets.healthBar:GetHeight())
        end

        local calc = BD(self).widgets.healPredictionCalculator
        local absorbAmt, isClamped
        if calc and UnitGetDetailedHealPrediction then
            if calc.SetDamageAbsorbClampMode then
                calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
            end
            if UnitExists(unit) then
                UnitGetDetailedHealPrediction(unit, nil, calc)
            end
            if calc.GetDamageAbsorbs then
                absorbAmt, isClamped = calc:GetDamageAbsorbs()
            end
        end
        local displayAbsorbs = (absorbAmt == nil) and totalAbsorbs or absorbAmt

        if shieldEnabled then
            shieldBar:SetMinMaxValues(0, healthMax)
            shieldBar:SetValue(displayAbsorbs)
            shieldBar:Show()
        else
            shieldBar:Hide()
        end

        if overshieldEnabled and isClamped ~= nil then
            local glow = BD(self).widgets.overShieldGlow
            if glow.SetAlphaFromBoolean then
                glow:Show()
                glow:SetAlphaFromBoolean(isClamped, 1, 0)
            else
                if F.IsValueNonSecret(isClamped) and isClamped then
                    glow:Show()
                else
                    glow:Hide()
                end
            end
        else
            BD(self).widgets.overShieldGlow:Hide()
        end
        BD(self).widgets.shieldBarR:Hide()
        BD(self).widgets.overShieldGlowR:Hide()

        if enabledIndicators["shieldBar"] then
            -- Size the indicator to match health bar
            local indBar = BD(self).indicators.shieldBar
            if BD(self).orientation == "horizontal" then
                indBar:SetWidth(BD(self).widgets.healthBar:GetWidth())
            else
                indBar:SetHeight(BD(self).widgets.healthBar:GetHeight())
            end
            indBar:SetAbsorbs(displayAbsorbs, healthMax)
            indBar:Show()
        else
            BD(self).indicators.shieldBar:Hide()
        end
    else
        if totalAbsorbs > 0 then
            local shieldPercent = totalAbsorbs / healthMax

            -- Indicator (percentage-based overlay)
            if enabledIndicators["shieldBar"] then
                if indicatorBooleans["shieldBar"] then
                    -- onlyShowOvershields
                    local overshieldPercent = (totalAbsorbs + health - healthMax) / healthMax
                    if overshieldPercent > 0 then
                        BD(self).indicators.shieldBar:Show()
                        BD(self).indicators.shieldBar:SetPercent(overshieldPercent)
                    else
                        BD(self).indicators.shieldBar:Hide()
                    end
                else
                    BD(self).indicators.shieldBar:Show()
                    BD(self).indicators.shieldBar:SetPercent(shieldPercent)
                end
            else
                BD(self).indicators.shieldBar:Hide()
            end

            -- Widget shield bar (StatusBar)
            if shieldEnabled then
                -- Set size to match health bar
                if BD(self).orientation == "horizontal" then
                    shieldBar:SetWidth(BD(self).widgets.healthBar:GetWidth())
                else
                    shieldBar:SetHeight(BD(self).widgets.healthBar:GetHeight())
                end
                shieldBar:SetMinMaxValues(0, healthMax)
                shieldBar:SetValue(totalAbsorbs)
                shieldBar:Show()
            else
                shieldBar:Hide()
            end

            local healthPercent = BD(self).states.healthPercent
            if shieldPercent + healthPercent > 1 then
                if overshieldReverseFillEnabled then
                    local p = shieldPercent + healthPercent - 1
                    if p > healthPercent then p = healthPercent end
                    local barSize = (BD(self).orientation == "horizontal")
                        and BD(self).widgets.healthBar:GetWidth()
                        or BD(self).widgets.healthBar:GetHeight()
                    local shieldBarR = BD(self).widgets.shieldBarR
                    if BD(self).orientation == "horizontal" then
                        shieldBarR:SetWidth(p * barSize)
                    else
                        shieldBarR:SetHeight(p * barSize)
                    end
                    shieldBarR:Show()
                    if overshieldEnabled then
                        BD(self).widgets.overShieldGlowR:Show()
                    else
                        BD(self).widgets.overShieldGlowR:Hide()
                    end
                    BD(self).widgets.overShieldGlow:Hide()
                else
                    if overshieldEnabled then
                        BD(self).widgets.overShieldGlow:Show()
                    else
                        BD(self).widgets.overShieldGlow:Hide()
                    end
                    BD(self).widgets.shieldBarR:Hide()
                    BD(self).widgets.overShieldGlowR:Hide()
                end
            else
                BD(self).widgets.overShieldGlow:Hide()
                BD(self).widgets.shieldBarR:Hide()
                BD(self).widgets.overShieldGlowR:Hide()
            end
        else
            BD(self).indicators.shieldBar:Hide()
            shieldBar:Hide()
            BD(self).widgets.overShieldGlow:Hide()
            BD(self).widgets.shieldBarR:Hide()
            BD(self).widgets.overShieldGlowR:Hide()
        end
    end
end

local function UnitButton_UpdateHealAbsorbs(self, skipStateUpdates)
    if Cell.isMidnight and BD(self).widgets.healthCalculator then
        if not absorbEnabled then
            BD(self).widgets.absorbsBar:Hide()
            BD(self).widgets.overAbsorbGlow:Hide()
            return
        end
        local unit = BD(self).states.displayedUnit
        if not unit then return end
        if not skipStateUpdates then
            UnitButton_UpdateCalculator(self)
        end
        local healAbsorbs = BD(self).widgets.healthCalculator:GetHealAbsorbs()
        BD(self).widgets.absorbsBar:SetValue(healAbsorbs)
        BD(self).widgets.absorbsBar:Show()
        return
    end

    if not absorbEnabled then
        BD(self).widgets.absorbsBar:Hide()
        BD(self).widgets.overAbsorbGlow:Hide()
        return
    end

    local unit = BD(self).states.displayedUnit
    if not unit then return end

    if not skipStateUpdates then
        UnitButton_UpdateHealthStates(self)
    end

    local absorbsBar = BD(self).widgets.absorbsBar
    if absorbInvertColor then
        local r, g, b = F.InvertColor(BD(self).widgets.healthBar:GetStatusBarColor())
        absorbsBar:SetStatusBarColor(r, g, b)
        absorbsBar.overAbsorbGlow:SetVertexColor(r, g, b)
    end

    local calc = BD(self).widgets.healPredictionCalculator
    local healAbsorbAmt, isClamped
    if calc and UnitGetDetailedHealPrediction then
        if calc.SetHealAbsorbClampMode then
            calc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.MaximumHealth)
        end
        if UnitExists(unit) then
            UnitGetDetailedHealPrediction(unit, nil, calc)
        end
        if calc.GetHealAbsorbs then
            healAbsorbAmt, isClamped = calc:GetHealAbsorbs()
        end
    end

    local _healAbs = (healAbsorbAmt == nil) and BD(self).states.healAbsorbs or healAbsorbAmt
    local displayAbsorbs = (_healAbs == nil) and 0 or _healAbs
    absorbsBar:SetMinMaxValues(0, BD(self).states.health)
    absorbsBar:SetValue(displayAbsorbs)
    absorbsBar:Show()

    local glow = BD(self).widgets.overAbsorbGlow
    if isClamped ~= nil then
        if SetAlphaFromBoolean then
            glow:Show()
            SetAlphaFromBoolean(glow, isClamped, 1, 0)
        else
            if F.IsValueNonSecret(isClamped) and isClamped then
                glow:Show()
            else
                glow:Hide()
            end
        end
    else
        local showGlow = F.IsValueNonSecret(displayAbsorbs) and displayAbsorbs and displayAbsorbs > BD(self).states.health
        if showGlow then
            glow:Show()
        else
            glow:Hide()
        end
    end
end

local function UnitButton_UpdateThreat(self)
    local unit = BD(self).states.displayedUnit
    if not unit or not UnitExists(unit) then return end

    local status = UnitThreatSituation(unit)
    if F.IsValueNonSecret(status) and status and status >= 1 then
        if enabledIndicators["aggroBlink"] then
            BD(self).indicators.aggroBlink:ShowAggro(GetThreatStatusColor(status))
        end
        if enabledIndicators["aggroBorder"] then
            BD(self).indicators.aggroBorder:ShowAggro(GetThreatStatusColor(status))
        end
    else
        BD(self).indicators.aggroBlink:Hide()
        BD(self).indicators.aggroBorder:Hide()
    end
end

local function UnitButton_UpdateThreatBar(self)
    if not enabledIndicators["aggroBar"] then
        BD(self).indicators.aggroBar:Hide()
        return
    end

    local unit = BD(self).states.displayedUnit
    if not unit or not UnitExists(unit) then return end

    -- isTanking, status, scaledPercentage, rawPercentage, threatValue = UnitDetailedThreatSituation(unit, mobUnit)
    local _, status, scaledPercentage, rawPercentage = UnitDetailedThreatSituation(unit, "target")
    if F.IsValueNonSecret(status) and status then
        BD(self).indicators.aggroBar:Show()
        BD(self).indicators.aggroBar:SetSmoothedValue(scaledPercentage)
        BD(self).indicators.aggroBar:SetStatusBarColor(GetThreatStatusColor(status))
    else
        BD(self).indicators.aggroBar:Hide()
    end
end

local function UnitButton_UpdateCombatIcon(self)
    if not enabledIndicators["combatIcon"] then return end

    local unit = BD(self).states.displayedUnit
    if not unit then return end

    if not (indicatorBooleans["combatIcon"] and InCombatLockdown()) and F.IsKnownTrue(UnitAffectingCombat(unit)) then
        BD(self).indicators.combatIcon:Show()
    else
        BD(self).indicators.combatIcon:Hide()
    end
end

-- self:GetAlpha() can come back secret/tainted here, which crashes
-- A.FrameFadeIn/Out's raw arithmetic -- fall back to a sane alpha instead.
local function SafeCurrentAlpha(self, fallback)
    local a = self:GetAlpha()
    if F.IsValueNonSecret(a) then
        return a
    end
    return fallback
end

-- UNIT_IN_RANGE_UPDATE: unit, inRange
local IsInRange = F.IsInRange
function UnitButton_UpdateInRange(self, ir)
    local unit = BD(self).states.displayedUnit
    if not unit then return end

    -- Your own pet is never range-faded (see F.IsInRange) -- bypass the raw/secret
    -- UnitInRange fast path below too, since that one feeds Blizzard's raw result
    -- straight to SetAlphaFromBoolean without ever calling F.IsInRange at all.
    if F.IsKnownTrue(UnitIsUnit(unit, "pet")) then
        if BD(self).states.inRange ~= true then
            BD(self).states.inRange = true
            BD(self).states.wasInRange = true
            if Cell.loaded then
                A.FrameFadeIn(self, 0.25, SafeCurrentAlpha(self, CellDB["appearance"]["outOfRangeAlpha"]), 1)
            end
        end
        return
    end

    -- Midnight: UnitInRange can return a secret boolean in restricted content.
    -- Hand it straight to SetAlphaFromBoolean instead of resolving it first.
    if Cell.isMidnight and issecretvalue and self.SetAlphaFromBoolean
        and Cell.loaded and F.UnitInGroup(unit)
        and not F.IsKnownTrue(UnitIsUnit("player", unit)) then
        local rawInRange, rawChecked = UnitInRange(unit)
        if issecretvalue(rawInRange) or issecretvalue(rawChecked) then
            self:SetAlphaFromBoolean(rawInRange, 1, CellDB["appearance"]["outOfRangeAlpha"])
            BD(self).states.inRange = true -- readable fallback for other consumers
            BD(self).states.wasInRange = nil -- forces the normal path to resync once values are readable again
            return
        end
    end

    local inRange = IsInRange(unit)
    -- so frames don't grey out incorrectly
    if inRange == nil then inRange = true end

    BD(self).states.inRange = inRange
    if Cell.loaded then
        if BD(self).states.inRange ~= BD(self).states.wasInRange then
            if inRange then
                if CELL_FADE_OUT_HEALTH_PERCENT then
                    if Cell.isMidnight and BD(self).widgets and BD(self).widgets.healthCalculator then
                        local fadeOutHealthCurve = RebuildFadeOutHealthCurve()
                        if fadeOutHealthCurve then
                            local resultColor = BD(self).widgets.healthCalculator:EvaluateCurrentHealthPercent(fadeOutHealthCurve)
                            if resultColor then
                                local _, _, _, targetAlpha = resultColor:GetRGBA()
                                self:SetAlpha(targetAlpha)
                            end
                        else
                            A.FrameFadeIn(self, 0.25, SafeCurrentAlpha(self, CellDB["appearance"]["outOfRangeAlpha"]), 1)
                        end
                    elseif not BD(self).states.healthPercent or BD(self).states.healthPercent < CELL_FADE_OUT_HEALTH_PERCENT then
                        A.FrameFadeIn(self, 0.25, SafeCurrentAlpha(self, CellDB["appearance"]["outOfRangeAlpha"]), 1)
                    else
                        A.FrameFadeOut(self, 0.25, SafeCurrentAlpha(self, 1), CellDB["appearance"]["outOfRangeAlpha"])
                    end
                else
                    A.FrameFadeIn(self, 0.25, SafeCurrentAlpha(self, CellDB["appearance"]["outOfRangeAlpha"]), 1)
                end
            else
                A.FrameFadeOut(self, 0.25, SafeCurrentAlpha(self, 1), CellDB["appearance"]["outOfRangeAlpha"])
            end
        end
        BD(self).states.wasInRange = inRange
        -- self:SetAlpha(inRange and 1 or CellDB["appearance"]["outOfRangeAlpha"])
    end
end

local function UnitButton_UpdateVehicleStatus(self)
    local unit = BD(self).states.unit
    if not unit then return end

    if UnitHasVehicleUI(unit) then -- or UnitInVehicle(unit) or UnitUsingVehicle(unit) then
        BD(self).states.inVehicle = true
        if unit == "player" then
            BD(self).states.displayedUnit = "vehicle"
        else
            -- local prefix, id, suffix = strmatch(unit, "([^%d]+)([%d]*)(.*)")
            local prefix, id = strmatch(unit, "([^%d]+)([%d]*)")
            BD(self).states.displayedUnit = prefix .. "pet" .. (id or "")
        end
        BD(self).indicators.nameText:UpdateVehicleName()
    else
        BD(self).states.inVehicle = nil
        BD(self).states.displayedUnit = BD(self).states.unit
        BD(self).indicators.nameText.vehicle:SetText("")
    end
    if useEventHub then
        SyncButtonTracker(self)
    end
    if I.UpdateHealersAuraDisplayUnit then
        I.UpdateHealersAuraDisplayUnit(self)
    end
    if I.UpdateCustomAuraDisplays then
        I.UpdateCustomAuraDisplays(self)
    end
    if I.UpdateCombatAuraDisplays then
        I.UpdateCombatAuraDisplays(self)
    end
end

UnitButton_UpdateStatusText = function(self)
    local statusText = BD(self).indicators.statusText
    if not enabledIndicators["statusText"] then
        -- statusText:Hide()
        statusText:SetStatus()
        return
    end

    local unit = BD(self).states.unit
    if not unit then return end

    BD(self).states.guid = UnitGUID(unit) -- update!
    if not BD(self).states.guid then return end

    if F.IsValueNonSecret(UnitIsConnected(unit)) and not UnitIsConnected(unit) and F.IsKnownTrue(UnitIsPlayer(unit)) then
        statusText:Show()
        statusText:SetStatus("OFFLINE")
        statusText:ShowTimer()
    elseif not Cell.isMidnight and UnitIsAFK(unit) then
        statusText:Show()
        statusText:SetStatus("AFK")
        statusText:ShowTimer()
    elseif F.IsKnownTrue(UnitIsFeignDeath(unit)) then
        statusText:Show()
        statusText:SetStatus("FEIGN")
        statusText:HideTimer(true)
    elseif F.IsKnownTrue(UnitIsDeadOrGhost(unit)) then
        statusText:Show()
        statusText:HideTimer(true)
        if F.IsKnownTrue(UnitIsGhost(unit)) then
            statusText:SetStatus("GHOST")
        else
            statusText:SetStatus("DEAD")
        end
    elseif C_IncomingSummon.HasIncomingSummon(unit) then
        statusText:Show()
        statusText:HideTimer()
        local status = C_IncomingSummon.IncomingSummonStatus(unit)
        if status == Enum.SummonStatus.Pending then
            statusText:SetStatus("PENDING")
        else
            if status == Enum.SummonStatus.Accepted then
                statusText:SetStatus("ACCEPTED")
            elseif status == Enum.SummonStatus.Declined then
                statusText:SetStatus("DECLINED")
            end
            C_Timer.After(6, function() UnitButton_UpdateStatusText(self) end)
        end
    elseif statusText:GetStatus() == "DRINKING" then
        -- update colors
        statusText:Show()
        statusText:SetStatus("DRINKING")
    else
        -- statusText:Hide()
        statusText:HideTimer(true)
        statusText:SetStatus()
    end
end

local function UnitButton_UpdateName(self)
    local unit = BD(self).states.unit
    if not unit then return end

    BD(self).states.name = UnitName(unit)
    BD(self).states.fullName = F.UnitFullName(unit)
    local resolvedClass = F.ResolveUnitClassFile(unit, BD(self).states.class)
    if resolvedClass then
        BD(self).states.class = resolvedClass
        BD(self).states._classGuid = UnitGUID(unit)
    else
        local classFile = UnitClassBase(unit)
        if classFile and F.IsValueNonSecret(classFile) then
            BD(self).states.class = classFile
            BD(self).states._classGuid = UnitGUID(unit)
        end
    end
    BD(self).states.guid = UnitGUID(unit)
    BD(self).states.isPlayer = UnitIsPlayer(unit)

    BD(self).indicators.nameText:UpdateName()
end

UnitButton_UpdateNameTextColor = function(self)
    local unit = BD(self).states.unit
    if not unit then return end

    if enabledIndicators["nameText"] then
        local connected = UnitIsConnected(unit)
        local charmed = UnitIsCharmed(unit)
        local charmedPlayer = F.IsPlayerOrPartyAI(unit)
            and F.IsKnownTrue(charmed)
        if indicatorColors["nameText"][1] == "class_color"
            or (F.IsValueNonSecret(connected) and not connected)
            or charmedPlayer
            or BD(self).states.inVehicle then
            BD(self).indicators.nameText:SetColor(F.GetUnitClassColor(unit))
        else
            BD(self).indicators.nameText:SetColor(unpack(indicatorColors["nameText"][2]))
        end
    end
end

UnitButton_UpdateHealthTextColor = function(self)
    local unit = BD(self).states.unit
    if not unit then return end

    if enabledIndicators["healthText"] then
        BD(self).indicators.healthText:SetColor(F.GetUnitClassColor(unit))
    end
end

UnitButton_UpdateHealthColor = function(self)
    local unit = BD(self).states.unit
    if not unit then return end

    -- Keep last known class for the same GUID so bars don't pick up a recycled frame's color.
    local guid = UnitGUID(unit)
    local resolved = F.ResolveUnitClassFile(unit)
    if resolved then
        BD(self).states.class = resolved
        BD(self).states._classGuid = guid
    elseif guid and F.IsValueNonSecret(guid) and BD(self).states._classGuid == guid and BD(self).states.class then
        -- keep cached class for this unit
    else
        local fallback = UnitClassBase(unit)
        if fallback and F.IsValueNonSecret(fallback) then
            BD(self).states.class = fallback
            BD(self).states._classGuid = guid
        end
    end

    local barR, barG, barB
    local lossR, lossG, lossB
    local barA, lossA = 1, 1

    if Cell.loaded then
        barA =  CellDB["appearance"]["barAlpha"]
        lossA =  CellDB["appearance"]["lossAlpha"]
    end

    if Cell.isMidnight and BD(self).widgets.healthBarColorCurve and UnitHealthPercent then
        local useCurve = false

        if F.IsPlayerOrPartyAI(unit) then
            local connected = UnitIsConnected(unit)
            local charmed = UnitIsCharmed(unit)
            if F.IsValueNonSecret(connected) and not connected then
                barR, barG, barB = 0.4, 0.4, 0.4
                lossR, lossG, lossB = 0.4, 0.4, 0.4
            elseif F.IsKnownTrue(charmed) then
                barR, barG, barB, barA = 0.5, 0, 1, 1
                lossR, lossG, lossB, lossA = barR*0.2, barG*0.2, barB*0.2, 1
            else
                useCurve = true
            end
        elseif F.IsPet(BD(self).states.guid, BD(self).states.unit) then
            useCurve = true
        else
            useCurve = true
        end

        if useCurve then
            -- Rebuild curves (handles class color per unit + current settings)
            B.UpdateHealthColorCurve(self)
            -- UnitHealthPercent(unit, true, curve) evaluates health% against the curve
            local barColor = UnitHealthPercent(unit, true, BD(self).widgets.healthBarColorCurve)
            local lossColor = UnitHealthPercent(unit, true, BD(self).widgets.healthLossColorCurve)
            if barColor then
                barR, barG, barB = barColor:GetRGB()
            else
                -- Fallback when the percent/curve API returns nil (common while unit/health is secret):
                -- still paint class/custom colors so the frame is not stuck on a dark empty bar.
                local class = BD(self).states.class or Cell.vars.playerClass
                local cr, cg, cb = F.GetClassColor(class)
                local barMode = Cell.loaded and CellDB["appearance"]["barColor"][1]
                if barMode == "class_color_dark" then
                    barR, barG, barB = cr * 0.2, cg * 0.2, cb * 0.2
                elseif barMode == "custom" then
                    local cc = CellDB["appearance"]["barColor"][2]
                    barR, barG, barB = cc[1], cc[2], cc[3]
                else
                    barR, barG, barB = cr, cg, cb
                end
            end
            if lossColor then
                lossR, lossG, lossB = lossColor:GetRGB()
            else
                local class = BD(self).states.class or Cell.vars.playerClass
                local cr, cg, cb = F.GetClassColor(class)
                local lossMode = Cell.loaded and CellDB["appearance"]["lossColor"][1]
                if lossMode == "class_color_dark" then
                    lossR, lossG, lossB = cr * 0.2, cg * 0.2, cb * 0.2
                elseif lossMode == "custom" then
                    local cc = CellDB["appearance"]["lossColor"][2]
                    lossR, lossG, lossB = cc[1], cc[2], cc[3]
                elseif lossMode == "class_color" then
                    lossR, lossG, lossB = cr, cg, cb
                else
                    lossR, lossG, lossB = cr * 0.2, cg * 0.2, cb * 0.2
                end
            end
            if Cell.vars.useFullColor then
                local health = UnitHealth(unit)
                local healthMax = UnitHealthMax(unit)
                if not F.HasAnySecretValues(health, healthMax) and healthMax > 0 and health == healthMax then
                    barR = CellDB["appearance"]["fullColor"][2][1]
                    barG = CellDB["appearance"]["fullColor"][2][2]
                    barB = CellDB["appearance"]["fullColor"][2][3]
                end
            end
            -- deathColor override
            if F.IsKnownTrue(BD(self).states.isDeadOrGhost) or F.IsKnownTrue(BD(self).states.isDead) then
                if Cell.vars.useDeathColor then
                    lossR = CellDB["appearance"]["deathColor"][2][1]
                    lossG = CellDB["appearance"]["deathColor"][2][2]
                    lossB = CellDB["appearance"]["deathColor"][2][3]
                end
            end
        end

        if barR then
            BD(self).widgets.healthBar:SetStatusBarColor(barR, barG, barB, barA)
        end
        if lossR then
            BD(self).widgets.healthBarLoss:SetVertexColor(lossR, lossG, lossB, lossA)
        end
        -- Incoming heal color
        if Cell.loaded and CellDB["appearance"]["healPrediction"][2] then
            BD(self).widgets.incomingHeal:SetStatusBarColor(CellDB["appearance"]["healPrediction"][3][1], CellDB["appearance"]["healPrediction"][3][2], CellDB["appearance"]["healPrediction"][3][3], CellDB["appearance"]["healPrediction"][3][4])
        elseif barR then
            BD(self).widgets.incomingHeal:SetStatusBarColor(barR, barG, barB, 0.4)
        end
        return
    end

    if F.IsPlayerOrPartyAI(unit) then
        local connected = UnitIsConnected(unit)
        local charmed = UnitIsCharmed(unit)
        if F.IsValueNonSecret(connected) and not connected then
            barR, barG, barB = 0.4, 0.4, 0.4
            lossR, lossG, lossB = 0.4, 0.4, 0.4
        elseif F.IsKnownTrue(charmed) then
            barR, barG, barB, barA = 0.5, 0, 1, 1
            lossR, lossG, lossB, lossA = barR*0.2, barG*0.2, barB*0.2, 1
        elseif BD(self).states.inVehicle then
            barR, barG, barB, lossR, lossG, lossB = F.GetHealthBarColor(BD(self).states.healthPercent, F.IsKnownTrue(BD(self).states.isDeadOrGhost) or F.IsKnownTrue(BD(self).states.isDead), 0, 1, 0.2)
        else
            barR, barG, barB, lossR, lossG, lossB = F.GetHealthBarColor(BD(self).states.healthPercent, F.IsKnownTrue(BD(self).states.isDeadOrGhost) or F.IsKnownTrue(BD(self).states.isDead), F.GetClassColor(BD(self).states.class))
        end
    elseif F.IsPet(BD(self).states.guid, BD(self).states.unit) then
        barR, barG, barB, lossR, lossG, lossB = F.GetHealthBarColor(BD(self).states.healthPercent, F.IsKnownTrue(BD(self).states.isDeadOrGhost) or F.IsKnownTrue(BD(self).states.isDead), 0.5, 0.5, 1)
    else
        barR, barG, barB, lossR, lossG, lossB = F.GetHealthBarColor(BD(self).states.healthPercent, F.IsKnownTrue(BD(self).states.isDeadOrGhost) or F.IsKnownTrue(BD(self).states.isDead), 0, 1, 0.2)
    end

    BD(self).widgets.healthBar:SetStatusBarColor(barR, barG, barB, barA)
    BD(self).widgets.healthBarLoss:SetVertexColor(lossR, lossG, lossB, lossA)

    if Cell.loaded and CellDB["appearance"]["healPrediction"][2] then
        BD(self).widgets.incomingHeal:SetVertexColor(CellDB["appearance"]["healPrediction"][3][1], CellDB["appearance"]["healPrediction"][3][2], CellDB["appearance"]["healPrediction"][3][3], CellDB["appearance"]["healPrediction"][3][4])
    else
        BD(self).widgets.incomingHeal:SetVertexColor(barR, barG, barB, 0.4)
    end
end

Cell_._updateHealthColor = UnitButton_UpdateHealthColor
Cell_._updateHealthTextColor = UnitButton_UpdateHealthTextColor
Cell_._updatePowerMax = UnitButton_UpdatePowerMax
Cell_._updatePower = UnitButton_UpdatePower
Cell_._updatePowerType = UnitButton_UpdatePowerType
Cell_._updatePowerText = UnitButton_UpdatePowerText
Cell_._updatePowerTextColor = UnitButton_UpdatePowerTextColor
Cell_._updateNameTextColor = UnitButton_UpdateNameTextColor
Cell_._updateName = UnitButton_UpdateName
Cell_._updateVehicleStatus = UnitButton_UpdateVehicleStatus
Cell_._updateHealthMax = UnitButton_UpdateHealthMax
Cell_._updateHealth = UnitButton_UpdateHealth
Cell_._updateHealPrediction = UnitButton_UpdateHealPrediction
Cell_._updateTarget = UnitButton_UpdateTarget
Cell_._updatePlayerRaidIcon = UnitButton_UpdatePlayerRaidIcon
Cell_._updateTargetRaidIcon = UnitButton_UpdateTargetRaidIcon
Cell_._updateReadyCheck = UnitButton_UpdateReadyCheck
Cell_._updateHealAbsorbs = UnitButton_UpdateHealAbsorbs
Cell_._updateInRange = UnitButton_UpdateInRange
Cell_._updateThreat = UnitButton_UpdateThreat
Cell_._updateThreatBar = UnitButton_UpdateThreatBar
Cell_._updatePowerStates = UnitButton_UpdatePowerStates
Cell_._rememberSecretHelpfulCast = RememberSecretHelpfulCast
Cell_._getRecentSecretHelpfulCastKind = GetRecentSecretHelpfulCastKind
Cell_._updateHealthStates = UnitButton_UpdateHealthStates
Cell_._finishReadyCheck = UnitButton_FinishReadyCheck
Cell_._shouldShowPowerBar = ShouldShowPowerBar
Cell_._shouldShowPowerText = ShouldShowPowerText
Cell_._hidePowerBar = HidePowerBar
Cell_._showPowerBar = ShowPowerBar
Cell_._updateCombatIcon = UnitButton_UpdateCombatIcon
Cell_._initAuraTables = InitAuraTables
Cell_._resetAuraTables = ResetAuraTables

end)(Cell)

;(function(Cell)

local Cell_ = Cell

local L = Cell_.L
local F = Cell_.funcs
local function BD(b) return F.GetButtonData(b) end
local I = Cell_.iFuncs
local B = Cell_.bFuncs
local U = Cell_.uFuncs
local P = Cell_.pixelPerfectFuncs
local A = Cell_.animations
local LGI = LibStub:GetLibrary("LibGroupInfo")

local InitAuraTables = Cell_._initAuraTables
local ResetAuraTables = Cell_._resetAuraTables
local EnsureIndicatorsReadyOnShow = Cell_._ensureIndicatorsReadyOnShow
local HidePowerBar = Cell_._hidePowerBar
local ShowPowerBar = Cell_._showPowerBar
local UnitButton_UpdateCombatIcon = Cell_._updateCombatIcon
local UnitButton_UpdateHealthStates = Cell_._updateHealthStates
local UnitButton_FinishReadyCheck = Cell_._finishReadyCheck
local RememberSecretHelpfulCast = Cell_._rememberSecretHelpfulCast
local UnitButton_UpdateHealthColor = Cell_._updateHealthColor
local UnitButton_UpdateHealthTextColor = Cell_._updateHealthTextColor
local UnitButton_UpdatePowerMax = Cell_._updatePowerMax
local UnitButton_UpdatePower = Cell_._updatePower
local UnitButton_UpdatePowerType = Cell_._updatePowerType
local UnitButton_UpdatePowerText = Cell_._updatePowerText
local UnitButton_UpdatePowerTextColor = Cell_._updatePowerTextColor
local UnitButton_UpdateNameTextColor = Cell_._updateNameTextColor
local UnitButton_UpdateName = Cell_._updateName
local UnitButton_UpdateVehicleStatus = Cell_._updateVehicleStatus
local UnitButton_UpdateHealthMax = Cell_._updateHealthMax
local UnitButton_UpdateHealth = Cell_._updateHealth
local UnitButton_UpdateHealPrediction = Cell_._updateHealPrediction
local UnitButton_UpdateTarget = Cell_._updateTarget
local UnitButton_UpdatePlayerRaidIcon = Cell_._updatePlayerRaidIcon
local UnitButton_UpdateTargetRaidIcon = Cell_._updateTargetRaidIcon
local UnitButton_UpdateReadyCheck = Cell_._updateReadyCheck
local UnitButton_UpdateHealAbsorbs = Cell_._updateHealAbsorbs
local UnitButton_UpdateInRange = Cell_._updateInRange
local UnitButton_UpdateThreat = Cell_._updateThreat
local UnitButton_UpdateThreatBar = Cell_._updateThreatBar
local UnitButton_UpdatePowerStates = Cell_._updatePowerStates
local ShouldShowPowerBar = Cell_._shouldShowPowerBar
local ShouldShowPowerText = Cell_._shouldShowPowerText

local enabledIndicators = Cell_._enabledIndicators
local indicatorNums = Cell_._indicatorNums

local DoesAuraMatchExpectedBuff = Cell_._doesAuraMatchExpectedBuff
local UpdateAuraRefreshState = Cell_._updateAuraRefreshState
local GetRecentSecretHelpfulCastKind = Cell_._getRecentSecretHelpfulCastKind

do
    local function BuildThresholdCurve(curve, c1, c2, c3, lowBound, highBound, useGradient)
        curve:ClearPoints()
        lowBound = lowBound or 0.05
        highBound = highBound or 0.95

        local col1 = CreateColor(c1[1], c1[2], c1[3], 1)
        local col2 = CreateColor(c2[1], c2[2], c2[3], 1)
        local col3 = CreateColor(c3[1], c3[2], c3[3], 1)

        if useGradient then
            curve:SetType(Enum.LuaCurveType.Linear)
            curve:AddPoint(0.0, col1)
            curve:AddPoint(lowBound, col1)
            local mid = (lowBound + highBound) / 2
            curve:AddPoint(mid, col2)
            curve:AddPoint(highBound, col3)
            curve:AddPoint(1.0, col3)
        else
            curve:SetType(Enum.LuaCurveType.Linear)
            local eps = 0.001
            curve:AddPoint(0.0, col1)
            if lowBound > eps then
                curve:AddPoint(lowBound - eps, col1)
            end
            curve:AddPoint(lowBound + eps, col2)
            if highBound - lowBound > 2 * eps then
                curve:AddPoint(highBound - eps, col2)
            end
            curve:AddPoint(highBound + eps, col3)
            curve:AddPoint(1.0, col3)
        end
    end

    local function BuildFlatCurve(curve, r, g, b)
        curve:ClearPoints()
        curve:SetType(Enum.LuaCurveType.Linear)
        local col = CreateColor(r, g, b, 1)
        curve:AddPoint(0.0, col)
        curve:AddPoint(1.0, col)
    end

    function B.UpdateHealthColorCurve(button)
        if not Cell.isMidnight then return end
        if not BD(button).widgets.healthBarColorCurve then return end
        if not Cell.loaded then return end

        local unit = BD(button).states.displayedUnit or BD(button).states.unit
        local barCurve = BD(button).widgets.healthBarColorCurve
        local lossCurve = BD(button).widgets.healthLossColorCurve

        local class = F.ResolveUnitClassFile(unit, BD(button).states.class) or BD(button).states.class or Cell.vars.playerClass
        if class and F.IsValueNonSecret(class) then
            BD(button).states.class = class
        end
        local cr, cg, cb = F.GetClassColor(class)

        -- Build bar color curve
        local barMode = CellDB["appearance"]["barColor"][1]
        if barMode == "threshold1" then
            local c = CellDB["appearance"]["colorThresholds"]
            BuildThresholdCurve(barCurve, c[1], c[2], c[3], c[4], c[5], c[6])
        elseif barMode == "threshold2" then
            local c = CellDB["appearance"]["colorThresholds"]
            BuildThresholdCurve(barCurve, c[1], c[2], {cr, cg, cb}, c[4], c[5], c[6])
        elseif barMode == "threshold3" then
            local c = CellDB["appearance"]["colorThresholds"]
            BuildThresholdCurve(barCurve, c[1], c[2], {cr*0.2, cg*0.2, cb*0.2}, c[4], c[5], c[6])
        elseif barMode == "class_color" then
            BuildFlatCurve(barCurve, cr, cg, cb)
        elseif barMode == "class_color_dark" then
            BuildFlatCurve(barCurve, cr*0.2, cg*0.2, cb*0.2)
        else
            local cc = CellDB["appearance"]["barColor"][2]
            BuildFlatCurve(barCurve, cc[1], cc[2], cc[3])
        end

        -- Build loss color curve
        local lossMode = CellDB["appearance"]["lossColor"][1]
        if lossMode == "threshold1" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            BuildThresholdCurve(lossCurve, c[1], c[2], c[3], c[4], c[5], c[6])
        elseif lossMode == "threshold2" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            BuildThresholdCurve(lossCurve, {cr, cg, cb}, c[2], c[3], c[4], c[5], c[6])
        elseif lossMode == "threshold3" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            BuildThresholdCurve(lossCurve, {cr*0.2, cg*0.2, cb*0.2}, c[2], c[3], c[4], c[5], c[6])
        elseif lossMode == "class_color" then
            BuildFlatCurve(lossCurve, cr, cg, cb)
        elseif lossMode == "class_color_dark" then
            BuildFlatCurve(lossCurve, cr*0.2, cg*0.2, cb*0.2)
        else
            local cc = CellDB["appearance"]["lossColor"][2]
            BuildFlatCurve(lossCurve, cc[1], cc[2], cc[3])
        end
    end
end

-------------------------------------------------
-- translit names
-------------------------------------------------
Cell.RegisterCallback("TranslitNames", "UnitButton_TranslitNames", function()
    F.IterateAllUnitButtons(function(b)
        UnitButton_UpdateName(b)
    end, true)
end)

-------------------------------------------------
-- update all
-------------------------------------------------
local UnitButton_UpdateAll = function(self)
    if not self:IsVisible() then return end

    -- print(GetTime(), "UpdateAll", self:GetName())

    UnitButton_UpdateVehicleStatus(self)
    UnitButton_UpdateName(self)
    UnitButton_UpdateNameTextColor(self)
    UnitButton_UpdateHealthTextColor(self)
    UnitButton_UpdateHealthMax(self)
    UnitButton_UpdateHealth(self, nil, true)
    UnitButton_UpdateHealPrediction(self, true)
    UnitButton_UpdateStatusText(self)
    UnitButton_UpdateHealthColor(self)
    UnitButton_UpdateTarget(self)
    UnitButton_UpdatePlayerRaidIcon(self)
    UnitButton_UpdateTargetRaidIcon(self)
    UnitButton_UpdateShieldAbsorbs(self, true)
    UnitButton_UpdateHealAbsorbs(self, true)
    UnitButton_UpdateInRange(self)
    UnitButton_UpdateRole(self)
    UnitButton_UpdateLeader(self)
    UnitButton_UpdateReadyCheck(self)
    UnitButton_UpdateThreat(self)
    UnitButton_UpdateThreatBar(self)
    -- UnitButton_UpdateStatusIcon(self)
    I.UpdateStatusIcon_Resurrection(self)

    UnitButton_UpdatePowerStates(self)
    if Cell.loaded then
        if BD(self)._powerUpdateRequired then
            BD(self)._powerUpdateRequired = nil

            BD(self)._shouldShowPowerText = ShouldShowPowerText(self)
            BD(self)._shouldShowPowerBar = ShouldShowPowerBar(self)
            CheckPowerEventRegistration(self)

            if BD(self)._shouldShowPowerText then
                UnitButton_UpdatePowerTextColor(self)
                UnitButton_UpdatePowerText(self)
            else
                BD(self).indicators.powerText:Hide()
            end

            if BD(self)._shouldShowPowerBar then
                ShowPowerBar(self)
            else
                HidePowerBar(self)
            end

        end
    end

    UnitButton_UpdateAuras(self)
end

-------------------------------------------------
-- unit button events
-------------------------------------------------
local UnitButton_OnEvent
local UnitButton_OnTick

-- Midnight: keep SecureUnitButton children event-clean.
-- Unit events → per-button addon tracker frames (RegisterUnitEvent).
-- Global events → one shared hub.
local activeButtons = setmetatable({}, { __mode = "k" })
local buttonTrackers = setmetatable({}, { __mode = "k" }) -- button -> Frame
local eventHub
local tickHub

local POWER_HUB_EVENTS = {
    UNIT_POWER_FREQUENT = true,
    UNIT_MAXPOWER = true,
    UNIT_DISPLAYPOWER = true,
}

local UNIT_TRACKER_EVENTS = {
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_POWER_FREQUENT",
    "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_HEAL_PREDICTION",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
    "INCOMING_SUMMON_CHANGED",
    "UNIT_IN_RANGE_UPDATE",
    "UNIT_FLAGS",
    "UNIT_FACTION",
    "UNIT_CONNECTION",
    "PLAYER_FLAGS_CHANGED",
    "UNIT_NAME_UPDATE",
    "UNIT_TARGET",
    "READY_CHECK_CONFIRM",
    "UNIT_PORTRAIT_UPDATE",
}

local function EnsureButtonTracker(button)
    local t = buttonTrackers[button]
    if t then return t end
    t = CreateFrame("Frame")
    buttonTrackers[button] = t
    t:SetScript("OnEvent", function(_, event, unit, arg, arg2, ...)
        if not button:IsShown() then return end
        if POWER_HUB_EVENTS[event] and not BD(button)._wantPowerEvents then
            return
        end
        UnitButton_OnEvent(button, event, unit, arg, arg2, ...)
    end)
    return t
end

local function SyncButtonTracker(button)
    if not useEventHub then return end
    local t = EnsureButtonTracker(button)
    local bd = BD(button)
    local unit = bd.states and bd.states.unit
    local displayed = bd.states and bd.states.displayedUnit
    if (not unit) and button.GetAttribute then
        unit = button:GetAttribute("unit")
    end
    if not unit then
        t:UnregisterAllEvents()
        t._boundUnit = nil
        t._boundDisplayed = nil
        return
    end
    displayed = displayed or unit

    -- Rebind when unit tokens change (RegisterUnitEvent is 1–2 units per event).
    if t._boundUnit == unit and t._boundDisplayed == displayed and t._boundWantPower == bd._wantPowerEvents then
        return
    end
    t:UnregisterAllEvents()
    t._boundUnit = unit
    t._boundDisplayed = displayed
    t._boundWantPower = bd._wantPowerEvents

    local u2 = (displayed ~= unit) and displayed or nil
    for i = 1, #UNIT_TRACKER_EVENTS do
        local ev = UNIT_TRACKER_EVENTS[i]
        if POWER_HUB_EVENTS[ev] and not bd._wantPowerEvents then
            -- skip power events when power bar/text hidden
        elseif u2 then
            t:RegisterUnitEvent(ev, unit, u2)
        else
            t:RegisterUnitEvent(ev, unit)
        end
    end
end

local function HubRegisterButton(button)
    activeButtons[button] = true
    SyncButtonTracker(button)
    if tickHub then
        tickHub:Show()
    end
end

local function HubUnregisterButton(button)
    activeButtons[button] = nil
    local t = buttonTrackers[button]
    if t then
        t:UnregisterAllEvents()
        t._boundUnit = nil
        t._boundDisplayed = nil
    end
    if tickHub and not next(activeButtons) then
        tickHub:Hide()
    end
end

local function HubDispatchGlobal(event, unit, arg, arg2, ...)
    for btn in pairs(activeButtons) do
        if btn:IsShown() then
            pcall(UnitButton_OnEvent, btn, event, unit, arg, arg2, ...)
        end
    end
end

local function UnitButton_RegisterEvents(self)
    if useEventHub then
        HubRegisterButton(self)
        CheckPowerEventRegistration(self)
        SyncButtonTracker(self)
        local success, result = pcall(UnitButton_UpdateAll, self)
        if not success then
            F.Debug("UnitButton_UpdateAll |cffff0000FAILED:|r", self:GetName(), result)
        end
        return
    end
    -- self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")

    self:RegisterEvent("UNIT_HEALTH")
    self:RegisterEvent("UNIT_MAXHEALTH")

    self:RegisterEvent("UNIT_POWER_FREQUENT")
    self:RegisterEvent("UNIT_MAXPOWER")
    self:RegisterEvent("UNIT_DISPLAYPOWER")

    if F.IsLiveAuraScanBlocked and F.IsLiveAuraScanBlocked() then
        self:UnregisterEvent("UNIT_AURA")
    else
        self:RegisterEvent("UNIT_AURA")
    end
    if Cell.isMidnight then
        self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end

    self:RegisterEvent("UNIT_HEAL_PREDICTION")
    self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    self:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")

    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    self:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    self:RegisterEvent("UNIT_ENTERED_VEHICLE")
    self:RegisterEvent("UNIT_EXITED_VEHICLE")

    self:RegisterEvent("INCOMING_SUMMON_CHANGED")
    self:RegisterEvent("UNIT_IN_RANGE_UPDATE")
    self:RegisterEvent("UNIT_FLAGS") -- afk
    self:RegisterEvent("UNIT_FACTION") -- mind control

    self:RegisterEvent("UNIT_CONNECTION") -- offline
    self:RegisterEvent("PLAYER_FLAGS_CHANGED") -- afk
    self:RegisterEvent("UNIT_NAME_UPDATE") -- unknown target
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA") --? update status text

    -- self:RegisterEvent("PARTY_LEADER_CHANGED") -- GROUP_ROSTER_UPDATE
    -- self:RegisterEvent("PLAYER_ROLES_ASSIGNED") -- GROUP_ROSTER_UPDATE
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")

    self:RegisterEvent("PLAYER_TARGET_CHANGED")

    if Cell.loaded then
        if enabledIndicators["playerRaidIcon"] then
            self:RegisterEvent("RAID_TARGET_UPDATE")
        end
        if enabledIndicators["targetRaidIcon"] then
            self:RegisterEvent("UNIT_TARGET")
        end
        if enabledIndicators["readyCheckIcon"] then
            self:RegisterEvent("READY_CHECK")
            self:RegisterEvent("READY_CHECK_FINISHED")
            self:RegisterEvent("READY_CHECK_CONFIRM")
        end
    else
        self:RegisterEvent("RAID_TARGET_UPDATE")
        self:RegisterEvent("UNIT_TARGET")
        self:RegisterEvent("READY_CHECK")
        self:RegisterEvent("READY_CHECK_FINISHED")
        self:RegisterEvent("READY_CHECK_CONFIRM")
    end

    -- self:RegisterEvent("UNIT_PHASE") -- warmode, traditional sources of phasing such as progress through quest chains
    -- self:RegisterEvent("PARTY_MEMBER_DISABLE")
    -- self:RegisterEvent("PARTY_MEMBER_ENABLE")
    -- self:RegisterEvent("INCOMING_RESURRECT_CHANGED")

    -- self:RegisterEvent("VOICE_CHAT_CHANNEL_ACTIVATED")
    -- self:RegisterEvent("VOICE_CHAT_CHANNEL_DEACTIVATED")

    -- self:RegisterEvent("UNIT_PET")
    self:RegisterEvent("UNIT_PORTRAIT_UPDATE") -- pet summoned far away

    --! OnShow时立即执行，但UpdateIndicators可能并未执行完毕，导致在ResetCustomIndicators过程中指示器发生变化，进而报错
    -- OnShow fires immediately but UpdateIndicators may not have completed yet,
    -- so indicators can change during ResetCustomIndicators and cause errors.
    -- pcall prevents one frame's error from breaking all other frames.
    local success, result = pcall(UnitButton_UpdateAll, self)
    if not success then
        F.Debug("UnitButton_UpdateAll |cffff0000FAILED:|r", self:GetName(), result)
    end
end

local function UnitButton_UnregisterEvents(self)
    if useEventHub then
        HubUnregisterButton(self)
        return
    end
    self:UnregisterAllEvents()
end

UnitButton_OnEvent = function(self, event, unit, arg, arg2, ...)
    if event == "UNIT_AURA" and Cell.isMidnight then
        return
    end

    local function UnitMatches(u)
        if not u then return false end
        local bd = BD(self)
        local a, b = bd.states.displayedUnit, bd.states.unit
        if a == u or b == u then return true end
        -- UnitIsUnit can return a secret boolean (e.g. player vs targettarget) — never test it raw.
        if a and F.IsKnownTrue(UnitIsUnit(a, u)) then return true end
        if b and b ~= a and F.IsKnownTrue(UnitIsUnit(b, u)) then return true end
        return false
    end

    if unit and UnitMatches(unit) then
        if  event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" or event == "UNIT_CONNECTION" then
            BD(self)._updateRequired = 1
            BD(self)._powerUpdateRequired = 1

        elseif event == "UNIT_NAME_UPDATE" then
            UnitButton_UpdateName(self)
            UnitButton_UpdateNameTextColor(self)
            UnitButton_UpdateHealthColor(self)
            UnitButton_UpdateHealthTextColor(self)
            UnitButton_UpdatePowerTextColor(self)

        elseif event == "UNIT_MAXHEALTH" then
            UnitButton_UpdateHealthMax(self)
            UnitButton_UpdateHealth(self, nil, true)
            UnitButton_UpdateHealPrediction(self, true)
            UnitButton_UpdateShieldAbsorbs(self, true)
            UnitButton_UpdateHealAbsorbs(self, true)

        elseif event == "UNIT_HEALTH" then
            UnitButton_UpdateHealth(self)
            UnitButton_UpdateHealPrediction(self, true)
            UnitButton_UpdateShieldAbsorbs(self, true)
            UnitButton_UpdateHealAbsorbs(self, true)
            -- UnitButton_UpdateStatusText(self)

        elseif event == "UNIT_HEAL_PREDICTION" then
            UnitButton_UpdateHealPrediction(self)

        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            UnitButton_UpdateShieldAbsorbs(self)
            if enabledIndicators["healthText"] then
                UnitButton_UpdateHealthStates(self)
            end

        elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
            UnitButton_UpdateHealAbsorbs(self)
            if enabledIndicators["healthText"] then
                UnitButton_UpdateHealthStates(self)
            end

        elseif event == "UNIT_MAXPOWER" then
            UnitButton_UpdatePowerStates(self)
            UnitButton_UpdatePowerMax(self)
            UnitButton_UpdatePower(self)
            UnitButton_UpdatePowerText(self)

        elseif event == "UNIT_POWER_FREQUENT" then
            UnitButton_UpdatePowerStates(self)
            UnitButton_UpdatePower(self)
            UnitButton_UpdatePowerText(self)

        elseif event == "UNIT_DISPLAYPOWER" then
            UnitButton_UpdatePowerStates(self)
            UnitButton_UpdatePowerMax(self)
            UnitButton_UpdatePower(self)
            UnitButton_UpdatePowerType(self)
            UnitButton_UpdatePowerTextColor(self)
            UnitButton_UpdatePowerText(self)

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local castingUnit = unit
            if castingUnit ~= "player" then return end
            local spellID = arg2
            if not spellID or type(spellID) ~= "number" then
                spellID = select(5, ...)
            end
            if spellID and type(spellID) == "number" then
                RememberSecretHelpfulCast(self, spellID)
            end

        elseif event == "UNIT_AURA" then
            if ShouldDeferUnitAura(unit) then
                local btn = self
                C_Timer.After(0, function()
                    local bd = F.BD(btn)
                    if bd.states and (bd.states.displayedUnit == unit or bd.states.unit == unit) then
                        UnitButton_UpdateAuras(btn, nil)
                    end
                end)
            else
                UnitButton_UpdateAuras(self, arg)
            end

        elseif event == "UNIT_IN_RANGE_UPDATE" then
            UnitButton_UpdateInRange(self, arg)

        elseif event == "UNIT_TARGET" then
            UnitButton_UpdateTargetRaidIcon(self)

        elseif event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_FLAGS" or event == "INCOMING_SUMMON_CHANGED" then
            -- if CELL_SUMMON_ICONS_ENABLED then UnitButton_UpdateStatusIcon(self) end
            UnitButton_UpdateStatusText(self)

        elseif event == "UNIT_FACTION" then -- mind control
            UnitButton_UpdateNameTextColor(self)
            UnitButton_UpdateHealthColor(self)

        elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
            UnitButton_UpdateThreat(self)

        -- elseif event == "INCOMING_RESURRECT_CHANGED" or event == "UNIT_PHASE" or event == "PARTY_MEMBER_DISABLE" or event == "PARTY_MEMBER_ENABLE" then
            -- UnitButton_UpdateStatusIcon(self)

        elseif event == "READY_CHECK_CONFIRM" then
            UnitButton_UpdateReadyCheck(self)

        elseif event == "UNIT_PORTRAIT_UPDATE" then -- pet summoned far away
            if BD(self).states.healthMax == 0 then
                BD(self)._updateRequired = 1
                BD(self)._powerUpdateRequired = 1
            end
        end

    else
        if event == "GROUP_ROSTER_UPDATE" then
            -- FIXME:
            -- if IsDelveInProgress() then
            --     BD(self).__tickCount = 2
            --     BD(self).__updateElapsed = 0.25
            -- else
                BD(self)._updateRequired = 1
                BD(self)._powerUpdateRequired = 1
            -- end

        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            UnitButton_UpdateLeader(self, event)
            -- resync range-fade alpha right at the combat boundary
            UnitButton_UpdateInRange(self)
            if event == "PLAYER_REGEN_DISABLED" then
                EnqueueCombatAuraUpdate(self)
            end
            if event == "PLAYER_REGEN_ENABLED" then
                UnitButton_UpdateHealth(self)
                UnitButton_UpdateShieldAbsorbs(self)
                UnitButton_UpdateHealAbsorbs(self)
                UnitButton_UpdatePowerStates(self)
                UnitButton_UpdatePowerText(self)
                UnitButton_UpdateAuras(self)
                -- Delayed retry: values at full health/power won't get events
                local btn = self
                C_Timer.After(0.5, function()
                    local bd = F.BD(btn)
                    if bd.states and bd.states.displayedUnit then
                        UnitButton_UpdateHealth(btn)
                        UnitButton_UpdateShieldAbsorbs(btn)
                        UnitButton_UpdateHealAbsorbs(btn)
                        UnitButton_UpdatePowerStates(btn)
                        UnitButton_UpdatePowerText(btn)
                        UnitButton_UpdateAuras(btn)
                    end
                end)
            end

        elseif event == "PLAYER_TARGET_CHANGED" then
            UnitButton_UpdateTarget(self)
            UnitButton_UpdateThreatBar(self)
            if self:GetAttribute("updateOnTargetChanged") then
                UnitButton_UpdateAll(self)
            end

        elseif event == "UNIT_THREAT_LIST_UPDATE" then
            UnitButton_UpdateThreatBar(self)

        elseif event == "RAID_TARGET_UPDATE" then
            UnitButton_UpdatePlayerRaidIcon(self)
            UnitButton_UpdateTargetRaidIcon(self)

        elseif event == "READY_CHECK" then
            UnitButton_UpdateReadyCheck(self)

        elseif event == "READY_CHECK_FINISHED" then
            UnitButton_FinishReadyCheck(self)

        elseif event == "ZONE_CHANGED_NEW_AREA" then
            -- F.Debug("|cffbbbbbb=== ZONE_CHANGED_NEW_AREA ===")
            -- BD(self)._updateRequired = 1
            UnitButton_UpdateStatusText(self)

        -- elseif event == "VOICE_CHAT_CHANNEL_ACTIVATED" or event == "VOICE_CHAT_CHANNEL_DEACTIVATED" then
        -- 	VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED
        end
    end
end

local timer
local function EnterLeaveInstance()
    if timer then timer:Cancel() timer=nil end
    timer = C_Timer.NewTimer(1, function()
        F.Debug("|cffff1111*** EnterLeaveInstance:|r UnitButton_UpdateAll")
        F.IterateAllUnitButtons(UnitButton_UpdateAll, true)
        timer = nil
    end)
end
Cell.RegisterCallback("EnterInstance", "UnitButton_EnterInstance", EnterLeaveInstance)
Cell.RegisterCallback("LeaveInstance", "UnitButton_LeaveInstance", EnterLeaveInstance)

local function UnitButton_OnAttributeChanged(self, name, value)
    if name == "unit" then
        local prevUnit = BD(self).states.unit
        local unitChanged = (value ~= prevUnit)

        -- A raid reshuffle can hand this button a different token (e.g. raid3
        -- -> raid5) while the same player stays on it. Skip the state wipe and
        -- full repaint in that case; only the GUID/name bookkeeping needs to move.
        local samePlayerNewSlot = false
        if unitChanged and value and prevUnit then
            local oldGuid = BD(self).__unitGuid
            if oldGuid and F.IsValueNonSecret(oldGuid) then
                local newGuid = UnitGUID(value)
                if newGuid and F.IsValueNonSecret(newGuid) and newGuid == oldGuid then
                    samePlayerNewSlot = true
                end
            end
        end

        if not value or unitChanged then
            if samePlayerNewSlot then
                -- Same occupant, just a new token -- repoint the registries
                -- instead of tearing them down, and leave BD(self).states
                -- alone (still correct for this occupant, nothing to redo).
                if not BD(self).isSpotlight and F.IsValueNonSecret(BD(self).__unitGuid) then
                    Cell.vars.guids[BD(self).__unitGuid] = value
                end
                if BD(self).__unitName and not BD(self).isSpotlight and F.IsValueNonSecret(BD(self).__unitName) then
                    Cell.vars.names[BD(self).__unitName] = value
                end
            else
                if BD(self).__unitGuid then
                    if not BD(self).isSpotlight and F.IsValueNonSecret(BD(self).__unitGuid) then
                        Cell.vars.guids[BD(self).__unitGuid] = nil
                    end
                    BD(self).__unitGuid = nil
                end

                if BD(self).__unitName then
                    if not BD(self).isSpotlight and F.IsValueNonSecret(BD(self).__unitName) then
                        Cell.vars.names[BD(self).__unitName] = nil
                    end
                    BD(self).__unitName = nil
                end

                BD(self)._recentSecretHelpfulCastKind = nil
                BD(self)._recentSecretHelpfulCastAt = nil
                BD(self)._recentSecretHelpfulCastSpellId = nil
                wipe(BD(self).states)

                -- a different player took over this slot -- clear the old
                -- occupant's aura/dispel state before the next repaint
                ResetAuraTables(self)

                if BD(self).widgets and BD(self).widgets.healthCalculator then
                    pcall(BD(self).widgets.healthCalculator.ResetPredictedValues, BD(self).widgets.healthCalculator)
                end
            end
        end

        -- Restore unit tokens immediately after wipe so a later error cannot leave the button unit-less
        -- (that stuck health at 0 and left the bar on a dark loss/background color).
        if type(value) == "string" then
            BD(self).states.unit = value
            BD(self).states.displayedUnit = value
            if string.find(value, "^raid%d+$") then
                Cell.unitButtons.raid.units[value] = self
            end
        end

        if unitChanged then
            if BD(self).indicators and BD(self).indicators.privateAuras then
                pcall(BD(self).indicators.privateAuras.UpdatePrivateAuraAnchor, BD(self).indicators.privateAuras, value)
            end
        end

        if type(value) == "string" then
            if useEventHub then
                SyncButtonTracker(self)
            end

            if unitChanged then
                if samePlayerNewSlot then
                    if I.UpdateHealersAuraDisplayUnit then
                        pcall(I.UpdateHealersAuraDisplayUnit, self)
                    end
                    if I.UpdateCustomAuraDisplays then
                        pcall(I.UpdateCustomAuraDisplays, self)
                    end
                    if I.UpdateCombatAuraDisplays then
                        pcall(I.UpdateCombatAuraDisplays, self)
                    end
                else
                    -- New occupant: defer the full repaint one frame instead of
                    -- running it inside the header's own reassignment pass, so a
                    -- join/leave touching many buttons doesn't stack it all at once.
                    C_Timer.After(0, function()
                        if not self:IsVisible() then return end
                        if BD(self).states.unit ~= value then return end
                        if I.UpdateHealersAuraDisplayUnit then
                            pcall(I.UpdateHealersAuraDisplayUnit, self)
                        end
                        if I.UpdateCustomAuraDisplays then
                            pcall(I.UpdateCustomAuraDisplays, self)
                        end
                        if I.UpdateCombatAuraDisplays then
                            pcall(I.UpdateCombatAuraDisplays, self)
                        end
                        pcall(UnitButton_UpdateAll, self)
                    end)
                end
            end
        end
    end
end

-------------------------------------------------
-- unit button show/hide/enter/leave
-------------------------------------------------
Cell.vars.guids = {} -- guid to unitid
Cell.vars.names = {} -- name to unitid

local function UnitButton_OnShow(self)
    -- print(GetTime(), "OnShow", self:GetName())

    -- Self-heal a button that was still hidden during the last full indicator
    -- init/update sweep (e.g. a Spotlight frame on a pseudo-unit like
    -- "targettarget"/"focustarget"/"boss1target" that didn't exist at that
    -- moment) and so never got _indicatorsReady set. Without this, the button
    -- keeps refreshing health/name forever (that runs unconditionally) while
    -- UnitButton_UpdateAuras silently no-ops every single call, since it bails
    -- out on !_indicatorsReady -- indicators on it never appear until some
    -- unrelated event (spec change, group type switch) happens to trigger
    -- another full sweep. Queueing it here catches it the moment it's actually
    -- shown instead of waiting on that coincidence.
    EnsureIndicatorsReadyOnShow(self)

    BD(self)._updateRequired = nil -- prevent UnitButton_UpdateAll twice. when convert party <-> raid, GROUP_ROSTER_UPDATE fired.
    BD(self)._powerUpdateRequired = 1
    UnitButton_RegisterEvents(self)

    --[[
    if BD(self).states.unit then
        -- NOTE: update Cell.vars.guids
        local guid = UnitGUID(BD(self).states.unit)
        if guid then
            Cell.vars.guids[guid] = BD(self).states.unit
        end
        --! NOTE: can't get valid name immediately after an unseen player joining into group
        BD(self).__timer = C_Timer.NewTicker(0.5, function()
            local name = GetUnitName(BD(self).states.unit, true)
            if name and name ~= _G.UNKNOWN then
                Cell.vars.names[name] = BD(self).states.unit
                BD(self).__timer:Cancel()
                BD(self).__timer = nil
            end
        end)
        -- print("show", BD(self).states.unit, guid, name)
    end
    ]]
end

local function UnitButton_OnHide(self)
    UnitButton_UnregisterEvents(self)
    ResetAuraTables(self)

    if BD(self).__unitGuid then
        if not BD(self).isSpotlight and F.IsValueNonSecret(BD(self).__unitGuid) then
            Cell.vars.guids[BD(self).__unitGuid] = nil
        end
        BD(self).__unitGuid = nil
    end

    if BD(self).__unitName then
        if not BD(self).isSpotlight and F.IsValueNonSecret(BD(self).__unitName) then
            Cell.vars.names[BD(self).__unitName] = nil
        end
        BD(self).__unitName = nil
    end

    BD(self).__displayedGuid = nil
    BD(self).__auraDisplayGuid = nil
    BD(self)._updateRequired = nil

    F.RemoveElementsExceptKeys(BD(self).states, "unit", "displayedUnit")

    if BD(self).widgets and BD(self).widgets.healthCalculator then
        BD(self).widgets.healthCalculator:ResetPredictedValues()
    end
end

local function UnitButton_OnEnter(self)
    if not IsEncounterInProgress() then UnitButton_UpdateStatusText(self) end

    if highlightEnabled then BD(self).widgets.mouseoverHighlight:Show() end

    local unit = BD(self).states.displayedUnit
    if not unit then return end

    if F.ShouldShowUnitTooltip and not F.ShouldShowUnitTooltip() then return end
    F.ShowTooltips(self, "unit", unit)
end

local function UnitButton_OnLeave(self)
    BD(self).widgets.mouseoverHighlight:Hide()
    GameTooltip:Hide()
end

-- Catches the one case OnAttributeChanged can't: a raid slot's own token
-- (e.g. "raid5") stays assigned to the same button, but the actual player
-- behind it changed (Blizzard doesn't re-fire "unit" for that). Runs once
-- per GROUP_ROSTER_UPDATE. Separate __auraDisplayGuid field so it doesn't
-- race with OnTick's own (unrelated) __unitGuid bookkeeping.
function F.ResyncAuraDisplaysForRosterChange()
    if not F.IterateAllUnitButtons then return end
    F.IterateAllUnitButtons(function(self)
        if not (self:IsShown() and BD(self).states.unit) then return end
        local unit = BD(self).states.unit
        local guid = UnitGUID(unit)
        if not F.IsValueNonSecret(guid) or not guid then return end
        if guid ~= BD(self).__auraDisplayGuid then
            BD(self).__auraDisplayGuid = guid
            if I.UpdateHealersAuraDisplayUnit then
                pcall(I.UpdateHealersAuraDisplayUnit, self)
            end
            if I.UpdateCustomAuraDisplays then
                pcall(I.UpdateCustomAuraDisplays, self)
            end
            if I.UpdateCombatAuraDisplays then
                pcall(I.UpdateCombatAuraDisplays, self)
            end
        end
    end, true)
end

local UNKNOWN, UNKNOWNOBJECT = _G.UNKNOWN, _G.UNKNOWNOBJECT
UnitButton_OnTick = function(self)
    local e = (BD(self).__tickCount or 0) + 1
    if e >= 2 then
        e = 0

        if useEventHub then
            local attrUnit = self.GetAttribute and self:GetAttribute("unit")
            if attrUnit and type(attrUnit) == "string" then
                if BD(self).states.unit ~= attrUnit then
                    BD(self).states.unit = attrUnit
                    if not BD(self).states.displayedUnit then
                        BD(self).states.displayedUnit = attrUnit
                    end
                    SyncButtonTracker(self)
                    BD(self)._updateRequired = 1
                    BD(self)._powerUpdateRequired = 1
                else
                    local t = buttonTrackers[self]
                    if not t or t._boundUnit ~= attrUnit then
                        SyncButtonTracker(self)
                    end
                end
            end
        end

        if BD(self).states.unit and BD(self).states.displayedUnit then
            local displayedGuid = UnitGUID(BD(self).states.displayedUnit)
            
            local guidChanged = false
            if not F.IsValueNonSecret(displayedGuid) or not F.IsValueNonSecret(BD(self).__displayedGuid) then
                guidChanged = true
            else
                guidChanged = displayedGuid ~= BD(self).__displayedGuid
            end

            if guidChanged then
                F.RemoveElementsExceptKeys(BD(self).states, "unit", "displayedUnit")
                BD(self).__displayedGuid = displayedGuid
                if displayedGuid ~= nil then
                    BD(self)._updateRequired = 1
                    BD(self)._powerUpdateRequired = 1
                end
            end

            local guid = UnitGUID(BD(self).states.unit)
            local unitGuidChanged = false

            if not F.IsValueNonSecret(guid) or not F.IsValueNonSecret(BD(self).__unitGuid) then
                unitGuidChanged = guid ~= nil
            else
                unitGuidChanged = guid and guid ~= BD(self).__unitGuid
            end

            if unitGuidChanged then
                BD(self).__unitGuid = guid
                
                if not BD(self).isSpotlight and F.IsValueNonSecret(guid) then
                    Cell.vars.guids[guid] = BD(self).states.unit
                end

                if UnitIsPlayer(BD(self).states.unit) then
                    local name = GetUnitName(BD(self).states.unit, true)
                    if (name and BD(self).__nameRetries and BD(self).__nameRetries >= 4) or 
                       (name and name ~= UNKNOWN and name ~= UNKNOWNOBJECT) then
                        BD(self).__unitName = name
                        if not BD(self).isSpotlight and F.IsValueNonSecret(name) then 
                            Cell.vars.names[name] = BD(self).states.unit 
                        end
                        BD(self).__nameRetries = nil
                    else
                        BD(self).__nameRetries = (BD(self).__nameRetries or 0) + 1
                        BD(self).__unitGuid = nil
                    end
                end
            end
        end

        UnitButton_UpdateInRange(self)
    end

    BD(self).__tickCount = e

    if BD(self)._updateRequired and BD(self)._indicatorsReady then
        BD(self)._updateRequired = nil
        UnitButton_UpdateAll(self)
    end

    if self:GetAttribute("refreshOnUpdate") then
        UnitButton_UpdateAll(self)
    end
end

local function UnitButton_OnUpdate(self, elapsed)
    local e = (BD(self).__updateElapsed or 0) + elapsed
    if e > 0.25 then
        e = 0
        UnitButton_OnTick(self)
        UnitButton_UpdateCombatIcon(self)
    end
    BD(self).__updateElapsed = e
end

if useEventHub then
    eventHub = CreateFrame("Frame")
    -- Global / non-unit-filtered events only. Per-unit events use button trackers.
    local hubEvents = {
        "GROUP_ROSTER_UPDATE",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "PLAYER_TARGET_CHANGED",
        "RAID_TARGET_UPDATE",
        "READY_CHECK", "READY_CHECK_FINISHED",
    }
    for i = 1, #hubEvents do
        eventHub:RegisterEvent(hubEvents[i])
    end
    eventHub:SetScript("OnEvent", function(_, event, unit, arg, arg2, ...)
        HubDispatchGlobal(event, unit, arg, arg2, ...)
    end)

    tickHub = CreateFrame("Frame")
    tickHub:Hide()
    tickHub:SetScript("OnUpdate", function(_, elapsed)
        for btn in pairs(activeButtons) do
            if btn:IsShown() then
                local e = (BD(btn).__updateElapsed or 0) + elapsed
                if e > 0.25 then
                    e = 0
                    UnitButton_OnTick(btn)
                    UnitButton_UpdateCombatIcon(btn)
                end
                BD(btn).__updateElapsed = e
            end
        end
    end)
end

-------------------------------------------------
-- button functions
-------------------------------------------------
function B.SetPowerSize(button, size)
    -- print(GetTime(), "SetPowerSize", button:GetName(), button:IsShown(), button:IsVisible())
    BD(button).powerSize = size

    if size == 0 then
        HidePowerBar(button)
        BD(button)._shouldShowPowerBar = false
    else
        BD(button)._shouldShowPowerBar = ShouldShowPowerBar(button)
        if BD(button)._shouldShowPowerBar then
            ShowPowerBar(button)
        else
            HidePowerBar(button)
        end
    end
    CheckPowerEventRegistration(button)
end

function B.UpdateShields(button)
    predictionEnabled = CellDB["appearance"]["healPrediction"][1]
    shieldEnabled = CellDB["appearance"]["shield"][1]
    overshieldEnabled = CellDB["appearance"]["overshield"][1]
    overshieldReverseFillEnabled = shieldEnabled and CellDB["appearance"]["overshieldReverseFill"]
    absorbEnabled = CellDB["appearance"]["healAbsorb"][1]
    absorbInvertColor = CellDB["appearance"]["healAbsorbInvertColor"]

    if Cell.isMidnight then
        BD(button).widgets.shieldBar:SetStatusBarColor(unpack(CellDB["appearance"]["shield"][2]))
        BD(button).widgets.shieldBarR:SetStatusBarColor(unpack(CellDB["appearance"]["shield"][2]))
    else
        BD(button).widgets.shieldBar:SetVertexColor(unpack(CellDB["appearance"]["shield"][2]))
        BD(button).widgets.shieldBarR:SetVertexColor(unpack(CellDB["appearance"]["shield"][2]))
    end
    -- overShieldGlow textures are always textures
    BD(button).widgets.overShieldGlow:SetVertexColor(unpack(CellDB["appearance"]["overshield"][2]))
    BD(button).widgets.overShieldGlowR:SetVertexColor(unpack(CellDB["appearance"]["overshield"][2]))
    if not absorbInvertColor then
        BD(button).widgets.overAbsorbGlow:SetVertexColor(unpack(CellDB["appearance"]["healAbsorb"][2]))
        if Cell.isMidnight then
            BD(button).widgets.absorbsBar:SetStatusBarColor(unpack(CellDB["appearance"]["healAbsorb"][2]))
        else
            BD(button).widgets.absorbsBar:SetVertexColor(unpack(CellDB["appearance"]["healAbsorb"][2]))
        end
    end

    UnitButton_UpdateHealPrediction(button)
    UnitButton_UpdateHealAbsorbs(button)
    UnitButton_UpdateShieldAbsorbs(button)
end

function B.SetTexture(button, tex)
    BD(button).widgets.healthBar:SetStatusBarTexture(tex)
    BD(button).widgets.healthBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -7) --! VERY IMPORTANT
    BD(button).widgets.healthBarLoss:SetTexture(tex)
    BD(button).widgets.powerBar:SetStatusBarTexture(tex)
    BD(button).widgets.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -7) --! VERY IMPORTANT
    BD(button).widgets.powerBarLoss:SetTexture(tex)
    if Cell.isMidnight then
        BD(button).widgets.incomingHeal:SetStatusBarTexture(tex)
    else
        BD(button).widgets.incomingHeal:SetTexture(tex)
    end
    BD(button).widgets.damageFlashTex:SetTexture(tex)
end

function B.UpdateColor(button)
    UnitButton_UpdateHealthColor(button)
    UnitButton_UpdatePowerType(button)
    UnitButton_UpdatePowerTextColor(button)
    button:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])
end

local function IncomingHeal_SetValue_Horizontal(self, incomingPercent, healthPercent)
    local barWidth = self:GetParent():GetWidth()
    local incomingHealWidth = incomingPercent * barWidth
    local lostHealthWidth = barWidth * (1 - healthPercent)

    -- FIXME: if incomingPercent is a very tiny number, like 0.005
    --! if width is set to 0, then the ACTUAL width may be 256!!!

    if lostHealthWidth == 0 then
        self:Hide()
    else
        if lostHealthWidth > incomingHealWidth then
            self:SetWidth(incomingHealWidth)
        else
            self:SetWidth(lostHealthWidth)
        end
        self:Show()
    end
end

local function ShieldBar_SetValue_Horizontal(self, shieldPercent, healthPercent)
    local barWidth = self:GetParent():GetWidth()
    if shieldPercent + healthPercent > 1 then -- overshield
        local p = 1 - healthPercent
        if p ~= 0 then
            if shieldEnabled then
                self:SetWidth(p * barWidth)
                self:Show()
            else
                self:Hide()
            end
        else
            self:Hide()
        end

        if overshieldReverseFillEnabled then
            p = shieldPercent + healthPercent - 1
            if p > healthPercent then p = healthPercent end
            self.shieldBarR:SetWidth(p * barWidth)
            self.shieldBarR:Show()
            if overshieldEnabled then
                self.overShieldGlowR:Show()
            else
                self.overShieldGlowR:Hide()
            end
            self.overShieldGlow:Hide()
        else
            if overshieldEnabled then
                self.overShieldGlow:Show()
            else
                self.overShieldGlow:Hide()
            end
            self.shieldBarR:Hide()
            self.overShieldGlowR:Hide()
        end
    else
        if shieldEnabled then
            self:SetWidth(shieldPercent * barWidth)
            self:Show()
        else
            self:Hide()
        end
        self.shieldBarR:Hide()
        self.overShieldGlow:Hide()
        self.overShieldGlowR:Hide()
    end
end

local function AbsorbsBar_SetValue_Horizontal(self, absorbsPercent, healthPercent)
    if absorbInvertColor then
        local r, g, b = F.InvertColor(self.healthBar:GetStatusBarColor())
        self:SetVertexColor(r, g, b)
        self.overAbsorbGlow:SetVertexColor(r, g, b)
    end

    local barWidth = self:GetParent():GetWidth()
    if absorbsPercent > healthPercent then
        self:SetWidth(healthPercent * barWidth)
        self.overAbsorbGlow:Show()
    else
        self:SetWidth(absorbsPercent * barWidth)
        self.overAbsorbGlow:Hide()
    end
    self:Show()
end

local function DamageFlashTex_SetValue_Horizontal(self, lostPercent)
    local barWidth = self:GetParent():GetWidth()
    self:SetWidth(barWidth * lostPercent)
end

local function IncomingHeal_SetValue_Vertical(self, incomingPercent, healthPercent)
    local barHeight = self:GetParent():GetHeight()
    local incomingHealHeight = incomingPercent * barHeight
    local lostHealthHeight = barHeight * (1 - healthPercent)

    if lostHealthHeight == 0 then
        self:Hide()
    else
        if lostHealthHeight > incomingHealHeight then
            self:SetHeight(incomingHealHeight)
        else
            self:SetHeight(lostHealthHeight)
        end
        self:Show()
    end
end

local function ShieldBar_SetValue_Vertical(self, shieldPercent, healthPercent)
    local barHeight = self:GetParent():GetHeight()
    if shieldPercent + healthPercent > 1 then -- overshield
        local p = 1 - healthPercent
        if p ~= 0 then
            if shieldEnabled then
                self:SetHeight(p * barHeight)
                self:Show()
            else
                self:Hide()
            end
        else
            self:Hide()
        end

        if overshieldReverseFillEnabled then
            p = shieldPercent + healthPercent - 1
            if p > healthPercent then p = healthPercent end
            self.shieldBarR:SetHeight(p * barHeight)
            self.shieldBarR:Show()
            if overshieldEnabled then
                self.overShieldGlowR:Show()
            else
                self.overShieldGlowR:Hide()
            end
            self.overShieldGlow:Hide()
        else
            if overshieldEnabled then
                self.overShieldGlow:Show()
            else
                self.overShieldGlow:Hide()
            end
            self.shieldBarR:Hide()
            self.overShieldGlowR:Hide()
        end
    else
        if shieldEnabled then
            self:SetHeight(shieldPercent * barHeight)
            self:Show()
        else
            self:Hide()
        end
        self.shieldBarR:Hide()
        self.overShieldGlow:Hide()
        self.overShieldGlowR:Hide()
    end
end

local function AbsorbsBar_SetValue_Vertical(self, absorbsPercent, healthPercent)
    if absorbInvertColor then
        local r, g, b = F.InvertColor(self.healthBar:GetStatusBarColor())
        self:SetVertexColor(r, g, b)
        self.overAbsorbGlow:SetVertexColor(r, g, b)
    end

    local barHeight = self:GetParent():GetHeight()
    if absorbsPercent > healthPercent then
        self:SetHeight(healthPercent * barHeight)
        self.overAbsorbGlow:Show()
    else
        self:SetHeight(absorbsPercent * barHeight)
        self.overAbsorbGlow:Hide()
    end
    self:Show()
end

local function DamageFlashTex_SetValue_Vertical(self, lostPercent)
    local barHeight = self:GetParent():GetHeight()
    self:SetHeight(barHeight * lostPercent)
end

function B.SetOrientation(button, orientation, rotateTexture)
    local healthBar = BD(button).widgets.healthBar
    local healthBarLoss = BD(button).widgets.healthBarLoss
    local powerBar = BD(button).widgets.powerBar
    local powerBarLoss = BD(button).widgets.powerBarLoss
    local incomingHeal = BD(button).widgets.incomingHeal
    local damageFlashTex = BD(button).widgets.damageFlashTex
    local gapTexture = BD(button).widgets.gapTexture
    local shieldBar = BD(button).widgets.shieldBar
    local shieldBarR = BD(button).widgets.shieldBarR
    local overShieldGlow = BD(button).widgets.overShieldGlow
    local overShieldGlowR = BD(button).widgets.overShieldGlowR
    local overAbsorbGlow = BD(button).widgets.overAbsorbGlow
    local absorbsBar = BD(button).widgets.absorbsBar

    gapTexture:SetColorTexture(unpack(CELL_BORDER_COLOR))

    BD(button).orientation = orientation
    if orientation == "vertical_health" then
        healthBar:SetOrientation("vertical")
        powerBar:SetOrientation("horizontal")
    else
        healthBar:SetOrientation(orientation)
        powerBar:SetOrientation(orientation)
    end
    healthBar:SetRotatesTexture(rotateTexture)
    powerBar:SetRotatesTexture(rotateTexture)

    local barOrientation = (orientation == "vertical_health") and "vertical" or orientation
    incomingHeal:SetOrientation(barOrientation)
    incomingHeal:SetRotatesTexture(rotateTexture)
    shieldBar:SetOrientation(barOrientation)
    shieldBar:SetRotatesTexture(rotateTexture)
    absorbsBar:SetOrientation(barOrientation)
    absorbsBar:SetRotatesTexture(rotateTexture)

    BD(button).indicators.healthThresholds:SetOrientation(orientation)

    if rotateTexture then
        F.RotateTexture(healthBarLoss, 90)
        F.RotateTexture(powerBarLoss, 90)
        if not Cell.isMidnight then F.RotateTexture(incomingHeal, 90) end
        F.RotateTexture(damageFlashTex, 90)
    else
        F.RotateTexture(healthBarLoss, 0)
        F.RotateTexture(powerBarLoss, 0)
        if not Cell.isMidnight then F.RotateTexture(incomingHeal, 0) end
        F.RotateTexture(damageFlashTex, 0)
    end

    if orientation == "horizontal" then
        -- update healthBarLoss
        P.ClearPoints(healthBarLoss)
        P.Point(healthBarLoss, "TOPRIGHT", healthBar)
        P.Point(healthBarLoss, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")

        -- update powerBarLoss
        P.ClearPoints(powerBarLoss)
        P.Point(powerBarLoss, "TOPRIGHT", powerBar)
        P.Point(powerBarLoss, "BOTTOMLEFT", powerBar:GetStatusBarTexture(), "BOTTOMRIGHT")

        -- update gapTexture
        P.ClearPoints(gapTexture)
        P.Point(gapTexture, "BOTTOMLEFT", powerBar, "TOPLEFT")
        P.Point(gapTexture, "BOTTOMRIGHT", powerBar, "TOPRIGHT")
        P.Height(gapTexture, CELL_BORDER_SIZE)

        if Cell.isMidnight then
            P.ClearPoints(incomingHeal)
            P.Point(incomingHeal, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
            P.Point(incomingHeal, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")
            incomingHeal:SetOrientation("horizontal")
            shieldBar:SetOrientation("horizontal")
            shieldBarR:SetOrientation("horizontal")
            absorbsBar:SetOrientation("horizontal")
        else
            incomingHeal.SetValue = IncomingHeal_SetValue_Horizontal
            P.ClearPoints(incomingHeal)
            P.Point(incomingHeal, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
            P.Point(incomingHeal, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")

            -- update shieldBar
            shieldBar.SetValue = ShieldBar_SetValue_Horizontal
            P.ClearPoints(shieldBar)
            P.Point(shieldBar, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
            P.Point(shieldBar, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")

            -- update shieldBarR
            P.ClearPoints(shieldBarR)
            P.Point(shieldBarR, "TOPRIGHT", healthBar:GetStatusBarTexture())
            P.Point(shieldBarR, "BOTTOMRIGHT", healthBar:GetStatusBarTexture())

            -- update absorbsBar
            absorbsBar.SetValue = AbsorbsBar_SetValue_Horizontal
            P.ClearPoints(absorbsBar)
            P.Point(absorbsBar, "TOPRIGHT", healthBar:GetStatusBarTexture())
            P.Point(absorbsBar, "BOTTOMRIGHT", healthBar:GetStatusBarTexture())
        end

        -- update overShieldGlow
        P.ClearPoints(overShieldGlow)
        P.Point(overShieldGlow, "TOPRIGHT")
        P.Point(overShieldGlow, "BOTTOMRIGHT")
        P.Width(overShieldGlow, 4)
        F.RotateTexture(overShieldGlow, 0)

        -- update overShieldGlowR
        local reverseShieldAnchor = Cell.isMidnight and shieldBarR:GetStatusBarTexture() or shieldBarR
        P.ClearPoints(overShieldGlowR)
        P.Point(overShieldGlowR, "TOP", reverseShieldAnchor, "TOPLEFT", 0, 0)
        P.Point(overShieldGlowR, "BOTTOM", reverseShieldAnchor, "BOTTOMLEFT", 0, 0)
        P.Width(overShieldGlowR, 8)
        F.RotateTexture(overShieldGlowR, 0)

        -- update overAbsorbGlow
        P.ClearPoints(overAbsorbGlow)
        P.Point(overAbsorbGlow, "TOPLEFT")
        P.Point(overAbsorbGlow, "BOTTOMLEFT")
        P.Width(overAbsorbGlow, 4)
        F.RotateTexture(overAbsorbGlow, 0)

        -- update damageFlashTex
        damageFlashTex.SetValue = DamageFlashTex_SetValue_Horizontal
        P.ClearPoints(damageFlashTex)
        P.Point(damageFlashTex, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
        P.Point(damageFlashTex, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")

    else -- vertical / vertical_health
        P.ClearPoints(healthBarLoss)
        P.Point(healthBarLoss, "TOPRIGHT", healthBar)
        P.Point(healthBarLoss, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")

        if orientation == "vertical" then
            -- update powerBarLoss
            P.ClearPoints(powerBarLoss)
            P.Point(powerBarLoss, "TOPRIGHT", powerBar)
            P.Point(powerBarLoss, "BOTTOMLEFT", powerBar:GetStatusBarTexture(), "TOPLEFT")

            -- update gapTexture
            P.ClearPoints(gapTexture)
            P.Point(gapTexture, "TOPRIGHT", powerBar, "TOPLEFT")
            P.Point(gapTexture, "BOTTOMRIGHT", powerBar, "BOTTOMLEFT")
            P.Width(gapTexture, CELL_BORDER_SIZE)
        else -- vertical_health
            -- update powerBarLoss
            P.ClearPoints(powerBarLoss)
            P.Point(powerBarLoss, "TOPRIGHT", powerBar)
            P.Point(powerBarLoss, "BOTTOMLEFT", powerBar:GetStatusBarTexture(), "BOTTOMRIGHT")

            -- update gapTexture
            P.ClearPoints(gapTexture)
            P.Point(gapTexture, "BOTTOMLEFT", powerBar, "TOPLEFT")
            P.Point(gapTexture, "BOTTOMRIGHT", powerBar, "TOPRIGHT")
            P.Height(gapTexture, CELL_BORDER_SIZE)
        end

        if Cell.isMidnight then
            P.ClearPoints(incomingHeal)
            P.Point(incomingHeal, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")
            P.Point(incomingHeal, "BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
            incomingHeal:SetOrientation("vertical")
            shieldBar:SetOrientation("vertical")
            shieldBarR:SetOrientation("vertical")
            absorbsBar:SetOrientation("vertical")
        else
            incomingHeal.SetValue = IncomingHeal_SetValue_Vertical
            P.ClearPoints(incomingHeal)
            P.Point(incomingHeal, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")
            P.Point(incomingHeal, "BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT")

            -- update shieldBar
            shieldBar.SetValue = ShieldBar_SetValue_Vertical
            P.ClearPoints(shieldBar)
            P.Point(shieldBar, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")
            P.Point(shieldBar, "BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT")

            -- update shieldBarR
            P.ClearPoints(shieldBarR)
            P.Point(shieldBarR, "TOPLEFT", healthBar:GetStatusBarTexture())
            P.Point(shieldBarR, "TOPRIGHT", healthBar:GetStatusBarTexture())

            -- update absorbsBar
            absorbsBar.SetValue = AbsorbsBar_SetValue_Vertical
            P.ClearPoints(absorbsBar)
            P.Point(absorbsBar, "TOPLEFT", healthBar:GetStatusBarTexture())
            P.Point(absorbsBar, "TOPRIGHT", healthBar:GetStatusBarTexture())
        end

        -- update overShieldGlow
        P.ClearPoints(overShieldGlow)
        P.Point(overShieldGlow, "TOPLEFT")
        P.Point(overShieldGlow, "TOPRIGHT")
        P.Height(overShieldGlow, 4)
        F.RotateTexture(overShieldGlow, 90)

        -- update overShieldGlowR
        local reverseShieldAnchor = Cell.isMidnight and shieldBarR:GetStatusBarTexture() or shieldBarR
        P.ClearPoints(overShieldGlowR)
        P.Point(overShieldGlowR, "LEFT", reverseShieldAnchor, "BOTTOMLEFT", 0, 0)
        P.Point(overShieldGlowR, "RIGHT", reverseShieldAnchor, "BOTTOMRIGHT", 0, 0)
        P.Height(overShieldGlowR, 8)
        F.RotateTexture(overShieldGlowR, 90)

        -- update overAbsorbGlow
        P.ClearPoints(overAbsorbGlow)
        P.Point(overAbsorbGlow, "BOTTOMLEFT")
        P.Point(overAbsorbGlow, "BOTTOMRIGHT")
        P.Height(overAbsorbGlow, 4)
        F.RotateTexture(overAbsorbGlow, 90)

        -- update damageFlashTex
        damageFlashTex.SetValue = DamageFlashTex_SetValue_Vertical
        P.ClearPoints(damageFlashTex)
        P.Point(damageFlashTex, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "TOPLEFT")
        P.Point(damageFlashTex, "BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
    end

    -- update actions
    I.UpdateActionsOrientation(button, orientation)
end

function B.UpdateHighlightColor(button)
    BD(button).widgets.targetHighlight:SetBackdropBorderColor(unpack(CellDB["appearance"]["targetColor"]))
    BD(button).widgets.mouseoverHighlight:SetBackdropBorderColor(unpack(CellDB["appearance"]["mouseoverColor"]))
end

function B.UpdateHighlightSize(button)
    local targetHighlight = BD(button).widgets.targetHighlight
    local mouseoverHighlight = BD(button).widgets.mouseoverHighlight

    local size = CellDB["appearance"]["highlightSize"]

    if size ~= 0 then
        highlightEnabled = true

        P.ClearPoints(targetHighlight)
        P.ClearPoints(mouseoverHighlight)

        -- update point
        if size < 0 then
            size = abs(size)
            P.Point(targetHighlight, "TOPLEFT", button, "TOPLEFT")
            P.Point(targetHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT")
            P.Point(mouseoverHighlight, "TOPLEFT", button, "TOPLEFT")
            P.Point(mouseoverHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT")
        else
            P.Point(targetHighlight, "TOPLEFT", button, "TOPLEFT", -size, size)
            P.Point(targetHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT", size, -size)
            P.Point(mouseoverHighlight, "TOPLEFT", button, "TOPLEFT", -size, size)
            P.Point(mouseoverHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT", size, -size)
        end

        -- update thickness
        targetHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(size)})
        mouseoverHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(size)})

        -- update color
        targetHighlight:SetBackdropBorderColor(unpack(CellDB["appearance"]["targetColor"]))
        mouseoverHighlight:SetBackdropBorderColor(unpack(CellDB["appearance"]["mouseoverColor"]))

        UnitButton_UpdateTarget(button) -- 0->!0 show highlight again
    else
        highlightEnabled = false
        targetHighlight:Hide()
        mouseoverHighlight:Hide()
    end
end

-- raidIcons
function B.UpdatePlayerRaidIcon(button, enabled)
    if not button:IsShown() then return end
    UnitButton_UpdatePlayerRaidIcon(button)
    if enabled then
        button:RegisterEvent("RAID_TARGET_UPDATE")
    else
        button:UnregisterEvent("RAID_TARGET_UPDATE")
    end
end

function B.UpdateTargetRaidIcon(button, enabled)
    if not button:IsShown() then return end
    UnitButton_UpdateTargetRaidIcon(button)
    if enabled then
        button:RegisterEvent("UNIT_TARGET")
    else
        button:UnregisterEvent("UNIT_TARGET")
    end
end

-- readyCheckIcon
function B.UpdateReadyCheckIcon(button, enabled)
    if not button:IsShown() then return end
    UnitButton_UpdateReadyCheck(button)
    if enabled then
        button:RegisterEvent("READY_CHECK")
        button:RegisterEvent("READY_CHECK_FINISHED")
        button:RegisterEvent("READY_CHECK_CONFIRM")
    else
        button:UnregisterEvent("READY_CHECK")
        button:UnregisterEvent("READY_CHECK_FINISHED")
        button:UnregisterEvent("READY_CHECK_CONFIRM")
    end
end

-- healthText
function B.UpdateHealthText(button)
    if BD(button).states.displayedUnit then
        UnitButton_UpdateHealthStates(button)
    end
end

-- powerText
function B.UpdatePowerText(button)
    if not BD(button).states.displayedUnit and BD(button).states.unit then
        BD(button).states.displayedUnit = BD(button).states.unit
    end
    if not BD(button).states.displayedUnit then
        local attrUnit = button:GetAttribute("unit")
        if attrUnit then
            BD(button).states.displayedUnit = attrUnit
        end
    end
    if BD(button)._shouldShowPowerText == nil and ShouldShowPowerText then
        BD(button)._shouldShowPowerText = ShouldShowPowerText(button)
    end
    if BD(button).states.displayedUnit then
        UnitButton_UpdatePowerStates(button)
        UnitButton_UpdatePowerText(button)
        UnitButton_UpdatePowerTextColor(button)
    end
end

-- statusText
function B.UpdateStatusText(button)
    UnitButton_UpdateStatusText(button)
end

-- shields
function B.UpdateShield(button)
    UnitButton_UpdateShieldAbsorbs(button)
end

-- animation
function B.UpdateAnimation(button)
    barAnimationType = CellDB["appearance"]["barAnimation"]

    if Cell.isMidnight then
        BD(button).widgets.healthBar:ResetSmoothedValue()
        BD(button).widgets.powerBar:ResetSmoothedValue()
        BD(button).widgets.healthBar.SetBarValue = BD(button).widgets.healthBar.SetValue
        BD(button).widgets.powerBar.SetBarValue = BD(button).widgets.powerBar.SetValue
    elseif barAnimationType == "Smooth" or barAnimationType == "Legacy" or barAnimationType == "Old" then
        BD(button).widgets.healthBar.SetBarValue = BD(button).widgets.healthBar.SetSmoothedValue
        BD(button).widgets.powerBar.SetBarValue = BD(button).widgets.powerBar.SetSmoothedValue
    else
        BD(button).widgets.healthBar:ResetSmoothedValue()
        BD(button).widgets.healthBar.SetBarValue = BD(button).widgets.healthBar.SetValue
        BD(button).widgets.powerBar:ResetSmoothedValue()
        BD(button).widgets.powerBar.SetBarValue = BD(button).widgets.powerBar.SetValue
    end

    BD(button).widgets.damageFlashAG:Finish()
end

-- backdrop
function B.UpdateBackdrop(button)
    if CELL_BORDER_SIZE == 0 then
        button:SetBackdrop({bgFile = Cell.vars.whiteTexture})
        button:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])
    else
        button:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(CELL_BORDER_SIZE)})
        button:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])
        button:SetBackdropBorderColor(unpack(CELL_BORDER_COLOR))
    end
end

-- pixel perfect
function B.UpdatePixelPerfect(button, updateIndicators)
    if not InCombatLockdown() then P.Resize(button) end
    P.Reborder(button)

    P.Repoint(BD(button).widgets.healthBar)
    P.Repoint(BD(button).widgets.healthBarLoss)
    P.Repoint(BD(button).widgets.powerBar)
    P.Repoint(BD(button).widgets.powerBarLoss)
    P.Repoint(BD(button).widgets.gapTexture)
    P.Resize(BD(button).widgets.gapTexture)

    P.Repoint(BD(button).widgets.incomingHeal)
    P.Repoint(BD(button).widgets.shieldBar)
    P.Repoint(BD(button).widgets.absorbsBar)
    P.Repoint(BD(button).widgets.damageFlashTex)

    P.Resize(BD(button).widgets.overShieldGlow)
    P.Repoint(BD(button).widgets.overShieldGlow)
    P.Resize(BD(button).widgets.overAbsorbGlow)
    P.Repoint(BD(button).widgets.overAbsorbGlow)

    B.UpdateHighlightSize(button)
    B.UpdateBackdrop(button)

    if updateIndicators then
        -- indicators
        for _, i in next, BD(button).indicators do
            if i.UpdatePixelPerfect then
                i:UpdatePixelPerfect()
            end
        end
    end

    BD(button).widgets.srIcon:UpdatePixelPerfect()
end

B.UpdateAll = UnitButton_UpdateAll
B.UpdateHealth = UnitButton_UpdateHealth
B.UpdateHealthMax = UnitButton_UpdateHealthMax
B.UpdateAuras = UnitButton_UpdateAuras
B.UpdateName = UnitButton_UpdateName

-------------------------------------------------
-- unit button init
-------------------------------------------------
-- local startTimeCache, statusCache = {}, {}
local startTimeCache = {}

-- Layers ---------------------------------------
-- OVERLAY
-- ARTWORK
--  -2 overAbsorbGlow (texture)
--  absorbsBar (StatusBar, frame level midLevel+2)
--  -4 overShieldGlow, overShieldGlowR (texture)
--  shieldBar (StatusBar, frame level midLevel+1), shieldBarR (texture)
--	-6 damageFlashTex
--	-7 healthBar, healthBarLoss
-- BORDER
--  0 gapTexture
-- BACKGROUND
-------------------------------------------------

-- NOTE: prevent a nil method error
local DumbFunc = function() end

Cell._hb.GetTime = GetTime
Cell._hb.enabledIndicators = enabledIndicators
Cell._hb.indicatorNums = indicatorNums
Cell._hb.DoesAuraMatchExpectedBuff = DoesAuraMatchExpectedBuff
Cell._hb.GetRecentSecretHelpfulCastKind = GetRecentSecretHelpfulCastKind
Cell._hb.UpdateAuraRefreshState = UpdateAuraRefreshState

function CellUnitButton_OnLoad(button)
    local name = button:GetName()

    BD(button).widgets = {}
    BD(button).states = {}
    BD(button).indicators = {}

    if Cell.isMidnight and CreateUnitHealPredictionCalculator then
        BD(button).widgets.healthCalculator = CreateUnitHealPredictionCalculator()
        BD(button).widgets.healPredictionCalculator = CreateUnitHealPredictionCalculator()
    end
    if Cell.isMidnight and C_CurveUtil then
        BD(button).widgets.healthBarColorCurve = C_CurveUtil.CreateColorCurve()
        BD(button).widgets.healthLossColorCurve = C_CurveUtil.CreateColorCurve()
    end

    InitAuraTables(button)

    -- ping system
    Mixin(button, PingableType_UnitFrameMixin)
    button:SetAttribute("ping-receiver", true)

    function button:GetTargetPingGUID()
        return BD(button).__unitGuid
    end

    -- background
    -- local background = button:CreateTexture(name.."Background", "BORDER")
    -- BD(button).widgets.background = background
    -- background:SetAllPoints(button)
    -- background:SetTexture(Cell.vars.whiteTexture)
    -- background:SetVertexColor(0, 0, 0, 1)

    -- NOTE: SecureUnitButton has no OnActionButtonPressAndHoldRelease
    -- button:SetAttribute("pressAndHoldAction", true)
    -- button:SetAttribute("typerelease", "macro")

    -- backdrop
    -- button:SetBackdrop({bgFile = Cell.vars.whiteTexture, edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(CELL_BORDER_SIZE)})
    -- button:SetBackdropColor(0, 0, 0, 1)
    -- button:SetBackdropBorderColor(unpack(CELL_BORDER_COLOR))

    -- healthbar
    local healthBar = CreateFrame("StatusBar", name.."HealthBar", button)
    BD(button).widgets.healthBar = healthBar
    -- P.Point(healthBar, "TOPLEFT", button, "TOPLEFT", 1, -1)
    -- P.Point(healthBar, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 4)
    healthBar:SetStatusBarTexture(Cell.vars.texture)
    healthBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -7)
    healthBar:SetFrameLevel(button:GetFrameLevel()+1)
    healthBar.SetBarValue = healthBar.SetValue

    -- healthBar:SetScript("OnValueChanged", function(self, value)
    --     if value == 0 then
    --         healthBar:SetValue(0.1)
    --     end
    -- end)

    -- hp loss
    local healthBarLoss = button:CreateTexture(name.."HealthBarLoss", "ARTWORK", nil , -7)
    BD(button).widgets.healthBarLoss = healthBarLoss
    -- P.Point(healthBarLoss, "TOPRIGHT", healthBar)
    -- P.Point(healthBarLoss, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")
    healthBarLoss:SetTexture(Cell.vars.texture)

    -- powerbar
    local powerBar = CreateFrame("StatusBar", name.."PowerBar", button)
    BD(button).widgets.powerBar = powerBar
    -- P.Point(powerBar, "TOPLEFT", healthBar, "BOTTOMLEFT", 0, -1)
    -- P.Point(powerBar, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    powerBar:SetStatusBarTexture(Cell.vars.texture)
    powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -7)
    powerBar:SetFrameLevel(button:GetFrameLevel()+2)
    powerBar.SetBarValue = powerBar.SetValue

    local gapTexture = button:CreateTexture(nil, "BORDER")
    BD(button).widgets.gapTexture = gapTexture
    -- P.Point(gapTexture, "BOTTOMLEFT", powerBar, "TOPLEFT")
    -- P.Point(gapTexture, "BOTTOMRIGHT", powerBar, "TOPRIGHT")
    -- P.Height(gapTexture, 1)
    gapTexture:SetColorTexture(unpack(CELL_BORDER_COLOR))

    -- power loss
    local powerBarLoss = button:CreateTexture(name.."PowerBarLoss", "ARTWORK", nil , -7)
    BD(button).widgets.powerBarLoss = powerBarLoss
    -- P.Point(powerBarLoss, "TOPRIGHT", powerBar)
    -- P.Point(powerBarLoss, "BOTTOMLEFT", powerBar:GetStatusBarTexture(), "BOTTOMRIGHT")
    powerBarLoss:SetTexture(Cell.vars.texture)

    -- incoming heal
    local incomingHeal
    if Cell.isMidnight then
        incomingHeal = CreateFrame("StatusBar", name.."IncomingHealBar", healthBar)
        incomingHeal:SetStatusBarTexture(Cell.vars.texture)
        incomingHeal:GetStatusBarTexture():SetDrawLayer("ARTWORK", -6)
        incomingHeal:SetFrameLevel(healthBar:GetFrameLevel()+1)
        -- Positioned by SetOrientation (anchored to health fill edge, not SetAllPoints)
        incomingHeal.SetVertexColor = incomingHeal.SetStatusBarColor
        incomingHeal.SetTexture = incomingHeal.SetStatusBarTexture
    else
        incomingHeal = healthBar:CreateTexture(name.."IncomingHealBar", "ARTWORK", nil, -3)
        incomingHeal:SetTexture(Cell.vars.texture)
        incomingHeal.SetValue = DumbFunc
    end
    BD(button).widgets.incomingHeal = incomingHeal
    incomingHeal:Hide()

    --* indicatorFrame
    local indicatorFrame = CreateFrame("Frame", name.."IndicatorFrame", button)
    BD(button).widgets.indicatorFrame = indicatorFrame
    indicatorFrame:SetFrameLevel(button:GetFrameLevel()+220)
    indicatorFrame:SetAllPoints(button)

    --* tsGlowFrame (Targeted Spells)
    local tsGlowFrame = CreateFrame("Frame", name.."TSGlowFrame", button)
    BD(button).widgets.tsGlowFrame = tsGlowFrame
    tsGlowFrame:SetFrameLevel(button:GetFrameLevel()+200)
    tsGlowFrame:SetAllPoints(button)

    --* srGlowFrame (Spell Request)
    local srGlowFrame = CreateFrame("Frame", name.."SRGlowFrame", button)
    BD(button).widgets.srGlowFrame = srGlowFrame
    srGlowFrame:SetFrameLevel(button:GetFrameLevel()+200)
    srGlowFrame:SetAllPoints(button)

    --* drGlowFrame (Dispel Request)
    local drGlowFrame = CreateFrame("Frame", name.."DRGlowFrame", button)
    BD(button).widgets.drGlowFrame = drGlowFrame
    drGlowFrame:SetFrameLevel(button:GetFrameLevel()+200)
    drGlowFrame:SetAllPoints(button)

    --* highLevelFrame
    local highLevelFrame = CreateFrame("Frame", name.."HighLevelFrame", button)
    BD(button).widgets.highLevelFrame = highLevelFrame
    highLevelFrame:SetFrameLevel(button:GetFrameLevel()+140)
    highLevelFrame:SetAllPoints(button)

    --* midLevelFrame
    local midLevelFrame = CreateFrame("Frame", name.."MidLevelFrame", button)
    BD(button).widgets.midLevelFrame = midLevelFrame
    midLevelFrame:SetFrameLevel(button:GetFrameLevel()+120)
    midLevelFrame:SetAllPoints(healthBar)

    -- shield bar
    local shieldBar
    if Cell.isMidnight then
        shieldBar = CreateFrame("StatusBar", name.."ShieldBar", midLevelFrame)
        shieldBar:SetStatusBarTexture("Interface\\AddOns\\Cell\\Media\\shield")
        shieldBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -5)
        shieldBar:SetFrameLevel(midLevelFrame:GetFrameLevel()+1)
        shieldBar:SetAllPoints(healthBar)
        shieldBar.SetVertexColor = shieldBar.SetStatusBarColor
        shieldBar.SetTexture = shieldBar.SetStatusBarTexture
    else
        shieldBar = midLevelFrame:CreateTexture(name.."ShieldBar", "ARTWORK", nil, -5)
        shieldBar:SetTexture("Interface\\AddOns\\Cell\\Media\\shield", "REPEAT", "REPEAT")
        shieldBar:SetHorizTile(true)
        shieldBar:SetVertTile(true)
        shieldBar.SetValue = DumbFunc
    end
    BD(button).widgets.shieldBar = shieldBar
    shieldBar:Hide()

    local shieldBarR
    if Cell.isMidnight then
        shieldBarR = CreateFrame("StatusBar", name.."ShieldBarR", midLevelFrame)
        shieldBarR:SetStatusBarTexture("Interface\\AddOns\\Cell\\Media\\shield")
        shieldBarR:GetStatusBarTexture():SetDrawLayer("ARTWORK", -5)
        shieldBarR:SetFrameLevel(midLevelFrame:GetFrameLevel()+1)
        shieldBarR:SetAllPoints(healthBar)
        shieldBarR:SetReverseFill(true)
        shieldBarR.SetVertexColor = shieldBarR.SetStatusBarColor
        shieldBarR.SetTexture = shieldBarR.SetStatusBarTexture
    else
        shieldBarR = midLevelFrame:CreateTexture(name.."ShieldBarR", "ARTWORK", nil, -5)
        shieldBarR:SetTexture("Interface\\AddOns\\Cell\\Media\\shield", "REPEAT", "REPEAT")
        shieldBarR:SetHorizTile(true)
        shieldBarR:SetVertTile(true)
    end
    BD(button).widgets.shieldBarR = shieldBarR
    shieldBarR:Hide()
    shieldBar.shieldBarR = shieldBarR

    -- over-shield glow -- hosted a level above shieldBar so it doesn't get
    -- drawn over on Midnight, where shieldBar is its own StatusBar frame
    local overShieldFrame = midLevelFrame
    if Cell.isMidnight then
        overShieldFrame = CreateFrame("Frame", name.."OverShieldFrame", midLevelFrame)
        overShieldFrame:SetFrameLevel(shieldBar:GetFrameLevel()+1)
        overShieldFrame:SetAllPoints(midLevelFrame)
    end

    local overShieldGlow = overShieldFrame:CreateTexture(name.."OverShieldGlow", "ARTWORK", nil, -4)
    BD(button).widgets.overShieldGlow = overShieldGlow
    overShieldGlow:SetTexture("Interface\\AddOns\\Cell\\Media\\overshield")
    -- overShieldGlow:SetBlendMode("ADD")
    overShieldGlow:Hide()
    shieldBar.overShieldGlow = overShieldGlow

    -- over-shield glow reversed
    local overShieldGlowR = overShieldFrame:CreateTexture(name.."OverShieldGlowR", "ARTWORK", nil, -4)
    BD(button).widgets.overShieldGlowR = overShieldGlowR
    overShieldGlowR:SetTexture("Interface\\AddOns\\Cell\\Media\\overshield_reversed")
    -- overShieldGlowR:SetBlendMode("ADD")
    overShieldGlowR:Hide()
    shieldBar.overShieldGlowR = overShieldGlowR

    local overAbsorbGlow = midLevelFrame:CreateTexture(name.."OverAbsorbGlow", "ARTWORK", nil, -2)
    BD(button).widgets.overAbsorbGlow = overAbsorbGlow
    overAbsorbGlow:SetTexture("Interface\\AddOns\\Cell\\Media\\overabsorb")
    -- overAbsorbGlow:SetBlendMode("ADD")
    overAbsorbGlow:Hide()

    -- absorbs bar
    local absorbsBar
    if Cell.isMidnight then
        absorbsBar = CreateFrame("StatusBar", name.."AbsorbsBar", midLevelFrame)
        absorbsBar:SetStatusBarTexture("Interface\\AddOns\\Cell\\Media\\shield.tga")
        absorbsBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
        absorbsBar:SetStatusBarColor(1, 0.1, 0.1, 1)
        absorbsBar:SetFrameLevel(midLevelFrame:GetFrameLevel()+2)
        absorbsBar:SetAllPoints(healthBar)
        absorbsBar:SetReverseFill(true)
        absorbsBar.SetVertexColor = absorbsBar.SetStatusBarColor
        absorbsBar.SetTexture = absorbsBar.SetStatusBarTexture
    else
        absorbsBar = midLevelFrame:CreateTexture(name.."AbsorbsBar", "ARTWORK", nil, 1)
        absorbsBar:SetTexture("Interface\\AddOns\\Cell\\Media\\shield.tga", "REPEAT", "REPEAT")
        absorbsBar:SetHorizTile(true)
        absorbsBar:SetVertTile(true)
        absorbsBar:SetVertexColor(1, 0.1, 0.1, 1)
        absorbsBar.SetValue = DumbFunc
    end
    BD(button).widgets.absorbsBar = absorbsBar
    absorbsBar.healthBar = healthBar
    -- absorbsBar:SetBlendMode("ADD")
    absorbsBar:Hide()
    absorbsBar.overAbsorbGlow = overAbsorbGlow

    if Cell.isMidnight then
        if BD(button).widgets.incomingHeal then
            BD(button).widgets.incomingHeal:SetMinMaxValues(0, 1)
        end
        if BD(button).widgets.shieldBar then
            BD(button).widgets.shieldBar:SetMinMaxValues(0, 1)
        end
        if BD(button).widgets.shieldBarR then
            BD(button).widgets.shieldBarR:SetMinMaxValues(0, 1)
        end
        if BD(button).widgets.absorbsBar then
            BD(button).widgets.absorbsBar:SetMinMaxValues(0, 1)
        end
    end

    -- bar animation
    -- flash
    local damageFlashTex = healthBar:CreateTexture(name.."DamageFlash", "ARTWORK", nil, -6)
    BD(button).widgets.damageFlashTex = damageFlashTex
    damageFlashTex:SetTexture(Cell.vars.whiteTexture)
    damageFlashTex:SetVertexColor(1, 1, 1, 0.7)
    -- P.Point(damageFlashTex, "TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT")
    -- P.Point(damageFlashTex, "BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT")
    damageFlashTex:Hide()
    damageFlashTex.SetValue = DumbFunc

    -- damage flash animation group
    local damageFlashAG = damageFlashTex:CreateAnimationGroup()
    BD(button).widgets.damageFlashAG = damageFlashAG

    local alpha = damageFlashAG:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.7)
    alpha:SetToAlpha(0)
    alpha:SetDuration(0.2)

    damageFlashAG:SetScript("OnPlay", function(self)
        damageFlashTex:Show()
    end)

    damageFlashAG:SetScript("OnFinished", function(self)
        damageFlashTex:Hide()
    end)

    -- smooth
    Mixin(healthBar, SmoothStatusBarMixin)
    Mixin(powerBar, SmoothStatusBarMixin)

    -- target highlight
    local targetHighlight = CreateFrame("Frame", name.."TargetHighlight", button, "BackdropTemplate")
    BD(button).widgets.targetHighlight = targetHighlight
    targetHighlight:SetIgnoreParentAlpha(true)
    targetHighlight:SetFrameLevel(button:GetFrameLevel()+3)
    -- targetHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
    -- P.Point(targetHighlight, "TOPLEFT", button, "TOPLEFT", -1, 1)
    -- P.Point(targetHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    targetHighlight:Hide()

    -- mouseover highlight
    local mouseoverHighlight = CreateFrame("Frame", name.."MouseoverHighlight", button, "BackdropTemplate")
    BD(button).widgets.mouseoverHighlight = mouseoverHighlight
    mouseoverHighlight:SetIgnoreParentAlpha(true)
    mouseoverHighlight:SetFrameLevel(button:GetFrameLevel()+4)
    -- mouseoverHighlight:SetBackdrop({edgeFile = Cell.vars.whiteTexture, edgeSize = P.Scale(1)})
    -- P.Point(mouseoverHighlight, "TOPLEFT", button, "TOPLEFT", -1, 1)
    -- P.Point(mouseoverHighlight, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    mouseoverHighlight:Hide()

    -- readyCheck highlight
    -- local readyCheckHighlight = button:CreateTexture(name.."ReadyCheckHighlight", "BACKGROUND")
    -- BD(button).widgets.readyCheckHighlight = readyCheckHighlight
    -- readyCheckHighlight:SetPoint("TOPLEFT", -1, 1)
    -- readyCheckHighlight:SetPoint("BOTTOMRIGHT", 1, -1)
    -- readyCheckHighlight:SetTexture(Cell.vars.whiteTexture)
    -- readyCheckHighlight:Hide()

    -- aggro bar
    local aggroBar = Cell.CreateStatusBar(name.."AggroBar", indicatorFrame, 20, 4, 100, true)
    BD(button).indicators.aggroBar = aggroBar
    aggroBar:Hide()

    -- indicators
    I.CreateNameText(button)
    I.CreateStatusText(button)
    I.CreateHealthText(button)
    I.CreatePowerText(button)
    I.CreateStatusIcon(button)
    I.CreateRoleIcon(button)
    I.CreateLeaderIcon(button)
    I.CreateCombatIcon(button)
    I.CreateReadyCheckIcon(button)
    I.CreateAggroBlink(button)
    I.CreateAggroBorder(button)
    I.CreatePlayerRaidIcon(button)
    I.CreateTargetRaidIcon(button)
    I.CreateShieldBar(button)
    I.CreateAoEHealing(button)
    I.CreateTankActiveMitigation(button)
    -- I.CreateDefensiveCooldowns(button)
    -- I.CreateExternalCooldowns(button)
    -- I.CreateAllCooldowns(button)
    -- I.CreateDebuffs(button)
    I.CreateDispels(button)
    I.CreateRaidDebuffs(button)
    I.CreatePrivateAuras(button)
    I.CreateTargetedSpells(button)
    I.CreateTargetCounter(button)
    I.CreateCrowdControls(button)
    I.CreateActions(button)
    I.CreateMissingBuffs(button)
    I.CreateHealthThresholds(button)
    U.CreateSpellRequestIcon(button)
    U.CreateDispelRequestText(button)

    BD(button)._waitingForIndicatorCreation = true

    -- events
    button:HookScript("OnAttributeChanged", UnitButton_OnAttributeChanged) -- init
    button:HookScript("OnShow", UnitButton_OnShow)
    button:HookScript("OnHide", UnitButton_OnHide) -- use _onhide for click-castings
    button:HookScript("OnEnter", UnitButton_OnEnter) -- SecureHandlerEnterLeaveTemplate
    button:HookScript("OnLeave", UnitButton_OnLeave) -- SecureHandlerEnterLeaveTemplate
    button:SetScript("OnUpdate", UnitButton_OnUpdate)
    button:SetScript("OnEvent", UnitButton_OnEvent)
    button:RegisterForClicks("AnyDown")
end

end)(Cell)
