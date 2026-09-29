local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs
local L = Cell.L
local P = Cell.pixelPerfectFuncs

--[[
    Targeted Spell Bars

    Successor to the "Targeted Spells" indicator (Indicators/TargetedSpells.lua), which is
    permanently disabled (I.EnableTargetedSpells hardcodes enable = false) because it tried to
    guess WHICH party/raid frame an enemy cast was targeting via a class/role/race/sex elimination
    heuristic -- unreliable, party-only, and built around a match that Secret Values makes
    increasingly unworkable.

    This indicator never tries to match a cast to one of our own frames at all. Instead it shows
    one floating, Cell-styled bar per tracked enemy cast (one per nameplate), and reads WHO it is
    aimed at through the dedicated, secret-safe Blizzard APIs built for exactly this purpose:
    UnitShouldDisplaySpellTargetName / UnitSpellTargetName. Their answer can be a secret string --
    it is only ever handed straight to SetText, never inspected or compared in Lua.

    Floating and independent of unit frames, so it is NOT built per-button like a normal indicator
    (there is no I.CreateTargetedSpellBars(button) call from UnitButton.lua). It still lives in the
    indicator list (enable checkbox + settings) so it sits next to "Targeted Spells", but the actual
    display is a single shared container, refreshed through its own "UpdateIndicators" callback --
    the same pattern CombatAuraDisplay.lua / HealersAuraDisplay.lua use for their own engine-driven
    displays that don't map 1:1 onto the generic per-button settings pipeline.
]]

local UnitCanAttack = UnitCanAttack
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetTime = GetTime
local C_Spell = C_Spell
local C_NamePlate = C_NamePlate
local C_ClassColor = C_ClassColor

local INDICATOR_NAME = "targetedSpellBars"
--! At the instant a START event fires, UnitCastingInfo/UnitCastingDuration/etc. aren't
--! populated yet (Blizzard fills them in a few frames later), so reading immediately just
--! gets nil back. 0.2s is comfortably past that and still imperceptible for a cast bar.
local PICKUP_DELAY = 0.2

local STATUSBAR_INTERPOLATION_IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local STATUSBAR_DIRECTION_ELAPSED = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
local STATUSBAR_DIRECTION_REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime

-------------------------------------------------
-- config
-------------------------------------------------
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

local function IsEnabled(cfg)
    return cfg ~= nil and cfg.enabled == true
end

local function WhereAllows(cfg)
    local where = cfg.where or "both"
    if where == "raid" then
        return IsInRaid()
    elseif where == "party" then
        return IsInGroup() and not IsInRaid()
    end
    return true -- "both": raid, party, or solo
end

-------------------------------------------------
-- state
-------------------------------------------------
local container -- built lazily
local bars = {} -- frame pool
local shown = {} -- active entries, in display order
local unitEntry = {} -- unit -> entry
local plateUnits = {} -- unit -> true while its nameplate exists
local active = false -- events registered / display live
local previewOn = false
local castGen = {} -- unit -> generation, invalidates a deferred ApplyCast if the cast already stopped

-------------------------------------------------
-- per-button placeholder (settings-preview compatibility only)
-------------------------------------------------
-- This indicator's real display is the single floating container below, never anything
-- per-button. But Cell's generic indicator-settings preview (Indicators.lua's
-- ResetIndicators-equivalent for the preview button) assumes EVERY "built-in" indicator has
-- a per-button widget at F.BD(button).indicators[indicatorName] -- without one it falls back
-- to I.CreateIndicator(), which doesn't recognize this indicatorName and returns nil, and the
-- caller immediately does `indicator.configs = t` on that nil. A tiny inert placeholder frame
-- (never shown, never touched by the real engine above) is enough to satisfy every generic
-- call the settings preview can make on it (P.Size/SetFrameLevel work natively on any Frame;
-- everything else it calls is guarded by an `indicator.MethodName` existence check first,
-- except SetOrientation, hence the one stub below).
function I.CreateTargetedSpellBars(parent)
    local placeholder = CreateFrame("Frame", nil, F.BD(parent).widgets.indicatorFrame)
    placeholder:Hide()
    function placeholder:SetOrientation() end
    F.BD(parent).indicators[INDICATOR_NAME] = placeholder
