local _, Cell = ...
local F = Cell.funcs
local L = Cell.L

Cell.vars.editModeOpen = false

local hardDisabled = false
local partyMixinHooked = false
local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()
local parentHooks = {}
local looseParents = {}
local reenteringParent = {}
local TrySuppressForGroup
local KillFrame
local QuietCompactParty
local FrameIsForbidden
local ApplyEditModeOverlaySuppression

local function IsAlreadyParked(parent)
    if not parent or parent == hiddenParent then
        return true
    end
    if parent == UIParent then
        return false
    end
    local ok, shown = pcall(parent.IsShown, parent)
    return ok and not shown
end

local parentWatch = CreateFrame("Frame")
parentWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
parentWatch:SetScript("OnEvent", function()
    for frame in next, looseParents do
        if frame and not FrameIsForbidden(frame) and not InCombatLockdown() then
            local parent = frame.GetParent and frame:GetParent()
            if not IsAlreadyParked(parent) then
                reenteringParent[frame] = true
                pcall(frame.SetParent, frame, hiddenParent)
                reenteringParent[frame] = nil
            end
        end
        looseParents[frame] = nil
    end
end)

local function ShouldHideBlizzardParty()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardParty"]
end

local function ShouldHideBlizzardRaid()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardRaid"]
end

local function ShouldHideBlizzardRaidManager()
    return CellDB and CellDB["general"] and CellDB["general"]["hideBlizzardRaidManager"]
end

local function IsTraditionalPartyStyleActive()
    local pf = _G.PartyFrame
    if not (pf and pf.IsShown) then return false end
    local ok, shown = pcall(pf.IsShown, pf)
    return ok and shown and true or false
end

local function ShouldParkTraditionalParty()
    return ShouldHideBlizzardParty() and IsTraditionalPartyStyleActive()
end

function F.IsEditModeOpen()
    local em = _G.EditModeManagerFrame
    if em and em.IsShown then
        local ok, shown = pcall(em.IsShown, em)
        if ok and shown then
            return true
        end
    end
    return Cell.vars.editModeOpen == true
end

FrameIsForbidden = function(frame)
    if not frame then return true end
    local ok, forbidden = pcall(function()
        return frame.IsForbidden and frame:IsForbidden()
    end)
    return (not ok) or forbidden
end

local function StickToHiddenParent(frame, shouldHide)
    if not frame or FrameIsForbidden(frame) or parentHooks[frame] then return end
    parentHooks[frame] = true
    pcall(function()
        hooksecurefunc(frame, "SetParent", function(self)
            if reenteringParent[self] then return end
            -- Deferred instead of synchronous: Blizzard can call SetParent on these
            -- frames from inside its own protected call chains (e.g. Edit Mode
            -- laying out its managed frames), and re-parenting here immediately
            -- would run Cell's code mid-chain and taint the rest of it (the same
            -- mechanism behind the CompactUnitFrame_SetUpFrame/RegisterEvent hooks
            -- removed elsewhere in this file). C_Timer.After starts a fresh,
            -- untainted execution one frame later.
            C_Timer.After(0, function()
                if reenteringParent[self] then return end
                if not shouldHide() then return end
                local parent = self.GetParent and self:GetParent()
                if IsAlreadyParked(parent) then return end
                if InCombatLockdown() then
                    looseParents[self] = true
                    return
                end
                reenteringParent[self] = true
                pcall(self.SetParent, self, hiddenParent)
                reenteringParent[self] = nil
            end)
        end)
    end)
end

local function ParkUnderHiddenParent(frame, shouldHide)
    if not frame or FrameIsForbidden(frame) then return end
    StickToHiddenParent(frame, shouldHide)
    if InCombatLockdown() then
        looseParents[frame] = true
        return
    end
    local parent = frame.GetParent and frame:GetParent()
    if IsAlreadyParked(parent) then return end
    reenteringParent[frame] = true
    pcall(frame.SetParent, frame, hiddenParent)
    reenteringParent[frame] = nil
end

local function StickHiddenParent(frame)
    StickToHiddenParent(frame, ShouldHideBlizzardParty)
end

local function SetFrameAlpha(frame, alpha)
    if not frame or FrameIsForbidden(frame) then return end
    pcall(frame.SetAlpha, frame, alpha)
end

