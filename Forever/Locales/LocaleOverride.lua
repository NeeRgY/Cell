-- Locale override bootstrap
-- Runs before locale files in LoadLocales.xml.
-- It rewrites LOCALE_xx globals so locale chunks can load by user selection.

local supported = {
    "enUS", "zhCN", "zhTW", "koKR", "ptBR", "deDE", "ruRU", "frFR", "esES", "itIT", "esMX",
}

local _, Cell = ...
Cell.supportedLocales = supported

local function IsSupported(locale)
    for _, code in ipairs(supported) do
        if code == locale then return true end
    end
    return false
end

local selected = CellDB and CellDB.general and CellDB.general.localeOverride
local clientLocale = GetLocale and GetLocale() or "enUS"
local effective = (selected and selected ~= "auto") and selected or clientLocale
if not IsSupported(effective) then
    effective = clientLocale
end
if not IsSupported(effective) then
    effective = "enUS"
end

for _, code in ipairs(supported) do
    _G["LOCALE_" .. code] = (code == effective)
end