end

-------------------------------------------------
-- container + mover (same pattern as the Buff Tracker panel)
-------------------------------------------------
local function EnsureContainer()
    if container then return container end
    container = CreateFrame("Frame", "CellTargetedSpellBarsFrame", Cell.frames.mainFrame, "BackdropTemplate")
    container:SetSize(240, 20)
    container:SetClampedToScreen(true)
    P.Point(container, "CENTER", CellParent, "CENTER", 0, 120)

    container:SetMovable(true)
    container:EnableMouse(false)
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    local function SavePos()
        local cfg = GetConfig()
        if cfg then
            cfg.moverPos = cfg.moverPos or {}
            P.SavePosition(container, cfg.moverPos)
        end
    end
    container:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos()
    end)

    -- Separate title-bar-style handle above the container: the "Mover" label used to just be
    -- text floating outside the container's own bounds, so clicking it (rather than the bar
    -- itself) did nothing. This handle has its own drag scripts (dragging IT moves the
    -- container) and carries the green "drag me" highlight instead of tinting the bar.
    container.moverHandle = CreateFrame("Frame", nil, container)
    container.moverHandle:SetPoint("BOTTOM", container, "TOP", 0, 0)
    container.moverHandle:SetSize(80, 16)
    container.moverHandle:EnableMouse(false)
    container.moverHandle:RegisterForDrag("LeftButton")
    container.moverHandle:SetScript("OnDragStart", function()
        container:StartMoving()
    end)
    container.moverHandle:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        SavePos()
    end)
    container.moverHandle:Hide()

    container.moverBg = container.moverHandle:CreateTexture(nil, "BACKGROUND")
    container.moverBg:SetAllPoints(container.moverHandle)
    container.moverBg:SetColorTexture(0, 1, 0, 0.4)

    container.moverText = container.moverHandle:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    container.moverText:SetPoint("CENTER")
    container.moverText:SetText(L["Mover"])

    return container
end

local function ResizeContainer(cfg)
    local c = EnsureContainer()
    local w, h = 240, 20
    if type(cfg.size) == "table" then
        w = cfg.size[1] or w
        h = cfg.size[2] or h
    end
    c:SetSize(w, h)
    c.moverHandle:SetWidth(w)
end

