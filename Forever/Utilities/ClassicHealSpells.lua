local _, Cell = ...
local F = Cell.funcs

--[[
    Spell Picker suggestions for Forever (Classic Era client). Retail's own database in
    Utilities/AuraBlacklist.lua lists many spells that don't exist here (they show up with a "?" icon),
    so the Spell Picker uses this list instead. Only spells that leave a lasting buff are listed, and
    entries the client doesn't know are dropped when the list is built.
]]

local FALLBACK_ICON = 134400

local SPELLS = {
    PRIEST = {
        17,    -- Power Word: Shield
        139,   -- Renew
        1243,  -- Power Word: Fortitude
        21562, -- Prayer of Fortitude
        14752, -- Divine Spirit
        27681, -- Prayer of Spirit
        976,   -- Shadow Protection
        27683, -- Prayer of Shadow Protection
        6346,  -- Fear Ward
        10060, -- Power Infusion
    },
    DRUID = {
        774,   -- Rejuvenation
        8936,  -- Regrowth
        1126,  -- Mark of the Wild
        21849, -- Gift of the Wild
        467,   -- Thorns
    },
    PALADIN = {
        20217, -- Blessing of Kings
        25898, -- Greater Blessing of Kings
        19740, -- Blessing of Might
        25782, -- Greater Blessing of Might
        19742, -- Blessing of Wisdom
        25894, -- Greater Blessing of Wisdom
        20911, -- Blessing of Sanctuary
        25899, -- Greater Blessing of Sanctuary
        1022,  -- Blessing of Protection
        1044,  -- Blessing of Freedom
        6940,  -- Blessing of Sacrifice
        1038,  -- Blessing of Salvation
    },
    SHAMAN = {
        324,   -- Lightning Shield
        974,   -- Earth Shield
        546,   -- Water Walking
        131,   -- Water Breathing
    },
    MAGE = {
        1459,  -- Arcane Intellect
        23028, -- Arcane Brilliance
        1008,  -- Amplify Magic
        604,   -- Dampen Magic
        130,   -- Slow Fall
    },
    WARLOCK = {
        132,   -- Detect Invisibility
        5697,  -- Unending Breath
    },
}

local CLASS_ORDER = { "PRIEST", "DRUID", "PALADIN", "SHAMAN", "MAGE", "WARLOCK" }

local built = {}

function F.GetClassicHealSpells(classToken)
    if not classToken then return SPELLS end
    if not built[classToken] then
        local list = {}
        for _, id in ipairs(SPELLS[classToken] or {}) do
            local name, icon = F.GetSpellInfo(id)
            if name then
                tinsert(list, { spellId = id, display = name .. (F.GetSpellRankSuffix and F.GetSpellRankSuffix(id) or ""), icon = icon or FALLBACK_ICON })
            end
        end
        built[classToken] = list
    end
    return built[classToken]
end

function F.GetClassicHealClassOrder()
    return CLASS_ORDER
end
