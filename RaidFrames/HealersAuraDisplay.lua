local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

local GROUP_KEY = "healers"
local INIT_VERSION = 38
local BUILD = select(4, GetBuildInfo())
local SUPPORTED = Cell.isRetail and BUILD >= 120100

local HARD_EXCLUDE_SPELLS = {
    [225788] = true,
    [186404] = true,
}

local stateByButton = setmetatable({}, { __mode = "k" })
local cachedConfig
local featureReady
local buildQueue = {}
local buildQueued = setmetatable({}, { __mode = "k" })
local buildTicker

local function EnsureAuraContainerLoaded()
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
end

local function ProbeSupported()
    if featureReady ~= nil then return featureReady end
    if not SUPPORTED then
        featureReady = false
        return false
    end
    EnsureAuraContainerLoaded()
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not container then
        featureReady = false
        return false
    end
    pcall(function()
        container:Hide()
        container:SetParent(UIParent)
        container:SetAlpha(0)
    end)
    featureReady = type(container.AddAuraGroup) == "function"
        and type(container.SetUnit) == "function"
        and type(container.SetEnabled) == "function"
    return featureReady
end

local function ResolveHealersConfig()
    local layout = Cell.vars.currentLayoutTable
    if not (layout and layout.indicators) then return end
    for _, t in ipairs(layout.indicators) do
        if t.name == "Healers" and t.enabled and t.auraType == "buff" and t.auras and t.indicatorName then
            return t
        end
    end
end

local function BuildSpellMap(auras)
    local map = {}
    if type(auras) ~= "table" then return map end
    for k, v in pairs(auras) do
        local n = tonumber(v)
        if not (n and n > 0) then n = tonumber(k) end
        if n and n > 0 then map[n] = true end
    end
    local alts = Cell.AuraBlacklist and Cell.AuraBlacklist.AlternateSpellIDs
    if type(alts) == "table" then
        for altId, primaryId in pairs(alts) do
            if map[primaryId] then
                map[altId] = true
            elseif map[altId] then
                map[primaryId] = true
            end
        end
    end
    return map
end

local function SpellMapCount(map)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

local function BuildExcludeSpellMap()
    local map = {}
    for id in pairs(HARD_EXCLUDE_SPELLS) do
        map[id] = true
    end

    local function addId(id)
        id = tonumber(id)
        if id and id > 0 then
            map[id] = true
        end
    end

    local function addAuraBlacklistTable(tbl)
        if type(tbl) ~= "table" then return end
        for spellId, entry in pairs(tbl) do
            if type(spellId) == "number" then
                if entry == true then
                    addId(spellId)
                elseif type(entry) == "table" and (entry.combat or entry.ooc) then
                    addId(spellId)
                end
            elseif type(entry) == "number" then
                addId(entry)
            end
        end
    end

    if CellDB and CellDB["auraBlacklist"] then
        addAuraBlacklistTable(CellDB["auraBlacklist"]["buffs"])
        addAuraBlacklistTable(CellDB["auraBlacklist"]["HELPFUL"])
    end

    local layout = Cell.vars and Cell.vars.currentLayoutTable
    if layout and layout.indicators then
        for _, t in ipairs(layout.indicators) do
            if t and t.enabled and t.auraType == "buff" and t.name ~= "Healers"
                and not t.keepInHealers and type(t.auras) == "table" then
                for k, v in pairs(t.auras) do
                    -- hasColor types (border/bars/blocks) store {spellId, color} pairs, not a plain
                    -- spellId -- tonumber(v) on that table is always nil, and falling back to the
                    -- array index k (not a real spell ID) silently excluded the wrong ID entirely
                    local n
                    if type(v) == "table" then
                        n = tonumber(v[1])
                    else
                        n = tonumber(v)
                        if not (n and n > 0) then n = tonumber(k) end
                    end
                    addId(n)
                end
            end
        end
    end

    local alts = Cell.AuraBlacklist and Cell.AuraBlacklist.AlternateSpellIDs
    if type(alts) == "table" then
        for altId, primaryId in pairs(alts) do
            if map[primaryId] then
                addId(altId)
            elseif map[altId] then
                addId(primaryId)
            end
        end
    end

    return map
