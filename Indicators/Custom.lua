local _, Cell = ...
local L = Cell.L
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs


-------------------------------------------------
-- custom indicators
-------------------------------------------------
local enabledIndicators = {}
local customIndicators = {
    ["buff"] = {},
    ["debuff"] = {},
}

Cell.snippetVars.enabledIndicators = enabledIndicators
Cell.snippetVars.customIndicators = customIndicators

--! init enabledIndicators & customIndicators
function I.UpdateIndicatorTable(indicatorTable)
    local indicatorName = indicatorTable["indicatorName"]
    local auraType = indicatorTable["auraType"]

    -- keep custom indicators in table
    if indicatorTable["enabled"] and not (Cell.isRetail and indicatorTable["type"] == "glow") then enabledIndicators[indicatorName] = true end

    -- NOTE: icons is different from other custom indicators, more like the Debuffs indicator
    if indicatorTable["type"] == "icons" then
        customIndicators[auraType][indicatorName] = {
            ["auras"] = F.ConvertSpellTable(indicatorTable["auras"], indicatorTable["trackByName"]), -- auras to match
            ["found"] = {},
            ["num"] = indicatorTable["num"],
        }
    elseif indicatorTable["type"] == "bars" or indicatorTable["type"] == "blocks" then
        customIndicators[auraType][indicatorName] = {
            ["auras"] = F.ConvertSpellTable_WithColor(indicatorTable["auras"], indicatorTable["trackByName"]), -- auras to match
            ["hasColor"] = true,
            ["found"] = {},
            ["num"] = indicatorTable["num"],
        }
    elseif indicatorTable["type"] == "border" then
        customIndicators[auraType][indicatorName] = {
            ["auras"] = F.ConvertSpellTable_WithColor(indicatorTable["auras"], indicatorTable["trackByName"]), -- auras to match
            ["hasColor"] = true,
            ["top"] = {},
            ["topOrder"] = {},
        }
    else
        customIndicators[auraType][indicatorName] = {
            ["auras"] = F.ConvertSpellTable(indicatorTable["auras"], indicatorTable["trackByName"]), -- auras to match
            ["top"] = {}, -- top aura details
            ["topOrder"] = {}, -- top aura order
        }
    end

    customIndicators[auraType][indicatorName]["name"] = indicatorTable["name"]
    customIndicators[auraType][indicatorName]["type"] = indicatorTable["type"]
    customIndicators[auraType][indicatorName]["castBy"] = indicatorTable["castBy"]

    if auraType == "buff" then
        customIndicators[auraType][indicatorName]["_auras"] = F.Copy(indicatorTable["auras"]) --* save ids
        customIndicators[auraType][indicatorName]["trackByName"] = indicatorTable["trackByName"]
        customIndicators[auraType][indicatorName]["keepInHealers"] = indicatorTable["keepInHealers"]

        if Cell.isMidnight and not indicatorTable["trackByName"] then
            local nameLookup = {}
            for _, spellId in ipairs(indicatorTable["auras"]) do
                if type(spellId) == "number" then
                    local name = F.GetSpellInfo(spellId)
                    if name then nameLookup[name] = true end
                end
            end
            customIndicators[auraType][indicatorName]["_nameLookup"] = nameLookup
        end
    end
end