local function LoadContainerPosition(cfg)
    local c = EnsureContainer()
    if not (cfg and type(cfg.moverPos) == "table" and #cfg.moverPos > 0) then return end
    P.LoadPosition(c, cfg.moverPos)
end

local function ShowMover(show)
    local cfg = GetConfig()
    local c = EnsureContainer()
    if show then
        if not IsEnabled(cfg) then return end
        c:Show()
        c:EnableMouse(true)
        c.moverHandle:EnableMouse(true)
        c.moverHandle:Show()
    else
        c:EnableMouse(false)
        c.moverHandle:EnableMouse(false)
        c.moverHandle:Hide()
        if not active and not previewOn then
            c:Hide()
        end
    end
end
Cell.RegisterCallback("ShowMover", "TargetedSpellBars_ShowMover", ShowMover)

-------------------------------------------------
-- bar pool
-------------------------------------------------
local function BuildBar()
    local c = EnsureContainer()
    local holder = CreateFrame("Frame", nil, c)
    holder:Hide()

    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    --! NO BackdropTemplate ANYWHERE in this bar's frame subtree -- not on the StatusBar itself,
    --! and (field-confirmed) not even as its PARENT. A StatusBar driven by :SetTimerDuration()
    --! with a secret-tainted duration object still crashes Backdrop.lua's corner-texture redraw
    --! if any BackdropTemplate frame sits in the same chain, parent or not -- Blizzard's native
    --! fill-driving code and the backdrop's OnSizeChanged hook collide somewhere in the engine's
    --! layout pass, not just on the exact frame. Border/background are plain textures instead
    --! (CreateTexture calls), never SetBackdrop/BackdropTemplate.
    holder.barFrame = CreateFrame("Frame", nil, holder) -- plain positioning frame, no template at all
    holder.barBorderBg = holder.barFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    holder.barBorderBg:SetAllPoints(holder.barFrame)
    holder.barBorderBg:SetColorTexture(0, 0, 0, 1) -- shows through as a 1px border ring

    holder.barBg = holder.barFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
    holder.barBg:SetPoint("TOPLEFT", holder.barFrame, "TOPLEFT", P.Scale(1), -P.Scale(1))
    holder.barBg:SetPoint("BOTTOMRIGHT", holder.barFrame, "BOTTOMRIGHT", -P.Scale(1), P.Scale(1))
    holder.barBg:SetColorTexture(0.07, 0.07, 0.07, 0.9)

    holder.bar = CreateFrame("StatusBar", nil, holder.barFrame) -- plain StatusBar: no template
    holder.bar:SetPoint("TOPLEFT", holder.barFrame, "TOPLEFT", P.Scale(1), -P.Scale(1))
    holder.bar:SetPoint("BOTTOMRIGHT", holder.barFrame, "BOTTOMRIGHT", -P.Scale(1), P.Scale(1))
    holder.bar:SetStatusBarTexture(Cell.vars.whiteTexture)
    holder.bar:SetStatusBarColor(0.7, 0.4, 0.9, 1)
    holder.bar:SetMinMaxValues(0, 1)
    holder.bar:SetValue(0)
    holder.bar:EnableMouse(false)

    holder.name = holder.bar:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    holder.name:SetJustifyH("LEFT")
    holder.name:SetWordWrap(false)

    holder.target = holder.bar:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    holder.target:SetJustifyH("RIGHT")
    holder.target:SetWordWrap(false)

    holder.timer = holder.bar:CreateFontString(nil, "OVERLAY", "CELL_FONT_STATUS")
    holder.timer:SetJustifyH("RIGHT")
    holder.timer:SetWordWrap(false)

    return holder
end

local function AcquireBar()
    for i = 1, #bars do
        if not bars[i]._inUse then
            bars[i]._inUse = true
            return bars[i]
        end
    end
    local b = BuildBar()
    bars[#bars + 1] = b
    b._inUse = true
    return b
end

-------------------------------------------------
-- style / layout
-------------------------------------------------
local function StyleBar(holder, cfg)
    local w, h = 200, 20
    if type(cfg.size) == "table" then
        w = cfg.size[1] or w
        h = cfg.size[2] or h
    end
    holder:SetSize(w, h)

    local showIcon = cfg.showIcon ~= false
    holder.icon:ClearAllPoints()
    holder.barFrame:ClearAllPoints()
    if showIcon then
        holder.icon:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        holder.icon:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
        holder.icon:SetWidth(h)
        holder.icon:Show()
        holder.barFrame:SetPoint("TOPLEFT", holder.icon, "TOPRIGHT", 2, 0)
        holder.barFrame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    else
        holder.icon:Hide()
        holder.barFrame:SetAllPoints(holder)
    end

    -- Base color stays neutral white here -- the actual visible color (plain vs. important) is
    -- applied per-cast in ApplyCast via the fill texture's vertex color, since "important" can
    -- be a secret boolean that only a native color-from-boolean sink can act on safely.
    holder.bar:SetStatusBarColor(1, 1, 1, 1)

    holder.name:ClearAllPoints()
    holder.name:SetPoint("LEFT", holder.bar, "LEFT", 4, 0)
    holder.timer:ClearAllPoints()
    holder.timer:SetPoint("RIGHT", holder.bar, "RIGHT", -3, 0)
    holder.target:ClearAllPoints()

    local showTargetText = cfg.showTargetText ~= false
    if showTargetText then
        holder.target:SetPoint("RIGHT", holder.timer, "LEFT", -6, 0)
        holder.name:SetWidth(max(1, w * 0.45))
        holder.target:SetWidth(max(1, w * 0.30))
    else
        holder.name:SetWidth(max(1, w - h - 30))
        holder.target:SetWidth(1)
    end
end

local function PositionBar(holder, slot, cfg)
    holder:ClearAllPoints()
    local w, h = 240, 20
    if type(cfg.size) == "table" then
        w = cfg.size[1] or w
        h = cfg.size[2] or h
    end
    local spacing = 2
    local orientation = cfg.orientation or "top-to-bottom"
    local off = (slot - 1) * (h + spacing)
    if orientation == "bottom-to-top" then
        holder:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, off)
    elseif orientation == "left-to-right" then
        off = (slot - 1) * (w + spacing)
        holder:SetPoint("TOPLEFT", container, "TOPLEFT", off, 0)
    elseif orientation == "right-to-left" then
        off = (slot - 1) * (w + spacing)
        holder:SetPoint("TOPRIGHT", container, "TOPRIGHT", -off, 0)
    else
        holder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -off)
    end
