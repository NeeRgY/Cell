local _, Cell = ...
local F = Cell.funcs
local B = Cell.bFuncs
local P = Cell.pixelPerfectFuncs

local partyFrame = CreateFrame("Frame", "CellPartyFrame", Cell.frames.mainFrame, "SecureFrameTemplate")
Cell.frames.partyFrame = partyFrame
partyFrame:SetAllPoints(Cell.frames.mainFrame)

if not Cell.isRetail then
    partyFrame:HookScript("OnShow", function()
        F.Debug("|cff77bbffpartyFrame:|r OnShow InCombat="..tostring(InCombatLockdown()))
    end)
    partyFrame:HookScript("OnHide", function()
        F.Debug("|cff77bbffpartyFrame:|r OnHide InCombat="..tostring(InCombatLockdown()))
    end)
end

local header = CreateFrame("Frame", "CellPartyFrameHeader", partyFrame, "SecureGroupHeaderTemplate")
F.ApplyMidnightGroupHeaderAttributes(header)
header:SetAttribute("template", "CellUnitButtonTemplate")

function header:UpdateButtonUnit(bName, unit)
    if not unit then return end

    _G[bName].unit = unit -- OmniCD

    local petUnit
    if unit == "player" then
        petUnit = "pet"
    else
        petUnit = string.gsub(unit, "party", "partypet")
    end
    Cell.unitButtons.party.units[unit] = _G[bName]
    Cell.unitButtons.party.units[petUnit] = F.BD(_G[bName]).petButton
end

-- header:SetAttribute("initialConfigFunction", [[
--     RegisterUnitWatch(self)

--     local header = self:GetParent()
--     self:SetWidth(header:GetAttribute("buttonWidth") or 66)
--     self:SetHeight(header:GetAttribute("buttonHeight") or 46)
-- ]])

header:SetAttribute("_initialAttributeNames", "refreshUnitChange")
header:SetAttribute("_initialAttribute-refreshUnitChange", [[
    local unit = self:GetAttribute("unit")
    local header = self:GetParent()
    local petButton = self:GetFrameRef("petButton")

    -- print(self:GetName(), unit, petButton)

    if petButton and header:GetAttribute("showPartyPets") and not header:GetAttribute("partyDetached") then
        local petUnit
        if unit == "player" then
            petUnit = "pet"
        else
            petUnit = string.gsub(unit, "party", "partypet")
        end
        petButton:SetAttribute("unit", petUnit)
        RegisterUnitWatch(petButton)
    end

    header:CallMethod("UpdateButtonUnit", self:GetName(), unit)
]])

header:SetAttribute("point", "TOP")
header:SetAttribute("xOffset", 0)
header:SetAttribute("yOffset", -1)
header:SetAttribute("maxColumns", 1)
header:SetAttribute("unitsPerColumn", 5)
header:SetAttribute("showPlayer", true)
header:SetAttribute("showParty", true)
if not Cell.isRetail then
    -- native showSolo shows just the player when ungrouped, via the same combat-safe header logic
    -- that already handles party members -- replaces the old separate SoloFrame driver approach.
    header:SetAttribute("showSolo", true)
end

--! to make needButtons == 5 cheat configureChildren in SecureGroupHeaders.lua
header:SetAttribute("startingIndex", -4)
header:Show()
header:SetAttribute("startingIndex", 1)

-- init pet buttons
for i, playerButton in ipairs(header) do
    -- playerButton.type = "main" -- layout setup

    local petButton = CreateFrame("Button", playerButton:GetName().."Pet", playerButton, "CellUnitButtonTemplate")
    -- petButton.type = "pet" -- layout setup
    petButton:SetIgnoreParentAlpha(true)

    --! button for pet/vehicle only, toggleForVehicle MUST be false
    petButton:SetAttribute("toggleForVehicle", false)

    F.BD(playerButton).petButton = petButton
    SecureHandlerSetFrameRef(playerButton, "petButton", petButton)

    -- for IterateAllUnitButtons
    Cell.unitButtons.party["player"..i] = playerButton
    Cell.unitButtons.party["pet"..i] = petButton

    -- OmniCD
    _G["CellPartyFrameMember"..i] = playerButton
end