end

local function BuildFilter(castBy)
    if castBy == "anyone" then
        return "HELPFUL"
    end
    return "HELPFUL|PLAYER"
end

local function ResolveUnit(unitButton)
    local unit = F.BD(unitButton).states and (F.BD(unitButton).states.displayedUnit or F.BD(unitButton).states.unit)
    if type(unit) == "string" and unit ~= "" then
        return unit
    end
    local attr = unitButton.GetAttribute and unitButton:GetAttribute("unit")
    if type(attr) == "string" and attr ~= "" then
        return attr
    end
end

local function StyleFont(fs, fontCfg, defaultSize)
    local font, size, outline, shadow
    if type(fontCfg) == "table" then
        font, size, outline, shadow = fontCfg[1], fontCfg[2], fontCfg[3], fontCfg[4]
    end
    size = size or defaultSize or 11
    local flags = "OUTLINE"
    if outline == "None" or outline == "" then
        flags = ""
    elseif outline == "Monochrome Outline" then
        flags = "OUTLINE,MONOCHROME"
    elseif outline == "Monochrome" then
        flags = "MONOCHROME"
    end
    local path = GameFontNormal:GetFont()
    if font and F.GetFont then
        local ok, resolved = pcall(F.GetFont, font)
        if ok and type(resolved) == "string" and resolved ~= "" then
            path = resolved
        end
    end
    if not pcall(fs.SetFont, fs, path, size, flags) then
        pcall(fs.SetFontObject, fs, GameFontNormalSmall)
    end
    if shadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
    fs:SetTextColor(1, 1, 1, 1)
end

local function GetCellDurationFormatter()
    return F.GetAuraDurationFormatter and F.GetAuraDurationFormatter() or nil
end

local function ResolveAnimationStyle(cfg)
    if type(cfg) == "table" and type(cfg.animationStyle) == "string" then
        local s = cfg.animationStyle
        if s == "none" or s == "vertical" or s == "clock" then
            return s
        end
    end
    if type(cfg) == "table" and cfg.showAnimation == false then
        return "none"
    end
    return "clock"
end

local function AttachInvisibleCooldown(button)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:EnableMouse(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetSwipeColor(0, 0, 0, 0)
    pcall(button.SetDurationCooldown, button, cooldown)
    return cooldown
end

local function InitAuraButton(button)
    local cfg = cachedConfig
    local size = (cfg and cfg.size and cfg.size[1]) or 13
    pcall(button.SetSize, button, size, size)
    F.SetupEngineAuraButtonMouse(button, not (cfg and cfg.showTooltip), cfg)
    if not F.InitEngineAuraButtonOnce(button) then
        if button._cellStackFS then
            button._cellStackFS:SetShown(not cfg or cfg.showStack ~= false)
        end
        if button._cellDurationFS and cfg and cfg.showDuration then
            F.BindAuraDurationText(button, button._cellDurationFS, GetCellDurationFormatter(), cfg.auras)
        end
        F.RestyleEngineAuraButtonFonts(button, cfg, StyleFont)
        return
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)

    local style = ResolveAnimationStyle(cfg)
    local animFrame

    if style == "none" then
        animFrame = AttachInvisibleCooldown(button)
    elseif style == "vertical" and type(button.SetDurationBar) == "function" then
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetAllPoints(button)
        bar:EnableMouse(false)
        bar:SetOrientation("VERTICAL")
        bar:SetReverseFill(true)
        bar:SetStatusBarTexture(Cell.vars.whiteTexture)
        local barTex = bar:GetStatusBarTexture()
        if barTex then
            barTex:SetVertexColor(0, 0, 0, 0.77)
        end
        local barOpts = {}
        if Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime then
            barOpts.direction = Enum.StatusBarTimerDirection.ElapsedTime
        end
        if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate then
            barOpts.interpolation = Enum.StatusBarInterpolation.Immediate
        end
        pcall(button.SetDurationBar, button, bar, barOpts)
        animFrame = bar
    else
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints(button)
        cooldown:EnableMouse(false)
        cooldown:SetHideCountdownNumbers(true)
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawBling(false)
        cooldown:SetReverse(true)
        if Cell.vars and Cell.vars.whiteTexture then
            cooldown:SetSwipeTexture(Cell.vars.whiteTexture)
            cooldown:SetSwipeColor(0, 0, 0, 0.77)
        end
        pcall(button.SetDurationCooldown, button, cooldown)
        animFrame = cooldown
    end

    local textHost = CreateFrame("Frame", nil, button)
    textHost:SetAllPoints(button)
    textHost:EnableMouse(false)
    textHost:SetFrameLevel(((animFrame and animFrame.GetFrameLevel and animFrame:GetFrameLevel()) or 1) + 4)
    button._cellAuraTextHost = textHost

    local stack = textHost:CreateFontString(nil, "OVERLAY")
    stack:SetJustifyH("RIGHT")
    button._cellStackFS = stack
    pcall(button.SetApplicationCount, button, stack, {})
    stack:SetShown(not cfg or cfg.showStack ~= false)

    if cfg and cfg.showDuration then
        local duration = textHost:CreateFontString(nil, "OVERLAY")
        duration:SetJustifyH("RIGHT")
        button._cellDurationFS = duration
        F.BindAuraDurationText(button, duration, GetCellDurationFormatter(), cfg.auras)
    end

    F.RestyleEngineAuraButtonFonts(button, cfg, StyleFont)