local function HideSelectionHighlight(frame)
    if not frame or FrameIsForbidden(frame) then return end
    local hl = frame.selectionHighlight
    if hl then
        pcall(hl.SetShown, hl, false)
        pcall(hl.SetAlpha, hl, 0)
        pcall(hl.SetIgnoreParentAlpha, hl, false)
    end
    local ind = frame.selectionIndicator
    if ind then
        pcall(ind.SetShown, ind, false)
        pcall(ind.SetAlpha, ind, 0)
    end
end

local function ForEachCompactPartyMember(func)
    local members = _G.MEMBERS_PER_RAID_GROUP or 5
    for i = 1, members do
        func(_G["CompactPartyFrameMember" .. i])
        func(_G["CompactPartyFramePet" .. i])
    end
    local cpf = _G.CompactPartyFrame
    if cpf then
        if cpf.memberUnitFrames then
            for _, frame in ipairs(cpf.memberUnitFrames) do
                func(frame)
            end
        end
        if cpf.petUnitFrames then
            for _, frame in ipairs(cpf.petUnitFrames) do
                func(frame)
            end
        end
    end
end

local function ForEachCompactRaidMember(func)
    local members = _G.MEMBERS_PER_RAID_GROUP or 5
    for i = 1, 8 do
        for m = 1, members do
            func(_G["CompactRaidGroup" .. i .. "Member" .. m])
        end
        func(_G["CompactRaidGroup" .. i])
    end
    for i = 1, 80 do
        func(_G["CompactRaidFrame" .. i])
    end
end

local function HideGoldHighlights()
    if ShouldHideBlizzardParty() then
        HideSelectionHighlight(_G.CompactPartyFrame)
        ForEachCompactPartyMember(HideSelectionHighlight)
    end
    if ShouldHideBlizzardRaid() then
        ForEachCompactRaidMember(HideSelectionHighlight)
    end
end

local function QuietStatusBar(bar)
    if not bar or FrameIsForbidden(bar) then return end
    -- Never replace OnEvent (see NeutralizeTraditionalMember below for why):
    -- UnregisterAllEvents already makes the existing handler a no-op.
    pcall(bar.UnregisterAllEvents, bar)
    pcall(bar.SetScript, bar, "OnUpdate", nil)
end

-- NOTE: This used to hooksecurefunc "RegisterEvent"/"RegisterUnitEvent" on each
-- sub-widget to call self:UnregisterEvent(...) synchronously whenever Blizzard
-- (re)registered one. Same problem as the CompactUnitFrame_SetUpFrame hooks
-- removed above: CompactUnitFrame_SetUpFrame/UpdateAll -- called directly out of
-- EnterEditMode/RefreshMembers -- re-registers the health bar's unit event as
-- part of that same continuous member-refresh loop, so this hook body ran mid
-- Blizzard-execution and tainted the rest of the loop (the actual cause of the
-- "secret number value, while execution tainted by 'Cell'" HealPrediction error
-- reproducible by just opening Edit Mode). The direct UnregisterAllEvents call
-- already done alongside every call site (QuietStatusBar, KillFrame,
-- NeutralizeTraditionalMember) runs from ordinary events/tickers instead and is
-- enough -- it just won't undo a re-registration until the next sweep.
local function StopEventRegistration(frame)
end

local function QuietUnitParts(frame)
    if not frame then return end
    local container = frame.HealthBarContainer or frame.HealthBarsContainer
    local health = (container and (container.HealthBar or container.healthBar))
        or frame.healthbar or frame.HealthBar or frame.healthBar
    QuietStatusBar(health)
    StopEventRegistration(health)
    local power = frame.ManaBar or frame.manabar or frame.powerBar or frame.PowerBar
    QuietStatusBar(power)
    StopEventRegistration(power)
    QuietStatusBar(frame.castBar or frame.spellbar or frame.CastingBarFrame)
    QuietStatusBar(frame.powerBarAlt or frame.PowerBarAlt)
    if frame.BuffFrame then
        pcall(frame.BuffFrame.UnregisterAllEvents, frame.BuffFrame)
    end
    if frame.DebuffFrame then
        pcall(frame.DebuffFrame.UnregisterAllEvents, frame.DebuffFrame)
    end
    if frame.AurasFrame then
        pcall(frame.AurasFrame.UnregisterAllEvents, frame.AurasFrame)
    end
    if frame.PetFrame then
        pcall(frame.PetFrame.UnregisterAllEvents, frame.PetFrame)
    end
end

local function SafeHide(frame)
    if not frame then return end
    if InCombatLockdown() then
        pcall(frame.SetAlpha, frame, 0)
        return
    end
    pcall(frame.Hide, frame)
end

