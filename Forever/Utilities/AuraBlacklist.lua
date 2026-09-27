
local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

local InCombatLockdown = InCombatLockdown
local pairs = pairs
local tinsert = table.insert

local AlternateSpellIDs = {
    [383648] = 974,
    [382021] = 382024,
    [382022] = 382024,
    [474750] = 474754,
    [474760] = 474754,
    [432496] = 432502,
    [457481] = 457496,
    [462742] = 462757,
    [390435] = 57723,
    [428628] = 57723,
    [264689] = 160455,
    [102352] = 102351,
    [188550] = 33763,
    [1245369] = 1244893,
    [1300009] = 1253593,
    [406220] = 406139,
    [381732] = 381748,  -- Death Knight
    [381741] = 381748,  -- Demon Hunter
    [381746] = 381748,  -- Druid
    [381749] = 381748,  -- Hunter
    [381750] = 381748,  -- Mage
    [381751] = 381748,  -- Monk
    [381752] = 381748,  -- Paladin
    [381753] = 381748,  -- Priest
    [381754] = 381748,  -- Rogue
    [381756] = 381748,  -- Shaman
    [381757] = 381748,  -- Warlock
    [381758] = 381748,  -- Warrior
}

local function ResolvePrimary(spellId)
    if spellId and AlternateSpellIDs[spellId] then
        return AlternateSpellIDs[spellId]
    end
    return spellId
end

local function IsBlacklistedState(entry)
    if not entry then return false end
    if entry == true then return true end
    if InCombatLockdown() then
        return entry.combat
    end
    return entry.ooc
end

function F.IsAuraBlacklisted(spellId, filter)
    if not spellId then return false end
    if not (CellDB and CellDB["auraBlacklist"]) then return false end

    local bl = CellDB["auraBlacklist"][filter]
    if not bl then
        if filter == "HARMFUL" then
            bl = CellDB["auraBlacklist"]["debuffs"]
        elseif filter == "HELPFUL" then
            bl = CellDB["auraBlacklist"]["buffs"]
        end
    end
    if not bl then return false end

    local entry = bl[spellId]
    if entry and IsBlacklistedState(entry) then return true end

    local pId = AlternateSpellIDs[spellId]
    if pId then
        entry = bl[pId]
        if entry and IsBlacklistedState(entry) then return true end
    end

    return false
end

function F.ToggleAuraBlacklist(spellId, filter, combat, ooc)
    if not spellId then return end

    local bl = CellDB["auraBlacklist"]
    if not bl[filter] then bl[filter] = {} end
    local list = bl[filter]

    if combat or ooc then
        list[spellId] = { combat = combat or false, ooc = ooc or false }
    else
        list[spellId] = nil
    end
end

function F.RemoveAuraBlacklist(spellId, filter)
    if not spellId or not filter then return end
    local list = CellDB["auraBlacklist"][filter]
    if list then
        list[spellId] = nil
    end
end

function F.GetAuraBlacklistEntry(spellId, filter)
    if not spellId or not filter then return nil end
    local list = CellDB["auraBlacklist"][filter]
    if not list then return nil end

    local entry = list[spellId]
    if entry then return entry end

    local primary = AlternateSpellIDs[spellId]
    if primary and list[primary] then
        return list[primary]
    end

    return nil
end

function F.GetAuraBlacklistCount(filter)
    local list = CellDB["auraBlacklist"][filter]
    if not list then return 0 end
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    return count
end


local iconCache = {}

local function GetSpellIcon(spellId)
    if iconCache[spellId] then return iconCache[spellId] end
    local ok, icon = pcall(function()
        return select(2, F.GetSpellInfo(spellId))
    end)
    if not ok or not icon then icon = 134400 end
    iconCache[spellId] = icon
    return icon
end

local function SpellEntry(spellId, display)
    return { spellId = spellId, display = display, icon = GetSpellIcon(spellId) }
