---@class Cell
local Cell = select(2, ...)
local L = Cell.L
---@class CellFuncs
local F = Cell.funcs
---@type CellIndicatorFuncs
local I = Cell.iFuncs

Cell.vars.playerFaction = UnitFactionGroup("player")

-------------------------------------------------
-- game version
-------------------------------------------------
Cell.isAsian = LOCALE_zhCN or LOCALE_zhTW or LOCALE_koKR

Cell.isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
Cell.isMidnight = Cell.isRetail and (select(4, GetBuildInfo()) >= 120000)
Cell.isVanilla = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
Cell.isTBC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
Cell.isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
Cell.isCata = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC
Cell.isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
Cell.isTWW = LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_WAR_WITHIN

local CELL_VERSION_FALLBACK = "r277.9.8.4"

function F.InitAddonVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version
    if getMeta then
        version = getMeta("Cell", "Version") or getMeta("Cell", "version")
    end
    if type(version) ~= "string" or version == "" then
        version = CELL_VERSION_FALLBACK
    end
    Cell.version = version
    Cell.versionNum = tonumber(string.match(version, "%d+")) or tonumber(string.match(CELL_VERSION_FALLBACK, "%d+")) or 0
end

function F.GetNickname(shortname, fullname)
    return shortname or fullname
end

-------------------------------------------------
-- compatibility
-------------------------------------------------
if not IsEncounterInProgress and C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress then
    IsEncounterInProgress = C_InstanceEncounter.IsEncounterInProgress
end

if Cell.isRetail then
    Cell.flavor = "retail"
elseif Cell.isMists then
    Cell.flavor = "mists"
elseif Cell.isCata then
    Cell.flavor = "cata"
elseif Cell.isWrath then
    Cell.flavor = "wrath"
elseif Cell.isTBC then
    Cell.flavor = "tbc"
elseif Cell.isVanilla then
    Cell.flavor = "vanilla"
end

-------------------------------------------------
-- class
-------------------------------------------------
local localizedClass
if Cell.isRetail then
    localizedClass = LocalizedClassList()
else
    localizedClass = {}
    FillLocalizedClassList(localizedClass)
end

local sortedClasses = {}
local classFileToID = {}
local classIDToFile = {}

do
    -- WARRIOR = 1,
    -- PALADIN = 2,
    -- HUNTER = 3,
    -- ROGUE = 4,
    -- PRIEST = 5,
    -- DEATHKNIGHT = 6,
    -- SHAMAN = 7,
    -- MAGE = 8,
    -- WARLOCK = 9,
    -- MONK = 10,
    -- DRUID = 11,
    -- DEMONHUNTER = 12,
    -- EVOKER = 13,
    --! GetNumClasses returns the highest class ID (NOT IN CLASSIC)
    local highestClassID = GetNumClasses()
    if highestClassID < 11 then highestClassID = 11 end
    for i = 1, highestClassID do
        local classFile, classID = select(2, GetClassInfo(i))
        if classFile and classID == i then
            tinsert(sortedClasses, classFile)
            classFileToID[classFile] = i
            classIDToFile[i] = classFile
        end
    end
    sort(sortedClasses)
end

function F.GetClassID(classFile)
    return classFileToID[classFile]
end

function F.GetLocalizedClassName(classFileOrID)
    if type(classFileOrID) == "string" then
        return localizedClass[classFileOrID] or classFileOrID
    elseif type(classFileOrID) == "number" and classIDToFile[classFileOrID] then
        return localizedClass[classIDToFile[classFileOrID]] or classFileOrID
    end
    return ""
end

function F.IterateClasses()
    local i = 0
    return function()
        i = i + 1
        if i <= GetNumClasses() then
            return sortedClasses[i], classFileToID[sortedClasses[i]], i
        end
    end
end

function F.GetSortedClasses()
    return F.Copy(sortedClasses)
end

-------------------------------------------------
-- Classic
-------------------------------------------------
if Cell.isCata then
    function F.GetActiveTalentInfo()
        local which = GetActiveTalentGroup() == 1 and L["Primary Talents"] or L["Secondary Talents"]
        return which, Cell.vars.playerSpecIcon, Cell.vars.playerSpecName
    end

elseif Cell.isWrath or Cell.isTBC or Cell.isVanilla then
    function F.GetActiveTalentInfo()
        local which = GetActiveTalentGroup() == 1 and L["Primary Talents"] or L["Secondary Talents"]

        local maxPoints = 0
        local specName, specIcon, specFileName

        for i = 1, GetNumTalentTabs() do
            local id, name, description, icon, pointsSpent, background = GetTalentTabInfo(i)
            if pointsSpent > maxPoints then
                maxPoints = pointsSpent
                specIcon = icon
                specName = name
            -- elseif pointsSpent == maxPoints then
            --     specIcon = 132148
            end
        end

        return which, specIcon or 134400, specName or L["No Spec"]
    end
end

-- local specRoles = {
--     ["DeathKnightBlood"] = "DAMAGER",
--     ["DeathKnightFrost"] = "TANK",
--     ["DeathKnightUnholy"] = "DAMAGER",

--     ["DruidRestoration"] = "HEALER",
--     ["DruidBalance"] = "DAMAGER",
--     -- ["DruidFeralCombat"] = nil,

--     ["HunterBeastMastery"] = "DAMAGER",
--     ["HunterSurvival"] = "DAMAGER",
--     ["HunterMarksmanship"] = "DAMAGER",

--     ["MageFrost"] = "DAMAGER",
--     ["MageArcane"] = "DAMAGER",
--     ["MageFire"] = "DAMAGER",

--     ["PaladinHoly"] = "HEALER",
--     ["PaladinCombat"] = "DAMAGER",
--     ["PaladinProtection"] = "TANK",

--     ["PriestShadow"] = "DAMAGER",
--     ["PriestHoly"] = "HEALER",
--     ["PriestDiscipline"] = "HEALER",

--     ["RogueCombat"] = "DAMAGER",
--     ["RogueSubtlety"] = "DAMAGER",
--     ["RogueAssassination"] = "DAMAGER",

--     ["ShamanElementalCombat"] = "DAMAGER",
--     ["ShamanEnhancement"] = "DAMAGER",
--     ["ShamanRestoration"] = "HEALER",

--     ["WarlockSummoning"] = "DAMAGER",
--     ["WarlockDestruction"] = "DAMAGER",
--     ["WarlockCurses"] = "DAMAGER",

--     ["WarriorArms"] = "DAMAGER",
--     ["WarriorFury"] = "DAMAGER",
--     ["WarriorProtection"] = "TANK",
-- }

-- function F.GetPlayerRole()

-- end

-------------------------------------------------
-- color
-------------------------------------------------
function F.ConvertRGB(r, g, b, desaturation)
    if not desaturation then desaturation = 1 end
    r = r / 255 * desaturation
    g = g / 255 * desaturation
    b = b / 255 * desaturation
    return r, g, b
end

function F.ConvertRGB_256(r, g, b)
    return floor(r * 255), floor(g * 255), floor(b * 255)
end

function F.ConvertRGBToHEX(r, g, b)
    local result = ""

    for key, value in pairs({r, g, b}) do
        local hex = ""

        while(value > 0)do
            local index = math.fmod(value, 16) + 1
            value = math.floor(value / 16)
            hex = string.sub("0123456789ABCDEF", index, index) .. hex
        end

        if(string.len(hex) == 0)then
            hex = "00"

        elseif(string.len(hex) == 1)then
            hex = "0" .. hex
        end

        result = result .. hex
    end

    return result
end

function F.ConvertHEXToRGB(hex)
    hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
end

-- https://wowpedia.fandom.com/wiki/ColorGradient
-- function F.ColorGradient(perc, r1,g1,b1, r2,g2,b2, r3,g3,b3)
--     perc = perc or 1
--     if perc >= 1 then
--         return r3, g3, b3
--     elseif perc <= 0 then
--         return r1, g1, b1
--     end

--     local segment, relperc = math.modf(perc * 2)
--     local rr1, rg1, rb1, rr2, rg2, rb2 = select((segment * 3) + 1, r1,g1,b1, r2,g2,b2, r3,g3,b3)

--     return rr1 + (rr2 - rr1) * relperc, rg1 + (rg2 - rg1) * relperc, rb1 + (rb2 - rb1) * relperc
-- end

function F.ColorGradient(perc, c1, c2, c3, lowBound, highBound)
    local r1, g1, b1 = c1[1], c1[2], c1[3]
    local r2, g2, b2 = c2[1], c2[2], c2[3]
    local r3, g3, b3 = c3[1], c3[2], c3[3]

    lowBound = lowBound or 0
    highBound = highBound or 1
    perc = perc or 1

    if perc >= highBound then
        return r3, g3, b3
    elseif perc <= lowBound then
        return r1, g1, b1
    end

    perc = (perc - lowBound) / (highBound - lowBound)

    local segment, relperc = math.modf(perc * 2)
    local rr1, rg1, rb1, rr2, rg2, rb2 = select((segment * 3) + 1, r1,g1,b1, r2,g2,b2, r3,g3,b3)

    return rr1 + (rr2 - rr1) * relperc, rg1 + (rg2 - rg1) * relperc, rb1 + (rb2 - rb1) * relperc
end

-- ElvUI-style health text coloring: red at 0% health, yellow at 50%, the segment's
-- own base color (r, g, b) once fully healed.
function F.GetHealthTextColor(percent, r, g, b)
    return F.ColorGradient(percent, {1, 0, 0}, {1, 1, 0}, {r, g, b})
end

function F.ColorThreshold(perc, c1, c2, c3, lowBound, highBound, useThresholdColor)
    if useThresholdColor then
        return F.ColorGradient(perc, c1, c2, c3, lowBound, highBound)
    end

    lowBound = lowBound or 0
    highBound = highBound or 1
    perc = perc or 1

    if perc >= highBound then
        return c3[1], c3[2], c3[3]
    elseif perc >= lowBound then
        return c2[1], c2[2], c2[3]
    else
        return c1[1], c1[2], c1[3]
    end
end

--! From ColorPickerAdvanced by Feyawen-Llane
--[[ Convert RGB to HSV ---------------------------------------------------
    Inputs:
        r = Red [0, 1]
        g = Green [0, 1]
        b = Blue [0, 1]
    Outputs:
        H = Hue [0, 360]
        S = Saturation [0, 1]
        B = Brightness [0, 1]
]]--
function F.ConvertRGBToHSB(r, g, b)
    local colorMax = max(max(r, g), b)
    local colorMin = min(min(r, g), b)
    local delta = colorMax - colorMin
    local H, S, B

    -- WoW's LUA doesn't handle floating point numbers very well (Somehow 1.000000 != 1.000000   WTF?)
    -- So we do this weird conversion of, Number to String back to Number, to make the IF..THEN work correctly!
    colorMax = tonumber(format("%f", colorMax))
    r = tonumber(format("%f", r))
    g = tonumber(format("%f", g))
    b = tonumber(format("%f", b))

    if (delta > 0) then
        if (colorMax == r) then
            H = 60 * (((g - b) / delta) % 6)
        elseif (colorMax == g) then
            H = 60 * (((b - r) / delta) + 2)
        elseif (colorMax == b) then
            H = 60 * (((r - g) / delta) + 4)
        end

        if (colorMax > 0) then
            S = delta / colorMax
        else
            S = 0
        end

        B = colorMax
    else
        H = 0
        S = 0
        B = colorMax
    end

    if (H < 0) then
        H = H + 360
    end

    return H, S, B
end

--[[ Convert HSB to RGB ---------------------------------------------------
    Inputs:
        h = Hue [0, 360]
        s = Saturation [0, 1]
        b = Brightness [0, 1]
    Outputs:
        R = Red [0,1]
        G = Green [0,1]
        B = Blue [0,1]
]]--
function F.ConvertHSBToRGB(h, s, b)
    local chroma = b * s
    local prime = (h / 60) % 6
    local X = chroma * (1 - abs((prime % 2) - 1))
    local M = b - chroma
    local R, G, B

    if (0 <= prime) and (prime < 1) then
        R = chroma
        G = X
        B = 0
    elseif (1 <= prime) and (prime < 2) then
        R = X
        G = chroma
        B = 0
    elseif (2 <= prime) and (prime < 3) then
        R = 0
        G = chroma
        B = X
    elseif (3 <= prime) and (prime < 4) then
        R = 0
        G = X
        B = chroma
    elseif (4 <= prime) and (prime < 5) then
        R = X
        G = 0
        B = chroma
    elseif (5 <= prime) and (prime < 6) then
        R = chroma
        G = 0
        B = X
    else
        R = 0
        G = 0
        B = 0
    end

    R = R + M
    G = G + M
    B =  B + M

    return R, G, B
end

function F.InvertColor(r, g, b)
    return 1 - r, 1 - g, 1 - b
end

-------------------------------------------------
-- number
-------------------------------------------------
function F.Round(num, numDecimalPlaces)
    if numDecimalPlaces and numDecimalPlaces >= 0 then
        local mult = 10 ^ numDecimalPlaces
        num = num * mult
        if num >= 0 then
            return floor(num + 0.5) / mult
        else
            return ceil(num - 0.5) / mult
        end
    end

    if num >= 0 then
        return floor(num + 0.5)
    else
        return ceil(num - 0.5)
    end
end

local symbol_1K, symbol_10K, symbol_1B
if LOCALE_zhCN then
    symbol_1K, symbol_10K, symbol_1B = "千", "万", "亿"
elseif LOCALE_zhTW then
    symbol_1K, symbol_10K, symbol_1B = "千", "萬", "億"
elseif LOCALE_koKR then
    symbol_1K, symbol_10K, symbol_1B = "천", "만", "억"
end

local abs = math.abs

if Cell.isAsian then
    function F.FormatNumber(n, decimals)
        if abs(n) >= 100000000 then
            return F.Round(n / 100000000, decimals or 2) .. symbol_1B
        elseif abs(n) >= 10000 then
            return F.Round(n / 10000, decimals or 1) .. symbol_10K
        else
            return n
        end
    end
else
    function F.FormatNumber(n, decimals)
        if abs(n) >= 1000000000 then
            return F.Round(n / 1000000000, decimals or 2) .. "B"
        elseif abs(n) >= 1000000 then
            return F.Round(n / 1000000, decimals or 2) .. "M"
        elseif abs(n) >= 1000 then
            return F.Round(n / 1000, decimals or 1) .. "K"
        else
            return n
        end
    end
end

-------------------------------------------------
-- string
-------------------------------------------------
function F.UpperFirst(str, lowerOthers)
    if lowerOthers then
        str = strlower(str)
    end
    return (str:gsub("^%l", string.upper))
end

function F.SplitToNumber(sep, str)
    if not str then return end

    local ret = {strsplit(sep, str)}
    for i, v in ipairs(ret) do
        ret[i] = tonumber(v) or ret[i] -- keep non number
    end
    return unpack(ret)
end

local function Chsize(char)
    if not char then
        return 0
    elseif char > 240 then
        return 4
    elseif char > 225 then
        return 3
    elseif char > 192 then
        return 2
    else
        return 1
    end
end

function F.Utf8sub(str, startChar, numChars)
    if not str then return "" end
    local startIndex = 1
    while startChar > 1 do
        local char = string.byte(str, startIndex)
        startIndex = startIndex + Chsize(char)
        startChar = startChar - 1
    end

    local currentIndex = startIndex

    while numChars > 0 and currentIndex <= #str do
        local char = string.byte(str, currentIndex)
        currentIndex = currentIndex + Chsize(char)
        numChars = numChars -1
    end
    return str:sub(startIndex, currentIndex - 1)
end

function F.FitWidth(fs, text, alignment)
    fs:SetText(text)

    if fs:IsTruncated() then
        for i = 1, string.utf8len(text) do
            if strlower(alignment) == "right" then
                fs:SetText("..."..string.utf8sub(text, i))
            else
                fs:SetText(string.utf8sub(text, i).."...")
            end

            if not fs:IsTruncated() then
                break
            end
        end
    end
end

-------------------------------------------------
-- table
-------------------------------------------------
function F.Getn(t)
    local count = 0
    for _ in next, t do
        count = count + 1
    end
    return count
end

function F.GetIndex(t, e)
    for i, v in pairs(t) do
        if e == v then
            return i
        end
    end
    return nil
end