local function PartyFrame_UpdateLayout(layout, which)
    -- visibility
    if Cell.isRetail then
        if Cell.vars.groupType ~= "party" or Cell.vars.isHidden then
            UnregisterAttributeDriver(partyFrame, "state-visibility")
            partyFrame:Hide()
            return
        else
            RegisterAttributeDriver(partyFrame, "state-visibility", "[@raid1,exists] hide;[@party1,exists] show;[group:party] show;hide")
        end
    else
        -- Classic: with showSolo on the header, this frame stays shown for solo too -- the 0-vs-N
        -- member count is left entirely to the header's own native logic.
        local isHiddenNow
        if Cell.vars.groupType == "solo" then
            isHiddenNow = F.IsGroupTypeHidden(Cell.vars.soloLayoutGroupType)
        else
            isHiddenNow = F.IsGroupTypeHidden(Cell.vars.partyLayoutGroupType)
        end
        F.Debug("|cff77bbffPartyFrame_UpdateLayout:|r groupType="..tostring(Cell.vars.groupType)
            .." IsGroupTypeHidden="..tostring(isHiddenNow)
            .." InCombat="..tostring(InCombatLockdown()))
        if isHiddenNow then
            RegisterAttributeDriver(partyFrame, "state-visibility", "hide")
            partyFrame:Hide()
            return
        else
            RegisterAttributeDriver(partyFrame, "state-visibility", "[@raid1,exists] hide;show")
        end

        if Cell.vars.groupType == "solo" then
            -- Solo: use Solo's own layout, not Party's, even though this header renders it
            local ownLayout = F.GetGroupTypeLayout(Cell.vars.soloLayoutGroupType)
            if not ownLayout then return end
            layout = ownLayout
        elseif Cell.vars.groupType ~= "party" then
            -- lay out ahead of time even while inactive, so it's not blank the first time combat shows it
            local ownLayout = F.GetGroupTypeLayout(Cell.vars.partyLayoutGroupType)
            if not ownLayout then return end
            layout = ownLayout
        end
    end

    -- update
    layout = CellDB["layouts"][layout]

    -- anchor
    if not which or which == "main-arrangement" or which == "pet-arrangement" then
        local orientation = layout["main"]["orientation"]
        local anchor = layout["main"]["anchor"]
        local spacingX = layout["main"]["spacingX"]
        local spacingY = layout["main"]["spacingY"]
        local petSpacingX = layout["pet"]["sameArrangementAsMain"] and spacingX or layout["pet"]["spacingX"]
        local petSpacingY = layout["pet"]["sameArrangementAsMain"] and spacingY or layout["pet"]["spacingY"]

        local point, playerAnchorPoint, petAnchorPoint, playerSpacing, petSpacing, headerPoint
        if orientation == "vertical" then
            if anchor == "BOTTOMLEFT" then
                point, playerAnchorPoint, petAnchorPoint = "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT"
                headerPoint = "BOTTOM"
                playerSpacing = spacingY
                petSpacing = petSpacingX
            elseif anchor == "BOTTOMRIGHT" then
                point, playerAnchorPoint, petAnchorPoint = "BOTTOMRIGHT", "TOPRIGHT", "BOTTOMLEFT"
                headerPoint = "BOTTOM"
                playerSpacing = spacingY
                petSpacing = -petSpacingX
            elseif anchor == "TOPLEFT" then
                point, playerAnchorPoint, petAnchorPoint = "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT"
                headerPoint = "TOP"
                playerSpacing = -spacingY
                petSpacing = petSpacingX
            elseif anchor == "TOPRIGHT" then
                point, playerAnchorPoint, petAnchorPoint = "TOPRIGHT", "BOTTOMRIGHT", "TOPLEFT"
                headerPoint = "TOP"
                playerSpacing = -spacingY
                petSpacing = -petSpacingX
            end

            header:SetAttribute("xOffset", 0)
            header:SetAttribute("yOffset", P.Scale(playerSpacing))
        else
            -- anchor
            if anchor == "BOTTOMLEFT" then
                point, playerAnchorPoint, petAnchorPoint = "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT"
                headerPoint = "LEFT"
                playerSpacing = spacingX
                petSpacing = petSpacingY
            elseif anchor == "BOTTOMRIGHT" then
                point, playerAnchorPoint, petAnchorPoint = "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT"
                headerPoint = "RIGHT"
                playerSpacing = -spacingX
                petSpacing = petSpacingY
            elseif anchor == "TOPLEFT" then
                point, playerAnchorPoint, petAnchorPoint = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT"
                headerPoint = "LEFT"
                playerSpacing = spacingX
                petSpacing = -petSpacingY
            elseif anchor == "TOPRIGHT" then
                point, playerAnchorPoint, petAnchorPoint = "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT"
                headerPoint = "RIGHT"
                playerSpacing = -spacingX
                petSpacing = -petSpacingY
            end

            header:SetAttribute("xOffset", P.Scale(playerSpacing))
            header:SetAttribute("yOffset", 0)
        end

        header:ClearAllPoints()
        header:SetPoint(point)
        header:SetAttribute("point", headerPoint)

        --! force update unitbutton's point
        local petSide = layout["pet"]["petSide"] or "right"
        local v = anchor:find("^BOTTOM") and "BOTTOM" or "TOP"
        local h = anchor:find("LEFT$") and "LEFT" or "RIGHT"
        for j = 1, 5 do
            header[j]:ClearAllPoints()
            -- update petButton's point
            F.BD(header[j]).petButton:ClearAllPoints()
            if orientation == "vertical" then
                -- Pet on LEFT or RIGHT side of owner
                if petSide == "right" then
                    F.BD(header[j]).petButton:SetPoint(v.."LEFT", header[j], v.."RIGHT", P.Scale(petSpacingX), 0)
                else
                    F.BD(header[j]).petButton:SetPoint(v.."RIGHT", header[j], v.."LEFT", P.Scale(-petSpacingX), 0)
                end
            else
                -- Pet on TOP or BOTTOM of owner
                if petSide == "bottom" then
                    F.BD(header[j]).petButton:SetPoint("TOP"..h, header[j], "BOTTOM"..h, 0, P.Scale(-petSpacingY))
                else
                    F.BD(header[j]).petButton:SetPoint("BOTTOM"..h, header[j], "TOP"..h, 0, P.Scale(petSpacingY))
                end
            end
        end
        header:SetAttribute("unitsPerColumn", 5)
    end

    if not which or strfind(which, "size$") or strfind(which, "power$") or which == "barOrientation" or which == "powerFilter" then
        for i, playerButton in ipairs(header) do
            local petButton = F.BD(playerButton).petButton

            if not which or strfind(which, "size$") then
                local width, height = unpack(layout["main"]["size"])
                P.Size(playerButton, width, height)
                header:SetAttribute("buttonWidth", P.Scale(width))
                header:SetAttribute("buttonHeight", P.Scale(height))
                if layout["pet"]["sameSizeAsMain"] then
                    P.Size(petButton, width, height)
                else
                    P.Size(petButton, layout["pet"]["size"][1], layout["pet"]["size"][2])
                end
            end

            -- NOTE: SetOrientation BEFORE SetPowerSize
            if not which or which == "barOrientation" then
                B.SetOrientation(playerButton, layout["barOrientation"][1], layout["barOrientation"][2])
                B.SetOrientation(petButton, layout["barOrientation"][1], layout["barOrientation"][2])
            end

            if not which or strfind(which, "power$") or which == "barOrientation" or which == "powerFilter" then
                B.SetPowerSize(playerButton, layout["main"]["powerSize"])
                if layout["pet"]["sameSizeAsMain"] then
                    B.SetPowerSize(petButton, layout["main"]["powerSize"])
                else
                    B.SetPowerSize(petButton, layout["pet"]["powerSize"])
                end
            end
        end
    end

    if not which or which == "pet" then
        header:SetAttribute("showPartyPets", layout["pet"]["partyEnabled"])
        header:SetAttribute("partyDetached", layout["pet"]["partyDetached"])
        if layout["pet"]["partyEnabled"] and not layout["pet"]["partyDetached"] then
            for i, playerButton in ipairs(header) do
                RegisterUnitWatch(F.BD(playerButton).petButton)
            end
        else
            for i, playerButton in ipairs(header) do
                UnregisterUnitWatch(F.BD(playerButton).petButton)
                F.BD(playerButton).petButton:Hide()
            end
        end
    end

    if not which or which == "sort" then
        if layout["main"]["sortByRole"] then
            header:SetAttribute("sortMethod", "NAME")
            local order = table.concat(layout["main"]["roleOrder"], ",")..",NONE"
            header:SetAttribute("groupingOrder", order)
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
        else
            header:SetAttribute("sortMethod", "INDEX")
            header:SetAttribute("groupingOrder", "")
            header:SetAttribute("groupBy", nil)
        end
    end

    if not which or which == "hideSelf" then
        header:SetAttribute("showPlayer", not layout["main"]["hideSelf"])
    end
