local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs

--[[
    Ping Icon (Retail only)

    Mirrors Blizzard's own raid/party-frame ping marker (Attack/Warning/OnMyWay/...) onto Cell's
    unit buttons. The events that actually drive a ping (UNIT_PING_PIN_ADDED/_REMOVED) are
    protected -- an addon RegisterEvent on them is ADDON_ACTION_FORBIDDEN, and the icon
    template/mixin that consumes them lives in a forbidden scope too, so this can never listen
    for the ping directly or build one of Blizzard's own icons.

    What IS reachable: Blizzard already builds a ping-icon child frame (`.pingIconFrame`) into
    every one of its own (hidden) compact unit frames, and that object's ShowPing/ClearPing
    methods are ordinary, non-forbidden functions -- hooksecurefunc on them fires with the
    ping's texture kit. Blizzard resolves the protected event to a unit for us internally; this
    only ever reads the icon's owner frame's `.unit` (a plain field, not a secure attribute) and
    mirrors onto whichever Cell button(s) currently show that same unit.

    Two things this depends on:
      * Blizzard's own hidden compact frames must keep receiving events, so HideBlizzard.lua
        skips its event-stripping step on the affected frames while Ping Icon is enabled
        (concealment via alpha/mouse still applies -- only the event strip backs off). Turning
        it on after events were already stripped needs a /reload; there is no clean way to
        restore just the events Blizzard originally registered.
      * The "showPingsOnRaidFrames" CVar must be on -- Blizzard's own handler returns before
        ShowPing ever runs otherwise.
]]

local INDICATOR_NAME = "pingIcon"
local PING_CVAR = "showPingsOnRaidFrames"
local SAFETY_EXPIRE = 20 -- seconds; covers a missed ClearPing if a frame/unit is recycled

local function GetConfig()
    local layoutTable = Cell.vars.currentLayoutTable
    if not (layoutTable and layoutTable.indicators) then return nil end
    for _, t in pairs(layoutTable.indicators) do
        if t.indicatorName == INDICATOR_NAME then
            return t
        end
    end
    return nil
end

local UnitGUID = UnitGUID
local UnitIsUnit = UnitIsUnit
local UnitExists = UnitExists

local enabled = false

-- Confirmed-working kit (a real self-ping uses it) -- used to give the settings-panel preview
-- something to show without needing an actual ping to fire.
local PREVIEW_KIT = "NonThreat"

-- SetAtlas() on an unknown atlas name does NOT error -- it just silently sets nothing, so a
-- pcall around it reports "success" even when nothing became visible. Checking GetAtlasInfo
-- first is the only reliable way to know whether the atlas actually exists on this client
-- (different clients/builds -- e.g. WoW Forever -- may not ship the same "Ping_Frame_*" atlases
-- Retail does).
local GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo

