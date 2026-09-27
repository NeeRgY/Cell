local _, Cell = ...
Cell._hb = Cell._hb or {}
local hb = Cell._hb
local F = Cell.funcs
local function BD(b) return F.GetButtonData(b) end
local I = Cell.iFuncs

local function HandleBuff(self, auraInfo)
    if not auraInfo then return end

    if not F.IsValueNonSecret(auraInfo.auraInstanceID) then
        if F.IsValueNonSecret(auraInfo.spellId) then
            I.UpdateCustomIndicators(self, auraInfo, "buff")
        end
        return
    end

    local unit = BD(self).states.displayedUnit
    local auraInstanceID = auraInfo.auraInstanceID

    local name = auraInfo.name
    local icon = auraInfo.icon
    local count = auraInfo.applications
    local spellId = auraInfo.spellId
    local source = auraInfo.sourceUnit

    if spellId and not auraInfo._hasSecrets and F.IsAuraBlacklisted and F.IsAuraBlacklisted(spellId, "HELPFUL") then return end

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
        hb.UpdateAuraRefreshState(auraInfo)
        BD(self)._buffs_cache[auraInstanceID] = auraInfo

        local isDefensive = false
        local isExternal = false
        local isOffensive = false
        local secretAuraUnitTrustworthy = F.IsSecretAuraUnitTrustworthy and F.IsSecretAuraUnitTrustworthy(unit, self)

        local inCombat = UnitAffectingCombat("player")

        local classified = BD(self)._buffs._classified and BD(self)._buffs._classified[auraInstanceID]
        if classified and (inCombat or not auraInfo._hasSecrets) then
            isDefensive = classified == "defensive"
            isExternal = classified == "external"
            isOffensive = classified == "offensive"
        end

        if not classified then
            isDefensive = I.IsDefensiveCooldown(name, spellId)
            isExternal = I.IsExternalCooldown(name, spellId, source, unit)
            isOffensive = I.IsOffensiveCooldown and I.IsOffensiveCooldown(name, spellId)
        end

        if not isDefensive and not isExternal and inCombat
            and auraInfo._hasSecrets and secretAuraUnitTrustworthy then
            if not F.IsValueNonSecret(spellId) then
                local _, kind = Cell.IdentifySecretAura(unit, auraInstanceID)
                if kind == "defensive" then
                    isDefensive = true
                elseif kind == "external" then
                    isExternal = true
                elseif kind == "offensive" then
                    isOffensive = true
                end
            end
        end

        if not classified and (isDefensive or isExternal or isOffensive) then
            BD(self)._buffs._classified = BD(self)._buffs._classified or {}
            BD(self)._buffs._classified[auraInstanceID] = isDefensive and "defensive" or (isExternal and "external" or "offensive")
        end

        local isPlayerCast = false
        if isExternal or isDefensive or isOffensive then
            if not auraInfo._hasSecrets then
                isPlayerCast = source == "player" or source == "pet"
            elseif hb._IsAuraFilteredOut then
                local function CheckPlayerFilter(filter)
                    local result = hb._IsAuraFilteredOut(unit, auraInstanceID, filter)
                    return type(result) == "boolean" and not result
                end
                if isExternal then
                    isPlayerCast = CheckPlayerFilter("HELPFUL|EXTERNAL_DEFENSIVE|PLAYER")
                end
                if not isPlayerCast and isDefensive then
                    isPlayerCast = CheckPlayerFilter("HELPFUL|BIG_DEFENSIVE|PLAYER")
                end
                if not isPlayerCast then
                    isPlayerCast = CheckPlayerFilter("HELPFUL|RAID|PLAYER")
                end
            end
        end

        local borderR, borderG, borderB = 1, 0.85, 0
        if isPlayerCast then
            borderR, borderG, borderB = 0, 0.8, 0
        end

        local skipLegacy = I.ShouldSkipLegacyCombatAura
        if hb.enabledIndicators["defensiveCooldowns"] and isDefensive
            and not (skipLegacy and skipLegacy("defensiveCooldowns", self))
            and BD(self)._buffs.defensiveFound < hb.indicatorNums["defensiveCooldowns"] then
            BD(self)._buffs.defensiveFound = BD(self)._buffs.defensiveFound + 1
            local frame = BD(self).indicators.defensiveCooldowns[BD(self)._buffs.defensiveFound]
            if Cell.isMidnight then
                frame:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                if frame.border then frame.border:SetColorTexture(borderR, borderG, borderB); frame.border:Show() end
                if frame.cooldown and frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0) end
            else
                frame:SetCooldown(start, duration, nil, icon, count, auraInfo.refreshing)
            end
            frame.auraInstanceID = auraInstanceID
        end

        if hb.enabledIndicators["externalCooldowns"] and isExternal
            and not (skipLegacy and skipLegacy("externalCooldowns", self))
            and BD(self)._buffs.externalFound < hb.indicatorNums["externalCooldowns"] then
            BD(self)._buffs.externalFound = BD(self)._buffs.externalFound + 1
            local frame = BD(self).indicators.externalCooldowns[BD(self)._buffs.externalFound]
            if Cell.isMidnight then
                frame:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                if frame.border then frame.border:SetColorTexture(borderR, borderG, borderB); frame.border:Show() end
                if frame.cooldown and frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0) end
            else
                frame:SetCooldown(start, duration, nil, icon, count, auraInfo.refreshing)
            end
            frame.auraInstanceID = auraInstanceID
        end

        if hb.enabledIndicators["offensiveCooldowns"] and isOffensive
            and not (skipLegacy and skipLegacy("offensiveCooldowns", self))
            and BD(self)._buffs.offensiveFound < hb.indicatorNums["offensiveCooldowns"] then
            BD(self)._buffs.offensiveFound = BD(self)._buffs.offensiveFound + 1
            local frame = BD(self).indicators.offensiveCooldowns[BD(self)._buffs.offensiveFound]
            if Cell.isMidnight then
                frame:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                if frame.border then frame.border:SetColorTexture(borderR, borderG, borderB); frame.border:Show() end
                if frame.cooldown and frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0) end
            else
                frame:SetCooldown(start, duration, nil, icon, count, auraInfo.refreshing)
            end
            frame.auraInstanceID = auraInstanceID
        end

        if hb.enabledIndicators["allCooldowns"] and (isDefensive or isExternal)
            and not (skipLegacy and skipLegacy("allCooldowns", self))
            and BD(self)._buffs.allFound < hb.indicatorNums["allCooldowns"] then
            BD(self)._buffs.allFound = BD(self)._buffs.allFound + 1
            local frame = BD(self).indicators.allCooldowns[BD(self)._buffs.allFound]
            if Cell.isMidnight then
                frame:SetCooldownFromAura(unit, auraInstanceID, icon, auraInfo.refreshing)
                if frame.border then frame.border:SetColorTexture(borderR, borderG, borderB); frame.border:Show() end
                if frame.cooldown and frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0) end
            else
                frame:SetCooldown(start, duration, nil, icon, count, auraInfo.refreshing)
            end
            frame.auraInstanceID = auraInstanceID
        end

        if not Cell.isMidnight and hb.enabledIndicators["tankActiveMitigation"] and I.IsTankActiveMitigation(spellId) then
            BD(self).indicators.tankActiveMitigation:SetCooldown(start, duration)
            BD(self)._buffs.tankActiveMitigationFound = true
        end

        if hb.enabledIndicators["statusText"] and I.IsDrinking(name) then
            if not BD(self).indicators.statusText:GetStatus() then
                BD(self).indicators.statusText:SetStatus("DRINKING")
                BD(self).indicators.statusText:Show()
            end
            BD(self)._buffs.drinkingFound = true
        end

        I.UpdateCustomIndicators(self, auraInfo, "buff")

        if not auraInfo._hasSecrets and spellId then
            if spellId == 156621 then
                BD(self).states.BGFlag = "alliance"
            elseif spellId == 156618 then
                BD(self).states.BGFlag = "horde"
            end
        end
    end
end

Cell.HandleBuff = HandleBuff