function I.CreateIndicator(parent, indicatorTable)
    local indicatorName = indicatorTable["indicatorName"]
    local indicator
    if indicatorTable["type"] == "icon" then
        indicator = I.CreateAura_BarIcon(nil, F.BD(parent).widgets.indicatorFrame)
    elseif indicatorTable["type"] == "text" then
        indicator = I.CreateAura_Text(nil, F.BD(parent).widgets.indicatorFrame)
    elseif indicatorTable["type"] == "bar" then
        indicator = I.CreateAura_Bar(nil, F.BD(parent).widgets.indicatorFrame)
    elseif indicatorTable["type"] == "bars" then
        indicator = I.CreateAura_Bars(nil, F.BD(parent).widgets.indicatorFrame, 10)
    elseif indicatorTable["type"] == "rect" then
        indicator = I.CreateAura_Rect(nil, F.BD(parent).widgets.indicatorFrame)
    elseif indicatorTable["type"] == "icons" then
        indicator = I.CreateAura_Icons(nil, F.BD(parent).widgets.indicatorFrame, 10)
    elseif indicatorTable["type"] == "color" then
        indicator = I.CreateAura_Color(nil, parent)
    elseif indicatorTable["type"] == "texture" then
        indicator = I.CreateAura_Texture(nil, F.BD(parent).widgets.indicatorFrame)
    elseif indicatorTable["type"] == "glow" then
        if Cell.isRetail then
            indicator = CreateFrame("Frame", nil, parent)
            indicator:Hide()
            indicator.indicatorType = "glow"
            indicator.SetCooldown = function() end
            indicator.SetupGlow = function() end
            indicator.SetFadeOut = function() end
            indicator.Show = function() end
        else
            indicator = I.CreateAura_Glow(nil, F.BD(parent).widgets.highLevelFrame)
        end
    elseif indicatorTable["type"] == "overlay" then
        indicator = I.CreateAura_Overlay(nil, parent)
    elseif indicatorTable["type"] == "block" then
        indicator = I.CreateAura_Block(nil, F.BD(parent).widgets.indicatorFrame)
    elseif indicatorTable["type"] == "blocks" then
        indicator = I.CreateAura_Blocks(nil, F.BD(parent).widgets.indicatorFrame, 10)
    elseif indicatorTable["type"] == "border" then
        indicator = I.CreateAura_Border(nil, F.BD(parent).widgets.highLevelFrame)
    elseif indicatorTable["type"] == "highlightDebuffs" then
        indicator = I.CreateAura_Icons(nil, F.BD(parent).widgets.indicatorFrame, 10)
    end
    F.BD(parent).indicators[indicatorName] = indicator

    return indicator
end

function I.RemoveIndicator(parent, indicatorName, auraType)
    local indicator = F.BD(parent).indicators[indicatorName]
    indicator:ClearAllPoints()
    indicator:Hide()
    indicator:SetParent(nil)
    F.BD(parent).indicators[indicatorName] = nil
    enabledIndicators[indicatorName] = nil
    customIndicators[auraType][indicatorName] = nil
end

-- used for switching to a new layout
function I.RemoveAllCustomIndicators(parent)
    -- if parent ~= CellIndicatorsPreviewButton then
    --     wipe(enabledIndicators)
    --     wipe(customIndicators["buff"])
    --     wipe(customIndicators["debuff"])
    -- end

    for indicatorName, indicator in pairs(F.BD(parent).indicators) do
        if string.find(indicatorName, "^indicator") then
            indicator:ClearAllPoints()
            indicator:Hide()
            indicator:SetParent(nil)
            F.BD(parent).indicators[indicatorName] = nil
        end
    end
end

function I.ResetCustomIndicatorTables()
    -- clear
    wipe(enabledIndicators)
    wipe(customIndicators["buff"])
    wipe(customIndicators["debuff"])

    -- update customs
    for i = Cell.defaults.builtIns + 1, #Cell.vars.currentLayoutTable.indicators do
        I.UpdateIndicatorTable(Cell.vars.currentLayoutTable.indicators[i])
    end
end