end

local function ResolveContainerParent(unitButton)
    if F.BD(unitButton).widgets and F.BD(unitButton).widgets.indicatorFrame then
        return F.BD(unitButton).widgets.indicatorFrame
    end
    return unitButton
end

local function HideLegacy(unitButton, indicatorName)
    local ind = F.BD(unitButton).indicators and indicatorName and F.BD(unitButton).indicators[indicatorName]
    if not ind then return end
    ind:Hide(true)
    if ind.SetAlpha then ind:SetAlpha(0) end
end

local function ShowLegacy(unitButton, indicatorName)
    local ind = F.BD(unitButton).indicators and indicatorName and F.BD(unitButton).indicators[indicatorName]
    if not ind then return end
    if ind.SetAlpha then ind:SetAlpha(1) end
end

local function MakeParkKey(cfg)
    local sizeW = (cfg and cfg.size and cfg.size[1]) or 13
    local sizeH = (cfg and cfg.size and cfg.size[2]) or 13
    return F.AuraParkKey(
        "healers",
        INIT_VERSION,
        sizeW,
        sizeH,
        ResolveAnimationStyle(cfg),
        cfg and cfg.showDuration,
        cfg and cfg.showStack ~= false,
        F.StampAuraFont(cfg and cfg.font),
        cfg and cfg.showTooltip
    )
end

local function DestroyContainer(st)
    if not (st and st.container) then return end
    st.parks = st.parks or {}
    F.ParkAuraContainer(st.parks, st.parkKey, st.container)
    st.container = nil
    st.boundUnit = nil
    st.parkKey = nil
end