end


local BuffSpellsBySpec = {
    DRUID = {
        [1] = { SpellEntry(1126, "Mark of the Wild"), },                     -- Balance
        [2] = { SpellEntry(1126, "Mark of the Wild"), },                     -- Feral
        [3] = { SpellEntry(1126, "Mark of the Wild"), },                     -- Guardian
        [4] = {                                                              -- Restoration
            SpellEntry(391891, "Adaptive Swarm"),
            SpellEntry(102351, "Cenarion Ward"),
            SpellEntry(155777, "Germination"),
            SpellEntry(383193, "Grove Tending"),
            SpellEntry(29166,  "Innervate"),
            SpellEntry(33763,  "Lifebloom"),
            SpellEntry(1126,   "Mark of the Wild"),
            SpellEntry(8936,   "Regrowth"),
            SpellEntry(774,    "Rejuvenation"),
            SpellEntry(474754, "Symbiotic Relationship"),
            SpellEntry(439530, "Symbiotic Blooms"),
            SpellEntry(48438,  "Wild Growth"),
        },
    },
    PRIEST = {
        [1] = {                                                              -- Discipline
            SpellEntry(194384, "Atonement"),
            SpellEntry(17,     "Power Word: Shield"),
            SpellEntry(21562,  "Power Word: Fortitude"),
            SpellEntry(41635,  "Prayer of Mending"),
            SpellEntry(139,    "Renew"),
            SpellEntry(453846, "Resonant Energy"),
            SpellEntry(1253593,"Void Shield"),
        },
        [2] = {                                                              -- Holy
            SpellEntry(77489,  "Echo of Light"),
            SpellEntry(17,     "Power Word: Shield"),
            SpellEntry(21562,  "Power Word: Fortitude"),
            SpellEntry(41635,  "Prayer of Mending"),
            SpellEntry(139,    "Renew"),
            SpellEntry(453846, "Resonant Energy"),
            SpellEntry(1253593,"Void Shield"),
        },
        [3] = {                                                              -- Shadow
            SpellEntry(21562,  "Power Word: Fortitude"),
            SpellEntry(1253593,"Void Shield"),
        },
    },
    PALADIN = {
        [1] = {                                                              -- Holy
            SpellEntry(148039, "Barrier of Faith"),
            SpellEntry(156910, "Beacon of Faith"),
            SpellEntry(53563,  "Beacon of Light"),
            SpellEntry(1244893,"Beacon of the Savior"),
            SpellEntry(200025, "Beacon of Virtue"),
            SpellEntry(223306, "Bestow Faith"),
            SpellEntry(431381, "Dawnlight"),
            SpellEntry(156322, "Eternal Flame"),
            SpellEntry(287280, "Glimmer of Light"),
            SpellEntry(432502, "Holy Armaments"),
            SpellEntry(433583, "Rite of Adjuration"),
            SpellEntry(433568, "Rite of Sanctification"),
            SpellEntry(1241717,"Seraphic Barrier"),
            SpellEntry(200654, "Tyr's Deliverance"),
        },
        [2] = {},                                                             -- Protection
        [3] = {},                                                            -- Retribution
    },
    SHAMAN = {
        [1] = {                                                              -- Elemental
            SpellEntry(462854, "Skyfury"),
            SpellEntry(369459, "Source of Magic"),
            SpellEntry(462757, "Thunderstrike Ward"),
            SpellEntry(20608,  "Reincarnation"),
        },
        [2] = {                                                              -- Enhancement
            SpellEntry(319778, "Flametongue Weapon"),
            SpellEntry(319773, "Windfury Weapon"),
            SpellEntry(462854, "Skyfury"),
            SpellEntry(369459, "Source of Magic"),
            SpellEntry(462757, "Thunderstrike Ward"),
            SpellEntry(20608,  "Reincarnation"),
        },
        [3] = {                                                              -- Restoration
            SpellEntry(207400, "Ancestral Vigor"),
            SpellEntry(974,    "Earth Shield"),
            SpellEntry(382024, "Earthliving Weapon"),
            SpellEntry(444490, "Hydrobubble"),
            SpellEntry(375986, "Primordial Wave"),
            SpellEntry(61295,  "Riptide"),
            SpellEntry(457496, "Tidecaller's Guard"),
            SpellEntry(462854, "Skyfury"),
            SpellEntry(369459, "Source of Magic"),
            SpellEntry(462757, "Thunderstrike Ward"),
            SpellEntry(20608,  "Reincarnation"),
        },
    },
    MONK = {
        [1] = {},                                                             -- Brewmaster
        [2] = {                                                              -- Mistweaver
            SpellEntry(450769, "Aspect of Harmony"),
            SpellEntry(406139, "Chi Cocoon"),
            SpellEntry(1292922,"Coalescence"),
            SpellEntry(325209, "Enveloping Breath"),
            SpellEntry(124682, "Enveloping Mist"),
            SpellEntry(467281, "Healing Elixir"),
            SpellEntry(450805, "Purified Spirit"),
            SpellEntry(119611, "Renewing Mist"),
            SpellEntry(115175, "Soothing Mist"),
        },
        [3] = {},                                                             -- Windwalker
    },
    EVOKER = {
        [1] = {                                                              -- Devastation
            SpellEntry(381748, "Blessing of the Bronze"),
            SpellEntry(410263, "Inferno's Blessing"),
            SpellEntry(369459, "Source of Magic"),
        },
        [2] = {                                                              -- Augmentation
            SpellEntry(360827, "Blistering Scales"),
            SpellEntry(395152, "Ebon Might"),
            SpellEntry(410089, "Prescience"),
            SpellEntry(413984, "Shifting Sands"),
            SpellEntry(381748, "Blessing of the Bronze"),
            SpellEntry(410686, "Symbiotic Bloom"),
            SpellEntry(369459, "Source of Magic"),
        },
        [3] = {                                                              -- Preservation
            SpellEntry(381748, "Blessing of the Bronze"),
            SpellEntry(409678, "Chrono Ward"),
            SpellEntry(355941, "Dream Breath"),
            SpellEntry(363502, "Dream Flight"),
            SpellEntry(378001, "Dream Projection"),
            SpellEntry(364343, "Echo"),
            SpellEntry(376788, "Echo Dream Breath"),
            SpellEntry(367364, "Echo Reversion"),
            SpellEntry(445740, "Enkindle"),
            SpellEntry(373267, "Lifebind"),
            SpellEntry(366155, "Reversion"),
            SpellEntry(409895, "Reverberations"),
            SpellEntry(369459, "Source of Magic"),
            SpellEntry(406789, "Spatial Paradox"),
            SpellEntry(410686, "Symbiotic Bloom"),
            SpellEntry(373862, "Temporal Anomaly"),
            SpellEntry(1291636,"Temporal Barrier"),
            SpellEntry(370889, "Twin Guardian"),
        },
    },
    MAGE = {
        SpellEntry(1459,   "Arcane Intellect"),
        SpellEntry(205473, "Icicles"),
    },
    WARRIOR = {
        SpellEntry(6673,   "Battle Shout"),
    },
    ROGUE = {
        SpellEntry(381664, "Amplifying Poison"),
        SpellEntry(381637, "Atrophic Poison"),
        SpellEntry(3408,   "Crippling Poison"),
        SpellEntry(2823,   "Deadly Poison"),
        SpellEntry(315584, "Instant Poison"),
        SpellEntry(5761,   "Numbing Poison"),
        SpellEntry(8679,   "Wound Poison"),
    },
    HUNTER = {
        SpellEntry(260286, "Tip of the Spear"),
    },
}

