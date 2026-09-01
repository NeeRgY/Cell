local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs
local LCG = LibStub("LibCustomGlow-1.0")

--[[
    Targeted Spells
]]

local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitClass = UnitClass
local UnitRace = UnitRace
local UnitSex = UnitSex
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetTime = GetTime
local C_Spell = C_Spell
local issecret = issecretvalue or function() return false end

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local PICKUP_DELAY = 0.1
local VERIFY_DELAY = 0.15
local RETARGET_DELAY = 0.05

local maxIcons = 1
local showAllSpells = false
--! Classic only: single on/off glow toggle, auto-scaled Pixel glow instead of Retail's type/color picker
local classicGlowEnabled = false
--! Retail: "None"/"Icons" only, glow display was disabled for stability. Classic also has "Border"/"Both".
local displayMode = "Icons"
local enabled = false
local SWIPE_COLOR = { 0.95, 0.95, 0.32, 1 }
local targetedSpellsByName = {}


local eventFrame = CreateFrame("Frame")
eventFrame:Hide()

-- cast tracking
local casts = {} -- sourceUnit -> castInfo
local castsOnUnit, sortedCastsOnUnit = {}, {}
local gen = {} -- sourceUnit -> generation (stale timer guard)
local plateTokens = {}

local rosterByClass = {}
local rosterRole, rosterRace, rosterSex = {}, {}, {}
local lastRosterSync = 0
local matchBuf = {}

local function WipeCastTables()
    wipe(casts)
    wipe(castsOnUnit)
    wipe(sortedCastsOnUnit)
    wipe(gen)
end

local function IsPartyContext()
    if IsInRaid() then return false end
    return true -- solo + party
end

