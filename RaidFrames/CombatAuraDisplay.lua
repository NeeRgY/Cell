local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

local INIT_VERSION = 57
local BUILD = select(4, GetBuildInfo())
local SUPPORTED = Cell.isRetail and BUILD >= 120100

local DISPEL_TYPE_ORDER = { "Magic", "Curse", "Disease", "Poison", "Bleed" }
local DISPEL_TYPE_LEVEL = { Magic = 1, Curse = 2, Disease = 3, Poison = 4, Bleed = 5 }
local EDGE_FADE_TOP = "Interface\\AddOns\\Cell\\Media\\Edge-Fade-Top"
local EDGE_FADE_BOTTOM = "Interface\\AddOns\\Cell\\Media\\Edge-Fade-Bottom"
local WHITE_TEXTURE = "Interface\\AddOns\\Cell\\Media\\white"
local DISPEL_FULL_ALPHA = 0.5

----------------------------------------------------
-- debuff-type border color (icon outline)
-- Uses Blizzard's official AddDispelTypeTexture API: you hand the engine a
-- plain, uncolored texture and it fills in the correct atlas/vertex-color/
-- visibility itself, per aura, entirely inside privileged code. This is the
-- sanctioned way to show a dispel-type decoration without ever reading the
-- (often secret) dispel type in our own insecure code.
----------------------------------------------------
local DISPEL_BORDER_STYLE = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
local DISPEL_BORDER_OPTS = DISPEL_BORDER_STYLE and {
    style = DISPEL_BORDER_STYLE,
    showWhenHarmful = true,
    showWhenHelpful = false,
}

local function RegisterDispelBorderStrips(button, edges)
    if not DISPEL_BORDER_OPTS then return end
    local addFn = button.AddDispelTypeTexture or button.SetAuraBorder
    if not addFn then return end
    for i = 1, #edges do
        pcall(addFn, button, edges[i], DISPEL_BORDER_OPTS)
    end
end

local stateByButton = setmetatable({}, { __mode = "k" })
local featureReady
local cachedLayouts

-- Set whenever something had to skip real work because of combat lockdown
-- (e.g. a container destroy got downgraded to a mere stop -- see SyncButton
-- below) and genuinely needs a catch-up pass once combat ends. PLAYER_REGEN_ENABLED
-- only pays for a full-raid resync when this is actually true, instead of
-- unconditionally re-driving every unit button on every single combat transition.
local needsCombatCatchup = false

-- ht is either the new {highlightType, opacity} pair or a bare legacy string.
local function NormalizeDispelHighlightType(ht)
    if type(ht) == "table" then
        ht = ht[1]
    end
    if ht == "none" then
        return "none"
    end
    if ht == "edge-top" then
        return "edge-top"
    end
    if ht == "edge-bottom" or ht == "gradient-sharp" then
        return "edge-bottom"
    end
    if ht == "full" or ht == "entire-solid" then
        return "full"
    end
    return "fill" -- "fill", legacy "entire", or unset
end

-- Returns 0-1. Legacy "entire"/"entire-solid" (no opacity saved) keep their old
-- fixed 50%/100% look; everything else uses the saved opacity slider value.
local function ResolveDispelHighlightOpacity(ht)
    local htType, opacity
    if type(ht) == "table" then
        htType, opacity = ht[1], ht[2]
    else
        htType = ht
    end
    if opacity then
        return opacity / 100
    end
    if htType == "entire-solid" or htType == "full" then
        return 1
    end
    return DISPEL_FULL_ALPHA
end

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

local function ResolveContainerParent(unitButton)
    if F.BD(unitButton).widgets and F.BD(unitButton).widgets.indicatorFrame then
        return F.BD(unitButton).widgets.indicatorFrame
    end
    return unitButton
end

local function JoinFilter(...)
    local n = select("#", ...)
    if n == 1 then return (select(1, ...)) end
    local t = {}
    for i = 1, n do
        t[i] = select(i, ...)
    end
    return table.concat(t, "|")
end

local TRACKED = {
    "crowdControls",
    "raidDebuffs",
    "debuffs",
    "dispels",
    "defensiveCooldowns",
    "offensiveCooldowns",
    "externalCooldowns",
    "allCooldowns",
}

local TRACKED_SET = {}
for i = 1, #TRACKED do
    TRACKED_SET[TRACKED[i]] = true
end

-- Latest cfg per indicator, kept fresh on every CreateIndicatorContainer call (both the
-- "build fresh" and "just resync" paths). MakeInitAuraButton/MakeInitDispelAuraButton read
-- from this instead of only using what their closure captured when it was created -- see
-- the comment on those functions for why that matters.
local currentConfigs = {}

local ALL_TRACKED = {}

local function IsHighlightDebuffCfg(t)
    return t and t.type == "highlightDebuffs" and type(t.indicatorName) == "string"
        and t.indicatorName:find("^indicator") and t.indicatorName ~= ""
end

local COOLDOWN_AURAS = {
    defensiveCooldowns = true,
    offensiveCooldowns = true,
    externalCooldowns = true,
    allCooldowns = true,
}

local function UseEngineCooldownAuras()
    return UnitAffectingCombat("player")
end

local function IsCooldownAuraIndicator(indicatorName)
    return COOLDOWN_AURAS[indicatorName]
end

