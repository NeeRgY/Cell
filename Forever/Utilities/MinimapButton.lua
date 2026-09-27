local _, Cell = ...
local L = Cell.L
local F = Cell.funcs

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

local ICON = "Interface\\AddOns\\Cell\\Media\\icon.tga"
local BUTTON_NAME = "CellMinimapButton"

local button

local function EnsureDB()
    if type(CellDB) ~= "table" then return false end
    if type(CellDB["minimap"]) ~= "table" then
        CellDB["minimap"] = {
            minimapPos = 220,
        }
    end
    if type(CellDB["general"]) ~= "table" then
        return false
    end
    if CellDB["general"]["showMinimapButton"] == nil then
        CellDB["general"]["showMinimapButton"] = true
    end
    return true
end

local function UpdatePosition()
    if not button then return end
    EnsureDB()

    local angle = math.rad(CellDB["minimap"]["minimapPos"] or 220)
    local x, y = math.cos(angle), math.sin(angle)
    local round = true
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape ~= "ROUND" then
        round = false
    end

    local w = (Minimap:GetWidth() / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    if round then
        x, y = x * w, y * h
    else
        x = math.max(-w, math.min(x * w * 1.414, w))
        y = math.max(-h, math.min(y * h * 1.414, h))
    end

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateButton()
    if button or not Minimap then return end

    button = CreateFrame("Button", BUTTON_NAME, Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:SetHighlightTexture(136477) -- Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture(136430) -- Interface\\Minimap\\MiniMap-TrackingBorder
    overlay:SetPoint("TOPLEFT")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture(136467) -- Interface\\Minimap\\UI-Minimap-Background
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Cell", 1, 1, 1)
        GameTooltip:AddLine(L["Left-Click"]..": "..L["Options"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Drag to move"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" and not button.isDragging then
            F.ShowOptionsFrame()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            EnsureDB()
            CellDB["minimap"]["minimapPos"] = math.deg(math.atan2(py - my, px - mx)) % 360
            UpdatePosition()
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        -- delay clear so OnClick ignores this drag
        C_Timer.After(0, function()
            self.isDragging = false
        end)
    end)

    UpdatePosition()
end

function F.UpdateMinimapButton()
    if not EnsureDB() then return end
    if not button then
        CreateButton()
    end
    if not button then return end

    if CellDB["general"]["showMinimapButton"] then
        button:Show()
        UpdatePosition()
    else
        button:Hide()
    end
end

-- Addon compartment (Settings -> AddOns / compartment menu) — TOC + runtime fallback
function Cell_OnAddonCompartmentClick()
    F.ShowOptionsFrame()
end

local function RegisterAddonCompartment()
    -- TOC ## AddonCompartmentFunc covers modern clients; runtime register is fallback
    -- when the compartment UI exists but Cell is not listed yet.
    if not AddonCompartmentFrame or not AddonCompartmentFrame.RegisterAddon then
        return
    end
    if AddonCompartmentFrame.registeredAddons then
        for _, entry in pairs(AddonCompartmentFrame.registeredAddons) do
            if entry and entry.text == "Cell" then
                return
            end
        end
    end
    AddonCompartmentFrame:RegisterAddon({
        text = "Cell",
        icon = ICON,
        registerForAnyClick = true,
        notCheckable = true,
        func = function()
            F.ShowOptionsFrame()
        end,
    })
end

local init
local function InitMinimap()
    if init then return end
    if not EnsureDB() then return end
    init = true
    F.UpdateMinimapButton()
    RegisterAddonCompartment()
end

Cell.RegisterCallback("AddonLoaded", "CellMinimap_AddonLoaded", InitMinimap)

-- fallback if callback already fired
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    InitMinimap()
end)
