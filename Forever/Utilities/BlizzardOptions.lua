local _, Cell = ...
local L = Cell.L
local F = Cell.funcs

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

local ICON = "Interface\\AddOns\\Cell\\Media\\icon.tga"
local PANEL = { r = 0.08, g = 0.09, b = 0.11 }
local CARD  = { r = 0.12, g = 0.13, b = 0.16 }

local function GetAccent()
    if Cell.GetAccentColorRGB then
        local r, g, b = Cell.GetAccentColorRGB()
        return { r = r, g = g, b = b }
    end
    local class = select(2, UnitClass("player"))
    local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if c then
        return { r = c.r, g = c.g, b = c.b }
    end
    return { r = 1, g = 0.55, b = 0.70 }
end

local function ColorTex(tex, c, a)
    tex:SetColorTexture(c.r, c.g, c.b, a or 1)
end

local function MakeFS(parent, template, text, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if r then fs:SetTextColor(r, g, b) end
    if text then fs:SetText(text) end
    return fs
end

local function RegisterSettingsCategory()
    if not Settings or not Settings.RegisterCanvasLayoutCategory or not Settings.RegisterAddOnCategory then
        return
    end
    if Cell.settingsCategory then
        return
    end

    local accent = GetAccent()
    local root = CreateFrame("Frame")
    local themed = {}

    local bg = root:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ColorTex(bg, PANEL, 1)

    local wash = root:CreateTexture(nil, "BACKGROUND", nil, 1)
    wash:SetPoint("TOPLEFT", 0, 0)
    wash:SetPoint("BOTTOMLEFT", 0, 0)
    wash:SetWidth(5)
    themed.wash = wash

    local card = CreateFrame("Frame", nil, root, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 28, -36)
    card:SetPoint("BOTTOMRIGHT", -28, 36)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(CARD.r, CARD.g, CARD.b, 0.95)
    themed.card = card

    local topGlow = card:CreateTexture(nil, "ARTWORK")
    topGlow:SetPoint("TOPLEFT", 1, -1)
    topGlow:SetPoint("TOPRIGHT", -1, -1)
    topGlow:SetHeight(40)
    themed.topGlow = topGlow

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 22, -22)

    local title = MakeFS(card, "GameFontNormalHuge", "Cell")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 16, -4)
    themed.title = title

    local version = GetAddOnMetadata("Cell", "Version") or ""
    local versionText = MakeFS(card, "GameFontHighlight", (L["Version"] or "Version").."  ·  "..version, 0.70, 0.72, 0.78)
    versionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    local tag = MakeFS(card, "GameFontNormalSmall", "RAID / PARTY FRAMES")
    tag:SetPoint("TOPLEFT", versionText, "BOTTOMLEFT", 0, -8)
    themed.tag = tag

    local divider = card:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 22, -110)
    divider:SetPoint("TOPRIGHT", -22, -110)
    divider:SetHeight(1)
    themed.divider = divider

    local button
    if Cell.CreateButton then
        button = Cell.CreateButton(card, L["Open Options"], "accent-hover", {180, 24})
        button:SetPoint("BOTTOMLEFT", 22, 24)
    else
        button = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        button:SetSize(180, 24)
        button:SetPoint("BOTTOMLEFT", 22, 24)
        button:SetText(L["Open Options"])
    end
    button:SetScript("OnClick", function()
        if SettingsPanel then
            HideUIPanel(SettingsPanel)
        end
        F.ShowOptionsFrame()
    end)

    local hint = MakeFS(card, "GameFontDisableSmall", "/cell options", 0.45, 0.48, 0.55)
    hint:SetPoint("LEFT", button, "RIGHT", 12, 0)

    local function ApplyTheme(c)
        accent = c or GetAccent()
        ColorTex(themed.wash, accent, 0.9)
        if themed.wash.SetGradient and CreateColor then
            themed.wash:SetColorTexture(1, 1, 1, 1)
            themed.wash:SetGradient("VERTICAL",
                CreateColor(accent.r, accent.g, accent.b, 0.2),
                CreateColor(accent.r, accent.g, accent.b, 0.95)
            )
        end
        themed.card:SetBackdropBorderColor(accent.r, accent.g, accent.b, 0.4)
        if themed.topGlow.SetGradient and CreateColor then
            themed.topGlow:SetColorTexture(1, 1, 1, 1)
            themed.topGlow:SetGradient("VERTICAL",
                CreateColor(accent.r, accent.g, accent.b, 0),
                CreateColor(accent.r, accent.g, accent.b, 0.16)
            )
        else
            ColorTex(themed.topGlow, accent, 0.1)
        end
        themed.title:SetTextColor(accent.r, accent.g, accent.b)
        themed.tag:SetTextColor(accent.r, accent.g, accent.b)
        ColorTex(themed.divider, accent, 0.4)
    end

    ApplyTheme(accent)

    root.OnCommit = function() end
    root.OnDefault = function() end
    root.OnRefresh = function()
        ApplyTheme(GetAccent())
    end

    local category = Settings.RegisterCanvasLayoutCategory(root, "Cell")
    category.ID = "Cell"
    Settings.RegisterAddOnCategory(category)
    Cell.settingsCategory = category
end

local init
local function Init()
    if init then return end
    init = true
    RegisterSettingsCategory()
end

Cell.RegisterCallback("AddonLoaded", "CellBlizzardOptions_AddonLoaded", Init)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Init()
end)