local mergedCache = {}

local function IsFlatFormat(entry)
    local k, v = next(entry)
    if not k then return true end
    return type(v) == "table" and v.spellId ~= nil
end

local DebuffSpells = {
    { spellId = 57723,  display = "Exhaustion",             icon = GetSpellIcon(57723) },
    { spellId = 160455, display = "Fatigued",               icon = GetSpellIcon(160455) },
    { spellId = 95809,  display = "Insanity",               icon = GetSpellIcon(95809) },
    { spellId = 57724,  display = "Sated",                  icon = GetSpellIcon(57724) },
    { spellId = 80354,  display = "Temporal Displacement",  icon = GetSpellIcon(80354) },
    { spellId = 26013,  display = "BG Deserter",            icon = GetSpellIcon(26013) },
    { spellId = 71041,  display = "Dungeon Deserter",       icon = GetSpellIcon(71041) },
    { spellId = 427490, display = "Ride Along Available",   icon = GetSpellIcon(427490) },
    { spellId = 447959, display = "Ride Along Active",      icon = GetSpellIcon(447959) },
    { spellId = 447960, display = "Ride Along Inactive",    icon = GetSpellIcon(447960) },
}

function F.GetAuraBlacklistBuffSpells(classToken, specIndex)
    if not classToken then return BuffSpellsBySpec end

    local entry = BuffSpellsBySpec[classToken]
    if not entry then return {} end

    if IsFlatFormat(entry) then
        return entry
    end

    if specIndex and entry[specIndex] then
        return entry[specIndex]
    end

    if not mergedCache[classToken] then
        local merged = {}
        local seen = {}
        for _, spells in pairs(entry) do
            for _, spell in ipairs(spells) do
                if not seen[spell.spellId] then
                    seen[spell.spellId] = true
                    tinsert(merged, spell)
                end
            end
        end
        mergedCache[classToken] = merged
    end
    return mergedCache[classToken]