end
Cell.RegisterCallback("UpdateLayout", "PartyFrame_UpdateLayout", PartyFrame_UpdateLayout)

-- local function PartyFrame_UpdateVisibility(which)
--     if not which or which == "party" then
--         header:SetAttribute("showParty", CellDB["general"]["showParty"])
--         if CellDB["general"]["showParty"] then
--             --! [group] won't fire during combat
--             -- RegisterAttributeDriver(partyFrame, "state-visibility", "[group:raid] hide; [group:party] show; hide")
--             -- NOTE: [group:party] show: fix for premade, only player in party, but party1 not exists
--             RegisterAttributeDriver(partyFrame, "state-visibility", "[@raid1,exists] hide;[@party1,exists] show;[group:party] show;hide")
--         else
--             UnregisterAttributeDriver(partyFrame, "state-visibility")
--             partyFrame:Hide()
--         end
--     end
-- end
-- Cell.RegisterCallback("UpdateVisibility", "PartyFrame_UpdateVisibility", PartyFrame_UpdateVisibility)

-- local f = CreateFrame("Frame", nil, CellParent, "SecureFrameTemplate")
-- RegisterAttributeDriver(f, "state-group", "[@raid1,exists] raid;[@party1,exists] party; solo")
-- SecureHandlerWrapScript(f, "OnAttributeChanged", f, [[
--     print(name, value)
--     if name ~= "state-group" then return end
-- ]])

-- RegisterStateDriver(f, "groupstate", "[group:raid] raid; [group:party] party; solo")
-- f:SetAttribute("_onstate-groupstate", [[
--     print(stateid, newstate)
-- ]])