-- Bundled fallback icons (Media/Ping/*.png) for clients that don't ship Blizzard's own
-- "Ping_Frame_*" atlases (confirmed missing on WoW Forever). These are complete standalone
-- icons, not a separate background+glyph pair, so only pingIcon.glyph is used for them.
local PING_ICON_FOLDER = "Interface\\AddOns\\Cell\\Media\\Ping\\"
local KIT_IMAGE_MAP = {
    -- confirmed real kit for the default ping (Nucleus/DandersFrames both found this one working)
    ["nonthreat"] = "Default",
    ["default"] = "Default",
    ["standard"] = "Default",
    ["attack"] = "Attack",
    ["assist"] = "Assist",
    ["help"] = "Assist",
    ["warning"] = "Warning",
    ["danger"] = "Warning",
    ["alert"] = "Warning",
    ["onmyway"] = "OnMyWay",
    ["coming"] = "OnMyWay",
}

local function CustomImageForKit(kit)
    local norm = kit:lower():gsub("[%s_%-]", "")
    return KIT_IMAGE_MAP[norm]
end

local function SetKitTexture(pingIcon, kit)
    local bgAtlas, glyphAtlas = "Ping_Frame_BG_" .. kit, "Ping_Frame_" .. kit
    local hasBg = GetAtlasInfo and GetAtlasInfo(bgAtlas) ~= nil
    local hasGlyph = GetAtlasInfo and GetAtlasInfo(glyphAtlas) ~= nil

    if hasBg then
        pcall(pingIcon.bg.SetAtlas, pingIcon.bg, bgAtlas, true)
    else
        pingIcon.bg:SetTexture(nil)
    end

    if hasGlyph then
        pcall(pingIcon.glyph.SetAtlas, pingIcon.glyph, glyphAtlas, true)
        pingIcon.glyph:SetVertexColor(1, 1, 1, 1) -- reset in case a prior unknown kit tinted it
        return
    end

    local customImage = CustomImageForKit(kit)
    if customImage then
        pingIcon.glyph:SetTexture(PING_ICON_FOLDER .. customImage)
        pingIcon.glyph:SetVertexColor(1, 1, 1, 1)
        return
    end

    -- Truly unknown kit (e.g. a spell/resource ping, or a type this client's atlas and our
    -- own map both miss): fall back to the standard ping icon rather than showing nothing.
    pingIcon.glyph:SetTexture(PING_ICON_FOLDER .. "Default")
    pingIcon.glyph:SetVertexColor(1, 1, 1, 1)
end

-------------------------------------------------
-- per-button icon
-------------------------------------------------
function I.CreatePingIcon(parent)
    local pingIcon = CreateFrame("Frame", parent:GetName().."PingIcon", F.BD(parent).widgets.indicatorFrame)
    F.BD(parent).indicators.pingIcon = pingIcon
    pingIcon:SetIgnoreParentAlpha(true)
    pingIcon:Hide()

    pingIcon.bg = pingIcon:CreateTexture(nil, "OVERLAY", nil, 6)
    pingIcon.bg:SetAllPoints()
    pingIcon.glyph = pingIcon:CreateTexture(nil, "OVERLAY", nil, 7)
    pingIcon.glyph:SetAllPoints()

    -- Give the icon a visible texture right away (same idea as Combat Icon's default texture)
    -- so the Indicators settings panel's "select to preview" / "Show All" can just :Show() it.
    SetKitTexture(pingIcon, PREVIEW_KIT)

    function pingIcon:ShowPing(kit)
        SetKitTexture(pingIcon, kit)
        pingIcon:Show()

        -- Belt-and-braces: if Blizzard's own ClearPing is ever missed (the unit's frame gets
        -- recycled to someone else before the pin naturally expires), don't leave the icon
        -- stuck on screen forever.
        if pingIcon._timer then
            pingIcon._timer:Cancel()
        end
        pingIcon._timer = C_Timer.NewTimer(SAFETY_EXPIRE, function()
            pingIcon._timer = nil
            pingIcon:Hide()
        end)
    end

    function pingIcon:ClearPing()
        if pingIcon._timer then
            pingIcon._timer:Cancel()
            pingIcon._timer = nil
        end
        pingIcon:Hide()
    end
end

-------------------------------------------------
-- mirror engine
-------------------------------------------------
local function safeGUID(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    if guid == nil or not F.IsValueNonSecret(guid) then return nil end
    return guid
end

-- A unit can be shown on more than one Cell button at once (e.g. a pet-linked frame), so every
-- match gets the ping, not just the first one found.
local function forEachButtonShowing(unit, callback)
    if not unit or not F.IsKnownTrue(UnitExists(unit)) then return end
    F.IterateAllUnitButtons(function(b)
        local u = F.BD(b).states.unit
        if u and F.IsKnownTrue(UnitIsUnit(u, unit)) then callback(b) end
    end, true)
end

local function onBlizzardShowPing(icon, kit)
    if not enabled then return end
    if type(kit) ~= "string" or not F.IsValueNonSecret(kit) then return end
    local owner = icon:GetParent()
    local unit = owner and owner.unit
    if not safeGUID(unit) then return end

    forEachButtonShowing(unit, function(b)
        local pingIcon = F.BD(b).indicators.pingIcon
        if pingIcon then pingIcon:ShowPing(kit) end
    end)
end

local function onBlizzardClearPing(icon)
    local owner = icon:GetParent()
    local unit = owner and owner.unit
    if not unit then return end

    forEachButtonShowing(unit, function(b)
        local pingIcon = F.BD(b).indicators.pingIcon
        if pingIcon then pingIcon:ClearPing() end
    end)
end

local function hookIcon(icon)
    if not icon or icon._cellPingHooked then return end
    local ok, forbidden = pcall(icon.IsForbidden, icon)
    if not ok or forbidden then return end
    icon._cellPingHooked = true
    hooksecurefunc(icon, "ShowPing", onBlizzardShowPing)
    hooksecurefunc(icon, "ClearPing", onBlizzardClearPing)
end

local function hookOwner(frame)
    if frame and frame.pingIconFrame then hookIcon(frame.pingIconFrame) end
end

-- Every compact frame Blizzard may already have built, plus the classic Player/Target/Focus
-- frames (self/target pings don't go through the compact-frame system at all -- a solo player
-- has no CompactPartyFrameMember with a unit assigned to it in the first place). Cheap and
-- guarded per icon, safe to re-run on every roster change; deliberately NOT hooked off
-- CompactUnitFrame_SetUpFrame/DefaultCompactUnitFrameSetup themselves -- Cell has already been
-- burned once by running addon code inside that same Blizzard call chain (see the
-- CompactUnitFrame_SetUpFrame note in HideBlizzard.lua), so this only ever runs from an
-- ordinary event, never nested inside Blizzard's own execution.
local function sweepBlizzardFrames()
    for i = 1, 5 do hookOwner(_G["CompactPartyFrameMember" .. i]) end
    for i = 1, 40 do hookOwner(_G["CompactRaidFrame" .. i]) end
    for g = 1, 8 do
        for m = 1, 5 do hookOwner(_G["CompactRaidGroup" .. g .. "Member" .. m]) end
    end
    hookOwner(_G.PlayerFrame)
    hookOwner(_G.TargetFrame)
    hookOwner(_G.FocusFrame)
end

local function ensurePingCVar()
    if GetCVarBool and not GetCVarBool(PING_CVAR) then
        SetCVar(PING_CVAR, "1")
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function()
    if enabled then sweepBlizzardFrames() end
end)

-------------------------------------------------
-- settings entry point (called from Indicators.lua / UnitButton.lua)
-------------------------------------------------
function I.EnablePingIcon(value)
    enabled = not not value
    if enabled then
        ensurePingCVar()
        sweepBlizzardFrames()
    end
end

-- Self-sufficient, same pattern as Targeted Spell Bars: fires on EVERY settings-panel change
-- for this indicator (including "enabled"), so a live toggle works without needing its own
-- dispatch case wired into UnitButton.lua's big currentSetting switch.
Cell.RegisterCallback("UpdateIndicators", "PingIcon_UpdateIndicators", function(layout, indicatorName)
    if indicatorName and indicatorName ~= INDICATOR_NAME then return end
    local cfg = GetConfig()
    I.EnablePingIcon(cfg and cfg.enabled)
end)