local function AnchorContainer(container, unitButton, cfg)
    local sizeW = (cfg.size and cfg.size[1]) or 13
    local sizeH = (cfg.size and cfg.size[2]) or 13
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    local num = cfg.num or 5
    local numPerLine = cfg.numPerLine or num
    local pos = cfg.position or { "TOPRIGHT", "button", "TOPRIGHT", 0, 3 }
    local point = pos[1] or "TOPRIGHT"
    local relative = pos[2]
    local relativePoint = pos[3] or point
    local x, y = pos[4] or 0, pos[5] or 0

    local relativeTo = unitButton
    if relative == "healthBar" and F.BD(unitButton).widgets and F.BD(unitButton).widgets.healthBar then
        relativeTo = F.BD(unitButton).widgets.healthBar
    end

    container:ClearAllPoints()
    container:SetPoint(point, relativeTo, relativePoint, x, y)
    container:SetSize(1, 1)

    if container.SetFlowLayoutAnchorPoint then
        pcall(container.SetFlowLayoutAnchorPoint, container, point)
    end

    local orientation = cfg.orientation or "right-to-left"
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if FD and container.SetFlowLayoutGrowthDirection then
        local h, v = FD.Left, FD.Down
        if orientation == "left-to-right" then
            h, v = FD.Right, FD.Down
        elseif orientation == "top-to-bottom" then
            h, v = FD.Right, FD.Down
        elseif orientation == "bottom-to-top" then
            h, v = FD.Right, FD.Up
        end
        pcall(container.SetFlowLayoutGrowthDirection, container, h, v)
    end
    if container.SetFlowLayoutMaximumLineSize then
        local rowWidth = numPerLine * sizeW + math.max(numPerLine - 1, 0) * spacingX + 0.4
        if orientation == "top-to-bottom" or orientation == "bottom-to-top" then
            rowWidth = sizeH + 0.4
        end
        pcall(container.SetFlowLayoutMaximumLineSize, container, rowWidth)
    end
    if container.HasAuraGroup and container:HasAuraGroup(GROUP_KEY) and container.SetAuraGroupLayout then
        pcall(container.SetAuraGroupLayout, container, GROUP_KEY, {
            elementWidth = sizeW,
            elementHeight = sizeH,
            elementSpacing = spacingX,
            lineSpacing = spacingY,
        })
    end

    local parent = ResolveContainerParent(unitButton)
    container:SetFrameLevel((parent:GetFrameLevel() or 0) + (cfg.frameLevel or 5))
end

local function HealersGroupOpts(cfg)
    local sizeW = (cfg.size and cfg.size[1]) or 13
    local sizeH = (cfg.size and cfg.size[2]) or 13
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    local groupOpts = {
        maxFrameCount = cfg.num or 5,
        candidateFilters = {
            includeSpellIDs = BuildSpellMap(cfg.auras),
            excludeSpellIDs = BuildExcludeSpellMap(),
        },
        initializeFrame = InitAuraButton,
        layout = {
            elementWidth = sizeW,
            elementHeight = sizeH,
            elementSpacing = spacingX,
            lineSpacing = spacingY,
        },
    }
    if AuraContainerSortMethod and AuraContainerSortMethod.Default then
        groupOpts.sortMethod = AuraContainerSortMethod.Default
    end
    if AuraContainerSortDirection and AuraContainerSortDirection.Normal then
        groupOpts.sortDirection = AuraContainerSortDirection.Normal
    end
    return groupOpts
end

local function ApplyHealersTuning(container, cfg)
    if not (container and cfg) then return end
    F.ApplyAuraGroupTuning(container, GROUP_KEY, BuildFilter(cfg.castBy), HealersGroupOpts(cfg))
    F.RestyleAuraContainerFonts(container, cfg, StyleFont)
end

local function CreateHealersContainer(unitButton, cfg, existing)
    local spellMap = BuildSpellMap(cfg.auras)
    if SpellMapCount(spellMap) == 0 then
        return nil, "empty spell list"
    end

    local parent = ResolveContainerParent(unitButton)
    local container = existing
    if container then
        pcall(function()
            container:SetAlpha(1)
            container:SetParent(parent)
        end)
    else
        EnsureAuraContainerLoaded()
        local ok, created = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
        if not ok or not created then
            return nil, tostring(created)
        end
        container = created
    end

    local filter = BuildFilter(cfg.castBy)
    local unit = ResolveUnit(unitButton) or "player"
    local groupOpts = HealersGroupOpts(cfg)

    AnchorContainer(container, unitButton, cfg)

    if existing then
        F.ApplyAuraGroupTuning(container, GROUP_KEY, filter, groupOpts)
    else
        local addOk, addErr = pcall(container.AddAuraGroup, container, GROUP_KEY, filter, groupOpts)
        if not addOk then
            F.QuiesceAuraContainer(container)
            return nil, tostring(addErr)
        end
    end

    AnchorContainer(container, unitButton, cfg)
    pcall(container.SetUnit, container, unit)
    if container.UpdateAllAuras then
        pcall(container.UpdateAllAuras, container)
    end

    return container
end

function I.ForEachHealersAuraContainer(func)
    if not func then return end
    for _, st in pairs(stateByButton) do
        if st and st.container then
            func(st.container)
        end
    end
end