local function RefreshCachedLayouts()
    if not cachedLayouts then
        cachedLayouts = {}
    else
        wipe(cachedLayouts)
    end
    wipe(ALL_TRACKED)
    for i = 1, #TRACKED do
        ALL_TRACKED[i] = TRACKED[i]
    end

    local layout = Cell.vars.currentLayoutTable
    if not (layout and layout.indicators) then return end
    for _, t in ipairs(layout.indicators) do
        if t.enabled and t.indicatorName then
            local isTracked = false
            for i = 1, #TRACKED do
                if t.indicatorName == TRACKED[i] then
                    isTracked = true
                end
            end
            if isTracked then
                cachedLayouts[t.indicatorName] = t
            elseif IsHighlightDebuffCfg(t) then
                cachedLayouts[t.indicatorName] = t
                ALL_TRACKED[#ALL_TRACKED + 1] = t.indicatorName
            end
        end
    end
end

-- Cooldown-aura indicators (Defensive/External/Offensive/All Cooldowns) switch
-- between the native engine container and the legacy Lua-driven display purely
-- based on UnitAffectingCombat (see UseEngineCooldownAuras above) -- so unlike
-- debuffs/dispels, THEY genuinely need a resync on every single combat
-- transition, not just when something got deferred. Only these indicators
-- justify the unconditional sweep in the boot handler below.
local function AnyCooldownAuraIndicatorActive()
    RefreshCachedLayouts()
    if not cachedLayouts then return false end
    for name in pairs(COOLDOWN_AURAS) do
        if cachedLayouts[name] then return true end
    end
    return false
end

local function ResolveSize(cfg)
    local s = cfg and cfg.size
    if type(s) == "table" and type(s[1]) == "table" then
        return s[1][1] or 13, s[1][2] or 13
    end
    return (s and s[1]) or 13, (s and s[2]) or 13
end

local PERSONAL_DEBUFF_IDS = {
    57723, 57724, 80354, 95809, 160455, 264689, 390435, 428628, 25771, 387847, 386124,
    113942, -- Demonic Gateway (90s "can't use another gateway" debuff)
}

local function BuildPersonalDebuffExcludeMap()
    local map = {}
    for i = 1, #PERSONAL_DEBUFF_IDS do
        map[PERSONAL_DEBUFF_IDS[i]] = true
    end
    return map
end

local function BuildExcludeSpellMap()
    local map = {}
    local function addId(id)
        id = tonumber(id)
        if id and id > 0 then
            map[id] = true
        end
    end

    if I.GetDefaultDebuffBlacklist then
        local defaults = I.GetDefaultDebuffBlacklist()
        if type(defaults) == "table" then
            for _, id in pairs(defaults) do
                addId(id)
            end
        end
    end

    if Cell.vars and type(Cell.vars.debuffBlacklist) == "table" then
        for id, v in pairs(Cell.vars.debuffBlacklist) do
            if v then addId(id) end
        end
    end
    if Cell.vars and type(Cell.vars.dispelBlacklist) == "table" then
        for id, v in pairs(Cell.vars.dispelBlacklist) do
            if v then addId(id) end
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
        addAuraBlacklistTable(CellDB["auraBlacklist"]["debuffs"])
        addAuraBlacklistTable(CellDB["auraBlacklist"]["HARMFUL"])
        addAuraBlacklistTable(CellDB["auraBlacklist"]["buffs"])
        addAuraBlacklistTable(CellDB["auraBlacklist"]["HELPFUL"])
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

local function CollectSpellIds(src, dest)
    if type(src) ~= "table" then return dest end
    for k, v in pairs(src) do
        local id = tonumber(k)
        if id and id > 0 and v then
            dest[id] = true
        end
        if type(v) == "number" and v > 0 then
            dest[v] = true
        end
    end
    return dest
end

local function FlattenClassSpellTree(tree, dest)
    if type(tree) ~= "table" then return dest end
    for k, v in pairs(tree) do
        if type(k) == "number" and k > 0 then
            dest[k] = true
            if type(v) == "table" then
                for subId in pairs(v) do
                    if type(subId) == "number" and subId > 0 then
                        dest[subId] = true
                    end
                end
            end
        elseif type(v) == "table" then
            FlattenClassSpellTree(v, dest)
        end
    end
    return dest
end

local cachedExcludeMap
local cachedDefMap
local cachedExtMap
local cachedOffMap

local function InvalidateCombatSpellMaps()
    cachedExcludeMap = nil
    cachedDefMap = nil
    cachedExtMap = nil
    cachedOffMap = nil
end

local function BuildDefensiveSpellMap()
    if cachedDefMap then return cachedDefMap end
    local map = CollectSpellIds(Cell.vars and Cell.vars.builtInDefensives, {})
    CollectSpellIds(Cell.vars and Cell.vars.customDefensives, map)
    if not next(map) and I.GetDefensives then
        FlattenClassSpellTree(I.GetDefensives(), map)
    end
    cachedDefMap = map
    return map
end

local function BuildExternalSpellMap()
    if cachedExtMap then return cachedExtMap end
    local map = CollectSpellIds(Cell.vars and Cell.vars.builtInExternals, {})
    CollectSpellIds(Cell.vars and Cell.vars.customExternals, map)
    if not next(map) and I.GetExternals then
        FlattenClassSpellTree(I.GetExternals(), map)
    end
    cachedExtMap = map
    return map
end

local function BuildOffensiveSpellMap()
    if cachedOffMap then return cachedOffMap end
    local map = CollectSpellIds(Cell.vars and Cell.vars.builtInOffensives, {})
    CollectSpellIds(Cell.vars and Cell.vars.customOffensives, map)
    if not next(map) and I.GetOffensives then
        FlattenClassSpellTree(I.GetOffensives(), map)
    end
    cachedOffMap = map
    return map
end

local function CountKeys(map)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

local function GetExcludeSpellMap()
    if cachedExcludeMap then return cachedExcludeMap end
    cachedExcludeMap = BuildExcludeSpellMap()
    return cachedExcludeMap
end

local function BuildRaidDebuffSpellMap()
    local map = {}
    local list = I.GetCurrentAreaDebuffs and I.GetCurrentAreaDebuffs()
    if type(list) ~= "table" then
        return map
    end
    for _, entry in pairs(list) do
        if type(entry) == "table" then
            local id = tonumber(entry.id)
            if id and id > 0 then
                map[id] = true
            end
        end
    end
    return map
end

local HIGHLIGHT_DEBUFF_CLASSES = {
    { key = "nonplayer",   kind = "cand",  cand = { isFromPlayerOrPlayerPet = false } },
    { key = "priority",    kind = "cand",  cand = { isPriorityAura = true } },
    { key = "cc",          kind = "token", token = "CROWD_CONTROL" },
    { key = "bossaura",    kind = "cand",  cand = { isBossAura = true } },
    { key = "roleaura",    kind = "cand",  cand = { isRoleAura = true } },
    { key = "raid",        kind = "token", token = "RAID" },
    { key = "raidcombat",  kind = "token", token = "RAID_IN_COMBAT" },
    { key = "dispellable", kind = "token", token = "RAID_PLAYER_DISPELLABLE" },
    { key = "dispeltyped", kind = "cand",  cand = { includeDispelTypes = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true } } },
}