end

local function Reflow(cfg)
    for i = 1, #shown do
        PositionBar(shown[i].bar, i, cfg)
    end
end

-------------------------------------------------
-- important-cast color marking
-------------------------------------------------
-- `important` can be a secret boolean (see ClassifyCast) -- spellId is normally secret for an
-- enemy nameplate cast, so this must never be truth-tested directly. Color is the only marking
-- (no glow: LibCustomGlow needs an actual Lua branch to pick Start vs Stop, which a secret
-- boolean can't safely drive, and never lit up reliably even for the non-secret case), applied
-- through the native color-from-boolean sink that's built to accept a secret bool directly.
local function ApplyImportantVisual(holder, cfg, important)
    local normalColor = cfg.color or {0.7, 0.4, 0.9, 1}
    local importantColor = cfg.importantColor or {1, 0.85, 0.1, 1}
    local tex = holder.bar.GetStatusBarTexture and holder.bar:GetStatusBarTexture()
    if tex and tex.SetVertexColorFromBoolean then
        local flag = important
        if flag == nil then flag = false end
        tex:SetVertexColorFromBoolean(flag,
            {r = importantColor[1], g = importantColor[2], b = importantColor[3], a = importantColor[4] or 1},
            {r = normalColor[1], g = normalColor[2], b = normalColor[3], a = normalColor[4] or 1})
    elseif F.IsValueNonSecret(important) then
        -- No native sink on this client -- only safe to color it when we can prove it either way.
        local c = (important == true) and importantColor or normalColor
        holder.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end
end

-------------------------------------------------
-- release
-------------------------------------------------
local function Release(unit, cfg)
    castGen[unit] = (castGen[unit] or 0) + 1 -- invalidate any deferred ApplyCast still pending for this unit
    local e = unitEntry[unit]
    if not e then return end
    unitEntry[unit] = nil
    for i = 1, #shown do
        if shown[i] == e then
            table.remove(shown, i)
            break
        end
    end
    local holder = e.bar
    holder:SetScript("OnUpdate", nil)
    holder._inUse = nil
    holder:Hide()
    Reflow(cfg or GetConfig() or {})
end

local function ReleaseAll()
    local cfg = GetConfig() or {}
    for i = #shown, 1, -1 do
        local e = shown[i]
        castGen[e.unit] = (castGen[e.unit] or 0) + 1
        unitEntry[e.unit] = nil
        e.bar:SetScript("OnUpdate", nil)
        e.bar._inUse = nil
        e.bar:Hide()
        shown[i] = nil
    end
    Reflow(cfg)
end

-------------------------------------------------
-- sorting
-------------------------------------------------
local function SortShown(cfg)
    local sortMode = cfg.sortMode or "startTime"
    if sortMode == "listOrder" then
        table.sort(shown, function(a, b)
            if a.inList ~= b.inList then return a.inList end
            return a.startTime < b.startTime
        end)
    else
        table.sort(shown, function(a, b)
            return a.startTime < b.startTime
        end)
    end
end

-------------------------------------------------
-- bar update (per cast tick)
-------------------------------------------------
--! The "__preview" entry is fully synthetic (fake spell, fake times, never touches a real
--! unit's cast info), so manual GetTime() math on it is always plain-number-safe -- this is
--! the ONLY place that still computes a fraction by hand.
local function BarOnUpdate(holder)
    local e = holder._entry
    if not e then return end

    if e.unit == "__preview" then
        local remain = e.endTime - GetTime()
        if remain <= 0 then
            -- loop the fake cast forever instead of freezing at full/empty
            e.startTime = GetTime()
            e.endTime = GetTime() + 3
            remain = 3
        end
        holder.bar:SetValue(1 - (remain / (e.endTime - e.startTime)))
        if remain > 60 then
            holder.timer:SetFormattedText("%dm", remain / 60)
        else
            holder.timer:SetFormattedText("%.1f", remain)
        end
        return
    end

    -- Real casts never compute their own fraction: ApplyCast's one-time :SetTimerDuration()
    -- call drives the fill natively. This only refreshes the countdown text, and only through
    -- the duration object's own accessor -- never a raw secret start/end time (see the note
    -- above ResolveDuration/ApplyCast for why manual math on those crashes).
    local remaining
    if e.duration and e.duration.GetRemainingDuration then
        remaining = e.duration:GetRemainingDuration()
    end
    if type(remaining) ~= "number" then
        holder.timer:SetText("")
        return
    end
    -- GetRemainingDuration() can ALSO come back secret (field-confirmed) -- but FontString:
    -- SetFormattedText is itself a secret-safe sink (same idea as SetText/SetTexture), so the
    -- number is handed straight to it and never inspected in Lua. What's NOT safe is branching
    -- on it (e.g. a ">60s -> minutes" format), so there's only ever the one fixed format here.
    holder.timer:SetFormattedText("%.1f", remaining)
end

local function PaintTarget(holder, unit, cfg)
    if cfg.showTargetText == false then
        holder.target:SetText("")
        return
    end
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(unit) then
        local targetName = UnitSpellTargetName and UnitSpellTargetName(unit)
        if type(targetName) ~= "nil" then
            holder.target:SetText(targetName) -- may be a secret string, SetText accepts it directly

            -- Class color: UnitSpellTargetClass is the secret-safe counterpart of
            -- UnitSpellTargetName for the target's class token, and C_ClassColor.GetClassColor()
            -- is a documented-safe sink for it -- the color object it hands back is never itself
            -- secret, so its r/g/b can be read directly (this is exactly what Blizzard's own
            -- cast bar does with it).
            local color
            if UnitSpellTargetClass and C_ClassColor and C_ClassColor.GetClassColor then
                color = C_ClassColor.GetClassColor(UnitSpellTargetClass(unit))
            end
            if color then
                holder.target:SetTextColor(color.r, color.g, color.b, 1)
            else
                holder.target:SetTextColor(1, 1, 1, 1)
            end
            return
        end
    end
    holder.target:SetText("")
end

-------------------------------------------------
-- spell filter (reuses the same list "Targeted Spells" already uses)
-------------------------------------------------
-- Every tracked-unit cast is shown (only the
-- "Where to Show" location gate and Max Bars limit which ones), never filtered by list or
-- importance. inList/important are purely informational -- inList only affects sort order
-- ("Listed Spells First"), important only adds the color marking. Neither one hides anything.
local function ClassifyCast(spellId, cfg)
    local nonSecretId = (spellId ~= nil and F.IsValueNonSecret(spellId)) and spellId or nil
    local list = Cell.vars and Cell.vars.targetedSpellsList
    local inList = nonSecretId and list and list[nonSecretId] and true or false

    -- `important` is returned RAW here -- it can come back a secret boolean, because spellId
    -- itself is normally secret for an enemy nameplate cast. IsSpellImportant still accepts a
    -- secret spellId as an argument fine (only INSPECTING its secret result is restricted), so
    -- gating this on nonSecretId like `inList` above would mean it's always nil/false for every
    -- real enemy cast. The caller (ApplyCast) feeds this straight into a secret-safe color sink
    -- instead of ever truth-testing it directly.
    local important
    if spellId ~= nil and C_Spell and C_Spell.IsSpellImportant then
        local ok, imp = pcall(C_Spell.IsSpellImportant, spellId)
        if ok then important = imp end
    end

    return inList, important
end

-------------------------------------------------
-- cast lifecycle
-------------------------------------------------
--! Field-tested approach: never do Lua arithmetic on UnitCastingInfo/UnitChannelInfo's start/end
--! times. On an enemy nameplate they can be secret-tainted, and dividing/subtracting them -- even
--! by a guarded fallback still running in the SAME tainted execution -- is what was crashing
--! Backdrop.lua when the result reached the StatusBar's own width/height.
--!
--! Fix: get progress from UnitCastingDuration/UnitChannelDuration/UnitEmpoweredChannelDuration,
--! an opaque "duration object" handed straight to the StatusBar's native :SetTimerDuration() --
--! Blizzard animates the fill itself, no Lua math involved. spellId comes from the START event's
--! own payload (or a positional read, never combined with reading name/texture off the same
--! UnitCastingInfo call); name/icon are (re-)fetched at render time via C_Spell.GetSpellName/
--! GetSpellTexture and handed straight to SetText/SetTexture, which accept secret values natively.
--! CreateFrame (AcquireBar) and SetSize (StyleBar) still get deferred a tick via C_Timer.After so
--! they never run in the same execution as any of the reads above.
local function ResolveDuration(unit)
    local duration, isEmpowered
    if UnitEmpoweredChannelDuration then
        duration = UnitEmpoweredChannelDuration(unit, true)
        if duration then isEmpowered = true end
    end
    if not duration and UnitChannelDuration then
        duration = UnitChannelDuration(unit)
    end
    if not duration and UnitCastingDuration then
        duration = UnitCastingDuration(unit)
    end
    return duration, isEmpowered
end

local function ApplyCast(unit, cfg, myGen, isChannel, isEmpowered, inList, important, duration, spellId)
    if castGen[unit] ~= myGen then return end
    if not (active and cfg) then return end

    local e = unitEntry[unit]
    local isNew = false
    if not e then
        local maxBars = cfg.num or 5
        if #shown >= maxBars then
            return
        end
        e = { unit = unit, bar = AcquireBar() }
        e.bar._entry = e
        unitEntry[unit] = e
        shown[#shown + 1] = e
        isNew = true
    end
    e.isChannel = isChannel
    e.inList = inList
    e.important = important
    e.startTime = GetTime() -- clean local timestamp for sort order only, never derived from cast info
    e.duration = duration

    StyleBar(e.bar, cfg)
    -- spellId ~= nil, never `spellId and ...` -- spellId itself can be a secret number, and a
    -- truthiness test on one is exactly the kind of comparison the secret-value system blocks.
    if cfg.showIcon ~= false and spellId ~= nil and C_Spell and C_Spell.GetSpellTexture then
        e.bar.icon:SetTexture(C_Spell.GetSpellTexture(spellId))
    end
    if cfg.showSpellName ~= false and spellId ~= nil and C_Spell and C_Spell.GetSpellName then
        e.bar.name:SetText(C_Spell.GetSpellName(spellId))
    end
    PaintTarget(e.bar, unit, cfg)

    if duration and e.bar.bar.SetTimerDuration then
        local direction
        if isEmpowered then
            direction = STATUSBAR_DIRECTION_ELAPSED -- empowered stages fill forward
        elseif isChannel then
            direction = STATUSBAR_DIRECTION_REMAINING -- channels drain
        else
            direction = STATUSBAR_DIRECTION_ELAPSED -- casts fill up
        end
        e.bar.bar:SetTimerDuration(duration, STATUSBAR_INTERPOLATION_IMMEDIATE, direction)
    else
        e.bar.bar:SetValue(0)
    end
    e.bar:SetScript("OnUpdate", BarOnUpdate)
    e.bar:Show()

    ApplyImportantVisual(e.bar, cfg, important)

    SortShown(cfg)
    Reflow(cfg)
    if isNew then
        -- nothing extra, StyleBar already applied above
    end
end

local function StartCast(unit, cfg, eventSpellId)
    if not (active and cfg) then return end
    if not UnitCanAttack("player", unit) then return end -- a unit-vs-unit relationship, never secret

    castGen[unit] = (castGen[unit] or 0) + 1
    local myGen = castGen[unit]

    C_Timer.After(PICKUP_DELAY, function()
        if castGen[unit] ~= myGen then return end
        if not (active and cfg) then return end

        -- type(x) == "nil", never `x ~= nil` -- these can return a secret string, and even a
        -- nil-comparison on one is an equality compare the secret-value system disallows.
        -- The extra parens force the call to exactly one value: on this client an inactive
        -- unit's UnitCastingInfo/UnitChannelInfo can return ZERO values instead of a lone nil,
        -- and type() with no argument at all is a Lua error ("value expected"), not a "nil".
        local isChannel, exists
        if type((UnitCastingInfo(unit))) ~= "nil" then
            isChannel, exists = false, true
        elseif type((UnitChannelInfo(unit))) ~= "nil" then
            isChannel, exists = true, true
        end
        if not exists then
            Release(unit, cfg)
            return
        end

        local spellId = eventSpellId
        if spellId == nil then
            -- No event payload (adopted from an already-casting nameplate, e.g. on
            -- NAME_PLATE_UNIT_ADDED) -- read it positionally instead, same slot Blizzard
            -- always returns it in. Never combined with reading name/texture here.
            if isChannel then
                spellId = select(8, UnitChannelInfo(unit))
            else
                spellId = select(9, UnitCastingInfo(unit))
            end
        end

        local inList, important = ClassifyCast(spellId, cfg)
        local duration, isEmpowered = ResolveDuration(unit)

        -- ApplyCast is where the actual frame work happens (AcquireBar's CreateFrame, StyleBar's
        -- SetSize/SetWidth) -- that has to run on ITS OWN clean tick, never the same execution
        -- that just called UnitCastingInfo/UnitCastingDuration/etc. above. Calling it straight
        -- from here re-creates the exact bug: the bar frame still comes out tainted even though
        -- every read into it went through a secret-safe sink or guard.
        C_Timer.After(0, function()
            if castGen[unit] ~= myGen then return end
            ApplyCast(unit, cfg, myGen, isChannel, isEmpowered, inList, important, duration, spellId)
        end)
    end)
end

-------------------------------------------------
-- events
-------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:Hide()

local START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}
local STOP_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_FAILED_QUIET = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
}
local UPDATE_EVENTS = {
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE = true,
}