local function DriveContainer(unitButton, cfg, enable)
    local st = stateByButton[unitButton]
    if not (st and st.container and cfg) then return end
    if Cell.funcs.IsEditModeOpen and Cell.funcs.IsEditModeOpen() then
        return
    end
    local unit = ResolveUnit(unitButton)
    ApplyHealersTuning(st.container, cfg)
    AnchorContainer(st.container, unitButton, cfg)
    if enable then
        st.container:Show()
        if unit and st.boundUnit ~= unit then
            pcall(st.container.SetUnit, st.container, unit)
            st.boundUnit = unit
        end
        if st.container.UpdateAllAuras then
            pcall(st.container.UpdateAllAuras, st.container)
        end
        HideLegacy(unitButton, cfg.indicatorName)
    else
        st.container:Hide()
        ShowLegacy(unitButton, cfg.indicatorName)
    end
end

local function EnsureContainer(unitButton, cfg, allowCreate)
    if not ProbeSupported() then return false end
    local st = stateByButton[unitButton]
    if not st then
        st = {}
        stateByButton[unitButton] = st
    end

    if st.createFailed and st.failedVersion == INIT_VERSION then
        return false
    end
    if st.createFailed and st.failedVersion ~= INIT_VERSION then
        st.createFailed = nil
        st.failedVersion = nil
    end

    if st.container then
        local want = MakeParkKey(cfg)
        if st.parkKey ~= want or st.initVersion ~= INIT_VERSION or not st.container:GetParent() then
            DestroyContainer(st)
        end
    end

    if st.container then
        return true
    end

    if not allowCreate then
        return false
    end

    local want = MakeParkKey(cfg)
    st.parks = st.parks or {}
    local existing = F.AcquireParkedAuraContainer(st.parks, want, ResolveContainerParent(unitButton))
    local container, err = CreateHealersContainer(unitButton, cfg, existing)
    if not container then
        if existing then
            F.ParkAuraContainer(st.parks, want, existing)
        end
        st.createFailed = true
        st.failedVersion = INIT_VERSION
        if not Cell.vars._healersAuraDisplayWarned then
            Cell.vars._healersAuraDisplayWarned = true
            F.Print("|cFFFF7D7DHealers AuraContainer failed:|r " .. tostring(err))
        end
        return false
    end
    st.container = container
    st.parkKey = want
    st.boundUnit = ResolveUnit(unitButton)
    st.initVersion = INIT_VERSION
    st.createFailed = nil
    st.failedVersion = nil
    return true
end

local EnqueueBuild

local function PumpBuildQueue()
    buildTicker = nil
    local b = table.remove(buildQueue, 1)
    while b do
        buildQueued[b] = nil
        if F.BD(b)._indicatorsReady then
            break
        end
        b = table.remove(buildQueue, 1)
    end
    if not b then return end

    local cfg = cachedConfig or ResolveHealersConfig()
    cachedConfig = cfg
    if cfg and EnsureContainer(b, cfg, true) then
        DriveContainer(b, cfg, true)
    end

    if #buildQueue > 0 and not buildTicker then
        buildTicker = C_Timer.After(0, PumpBuildQueue)
    end
end