local function NeutralizeTraditionalMember(frame)
    if not frame or FrameIsForbidden(frame) then return end
    StopEventRegistration(frame)
    -- Never replace OnEvent/UpdateArt/ToPlayerArt/ToVehicleArt/UpdateMember with
    -- an addon closure: Blizzard's own frame lifecycle code (e.g. re-initializing
    -- this member when Edit Mode refreshes party frames) can invoke these methods
    -- by reference directly, which would call Cell's code mid-Blizzard-chain and
    -- taint the rest of it (the "secret number value...tainted by Cell"
    -- HealPrediction error, reproducible by just opening Edit Mode).
    -- UnregisterAllEvents + Hide/SetAlpha (below) is enough to keep it quiet.
    pcall(function()
        if frame.SetScript then
            frame:SetScript("OnUpdate", nil)
        end
        frame:UnregisterAllEvents()
        frame:SetAlpha(0)
    end)
    QuietUnitParts(frame)
    if frame.PetFrame then
        NeutralizeTraditionalMember(frame.PetFrame)
    end
end

KillFrame = function(frame)
    if not frame or FrameIsForbidden(frame) then return end
    pcall(function()
        frame:UnregisterAllEvents()
        frame:SetAlpha(0)
        if not InCombatLockdown() then
            frame:Hide()
        end
    end)
    QuietUnitParts(frame)
    HideSelectionHighlight(frame)
end

local function InstallPartyMemberNoops()
    if not ShouldHideBlizzardParty() then return end

    local mixin = _G.PartyMemberFrameMixin
    if mixin and not partyMixinHooked then
        partyMixinHooked = true
        -- Never replace shared mixin methods (OnEvent/UpdateArt/.../UpdateMember)
        -- with an addon closure: every PartyMemberFrame instance shares this
        -- mixin table, and Blizzard calling any of these by reference on ANY
        -- instance would run Cell's code mid-Blizzard-chain (same reasoning as
        -- NeutralizeTraditionalMember above). NeutralizeTraditionalMember +
        -- KillFrame already keep individual instances quiet via
        -- UnregisterAllEvents + Hide/SetAlpha.
        if mixin.Setup then
            -- Deferred for the same reason as StickToHiddenParent's SetParent hook:
            -- Blizzard calls Setup() from inside its own protected call chains
            -- (e.g. Edit Mode refreshing party frames), and running Cell's
            -- Neutralize/Kill logic synchronously there would taint the rest of
            -- that chain.
            hooksecurefunc(mixin, "Setup", function(frame)
                C_Timer.After(0, function()
                    if ShouldHideBlizzardParty() then
                        NeutralizeTraditionalMember(frame)
                        KillFrame(frame)
                    end
                end)
            end)
        end
    end

    -- NOTE: This used to also replace pf.UpdateMemberFrames/UpdatePartyFrames
    -- with Swallow -- same risk as the mixin methods above, removed for the
    -- same reason: KillFrame(pf) in QuietTraditionalParty already keeps it
    -- quiet via UnregisterAllEvents + alpha.
end

local function ShrinkContainer(frame)
    if not frame or FrameIsForbidden(frame) then return end
    pcall(function()
        frame:SetAlpha(0)
        if not InCombatLockdown() then
            frame:SetScale(0.001)
        end
    end)
    HideSelectionHighlight(frame)
end

-- NOTE: This used to also hooksecurefunc "CompactUnitFrame_SetUpFrame",
-- "CompactUnitFrame_SetUnit" and "CompactUnitFrame_SetUpdateAllOnUpdate" to run
-- StopCompactOnUpdate/UnregisterAllEvents/Hide synchronously. hooksecurefunc does
-- not taint the ORIGINAL call, but the hook body itself still runs as part of the
-- SAME still-open Blizzard execution -- and Blizzard calls CompactUnitFrame_SetUpFrame
-- directly out of EnterEditMode/RefreshMembers while refreshing every party/raid
-- member in one continuous loop. The moment Cell's hook body ran or the next member
-- in that same loop, "execution tainted by 'Cell'" from that hook, causing
-- CompactUnitFrame_UpdateHealPrediction's later secret-number comparisons in the
-- SAME loop to fail (cell bug: opening Edit Mode alone reproduces it). The periodic
-- visibilityWatch ticker below and the event-driven QuietCompactMember sweep (from
-- ordinary events, never from inside a Blizzard call chain) are enough to keep these
-- member frames quiet without hooking Blizzard's own setup functions.