function F.GetKeys(t)
    local keys = {}
    for k in pairs(t) do
        tinsert(keys, k)
    end
    return keys
end

function F.Copy(t)
    local newTbl = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            newTbl[k] = F.Copy(v)
        else
            newTbl[k] = v
        end
    end
    return newTbl
end

function F.TContains(t, v)
    if not t then return false end
    if F.IsValueNonSecret and not F.IsValueNonSecret(v) then return false end

    for _, value in pairs(t) do
        if (not F.IsValueNonSecret or F.IsValueNonSecret(value)) and value == v then
            return true
        end
    end
    return false
end

function F.TInsert(t, v)
    local i, done = 1
    repeat
        if not t[i] then
            t[i] = v
            done = true
        end
        i = i + 1
    until done
end

function F.TInsertIfNotExists(t, ...)
    local n = select("#", ...)
    if n == 0 then return end

    if n == 1 then
        local v = ...
        if not F.TContains(t, v) then
            tinsert(t, v)
        end
    else
        local values = F.ConvertTable(t, true)
        for i = 1, n do
            local v = select(i, ...)
            if not values[v] then
                tinsert(t, v)
            end
        end
        values = nil
    end

end

function F.TRemove(t, v)
    for i = #t, 1, -1 do
        if t[i] == v then
            table.remove(t, i)
        end
    end
end

function F.TMergeOverwrite(...)
    local n = select("#", ...)
    if n == 0 then return {} end

    local temp = F.Copy(...)
    for i = 2, n do
        local t = select(i, ...)
        for k, v in pairs(t) do
            temp[k] = v
        end
    end
    return temp
end

function F.RemoveElementsExceptKeys(tbl, ...)
    local keys = {}

    for i = 1, select("#", ...) do
        local k = select(i, ...)
        keys[k] = true
    end

    for k in pairs(tbl) do
        if not keys[k] then
            tbl[k] = nil
        end
    end
end

function F.RemoveElementsByKeys(tbl, ...)
    for i = 1, select("#", ...) do
        local k = select(i, ...)
        tbl[k] = nil
    end
end

function F.Sort(t, k1, order1, k2, order2, k3, order3)
    table.sort(t, function(a, b)
        if a[k1] ~= b[k1] then
            if order1 == "ascending" then
                return a[k1] < b[k1]
            else -- "descending"
                return a[k1] > b[k1]
            end
        elseif k2 and order2 and a[k2] ~= b[k2] then
            if order2 == "ascending" then
                return a[k2] < b[k2]
            else -- "descending"
                return a[k2] > b[k2]
            end
        elseif k3 and order3 and a[k3] ~= b[k3] then
            if order3 == "ascending" then
                return a[k3] < b[k3]
            else -- "descending"
                return a[k3] > b[k3]
            end
        end
    end)
end

function F.StringToTable(s, sep, convertToNum)
    local t = {}
    for i, v in pairs({string.split(sep, s)}) do
        v = strtrim(v)
        if v ~= "" then
            if convertToNum then
                v = tonumber(v)
                if v then tinsert(t, v) end
            else
                tinsert(t, v)
            end
        end
    end
    return t
end

function F.TableToString(t, sep)
    return table.concat(t, sep)
end

function F.ConvertTable(t, value)
    local temp = {}
    for k, v in ipairs(t) do
        temp[v] = value or k
    end
    return temp
end

function F.ConvertSpellTable(t, convertIdToName)
    if not convertIdToName then
        return F.ConvertTable(t)
    end

    local temp = {}
    for k, v in ipairs(t) do
        local name = F.GetSpellInfo(v)
        if name then
            temp[name] = k
        end
    end
    return temp
end

function F.ConvertSpellTable_WithColor(t, convertIdToName)
    local temp = {}
    for k, st in ipairs(t) do
        local index

        if convertIdToName then
            index = F.GetSpellInfo(st[1])
        else
            index = st[1]
        end

        if index then
            temp[index] = {k, st[2]}
        end
    end
    return temp
end

function F.ConvertSpellTable_WithClass(t)
    local temp = {}
    for class, ct in pairs(t) do
        for _, id in ipairs(ct) do
            local name = F.GetSpellInfo(id)
            if name then
                temp[id] = true
            end
        end
    end
    return temp
end

function F.ConvertSpellDurationTable(t, convertIdToName)
    local temp = {}
    for _, v in ipairs(t) do
        local id, duration = strsplit(":", v)
        local name = F.GetSpellInfo(id)
        if name then
            if convertIdToName then
                temp[name] = tonumber(duration)
            else
                temp[tonumber(id)] = tonumber(duration)
            end
        end
    end
    return temp
end

function F.ConvertSpellDurationTable_WithClass(t)
    local temp = {}
    for class, ct in pairs(t) do
        for k, v in ipairs(ct) do
            local id, duration = strsplit(":", v)
            local name, icon = F.GetSpellInfo(id)
            if name then
                temp[tonumber(id)] = {tonumber(duration), icon}
            end
        end
    end
    return temp
end

function F.CheckTableRemoved(previous, after)
    local aa = {}
    local ret = {}

    for k,v in pairs(previous) do aa[v] = true end
    for k,v in pairs(after) do aa[v] = nil end

    for k,v in pairs(previous) do
        if aa[v] then
            tinsert(ret, v)
        end
    end
    return ret
end

function F.FilterInvalidSpells(t)
    if not t then return end
    for i = #t, 1, -1 do
        local spellId
        if type(t[i]) == "number" then
            spellId = t[i]
        else -- table
            spellId = t[i][1]
        end
        if not F.GetSpellInfo(spellId) then
            tremove(t, i)
        end
    end
end

-------------------------------------------------
-- general
-------------------------------------------------
-- function F.GetRealmName()
--     return string.gsub(GetRealmName(), " ", "")
-- end

function F.UnitFullName(unit)
    if not unit or not UnitIsPlayer(unit) then return end

    local name = GetUnitName(unit, true)

    --? name might be nil in some cases?
    if name and not string.find(name, "-") then
        local server = GetNormalizedRealmName()
        --? server might be nil in some cases?
        if server then
            name = name.."-"..server
        end
    end

    return name
end

function F.ToShortName(fullName)
    if not fullName then return "" end
    local shortName = strsplit("-", fullName)
    return shortName
end

function F.FormatTime(s)
    if s >= 3600 then
        return "%dh", ceil(s / 3600)
    elseif s >= 60 then
        return "%dm", ceil(s / 60)
    end
    return "%ds", floor(s)
end

-- function F.SecondsToTime(seconds)
--     local m = seconds / 60
--     local s = seconds % 60
--     return format("%d:%02d", m, s)
-- end

local SEC = _G.SPELL_DURATION_SEC
local MIN = _G.SPELL_DURATION_MIN

local PATTERN_SEC
local PATTERN_MIN
if SEC and (strfind(SEC, "1f") or strfind(SEC, "1F")) then
    PATTERN_SEC = "%.0"
elseif SEC and (strfind(SEC, "2f") or strfind(SEC, "2F")) then
    PATTERN_SEC = "%.00"
end
if MIN and (strfind(MIN, "1f") or strfind(MIN, "1F")) then
    PATTERN_MIN = "%.0"
elseif MIN and (strfind(MIN, "2f") or strfind(MIN, "2F")) then
    PATTERN_MIN = "%.00"
end

function F.SecondsToTime(seconds)
    if not seconds then return "0" end
    if seconds > 60 then
        local text = format(MIN or "%.1f min", seconds / 60)
        return PATTERN_MIN and gsub(text, PATTERN_MIN, "") or text
    else
        local text = format(SEC or "%.1f s", seconds)
        return PATTERN_SEC and gsub(text, PATTERN_SEC, "") or text
    end
end

-------------------------------------------------
-- unit buttons
-------------------------------------------------
local combinedHeader = "CellRaidFrameHeader0"
local separatedHeaders = {"CellRaidFrameHeader1", "CellRaidFrameHeader2", "CellRaidFrameHeader3", "CellRaidFrameHeader4", "CellRaidFrameHeader5", "CellRaidFrameHeader6", "CellRaidFrameHeader7", "CellRaidFrameHeader8"}

-- REVIEW:
-- Cell.clickCastFrames = {}
-- Cell.clickCastFrameQueue = {}

-- function F.RegisterFrame(frame)
--     Cell.clickCastFrames[frame] = true
--     Cell.clickCastFrameQueue[frame] = true  -- put into queue
--     Cell.Fire("UpdateQueuedClickCastings")
-- end

-- function F.UnregisterFrame(frame)
--     Cell.clickCastFrames[frame] = nil       -- ignore
--     Cell.clickCastFrameQueue[frame] = false -- mark for only cleanup
--     Cell.Fire("UpdateQueuedClickCastings")
-- end

function F.IterateAllUnitButtons(func, updateCurrentGroupOnly, updateQuickAssists, skipShared)
    -- solo
    if not updateCurrentGroupOnly or (updateCurrentGroupOnly and Cell.vars.groupType == "solo") then
        for _, b in pairs(Cell.unitButtons.solo) do
            func(b)
        end
    end

    -- party
    if not updateCurrentGroupOnly or (updateCurrentGroupOnly and Cell.vars.groupType == "party") then
        for index, b in pairs(Cell.unitButtons.party) do
            if index ~= "units" then
                func(b)
            end
        end
    end

    -- raid
    if not updateCurrentGroupOnly or (updateCurrentGroupOnly and Cell.vars.groupType == "raid") then
        if not updateCurrentGroupOnly or Cell.vars.currentLayoutTable.main.combineGroups then
            for _, b in ipairs(Cell.unitButtons.raid[combinedHeader]) do
                func(b)
            end
        end

        if not updateCurrentGroupOnly or not Cell.vars.currentLayoutTable.main.combineGroups then
            for _, header in ipairs(separatedHeaders) do
                for _, b in ipairs(Cell.unitButtons.raid[header]) do
                    func(b)
                end
            end
        end

        -- arena pet
        for _, b in pairs(Cell.unitButtons.arena) do
            func(b)
        end
    end

    -- group pet
    if not updateCurrentGroupOnly or (updateCurrentGroupOnly and Cell.vars.groupType == "raid") or (updateCurrentGroupOnly and Cell.vars.groupType == "party") then
        for index, b in pairs(Cell.unitButtons.pet) do
            if index ~= "units" then
                func(b)
            end
        end
    end

    if not skipShared then
        -- npc
        for _, b in ipairs(Cell.unitButtons.npc) do
            func(b)
        end

        -- spotlight
        for _, b in pairs(Cell.unitButtons.spotlight) do
            func(b)
        end
    end

    if Cell.isRetail and updateQuickAssists then
        for i = 1, 40 do
            func(Cell.unitButtons.quickAssist[i])
        end
    end
end

function F.IterateSharedUnitButtons(func)
    -- npc
    for _, b in ipairs(Cell.unitButtons.npc) do
        func(b)
    end

    -- spotlight
    for _, b in pairs(Cell.unitButtons.spotlight) do
        func(b)
    end
end

local function IsTruthyOrSecret(value)
    if value == nil then
        return false
    end
    if not F.IsValueNonSecret(value) then
        return true
    end
    return value == true or value == 1
end

local function IsUnitMatchOrSecret(unit1, unit2)
    return IsTruthyOrSecret(UnitIsUnit(unit1, unit2))
end

function F.GetUnitButtonByUnit(unit, getSpotlights, getQuickAssist)
    if not unit then return end

    local normal, spotlights, quickAssist

    if Cell.vars.groupType == "raid" then
        if Cell.vars.inBattleground == 5 then
            normal = Cell.unitButtons.raid.units[unit] or Cell.unitButtons.npc.units[unit] or Cell.unitButtons.arena[unit]
        else
            normal = Cell.unitButtons.raid.units[unit] or Cell.unitButtons.npc.units[unit] or Cell.unitButtons.pet.units[unit]
        end
    elseif Cell.vars.groupType == "party" then
        normal = Cell.unitButtons.party.units[unit] or Cell.unitButtons.npc.units[unit]
    else -- solo
        normal = Cell.unitButtons.solo[unit] or Cell.unitButtons.npc.units[unit]
    end

    if getSpotlights then
        spotlights = {}
        for _, b in pairs(Cell.unitButtons.spotlight) do
            if b.unit and IsUnitMatchOrSecret(b.unit, unit) then
                tinsert(spotlights, b)
            end
        end
    end

    if getQuickAssist then
        quickAssist = Cell.unitButtons.quickAssist.units[unit]
    end

    return normal, spotlights, quickAssist
end

function F.GetUnitButtonByGUID(guid, getSpotlights, getQuickAssist)
    return F.GetUnitButtonByUnit(Cell.vars.guids[guid], getSpotlights, getQuickAssist)
end

function F.GetUnitButtonByName(name, getSpotlights, getQuickAssist)
    return F.GetUnitButtonByUnit(Cell.vars.names[name], getSpotlights, getQuickAssist)
end

function F.HandleUnitButton(type, unit, func, ...)
    if not unit then return end

    if type == "guid" then
        unit = Cell.vars.guids[unit]
    elseif type == "name" then
        unit = Cell.vars.names[unit]
    end

    if not unit then return end

    local handled, normal

    if Cell.vars.groupType == "raid" then
        if Cell.vars.inBattleground == 5 then
            normal = Cell.unitButtons.raid.units[unit] or Cell.unitButtons.npc.units[unit] or Cell.unitButtons.arena[unit]
        else
            normal = Cell.unitButtons.raid.units[unit] or Cell.unitButtons.npc.units[unit] or Cell.unitButtons.pet.units[unit]
        end
    elseif Cell.vars.groupType == "party" then
        normal = Cell.unitButtons.party.units[unit] or Cell.unitButtons.npc.units[unit]
    else -- solo
        normal = Cell.unitButtons.solo[unit] or Cell.unitButtons.npc.units[unit]
    end

    if normal then
        func(normal, ...)
        handled = true
    end

    for _, b in pairs(Cell.unitButtons.spotlight) do
        if F.BD(b).states.unit then
            local isMatch = UnitIsUnit(F.BD(b).states.unit, unit)
            if not F.IsValueNonSecret(isMatch) or isMatch then
                func(b, ...)
                handled = true
            end
        end
    end

    return handled
end

function F.UpdateTextWidth(fs, text, width, relativeTo)
    if not fs then return end

    if Cell.isMidnight and not F.IsValueNonSecret(text) then
        fs:SetText(text or "")
        return
    end

    if not text or text == "" then
        fs:SetText("")
        return
    end

    if not width or type(width) ~= "table" then
        fs:SetText(text)
        return
    end

    if width[1] == "unlimited" or width == "unlimited" then
        fs:SetText(text)
        return
    end

    if width[1] == "percentage" then
        local percent = width[2] or 0.75
        if not relativeTo then
            fs:SetText(text)
            return
        end
        local barWidth = relativeTo:GetWidth()
        if not F.IsValueNonSecret(barWidth) then
            fs:SetText(text)
            return
        end
        barWidth = barWidth - 2
        local okLen, len = pcall(string.utf8len, text)
        if not okLen or not F.IsValueNonSecret(len) then
            fs:SetText(text)
            return
        end
        for i = len, 0, -1 do
            fs:SetText(string.utf8sub(text, 1, i))
            local fsWidth = fs:GetWidth()
            if not F.IsValueNonSecret(fsWidth) then
                break
            end
            if fsWidth / barWidth <= percent then
                break
            end
        end
    elseif width[1] == "length" then
        if string.len(text) == string.utf8len(text) then
            fs:SetText(string.utf8sub(text, 1, width[2]))
        else
            fs:SetText(string.utf8sub(text, 1, width[3]))
        end
    end
end

function F.GetMarkEscapeSequence(index)
    index = index - 1
    local left, right, top, bottom
    local coordIncrement = 64 / 256
    left = mod(index , 4) * coordIncrement
    right = left + coordIncrement
    top = floor(index / 4) * coordIncrement
    bottom = top + coordIncrement
    return string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcons:0:0:0:0:64:64:%d:%d:%d:%d|t", left*64, right*64, top*64, bottom*64)
end

