local _, Cell = ...
local F = Cell.funcs

-------------------------------------------------------------------------------
-- EngineGlow.lua
--
-- Glow for indicators on the native Retail aura engine (CustomAuraDisplay.lua).
-- LibCustomGlow (used on Classic/TBC) animates via Lua "OnUpdate", which since
-- patch 12.1 throws/freezes once a pooled aura button turns restricted. Fix:
-- drive the animation with a Blizzard AnimationGroup instead -- started once,
-- it loops on the C side forever, no Lua touching the button again.
--
-- New style: add a Start<Name>/Stop<Name> pair and register it in
-- STARTERS/STOPPERS below. Keep it AnimationGroup-based, not OnUpdate-based.
-------------------------------------------------------------------------------

local function GetOrCreateRingTexture(wrapper, key, thickness)
    local d = wrapper[key]
    if d then return d end

    local tex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetTexture(Cell.vars.whiteTexture or Cell.vars.texture)
    tex:SetAllPoints(wrapper)

    -- Hollow it into a ring: mask inset by `thickness`, CLAMPTOWHITE so
    -- everything outside the mask's own rect reads as fully revealed.
    local mask = wrapper:CreateMaskTexture()
    mask:SetTexture(Cell.vars.emptyTexture, "CLAMPTOWHITE", "CLAMPTOWHITE")
    mask:SetPoint("TOPLEFT", tex, "TOPLEFT", thickness, -thickness)
    mask:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", -thickness, thickness)
    tex:AddMaskTexture(mask)

    d = { tex = tex }
    wrapper[key] = d
    return d
end

-------------------------------------------------------------------------------
-- Pulse -- a colored ring that fades between low and high alpha.
-------------------------------------------------------------------------------
local PULSE_THICKNESS = 3
local PULSE_MIN_ALPHA, PULSE_MAX_ALPHA = 0.35, 1
local PULSE_TIME = 0.6

local function StartPulse(wrapper, r, g, b, a)
    local d = GetOrCreateRingTexture(wrapper, "_cellGlowPulse", PULSE_THICKNESS)
    if not d.ag then
        local ag = d.tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetDuration(PULSE_TIME)
        fadeOut:SetOrder(1)
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetDuration(PULSE_TIME)
        fadeIn:SetOrder(2)
        d.ag, d.fadeOut, d.fadeIn = ag, fadeOut, fadeIn
    end

    -- Alpha animation overrides SetAlpha each tick, so bake the chosen alpha
    -- into its from/to values instead.
    local maxA, minA = PULSE_MAX_ALPHA * a, PULSE_MIN_ALPHA * a
    d.fadeOut:SetFromAlpha(maxA)
    d.fadeOut:SetToAlpha(minA)
    d.fadeIn:SetFromAlpha(minA)
    d.fadeIn:SetToAlpha(maxA)

    d.tex:SetVertexColor(r, g, b, 1)
    d.tex:SetAlpha(maxA)
    d.tex:Show()
    if d.ag:IsPlaying() then d.ag:Stop() end
    d.ag:Play()
end

local function StopPulse(wrapper)
    local d = wrapper._cellGlowPulse
    if not d then return end
    if d.ag then d.ag:Stop() end
    d.tex:Hide()
end

-------------------------------------------------------------------------------
-- Flash -- same ring as Pulse, just a hard, fast blink instead of a smooth
-- fade (SetSmoothing("NONE") + a short duration).
-------------------------------------------------------------------------------
local FLASH_THICKNESS = 3
local FLASH_MIN_ALPHA, FLASH_MAX_ALPHA = 0.15, 1
local FLASH_TIME = 0.18

local function StartFlash(wrapper, r, g, b, a)
    local d = GetOrCreateRingTexture(wrapper, "_cellGlowFlash", FLASH_THICKNESS)
    if not d.ag then
        local ag = d.tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetDuration(FLASH_TIME)
        fadeOut:SetOrder(1)
        fadeOut:SetSmoothing("NONE")
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetDuration(FLASH_TIME)
        fadeIn:SetOrder(2)
        fadeIn:SetSmoothing("NONE")
        d.ag, d.fadeOut, d.fadeIn = ag, fadeOut, fadeIn
    end

    local maxA, minA = FLASH_MAX_ALPHA * a, FLASH_MIN_ALPHA * a
    d.fadeOut:SetFromAlpha(maxA)
    d.fadeOut:SetToAlpha(minA)
    d.fadeIn:SetFromAlpha(minA)
    d.fadeIn:SetToAlpha(maxA)

    d.tex:SetVertexColor(r, g, b, 1)
    d.tex:SetAlpha(maxA)
    d.tex:Show()
    if d.ag:IsPlaying() then d.ag:Stop() end
    d.ag:Play()
end

local function StopFlash(wrapper)
    local d = wrapper._cellGlowFlash
    if not d then return end
    if d.ag then d.ag:Stop() end
    d.tex:Hide()
end

-------------------------------------------------------------------------------
-- Proc -- the action-button "proc ready" flipbook glow, filling `wrapper` with
-- a small outset. Not ring-masked like Pulse/Flash -- made for icon-shaped
-- targets (e.g. a Highlight Debuffs icon); looks smeared on a wide target
-- like Border.
-------------------------------------------------------------------------------
local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local PROC_ROWS, PROC_COLUMNS, PROC_FRAMES, PROC_DURATION = 6, 5, 30, 1
local PROC_OUTSET = 4

local function StartProc(wrapper, r, g, b, a)
    local d = wrapper._cellGlowProc
    if not d then
        local tex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetPoint("TOPLEFT", wrapper, "TOPLEFT", -PROC_OUTSET, PROC_OUTSET)
        tex:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", PROC_OUTSET, -PROC_OUTSET)

        local ag = tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local anim = ag:CreateAnimation("FlipBook")
        anim:SetFlipBookRows(PROC_ROWS)
        anim:SetFlipBookColumns(PROC_COLUMNS)
        anim:SetFlipBookFrames(PROC_FRAMES)
        anim:SetDuration(PROC_DURATION)

        d = { tex = tex, ag = ag }
        wrapper._cellGlowProc = d
    end

    d.tex:SetAtlas(PROC_ATLAS)
    d.tex:SetVertexColor(r, g, b, a)
    d.tex:Show()
    if d.ag:IsPlaying() then d.ag:Stop() end
    d.ag:Play()
end

local function StopProc(wrapper)
    local d = wrapper._cellGlowProc
    if not d then return end
    if d.ag then d.ag:Stop() end
    d.tex:Hide()
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
local STARTERS = {
    pulse = StartPulse,
    flash = StartFlash,
    proc  = StartProc,
}
local STOPPERS = {
    StopPulse, StopFlash, StopProc,
}

-- Starts (or switches style of) the glow on `wrapper`; size it by anchoring
-- `wrapper` itself, not by passing pixel dimensions here.
function F.StartEngineGlow(wrapper, style, r, g, b, a)
    if not wrapper then return end
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    local starter = STARTERS[style] or StartPulse

    for _, stop in ipairs(STOPPERS) do
        stop(wrapper)
    end
    starter(wrapper, r, g, b, a)
end

function F.StopEngineGlow(wrapper)
    if not wrapper then return end
    for _, stop in ipairs(STOPPERS) do
        stop(wrapper)
    end
end