local function UpdateCustomIndicators(layout, indicatorName, setting, value, value2)
    if layout and layout ~= Cell.vars.currentLayout then return end

    if not indicatorName or not string.find(indicatorName, "^indicator") then return end

    if setting == "enabled" then
        if value then
            enabledIndicators[indicatorName] = true
        else
            enabledIndicators[indicatorName] = nil
        end
    elseif setting == "auras" then
        customIndicators[value][indicatorName]["_auras"] = F.Copy(value2) --* save ids
        if customIndicators[value][indicatorName]["hasColor"] then
            customIndicators[value][indicatorName]["auras"] = F.ConvertSpellTable_WithColor(value2, customIndicators[value][indicatorName]["trackByName"])
        else
            customIndicators[value][indicatorName]["auras"] = F.ConvertSpellTable(value2, customIndicators[value][indicatorName]["trackByName"])
        end
        if Cell.isMidnight and value == "buff" and customIndicators["buff"][indicatorName]
            and not customIndicators["buff"][indicatorName]["trackByName"] then
            local nameLookup = {}
            for _, spellId in ipairs(value2) do
                if type(spellId) == "number" then
                    local name = F.GetSpellInfo(spellId)
                    if name then nameLookup[name] = true end
                end
            end
            customIndicators["buff"][indicatorName]["_nameLookup"] = nameLookup
        end
    elseif setting == "checkbutton" then
        if customIndicators["buff"][indicatorName] then
            customIndicators["buff"][indicatorName][value] = value2
            if value == "trackByName" then
                if customIndicators["buff"][indicatorName]["hasColor"] then
                    customIndicators["buff"][indicatorName]["auras"] = F.ConvertSpellTable_WithColor(customIndicators["buff"][indicatorName]["_auras"], value2)
                else
                    customIndicators["buff"][indicatorName]["auras"] = F.ConvertSpellTable(customIndicators["buff"][indicatorName]["_auras"], value2)
                end
                if Cell.isMidnight then
                    if not value2 then
                        -- Switched FROM trackByName=true TO false: build name lookup
                        local nameLookup = {}
                        for _, spellId in ipairs(customIndicators["buff"][indicatorName]["_auras"]) do
                            if type(spellId) == "number" then
                                local name = F.GetSpellInfo(spellId)
                                if name then nameLookup[name] = true end
                            end
                        end
                        customIndicators["buff"][indicatorName]["_nameLookup"] = nameLookup
                    else
                        -- Switched FROM trackByName=false TO true: name lookup no longer needed
                        customIndicators["buff"][indicatorName]["_nameLookup"] = nil
                    end
                end
            end
        elseif customIndicators["debuff"][indicatorName] then
            customIndicators["debuff"][indicatorName][value] = value2
        end
    else -- num, castBy
        if customIndicators["buff"][indicatorName] then
            customIndicators["buff"][indicatorName][setting] = value
        elseif customIndicators["debuff"][indicatorName] then
            customIndicators["debuff"][indicatorName][setting] = value
        end
    end
end
Cell.RegisterCallback("UpdateIndicators", "UpdateCustomIndicators", UpdateCustomIndicators)

-------------------------------------------------
-- reset
-------------------------------------------------
function I.ResetCustomIndicators(unitButton, auraType)
    local unit = F.BD(unitButton).states.displayedUnit

    for indicatorName, indicatorTable in pairs(customIndicators[auraType]) do
        if enabledIndicators[indicatorName] and F.BD(unitButton).indicators[indicatorName]
            and not (I.ShouldSkipLegacyHealers and I.ShouldSkipLegacyHealers(indicatorTable))
            and not (I.ShouldSkipLegacyCustom and I.ShouldSkipLegacyCustom(indicatorTable)) then
            F.BD(unitButton).indicators[indicatorName]:Hide(true)
            if indicatorTable["num"] then
                if not indicatorTable["found"][unit] then
                    indicatorTable["found"][unit] = {}
                else
                    wipe(indicatorTable["found"][unit])
                end
            else
                indicatorTable["topOrder"][unit] = 999
                if not indicatorTable["top"][unit] then
                    indicatorTable["top"][unit] = {}
                else
                    wipe(indicatorTable["top"][unit])
                end
            end
        end
    end
end

-------------------------------------------------
-- update
-------------------------------------------------
local DEFAULT_HASCOLOR_COLOR = {1, 1, 1, 1}

local function ResolveAuraEntry(indicatorTable, spell)
    local auras = indicatorTable["auras"]
    local entry = auras and auras[spell]
    if entry == nil and auras then
        entry = auras[0]
    end
    return entry
end

local function Update(indicator, indicatorTable, unit, spell, start, duration, debuffType, icon, count, refreshing)
    local entry = ResolveAuraEntry(indicatorTable, spell)
    if entry == nil then return end

    local order, color
    if type(entry) == "table" then
        order, color = entry[1] or 999, entry[2]
    else
        order = entry
    end

    if indicatorTable["num"] then
        if indicatorTable["hasColor"] then
            tinsert(indicatorTable["found"][unit], {order, start, duration, debuffType, icon, count, refreshing, color})
        else
            tinsert(indicatorTable["found"][unit], {order, start, duration, debuffType, icon, count, refreshing})
        end
    else
        if order < (indicatorTable["topOrder"][unit] or 999) then
            indicatorTable["topOrder"][unit] = order
            indicatorTable["top"][unit]["start"] = start
            indicatorTable["top"][unit]["duration"] = duration
            indicatorTable["top"][unit]["debuffType"] = debuffType
            indicatorTable["top"][unit]["texture"] = icon
            indicatorTable["top"][unit]["count"] = count
            indicatorTable["top"][unit]["refreshing"] = refreshing
            -- always (re)assign when hasColor, otherwise a new top aura without its own color keeps the previous one's
            if indicatorTable["hasColor"] then
                indicatorTable["top"][unit]["color"] = color or DEFAULT_HASCOLOR_COLOR
            end
        end
    end