-- local scriptObjects = {}
-- local frame = CreateFrame("Frame")
-- frame:RegisterEvent("PLAYER_REGEN_DISABLED")
-- frame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- frame:SetScript("OnEvent", function(self, event)
--     if event == "PLAYER_REGEN_ENABLED" then
--         for _, obj in pairs(scriptObjects) do
--             obj:Show()
--         end
--     else
--         for _, obj in pairs(scriptObjects) do
--             obj:Hide()
--         end
--     end
-- end)
-- function F.SetHideInCombat(obj)
--     tinsert(scriptObjects, obj)
-- end

-------------------------------------------------
-- global functions
-------------------------------------------------
local UnitGUID = UnitGUID
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
local UnitPlayerOrPetInParty = UnitPlayerOrPetInParty
local UnitPlayerOrPetInRaid = UnitPlayerOrPetInRaid
local UnitClass = UnitClass
local UnitClassBase = UnitClassBase
local UnitName = UnitName
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitInPartyIsAI = UnitInPartyIsAI or function() end

-------------------------------------------------
-- frame colors
-------------------------------------------------
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local GetPlayerInfoByGUID = GetPlayerInfoByGUID

function F.ResolveUnitClassFile(unit, fallback)
    if unit then
        local classFile = select(2, UnitClass(unit))
        if classFile and F.IsValueNonSecret(classFile) and RAID_CLASS_COLORS[classFile] then
            return classFile
        end
        if UnitClassBase then
            local base = UnitClassBase(unit)
            if base and F.IsValueNonSecret(base) and RAID_CLASS_COLORS[base] then
                return base
            end
        end
        local guid = UnitGUID(unit)
        if guid and F.IsValueNonSecret(guid) then
            if GetPlayerInfoByGUID then
                local ok, _, classFromGuid = pcall(GetPlayerInfoByGUID, guid)
                if ok and classFromGuid and RAID_CLASS_COLORS[classFromGuid] then
                    return classFromGuid
                end
            end
            local LGI = LibStub and LibStub("LibGroupInfo", true)
            if LGI and LGI.GetCachedInfo then
                local info = LGI:GetCachedInfo(guid)
                if info and info.class and F.IsValueNonSecret(info.class) and RAID_CLASS_COLORS[info.class] then
                    return info.class
                end
            end
        end
    end
    if fallback and F.IsValueNonSecret(fallback) and RAID_CLASS_COLORS[fallback] then
        return fallback
    end
    return nil
end

function F.GetClassColor(class)
    if not class or class == "" then
        return 1, 1, 1
    end
    if not F.IsValueNonSecret(class) then
        return 1, 1, 1
    end
    if RAID_CLASS_COLORS[class] then
        if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class] then
            return CUSTOM_CLASS_COLORS[class].r, CUSTOM_CLASS_COLORS[class].g, CUSTOM_CLASS_COLORS[class].b
        else
            return RAID_CLASS_COLORS[class]:GetRGB()
        end
    else
        return 1, 1, 1
    end
end

function F.GetClassColorStr(class)
    if not class or class == "" or not F.IsValueNonSecret(class) then
        return "|cffffffff"
    end
    if RAID_CLASS_COLORS[class] then
        if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class] then
            return "|c"..CUSTOM_CLASS_COLORS[class].colorStr
        else
            return "|c"..RAID_CLASS_COLORS[class].colorStr
        end
    else
        return "|cffffffff"
    end
end

function F.GetUnitClassColor(unit, class, guid)
    class = F.ResolveUnitClassFile(unit, class) or class or select(2, UnitClass(unit))
    guid = guid or UnitGUID(unit)

    if UnitIsPlayer(unit) or IsTruthyOrSecret(UnitInPartyIsAI(unit)) then -- player
        return F.GetClassColor(class)
    elseif F.IsPet(guid, unit) then -- pet
        return 0.5, 0.5, 1
    else -- npc / vehicle
        return 0, 1, 0.2
    end
end


function F.GetPowerColor(unit)
    local r, g, b, t
    local powerType, powerToken, altR, altG, altB = UnitPowerType(unit)
    t = powerType

    local info
    if powerToken and F.IsValueNonSecret(powerToken) then
        info = PowerBarColor[powerToken]
    end
    if F.IsValueNonSecret(powerType) and powerType == 0 then
        info = {r=0, g=0.5, b=1}
    elseif F.IsValueNonSecret(powerType) and powerType == 13 then
        info = {r=0.6, g=0.2, b=1}
    end

    if info then
        r, g, b = info.r, info.g, info.b
    elseif altR and F.IsValueNonSecret(altR) then
        r, g, b = altR, altG, altB
    else
        if F.IsValueNonSecret(powerType) then
            info = PowerBarColor[powerType]
        end
        info = info or PowerBarColor["MANA"]
        r, g, b = info.r, info.g, info.b
    end
    return r, g, b, t
end

function F.GetPowerBarColor(unit, class)
    local r, g, b, lossR, lossG, lossB, t
    r, g, b, t = F.GetPowerColor(unit)

    if not Cell.loaded then
        return r, g, b, r*0.2, g*0.2, b*0.2, t
    end

    if CellDB["appearance"]["powerColor"][1] == "power_color_dark" then
        lossR, lossG, lossB = r, g, b
        r, g, b = r*0.2, g*0.2, b*0.2
    elseif CellDB["appearance"]["powerColor"][1] == "class_color" then
        r, g, b = F.GetClassColor(class)
        lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
    elseif CellDB["appearance"]["powerColor"][1] == "custom" then
        r, g, b = unpack(CellDB["appearance"]["powerColor"][2])
        lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
    else
        lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
    end
    return r, g, b, lossR, lossG, lossB, t
end

function F.GetHealthBarColor(percent, isDeadOrGhost, r, g, b)
    if not Cell.loaded then
        return r, g, b, r*0.2, g*0.2, b*0.2
    end

    local barR, barG, barB, lossR, lossG, lossB
    percent = percent or 1

    -- bar
    if percent == 1 and Cell.vars.useFullColor then
        barR = CellDB["appearance"]["fullColor"][2][1]
        barG = CellDB["appearance"]["fullColor"][2][2]
        barB = CellDB["appearance"]["fullColor"][2][3]
    else
        if CellDB["appearance"]["barColor"][1] == "class_color" then
            barR, barG, barB = r, g, b
        elseif CellDB["appearance"]["barColor"][1] == "class_color_dark" then
            barR, barG, barB = r*0.2, g*0.2, b*0.2
        elseif CellDB["appearance"]["barColor"][1] == "threshold1" then
            local c = CellDB["appearance"]["colorThresholds"]
            barR, barG, barB = F.ColorThreshold(percent, c[1], c[2], c[3], c[4], c[5], c[6])
        elseif CellDB["appearance"]["barColor"][1] == "threshold2" then
            local c = CellDB["appearance"]["colorThresholds"]
            if percent >= c[5] then
                barR, barG, barB = r, g, b -- full: class color
            else
                barR, barG, barB = F.ColorThreshold(percent, c[1], c[2], {r, g, b}, c[4], c[5], c[6])
            end
        elseif CellDB["appearance"]["barColor"][1] == "threshold3" then
            local c = CellDB["appearance"]["colorThresholds"]
            if percent >= c[5] then
                barR, barG, barB = r*0.2, g*0.2, b*0.2 -- full: class color
            else
                barR, barG, barB = F.ColorThreshold(percent, c[1], c[2], {r*0.2, g*0.2, b*0.2}, c[4], c[5], c[6])
            end
        else
            barR = CellDB["appearance"]["barColor"][2][1]
            barG = CellDB["appearance"]["barColor"][2][2]
            barB = CellDB["appearance"]["barColor"][2][3]
        end
    end

    -- loss
    if isDeadOrGhost and Cell.vars.useDeathColor then
        lossR = CellDB["appearance"]["deathColor"][2][1]
        lossG = CellDB["appearance"]["deathColor"][2][2]
        lossB = CellDB["appearance"]["deathColor"][2][3]
    else
        if CellDB["appearance"]["lossColor"][1] == "class_color" then
            lossR, lossG, lossB = r, g, b
        elseif CellDB["appearance"]["lossColor"][1] == "class_color_dark" then
            lossR, lossG, lossB = r*0.2, g*0.2, b*0.2
        elseif CellDB["appearance"]["lossColor"][1] == "threshold1" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            lossR, lossG, lossB = F.ColorThreshold(percent, c[1], c[2], c[3], c[4], c[5], c[6])
        elseif CellDB["appearance"]["lossColor"][1] == "threshold2" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            if isDeadOrGhost or percent <= c[4] then
                lossR, lossG, lossB = r, g, b  -- dead: class color
            else
                lossR, lossG, lossB = F.ColorThreshold(percent, {r, g, b}, c[2], c[3], c[4], c[5], c[6])
            end
        elseif CellDB["appearance"]["lossColor"][1] == "threshold3" then
            local c = CellDB["appearance"]["colorThresholdsLoss"]
            if isDeadOrGhost or percent <= c[4] then
                lossR, lossG, lossB = r*0.2, g*0.2, b*0.2  -- dead: class color
            else
                lossR, lossG, lossB = F.ColorThreshold(percent, {r*0.2, g*0.2, b*0.2}, c[2], c[3], c[4], c[5], c[6])
            end
        else
            lossR = CellDB["appearance"]["lossColor"][2][1]
            lossG = CellDB["appearance"]["lossColor"][2][2]
            lossB = CellDB["appearance"]["lossColor"][2][3]
        end
    end

    return barR, barG, barB, lossR, lossG, lossB
end

-------------------------------------------------
-- units
-------------------------------------------------
function F.GetNumSubgroupMembers(group)
    local n = 0
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if subgroup == group then
            n = n + 1
        end
    end
    return n
end

function F.GetUnitsInSubGroup(group)
    local units = {}
    for i = 1, GetNumGroupMembers() do
        -- name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(raidIndex)
        local name, _, subgroup = GetRaidRosterInfo(i)
        if subgroup == group then
            tinsert(units, "raid"..i)
        end
    end
    return units
end

function F.GetRaidInfoByName(fullName)
    for i = 1, GetNumGroupMembers() do
        -- rank: Returns 2 if the raid member is the leader of the raid, 1 if the raid member is promoted to assistant, and 0 otherwise.
        local name, rank, subgroup = GetRaidRosterInfo(i)
        if name == fullName then
            return i, subgroup, rank
        end
    end
end

function F.GetRaidInfoBySubgroupIndex(group, index)
    local currentIndex = 0
    for i = 1, GetNumGroupMembers() do
        local name, rank, subgroup = GetRaidRosterInfo(i)
        if subgroup == group then
            currentIndex = currentIndex + 1
            if currentIndex == index then
                return i, name, rank -- found
            end
        elseif subgroup > group and currentIndex ~= 0 then
            return -- nil if not found
        end
    end
end

function F.GetPetUnit(playerUnit)
    if Cell.vars.groupType == "party" then
        if playerUnit == "player" then
            return "pet"
        else
            return "partypet"..select(3, strfind(playerUnit, "^party(%d+)$"))
        end
    elseif Cell.vars.groupType == "raid" then
        return "raidpet"..select(3, strfind(playerUnit, "^raid(%d+)$"))
    else
        return "pet"
    end
end

function F.GetPlayerUnit(petUnit)
    if petUnit == "pet" then
        return "player"
    else
        return petUnit:gsub("pet", "")
    end
end

function F.IterateGroupMembers()
    local groupType = IsInRaid() and "raid" or "party"
    local numGroupMembers = GetNumGroupMembers()
    local i

    if groupType == "party" then
        i = 0
        numGroupMembers = numGroupMembers - 1
    else
        i = 1
    end

    return function()
        local ret
        if i == 0 then
            ret = "player"
        elseif i <= numGroupMembers and i > 0 then
            ret = groupType .. i
        end
        i = i + 1
        return ret
    end
end

function F.IterateGroupPets()
    local groupType = IsInRaid() and "raid" or "party"
    local numGroupMembers = GetNumGroupMembers()
    local i = groupType == "party" and 0 or 1

    return function()
        local ret
        if i == 0 and groupType == "party" then
            ret = "pet"
        elseif i <= numGroupMembers and i > 0 then
            ret = groupType .. "pet" .. i
        end
        i = i + 1
        return ret
    end
end

function F.GetGroupType()
    if IsInRaid() then
        return "raid"
    elseif IsInGroup() then
        return "party"
    else
        return "solo"
    end
end

function F.UnitInGroup(unit, ignorePets)
    if ignorePets then
        return IsUnitMatchOrSecret(unit, "player")
            or IsTruthyOrSecret(UnitInParty(unit))
            or IsTruthyOrSecret(UnitInRaid(unit))
            or IsTruthyOrSecret(UnitInPartyIsAI(unit))
    else
        return IsUnitMatchOrSecret(unit, "player")
            or IsUnitMatchOrSecret(unit, "pet")
            or IsTruthyOrSecret(UnitPlayerOrPetInParty(unit))
            or IsTruthyOrSecret(UnitPlayerOrPetInRaid(unit))
            or IsTruthyOrSecret(UnitInPartyIsAI(unit))
    end
end

-- UnitTokenFromGUID
function F.GetTargetUnitID(target)
    if IsUnitMatchOrSecret(target, "player") then
        return "player"
    elseif IsUnitMatchOrSecret(target, "pet") then
        return "pet"
    end

    if not F.UnitInGroup(target) then return end

    if UnitIsPlayer(target) or IsTruthyOrSecret(UnitInPartyIsAI(target)) then
        for unit in F.IterateGroupMembers() do
            if IsUnitMatchOrSecret(target, unit) then
                return unit
            end
        end
    else
        for unit in F.IterateGroupPets() do
            if IsUnitMatchOrSecret(target, unit) then
                return unit
            end
        end
    end
end

function F.GetTargetPetID(target)
    if IsUnitMatchOrSecret(target, "player") then
        return "pet"
    end

    if not F.UnitInGroup(target) then return end

    if UnitIsPlayer(target) or IsTruthyOrSecret(UnitInPartyIsAI(target)) then
        for unit in F.IterateGroupMembers() do
            if IsUnitMatchOrSecret(target, unit) then
                return F.GetPetUnit(unit)
            end
        end
    end
end

-- https://wowpedia.fandom.com/wiki/UnitFlag
local OBJECT_AFFILIATION_MINE = 0x00000001
local OBJECT_AFFILIATION_PARTY = 0x00000002
local OBJECT_AFFILIATION_RAID = 0x00000004

function F.IsFriend(unitFlags)
    if not unitFlags then return false end
    return (bit.band(unitFlags, OBJECT_AFFILIATION_MINE) ~= 0) or (bit.band(unitFlags, OBJECT_AFFILIATION_RAID) ~= 0) or (bit.band(unitFlags, OBJECT_AFFILIATION_PARTY) ~= 0)
end

function F.IsPlayer(guid)
    if guid and F.IsValueNonSecret(guid) then
        return string.find(guid, "^Player")
    end
end

function F.IsPet(guid, unit)
    if unit then
        return strfind(unit, "pet%d*$")
    end
    if guid and F.IsValueNonSecret(guid) then
        return string.find(guid, "^Pet")
    end
end

function F.IsNPC(guid)
    if guid and F.IsValueNonSecret(guid) then
        return string.find(guid, "^Creature")
    end
end

function F.IsVehicle(guid)
    if guid and F.IsValueNonSecret(guid) then
        return string.find(guid, "^Vehicle")
    end
end

function F.GetTargetUnitInfo()
    if IsUnitMatchOrSecret("target", "player") then
        return "player", UnitName("player"), UnitClassBase("player")
    elseif IsUnitMatchOrSecret("target", "pet") then
        return "pet", UnitName("pet")
    end
    if not F.UnitInGroup("target") then return end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if IsUnitMatchOrSecret("target", "raid"..i) then
                return "raid"..i, UnitName("raid"..i), UnitClassBase("raid"..i)
            end
            if IsUnitMatchOrSecret("target", "raidpet"..i) then
                return "raidpet"..i, UnitName("raidpet"..i)
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers()-1 do
            if IsUnitMatchOrSecret("target", "party"..i) then
                return "party"..i, UnitName("party"..i), UnitClassBase("party"..i)
            end
            if IsUnitMatchOrSecret("target", "partypet"..i) then
                return "partypet"..i, UnitName("partypet"..i)
            end
        end
    end
end

function F.HasPermission(isPartyMarkPermission)
    if isPartyMarkPermission and IsInGroup() and not IsInRaid() then return true end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player"))
end