-- NOTE: This used to also call the real CompactUnitFrame_SetUpdateAllOnUpdate(frame,
-- false) and null out frame.updateAllSetupFunc/frame.onUpdateFrame's OnUpdate script --
-- direct writes to Blizzard's own per-frame update-all bookkeeping. Every write like
-- it in this file has turned out to be part of the taint chain behind the
-- HealPrediction error, so this is removed too rather than assumed safe.
local function StopCompactOnUpdate(frame)
end

local function QuietCompactMember(frame)
    if not frame or FrameIsForbidden(frame) then return end
    StopCompactOnUpdate(frame)
    -- Never replace OnEvent here either (see NeutralizeTraditionalMember for why:
    -- CompactUnitFrame_SetUpFrame -- called directly out of EnterEditMode/
    -- RefreshMembers -- can invoke the frame's current OnEvent handler by
    -- reference as part of its own setup, e.g. frame.updateAllEvent tracks which
    -- event that is). UnregisterAllEvents alone makes the existing Blizzard
    -- handler a no-op without ever putting Cell's code on that call stack.
    pcall(frame.UnregisterAllEvents, frame)
    pcall(function()
        if frame.SetScript then
            frame:SetScript("OnUpdate", nil)
        end
    end)
    -- Never SetParent()/Hide() individual compact member frames (this used to
    -- ParkUnderHiddenParent + SafeHide party members here): Edit Mode refreshes
    -- CompactPartyFrameMember1-5 as part of its own party-frame system, and
    -- reparenting/hiding them taints that system the same way reparenting the
    -- container did (the "secret number value...tainted by Cell" HealPrediction
    -- error reproducible by just opening Edit Mode). Alpha-only.
    SetFrameAlpha(frame, 0)
    -- NOTE: This used to also write frame.optionTable.fadeOutOfRange = false and
    -- frame.outOfRange = false. optionTable is commonly a table SHARED across every
    -- compact frame of a given type (not a per-instance copy), so writing into it from
    -- here could mark that shared table as touched by Cell for every frame referencing
    -- it, not just this one -- removed along with everything else in this function that
    -- wasn't a plain UnregisterAllEvents/SetAlpha.
    QuietUnitParts(frame)
    HideSelectionHighlight(frame)
    if frame.PetFrame then
        QuietCompactMember(frame.PetFrame)
    end
end

local function QuietTraditionalMember(frame)
    if not frame or FrameIsForbidden(frame) then return end
    NeutralizeTraditionalMember(frame)
    KillFrame(frame)
    if frame.PetFrame then
        NeutralizeTraditionalMember(frame.PetFrame)
        KillFrame(frame.PetFrame)
    end
end

local function QuietTraditionalParty()
    InstallPartyMemberNoops()
    local pf = _G.PartyFrame
    if pf and not FrameIsForbidden(pf) then
        StopEventRegistration(pf)
        KillFrame(pf)
        ShrinkContainer(pf)
        if IsTraditionalPartyStyleActive() then
            ParkUnderHiddenParent(pf, ShouldParkTraditionalParty)
        end
        if pf.PartyMemberFramePool then
            for memberFrame in pf.PartyMemberFramePool:EnumerateActive() do
                NeutralizeTraditionalMember(memberFrame)
                KillFrame(memberFrame)
                if memberFrame.PetFrame then
                    NeutralizeTraditionalMember(memberFrame.PetFrame)
                    KillFrame(memberFrame.PetFrame)
                end
            end
        end
        for i = 1, (_G.MAX_PARTY_MEMBERS or 4) do
            QuietTraditionalMember(pf["MemberFrame" .. i])
        end
        SetFrameAlpha(pf.DropdownButton, 0)
        SetFrameAlpha(pf.PartyMemberFrameDropDown, 0)
    end
    for i = 1, 4 do
        QuietTraditionalMember(_G["PartyMemberFrame" .. i])
        QuietTraditionalMember(_G["PartyMemberFrame" .. i .. "PetFrame"])
    end
    if _G.PartyMemberBackground then
        KillFrame(_G.PartyMemberBackground)
    end
end

