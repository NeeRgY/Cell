local _, Cell = ...
local F = Cell.funcs
local B = Cell.bFuncs
local P = Cell.pixelPerfectFuncs

local soloFrame = CreateFrame("Frame", "CellSoloFrame", Cell.frames.mainFrame, "SecureFrameTemplate")
Cell.frames.soloFrame = soloFrame
soloFrame:SetAllPoints(Cell.frames.mainFrame)

local playerButton = CreateFrame("Button", soloFrame:GetName().."Player", soloFrame, "CellUnitButtonTemplate")
-- playerButton.type = "main" -- layout setup
playerButton:SetAttribute("unit", "player")
playerButton:SetPoint("TOPLEFT")
playerButton:Show()
Cell.unitButtons.solo["player"] = playerButton

local petButton = CreateFrame("Button", soloFrame:GetName().."Pet", soloFrame, "CellUnitButtonTemplate")
-- petButton.type = "pet" -- layout setup
petButton:SetAttribute("unit", "pet")
Cell.unitButtons.solo["pet"] = petButton

local function SoloFrame_UpdateLayout(layout, which)
    -- visibility
    if Cell.isRetail then
        if Cell.vars.groupType ~= "solo" or Cell.vars.isHidden then
            UnregisterAttributeDriver(soloFrame, "state-visibility")
            soloFrame:Hide()
            return
        else
            RegisterAttributeDriver(soloFrame, "state-visibility", "[@raid1,exists] hide;[@party1,exists] hide;[group] hide;show")
        end
    else
        -- Classic-only: the driver reacts natively to the real group state, so it stays registered
        -- whatever the currently active group type is - combat can never leave it stuck unregistered
        -- (see F.IsGroupTypeHidden). Keeps Retail on the exact old register/unregister behavior above.
        if F.IsGroupTypeHidden(Cell.vars.soloLayoutGroupType) then
            -- Configured to hide: register an unconditional "hide" instead of unregistering, so that a
            -- group change happening in combat still resolves to hidden rather than to whatever the
            -- driver last said.
            RegisterAttributeDriver(soloFrame, "state-visibility", "hide")
            soloFrame:Hide()
            return
        else
            RegisterAttributeDriver(soloFrame, "state-visibility", "[@raid1,exists] hide;[@party1,exists] hide;[group] hide;show")
        end

        -- Layout: applied for every frame group, not only the active one, so that the first show of a group
        -- type since login can happen in combat. F.UpdateLayout defers itself until combat ends, so a solo frame
        -- that had never been active came up with no sizes, anchors or header attributes when the group changed
        -- in combat, and stayed blank until combat ended. See F.GetGroupTypeLayout.
        if Cell.vars.groupType ~= "solo" then
            local ownLayout = F.GetGroupTypeLayout(Cell.vars.soloLayoutGroupType)
            if not ownLayout then return end
            if which then
                -- partial update from the Layouts tab: only relevant when the edited layout is the one used here
                if layout ~= ownLayout then return end
            else
                layout = ownLayout
            end
        end
    end

    -- update
    layout = CellDB["layouts"][layout]

    if not which or strfind(which, "size$") then
        local width, height = unpack(layout["main"]["size"])
        P.Size(playerButton, width, height)
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

    if not which or which == "main-arrangement" or which == "pet-arrangement" then
        petButton:ClearAllPoints()
        local petSide = layout["pet"]["petSide"] or "right"
        local petSpacingX = layout["pet"]["sameArrangementAsMain"] and layout["main"]["spacingX"] or layout["pet"]["spacingX"]
        local petSpacingY = layout["pet"]["sameArrangementAsMain"] and layout["main"]["spacingY"] or layout["pet"]["spacingY"]
        local anchor = layout["main"]["anchor"]
        local v = anchor:find("^BOTTOM") and "BOTTOM" or "TOP"
        local h = anchor:find("LEFT$") and "LEFT" or "RIGHT"

        if layout["main"]["orientation"] == "vertical" then
            -- Pet on LEFT or RIGHT side of owner
            if petSide == "right" then
                petButton:SetPoint(v.."LEFT", playerButton, v.."RIGHT", P.Scale(petSpacingX), 0)
            else
                petButton:SetPoint(v.."RIGHT", playerButton, v.."LEFT", P.Scale(-petSpacingX), 0)
            end
        else
            -- Pet on TOP or BOTTOM of owner
            if petSide == "bottom" then
                petButton:SetPoint("TOP"..h, playerButton, "BOTTOM"..h, 0, P.Scale(-petSpacingY))
            else
                petButton:SetPoint("BOTTOM"..h, playerButton, "TOP"..h, 0, P.Scale(petSpacingY))
            end
        end
    end

    if not which or which == "pet" then
        if layout["pet"]["soloEnabled"] then
            RegisterAttributeDriver(petButton, "state-visibility", "[nopet] hide; [vehicleui] hide; show")
        else
            UnregisterAttributeDriver(petButton, "state-visibility")
            petButton:Hide()
        end
    end
end
Cell.RegisterCallback("UpdateLayout", "SoloFrame_UpdateLayout", SoloFrame_UpdateLayout)

-- local function SoloFrame_UpdateVisibility(which)
--     F.Debug("|cffff7fffUpdateVisibility:|r "..(which or "all"))

--     if not which or which == "solo" then
--         if CellDB["general"]["showSolo"] then
--             RegisterAttributeDriver(soloFrame, "state-visibility", "[@raid1,exists] hide;[@party1,exists] hide;[group] hide;show")
--         else
--             UnregisterAttributeDriver(soloFrame, "state-visibility")
--             soloFrame:Hide()
--         end
--     end
-- end
-- Cell.RegisterCallback("UpdateVisibility", "SoloFrame_UpdateVisibility", SoloFrame_UpdateVisibility)