-------------------------------------------------
-- LibSharedMedia
-------------------------------------------------
Cell.vars.texture = "Interface\\AddOns\\Cell\\Media\\statusbar.tga"
Cell.vars.emptyTexture = "Interface\\AddOns\\Cell\\Media\\empty.tga"
Cell.vars.whiteTexture = "Interface\\AddOns\\Cell\\Media\\white.tga"

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM then
    LSM:Register("statusbar", "Cell ".._G.DEFAULT, Cell.vars.texture)
    LSM:Register("font", "Visitor", [[Interface\Addons\Cell\Media\Fonts\visitor.ttf]], 255)
end

function F.GetBarTexture()
    --! update Cell.vars.texture for further use in UnitButton_OnLoad
    if LSM and LSM:IsValid("statusbar", CellDB["appearance"]["texture"]) then
        Cell.vars.texture = LSM:Fetch("statusbar", CellDB["appearance"]["texture"])
    else
        Cell.vars.texture = "Interface\\AddOns\\Cell\\Media\\statusbar.tga"
    end
    return Cell.vars.texture
end

function F.GetBarTextureByName(name)
    if LSM and LSM:IsValid("statusbar", name) then
        return LSM:Fetch("statusbar", name)
    end
    return "Interface\\AddOns\\Cell\\Media\\statusbar.tga"
end

local durationRemainProp
local durationCurveCache = {}

local function ColorFromOpt(c, fb, a)
    a = a or 1
    if type(c) ~= "table" then
        return CreateColor(fb[1], fb[2], fb[3], a)
    end
    return CreateColor(c[1] or fb[1], c[2] or fb[2], c[3] or fb[3], a)
end

local durationPercentProp

local function GetRemainProp()
    if durationRemainProp ~= nil then
        return durationRemainProp
    end
    local e = Enum and Enum.DurationTextBindingProperty
    local remain = e and e.RemainingDuration
    if remain == nil then
        remain = 0
    end
    durationRemainProp = remain
    return remain
end

local function GetPercentProp()
    if durationPercentProp ~= nil then
        return durationPercentProp
    end
    local e = Enum and Enum.DurationTextBindingProperty
    local pct = e and e.RemainingPercent
    if pct == nil then
        pct = e and e.RemainingDurationPercent
    end
    if pct == nil then
        pct = e and e.PercentRemaining
    end
    if pct == nil then
        pct = 1
    end
    durationPercentProp = pct
    return pct
end

local function MakePercentColorCurve(sec, pct, c1, c2, c3, scale)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
        return nil
    end
    sec = tonumber(sec) or 0
    pct = tonumber(pct) or 0
    scale = tonumber(scale) or 1
    if pct <= 0 then
        return nil
    end
    local mid = pct * scale
    if mid <= 0 then
        return nil
    end
    local curve = C_CurveUtil.CreateColorCurve()
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if stepType then
        curve:SetType(stepType)
    end
    if sec > 0 then
        local redEnd = mid * 0.2
        if scale == 1 then
            if redEnd < 0.02 then
                redEnd = 0.02
            end
        elseif redEnd < 1 then
            redEnd = 1
        end
        curve:AddPoint(0, ColorFromOpt(c3, { 1, 0, 0 }))
        curve:AddPoint(redEnd, ColorFromOpt(c2, { 1, 1, 0 }))
        curve:AddPoint(mid, ColorFromOpt(c1, { 0, 1, 0 }))
    else
        curve:AddPoint(0, ColorFromOpt(c2, { 1, 1, 0 }))
        curve:AddPoint(mid, ColorFromOpt(c1, { 0, 1, 0 }))
    end
    return curve
end

local function IsPlainNumber(v)
    return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

local function MakeRemainColorCurve(sec, yellowUntil, c1, c2, c3)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
        return nil
    end
    sec = tonumber(sec) or 0
    yellowUntil = tonumber(yellowUntil) or 0
    local key = string.format("%s|%s|%s,%s,%s|%s,%s,%s|%s,%s,%s",
        tostring(sec), tostring(yellowUntil),
        tostring(c1 and c1[1]), tostring(c1 and c1[2]), tostring(c1 and c1[3]),
        tostring(c2 and c2[1]), tostring(c2 and c2[2]), tostring(c2 and c2[3]),
        tostring(c3 and c3[1]), tostring(c3 and c3[2]), tostring(c3 and c3[3]))
    local cached = durationCurveCache[key]
    if cached then
        return cached
    end
    local curve = C_CurveUtil.CreateColorCurve()
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if stepType then
        curve:SetType(stepType)
    end
    if sec > 0 and yellowUntil > sec then
        curve:AddPoint(0, ColorFromOpt(c3, { 1, 0, 0 }))
        curve:AddPoint(sec, ColorFromOpt(c2, { 1, 1, 0 }))
        curve:AddPoint(yellowUntil, ColorFromOpt(c1, { 0, 1, 0 }))
    elseif sec > 0 then
        curve:AddPoint(0, ColorFromOpt(c3, { 1, 0, 0 }))
        curve:AddPoint(sec, ColorFromOpt(c1, { 0, 1, 0 }))
    elseif yellowUntil > 0 then
        curve:AddPoint(0, ColorFromOpt(c2, { 1, 1, 0 }))
        curve:AddPoint(yellowUntil, ColorFromOpt(c1, { 0, 1, 0 }))
    else
        return nil
    end
    durationCurveCache[key] = curve
    return curve
end

local function ResolveAuraUnit(button)
    local p = button
    for _ = 1, 8 do
        if not p then
            break
        end
        if p.states and p.states.unit then
            return p.states.unit
        end
        local bd = F.BD(p)
        if bd.states and bd.states.unit then
            return bd.states.unit
        end
        if p.unit then
            return p.unit
        end
        if p.GetAttribute then
            local ok, unit = pcall(p.GetAttribute, p, "unit")
            if ok and type(unit) == "string" and unit ~= "" then
                return unit
            end
        end
        p = p.GetParent and p:GetParent()
    end
end

local function CollectSpellIds(auras)
    local ids, seen = {}, {}
    if type(auras) ~= "table" then
        return ids
    end
    for k, v in pairs(auras) do
        local n
        local keyId = tonumber(k)
        if type(v) == "table" then
            local first = tonumber(v[1]) or tonumber(v.id) or tonumber(v.spellId)
            if keyId and keyId > 100 and (not first or first < 1000 or first == keyId) then
                n = keyId
            else
                n = first
            end
        else
            n = tonumber(v) or keyId
        end
        if n and n > 0 and not seen[n] then
            seen[n] = true
            ids[#ids + 1] = n
        end
    end
    return ids
end

local function NormalizeDuration(v)
    if not IsPlainNumber(v) or v <= 0 then
        return nil
    end
    if v > 1000 then
        v = v / 1000
    end
    if v > 0 and v < 36000 then
        return v
    end
end

local function ReadCooldownTotal(button)
    local function fromCooldown(cd)
        if not cd then
            return
        end
        if cd.GetCooldownTimes then
            local ok, start, duration = pcall(cd.GetCooldownTimes, cd)
            if ok then
                local total = NormalizeDuration(duration)
                if total then
                    return total
                end
            end
        end
        if cd.GetCooldownDuration then
            local ok, duration = pcall(cd.GetCooldownDuration, cd)
            if ok then
                local total = NormalizeDuration(duration)
                if total then
                    return total
                end
            end
        end
    end
    if button.GetDurationCooldown then
        local ok, cd = pcall(button.GetDurationCooldown, button)
        if ok then
            local total = fromCooldown(cd)
            if total then
                return total
            end
        end
    end
    local kids = { button:GetChildren() }
    for i = 1, #kids do
        local child = kids[i]
        if child and child.GetObjectType then
            local ok, ty = pcall(child.GetObjectType, child)
            if ok and ty == "Cooldown" then
                local total = fromCooldown(child)
                if total then
                    return total
                end
            end
        end
    end
end

local function TryAuraDuration(unit, iid)
    if not (unit and C_UnitAuras and C_UnitAuras.GetAuraDuration) then
        return
    end
    local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit, iid)
    if ok then
        return dur
    end
end

local function ResolveAuraDuration(button, unit, spellIds)
    if button.GetAuraDuration then
        local ok, dur = pcall(button.GetAuraDuration, button)
        if ok and dur then
            return dur
        end
    end
    unit = unit or ResolveAuraUnit(button)
    if button.GetAuraInstanceID then
        local ok, id = pcall(button.GetAuraInstanceID, button)
        if ok then
            local dur = TryAuraDuration(unit, id)
            if dur then
                return dur
            end
        end
    end
    if button.GetAuraInstance then
        local ok, a, b = pcall(button.GetAuraInstance, button)
        if ok then
            local okd, dur = pcall(function()
                return TryAuraDuration(unit, a)
                    or TryAuraDuration(unit, b)
                    or TryAuraDuration(unit, a and a.auraInstanceID)
                    or TryAuraDuration(unit, b and b.auraInstanceID)
            end)
            if okd and dur then
                return dur
            end
        end
    end
    if button.GetAuraData then
        local ok, data = pcall(button.GetAuraData, button)
        if ok and type(data) == "table" then
            local dur = TryAuraDuration(unit or data.unit, data.auraInstanceID)
            if dur then
                return dur
            end
        end
    end
    do
        local ok, dur = pcall(function()
            return TryAuraDuration(unit, button.auraInstanceID) or TryAuraDuration(unit, button.auraInstanceId)
        end)
        if ok and dur then
            return dur
        end
    end
    if unit and spellIds and C_UnitAuras then
        for i = 1, #spellIds do
            local data
            if C_UnitAuras.GetUnitAuraBySpellID then
                local ok, d = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellIds[i])
                if ok then
                    data = d
                end
            end
            if not data and C_UnitAuras.GetPlayerAuraBySpellID and (unit == "player" or (UnitIsUnit and UnitIsUnit(unit, "player"))) then
                local ok, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellIds[i])
                if ok then
                    data = d
                end
            end
            if type(data) == "table" then
                local got = TryAuraDuration(unit, data.auraInstanceID)
                if got then
                    return got
                end
            end
        end
    end
    if unit and spellIds and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local want = {}
        for i = 1, #spellIds do
            want[spellIds[i]] = true
        end
        for i = 1, 80 do
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not data then
                break
            end
            local got
            pcall(function()
                if data.spellId and want[data.spellId] then
                    got = TryAuraDuration(unit, data.auraInstanceID)
                end
            end)
            if got then
                return got
            end
        end
    end
end

local function ReadAuraTotalDuration(dur)
    if not dur then
        return nil
    end
    if dur.GetTotalDuration then
        local ok, total = pcall(dur.GetTotalDuration, dur)
        if ok then
            total = NormalizeDuration(total)
            if total then
                return total
            end
        end
    end
    local remain, pct
    if dur.GetRemainingDuration then
        local ok, v = pcall(dur.GetRemainingDuration, dur)
        if ok and IsPlainNumber(v) then
            remain = v
        end
    end
    if dur.GetRemainingPercent then
        local ok, v = pcall(dur.GetRemainingPercent, dur)
        if ok and IsPlainNumber(v) and v > 0 then
            pct = v > 1 and (v / 100) or v
        end
    end
    if remain and pct and pct > 0 then
        return NormalizeDuration(remain / pct)
    end
end

local function ReadSpellAuraTotal(unit, spellIds)
    if not (unit and spellIds and C_UnitAuras) then
        return
    end
    for i = 1, #spellIds do
        local data
        if C_UnitAuras.GetUnitAuraBySpellID then
            local ok, d = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellIds[i])
            if ok then
                data = d
            end
        end
        if not data and C_UnitAuras.GetPlayerAuraBySpellID and (unit == "player" or (UnitIsUnit and UnitIsUnit(unit, "player"))) then
            local ok, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellIds[i])
            if ok then
                data = d
            end
        end
        if data then
            local total = NormalizeDuration(data.duration)
            if total then
                return total
            end
            if data.auraInstanceID then
                if C_UnitAuras.GetAuraBaseDuration then
                    local ok, base = pcall(C_UnitAuras.GetAuraBaseDuration, unit, data.auraInstanceID)
                    if ok then
                        total = NormalizeDuration(base)
                        if total then
                            return total
                        end
                    end
                end
                if C_UnitAuras.GetAuraDuration then
                    local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit, data.auraInstanceID)
                    if ok then
                        total = ReadAuraTotalDuration(dur)
                        if total then
                            return total
                        end
                    end
                end
            end
        end
    end
end

local function ReadButtonTotalDuration(button, spellIds)
    local unit = ResolveAuraUnit(button)
    local total = ReadAuraTotalDuration(ResolveAuraDuration(button, unit, spellIds))
    if total then
        return total
    end
    total = ReadCooldownTotal(button)
    if total then
        return total
    end
    return ReadSpellAuraTotal(unit, spellIds)
end

local auraDurationFormatter
local auraSecondsDurationFormatter

local function ApplyNumericDurationFormatter(button, formatter)
    if not (button and formatter) then
        return
    end
    if button.GetDurationTextBinding then
        local ok, binding = pcall(button.GetDurationTextBinding, button)
        if ok and binding and binding.SetFormatter then
            pcall(binding.SetFormatter, binding, formatter)
            return
        end
    end
    if button.SetDurationText and button._cellDurationFS then
        pcall(button.SetDurationText, button, button._cellDurationFS, { textFormatter = formatter })
    end
end

function F.GetAuraDurationFormatter()
    if auraDurationFormatter then
        return auraDurationFormatter
    end
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum and Enum.NumericRuleFormatRounding then
        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        local up = Enum.NumericRuleFormatRounding.Up
        local down = Enum.NumericRuleFormatRounding.Down
        local ok = pcall(formatter.SetBreakpoints, formatter, {
            { threshold = 0,     format = "%d",  step = 1, rounding = up },
            { threshold = 60,    format = "%dm", step = 1, rounding = down, components = { { div = 60 } } },
            { threshold = 3600,  format = "%dh", step = 1, rounding = down, components = { { div = 3600 } } },
            { threshold = 86400, format = "%dd", step = 1, rounding = down, components = { { div = 86400 } } },
        })
        if ok then
            auraDurationFormatter = formatter
            return auraDurationFormatter
        end
    end
end

local function GetAuraSecondsDurationFormatter()
    if auraSecondsDurationFormatter then
        return auraSecondsDurationFormatter
    end
    if not (C_StringUtil and C_StringUtil.CreateSecondsFormatter) then
        return nil
    end
    local formatter = C_StringUtil.CreateSecondsFormatter()
    local abbr = Enum and Enum.SecondsFormatterAbbreviation
    local interval = Enum and Enum.SecondsFormatterInterval
    local rounding = Enum and Enum.SecondsFormatterRounding
    local whitespace = Enum and Enum.SecondsFormatterIntervalWhitespace
    if abbr then
        pcall(formatter.SetDefaultAbbreviation, formatter, abbr.Truncate)
    end
    if whitespace and whitespace.Strip then
        pcall(formatter.SetStripIntervalWhitespace, formatter, whitespace.Strip)
    end
    if rounding and rounding.Truncate then
        pcall(formatter.SetRounding, formatter, rounding.Truncate)
    end
    pcall(formatter.SetDesiredUnitCount, formatter, 1)
    pcall(formatter.SetCanRoundUpLastUnit, formatter, true)
    if interval and interval.Seconds then
        pcall(formatter.SetMinInterval, formatter, interval.Seconds)
        if C_CurveUtil and C_CurveUtil.CreateCurve and interval.Minutes then
            local curve = C_CurveUtil.CreateCurve()
            local stepType = Enum.LuaCurveType and Enum.LuaCurveType.Step
            if stepType then
                curve:SetType(stepType)
            end
            curve:AddPoint(0, interval.Seconds)
            curve:AddPoint(60, interval.Minutes)
            if interval.Hours then
                curve:AddPoint(3600, interval.Hours)
            end
            if interval.Days then
                curve:AddPoint(86400, interval.Days)
            end
            pcall(formatter.SetMaxIntervalCurve, formatter, curve)
        end
    end
    auraSecondsDurationFormatter = formatter
    return auraSecondsDurationFormatter
end