-- NOTE: This used to also monkey-patch CompactPartyFrame/CompactRaidFrameContainer's
-- own methods (RefreshMembers/UpdateSystem/UpdateMemberLayout/TryUpdate/UpdateAll/
-- ApplyToFrames) to Swallow, a plain addon closure written directly onto the
-- Blizzard frame's table. CompactRaidFrameContainer shares Edit Mode's
-- BottomManagedFrameContainer layout pass with the Cooldown Viewers; when that
-- shared pass called into the swapped-in Swallow closure, execution transferred
-- into Cell's addon code from inside Blizzard's protected call chain, tainting
-- the rest of that pass -- including the Cooldown Viewer siblings processed in
-- the same secureexecuterange loop (cell bugs 01-05). UnregisterAllEvents +
-- alpha/scale (already done elsewhere) is enough to keep these frames quiet
-- without ever replacing their methods.

QuietCompactParty = function()
    local cpf = _G.CompactPartyFrame
    if cpf and not FrameIsForbidden(cpf) then
        pcall(cpf.UnregisterAllEvents, cpf)
        ShrinkContainer(cpf)
        SetFrameAlpha(cpf.title, 0)
        SetFrameAlpha(cpf.borderFrame, 0)
        HideSelectionHighlight(cpf)
        if not InCombatLockdown() then
            if cpf.dropdown then
                pcall(cpf.dropdown.Hide, cpf.dropdown)
            end
            if cpf.menuButton then
                pcall(cpf.menuButton.Hide, cpf.menuButton)
            end
        else
            SetFrameAlpha(cpf.dropdown, 0)
            SetFrameAlpha(cpf.menuButton, 0)
        end
    end
    ForEachCompactPartyMember(function(frame)
        QuietCompactMember(frame)
    end)
end

local function QuietCompactRaid()
    local container = _G.CompactRaidFrameContainer
    if container and not FrameIsForbidden(container) then
        -- Never SetParent()/Hide() this frame: it shares Edit Mode's
        -- BottomManagedFrameContainer layout with the Cooldown Viewers, and
        -- reparenting it out taints that shared managed-frame system (cell
        -- bugs 01-07). Alpha/scale + dead events is the taint-safe way to
        -- suppress it.
        pcall(container.UnregisterAllEvents, container)
        ShrinkContainer(container)
    end
    for i = 1, 8 do
        SetFrameAlpha(_G["CompactRaidGroup" .. i], 0)
    end
    ForEachCompactRaidMember(function(frame)
        QuietCompactMember(frame)
    end)
end

local function QuietRaidManager()
    local manager = _G.CompactRaidFrameManager
    if not manager or FrameIsForbidden(manager) then return end
    pcall(function()
        manager:UnregisterAllEvents()
        SafeHide(manager)
        if not InCombatLockdown() then
            ParkUnderHiddenParent(manager, ShouldHideBlizzardRaidManager)
            if CompactRaidFrameManager_SetSetting then
                CompactRaidFrameManager_SetSetting("IsShown", "0")
            end
        else
            looseParents[manager] = true
        end
    end)
    SetFrameAlpha(manager.container, 0)
    SetFrameAlpha(manager.toggleButton, 0)
    SetFrameAlpha(manager.displayFrame, 0)
end

ApplyEditModeOverlaySuppression = function()
    -- While Edit Mode is open, CompactRaidFrameContainer and CompactRaidFrameManager
    -- are managed by Blizzard's shared BottomManagedFrameContainer layout system --
    -- the same one that parents EssentialCooldownViewer/UtilityCooldownViewer.
    -- Calling Hide()/SetParent() on them here (as SafeHide/ParkUnderHiddenParent do)
    -- taints that shared managed-frame system and throws forbidden-table errors in
    -- Blizzard_CooldownViewer the next time it touches auraInstanceIDToItemFramesMap
    -- (cell bugs 01-04). Alpha/scale suppression via ShrinkContainer is the only
    -- taint-safe way to hide these frames while Edit Mode is active.
    if ShouldHideBlizzardRaid() then
        ShrinkContainer(_G.CompactRaidFrameContainer)
    end
    if ShouldHideBlizzardParty() then
        ShrinkContainer(_G.PartyFrame)
        ShrinkContainer(_G.CompactPartyFrame)
        HideGoldHighlights()
    elseif ShouldHideBlizzardRaid() then
        HideGoldHighlights()
    end
    if ShouldHideBlizzardRaidManager() then
        ShrinkContainer(_G.CompactRaidFrameManager)
    end
end

local function ApplyHiddenBlizzard()
    if ShouldHideBlizzardParty() then
        QuietTraditionalParty()
        QuietCompactParty()
    end
    if ShouldHideBlizzardRaid() then
        QuietCompactRaid()
    end
    if ShouldHideBlizzardRaidManager() then
        QuietRaidManager()
    end
    ApplyEditModeOverlaySuppression()
end

local raidStyleSwitchAttempted = false