end

function F.GetAuraBlacklistDebuffSpells()
    return DebuffSpells
end

F.AuraBlacklistClassOrder = {
    "DRUID", "PRIEST", "PALADIN", "SHAMAN", "MONK", "EVOKER",
    "MAGE", "WARRIOR", "ROGUE", "HUNTER",
}

F.AuraBlacklistClassNames = {
    DRUID   = "Druid",
    PRIEST  = "Priest",
    PALADIN = "Paladin",
    SHAMAN  = "Shaman",
    MONK    = "Monk",
    EVOKER  = "Evoker",
    MAGE    = "Mage",
    WARRIOR = "Warrior",
    ROGUE   = "Rogue",
    HUNTER  = "Hunter",
}

F.AuraBlacklistSpecNames = {
    DRUID   = { "Balance", "Feral", "Guardian", "Restoration" },
    PRIEST  = { "Discipline", "Holy", "Shadow" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    SHAMAN  = { "Elemental", "Enhancement", "Restoration" },
    MONK    = { "Brewmaster", "Mistweaver", "Windwalker" },
    EVOKER  = { "Devastation", "Augmentation", "Preservation" },
}

do
    local function InitDebuffDefaults()
        if not CellDB or not CellDB["auraBlacklist"] then return end
        if CellDB["auraBlacklist"]["_debuffInitDone"] == true then return end

        local db = CellDB["auraBlacklist"]["debuffs"]
        for _, spell in ipairs(DebuffSpells) do
            if not db[spell.spellId] then
                db[spell.spellId] = { combat = true, ooc = true }
            end
        end
        CellDB["auraBlacklist"]["_debuffInitDone"] = true
    end
    Cell.RegisterCallback("AddonLoaded", "AuraBlacklist_InitDebuffDefaults", InitDebuffDefaults)
end

Cell.AuraBlacklist = {
    AlternateSpellIDs = AlternateSpellIDs,
    BuffSpellsBySpec = BuffSpellsBySpec,
    DebuffSpells = DebuffSpells,
}