local function TrySetDurationText(button, fontString, formatter, curve, prop)
    formatter = F.GetAuraDurationFormatter() or formatter
    local secondsFormatter = GetAuraSecondsDurationFormatter()
    local opts = {}
    opts.textFormatter = formatter or secondsFormatter
    if curve then
        opts.textColor = { curve = curve, property = prop }
        if pcall(button.SetDurationText, button, fontString, opts) then
            ApplyNumericDurationFormatter(button, formatter)
            return true, true
        end
        opts.textColor = nil
    end
    if opts.textFormatter and pcall(button.SetDurationText, button, fontString, opts) then
        ApplyNumericDurationFormatter(button, formatter)
        return true, false
    end
    if formatter and formatter ~= opts.textFormatter then
        opts.textFormatter = formatter
        if pcall(button.SetDurationText, button, fontString, opts) then
            ApplyNumericDurationFormatter(button, formatter)
            return true, false
        end
    end
    return false, false
end

local function BindColorCurve(button, fontString, formatter, curve, prop)
    if not curve then
        return false
    end
    local _, colorLanded = TrySetDurationText(button, fontString, formatter, curve, prop)
    return colorLanded
end

function F.BindAuraDurationText(button, fontString, formatter, auras, colorsOverride)
    if not (button and fontString and button.SetDurationText) then
        return
    end

    local driver = fontString._cellDurColorDriver
    if driver then
        driver:SetScript("OnUpdate", nil)
        driver:Hide()
        fontString._cellDurColorDriver = nil
    end

    local colors = colorsOverride or Cell.vars.iconDurationColors
    if not colors then
        TrySetDurationText(button, fontString, formatter, nil, nil)
        return
    end

    local sec = (colors[3] and tonumber(colors[3][4])) or 0
    local pct = (colors[2] and tonumber(colors[2][4])) or 0
    local c1, c2, c3 = colors[1], colors[2], colors[3]
    local total = ReadButtonTotalDuration(button, CollectSpellIds(auras))

    local yellowUntil = 0
    if pct > 0 then
        if BindColorCurve(button, fontString, formatter, MakePercentColorCurve(sec, pct, c1, c2, c3, 100), GetPercentProp()) then
            return
        end
        if total then
            yellowUntil = pct * total
            if sec > 0 and yellowUntil <= sec then
                yellowUntil = sec + 0.1
            end
        end
    end
    BindColorCurve(button, fontString, formatter, MakeRemainColorCurve(sec, yellowUntil, c1, c2, c3), GetRemainProp())
end

local function PackAuraBarDurationColors(colors)
    if Cell.vars.iconDurationColors then
        return Cell.vars.iconDurationColors
    end
    if type(colors) ~= "table" or type(colors[1]) ~= "table" then
        return nil
    end
    local pctOn = colors[2] and colors[2][1]
    local secOn = colors[3] and colors[3][1]
    if not pctOn and not secOn then
        return nil
    end
    local c1 = colors[1]
    local pct = (pctOn and tonumber(colors[2][2])) or 0
    local sec = (secOn and tonumber(colors[3][2])) or 0
    local c2 = (pctOn and type(colors[2][3]) == "table" and colors[2][3]) or c1
    local c3 = (secOn and type(colors[3][3]) == "table" and colors[3][3]) or c2
    return {
        { c1[1] or 0, c1[2] or 1, c1[3] or 0, c1[4] or 1 },
        { c2[1] or 1, c2[2] or 1, c2[3] or 0, pct },
        { c3[1] or 1, c3[2] or 0, c3[3] or 0, sec },
    }
end

local function MakeRemainPercentCurve(pct, cLow, cHigh)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
        return nil
    end
    pct = tonumber(pct) or 0
    if pct <= 0 then
        return nil
    end
    local curve = C_CurveUtil.CreateColorCurve()
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if stepType then
        curve:SetType(stepType)
    end
    curve:AddPoint(0, ColorFromOpt(cLow, { 1, 1, 0 }))
    curve:AddPoint(pct, ColorFromOpt(cHigh, { 0, 1, 0 }))
    curve:AddPoint(1, ColorFromOpt(cHigh, { 0, 1, 0 }))
    return curve
end

local function EnsureBarColorOverlay(bar, c1)
    return bar and bar._cellDurationColorTex
end

local function ApplyDurationBarBinding(button, bar, curve)
    if not (button and bar and button.SetDurationBar and curve) then
        return
    end
    local bind = { curve = curve, property = GetRemainProp() }
    local function BaseOpts()
        local opts = {}
        local dirEnum = Enum and Enum.StatusBarTimerDirection
        if dirEnum and dirEnum.ElapsedTime then
            opts.direction = dirEnum.ElapsedTime
        end
        if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate then
            opts.interpolation = Enum.StatusBarInterpolation.Immediate
        end
        return opts
    end
    local extras = { "color", "fillColor", "barColor", "statusBarColor", "textColor" }
    for i = 1, #extras do
        local opts = BaseOpts()
        opts[extras[i]] = bind
        if pcall(button.SetDurationBar, button, bar, opts) then
            return
        end
    end
    pcall(button.SetDurationBar, button, bar, BaseOpts())
end

local function ReadBarTotalDuration(bar)
    if not bar then
        return
    end
    local ok, _, maxV = pcall(bar.GetMinMaxValues, bar)
    if ok and IsPlainNumber(maxV) and maxV > 1.5 then
        return NormalizeDuration(maxV)
    end
end

local function ApplyBarDurationColor(bar, color)
    if not (bar and color and color.GetRGB) then
        return
    end
    pcall(function()
        local r, g, b, a
        if color.GetRGBA then
            r, g, b, a = color:GetRGBA()
        else
            r, g, b = color:GetRGB()
            a = 1
        end
        bar:SetStatusBarColor(r, g, b, a or 1)
        local tex = bar:GetStatusBarTexture()
        if tex then
            tex:SetVertexColor(r, g, b, a or 1)
        end
    end)
end

local function TickAuraDurationColor(state)
    local button = state.button
    if not button then
        return
    end
    local now = GetTime()
    if state.lastTick and now - state.lastTick < 0.05 then
        return
    end
    state.lastTick = now
    local colors = Cell.vars.iconDurationColors or state.colors
    if not colors then
        return
    end
    local bar = state.bar
    local curve = button._cellDurationColorCurve
    local dur = ResolveAuraDuration(button, ResolveAuraUnit(button), state.spellIds)
    local sec = (colors[3] and tonumber(colors[3][4])) or 0
    local pct = (colors[2] and tonumber(colors[2][4])) or 0
    if dur and not state.boundRemainThree and pct > 0 and sec > 0 and state.fs and button.SetDurationText then
        local total = ReadAuraTotalDuration(dur) or ReadButtonTotalDuration(button, state.spellIds)
        if total and total >= 6 and total > sec * 2 then
            local yellowUntil = pct * total
            if yellowUntil > sec + 1 then
                local remainCurve = MakeRemainColorCurve(sec, yellowUntil, colors[1], colors[2], colors[3])
                if remainCurve and BindColorCurve(button, state.fs, state.formatter, remainCurve, GetRemainProp()) then
                    state.boundRemainThree = true
                    button._cellDurationColorCurve = remainCurve
                    button._cellDurationColorIsPercent = false
                    curve = remainCurve
                end
            end
        end
    end
    if not bar then
        return
    end
    local color
    if dur and curve then
        if button._cellDurationColorIsPercent and dur.EvaluateRemainingPercent then
            local ok, c = pcall(dur.EvaluateRemainingPercent, dur, curve)
            if ok then
                color = c
            end
        elseif dur.EvaluateRemainingDuration then
            local ok, c = pcall(dur.EvaluateRemainingDuration, dur, curve)
            if ok then
                color = c
            end
        end
    end
    if not color and curve and C_UnitAuras and C_UnitAuras.GetAuraDurationRemainingPercent then
        local unit = ResolveAuraUnit(button)
        local iid
        if button.GetAuraInstanceID then
            local ok, id = pcall(button.GetAuraInstanceID, button)
            if ok then
                iid = id
            end
        end
        if not iid and button.GetAuraInstance then
            pcall(function()
                local _, data = button:GetAuraInstance()
                iid = data and data.auraInstanceID
            end)
        end
        if unit and iid then
            local ok, c = pcall(C_UnitAuras.GetAuraDurationRemainingPercent, unit, iid, curve)
            if ok then
                color = c
            end
        end
    end
    if color then
        ApplyBarDurationColor(bar, color)
    end
end

function F.AttachAuraDurationColorDriver(button, auras, colors, bar, fontString, formatter)
    if not button then
        return
    end
    local packed = colors
    if colors and colors[2] and type(colors[2][1]) == "boolean" then
        packed = PackAuraBarDurationColors(colors)
    end
    packed = packed or Cell.vars.iconDurationColors
    if not packed then
        return
    end

    local state = button._cellDurColorState
    if not state then
        state = { button = button }
        button._cellDurColorState = state
    end
    state.auras = auras or state.auras
    state.colors = packed
    state.spellIds = CollectSpellIds(state.auras)
    if formatter then
        state.formatter = formatter
    end
    if bar then
        state.bar = bar
    end
    if fontString then
        state.fs = fontString
    elseif button._cellDurationFS then
        state.fs = button._cellDurationFS
    end

    if not button._cellDurColorDriver then
        local driver = CreateFrame("Frame", nil, button)
        driver:SetSize(1, 1)
        button._cellDurColorDriver = driver
        local elapsed = 0
        driver:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < 0.1 then
                return
            end
            elapsed = 0
            local st = button._cellDurColorState
            if st then
                TickAuraDurationColor(st)
            end
        end)
    end
    if bar and not bar._cellBarColorHooked then
        bar._cellBarColorHooked = true
        bar:HookScript("OnUpdate", function()
            local st = button._cellDurColorState
            if st then
                TickAuraDurationColor(st)
            end
        end)
    end
end

function F.BindAuraBarDurationColor(button, bar, formatter, colors, auras)
end

-- Helper: choose font based on locale and "Use Game Font" setting (shared with Widgets.lua)
-- NOTE: Accidental_Presidency.ttf has incomplete Latin glyph coverage and causes []
-- boxes for many names. Always use GameFontNormal which supports all scripts.
local function GetOptionsFontInternal(useGameFont)
    return GameFontNormal:GetFont()
end

function F.GetFont(font)
    if font and LSM and LSM:IsValid("font", font) then
        return LSM:Fetch("font", font)
    end
    -- Accidental_Presidency.ttf has incomplete Latin glyph coverage — redirect
    -- all non-LSM fonts through locale-aware helper (currently always returns game font).
    return GetOptionsFontInternal(CellDB["appearance"]["useGameFont"])
end

local defaultFontName = "Cell ".._G.DEFAULT
local defaultFont
function F.GetFontItems()
    defaultFont = GetOptionsFontInternal(CellDB["appearance"]["useGameFont"])

    local items = {}
    local fonts, fontNames

    if LSM then
        fonts, fontNames = F.Copy(LSM:HashTable("font")), F.Copy(LSM:List("font"))
        -- insert default font
        tinsert(fontNames, 1, defaultFontName)
        fonts[defaultFontName] = defaultFont

        for _, name in pairs(fontNames) do
            tinsert(items, {
                ["text"] = name,
                ["font"] = fonts[name],
            })
        end
    else
        fonts = {[defaultFontName] = defaultFont}
        tinsert(items, {
            ["text"] = defaultFontName,
            ["font"] = defaultFont,
        })
    end
    return items, fonts, defaultFontName, defaultFont
end

-------------------------------------------------
-- texture
-------------------------------------------------
function F.GetTexCoord(width, height)
    -- ULx,ULy, LLx,LLy, URx,URy, LRx,LRy
    local texCoord = {0.12, 0.12, 0.12, 0.88, 0.88, 0.12, 0.88, 0.88}
    if not width or not height then return texCoord end
    if F.IsValueNonSecret and (not F.IsValueNonSecret(width) or not F.IsValueNonSecret(height)) then
        return texCoord
    end
    if width <= 0 or height <= 0 then return texCoord end

    local aspectRatio = width / height
    if aspectRatio ~= aspectRatio or aspectRatio == math.huge or aspectRatio == -math.huge then
        return texCoord
    end

    local xRatio = aspectRatio < 1 and aspectRatio or 1
    local yRatio = aspectRatio > 1 and 1 / aspectRatio or 1

    for i, coord in ipairs(texCoord) do
        local aspectRatio = (i % 2 == 1) and xRatio or yRatio
        texCoord[i] = (coord - 0.5) * aspectRatio + 0.5
    end

    return texCoord
end

-- function F.RotateTexture(tex, degrees)
--     local angle = math.rad(degrees)
--     local cos, sin = math.cos(angle), math.sin(angle)
--     tex:SetTexCoord((sin - cos), -(cos + sin), -cos, -sin, sin, -cos, 0, 0)
-- end

-- https://wowpedia.fandom.com/wiki/Applying_affine_transformations_using_SetTexCoord
local s2 = sqrt(2)
local function CalculateCorner(degrees)
    local r = math.rad(degrees)
    return 0.5 + math.cos(r) / s2, 0.5 + math.sin(r) / s2
end
function F.RotateTexture(texture, degrees)
    local LRx, LRy = CalculateCorner(degrees + 45)
    local LLx, LLy = CalculateCorner(degrees + 135)
    local ULx, ULy = CalculateCorner(degrees + 225)
    local URx, URy = CalculateCorner(degrees - 45)

    texture:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
end

-- wow atlases
local wowAtlases = {
    "playerpartyblip",
    "Artifacts-PerkRing-WhiteGlow",
    "AftLevelup-WhiteIconGlow",
    "LootBanner-IconGlow",
    "AftLevelup-WhiteStarBurst",
    "ChallengeMode-WhiteSpikeyGlow",
    "UI-QuestPoiCampaign-OuterGlow",
    "vignettekill",
    "PetJournal-FavoritesIcon",
    "dungeonskull",
    "questnormal",
    "questturnin",
    "bags-icon-addslots",
    "communities-chat-icon-plus",
    "communities-chat-icon-minus",
}

-- wow textures
local wowTextures = {

}

-- shapes
local shapes = {
    "circle_blurred",
    "circle_filled",
    "circle_thin",
    "circle",
    "heart_filled",
    "heart",
    "rhombus",
    "rhombus_filled",
    "square_filled",
    "square",
    "star_filled",
    "star",
    "starburst_filled",
    "starburst",
    "triangle_filled",
    "triangle",
}

-- weakauras
local powaTextures = {
    9, 10, 12, 13, 14, 15, 21, 22, 25, 27, 29,
    37, 38, 39, 40, 41, 42, 43, 44,
    49, 51, 52, 53, 58, 78, 118, 84,
    96, 97, 98, 99, 100, 114, 115, 116, 132, 138, 143
}

function F.GetTextures()
    local builtIns = #wowAtlases + #wowTextures + #shapes

    local t = {}

    -- wow atlases
    for _, wa in pairs(wowAtlases) do
        tinsert(t, wa)
    end

    -- wow textures
    for _, wt in pairs(wowTextures) do
        tinsert(t, wt)
    end

    -- built-ins
    for _, s in pairs(shapes) do
        tinsert(t, "Interface\\AddOns\\Cell\\Media\\Shapes\\"..s..".tga")
    end

    -- add weakauras textures
    if WeakAuras then
        builtIns = builtIns + #powaTextures
        for _, powa in pairs(powaTextures) do
            tinsert(t, "Interface\\AddOns\\WeakAuras\\PowerAurasMedia\\Auras\\Aura"..powa..".tga")
        end
    end

    -- customs
    for _, path in pairs(CellDB["customTextures"]) do
        tinsert(t, path)
    end

    return builtIns, t
end

function F.GetDefaultRoleIcon(role)
    if not role or not F.IsValueNonSecret(role) or role == "NONE" then return "" end
    return "Interface\\AddOns\\Cell\\Media\\Roles\\Default_" .. role
end

function F.GetDefaultRoleIconEscapeSequence(role, size)
    if not role or not F.IsValueNonSecret(role) or role == "NONE" then return "" end
    return "|TInterface\\AddOns\\Cell\\Media\\Roles\\Default_" .. role .. ":" .. (size or 0) .. "|t"
end

-------------------------------------------------
-- frame
-------------------------------------------------
function F.GetMouseFocus()
    if GetMouseFoci then
        return GetMouseFoci()[1]
    else
        return GetMouseFocus()
    end
end

