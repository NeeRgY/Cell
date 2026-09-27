local _, Cell = ...
local F = Cell.funcs
local I = Cell.iFuncs

local _IsAuraFilteredOut = C_UnitAuras.IsAuraFilteredOutByInstanceID
local _GetSpecialization = GetSpecialization
local _UnitClassBase = UnitClassBase

local SpecMap = {
    MONK_1    = "MistweaverMonk",
    MONK_2    = "MistweaverMonk",
    MONK_3    = "MistweaverMonk",
    PALADIN_1 = "HolyPaladin",
    PALADIN_2 = "HolyPaladin",
    PALADIN_3 = "HolyPaladin",
    EVOKER_2  = "PreservationEvoker",
    EVOKER_3  = "AugmentationEvoker",
    DRUID_4   = "RestorationDruid",
    PRIEST_1  = "DisciplinePriest",
    PRIEST_2  = "HolyPriest",
}

local SpecAuraSignatures = {
    MistweaverMonk = {
        ["1:1:1:0"] = "LifeCocoon",
        ["0:1:0:1"] = "StrengthOfTheBlackOx",
    },
    HolyPaladin = {
        ["1:1:1:1"] = "BlessingOfProtection",
        ["1:1:1:0"] = "BlessingOfSacrifice",
        ["1:0:0:1"] = "BlessingOfFreedom",
        ["0:1:0:0"] = "HolyArmaments",
    },
    PreservationEvoker = {
        ["1:1:1:0"] = "TimeDilation",
        ["1:1:0:0"] = "Rewind",
    },
    RestorationDruid = {
        ["1:1:1:0"] = "Ironbark",
    },
    DisciplinePriest = {
        ["1:1:1:0"] = "PainSuppression",
        ["1:0:0:1"] = "PowerInfusion",
    },
    HolyPriest = {
        ["1:1:1:0"] = "GuardianSpirit",
        ["1:0:0:1"] = "PowerInfusion",
    },
    AugmentationEvoker = {
        ["0:1:0:0"] = "SensePower",
    },
}

local AuraClassification = {
    LifeCocoon           = "external",
    StrengthOfTheBlackOx = "defensive",
    BlessingOfProtection = "external",
    BlessingOfSacrifice  = "external",
    BlessingOfFreedom    = "external",
    HolyArmaments        = "external",
    TimeDilation         = "external",
    Rewind               = "external",
    Ironbark             = "external",
    PainSuppression      = "external",
    PowerInfusion        = "external",
    SensePower           = "external",
    GuardianSpirit       = "external",
}

local _specKeyCache
local _specSignatures

local function GetSpecSignatures()
    local specIndex = _GetSpecialization()
    if not specIndex then return nil end
    local classToken = _UnitClassBase("player")
    if not classToken then return nil end
    local mapKey = classToken .. "_" .. specIndex
    if mapKey ~= _specKeyCache then
        local specKey = SpecMap[mapKey]
        _specSignatures = SpecAuraSignatures[specKey]
        _specKeyCache = mapKey
    end
    return _specSignatures
end

local FILTER_RAID = "PLAYER|HELPFUL|RAID"
local FILTER_RIC  = "PLAYER|HELPFUL|RAID_IN_COMBAT"
local FILTER_EXT  = "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE"
local FILTER_DISP = "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE"

local function BuildSignature(unit, auraInstanceID)
    if not _IsAuraFilteredOut then return nil end

    local raidResult = _IsAuraFilteredOut(unit, auraInstanceID, FILTER_RAID)
    if type(raidResult) ~= "boolean" then return nil end
    local passesRaid = not raidResult

    local ricResult = _IsAuraFilteredOut(unit, auraInstanceID, FILTER_RIC)
    if type(ricResult) ~= "boolean" then return nil end
    local passesRic = not ricResult

    if not (passesRaid or passesRic) then return nil end

    local extResult = _IsAuraFilteredOut(unit, auraInstanceID, FILTER_EXT)
    if type(extResult) ~= "boolean" then return nil end
    local passesExt = not extResult

    local dispResult = _IsAuraFilteredOut(unit, auraInstanceID, FILTER_DISP)
    if type(dispResult) ~= "boolean" then return nil end
    local passesDisp = not dispResult

    return (passesRaid and "1" or "0") .. ":" ..
           (passesRic  and "1" or "0") .. ":" ..
           (passesExt  and "1" or "0") .. ":" ..
           (passesDisp and "1" or "0")
end

function Cell.IdentifySecretAura(unit, auraInstanceID)
    if F.IsSecretAuraUnitTrustworthy and not F.IsSecretAuraUnitTrustworthy(unit) then
        return
    end

    local sigs = GetSpecSignatures()
    if not sigs then return end

    local sig = BuildSignature(unit, auraInstanceID)
    if not sig then return end

    local auraName = sigs[sig]
    if not auraName then return end

    local kind = AuraClassification[auraName]
    if not kind then return end

    return auraName, kind
end