local function AdoptPlateCast(unit, cfg)
    local name = UnitCastingInfo(unit)
    if type(name) == "nil" then
        name = UnitChannelInfo(unit)
    end
    if type(name) ~= "nil" then
        StartCast(unit, cfg)
    end
end

eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
        ReleaseAll()
        return
    end

    if not active then return end
    local cfg = GetConfig()
    if not cfg then return end

    if event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) == "string" then
            plateUnits[unit] = true
            AdoptPlateCast(unit, cfg)
        end
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" then
            plateUnits[unit] = nil
            Release(unit, cfg)
        end
        return
    end

    if not (unit and plateUnits[unit]) then return end

    if START_EVENTS[event] then
        -- Event payload after `unit`: (castGUID, spellId, ...) -- spellId only, never combined
        -- with a read of the cast's name/texture.
        local _, spellId = ...
        StartCast(unit, cfg, spellId)
    elseif STOP_EVENTS[event] then
        Release(unit, cfg)
    elseif UPDATE_EVENTS[event] then
        if unitEntry[unit] then
            local _, spellId = ...
            StartCast(unit, cfg, spellId)
        end
    end
end)

local PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP",
}

local function SeedFromLivePlates(cfg)
    wipe(plateUnits)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for i = 1, #plates do
                local u = plates[i] and plates[i].namePlateUnitToken
                if u then plateUnits[u] = true end
            end
        end
    end
    for unit in pairs(plateUnits) do
        AdoptPlateCast(unit, cfg)
    end