-------------------------------------------------
-- instance
-------------------------------------------------
function F.GetInstanceName()
    if IsInInstance() then
        local name = GetInstanceInfo()
        if not name then name = GetRealZoneText() end
        return name
    else
        local mapID = C_Map.GetBestMapForUnit("player")
        if type(mapID) ~= "number" or mapID < 1 then
            return ""
        end

        local info = MapUtil.GetMapParentInfo(mapID, Enum.UIMapType.Continent, true)
        if info then
            return info.name, info.mapID
        end

        return ""
    end
end

-------------------------------------------------
-- spell
-------------------------------------------------
-- https://wow.gamepedia.com/UIOBJECT_GameTooltip
-- local function EnumerateTooltipLines_helper(...)
--     for i = 1, select("#", ...) do
--        local region = select(i, ...)
--        if region and region:GetObjectType() == "FontString" then
--           local text = region:GetText() -- string or nil
--           print(region:GetName(), text)
--        end
--     end
-- end

-- https://wowpedia.fandom.com/wiki/Patch_10.0.2/API_changes
local lines = {}
function F.GetSpellTooltipInfo(spellId)
    wipe(lines)

    local name, icon = F.GetSpellInfo(spellId)
    if not name then return end

    local data = C_TooltipInfo.GetSpellByID(spellId)
    for i, line in ipairs(data.lines) do
        TooltipUtil.SurfaceArgs(line)
        -- line.leftText
        -- line.rightText
    end

    return name, icon, table.concat(lines, "\n")
end

if Cell.isRetail or Cell.isMists then
    local GetSpellInfo = C_Spell.GetSpellInfo
    local GetSpellTexture = C_Spell.GetSpellTexture
    function F.GetSpellInfo(spellId)
        if not spellId then return end
        local info = GetSpellInfo(spellId)
        if not info then return end

        if not info.iconID then -- when?
            info.iconID = GetSpellTexture(spellId)
        end

        return info.name, info.iconID
    end
else
    local GetSpellInfo = GetSpellInfo
    function F.GetSpellInfo(spellId)
        if not spellId then return end
        local rank
        spellId, rank = strsplit(":", spellId)
        local name, _, icon = GetSpellInfo(spellId)
        return name, icon, tonumber(rank)
    end
end

if Cell.isWrath or Cell.isTBC or Cell.isVanilla then
    local GetSpellInfo = GetSpellInfo
    local GetNumSpellTabs = GetNumSpellTabs
    local GetSpellTabInfo = GetSpellTabInfo
    local GetSpellBookItemName = GetSpellBookItemName

    local MATCH_PATTERN, FORMAT_PATTERN = "Rank (%d+)", "Rank %d"
    if LOCALE_deDE or LOCALE_frFR then
        MATCH_PATTERN = "Rang (%d+)"
        FORMAT_PATTERN = "Rang %d"
    elseif LOCALE_esES or LOCALE_esMX then
        MATCH_PATTERN = "Rango (%d+)"
        FORMAT_PATTERN = "Rango %d"
    -- elseif LOCALE_itIT then -- not supported in classic
    --     MATCH_PATTERN = "Grado (%d+)"
    --     FORMAT_PATTERN = "Grado %d"
    elseif LOCALE_koKR then
        MATCH_PATTERN = "(%d+) 레벨"
        FORMAT_PATTERN = "%d 레벨"
    elseif LOCALE_ptBR then
        MATCH_PATTERN = "Grau (%d+)"
        FORMAT_PATTERN = "Grau %d"
    elseif LOCALE_ruRU then
        MATCH_PATTERN = "Уровень (%d+)"
        FORMAT_PATTERN = "Уровень %d"
    elseif LOCALE_zhCN then
        MATCH_PATTERN = "等级 (%d+)"
        FORMAT_PATTERN = "等级 %d"
    elseif LOCALE_zhTW then
        MATCH_PATTERN = "等級 (%d+)"
        FORMAT_PATTERN = "等級 %d"
    end

    FORMAT_PATTERN = "(" .. FORMAT_PATTERN .. ")"

    function F.GetRankSuffix(rank)
        return FORMAT_PATTERN:format(rank)
    end

    function F.GetMaxSpellRank(spellId)
        local spellName = select(1, GetSpellInfo(spellId))
        if not spellName then return end

        local maxRank = 0
        local bookType = BOOKTYPE_SPELL

        local totalSpells = 0
        for tab = 1, GetNumSpellTabs() do
            local name, texture, offset, numSpells = GetSpellTabInfo(tab)
            totalSpells = totalSpells + numSpells
        end

        -- local spellSubText
        for i = 1, totalSpells do
            local name, subText = GetSpellBookItemName(i, bookType)
            if name == spellName and subText then
                local rank = tonumber(subText:match(MATCH_PATTERN))
                -- spellSubText = subText
                if rank and rank > maxRank then
                    maxRank = rank
                end
            end
        end

        -- if spellSubText then
        --     print("----------------------------------------------")
        --     print(spellSubText, MATCH_PATTERN, tonumber(spellSubText:match(MATCH_PATTERN)))
        --     print("Max Rank of " .. spellName .. ": " .. maxRank)
        --     print("----------------------------------------------")
        -- else
        --     print("Rank info not found: " .. spellName)
        -- end

        return maxRank
    end
end

if C_Spell.GetSpellCooldown then
    local GetSpellCooldown = C_Spell.GetSpellCooldown
    F.GetSpellCooldown = function(spellId)
        local info = GetSpellCooldown(spellId)
        if info then
            return info.startTime, info.duration
        end
    end
else
    F.GetSpellCooldown = function(spellId)
        local start, duration = GetSpellCooldown(spellId)
        return start, duration
    end
end

function F.IsSpellReady(spellId)
    local start, duration = F.GetSpellCooldown(spellId)
    if start == 0 or duration == 0 then
        return true
    else
        local _, gcd = F.GetSpellCooldown(61304) --! check gcd
        if duration == gcd then -- spell ready
            return true
        else
            local cdLeft = 0
            if F.IsValueNonSecret(start) and F.IsValueNonSecret(duration) then
                cdLeft = start + duration - GetTime()
            end
            return false, cdLeft
        end
    end
end

-------------------------------------------------
-- macro
-------------------------------------------------
local mc = CreateFrame("Frame")
mc:RegisterEvent("UPDATE_MACROS")

local macroIndices = {}
mc:SetScript("OnEvent", function()
    wipe(macroIndices)

    local global, perChar = GetNumMacros()
    for i = 1, global do
        tinsert(macroIndices, i)
    end
    for i = 1, perChar do
        tinsert(macroIndices, 120 + i)
    end
end)

function F.GetMacroIndices()
    return macroIndices
end

-------------------------------------------------
-- auras
-------------------------------------------------
-- name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod = UnitAura
-- NOTE: FrameXML/AuraUtil.lua
-- AuraUtil.FindAura(predicate, unit, filter, predicateArg1, predicateArg2, predicateArg3)
-- predicate(predicateArg1, predicateArg2, predicateArg3, ...)
local function predicate(...)
    local idToFind = ...
    local id = select(13, ...)
    return idToFind == id
end

function F.FindAuraById(unit, type, spellId)
    if Cell.isMidnight and F.IsAuraRestricted() then return nil end
    if type == "BUFF" then
        return AuraUtil.FindAura(predicate, unit, "HELPFUL", spellId)
    else
        return AuraUtil.FindAura(predicate, unit, "HARMFUL", spellId)
    end
end

if Cell.isRetail then
    function F.FindDebuffByIds(unit, spellIds)
        if Cell.isMidnight and F.IsAuraRestricted() then return {} end
        local debuffs = {}
        AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
            if not F.IsValueNonSecret(spellId) then return end
            if spellIds[spellId] then
                debuffs[spellId] = I.CheckDebuffType(debuffType, spellId)
            end
        end)
        return debuffs
    end

    function F.FindAuraByDebuffTypes(unit, types)
        if Cell.isMidnight and F.IsAuraRestricted() then return {} end
        local debuffs = {}
        AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
            if not F.IsValueNonSecret(spellId) or not F.IsValueNonSecret(debuffType) then return end
            if types == "all" or types[debuffType] then
                debuffs[spellId] = I.CheckDebuffType(debuffType, spellId)
            end
        end)
        return debuffs
    end
else
    function F.FindDebuffByIds(unit, spellIds)
        local debuffs = {}
        for i = 1, 40 do
            local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitDebuff(unit, i)
            if not name then
                break
            end

            if spellIds[spellId] then
                debuffs[spellId] = I.CheckDebuffType(debuffType, spellId)
            end
        end
        return debuffs
    end

    function F.FindAuraByDebuffTypes(unit, types)
        local debuffs = {}
        for i = 1, 40 do
            local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitDebuff(unit, i)
            if not name then
                break
            end

            if types == "all" or types[debuffType] then
                debuffs[spellId] = I.CheckDebuffType(s, spellId)
            end
        end
        return debuffs
    end
end

-------------------------------------------------
-- OmniCD
-------------------------------------------------
function F.UpdateOmniCDPosition(frame)
    if OmniCD and OmniCD[1].db and OmniCD[1].db.position.uf == frame then
        C_Timer.After(0.5, function()
            OmniCD[1].Party:UpdatePosition()
        end)
    end
end

-------------------------------------------------
-- LibGetFrame
-------------------------------------------------
local frame_priorities = {}
local inited_priorities = {}
local modified_priorities = {}
local spotlightPriorityEnabled
local quickAssistPriorityEnabled

function F.UpdateFramePriority()
    wipe(frame_priorities)
    wipe(modified_priorities)
    spotlightPriorityEnabled = nil
    quickAssistPriorityEnabled = nil

    for i, t  in pairs(CellDB["general"]["framePriority"]) do
        if t[2] then
            if t[1] == "Main" then
                tinsert(frame_priorities, i, "^CellNormalUnitFrame$")
            elseif t[1] == "Spotlight" then
                tinsert(frame_priorities, i, "^CellSpotlightUnitFrame$")
                spotlightPriorityEnabled = true
            else
                tinsert(frame_priorities, i, "^CellQuickAssistUnitFrame$")
                quickAssistPriorityEnabled = true
            end
        else
            tinsert(frame_priorities, i, "^CellPlaceholder$")
        end
    end

    F.Debug(frame_priorities)
end

function Cell.GetUnitFramesForLGF(unit, frames, priorities)
    frames = frames or {}

    local normal, spotlights, quickAssist = F.GetUnitButtonByUnit(unit, spotlightPriorityEnabled, quickAssistPriorityEnabled)

    if normal then
        frames[F.BD(normal).widgets.highLevelFrame] = "CellNormalUnitFrame"
    end

    if spotlights then
        -- for _, spotlight in pairs(spotlights) do
        --     if not strfind(spotlight.unit, "target$") and F.BD(spotlight).widgets and F.BD(spotlight).widgets.highLevelFrame then
        --         frames[F.BD(spotlight).widgets.highLevelFrame] = "CellSpotlightUnitFrame"
        --         break
        --     end
        -- end
        --! just use the first (can be "XXtarget", whatever)
        if spotlights[1] then
            frames[F.BD(spotlights[1]).widgets.highLevelFrame] = "CellSpotlightUnitFrame"
        end
    end

    if quickAssist then
        frames[quickAssist] = "CellQuickAssistUnitFrame"
    end

    if not inited_priorities[priorities] then
        inited_priorities[priorities] = true
        for i = 1, 3 do
            tinsert(priorities, i, "^CellPlaceholder$")
        end
    end

    if not modified_priorities[priorities] then
        modified_priorities[priorities] = true
        for i, p in ipairs(frame_priorities) do
            priorities[i] = p
        end
    end

    return frames
end

-------------------------------------------------
-- range check
-------------------------------------------------
local UnitIsVisible = UnitIsVisible
local UnitInRange = UnitInRange
local UnitCanAssist = UnitCanAssist
local UnitCanAttack = UnitCanAttack
local UnitCanCooperate = UnitCanCooperate
local IsSpellInRangeAPI = C_Spell and C_Spell.IsSpellInRange
local LegacyIsSpellInRange = _G.IsSpellInRange
local IsItemInRange = C_Item and C_Item.IsItemInRange
local CheckInteractDistance = CheckInteractDistance
local UnitIsDead = UnitIsDead
local IsSpellKnownOrOverridesKnown = IsSpellKnownOrOverridesKnown
-- local GetSpellTabInfo = GetSpellTabInfo
-- local GetNumSpellTabs = GetNumSpellTabs
-- local GetSpellBookItemName = GetSpellBookItemName
-- local BOOKTYPE_SPELL = BOOKTYPE_SPELL
local IsSpellBookKnown = C_SpellBook and C_SpellBook.IsSpellKnown

local function IsSpellKnown(spellId)
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellId) then
        return true
    end
    if IsSpellBookKnown and IsSpellBookKnown(spellId) then
        return true
    end
    return false
end

local UnitInSamePhase
if Cell.isRetail then
    UnitInSamePhase = function(unit)
        return not UnitPhaseReason(unit)
    end
else
    UnitInSamePhase = UnitInPhase
end

local playerClass = UnitClassBase("player")

local friendSpells = {
    -- DEATHKNIGHT: no living-friendly-target spell in the kit -- see deadSpells.
    -- DEMONHUNTER: same, and no dead-target spell either.
    ["DRUID"] = (Cell.isWrath or Cell.isTBC or Cell.isVanilla) and 5185 or 8936, -- 治疗之触 / 愈合
    -- FIXME: [361469 活化烈焰] 会被英雄天赋 [431443 时序烈焰] 替代，但它而且有问题
    -- IsSpellInRange 始终返回 nil
    ["EVOKER"] = 355913, -- 翡翠之花
    ["HUNTER"] = 53271, -- Master's Call -- baseline, targets a friendly unit
    ["MAGE"] = 1459, -- 奥术智慧 / 奥术光辉
    ["MONK"] = 116670, -- 活血术
    ["PALADIN"] = Cell.isRetail and 19750 or 635, -- 圣光闪现 / 圣光术
    ["PRIEST"] = (Cell.isWrath or Cell.isTBC or Cell.isVanilla) and 2050 or 2061, -- 次级治疗术 / 快速治疗
    ["ROGUE"] = 57934, -- Tricks of the Trade -- talent, but the best available
    ["SHAMAN"] = Cell.isRetail and 8004 or 331, -- 治疗之涌 / 治疗波
    ["WARLOCK"] = 5697, -- 无尽呼吸
    ["WARRIOR"] = 3411, -- Intervene -- talent, but the best available
}

local deadSpells = {
    ["DEATHKNIGHT"] = 61999, -- Raise Ally -- baseline, dead-target only
    ["EVOKER"] = 361227, -- resurrection range, need separately for evoker
}

local petSpells = {
    ["HUNTER"] = 136,
}

local harmSpells = {
    ["DEATHKNIGHT"] = 47541, -- 凋零缠绕
    ["DEMONHUNTER"] = 185123, -- 投掷利刃
    ["DRUID"] = 5176, -- 愤怒
    -- FIXME: [361469 活化烈焰] 会被英雄天赋 [431443 时序烈焰] 替代，但它而且有问题
    -- IsSpellInRange 始终返回 nil
    ["EVOKER"] = 362969, -- 碧蓝打击
    ["HUNTER"] = 75, -- 自动射击
    ["MAGE"] = Cell.isRetail and 116 or 133, -- 寒冰箭 / 火球术
    ["MONK"] = 117952, -- 碎玉闪电
    ["PALADIN"] = 20271, -- 审判
    ["PRIEST"] = Cell.isRetail and 589 or 585, -- 暗言术：痛 / 惩击
    ["ROGUE"] = 1752, -- 影袭
    ["SHAMAN"] = Cell.isRetail and 188196 or 403, -- 闪电箭
    ["WARLOCK"] = 234153, -- 吸取生命
    ["WARRIOR"] = 355, -- 嘲讽
}

-- local friendItems = {
--     ["DEATHKNIGHT"] = 34471,
--     ["DEMONHUNTER"] = 34471,
--     ["DRUID"] = 34471,
--     ["EVOKER"] = 1180, -- 30y
--     ["HUNTER"] = 34471,
--     ["MAGE"] = 34471,
--     ["MONK"] = 34471,
--     ["PALADIN"] = 34471,
--     ["PRIEST"] = 34471,
--     ["ROGUE"] = 34471,
--     ["SHAMAN"] = 34471,
--     ["WARLOCK"] = 34471,
--     ["WARRIOR"] = 34471,
-- }

