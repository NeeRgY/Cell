local _, Cell = ...
local F = Cell.funcs

--[[
    Classic/TBC-only Spell Picker suggestions (Retail's own database in Utilities/AuraBlacklist.lua
    isn't loaded here). Only lists spells that leave a lasting buff - instant heals with no aura
    would never show up anyway.
]]

local ok, icon = pcall(function() return select(2, F.GetSpellInfo(17)) end)
local FALLBACK_ICON = (ok and icon) or 134400

local function GetSpellIcon(spellId)
    local ok2, tex = pcall(function() return select(2, F.GetSpellInfo(spellId)) end)
    return (ok2 and tex) or FALLBACK_ICON
end

local function Entry(spellId, display)
    return { spellId = spellId, display = display, icon = GetSpellIcon(spellId) }
end

-- Verified against Wowhead's TBC Classic spell database (wowhead.com/tbc/spell=<id>).
-- Paladins have no entry: Beacon of Light/Sacred Shield are both WotLK+, TBC Paladins only have
-- instant direct heals (Holy Light, Flash of Light) which leave no aura to track here.
local ClassicHealSpells = {
    PRIEST = {
        Entry(17,    "Power Word: Shield"),
        Entry(139,   "Renew"),
        Entry(33076, "Prayer of Mending"),      -- TBC
    },
    DRUID = {
        Entry(774,   "Rejuvenation"),
        Entry(8936,  "Regrowth"),
        Entry(33763, "Lifebloom"),              -- TBC
    },
    SHAMAN = {
        Entry(974,   "Earth Shield"),
    },
}

function F.GetClassicHealSpells(classToken)
    if not (Cell.isVanilla or Cell.isTBC) then return nil end
    if not classToken then return ClassicHealSpells end
    return ClassicHealSpells[classToken] or {}
end

--! lets the Spell Picker's class list show only the classes that actually have entries above,
--! instead of just "Auto" with nothing else selectable (F.AuraBlacklistClassOrder is Retail-only).
local ClassicHealClassOrder = { "PRIEST", "DRUID", "SHAMAN" }

function F.GetClassicHealClassOrder()
    if not (Cell.isVanilla or Cell.isTBC) then return nil end
    return ClassicHealClassOrder
end