end

local function Activate()
    if active then return end
    local cfg = GetConfig()
    if not cfg then return end
    active = true
    EnsureContainer():Show()
    ResizeContainer(cfg)
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    for i = 1, #PLATE_EVENTS do eventFrame:RegisterEvent(PLATE_EVENTS[i]) end
    for i = 1, #CAST_EVENTS do eventFrame:RegisterEvent(CAST_EVENTS[i]) end
    SeedFromLivePlates(cfg)
end

local function Deactivate()
    if not active then return end
    active = false
    eventFrame:UnregisterAllEvents()
    ReleaseAll()
    wipe(plateUnits)
    if container and not previewOn and not (container.moverHandle and container.moverHandle:IsShown()) then
        container:Hide()
    end
end

local function SyncActive()
    local cfg = GetConfig()
    if not IsEnabled(cfg) then
        Deactivate()
        return
    end
    LoadContainerPosition(cfg)
    if WhereAllows(cfg) then
        if not active then Activate() end
    else
        Deactivate()
    end
end

-------------------------------------------------
-- roster / zone watcher: re-evaluate the "where to show" gate
-------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", SyncActive)

-------------------------------------------------
-- settings entry points (called from Indicators.lua / UnitButton.lua)
-------------------------------------------------
function I.EnableTargetedSpellBars(enabled)
    SyncActive()