-- Traditional (portrait-style) party frames are secure-templated for click-casting,
-- and every taint-avoidance approach tried for them (alpha, UnregisterAllEvents,
-- Hide, gated/ungated reparent -- see cell bugs from 2026-08-25) still lets Blizzard's
-- own RefreshPartyFrames chain throw "tainted by 'Cell'" errors on unrelated later
-- frame refreshes (opening the game menu, entering Edit Mode). The compact/raid-style
-- party frames (CompactPartyFrame) don't have this problem. Rather than leave
-- traditional-style users with broken frames, silently switch them to raid-style
-- party frames via the Edit Mode API the first time this is detected. Every step is
-- pcall-guarded and existence-checked: on any WoW build where this API doesn't match
-- (e.g. a Midnight API change), this just does nothing instead of erroring.
local function DebugRaidStyleSwitch(reason)
    F.Debug("|cff888888[RaidStyleSwitch debug]|r " .. reason)
end

local function TryEnableRaidStylePartyFrames()
    if raidStyleSwitchAttempted then return false end
    if InCombatLockdown() then DebugRaidStyleSwitch("skipped: in combat"); return false end
    if not ShouldHideBlizzardParty() then DebugRaidStyleSwitch("skipped: hideBlizzardParty is off"); return false end
    -- NOTE: deliberately NOT gating on IsTraditionalPartyStyleActive() (PartyFrame:IsShown())
    -- here -- by the time this runs, Cell's own KillFrame(pf) may have already Hide()'d
    -- PartyFrame earlier in the same TrySuppressForGroup pass, which would make IsShown()
    -- always false regardless of the actual Edit Mode setting. The setting value read
    -- from C_EditMode below is the actual source of truth and isn't affected by that.
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then
        raidStyleSwitchAttempted = true
        DebugRaidStyleSwitch("aborted: C_EditMode.GetLayouts/SaveLayouts missing on this build")
        return false
    end
    if not (Enum and Enum.EditModeSystem and Enum.EditModeUnitFrameSetting
        and Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames
        and Enum.EditModeUnitFrameSystemIndices and Enum.EditModeUnitFrameSystemIndices.Party) then
        raidStyleSwitchAttempted = true
        DebugRaidStyleSwitch("aborted: expected Enum.EditMode* constants missing on this build")
        return false
    end

    local ok, switched, why = pcall(function()
        local layoutInfo = C_EditMode.GetLayouts()
        if not (layoutInfo and layoutInfo.layouts and layoutInfo.activeLayout) then
            return false, "GetLayouts() returned no usable layoutInfo/activeLayout"
        end
        -- activeLayout isn't a positional index into .layouts. Confirmed live: Blizzard reserves
        -- IDs 1-2 for the two built-in presets ("Modern"/"Klassisch"), which are NOT included in
        -- .layouts -- only custom layouts are, starting at ID 3. So .layouts[activeLayout - 2] is
        -- the active entry (verified: activeLayout=6, 4 custom layouts, 4th one active -> 6-2=4).
        local activeLayout = layoutInfo.layouts[layoutInfo.activeLayout - 2]
        if not activeLayout then
            -- Fallback in case the "2 reserved preset IDs" assumption doesn't hold on some
            -- account/build: try common per-entry ID/active-flag fields before giving up.
            activeLayout = layoutInfo.layouts[layoutInfo.activeLayout]
            if not activeLayout then
                for _, entry in ipairs(layoutInfo.layouts) do
                    if entry.id == layoutInfo.activeLayout
                        or entry.layoutID == layoutInfo.activeLayout
                        or entry.ID == layoutInfo.activeLayout
                        or entry.isActive or entry.active then
                        activeLayout = entry
                        break
                    end
                end
            end
        end
        if not (activeLayout and activeLayout.systems) then
            if activeLayout then
                local keys = {}
                for k in pairs(activeLayout) do
                    keys[#keys + 1] = tostring(k)
                end
                return false, "matched layout has no .systems table -- actual keys: " .. table.concat(keys, ", ")
            end
            local first = layoutInfo.layouts[1]
            local parts = {}
            if first then
                for k, v in pairs(first) do
                    parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
                end
            end
            return false, string.format(
                "no layout matched activeLayout=%s [%s], #layouts=%d -- layouts[1]: {%s}",
                tostring(layoutInfo.activeLayout), type(layoutInfo.activeLayout), #layoutInfo.layouts,
                table.concat(parts, ", "))
        end

        local sawPartySystem = false
        for _, system in ipairs(activeLayout.systems) do
            if system.system == Enum.EditModeSystem.UnitFrame
                and system.systemIndex == Enum.EditModeUnitFrameSystemIndices.Party then
                sawPartySystem = true
                if system.settings then
                    for _, setting in ipairs(system.settings) do
                        if setting.setting == Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames then
                            if setting.value == 1 then
                                return false, "setting already 1 (raid-style already on?)"
                            end
                            setting.value = 1
                            -- NOTE: EditModeManagerFrame:UpdateSystem(system) is NOT safe to call
                            -- here -- confirmed live, it errors inside Blizzard's own
                            -- EditModeManager.lua (attempt to call a nil value), because it
                            -- expects an active Edit Mode UI session/state that isn't set up
                            -- outside of Edit Mode actually being open. SaveLayouts persists the
                            -- setting to SavedVariables either way; Blizzard picks it up the next
                            -- time it lays out the party frames (next login/reload at the latest,
                            -- possibly sooner via its own PLAYER_ENTERING_WORLD/EditMode refresh).
                            C_EditMode.SaveLayouts(layoutInfo)
                            if EditModeManagerFrame and EditModeManagerFrame.ApplyChanges then
                                pcall(EditModeManagerFrame.ApplyChanges, EditModeManagerFrame)
                            end
                            return true
                        end
                    end
                    return false, "party system found but no matching UseRaidStylePartyFrames setting entry"
                end
                return false, "party system found but has no .settings table"
            end
        end
        if not sawPartySystem then
            return false, "no system matched UnitFrame+Party systemIndex in active layout"
        end
        return false, "unknown"
    end)
    raidStyleSwitchAttempted = true

    if not ok then
        DebugRaidStyleSwitch("pcall errored: " .. tostring(switched))
        return false
    end
    if switched then
        F.Print(L["raidStyleSwitchChatMsg"])
        pcall(function()
            local popup = Cell.CreateConfirmPopup(Cell.frames.anchorFrame, 260,
                L["raidStyleSwitchPopupText"],
                function() ReloadUI() end, nil, true, nil, nil, "raidStyleReloadPopup")
            popup.button1:SetText(_G.RELOADUI)
            popup.button1:SetSize(70, 15)
            popup.button2:SetSize(70, 15)
            popup.button1:ClearAllPoints()
            popup.button1:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -3, 16)
            popup.button2:ClearAllPoints()
            popup.button2:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 3, 16)
            popup:ClearAllPoints()
            -- Explicitly UIParent, not the popup's actual parent (Cell's own
            -- anchor frame), so it's centered on screen regardless of where
            -- the user has Cell's UI positioned.
            popup:SetPoint("CENTER", UIParent, "CENTER")
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
        end)
        return true
    end
    DebugRaidStyleSwitch(why or "not switched (no reason returned)")
    return false