local function BuildHighlightDebuffGroups(cfg, cand)
    local fc = cfg.filterClasses
    if type(fc) ~= "table" or not next(fc) then return {} end

    local groups = {}
    local negTokens = {} -- "!TOKEN" for every previously-enabled token class
    local negCand -- accumulated candidate-side negation for previously-enabled cand classes

    for i = 1, #HIGHLIGHT_DEBUFF_CLASSES do
        local class = HIGHLIGHT_DEBUFF_CLASSES[i]
        if fc[class.key] then
            local extra
            if negCand then
                extra = {}
                for k, v in pairs(negCand) do extra[k] = v end
            end

            if class.kind == "token" then
                local tokens = { "HARMFUL", class.token }
                for n = 1, #negTokens do tokens[#tokens + 1] = negTokens[n] end
                groups[#groups + 1] = {
                    key = "hd_" .. class.key,
                    filter = table.concat(tokens, "|"),
                    candidateFilters = cand(extra),
                    maxFrameCount = cfg.num or 3,
                }
                negTokens[#negTokens + 1] = "!" .. class.token
            else
                extra = extra or {}
                for k, v in pairs(class.cand) do extra[k] = v end
                groups[#groups + 1] = {
                    key = "hd_" .. class.key,
                    filter = "HARMFUL",
                    candidateFilters = cand(extra),
                    maxFrameCount = cfg.num or 3,
                }
                negCand = negCand or {}
                if class.cand.includeDispelTypes then
                    negCand.excludeDispelTypes = class.cand.includeDispelTypes
                elseif class.cand.isFromPlayerOrPlayerPet == false then
                    negCand.isFromPlayerOrPlayerPet = true
                else
                    for k, v in pairs(class.cand) do
                        if type(v) == "boolean" then
                            negCand[k] = not v
                        end
                    end
                end
            end
        end
    end

    return groups
end

local function BuildGroupsForIndicator(indicatorName, cfg)
    local groups = {}
    local exclude = GetExcludeSpellMap()
    local hasExclude = CountKeys(exclude) > 0

    local function cand(extra)
        local c
        if extra then
            c = {}
            for k, v in pairs(extra) do
                c[k] = v
            end
        else
            c = {}
        end
        if hasExclude then
            if c.excludeSpellIDs then
                for id in pairs(exclude) do
                    c.excludeSpellIDs[id] = true
                end
            else
                c.excludeSpellIDs = exclude
            end
        end
        if not next(c) then return nil end
        return c
    end

    if indicatorName == "crowdControls" then
        groups[#groups + 1] = {
            key = "cc",
            filter = JoinFilter("HARMFUL", "CROWD_CONTROL"),
            candidateFilters = cand(),
            maxFrameCount = cfg.num or 3,
        }
    elseif indicatorName == "raidDebuffs" or cfg.type == "highlightDebuffs" then
        local hdGroups = BuildHighlightDebuffGroups(cfg, cand)
        for i = 1, #hdGroups do
            groups[#groups + 1] = hdGroups[i]
        end
    elseif indicatorName == "debuffs" then
        local extra
        if cfg.nonPlayerAuras then
            extra = {
                excludeSpellIDs = BuildPersonalDebuffExcludeMap(),
                isFromPlayerOrPlayerPet = false,
            }
        end
        if cfg.dispellableByMe then
            local types = {}
            for i = 1, #DISPEL_TYPE_ORDER do
                local token = DISPEL_TYPE_ORDER[i]
                if I.CanDispel(token) then
                    types[token] = true
                end
            end
            if next(types) then
                extra = extra or {}
                extra.includeDispelTypes = types
            else
                return groups
            end
        end
        groups[#groups + 1] = {
            key = "deb",
            filter = "HARMFUL",
            candidateFilters = cand(extra),
            maxFrameCount = cfg.num or 3,
        }
    elseif indicatorName == "dispels" then
        local filters = cfg.filters or {}
        local filter
        if filters.dispellableByMe ~= false then
            filter = JoinFilter("HARMFUL", "RAID_PLAYER_DISPELLABLE")
        else
            filter = "HARMFUL"
        end
        for _, token in ipairs(DISPEL_TYPE_ORDER) do
            if filters[token] then
                groups[#groups + 1] = {
                    key = "dis_" .. string.lower(token),
                    filter = filter,
                    candidateFilters = cand({ includeDispelTypes = { [token] = true } }),
                    maxFrameCount = 1,
                    dispelToken = token,
                }
            end
        end
    elseif indicatorName == "defensiveCooldowns" then
        local map = BuildDefensiveSpellMap()
        if next(map) then
            groups[#groups + 1] = {
                key = "def",
                filter = "HELPFUL",
                candidateFilters = cand({ includeSpellIDs = map }),
                maxFrameCount = cfg.num or 5,
            }
        end
    elseif indicatorName == "offensiveCooldowns" then
        local map = BuildOffensiveSpellMap()
        if next(map) then
            groups[#groups + 1] = {
                key = "off",
                filter = "HELPFUL",
                candidateFilters = cand({ includeSpellIDs = map }),
                maxFrameCount = cfg.num or 5,
            }
        end
    elseif indicatorName == "externalCooldowns" then
        local map = BuildExternalSpellMap()
        if next(map) then
            groups[#groups + 1] = {
                key = "ext",
                filter = "HELPFUL",
                candidateFilters = cand({ includeSpellIDs = map }),
                maxFrameCount = cfg.num or 5,
            }
        end
    elseif indicatorName == "allCooldowns" then
        local map = BuildDefensiveSpellMap()
        CollectSpellIds(BuildExternalSpellMap(), map)
        if next(map) then
            groups[#groups + 1] = {
                key = "allcd",
                filter = "HELPFUL",
                candidateFilters = cand({ includeSpellIDs = map }),
                maxFrameCount = cfg.num or 5,
            }
        end
    end

    return groups
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

local function MakeInitDispelAuraButton(cfg, token, unitButton)
    return function(button)
        -- Re-read the live config every call -- see MakeInitAuraButton's comment below for
        -- why the closure's own captured `cfg` goes stale.
        cfg = currentConfigs["dispels"] or cfg
        local sizeW, sizeH = ResolveSize(cfg)
        local iconStyle = cfg.iconStyle or "blizzard"
        local showIcons = iconStyle ~= "none"
        -- Size (like MakeInitAuraButton) is re-applied on every call, not just the first --
        -- this used to sit after the InitEngineAuraButtonOnce early-return below, so a
        -- reused/pooled button never picked up a later size change at all.
        if showIcons then
            pcall(button.SetSize, button, sizeW, sizeH)
        else
            pcall(button.SetSize, button, 0.001, 0.001)
        end
        if not F.InitEngineAuraButtonOnce(button) then
            return
        end
        local mode = NormalizeDispelHighlightType(cfg and cfg.highlightType)
        local health = unitButton and F.BD(unitButton).widgets and F.BD(unitButton).widgets.healthBar
        local r, g, b = I.GetDebuffTypeColor(token)
        r, g, b = r or 1, g or 1, b or 1
        local isEdge = mode == "edge-top" or mode == "edge-bottom"
        local alpha = isEdge and 1 or ResolveDispelHighlightOpacity(cfg and cfg.highlightType)
        local asset = WHITE_TEXTURE
        if mode == "edge-top" then
            asset = EDGE_FADE_TOP
        elseif mode == "edge-bottom" then
            asset = EDGE_FADE_BOTTOM
        end
        F.SetupEngineAuraButtonMouse(button, true)

        if health and mode ~= "none" then
            local overlay = button:CreateTexture(nil, "ARTWORK", nil, 3)
            overlay:ClearAllPoints()
            if mode == "fill" then
                -- Tied to the current health-bar FILL, not the whole frame.
                local fillTex = health:GetStatusBarTexture()
                overlay:SetPoint("TOPLEFT", health, "TOPLEFT")
                overlay:SetPoint("BOTTOMRIGHT", fillTex or health, "BOTTOMRIGHT")
            else
                overlay:SetAllPoints(health)
            end
            overlay:SetTexture(asset)
            overlay:SetTexCoord(0, 1, 0, 1)
            overlay:SetVertexColor(r, g, b, alpha)
            overlay:Show()
            local lvl = (health.GetFrameLevel and health:GetFrameLevel() or 1)
                + 1 + (DISPEL_TYPE_LEVEL[token] or 1)
            pcall(button.SetFrameLevel, button, lvl)
        end

        if showIcons then
            local tex = button:CreateTexture(nil, "ARTWORK", nil, 6)
            tex:SetAllPoints(button)
            if iconStyle == "rhombus" then
                tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Debuffs\\Rhombus")
                tex:SetVertexColor(r, g, b, 1)
            else
                tex:SetTexture("Interface\\AddOns\\Cell\\Media\\Debuffs\\" .. token)
                tex:SetVertexColor(1, 1, 1, 1)
            end
        end

        -- Frame border: strips anchored to the health bar (not the whole unit frame,
        -- so it doesn't wrap the power bar too), owned by this per-token button so
        -- they inherit its show/hide from Blizzard's engine automatically -- same
        -- technique as the health-bar overlay above, just anchored differently. No
        -- extra "which token is active" tracking needed.
        if unitButton and health and cfg.showDispelFrameBorder == true then
            local bt = cfg.thickness or 3
            local lvl = (unitButton.GetFrameLevel and unitButton:GetFrameLevel() or 1)
                + 40 + (DISPEL_TYPE_LEVEL[token] or 1)
            pcall(button.SetFrameLevel, button, lvl)

            local function mkStrip()
                local s = button:CreateTexture(nil, "OVERLAY")
                s:SetColorTexture(r, g, b, 1)
                return s
            end
            local top = mkStrip()
            top:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
            top:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
            top:SetHeight(bt)
            local bottom = mkStrip()
            bottom:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
            bottom:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            bottom:SetHeight(bt)
            local left = mkStrip()
            left:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
            left:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
            left:SetWidth(bt)
            local right = mkStrip()
            right:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
            right:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            right:SetWidth(bt)
        end
    end
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

-- Re-reads the live config on every call instead of only ever using what this closure
-- captured when it was created. Necessary because F.ApplyAuraGroupTuning -- the "retune an
-- already-registered aura group" sync path, taken on every regular resync once a group
-- exists -- never updates the group's initializeFrame callback; only a genuine
-- destroy+AddAuraGroup (a real rebuild, e.g. from a changed park key) does. So a button that
-- gets reused for a LATER aura on an already-registered group kept calling the ORIGINAL,
-- now-stale closure forever -- a size/animation/etc change only ever reached brand-new
-- buttons, never recycled ones (confirmed: "Debuffs" size changes only applied to the next
-- NEW debuff instance, not ones reusing an existing pooled button). HealersAuraDisplay.lua
-- never had this problem because it uses a single static init function reading a shared
-- cachedConfig instead of a fresh closure per build -- same fix, applied here too.
local function MakeInitAuraButton(cfg, unit, wantBorder, indicatorName)
    return function(button)
        cfg = currentConfigs[indicatorName] or cfg
        local sizeW, sizeH = ResolveSize(cfg)
        pcall(button.SetSize, button, sizeW, sizeH)
        F.SetupEngineAuraButtonMouse(button, cfg.showTooltip ~= true, cfg)
        if not F.InitEngineAuraButtonOnce(button) then
            if button._cellStackFS then
                button._cellStackFS:SetShown(cfg.showStack ~= false)
            end
            if button._cellDurationFS and cfg.showDuration then
                F.BindAuraDurationText(button, button._cellDurationFS, GetCellDurationFormatter(), cfg.auras)
            end
            F.RestyleEngineAuraButtonFonts(button, cfg, StyleFont)
            return
        end

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pcall(button.SetIcon, button, icon)

        -- Highlight Debuffs / Debuffs: optional per-icon glow (native-engine-safe,
        -- EngineGlow.lua) -- off by default. Retail only; Classic keeps whatever it already has.
        if Cell.isRetail and (indicatorName == "raidDebuffs" or indicatorName == "debuffs")
            and cfg.highlightDebuffGlow and F.StartEngineGlow then
            local glowFrame = CreateFrame("Frame", nil, button)
            glowFrame:EnableMouse(false)
            glowFrame:SetAllPoints(button)
            F.StartEngineGlow(glowFrame, "proc", 1, 0.85, 0.1, 1)
        end

        if wantBorder and DISPEL_BORDER_OPTS then
            -- Four thin edge strips, fully within the button's own bounds (immune to
            -- both re-anchoring by SetIcon and clipping by the container's grid
            -- layout). Flat white base: the engine multiplies its dispel color in via
            -- SetVertexColor once registered -- an uncolored texture has nothing for
            -- the engine to tint. Hidden on creation; the engine is what shows these
            -- once registered via AddDispelTypeTexture below.
            local t = cfg.thickness or 3
            local edges = {}
            local top = button:CreateTexture(nil, "OVERLAY")
            top:SetColorTexture(1, 1, 1, 1)
            top:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
            top:SetHeight(t)
            top:Hide()
            edges[1] = top
            local bottom = button:CreateTexture(nil, "OVERLAY")
            bottom:SetColorTexture(1, 1, 1, 1)
            bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
            bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            bottom:SetHeight(t)
            bottom:Hide()
            edges[2] = bottom
            local left = button:CreateTexture(nil, "OVERLAY")
            left:SetColorTexture(1, 1, 1, 1)
            left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
            left:SetWidth(t)
            left:Hide()
            edges[3] = left
            local right = button:CreateTexture(nil, "OVERLAY")
            right:SetColorTexture(1, 1, 1, 1)
            right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
            right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            right:SetWidth(t)
            right:Hide()
            edges[4] = right
            button._cellDebuffBorder = edges
            RegisterDispelBorderStrips(button, edges)
        end

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
        local baseLevel = (animFrame and animFrame.GetFrameLevel and animFrame:GetFrameLevel())
            or (button.GetFrameLevel and button:GetFrameLevel())
            or 1
        textHost:SetFrameLevel(baseLevel + 10)
        button._cellAuraTextHost = textHost

        local stack = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        stack:SetJustifyH("RIGHT")
        button._cellStackFS = stack
        pcall(button.SetApplicationCount, button, stack, {})
        stack:SetShown(cfg.showStack ~= false)

        if cfg.showDuration then
            local duration = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            duration:SetJustifyH("RIGHT")
            button._cellDurationFS = duration
            F.BindAuraDurationText(button, duration, GetCellDurationFormatter(), cfg.auras)
        end

        F.RestyleEngineAuraButtonFonts(button, cfg, StyleFont)
    end
end

local function HideLegacy(unitButton, indicatorName)
    local ind = F.BD(unitButton).indicators and indicatorName and F.BD(unitButton).indicators[indicatorName]
    if not ind then return end
    if indicatorName == "dispels" then
        if type(ind) == "table" then
            for i = 1, 10 do
                local child = ind[i]
                if child and child.Hide then
                    pcall(child.Hide, child)
                end
            end
        end
        return
    end
    if indicatorName == "debuffs" or indicatorName == "raidDebuffs" then
        if ind.Show then
            pcall(ind.Show, ind)
        end
        if ind.SetAlpha then
            ind:SetAlpha(1)
        end
        if type(ind) == "table" then
            for i = 1, 10 do
                local child = ind[i]
                if child and child.Hide then
                    pcall(child.Hide, child)
                end
            end
        end
        if indicatorName == "raidDebuffs" and ind.HideGlow then
            pcall(ind.HideGlow, ind)
        end
        return
    end
    if ind.Hide then
        pcall(ind.Hide, ind, true)
    end
    if ind.SetAlpha then ind:SetAlpha(0) end
    if type(ind) == "table" then
        for i = 1, 10 do
            local child = ind[i]
            if child and child.Hide then
                pcall(child.Hide, child)
            end
        end
    end
end

local function ShowLegacy(unitButton, indicatorName)
    local ind = F.BD(unitButton).indicators and indicatorName and F.BD(unitButton).indicators[indicatorName]
    if not ind then return end
    if ind.SetAlpha then ind:SetAlpha(1) end
end

local function StopContainer(st)
    if not (st and st.container) then return end
    pcall(st.container.Hide, st.container)
    if st.hlContainer then
        pcall(st.hlContainer.Hide, st.hlContainer)
    end
    st.boundUnit = nil
end

local paPending = {}
local paWait = CreateFrame("Frame")
paWait:SetScript("OnEvent", function()
    paWait:UnregisterEvent("PLAYER_REGEN_ENABLED")
    for st, fn in pairs(paPending) do
        paPending[st] = nil
        pcall(fn)
    end
end)

local function ClearDebuffPrivateAuras(st)
    if not (st and st.paAnchorIDs) then return end
    if InCombatLockdown() then
        paPending[st] = function()
            ClearDebuffPrivateAuras(st)
        end
        paWait:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor then
        for i = 1, #st.paAnchorIDs do
            if st.paAnchorIDs[i] then
                pcall(C_UnitAuras.RemovePrivateAuraAnchor, st.paAnchorIDs[i])
            end
        end
    end
    wipe(st.paAnchorIDs)
    -- The anchors we just removed were created with whatever size/num/etc was live at
    -- BindDebuffPrivateAuras' last call -- Blizzard bakes iconWidth/iconHeight into the
    -- anchor at creation time, it can't be resized in place. Forget the bound unit so the
    -- next DriveContainer call takes the "unit changed" branch (BindDebuffPrivateAuras,
    -- a real teardown+recreate) instead of LayoutDebuffPrivateAuras (which only moves/resizes
    -- the invisible holder frame, not the actual icon anchors). Otherwise a settings change
    -- (e.g. size) never reaches the private-aura icons for a unit whose token never changes
    -- (e.g. "player").
    st.paUnit = nil
end

local function LayoutDebuffPrivateAuras(st, unitButton, cfg)
    if not (st and st.paHolders) then return end
    local sizeW, sizeH = ResolveSize(cfg)
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    local num = math.min(cfg.num or 3, 5)
    local pos = cfg.position or { "BOTTOMLEFT", "button", "BOTTOMLEFT", 1, 4 }
    local point = pos[1] or "BOTTOMLEFT"
    local relative = pos[2]
    local relativePoint = pos[3] or point
    local x, y = pos[4] or 0, pos[5] or 0
    local relativeTo = unitButton
    if relative == "healthBar" and F.BD(unitButton).widgets and F.BD(unitButton).widgets.healthBar then
        relativeTo = F.BD(unitButton).widgets.healthBar
    end
    local orientation = cfg.orientation or "left-to-right"
    for i = 1, #st.paHolders do
        local holder = st.paHolders[i]
        holder:ClearAllPoints()
        holder:SetSize(sizeW, sizeH)
        holder:SetFrameStrata("HIGH")
        if i == 1 then
            holder:SetPoint(point, relativeTo, relativePoint, x, y)
        else
            local prev = st.paHolders[i - 1]
            if orientation == "right-to-left" then
                holder:SetPoint("RIGHT", prev, "LEFT", -spacingX, 0)
            elseif orientation == "top-to-bottom" then
                holder:SetPoint("TOP", prev, "BOTTOM", 0, -spacingY)
            elseif orientation == "bottom-to-top" then
                holder:SetPoint("BOTTOM", prev, "TOP", 0, spacingY)
            else
                holder:SetPoint("LEFT", prev, "RIGHT", spacingX, 0)
            end
        end
        if i <= num then
            holder:Show()
        else
            holder:Hide()
        end
    end
end

local function BindDebuffPrivateAuras(st, unitButton, cfg, unit)
    if not (unit and C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor) then return end
    if InCombatLockdown() then
        paPending[st] = function()
            BindDebuffPrivateAuras(st, unitButton, cfg, ResolveUnit(unitButton) or unit)
        end
        paWait:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local parent = ResolveContainerParent(unitButton)
    local num = math.min(cfg.num or 3, 5)
    if not st.paHolders then
        st.paHolders = {}
        st.paAnchorIDs = {}
    end
    for i = 1, num do
        local holder = st.paHolders[i]
        if not holder then
            holder = CreateFrame("Frame", nil, parent)
            holder:EnableMouse(false)
            st.paHolders[i] = holder
        else
            holder:SetParent(parent)
        end
    end
    LayoutDebuffPrivateAuras(st, unitButton, cfg)
    ClearDebuffPrivateAuras(st)
    st.paAnchorIDs = st.paAnchorIDs or {}
    local sizeW, sizeH = ResolveSize(cfg)
    for i = 1, num do
        local holder = st.paHolders[i]
        local ok, anchorID = pcall(C_UnitAuras.AddPrivateAuraAnchor, {
            unitToken = unit,
            auraIndex = i,
            parent = holder,
            isContainer = false,
            showCountdownFrame = true,
            showCooldownFrame = true,
            showCountdownNumbers = false,
            iconInfo = {
                iconWidth = sizeW,
                iconHeight = sizeH,
                borderScale = sizeW / 16,
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = holder,
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
            },
        })
        if ok and anchorID then
            st.paAnchorIDs[i] = anchorID
        end
    end
    st.paUnit = unit
end

local function MakeParkKey(indicatorName, cfg)
    local sizeW, sizeH = ResolveSize(cfg)
    local groupSig = indicatorName or ""
    if indicatorName == "raidDebuffs" then
        groupSig = "rd_boss"
    elseif indicatorName == "debuffs" then
        groupSig = "deb:" .. (cfg and cfg.nonPlayerAuras and "1" or "0") .. (cfg and cfg.dispellableByMe and "1" or "0")
            .. ":" .. (cfg and cfg.showDispelBorder ~= false and "1" or "0") .. ":" .. tostring(cfg and cfg.thickness or 3)
    elseif indicatorName == "crowdControls" then
        groupSig = "cc"
    elseif indicatorName == "dispels" then
        local filters = cfg and cfg.filters or {}
        local parts = {}
        for i = 1, #DISPEL_TYPE_ORDER do
            local token = DISPEL_TYPE_ORDER[i]
            if filters[token] then
                parts[#parts + 1] = string.lower(token)
            end
        end
        groupSig = "dis:" .. table.concat(parts, ",")
            .. ":" .. (cfg and cfg.showDispelFrameBorder == true and "1" or "0") .. ":" .. tostring(cfg and cfg.thickness or 3)
    elseif indicatorName == "defensiveCooldowns" then
        groupSig = "def"
    elseif indicatorName == "offensiveCooldowns" then
        groupSig = "off"
    elseif indicatorName == "externalCooldowns" then
        groupSig = "ext"
    elseif indicatorName == "allCooldowns" then
        groupSig = "allcd"
    end
    return F.AuraParkKey(
        indicatorName,
        INIT_VERSION,
        sizeW,
        sizeH,
        ResolveAnimationStyle(cfg),
        cfg and cfg.showDuration,
        cfg and cfg.showStack ~= false,
        cfg and cfg.showTooltip,
        F.StampAuraFont(cfg and cfg.font),
        groupSig,
        indicatorName == "dispels" and (NormalizeDispelHighlightType(cfg and cfg.highlightType)
            .. ":" .. tostring(ResolveDispelHighlightOpacity(cfg and cfg.highlightType))) or "",
        cfg and cfg.iconStyle,
        (indicatorName == "raidDebuffs" or indicatorName == "debuffs") and (cfg and cfg.highlightDebuffGlow and "1" or "0") or ""
    )
end

local function DestroyContainer(st)
    if not st then return end
    ClearDebuffPrivateAuras(st)
    if st.paHolders then
        for i = 1, #st.paHolders do
            local holder = st.paHolders[i]
            if holder then
                holder:Hide()
                F.QuiesceAuraContainer(holder)
            end
        end
        st.paHolders = nil
    end
    if not st.container then return end
    StopContainer(st)
    st.parks = st.parks or {}
    if st.unitButton and F.IsHeaderAuraContainer(st.unitButton, st.container) then
        F.QuiesceAuraContainer(st.container)
    else
        F.ParkAuraContainer(st.parks, st.parkKey, st.container)
    end
    st.container = nil
    st.boundUnit = nil
    st.parkKey = nil
    if st.hlContainer then
        F.QuiesceAuraContainer(st.hlContainer)
        st.hlContainer = nil
    end
end

local function DestroyButtonState(unitButton)
    local map = stateByButton[unitButton]
    if not map then return end
    for _, st in pairs(map) do
        DestroyContainer(st)
    end
end

local function AnchorContainer(container, unitButton, cfg, indicatorName)
    local sizeW, sizeH = ResolveSize(cfg)
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    if indicatorName == "dispels" and not (cfg.spacing and cfg.spacing[1]) then
        spacingX = -math.floor(sizeW / 2)
        spacingY = -math.floor(sizeH / 2)
    end
    local num = cfg.num or 3
    if indicatorName == "dispels" then
        num = 5
    end
    local numPerLine = cfg.numPerLine or num
    local pos = cfg.position or { "TOPRIGHT", "button", "TOPRIGHT", 0, 0 }
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
    -- Old profiles can still carry the legacy 2-way "horizontal"/"vertical" values (from
    -- before this became a 4-way left/right/top/bottom dropdown) -- neither matches any of
    -- the checks below, so they silently fell through to the horizontal-row math/growth
    -- direction regardless of what was actually saved. Normalize them the same way
    -- ResolveBarOrientation (CustomAuraDisplay.lua) already does for the Bar indicator.
    local orientation = cfg.orientation or "left-to-right"
    if orientation == "horizontal" then
        orientation = "left-to-right"
    elseif orientation == "vertical" then
        orientation = "top-to-bottom"
    end
    local rowW = numPerLine * sizeW + math.max(numPerLine - 1, 0) * math.abs(spacingX)
    local rowH = sizeH
    if orientation == "top-to-bottom" or orientation == "bottom-to-top" then
        rowW = sizeW
        rowH = numPerLine * sizeH + math.max(numPerLine - 1, 0) * math.abs(spacingY)
    end
    container:SetSize(math.max(rowW, 1), math.max(rowH, 1))
    pcall(container.SetClipsChildren, container, false)

    if container.SetFlowLayoutAnchorPoint then
        pcall(container.SetFlowLayoutAnchorPoint, container, point)
    end

    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if FD and container.SetFlowLayoutGrowthDirection then
        local h, v = FD.Right, FD.Down
        if orientation == "right-to-left" then
            h, v = FD.Left, FD.Down
        elseif orientation == "top-to-bottom" then
            h, v = FD.Right, FD.Down
        elseif orientation == "bottom-to-top" then
            h, v = FD.Right, FD.Up
        end
        pcall(container.SetFlowLayoutGrowthDirection, container, h, v)
    end
    if container.SetFlowLayoutMaximumLineSize then
        local rowWidth = numPerLine * sizeW + math.max(numPerLine - 1, 0) * math.abs(spacingX) + 0.4
        if orientation == "top-to-bottom" or orientation == "bottom-to-top" then
            rowWidth = sizeH + 0.4
        end
        pcall(container.SetFlowLayoutMaximumLineSize, container, rowWidth)
    end

    local parent = ResolveContainerParent(unitButton)
    container:SetFrameLevel((parent:GetFrameLevel() or 0) + (cfg.frameLevel or 5))
end

local function CombatLayout(cfg, indicatorName)
    local sizeW, sizeH = ResolveSize(cfg)
    local spacingX = (cfg.spacing and cfg.spacing[1]) or 0
    local spacingY = (cfg.spacing and cfg.spacing[2]) or 0
    if indicatorName == "dispels" and not (cfg.spacing and cfg.spacing[1]) then
        spacingX = -math.floor(sizeW / 2)
        spacingY = -math.floor(sizeH / 2)
    end
    return sizeW, sizeH, spacingX, spacingY
end

local function CombatGroupOpts(g, cfg, indicatorName, initFn)
    local sizeW, sizeH, spacingX, spacingY = CombatLayout(cfg, indicatorName)
    local groupOpts = {
        maxFrameCount = g.maxFrameCount or cfg.num or 3,
        layout = {
            elementWidth = sizeW,
            elementHeight = sizeH,
            elementSpacing = spacingX,
            lineSpacing = spacingY,
        },
    }
    if initFn then
        groupOpts.initializeFrame = initFn
    end
    if g.candidateFilters then
        groupOpts.candidateFilters = g.candidateFilters
    end
    if AuraContainerSortMethod and AuraContainerSortMethod.Default then
        groupOpts.sortMethod = AuraContainerSortMethod.Default
    end
    if AuraContainerSortDirection and AuraContainerSortDirection.Normal then
        groupOpts.sortDirection = AuraContainerSortDirection.Normal
    end
    return groupOpts
end

local function ApplyCombatTuning(container, indicatorName, cfg, st)
    if not (container and cfg) then return end
    local groups = BuildGroupsForIndicator(indicatorName, cfg)
    for i = 1, #groups do
        local g = groups[i]
        F.ApplyAuraGroupTuning(container, g.key, g.filter, CombatGroupOpts(g, cfg, indicatorName))
    end
    local stamp = F.StampAuraFont(cfg.font)
        .. "|" .. tostring(cfg.showDuration)
        .. "|" .. tostring(cfg.showStack ~= false)
        .. "|" .. ResolveAnimationStyle(cfg)
    if not st or st.styleStamp ~= stamp then
        F.RestyleAuraContainerFonts(container, cfg, StyleFont)
        if st then
            st.styleStamp = stamp
        end
    end
end

local function CreateIndicatorContainer(unitButton, indicatorName, cfg, existing)
    currentConfigs[indicatorName] = cfg
    local groups = BuildGroupsForIndicator(indicatorName, cfg)
    if #groups == 0 then
        return nil, "skip"
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
        -- Header-born container only on SecureGroupHeader children (party/raid).
        -- Spotlight/solo/NPC/pet have no button.AuraContainer — always CreateFrame.
        if indicatorName == "debuffs" and Cell.isMidnight then
            container = F.AdoptHeaderAuraContainer(unitButton, parent, "debuffs")
        end
        if not container then
            local ok, created = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
            if not ok or not created then
                return nil, tostring(created)
            end
            container = created
        end
    end

    local unit = ResolveUnit(unitButton) or "player"
    -- Debuff-type border: debuffs only for now, user-configurable (enabled + thickness).
    local wantBorder = indicatorName == "debuffs" and cfg.showDispelBorder ~= false
    local defaultInitFn = MakeInitAuraButton(cfg, unit, wantBorder, indicatorName)

    AnchorContainer(container, unitButton, cfg, indicatorName)

    local added = 0
    local lastErr
    for i = 1, #groups do
        local g = groups[i]
        local initFn = defaultInitFn
        if g.dispelToken then
            initFn = MakeInitDispelAuraButton(cfg, g.dispelToken, unitButton)
        end
        local groupOpts = CombatGroupOpts(g, cfg, indicatorName, initFn)
        local hasGroup = container.HasAuraGroup and container:HasAuraGroup(g.key)
        -- Deliberately not gated on `existing`: a header-adopted container can
        -- already have this group registered even though `existing` is nil, so
        -- only whether the group exists on THIS container decides retune vs. add.
        if (not container.HasAuraGroup) or hasGroup then
            F.ApplyAuraGroupTuning(container, g.key, g.filter, groupOpts)
            added = added + 1
        else
            local addOk, addErr = pcall(container.AddAuraGroup, container, g.key, g.filter, groupOpts)
            if addOk then
                added = added + 1
            else
                lastErr = addErr
            end
        end
    end
    if added == 0 then
        F.QuiesceAuraContainer(container)
        return nil, tostring(lastErr)
    end

    AnchorContainer(container, unitButton, cfg, indicatorName)
    pcall(container.SetUnit, container, unit)
    if container.UpdateAllAuras then
        pcall(container.UpdateAllAuras, container)
    end
    return container
end

function I.ForEachCombatAuraContainer(func)
    if not func then return end
    for _, map in pairs(stateByButton) do
        if type(map) == "table" then
            for _, st in pairs(map) do
                if st and st.container then
                    func(st.container)
                end
                if st and st.hlContainer then
                    func(st.hlContainer)
                end
            end
        end
    end
end

local function DriveContainer(unitButton, indicatorName, cfg, enable)
    local map = stateByButton[unitButton]
    local st = map and map[indicatorName]
    if not (st and st.container and cfg) then return end
    if Cell.funcs.IsEditModeOpen and Cell.funcs.IsEditModeOpen() then
        return
    end
    local unit = ResolveUnit(unitButton)
    ApplyCombatTuning(st.container, indicatorName, cfg, st)
    AnchorContainer(st.container, unitButton, cfg, indicatorName)
    if enable then
        st.container:Show()
        if unit and st.boundUnit ~= unit then
            pcall(st.container.SetUnit, st.container, unit)
            st.boundUnit = unit
        end
        if st.container.UpdateAllAuras then
            pcall(st.container.UpdateAllAuras, st.container)
        end
        if indicatorName == "debuffs" then
            if unit ~= st.paUnit then
                BindDebuffPrivateAuras(st, unitButton, cfg, unit)
            else
                LayoutDebuffPrivateAuras(st, unitButton, cfg)
            end
        end
        HideLegacy(unitButton, indicatorName)
    else
        if indicatorName == "debuffs" then
            ClearDebuffPrivateAuras(st)
        end
        StopContainer(st)
        ShowLegacy(unitButton, indicatorName)
    end
end

-- "Show Debuffs on Pet Frames" / "Show Highlight Debuffs on Pet Frames" (Layouts
-- -> Pet). Pet unit buttons are flagged by PetFrame.lua (button.isGroupPet); when
-- the relevant setting is off, treat that indicator for those buttons the same as
-- one with zero groups configured -- no container.
local PET_HIDE_SETTING_BY_INDICATOR = {
    debuffs = "showDebuffs",
    raidDebuffs = "showRaidDebuffs",
}
local function IsDebuffsHiddenOnPet(unitButton, indicatorName)
    local settingKey = PET_HIDE_SETTING_BY_INDICATOR[indicatorName]
    if not settingKey then return false end
    if not (unitButton and unitButton.isGroupPet) then return false end
    local layout = Cell.vars.currentLayoutTable
    return layout and layout["pet"] and layout["pet"][settingKey] == false
end

local function EnsureIndicatorContainer(unitButton, indicatorName, cfg, allowCreate)
    if not ProbeSupported() then return false end
    local map = stateByButton[unitButton]
    if not map then
        map = {}
        stateByButton[unitButton] = map
    end
    local st = map[indicatorName]
    if not st then
        st = {}
        map[indicatorName] = st
    end

    if IsDebuffsHiddenOnPet(unitButton, indicatorName) then
        DestroyContainer(st)
        HideLegacy(unitButton, indicatorName)
        st.createFailed = nil
        st.failedVersion = nil
        return false
    end

    if #(BuildGroupsForIndicator(indicatorName, cfg)) == 0 then
        DestroyContainer(st)
        st.createFailed = nil
        st.failedVersion = nil
        return false
    end

    if st.createFailed and st.failedVersion == INIT_VERSION then
        return false
    end
    if st.createFailed and st.failedVersion ~= INIT_VERSION then
        st.createFailed = nil
        st.failedVersion = nil
    end

    if st.container then
        local want = MakeParkKey(indicatorName, cfg)
        local changed = st.parkKey ~= want or st.initVersion ~= INIT_VERSION or not st.container:GetParent()
        if changed then
            DestroyContainer(st)
        end
    end

    if st.container then
        return true
    end

    if not allowCreate then
        return false
    end

    local want = MakeParkKey(indicatorName, cfg)
    st.parks = st.parks or {}
    local existing = F.AcquireParkedAuraContainer(st.parks, want, ResolveContainerParent(unitButton))
    local container, err = CreateIndicatorContainer(unitButton, indicatorName, cfg, existing)
    if not container then
        if existing then
            F.ParkAuraContainer(st.parks, want, existing)
        end
        if err == "skip" then
            st.createFailed = nil
            st.failedVersion = nil
            return false
        end
        st.createFailed = true
        st.failedVersion = INIT_VERSION
        if not Cell.vars._combatAuraDisplayWarned then
            Cell.vars._combatAuraDisplayWarned = true
            F.Print("|cFFFF7D7DCombat AuraContainer (" .. indicatorName .. ") failed:|r " .. tostring(err))
        end
        return false
    end
    st.container = container
    st.unitButton = unitButton
    st.parkKey = want
    st.boundUnit = ResolveUnit(unitButton)
    st.hlContainer = nil
    st.initVersion = INIT_VERSION
    st.highlightType = indicatorName == "dispels" and NormalizeDispelHighlightType(cfg.highlightType) or nil
    st.createFailed = nil
    st.failedVersion = nil
    return true
end

local buildQueue = {}
local buildQueued = setmetatable({}, { __mode = "k" })
local buildTicker

local EnqueueBuild

local function NeedsContainerBuild(unitButton, name, cfg)
    if not cfg then return false end
    if IsCooldownAuraIndicator(name) and not UseEngineCooldownAuras() then
        return false
    end
    if IsDebuffsHiddenOnPet(unitButton, name) or #(BuildGroupsForIndicator(name, cfg)) == 0 then
        return false
    end
    local map = stateByButton[unitButton]
    local st = map and map[name]
    if st and st.container then return false end
    if st and st.createFailed and st.failedVersion == INIT_VERSION then return false end
    return true
end

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

    -- cachedLayouts stays valid until RefreshAll/RebuildAll/DisableAll below
    -- explicitly rebuilds it, so no need to redo it for every queued button.
    if not cachedLayouts then RefreshCachedLayouts() end
    for i = 1, #ALL_TRACKED do
        local name = ALL_TRACKED[i]
        local cfg = cachedLayouts and cachedLayouts[name]
        if NeedsContainerBuild(b, name, cfg) then
            if EnsureIndicatorContainer(b, name, cfg, true) then
                DriveContainer(b, name, cfg, true)
            end
            break
        end
    end

    local more = false
    for i = 1, #ALL_TRACKED do
        local name = ALL_TRACKED[i]
        local cfg = cachedLayouts and cachedLayouts[name]
        if NeedsContainerBuild(b, name, cfg) then
            more = true
            break
        end
    end
    if more then
        EnqueueBuild(b)
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
    -- Same reasoning as PumpBuildQueue above.
    if not cachedLayouts then RefreshCachedLayouts() end
    if allowCreate == nil then
        allowCreate = true
    end

    local seen = {}
    local needsBuild = false
    for i = 1, #ALL_TRACKED do
        local name = ALL_TRACKED[i]
        local cfg = cachedLayouts and cachedLayouts[name]
        if cfg then
            seen[name] = true
            if IsCooldownAuraIndicator(name) and not UseEngineCooldownAuras() then
                if EnsureIndicatorContainer(unitButton, name, cfg, false) then
                    DriveContainer(unitButton, name, cfg, false)
                else
                    ShowLegacy(unitButton, name)
                end
            elseif EnsureIndicatorContainer(unitButton, name, cfg, false) then
                DriveContainer(unitButton, name, cfg, true)
            elseif NeedsContainerBuild(unitButton, name, cfg) then
                needsBuild = true
            end
        end
    end

    if needsBuild and allowCreate then
        EnqueueBuild(unitButton)
    end

    local map = stateByButton[unitButton]
    if map then
        for name, st in pairs(map) do
            if not seen[name] then
                if not InCombatLockdown() then
                    DestroyContainer(st)
                    map[name] = nil
                else
                    StopContainer(st)
                    needsCombatCatchup = true
                end
                if cachedLayouts and cachedLayouts[name] then
                    ShowLegacy(unitButton, name)
                else
                    HideLegacy(unitButton, name)
                end
            end
        end
    end
end

function I.ShouldSkipLegacyCombatAura(indicatorName, unitButton)
    if not ProbeSupported() or not indicatorName then
        return false
    end
    if IsCooldownAuraIndicator(indicatorName) and not UseEngineCooldownAuras() then
        return false
    end
    local tracked = false
    for i = 1, #TRACKED do
        if TRACKED[i] == indicatorName then
            tracked = true
            break
        end
    end
    if not tracked then
        return false
    end
    RefreshCachedLayouts()
    if not (cachedLayouts and cachedLayouts[indicatorName]) then
        return false
    end
    if unitButton then
        return I.HasCombatAuraContainer(unitButton, indicatorName)
    end
    return false
end

function I.CombatAuraDisplayActive()
    return ProbeSupported()
end

function I.HasCombatAuraContainer(unitButton, indicatorName)
    if not (unitButton and indicatorName) then return false end
    local map = stateByButton[unitButton]
    local st = map and map[indicatorName]
    return st and st.container and true or false
end

function I.SyncCombatAuraDisplays(unitButton)
    if not SUPPORTED then return end
    SyncButton(unitButton, true)
end

function I.UpdateCombatAuraDisplays(unitButton)
    if not SUPPORTED then return end
    SyncButton(unitButton, true)
end

function I.RefreshAllCombatAuraDisplays()
    if not SUPPORTED then return end
    InvalidateCombatSpellMaps()
    RefreshCachedLayouts()
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

local function RebuildAllCombatAuraDisplays()
    if not SUPPORTED then return end
    InvalidateCombatSpellMaps()
    RefreshCachedLayouts()
    F.IterateAllUnitButtons(function(b)
        DestroyButtonState(b)
        EnqueueBuild(b)
    end, true)
end

function I.RebuildAllCombatAuraDisplays()
    RebuildAllCombatAuraDisplays()
end

function I.DisableCombatAuraDisplay(unitButton, indicatorName)
    if not SUPPORTED or not unitButton or not indicatorName then return end
    local map = stateByButton[unitButton]
    local st = map and map[indicatorName]
    if st then
        if not InCombatLockdown() then
            DestroyContainer(st)
        else
            StopContainer(st)
        end
    end
    HideLegacy(unitButton, indicatorName)
end

function I.DisableAllCombatAuraDisplays(indicatorName)
    if not SUPPORTED or not indicatorName then return end
    RefreshCachedLayouts()
    F.IterateAllUnitButtons(function(b)
        I.DisableCombatAuraDisplay(b, indicatorName)
    end, true)
end

if SUPPORTED then
    Cell.RegisterCallback("UpdateIndicators", "CombatAuraDisplay_UpdateIndicators", function(_, indicatorName, setting, value)
        InvalidateCombatSpellMaps()
        if setting == "enabled" and value == false and indicatorName then
            I.DisableAllCombatAuraDisplays(indicatorName)
            return
        end
        if indicatorName and indicatorName ~= "" and not TRACKED_SET[indicatorName]
            and not tostring(indicatorName):find("^indicator") then
            return
        end
        C_Timer.After(0, I.RefreshAllCombatAuraDisplays)
    end)

    Cell.RegisterCallback("UpdateLayout", "CombatAuraDisplay_UpdateLayout", function()
        InvalidateCombatSpellMaps()
        C_Timer.After(0, I.RefreshAllCombatAuraDisplays)
    end)

    Cell.RegisterCallback("SpecChanged", "CombatAuraDisplay_SpecChanged", function()
        C_Timer.After(1.25, I.RefreshAllCombatAuraDisplays)
    end)

    Cell.RegisterCallback("UpdateAppearance", "CombatAuraDisplay_UpdateAppearance", function(which)
        if which == nil or which == "icon" or which == "reset" then
            C_Timer.After(0, I.RefreshAllCombatAuraDisplays)
        end
    end)

    Cell.RegisterCallback("RaidDebuffsChanged", "CombatAuraDisplay_RaidDebuffs", function()
        C_Timer.After(0, function()
            F.IterateAllUnitButtons(function(b)
                local map = stateByButton[b]
                if map then
                    for _, name in ipairs({ "raidDebuffs", "debuffs" }) do
                        local st = map[name]
                        if st then
                            st.createFailed = nil
                            st.failedVersion = nil
                            DestroyContainer(st)
                        end
                    end
                end
            end, true)
            I.RefreshAllCombatAuraDisplays()
        end)
    end)

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:RegisterEvent("PLAYER_REGEN_DISABLED")
    boot:RegisterEvent("PLAYER_REGEN_ENABLED")
    boot:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            InvalidateCombatSpellMaps()
            needsCombatCatchup = false
            C_Timer.After(0.5, I.RefreshAllCombatAuraDisplays)
            C_Timer.After(1.25, I.RefreshAllCombatAuraDisplays)
            return
        end
        -- Cache-clear only: cheap regardless of whether a full resync is needed.
        InvalidateCombatSpellMaps()
        -- Defensive/External/Offensive/All Cooldowns switch their whole display
        -- mode based on combat state (UseEngineCooldownAuras), so if any of them
        -- are in use, both transitions still need the real resync -- skipping it
        -- left them showing nothing at all (in and out of combat) once the mode
        -- flipped out from under them without ever being re-applied.
        if AnyCooldownAuraIndicatorActive() then
            needsCombatCatchup = false
            I.RefreshAllCombatAuraDisplays()
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            -- Entering combat doesn't itself make anything else stale -- real
            -- config/roster/layout changes already drive their own refresh
            -- independent of combat state (UpdateIndicators/UpdateLayout/
            -- RaidDebuffsChanged callbacks above). Nothing to catch up on yet.
            return
        end
        -- Leaving combat: only pay for a full-raid resync of every unit button
        -- and every tracked indicator if something was actually deferred while
        -- combat-locked (see needsCombatCatchup writers above). Previously this
        -- ran unconditionally on every single combat exit, which is why the
        -- hitch scaled with how much happened during the fight.
        if needsCombatCatchup then
            needsCombatCatchup = false
            I.RefreshAllCombatAuraDisplays()
        end
    end)
end