end

function I.UpdateCustomIndicators(unitButton, auraInfo, auraTypeOverride)
    local unit = F.BD(unitButton).states.displayedUnit

    local auraType = auraTypeOverride
    if not auraType then
        if not F.IsValueNonSecret(auraInfo.isHelpful) then return end
        auraType = auraInfo.isHelpful and "buff" or "debuff"
    end

    -- Early exit: no custom indicators of this type are configured.
    -- Avoids pairs() call + loop overhead called per-aura per event.
    local indicators = customIndicators[auraType]
    if not indicators or not next(indicators) then return end

    local icon = auraInfo.icon
    local rawDispelName = auraInfo.dispelName
    local debuffType = auraInfo.isHarmful and ((rawDispelName and F.IsValueNonSecret(rawDispelName)) and rawDispelName or "") or nil
    local count = auraInfo.applications
    local duration = auraInfo.duration
    local start
    if F.IsAuraNonSecret(auraInfo) then
        start = (auraInfo.expirationTime or 0) - auraInfo.duration
    else
        start = 0
        duration = 0
    end
    local sourceUnit = auraInfo.sourceUnit

    if auraInfo.isHarmful then
        debuffType = I.CheckDebuffType(debuffType, auraInfo.spellId)
    end

    -- Dedup: first pass collects which spells are tracked by non-Healers custom
    -- indicators, so the Healers indicator can skip them in pass 2.
    local consumedSpell

    -- Pass 1: mark spell as consumed if any non-Healers indicator would match
    for indicatorName, indicatorTable in pairs(customIndicators[auraType]) do
        if indicatorName and enabledIndicators[indicatorName] and F.BD(unitButton).indicators[indicatorName]
            and indicatorTable["name"] ~= "Healers"
            and not indicatorTable["keepInHealers"] then
            local spell = indicatorTable["trackByName"] and auraInfo.name or auraInfo.spellId
            local matchedAura = spell and F.IsValueNonSecret(spell) and indicatorTable["auras"][spell]
            if not matchedAura and not indicatorTable["trackByName"] and Cell.isMidnight
                and not F.IsValueNonSecret(auraInfo.spellId)
                and auraInfo.name and F.IsValueNonSecret(auraInfo.name) then
                matchedAura = indicatorTable["_nameLookup"] and indicatorTable["_nameLookup"][auraInfo.name]
                if matchedAura then spell = auraInfo.name end
            end
                if matchedAura then
                    -- check caster
                    local castBy = indicatorTable["castBy"]
                    local castByMatches = castBy == "anyone"
                    if not castByMatches and F.IsValueNonSecret(sourceUnit) then
                        local castByMe = sourceUnit == "player" or sourceUnit == "pet"
                        castByMatches = (castBy == "me" and castByMe) or (castBy == "others" and not castByMe)
                    elseif not castByMatches and F.IsValueNonSecret(auraInfo.isFromPlayerOrPlayerPet) then
                        local fromPlayer = auraInfo.isFromPlayerOrPlayerPet
                        castByMatches = (castBy == "me" and fromPlayer) or (castBy == "others" and not fromPlayer)
                    end
                    if castByMatches then
                        consumedSpell = spell
                        break
                    end
                end
        end
    end

    -- Pass 2: process all indicators (Healers skips consumed spells)
    for indicatorName, indicatorTable in pairs(customIndicators[auraType]) do
        if indicatorName and enabledIndicators[indicatorName] and F.BD(unitButton).indicators[indicatorName]
            and not (I.ShouldSkipLegacyHealers and I.ShouldSkipLegacyHealers(indicatorTable))
            and not (I.ShouldSkipLegacyCustom and I.ShouldSkipLegacyCustom(indicatorTable)) then
            local spell  --* trackByName
            if indicatorTable["trackByName"] then
                spell = auraInfo.name
            else
                spell = auraInfo.spellId
            end

            if indicatorTable["name"] == "Healers" and consumedSpell and F.IsValueNonSecret(spell)
                and consumedSpell == spell then
            else
                local matchedAura = spell and F.IsValueNonSecret(spell) and indicatorTable["auras"][spell]
                if not matchedAura and not indicatorTable["trackByName"] and Cell.isMidnight
                    and not F.IsValueNonSecret(auraInfo.spellId)
                    and auraInfo.name and F.IsValueNonSecret(auraInfo.name) then
                    matchedAura = indicatorTable["_nameLookup"] and indicatorTable["_nameLookup"][auraInfo.name]
                    if matchedAura then spell = auraInfo.name end
                end
                if matchedAura or (indicatorTable["auras"][0] and (duration ~= 0 or auraInfo._hasSecrets)) then -- is in indicator spell list
                    -- check caster
                    local castBy = indicatorTable["castBy"]
                    local castByMatches = castBy == "anyone"
                    if not castByMatches and F.IsValueNonSecret(sourceUnit) then
                        local castByMe = sourceUnit == "player" or sourceUnit == "pet"
                        castByMatches = (castBy == "me" and castByMe) or (castBy == "others" and not castByMe)
                    elseif not castByMatches and F.IsValueNonSecret(auraInfo.isFromPlayerOrPlayerPet) then
                        local fromPlayer = auraInfo.isFromPlayerOrPlayerPet
                        castByMatches = (castBy == "me" and fromPlayer) or (castBy == "others" and not fromPlayer)
                    end
                    if castByMatches then
                        if auraType == "buff" then
                            Update(F.BD(unitButton).indicators[indicatorName], indicatorTable, unit, spell, start, duration, debuffType, icon, count, auraInfo.refreshing)
                        else -- debuff
                            Update(F.BD(unitButton).indicators[indicatorName], indicatorTable, unit, spell, start, duration, debuffType, icon, count, auraInfo.refreshing)
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------
-- show
-------------------------------------------------
local sort = table.sort
local function comparator(a, b)
    if not a then return false end
    if not b then return true end
    if a[1] and b[1] then
        return a[1] < b[1]
    end
    return (a[2] or 0) <= (b[2] or 0)