end

function I.RefreshTargetedSpellBars()
    SyncActive()
    local cfg = GetConfig()
    if not (active and cfg) then return end
    ResizeContainer(cfg)
    for i = 1, #shown do
        StyleBar(shown[i].bar, cfg)
        PaintTarget(shown[i].bar, shown[i].unit, cfg)
        ApplyImportantVisual(shown[i].bar, cfg, shown[i].important)
    end
    SortShown(cfg)
    Reflow(cfg)
end

-------------------------------------------------
-- preview (settings panel "Toggle Preview" button): shows one fake test bar and unlocks the
-- container for dragging, without needing to find the separate Utilities > Raid Tools > Unlock
-- button, and without the indicator having to be enabled first.
-------------------------------------------------
function I.SetTargetedSpellBarsPreview(show)
    local cfg = GetConfig() or {}
    local c = EnsureContainer()

    if show then
        previewOn = true
        ResizeContainer(cfg)
        c:Show()
        c:EnableMouse(true)
        c.moverHandle:EnableMouse(true)
        c.moverHandle:Show()

        local e = unitEntry["__preview"]
        if not e then
            e = { unit = "__preview", bar = AcquireBar() }
            e.bar._entry = e
            unitEntry["__preview"] = e
            shown[#shown + 1] = e
        end
        e.inList = true
        e.important = true
        e.startTime = GetTime()
        e.endTime = GetTime() + 3

        StyleBar(e.bar, cfg)
        if cfg.showIcon ~= false then
            e.bar.icon:SetTexture(134400) -- generic question-mark icon, just for sizing/preview
        end
        if cfg.showSpellName ~= false then
            e.bar.name:SetText(L["Example Cast"])
        end
        if cfg.showTargetText ~= false then
            e.bar.target:SetText(UnitName("player") or "Target")
        end
        e.bar.bar:SetMinMaxValues(0, 1)
        e.bar:SetScript("OnUpdate", BarOnUpdate)
        e.bar:Show()
        ApplyImportantVisual(e.bar, cfg, true) -- always "important" here, just to preview the color
        SortShown(cfg)
        Reflow(cfg)
    else
        previewOn = false
        if unitEntry["__preview"] then
            Release("__preview", cfg)
        end
        c:EnableMouse(false)
        c.moverHandle:EnableMouse(false)
        c.moverHandle:Hide()
        SyncActive() -- restore whatever the real (non-preview) state should be
    end
end

Cell.RegisterCallback("UpdateIndicators", "TargetedSpellBars_UpdateIndicators", function(layout, indicatorName)
    if indicatorName and indicatorName ~= INDICATOR_NAME then return end
    I.RefreshTargetedSpellBars()
end)