-------------------------------------------------
-- roster / classify
-------------------------------------------------
local function RebuildRoster()
    wipe(rosterByClass)
    wipe(rosterRole)
    wipe(rosterRace)
    wipe(rosterSex)
    for i = 1, #PARTY_UNITS do
        local u = PARTY_UNITS[i]
        local ex = UnitExists(u)
        if not issecret(ex) and ex == true then
            local _, token = UnitClass(u)
            if not issecret(token) and type(token) == "string" then
                local list = rosterByClass[token]
                if not list then
                    list = {}
                    rosterByClass[token] = list
                end
                list[#list + 1] = u
            end
            local role = UnitGroupRolesAssigned(u)
            if not issecret(role) and type(role) == "string" and role ~= "NONE" then
                rosterRole[u] = role
            end
            local _, raceToken = UnitRace(u)
            if not issecret(raceToken) and type(raceToken) == "string" then
                rosterRace[u] = raceToken
            end
            local sex = UnitSex(u)
            if not issecret(sex) and type(sex) == "number" then
                rosterSex[u] = sex
            end
        end
    end
    lastRosterSync = GetTime()
end

local function Narrow(targetVal, rosterMap)
    if targetVal == nil or #matchBuf <= 1 then return end
    local exact = 0
    for i = 1, #matchBuf do
        if rosterMap[matchBuf[i]] == targetVal then
            exact = exact + 1
        end
    end
    if exact == 0 then return end
    for i = #matchBuf, 1, -1 do
        if rosterMap[matchBuf[i]] ~= targetVal then
            tremove(matchBuf, i)
        end
    end
end

local function Classify(caster)
    local tgt = caster .. "target"
    local _, cls = UnitClass(tgt)
    if issecret(cls) or type(cls) ~= "string" then return nil end

    wipe(matchBuf)
    local cands = rosterByClass[cls]
    if cands then
        for i = 1, #cands do
            matchBuf[i] = cands[i]
        end
    end
    if #matchBuf == 0 then
        if GetTime() - lastRosterSync > 1 then
            RebuildRoster()
            cands = rosterByClass[cls]
            if cands then
                for i = 1, #cands do
                    matchBuf[i] = cands[i]
                end
            end
        end
        if #matchBuf == 0 then return nil end
    end

    local role = UnitGroupRolesAssigned(tgt)
    if issecret(role) or role == "NONE" then role = nil end
    Narrow(role, rosterRole)

    local okR, _, raceToken = pcall(UnitRace, tgt)
    if not okR or issecret(raceToken) or type(raceToken) ~= "string" then
        raceToken = nil
    end
    Narrow(raceToken, rosterRace)

    local okS, sex = pcall(UnitSex, tgt)
    if not okS or issecret(sex) or type(sex) ~= "number" then
        sex = nil
    end
    Narrow(sex, rosterSex)

    if #matchBuf ~= 1 then return nil end
    return matchBuf[1]
end

-------------------------------------------------
-- show / hide (Cell visuals)
-------------------------------------------------
local function GetGlowOptions()
    local glow = Cell.vars and Cell.vars.targetedSpellsGlow
    if type(glow) ~= "table" or not glow[1] or glow[1] == "None" then
        return I.GetDefaultTargetedSpellsGlow()
    end
    return glow
end

local function GetSwipeColor()
    local glow = GetGlowOptions()
    if type(glow[2]) == "table" then
        return glow[2]
    end
    return SWIPE_COLOR
end

--! tsGlowFrame is always created up front now (I.CreateTargetedSpells), so this just shows it.
local function EnsureTsGlowFrame(frame)
    local glowFrame = frame.tsGlowFrame
    if glowFrame then
        glowFrame:Show()
        glowFrame:SetAlpha(1)
    end
    return glowFrame
end

local function HideCasts(b)
    local ts = F.BD(b).indicators and F.BD(b).indicators.targetedSpells
    if not ts then return end
    ts:UpdateSize(0)
    ts:HideGlow()
    EnsureTsGlowFrame(ts)
end

local function ShowCasts(b, showGlow, sortedCasts, num)
    local ts = F.BD(b).indicators and F.BD(b).indicators.targetedSpells
    if not ts then return end

    ts:Show()

    if displayMode == "None" then
        ts:UpdateSize(0)
        ts:HideGlow()
        return
    end

    --! Classic only: "Border" shows glow with no icons at all.
    if not Cell.isRetail and displayMode == "Border" then
        ts:UpdateSize(0)
    else
        num = min(maxIcons, num)
        for i = 1, num do
            local cast = sortedCasts[i]
            ts[i].cooldown:SetReverse(not cast.isChanneling)
            ts[i]:SetCooldown(cast.startTime, cast.endTime - cast.startTime, cast.icon, cast.count)
        end
        ts:UpdateSize(num)
    end

    --! Classic only: glow when enabled, in "Border"/"Both" mode, with at least one real cast.
    if not Cell.isRetail and classicGlowEnabled and displayMode ~= "Icons" and sortedCasts[1] then
        EnsureTsGlowFrame(ts)
        ts:ShowGlow()
    else
        ts:HideGlow()
    end
end

local function GetCastsOnUnit(targetUnit)
    if castsOnUnit[targetUnit] then
        wipe(castsOnUnit[targetUnit])
        wipe(sortedCastsOnUnit[targetUnit])
    else
        castsOnUnit[targetUnit] = {}
        sortedCastsOnUnit[targetUnit] = {}
    end

    local castIndex = 0
    local inListFound
    local now = GetTime()
    for sourceKey, castInfo in pairs(casts) do
        if targetUnit == castInfo.targetUnit then
            if castInfo.endTime > now then
                castIndex = castIndex + 1
                local key = castInfo.nonSecretSpellId or castIndex
                local bucket = castsOnUnit[targetUnit][key]
                if not bucket then
                    bucket = { count = 0 }
                    castsOnUnit[targetUnit][key] = bucket
                end
                if not bucket.endTime or bucket.endTime > castInfo.endTime then
                    bucket.startTime = castInfo.startTime
                    bucket.endTime = castInfo.endTime
                    bucket.icon = castInfo.icon
                    bucket.isChanneling = castInfo.isChanneling
                    bucket.inList = castInfo.inList
                end
                bucket.count = bucket.count + 1
                if castInfo.inList then
                    bucket.inList = true
                    inListFound = true
                end
            else
                casts[sourceKey] = nil
            end
        end
    end
    return castsOnUnit[targetUnit], inListFound
end

local function Comparator(a, b)
    if a.inList ~= b.inList then
        return a.inList
    end
    return a.startTime < b.startTime
end

local function UpdateCastsOnUnit(targetUnit)
    if not targetUnit then return end
    local t, showGlow = GetCastsOnUnit(targetUnit)
    for _, castInfo in pairs(t) do
        tinsert(sortedCastsOnUnit[targetUnit], castInfo)
    end
    local n = #sortedCastsOnUnit[targetUnit]
    if n == 0 then
        F.HandleUnitButton("unit", targetUnit, HideCasts)
    else
        table.sort(sortedCastsOnUnit[targetUnit], Comparator)
        F.HandleUnitButton("unit", targetUnit, ShowCasts, showGlow, sortedCastsOnUnit[targetUnit], n)
    end
end

local function HideAll()
    F.IterateAllUnitButtons(HideCasts, true)
end

local function RefreshAllShown()
    local seen = {}
    for _, castInfo in pairs(casts) do
        local u = castInfo.targetUnit
        if u and not seen[u] then
            seen[u] = true
            UpdateCastsOnUnit(u)
        end
    end
end

-------------------------------------------------
-- cast resolve
-------------------------------------------------
local function RebuildNameIndex()
    wipe(targetedSpellsByName)
    local list = Cell.vars and Cell.vars.targetedSpellsList
    if type(list) ~= "table" then return end
    for spellId in pairs(list) do
        if type(spellId) == "number" then
            local name = F.GetSpellInfo and F.GetSpellInfo(spellId)
            if type(name) == "string" and name ~= "" then
                targetedSpellsByName[name] = spellId
            end
        end
    end
end

local function ShouldTrackSpell(spellId, castName)
    local nonSecretId = (spellId ~= nil and F.IsValueNonSecret(spellId)) and spellId or nil
    local nonSecretName = (type(castName) == "string" and F.IsValueNonSecret(castName)) and castName or nil

    local list = Cell.vars and Cell.vars.targetedSpellsList
    local inList = false
    local resolvedId = nonSecretId

    if nonSecretId and list and list[nonSecretId] then
        inList = true
    elseif nonSecretName and targetedSpellsByName[nonSecretName] then
        inList = true
        resolvedId = resolvedId or targetedSpellsByName[nonSecretName]
    elseif not nonSecretId and not nonSecretName then
        if displayMode == "None" then
            return false, false, nil
        end
        return true, true, nil
    end

    if inList then
        return true, true, resolvedId
    end
    if showAllSpells then
        return true, false, resolvedId
    end
    if displayMode == "Icons" then
        if C_Spell and C_Spell.IsSpellImportant and spellId ~= nil then
            local important = C_Spell.IsSpellImportant(spellId)
            if not F.IsValueNonSecret(important) or important then
                return true, true, resolvedId
            end
        end
        return false, false, resolvedId
    end
    if displayMode == "Border" or displayMode == "Both" then
        return true, false, resolvedId
    end
    return false, false, resolvedId
end

local function Resolve(sourceUnit, myGen)
    if not enabled or not IsPartyContext() then return end
    if gen[sourceUnit] ~= myGen then return end

    local name, _, texture, startMS, endMS, _, _, _, spellId = UnitCastingInfo(sourceUnit)
    local isChanneling = false
    if type(name) == "nil" then
        name, _, texture, startMS, endMS, _, _, spellId = UnitChannelInfo(sourceUnit)
        isChanneling = true
    end
    if type(name) == "nil" then return end

    local shouldTrack, inList, nonSecretSpellId = ShouldTrackSpell(spellId, name)
    if not shouldTrack then return end

    if Cell.isMidnight and C_Spell and C_Spell.GetSpellTexture and nonSecretSpellId then
        local tex = C_Spell.GetSpellTexture(nonSecretSpellId)
        if tex then texture = tex end
    elseif Cell.isMidnight and C_Spell and C_Spell.GetSpellTexture and spellId and F.IsValueNonSecret(spellId) then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then texture = tex end
    end

    local startTime, endTime
    if F.IsValueNonSecret(startMS) and F.IsValueNonSecret(endMS) then
        startTime = startMS / 1000
        endTime = endMS / 1000
    else
        startTime = GetTime()
        endTime = GetTime() + 3
    end

    local previousTarget = casts[sourceUnit] and casts[sourceUnit].targetUnit
    if GetTime() - lastRosterSync > 2 then
        RebuildRoster()
    end
    local targetUnit = Classify(sourceUnit)

    if not targetUnit then
        if casts[sourceUnit] then
            casts[sourceUnit] = nil
            if previousTarget then
                UpdateCastsOnUnit(previousTarget)
            end
        end
        return
    end

    casts[sourceUnit] = {
        startTime = startTime,
        endTime = endTime,
        spellId = spellId,
        nonSecretSpellId = nonSecretSpellId,
        icon = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
        isChanneling = isChanneling,
        inList = inList,
        sourceUnit = sourceUnit,
        targetUnit = targetUnit,
        nonNameplate = not strfind(sourceUnit, "^nameplate"),
    }

    if previousTarget and previousTarget ~= targetUnit then
        UpdateCastsOnUnit(previousTarget)
    end
    UpdateCastsOnUnit(targetUnit)
end

local function OnCastStart(sourceUnit)
    if not enabled or not IsPartyContext() then return end
    if type(sourceUnit) ~= "string" then return end

    local hostile = UnitCanAttack("player", sourceUnit)
    if not issecret(hostile) and hostile ~= true then return end

    gen[sourceUnit] = (gen[sourceUnit] or 0) + 1
    local myGen = gen[sourceUnit]
    local prev = casts[sourceUnit]
    if prev then
        local previousTarget = prev.targetUnit
        casts[sourceUnit] = nil
        if previousTarget then
            UpdateCastsOnUnit(previousTarget)
        end
    end

    C_Timer.After(PICKUP_DELAY, function()
        Resolve(sourceUnit, myGen)
    end)
    C_Timer.After(PICKUP_DELAY + VERIFY_DELAY, function()
        Resolve(sourceUnit, myGen)
    end)
end

local function OnCastStop(sourceUnit)
    if not sourceUnit then return end
    gen[sourceUnit] = (gen[sourceUnit] or 0) + 1
    local prev = casts[sourceUnit]
    if not prev then return end
    local previousTarget = prev.targetUnit
    casts[sourceUnit] = nil
    if previousTarget then
        UpdateCastsOnUnit(previousTarget)
    end
end

local function OnRetarget(sourceUnit)
    if not enabled or not IsPartyContext() then return end
    if not casts[sourceUnit] and not plateTokens[sourceUnit] then return end
    gen[sourceUnit] = (gen[sourceUnit] or 0) + 1
    local myGen = gen[sourceUnit]
    C_Timer.After(RETARGET_DELAY, function()
        Resolve(sourceUnit, myGen)
    end)
    C_Timer.After(RETARGET_DELAY + VERIFY_DELAY, function()
        Resolve(sourceUnit, myGen)
    end)
end

local function ClearEverything()
    WipeCastTables()
    HideAll()
end

local function AdoptPlateCast(unit)
    local castName = UnitCastingInfo(unit)
    if type(castName) == "nil" then
        castName = UnitChannelInfo(unit)
    end
    if type(castName) ~= "nil" then
        OnCastStart(unit)
    end
end

-------------------------------------------------
-- events
-------------------------------------------------
eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
        ClearEverything()
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if not IsPartyContext() then
            ClearEverything()
            return
        end
        RebuildRoster()
        return
    end

    if not enabled or not IsPartyContext() then return end

    if event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) == "string" then
            plateTokens[unit] = true
            AdoptPlateCast(unit)
        end
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" then
            plateTokens[unit] = nil
            local cast = casts[unit]
            if cast and not cast.nonNameplate then
                OnCastStop(unit)
            end
        end
        return
    end

    if unit and strfind(unit, "^soft") then return end

    local isPlate = unit and plateTokens[unit]
    local isTarget = unit == "target"

    if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START"
    then
        if isPlate or isTarget then
            OnCastStart(unit)
        end
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP"
    then
        if isPlate or isTarget or casts[unit] then
            OnCastStop(unit)
        end
    elseif event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE"
    then
        if casts[unit] then
            OnRetarget(unit)
        end
    elseif event == "UNIT_TARGET" then
        if casts[unit] or isPlate then
            OnRetarget(unit)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        AdoptPlateCast("target")
    end