end

local function HardDisableBlizzardFrames()
    if hardDisabled then return true end
    if InCombatLockdown() then return false end
    if not (ShouldHideBlizzardParty() or ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager()) then
        return false
    end

    pcall(function()
        if ShouldHideBlizzardParty() and ShouldHideBlizzardRaid() then
            UIParent:UnregisterEvent("GROUP_ROSTER_UPDATE")
        end
        if ShouldHideBlizzardRaid() and CompactRaidFrameContainer then
            CompactRaidFrameContainer:UnregisterAllEvents()
        end
        if ShouldHideBlizzardRaidManager() and CompactRaidFrameManager then
            CompactRaidFrameManager:UnregisterAllEvents()
            ParkUnderHiddenParent(CompactRaidFrameManager, ShouldHideBlizzardRaidManager)
            if CompactRaidFrameManager_SetSetting then
                CompactRaidFrameManager_SetSetting("IsShown", "0")
            end
        end
        if ShouldHideBlizzardParty() then
            InstallPartyMemberNoops()
            if CompactPartyFrame then
                CompactPartyFrame:UnregisterAllEvents()
            end
            if PartyFrame then
                PartyFrame:UnregisterAllEvents()
            end
        end
    end)

    ApplyHiddenBlizzard()
    hardDisabled = true
    return true
end

TrySuppressForGroup = function()
    if not raidStyleSwitchAttempted then
        C_Timer.After(0, TryEnableRaidStylePartyFrames)
    end
    if F.IsEditModeOpen() then
        ApplyEditModeOverlaySuppression()
        return
    end
    HardDisableBlizzardFrames()
    ApplyHiddenBlizzard()