end

function I.ShowCustomIndicators(unitButton, auraType)
    if not F.BD(unitButton)._indicatorsReady then return end

    local unit = F.BD(unitButton).states.displayedUnit
    for indicatorName, indicatorTable in pairs(customIndicators[auraType]) do
        local indicator = F.BD(unitButton).indicators[indicatorName]
        if indicator and enabledIndicators[indicatorName]
            and not (I.ShouldSkipLegacyHealers and I.ShouldSkipLegacyHealers(indicatorTable))
            and not (I.ShouldSkipLegacyCustom and I.ShouldSkipLegacyCustom(indicatorTable)) then
            if indicatorTable["num"] then
                local t = indicatorTable["found"][unit]
                if t and t[1] then
                    sort(t, comparator)
                    for i = 1, indicatorTable["num"] do
                        if not t[i] then break end
                        -- 1:order, 2:start, 3:duration, 4:debuffType, 5:icon, 6:count, 7:refreshing, 8:color
                        indicator[i]:SetCooldown(t[i][2], t[i][3], t[i][4], t[i][5], t[i][6], t[i][7], t[i][8])
                    end
                    indicator:Show()
                    indicator:UpdateSize()
                end
            else
                if indicatorTable["top"][unit] and indicatorTable["top"][unit]["start"] then
                    indicator:SetCooldown(
                        indicatorTable["top"][unit]["start"],
                        indicatorTable["top"][unit]["duration"],
                        indicatorTable["top"][unit]["debuffType"],
                        indicatorTable["top"][unit]["texture"],
                        indicatorTable["top"][unit]["count"],
                        indicatorTable["top"][unit]["refreshing"],
                        indicatorTable["top"][unit]["color"]
                    )
                end
            end
        end
    end
end