local harmItems = {
    ["DEATHKNIGHT"] = 28767, -- 40y
    ["DEMONHUNTER"] = 28767, -- 40y
    ["DRUID"] = 28767, -- 40y
    ["EVOKER"] = 24268, -- 25y
    ["HUNTER"] = 28767, -- 40y
    ["MAGE"] = 28767, -- 40y
    ["MONK"] = 28767, -- 40y
    ["PALADIN"] = 835, -- 30y
    ["PRIEST"] = 28767, -- 40y
    ["ROGUE"] = 28767, -- 40y
    ["SHAMAN"] = 28767, -- 40y
    ["WARLOCK"] = 28767, -- 40y
    ["WARRIOR"] = 28767, -- 40y
}

-- local FindSpellIndex
-- if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
--     FindSpellIndex = function(spellName)
--         if not spellName or spellName == "" then return end
--         return C_SpellBook.FindSpellBookSlotForSpell(spellName)
--     end
-- else
--     local function GetNumSpells()
--         local _, _, offset, numSpells = GetSpellTabInfo(GetNumSpellTabs())
--         return offset + numSpells
--     end

--     FindSpellIndex = function(spellName)
--         if not spellName or spellName == "" then return end
--         for i = 1, GetNumSpells() do
--             local spell = GetSpellBookItemName(i, BOOKTYPE_SPELL)
--             if spell == spellName then
--                 return i
--             end
--         end
--     end
-- end

local UnitInSpellRange
if IsSpellInRangeAPI then
    UnitInSpellRange = function(spellName, unit)
        local r = IsSpellInRangeAPI(spellName, unit)
        if not F.IsValueNonSecret(r) then return nil end
        if r == true or r == 1 then return true end
        if r == false or r == 0 then return false end
        return r and true or false
    end
else
    UnitInSpellRange = function(spellName, unit)
        if not LegacyIsSpellInRange then return nil end
        local result = LegacyIsSpellInRange(spellName, unit)
        if not F.IsValueNonSecret(result) then return nil end
        return result == 1 or result == true
    end
end

local rc = CreateFrame("Frame")
rc:RegisterEvent("SPELLS_CHANGED")

local spell_friend, spell_pet, spell_harm, spell_dead
CELL_RANGE_CHECK_FRIENDLY = {}
CELL_RANGE_CHECK_HOSTILE = {}
CELL_RANGE_CHECK_DEAD = {}
CELL_RANGE_CHECK_PET = {}

local function LoadSpellName(spellID, callback)
    if spellID and IsSpellKnown(spellID) then
        local spell = Spell:CreateFromSpellID(spellID)
        spell:ContinueOnSpellLoad(function()
            callback(spell:GetSpellName())
            -- print("Loaded spell for range check:", spellID, spell:GetSpellName())
        end)
    else
        callback(nil)
    end
end

local function SPELLS_CHANGED()
    local friend_id = CELL_RANGE_CHECK_FRIENDLY[playerClass] or friendSpells[playerClass]
    local harm_id = CELL_RANGE_CHECK_HOSTILE[playerClass] or harmSpells[playerClass]
    local dead_id = CELL_RANGE_CHECK_DEAD[playerClass] or deadSpells[playerClass]
    local pet_id = CELL_RANGE_CHECK_PET[playerClass] or petSpells[playerClass]

    LoadSpellName(friend_id, function(name) spell_friend = name end)
    LoadSpellName(harm_id, function(name) spell_harm = name end)
    LoadSpellName(dead_id, function(name) spell_dead = name end)
    LoadSpellName(pet_id, function(name) spell_pet = name end)

    -- F.Debug(
    --     "[RANGE CHECK]",
    --     "\nfriend:", spell_friend or "nil",
    --     "\npet:", spell_pet or "nil",
    --     "\nharm:", spell_harm or "nil",
    --     "\ndead:", spell_dead or "nil"
    -- )
end

local timer
local function DELAYED_SPELLS_CHANGED()
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(1, SPELLS_CHANGED)
end

rc:SetScript("OnEvent", DELAYED_SPELLS_CHANGED)

local function GetNonSecretBoolean(value, fallback)
    if value == nil then
        return fallback
    end
    if not F.IsValueNonSecret(value) then
        return fallback
    end
    if value == true or value == 1 then
        return true
    end
    if value == false or value == 0 then
        return false
    end
    return value and true or false
end

local function GetNonSecretRangeResult(value, fallback)
    if value == nil then
        return fallback
    end
    if not F.IsValueNonSecret(value) then
        return fallback
    end
    if value == true or value == 1 then
        return true
    end
    if value == false or value == 0 then
        return false
    end
    return fallback
end

function F.IsInRange(unit, check)
    -- Must run before the UnitIsVisible check below -- that can come back
    -- secret for the player's own unit, which would report self as out of range.
    local isPlayerUnit = GetNonSecretBoolean(UnitIsUnit("player", unit), false)
    if isPlayerUnit then
        return true
    end

    local visible = GetNonSecretBoolean(UnitIsVisible(unit), false)
    if not visible then
        return false
    end

    if not check and F.UnitInGroup(unit) then
        -- NOTE: UnitInRange only works with group players/pets
        --! but not available for PLAYER PET when SOLO
        local inRange, checked = UnitInRange(unit)
        local checkedBool = GetNonSecretBoolean(checked, nil)
        if checkedBool ~= true then
            return F.IsInRange(unit, true)
        end
        return GetNonSecretRangeResult(inRange, true)

    else
        local canAssist = GetNonSecretBoolean(UnitCanAssist("player", unit), false)
        if canAssist then -- or UnitCanCooperate("player", unit)
            local isConnected = GetNonSecretBoolean(UnitIsConnected(unit), false)
            local inSamePhase = true
            if UnitInSamePhase then
                inSamePhase = GetNonSecretBoolean(UnitInSamePhase(unit), true)
            end
            if not (isConnected and inSamePhase) then
                return false
            end

            local isDead = GetNonSecretBoolean(UnitIsDead(unit), false)
            if isDead then
                if spell_dead then
                    local deadInRange = GetNonSecretRangeResult(UnitInSpellRange(spell_dead, unit), nil)
                    if deadInRange ~= nil then
                        return deadInRange
                    end
                end
            elseif spell_friend then
                local friendInRange = GetNonSecretRangeResult(UnitInSpellRange(spell_friend, unit), nil)
                if friendInRange ~= nil then
                    return friendInRange
                end
            end

            local inRange, checked = UnitInRange(unit)
            local checkedBool = GetNonSecretBoolean(checked, nil)
            if checkedBool ~= true then
                -- Skip, fall through to pet/interact checks below
            else
                return GetNonSecretRangeResult(inRange, true)
            end

            local isPet = GetNonSecretBoolean(UnitIsUnit(unit, "pet"), false)
            if isPet and spell_pet then
                -- no spell_friend, use spell_pet
                local petInRange = GetNonSecretRangeResult(UnitInSpellRange(spell_pet, unit), nil)
                if petInRange ~= nil then
                    return petInRange
                end
            end

        else
            local canAttack = GetNonSecretBoolean(UnitCanAttack("player", unit), false)
            if canAttack then
                local isDead = GetNonSecretBoolean(UnitIsDead(unit), false)
                if isDead then
                    local deadInteract = GetNonSecretRangeResult(CheckInteractDistance(unit, 4), nil)
                    if deadInteract ~= nil then
                        return deadInteract -- 28 yards
                    end
                elseif spell_harm then
                    local harmInRange = GetNonSecretRangeResult(UnitInSpellRange(spell_harm, unit), nil)
                    if harmInRange ~= nil then
                        return harmInRange
                    end
                end

                if IsItemInRange then
                    local itemInRange = GetNonSecretRangeResult(IsItemInRange(harmItems[playerClass], unit), nil)
                    if itemInRange ~= nil then
                        return itemInRange
                    end
                end
            end
        end

        if not InCombatLockdown() then
            local interactInRange = GetNonSecretRangeResult(CheckInteractDistance(unit, 4), nil)
            if interactInRange ~= nil then
                return interactInRange -- 28 yards
            end
            return false
        end

        return true
    end
end

function F.IsSecretAuraUnitTrustworthy(unit, button)
    if not unit then
        return false
    end

    if GetNonSecretBoolean(UnitIsUnit("player", unit), false) then
        return true
    end

    if UnitExists and not GetNonSecretBoolean(UnitExists(unit), false) then
        return false
    end

    if UnitIsConnected and not GetNonSecretBoolean(UnitIsConnected(unit), false) then
        return false
    end

    if UnitIsVisible and not GetNonSecretBoolean(UnitIsVisible(unit), false) then
        return false
    end

    if UnitInSamePhase and not GetNonSecretBoolean(UnitInSamePhase(unit), true) then
        return false
    end

    if UnitPhaseReason then
        local phaseReason = UnitPhaseReason(unit)
        if F.IsValueNonSecret(phaseReason) and phaseReason then
            return false
        end
    end

    if button and F.BD(button).states and F.BD(button).states.inRange == false then
        return false
    end

    return true
end

-------------------------------------------------
-- RangeCheck debug
-------------------------------------------------
local debug = CreateFrame("Frame", "CellRangeCheckDebug", CellParent, "BackdropTemplate")
debug:SetBackdrop({bgFile = Cell.vars.whiteTexture})
debug:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
debug:SetBackdropBorderColor(0, 0, 0, 1)
debug:SetPoint("LEFT", 300, 0)
debug:Hide()

debug.text = debug:CreateFontString(nil, "OVERLAY")
debug.text:SetFont(GameFontNormal:GetFont(), 13, "")
debug.text:SetShadowColor(0, 0, 0)
debug.text:SetShadowOffset(1, -1)
debug.text:SetJustifyH("LEFT")
debug.text:SetSpacing(5)
debug.text:SetPoint("LEFT", 5, 0)

local function GetResult1()
    local inRange, checked = UnitInRange("target")

    return "UnitID: " .. (F.GetTargetUnitID("target") or "target") ..
        "\n|cffffff00F.IsInRange:|r " .. (F.IsInRange("target") and "true" or "false") ..
        "\nUnitInRange: " .. (checked and "checked" or "unchecked") .. " " .. (inRange and "true" or "false") ..
        "\nUnitIsVisible: " .. (UnitIsVisible("target") and "true" or "false") ..
        "\n\nUnitCanAssist: " .. (UnitCanAssist("player", "target") and "true" or "false") ..
        "\nUnitCanCooperate: " .. (UnitCanCooperate("player", "target") and "true" or "false") ..
        "\nUnitCanAttack: " .. (UnitCanAttack("player", "target") and "true" or "false") ..
        "\n\nUnitIsConnected: " .. (UnitIsConnected("target") and "true" or "false") ..
        "\nUnitInSamePhase: " .. (UnitInSamePhase("target") and "true" or "false") ..
        "\nUnitIsDead: " .. (UnitIsDead("target") and "true" or "false") ..
        "\n\nspell_friend: " .. (spell_friend and (spell_friend .. " " .. (UnitInSpellRange(spell_friend, "target") and "true" or "false")) or "none") ..
        "\nspell_dead: " .. (spell_dead and (spell_dead .. " " .. (UnitInSpellRange(spell_dead, "target") and "true" or "false")) or "none") ..
        "\nspell_pet: " .. (spell_pet and (spell_pet .. " " .. (UnitInSpellRange(spell_pet, "target") and "true" or "false")) or "none") ..
        "\nspell_harm: " .. (spell_harm and (spell_harm .. " " .. (UnitInSpellRange(spell_harm, "target") and "true" or "false")) or "none")
end

local function GetResult2()
    if UnitCanAttack("player", "target") then
        return "IsItemInRange: " .. (IsItemInRange(harmItems[playerClass], "target") and "true" or "false") ..
            "\nCheckInteractDistance(28y): " .. (CheckInteractDistance("target", 4) and "true" or "false")
    else
        return "IsItemInRange: " .. (InCombatLockdown() and "notAvailable" or (IsItemInRange(harmItems[playerClass], "target") and "true" or "false")) ..
            "\nCheckInteractDistance(28y): " .. (InCombatLockdown() and "notAvailable" or (CheckInteractDistance("target", 4) and "true" or "false"))
    end
end

debug:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed >= 0.25 then
        self.elapsed = 0
        local result = GetResult1() .. "\n\n" .. GetResult2()
        result = string.gsub(result, "none", "|cffabababnone|r")
        result = string.gsub(result, "true", "|cff00ff00true|r")
        result = string.gsub(result, "false", "|cffff0000false|r")
        result = string.gsub(result, " checked", " |cff00ff00checked|r")
        result = string.gsub(result, "unchecked", "|cffff0000unchecked|r")

        debug.text:SetText("|cffff0066Cell Range Check (Target)|r\n\n" .. result)

        debug:SetSize(debug.text:GetStringWidth() + 10, debug.text:GetStringHeight() + 20)
    end
end)

debug:SetScript("OnEvent", function()
    if not UnitExists("target") then
        debug:Hide()
        return
    end

    debug:Show()
end)

SLASH_CELLRC1 = "/cellrc"
function SlashCmdList.CELLRC()
    if debug:IsEventRegistered("PLAYER_TARGET_CHANGED") then
        debug:UnregisterEvent("PLAYER_TARGET_CHANGED")
        debug:Hide()
    else
        debug:RegisterEvent("PLAYER_TARGET_CHANGED")
        if UnitExists("target") then
            debug:Show()
        end
    end
end

---------------------------------------------------------------------
-- spec data
---------------------------------------------------------------------
if Cell.isMists then

end

-------------------------------------------------
-- unit button data (SecureGroupHeader child frames)
-------------------------------------------------
if not Cell.buttonData then
    Cell.buttonData = setmetatable({}, { __mode = "k" })
end

if not F.GetButtonData then
    function F.GetButtonData(button)
        if not button then
            return {}
        end
        local d = Cell.buttonData[button]
        if not d then
            d = {}
            Cell.buttonData[button] = d
        end
        return d
    end
end

if not F.BD then
    function F.BD(button)
        return F.GetButtonData(button)
    end
end

-------------------------------------------------
-- secrets
-------------------------------------------------
function F.HasAnySecretValues(...)
    if not Cell.isMidnight then return false end
    if not hasanysecretvalues then return false end
    return hasanysecretvalues(...)
end

function F.IsAuraRestricted()
    if GetRestrictedActionStatus and Enum and Enum.RestrictedActionType then
        local isRestricted = GetRestrictedActionStatus(Enum.RestrictedActionType.SecretAuras)
        if isRestricted == true then
            return true
        end
    end
    local build = select(4, GetBuildInfo())
    if Cell.isRetail and build and build >= 120100 and InCombatLockdown() then
        return true
    end
    return false
end

function F.IsLiveAuraScanBlocked()
    return Cell.isMidnight
end

function F.InitEngineAuraButtonOnce(button)
    if not button or button._cellAuraInited then
        return false
    end
    button._cellAuraInited = true
    return true
end

function F.RestyleEngineAuraButtonFonts(button, cfg, styleFont)
    if not (button and cfg) then return end
    local host = button._cellAuraTextHost or button
    local function isForbidden(obj)
        if not obj then return true end
        local ok, forbidden = pcall(function()
            return obj.IsForbidden and obj:IsForbidden()
        end)
        return (not ok) or forbidden
    end
    local function apply(fs, fontCfg, defaultAnchor, defaultX, defaultY)
        if not fs or isForbidden(fs) then return end
        local anchor = (type(fontCfg) == "table" and fontCfg[5]) or defaultAnchor
        local ox = (type(fontCfg) == "table" and fontCfg[6]) or defaultX
        local oy = (type(fontCfg) == "table" and fontCfg[7]) or defaultY
        if not pcall(fs.ClearAllPoints, fs) then return end
        pcall(fs.SetPoint, fs, anchor, host, anchor, ox, oy)
        if styleFont then
            pcall(styleFont, fs, fontCfg, 11)
        end
        if type(fontCfg) == "table" and type(fontCfg[8]) == "table" then
            local c = fontCfg[8]
            pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        end
    end
    apply(button._cellStackFS, cfg.font and cfg.font[1], "TOPRIGHT", 2, 1)
    apply(button._cellDurationFS, cfg.font and cfg.font[2], "BOTTOMRIGHT", 2, -1)
    if button._cellStackFS and not isForbidden(button._cellStackFS) then
        pcall(button._cellStackFS.SetShown, button._cellStackFS, cfg.showStack ~= false)
    end
    if button._cellDurationFS and cfg.showDuration and not isForbidden(button._cellDurationFS) then
        F.BindAuraDurationText(button, button._cellDurationFS, F.GetAuraDurationFormatter and F.GetAuraDurationFormatter(), cfg.auras)
    end