end

local function QueueSuppress()
    C_Timer.After(0, TrySuppressForGroup)
end

local function ApplySuppressLuaErrors()
    if not CellDB or not CellDB["general"] then return end
    if CellDB["general"]["suppressLuaErrors"] == false then
        pcall(SetCVar, "scriptErrors", "1")
    else
        pcall(SetCVar, "scriptErrors", "0")
    end
end
F.ApplySuppressLuaErrors = ApplySuppressLuaErrors

local visibilityWatch = CreateFrame("Frame")
local visibilityElapsed = 0
visibilityWatch:SetScript("OnUpdate", function(_, elapsed)
    if not (ShouldHideBlizzardParty() or ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager()) then
        return
    end
    if F.IsEditModeOpen() then
        -- Edit Mode actively owns CompactRaidFrameContainer/CompactRaidFrameManager's
        -- scale/visibility while it's open (they share BottomManagedFrameContainer's
        -- layout with the Cooldown Viewers). Re-applying ApplyEditModeOverlaySuppression
        -- here every 0.2s fights that live management and taints the shared managed-frame
        -- system (cell bugs 01-03). EDIT_MODE_LAYOUTS_UPDATED and GROUP_ROSTER_UPDATE
        -- already reapply suppression once on the events that actually matter, so just
        -- leave these frames alone for as long as Edit Mode stays open.
        return
    end
    visibilityElapsed = visibilityElapsed + elapsed
    if visibilityElapsed < 0.2 then return end
    visibilityElapsed = 0
    if InCombatLockdown() then
        if ShouldHideBlizzardParty() then
            ForEachCompactPartyMember(StopCompactOnUpdate)
        end
        if ShouldHideBlizzardRaid() then
            ForEachCompactRaidMember(StopCompactOnUpdate)
        end
        ApplyEditModeOverlaySuppression()
        return
    end
    do
        local cpf = _G.CompactPartyFrame
        local container = _G.CompactRaidFrameContainer
        local manager = _G.CompactRaidFrameManager
        if (ShouldHideBlizzardParty() and cpf and cpf.IsShown and cpf:IsShown())
            or (ShouldHideBlizzardRaid() and container and container.IsShown and container:IsShown())
            or (ShouldHideBlizzardRaidManager() and manager and manager.IsShown and manager:IsShown()) then
            TrySuppressForGroup()
        end
    end
end)

local raidManagerShownHooked = false

local function HookEditMode()
end

local function HookRaidManagerShown()
    if raidManagerShownHooked then return end
    if type(_G.CompactRaidFrameManager_UpdateShown) ~= "function" then return end
    raidManagerShownHooked = true
    hooksecurefunc("CompactRaidFrameManager_UpdateShown", function()
        C_Timer.After(0, ApplyEditModeOverlaySuppression)
    end)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:RegisterEvent("PLAYER_TARGET_CHANGED")
boot:RegisterEvent("GROUP_ROSTER_UPDATE")
boot:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == "Blizzard_EditMode"
            or addonName == "Blizzard_UnitFrame"
            or addonName == "Blizzard_CompactRaidFrames"
            or addonName == "Blizzard_RaidFrame"
            or addonName == "Blizzard_Game" then
            C_Timer.After(0, function()
                HookEditMode()
                HookRaidManagerShown()
                TrySuppressForGroup()
            end)
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        C_Timer.After(0, HideGoldHighlights)
        return
    end

    if event == "EDIT_MODE_LAYOUTS_UPDATED" then
        C_Timer.After(0, function()
            local open = F.IsEditModeOpen()
            Cell.vars.editModeOpen = open
            ApplyEditModeOverlaySuppression()
            if not open then
                TrySuppressForGroup()
            end
        end)
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        if ShouldHideBlizzardParty() or ShouldHideBlizzardRaid() or ShouldHideBlizzardRaidManager() then
            C_Timer.After(0, TrySuppressForGroup)
        end
        return
    end

    C_Timer.After(0, function()
        HookEditMode()
        HookRaidManagerShown()
        ApplySuppressLuaErrors()
        TrySuppressForGroup()
    end)
end)

function F.HideBlizzardParty()
    hardDisabled = false
    QueueSuppress()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaid()
    hardDisabled = false
    QueueSuppress()
    C_Timer.After(0.5, TrySuppressForGroup)
end

function F.HideBlizzardRaidManager()
    hardDisabled = false
    QueueSuppress()
    C_Timer.After(0.5, TrySuppressForGroup)
end