EnqueueBuild = function(unitButton)
    if not unitButton or buildQueued[unitButton] then return end
    buildQueued[unitButton] = true
    buildQueue[#buildQueue + 1] = unitButton
    if not buildTicker then
        buildTicker = C_Timer.After(0, PumpBuildQueue)
    end
end

local function SyncButton(unitButton, allowCreate)
    if not unitButton or not F.BD(unitButton)._indicatorsReady then return end
    -- Cache-aware like PumpBuildQueue above -- this runs once per button on
    -- every roster reshuffle, and the config only changes when the layout does.
    local cfg = cachedConfig or ResolveHealersConfig()
    cachedConfig = cfg
    if not cfg then
        local st = stateByButton[unitButton]
        if st then
            DestroyContainer(st)
        end
        return
    end

    if allowCreate == nil then
        allowCreate = true
    end

    if EnsureContainer(unitButton, cfg, false) then
        DriveContainer(unitButton, cfg, true)
    elseif allowCreate then
        EnqueueBuild(unitButton)
    end
end

function I.ShouldSkipLegacyHealers(indicatorTable)
    return ProbeSupported()
        and indicatorTable
        and indicatorTable.name == "Healers"
end

function I.HealersAuraDisplayActive()
    return ProbeSupported()
end

function I.SyncHealersAuraDisplay(unitButton)
    if not SUPPORTED then return end
    SyncButton(unitButton, true)
end

function I.UpdateHealersAuraDisplayUnit(unitButton)
    if not SUPPORTED then return end
    SyncButton(unitButton, true)
end

-- spreads SyncButton across multiple frames instead of one synchronous pass
local function ChunkedSyncAllButtons()
    local queue = {}
    local queued = {}
    F.IterateAllUnitButtons(function(b)
        if b and not queued[b] then
            queued[b] = true
            queue[#queue + 1] = b
        end
    end, true)
    if #queue == 0 then return end
    local idx = 1
    local function step()
        local budget = 4
        while budget > 0 and idx <= #queue do
            SyncButton(queue[idx], true)
            idx = idx + 1
            budget = budget - 1
        end
        if idx <= #queue then
            C_Timer.After(0, step)
        end
    end
    step()
end

function I.RefreshAllHealersAuraDisplays()
    if not SUPPORTED then return end
    cachedConfig = ResolveHealersConfig()
    ChunkedSyncAllButtons()
end

local function RebuildAllHealersAuraDisplays()
    if not SUPPORTED then return end
    cachedConfig = ResolveHealersConfig()
    F.IterateAllUnitButtons(function(b)
        local st = stateByButton[b]
        DestroyContainer(st)
        EnqueueBuild(b)
    end, true)
end

if SUPPORTED then
    Cell.RegisterCallback("UpdateIndicators", "HealersAuraDisplay_UpdateIndicators", function(layout, indicatorName, setting)
        local healersName
        local layoutTable = Cell.vars.currentLayoutTable
        if layoutTable and layoutTable.indicators then
            for _, t in ipairs(layoutTable.indicators) do
                if t.name == "Healers" then
                    healersName = t.indicatorName
                    break
                end
            end
        end
        -- "auras", "checkbutton" (covers "keep in Healers"), "create", "remove"
        -- and "enabled" can all change what OTHER buff indicators contribute to
        -- BuildExcludeSpellMap, so those always need a refresh regardless of
        -- which indicator changed -- only the purely cosmetic settings below
        -- are safe to skip when the change wasn't on the Healers indicator itself.
        local alwaysRefresh = setting == "auras" or setting == "checkbutton"
            or setting == "create" or setting == "remove" or setting == "enabled"
        if not alwaysRefresh and indicatorName and indicatorName ~= "" and indicatorName ~= "healers" and indicatorName ~= healersName then
            return
        end
        if not layout or not indicatorName or setting == "create" or setting == "remove"
            or setting == "auras" or setting == "position" or setting == "size"
            or setting == "num" or setting == "orientation" or setting == "spacing"
            or setting == "castBy" or setting == "enabled" or setting == "frameLevel"
            or setting == "showAnimation" or setting == "animationStyle"
            or setting == "showDuration" or setting == "showStack"
            or setting == "showTooltip"
            or setting == "checkbutton" or setting == "font" then
            C_Timer.After(0, I.RefreshAllHealersAuraDisplays)
        end
    end)

    Cell.RegisterCallback("UpdateLayout", "HealersAuraDisplay_UpdateLayout", function()
        C_Timer.After(0, I.RefreshAllHealersAuraDisplays)
    end)

    Cell.RegisterCallback("UpdateAppearance", "HealersAuraDisplay_UpdateAppearance", function(which)
        if which == nil or which == "icon" or which == "reset" then
            C_Timer.After(0, I.RefreshAllHealersAuraDisplays)
        end
    end)

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:RegisterEvent("PLAYER_REGEN_DISABLED")
    boot:RegisterEvent("PLAYER_REGEN_ENABLED")
    boot:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.5, I.RefreshAllHealersAuraDisplays)
            return
        end
        -- entering combat doesn't make anything stale -- only leaving does
        if event == "PLAYER_REGEN_DISABLED" then
            return
        end
        ChunkedSyncAllButtons()
    end)
end