end

function F.RestyleAuraContainerFonts(container, cfg, styleFont)
    if not container then return end
    local function isForbidden(obj)
        if not obj then return true end
        local ok, forbidden = pcall(function()
            return obj.IsForbidden and obj:IsForbidden()
        end)
        return (not ok) or forbidden
    end
    local function walk(frame, depth)
        if not frame or depth > 4 or isForbidden(frame) then return end
        if frame._cellStackFS or frame._cellDurationFS then
            F.RestyleEngineAuraButtonFonts(frame, cfg, styleFont)
        end
        if not frame.GetNumChildren or not frame.GetChildren then return end
        local okCount, n = pcall(frame.GetNumChildren, frame)
        if not okCount or type(n) ~= "number" or n <= 0 or n > 40 then return end
        local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10,
            a11, a12, a13, a14, a15, a16, a17, a18, a19, a20,
            a21, a22, a23, a24, a25, a26, a27, a28, a29, a30,
            a31, a32, a33, a34, a35, a36, a37, a38, a39, a40 = pcall(frame.GetChildren, frame)
        if not ok then return end
        local kids = { a1, a2, a3, a4, a5, a6, a7, a8, a9, a10,
            a11, a12, a13, a14, a15, a16, a17, a18, a19, a20,
            a21, a22, a23, a24, a25, a26, a27, a28, a29, a30,
            a31, a32, a33, a34, a35, a36, a37, a38, a39, a40 }
        local limit = math.min(n, #kids)
        for i = 1, limit do
            walk(kids[i], depth + 1)
        end
    end
    walk(container, 0)
end

-- No eviction cap here on purpose: WoW frames created via CreateFrame can never
-- actually be destroyed/freed during a session, so evicting an entry would only
-- drop Cell's own reference and permanently orphan an otherwise-reusable hidden
-- frame -- a real memory leak over a long session. Parked containers are hidden/
-- quiesced and cost effectively nothing while idle, so there's no upside to
-- evicting -- only ever grow the park map, never shrink it.

function F.StampAuraFont(font)
    if type(font) ~= "table" then
        return tostring(font or "")
    end
    local function part(v)
        if type(v) ~= "table" then
            return tostring(v or "")
        end
        return table.concat({
            tostring(v[1] or ""),
            tostring(v[2] or ""),
            tostring(v[3] or ""),
            tostring(v[4] or ""),
        }, ",")
    end
    if type(font[1]) == "table" or type(font[2]) == "table" then
        return part(font[1]) .. "/" .. part(font[2])
    end
    return part(font)
end

function F.AuraParkKey(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "boolean" then
            t[i] = v and "1" or "0"
        elseif v == nil then
            t[i] = ""
        else
            t[i] = tostring(v)
        end
    end
    local colors = Cell.vars.iconDurationColors
    if type(colors) == "table" then
        for i = 1, 3 do
            local c = colors[i]
            if type(c) == "table" then
                t[#t + 1] = tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3]) .. "," .. tostring(c[4])
            end
        end
    end
    return table.concat(t, "|")
end

function F.QuiesceAuraContainer(container)
    if not container then return end
    pcall(function()
        container:Hide()
        if container.SetUnit then
            container:SetUnit(nil)
        end
        container:ClearAllPoints()
        container:SetParent(UIParent)
        container:SetAlpha(0)
        container:SetSize(1, 1)
    end)
end

function F.ParkAuraContainer(parkMap, key, container)
    if not container then return end
    F.QuiesceAuraContainer(container)
    if type(parkMap) ~= "table" or type(key) ~= "string" or key == "" then
        return
    end
    -- No eviction here on purpose -- see the note above local removed AURA_PARK_CAP.
    parkMap[key] = container
end

function F.AcquireParkedAuraContainer(parkMap, key, parent)
    if type(parkMap) ~= "table" or type(key) ~= "string" or key == "" then
        return nil
    end
    local container = parkMap[key]
    if not container then
        return nil
    end
    parkMap[key] = nil
    parent = parent or UIParent
    pcall(function()
        container:SetAlpha(1)
        container:SetParent(parent)
    end)
    return container
end

function F.ApplyAuraGroupTuning(container, groupKey, filter, opts)
    if not (container and groupKey) then
        return false
    end
    if container.HasAuraGroup and not container:HasAuraGroup(groupKey) then
        return false
    end
    if not container.HasAuraGroup then
        return false
    end
    if filter and container.SetAuraGroupFilterString then
        pcall(container.SetAuraGroupFilterString, container, groupKey, filter)
    end
    opts = opts or {}
    if opts.maxFrameCount and container.SetAuraGroupMaxFrameCount then
        pcall(container.SetAuraGroupMaxFrameCount, container, groupKey, opts.maxFrameCount)
    end
    if opts.candidateFilters and container.SetAuraGroupCandidateFilters then
        pcall(container.SetAuraGroupCandidateFilters, container, groupKey, opts.candidateFilters)
    end
    if opts.layout and container.SetAuraGroupLayout then
        pcall(container.SetAuraGroupLayout, container, groupKey, opts.layout)
    end
    if opts.sortMethod and container.SetAuraGroupSortMethod then
        pcall(container.SetAuraGroupSortMethod, container, groupKey, opts.sortMethod, opts.sortDirection)
    end
    return true
end

function F.PauseAuraContainer(container)
end

function F.GuardAuraContainerEvents(container)
end

local function IsAuraEngineContainer(frame)
    return frame and (frame.UpdateAllAuras or frame.AddAuraGroup or frame.HasAuraGroup)
end

function F.IsAuraEngineContainer(frame)
    return IsAuraEngineContainer(frame)
end

-- Midnight: SecureGroupHeaderTemplate can birth an AuraContainer per child (secure-side).
function F.ApplyMidnightGroupHeaderAttributes(header)
    if Cell.isMidnight and header and header.SetAttribute then
        header:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
    end
end

function F.IsHeaderAuraContainer(unitButton, container)
    return Cell.isMidnight and unitButton and container and unitButton.AuraContainer == container
end

-- Adopt the header-born AuraContainer (one owner per button; e.g. combat debuffs).
function F.AdoptHeaderAuraContainer(unitButton, parent, ownerKey)
    if not (Cell.isMidnight and unitButton and ownerKey) then
        return nil
    end
    local container = unitButton.AuraContainer
    if not IsAuraEngineContainer(container) then
        return nil
    end
    local bd = F.GetButtonData(unitButton)
    if bd._headerAuraOwner and bd._headerAuraOwner ~= ownerKey then
        return nil
    end
    bd._headerAuraOwner = ownerKey
    parent = parent or unitButton
    pcall(function()
        container:SetAlpha(1)
        container:SetParent(parent)
    end)
    return container
end

local function StripUnitAuraTree(frame)
    if not frame then return end
    if frame.UnregisterEvent then
        pcall(frame.UnregisterEvent, frame, "UNIT_AURA")
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if child and not (child.IsForbidden and child:IsForbidden()) and not IsAuraEngineContainer(child) then
                StripUnitAuraTree(child)
            end
        end
    end
end

-- Caches the flat list of frames a root needs UnregisterEvent called on,
-- built once and reused on the hot roster-update path -- a roster event
-- only ever swaps which unit a button displays, never its child widgets.
-- The background ticker below rebuilds these on its own slow schedule so a
-- lazily-created widget still gets picked up eventually.
local stripCache = setmetatable({}, { __mode = "k" })

local function BuildStripList(root, list)
    if not root then return end
    if root.UnregisterEvent then
        list[#list + 1] = root
    end
    if root.GetChildren then
        local children = { root:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if child and not (child.IsForbidden and child:IsForbidden()) and not IsAuraEngineContainer(child) then
                BuildStripList(child, list)
            end
        end
    end
end

local function StripUnitAuraTreeCached(root)
    if not root then return end
    local entry = stripCache[root]
    if not entry then
        entry = { list = {} }
        BuildStripList(root, entry.list)
        stripCache[root] = entry
    end
    local list = entry.list
    for i = 1, #list do
        pcall(list[i].UnregisterEvent, list[i], "UNIT_AURA")
    end
end

-- Background refresh of the caches above, decoupled from GROUP_ROSTER_UPDATE
-- so roster churn never triggers a tree walk.
local REFRESH_INTERVAL = 30
local refreshQueue, refreshIdx = {}, 1

local function RefreshStripCachesStep()
    local budget = 2
    while budget > 0 and refreshIdx <= #refreshQueue do
        local root = refreshQueue[refreshIdx]
        if root then
            local list = {}
            BuildStripList(root, list)
            stripCache[root] = { list = list }
        end
        refreshIdx = refreshIdx + 1
        budget = budget - 1
    end
    if refreshIdx <= #refreshQueue then
        C_Timer.After(0, RefreshStripCachesStep)
    end
end

-- CellParent and Cell.frames.mainFrame used to be in this list too, but
-- each has ~27,700 descendant frames (every settings panel/dropdown Cell
-- has ever created) that can never realistically carry a UNIT_AURA
-- registration -- walking them was by far the dominant cost here.
C_Timer.NewTicker(REFRESH_INTERVAL, function()
    if not Cell.isMidnight then return end
    wipe(refreshQueue)
    if F.IterateAllUnitButtons then
        F.IterateAllUnitButtons(function(b) refreshQueue[#refreshQueue + 1] = b end)
    end
    if Cell.frames and Cell.frames.buffTrackerFrame then
        refreshQueue[#refreshQueue + 1] = Cell.frames.buffTrackerFrame
    end
    if _G.CellQuickCastFrame then refreshQueue[#refreshQueue + 1] = _G.CellQuickCastFrame end
    if _G.CellQuickAssistFrame then refreshQueue[#refreshQueue + 1] = _G.CellQuickAssistFrame end
    refreshIdx = 1
    RefreshStripCachesStep()
end)

function F.StripCellUnitAura()
    if not Cell.isMidnight then return end
    -- Only currently-shown buttons: F.IterateAllUnitButtons without its
    -- "current group only" flag also walks pet/NPC/arena/spotlight buttons
    -- (~90 total), most of which sit hidden most of the time.
    if F.IterateAllUnitButtons then
        F.IterateAllUnitButtons(function(b)
            if b:IsShown() then
                StripUnitAuraTreeCached(b)
            end
        end)
    end
    if Cell.frames and Cell.frames.buffTrackerFrame then
        StripUnitAuraTreeCached(Cell.frames.buffTrackerFrame)
    end
    if _G.CellQuickCastFrame then
        StripUnitAuraTreeCached(_G.CellQuickCastFrame)
    end
    if _G.CellQuickAssistFrame then
        StripUnitAuraTreeCached(_G.CellQuickAssistFrame)
    end
    if _G.CellStatusIconCleuFrame then
        pcall(_G.CellStatusIconCleuFrame.UnregisterEvent, _G.CellStatusIconCleuFrame, "UNIT_AURA")
    end
end

function F.ResumeAuraContainer(container)
    if not container then return end
    pcall(function()
        if container.UpdateAllAuras then
            container:UpdateAllAuras()
        end
    end)
end

function F.IsCooldownRestricted()
    if GetRestrictedActionStatus and Enum and Enum.RestrictedActionType then
        local isRestricted = GetRestrictedActionStatus(Enum.RestrictedActionType.SecretCooldowns)
        return isRestricted == true
    end
    return false
end

function F.IsAuraNonSecret(auraInfo)
    if not Cell.isMidnight then return true end
    if not issecretvalue then return true end
    return not issecretvalue(auraInfo.spellId)
end

function F.IsSpellAuraNonSecret(spellId)
    if not Cell.isMidnight then return true end
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        return not C_Secrets.ShouldSpellAuraBeSecret(spellId)
    end
    return false
end

function F.IsValueNonSecret(val)
    if not Cell.isMidnight then return true end
    if not issecretvalue then return true end
    return not issecretvalue(val)
end

function F.IsKnownTrue(value)
    return F.IsValueNonSecret(value) and value and true or false
end

function F.IsPlayerOrPartyAI(unit)
    if not unit then return false end
    return F.IsKnownTrue(UnitIsPlayer(unit)) or F.IsKnownTrue(UnitInPartyIsAI(unit))
end

function F.GetRemain(start, duration)
    if not start or not duration then return 0 end
    if Cell.isMidnight then
        if not F.IsValueNonSecret(start) or not F.IsValueNonSecret(duration) then
            return 0
        end
    end
    local remain = duration - (GetTime() - start)
    return remain > 0 and remain or 0
end

function F.GetWidth(frame)
    if not frame then return 0 end
    local w = frame.GetWidth and frame:GetWidth() or 0
    if not F.IsValueNonSecret(w) then return 0 end
    return w or 0
end

function F.GetHeight(frame)
    if not frame then return 0 end
    local h = frame.GetHeight and frame:GetHeight() or 0
    if not F.IsValueNonSecret(h) then return 0 end
    return h or 0
end

function F.IsFontValid(font)
    if type(font) ~= "string" or font == "" then return false end
    if not _G.CellFontValidator then
        _G.CellFontValidator = UIParent:CreateFontString(nil, "ARTWORK")
    end
    local success = pcall(function() _G.CellFontValidator:SetFont(font, 12, "") end)
    return success
end

-------------------------------------------------
-- communication
-------------------------------------------------
local restrictedChatTypes = {
    PARTY = true,
    PARTY_LEADER = true,
    RAID = true,
    RAID_LEADER = true,
    RAID_WARNING = true,
    INSTANCE_CHAT = true,
    INSTANCE_CHAT_LEADER = true,
    WHISPER = true,
    GUILD = true,
    OFFICER = true,
    CHANNEL = true,
}

local restrictedAddonChannels = {
    PARTY = true,
    RAID = true,
    INSTANCE_CHAT = true,
    WHISPER = true,
    GUILD = true,
    OFFICER = true,
    CHANNEL = true,
}

function F.IsCommRestricted()
    if not Cell.isMidnight then return false end
    if IsEncounterInProgress and IsEncounterInProgress() then return true end
    if C_MythicPlus and C_MythicPlus.IsRunActive and C_MythicPlus.IsRunActive() then return true end
    if C_PvP and C_PvP.IsActiveBattlefield and C_PvP.IsActiveBattlefield() then return true end
    return false
end

function F.IsSecretContextActive()
    return F.IsAuraRestricted() or F.IsCooldownRestricted() or F.IsCommRestricted()
end

function F.GetGroupCommChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
end

function F.CanSendChatMessage(chatType)
    if not chatType then return false end
    if not Cell.isMidnight then return true end
    if restrictedChatTypes[chatType] and F.IsCommRestricted() then
        return false
    end
    return true
end

function F.TrySendChatMessage(msg, chatType, language, target)
    if not msg or msg == "" or not chatType then return false end
    msg = tostring(msg)
    if not F.CanSendChatMessage(chatType) then
        F.Debug("Cell: Chat suppressed - restricted context ("..tostring(chatType)..")")
        return false
    end
    SendChatMessage(msg, chatType, language, target)
    return true
end

function F.CanSendAddonMessage(channel)
    if not channel then return false end
    if not Cell.isMidnight then return true end
    if restrictedAddonChannels[channel] and F.IsCommRestricted() then
        return false
    end
    return true
end

function F.TrySendAddonMessage(prefix, message, channel, target)
    if not prefix or not message or not channel then return false end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    message = tostring(message)
    if not F.CanSendAddonMessage(channel) then
        F.Debug("Cell: Addon message suppressed - restricted context ("..tostring(prefix)..")")
        return false
    end
    C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
    return true
end

function F.SendRequestAddonMessage(prefix, message, target)
    local channel = F.GetGroupCommChannel()
    if not channel then
        F.Debug("Cell: Addon message suppressed - no group channel ("..tostring(prefix)..")")
        return false
    end
    return F.TrySendAddonMessage(prefix, message, channel, target)
end