end)

-------------------------------------------------
-- create (Cell look)
-------------------------------------------------
local function SetCooldown(frame, start, duration, icon, count)
    frame.duration:Hide()

    if count ~= 1 then
        frame.stack:Show()
        frame.stack:SetText(count)
    else
        frame.stack:Hide()
    end

    frame.border:Show()
    frame.cooldown:Show()
    frame.cooldown:SetSwipeColor(unpack(GetSwipeColor()))
    frame.cooldown:SetCooldown(start, duration)
    frame.icon:SetTexture(icon)
    frame:Show()
end

local function SetFont(frame, ...)
    for i = 1, #frame do
        I.SetFont(frame[i].stack, frame[i], ...)
    end
end

local function IgnoreGlowParentAlpha(glowFrame)
    if not glowFrame then return end
    for _, suffix in ipairs({ "_PixelGlow", "_ButtonGlow", "_AutoCastGlow", "_ProcGlow" }) do
        local child = glowFrame[suffix]
        if child then
            child:SetIgnoreParentAlpha(true)
        end
    end
end

--! LibCustomGlow-1.0 doesn't nil its tracking field after Release, so a later Stop can try to release
--! an already-released object and get stuck - same bug fixed for Raid Debuffs.
local function HideGlow(frame)
    local glowFrame = frame.tsGlowFrame
    if not glowFrame then return end
    pcall(LCG.ButtonGlow_Stop, glowFrame)
    pcall(LCG.PixelGlow_Stop, glowFrame)
    pcall(LCG.AutoCastGlow_Stop, glowFrame)
    pcall(LCG.ProcGlow_Stop, glowFrame)
    glowFrame._ButtonGlow = nil
    glowFrame._PixelGlow = nil
    glowFrame._AutoCastGlow = nil
    glowFrame._ProcGlow = nil
end

--! Retail keeps this a no-op stub; Classic gets a single fixed, auto-scaled Pixel glow.
local function ShowGlow(frame)
    if Cell.isRetail then
        HideGlow(frame)
        return
    end
    local glowFrame = frame.tsGlowFrame
    if not glowFrame then return end
    HideGlow(frame)
    LCG.PixelGlow_Start(glowFrame, nil, nil, nil, nil, nil, 2, 2)
end

local function ShowPreview(frame)
    frame:Show()

    if displayMode == "None" then
        for i = 1, #frame do
            frame[i]:Hide()
        end
        frame:UpdateSize(0)
        frame:HideGlow()
        return
    end

    if not Cell.isRetail and displayMode == "Border" then
        for i = 1, #frame do
            frame[i]:Hide()
        end
        frame:UpdateSize(0)
    else
        local num = min(maxIcons or 1, #frame)
        for i = 1, num do
            frame[i]:Show()
        end
        frame:UpdateSize(num)
    end

    if not Cell.isRetail and classicGlowEnabled and displayMode ~= "Icons" then
        EnsureTsGlowFrame(frame)
        frame:ShowGlow()
    else
        frame:HideGlow()
    end
end

local function HidePreview(frame)
    for i = 1, #frame do
        frame[i]:Hide()
    end
    frame:UpdateSize(0)
    frame:HideGlow()
end

function I.CreateTargetedSpells(parent)
    local targetedSpells = CreateFrame("Frame", parent:GetName().."TargetedSpellsParent", F.BD(parent).widgets.indicatorFrame)
    F.BD(parent).indicators.targetedSpells = targetedSpells
    targetedSpells:Hide()

    --! the settings preview button is built differently and never gets a tsGlowFrame otherwise
    if not F.BD(parent).widgets.tsGlowFrame then
        local glowFrame = CreateFrame("Frame", parent:GetName().."TSGlowFrame", parent)
        F.BD(parent).widgets.tsGlowFrame = glowFrame
        glowFrame:SetFrameLevel(parent:GetFrameLevel() + 200)
        glowFrame:SetAllPoints(parent)
        glowFrame:Hide()
    end
    targetedSpells.tsGlowFrame = F.BD(parent).widgets.tsGlowFrame
    targetedSpells._SetSize = targetedSpells.SetSize
    targetedSpells.SetSize = I.Cooldowns_SetSize
    targetedSpells.SetBorder = I.Cooldowns_SetBorder
    targetedSpells.UpdateSize = I.Cooldowns_UpdateSize_WithSpacing
    targetedSpells.SetOrientation = I.Cooldowns_SetOrientation_WithSpacing
    targetedSpells.SetFont = SetFont
    targetedSpells.ShowGlow = ShowGlow
    targetedSpells.HideGlow = HideGlow
    targetedSpells.SetCooldownStyle = I.Cooldowns_SetCooldownStyle
    targetedSpells.ShowGlowPreview = ShowPreview
    targetedSpells.HideGlowPreview = HidePreview

    for i = 1, 3 do
        local frame = I.CreateAura_BorderIcon(parent:GetName().."TargetedSpells"..i, targetedSpells, 2)
        tinsert(targetedSpells, frame)
        frame.SetCooldown = SetCooldown
        frame.cooldown:SetScript("OnCooldownDone", function()
            frame:Hide()
        end)
    end
end

-------------------------------------------------
-- enable / config
-------------------------------------------------
local function RegisterEvents()
    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    eventFrame:RegisterEvent("UNIT_TARGET")
    if Cell.isRetail then
        eventFrame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
        eventFrame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
        eventFrame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE")
    end
    eventFrame:Show()
end

function I.EnableTargetedSpells(enable)
    enabled = not not enable
    ClearEverything()
    wipe(plateTokens)

    if not enabled then
        eventFrame:Hide()
        eventFrame:UnregisterAllEvents()
        F.IterateAllUnitButtons(function(b)
            local ts = F.BD(b).indicators and F.BD(b).indicators.targetedSpells
            if ts then
                ts:HideGlow()
                ts:Hide()
            end
        end, true)
        return
    end

    RebuildNameIndex()
    RegisterEvents()
    F.IterateAllUnitButtons(function(b)
        local ts = F.BD(b).indicators and F.BD(b).indicators.targetedSpells
        if ts then
            ts:Show()
        end
    end, true)

    if IsPartyContext() then
        RebuildRoster()
        if C_NamePlate and C_NamePlate.GetNamePlates then
            local plates = C_NamePlate.GetNamePlates()
            if type(plates) == "table" then
                for i = 1, #plates do
                    local plate = plates[i]
                    local u = plate and plate.namePlateUnitToken
                    if type(u) == "string" then
                        plateTokens[u] = true
                        AdoptPlateCast(u)
                    end
                end
            end
        end
        AdoptPlateCast("target")
    end
end

function I.ShowAllTargetedSpells(showAll)
    showAllSpells = showAll
end

--! Classic only.
function I.SetTargetedSpellsGlowEnabled(glowEnabled)
    classicGlowEnabled = not not glowEnabled
    RefreshAllShown()
    --! RefreshAllShown doesn't touch the settings preview button, nudge it directly too
    if CellIndicatorsPreviewButton then
        local ts = F.BD(CellIndicatorsPreviewButton).indicators.targetedSpells
        if ts then ts:ShowGlowPreview() end
    end
end

function I.RefreshTargetedSpellsList()
    RebuildNameIndex()
end

function I.UpdateTargetedSpellsNum(num)
    maxIcons = num or 1
    RefreshAllShown()
end

function I.UpdateTargetedSpellsDisplayMode(mode)
    if Cell.isRetail and (mode == "Border" or mode == "Both") then
        --! Retail: border/glow display stays disabled (see comment on `displayMode` above).
        mode = "Icons"
    end
    if mode == "None" or mode == "Icons" or (not Cell.isRetail and (mode == "Border" or mode == "Both")) then
        displayMode = mode
    else
        displayMode = "Icons"
    end
    local seen = {}
    for _, castInfo in pairs(casts) do
        local u = castInfo.targetUnit
        if u and not seen[u] then
            seen[u] = true
            UpdateCastsOnUnit(u)
        end
    end
end
