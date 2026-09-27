local _, Cell = ...
if not Cell.isMidnight then return end

local F = Cell.funcs

local max = max
local tinsert = tinsert
local strfind = strfind
local time = time

local mtPane
local restrictionText
local queueText
local versionsText
local showQueueIndicatorCB
local refreshTicker
local queueIndicator

local function EnsureMidnightToolsDB()
    if type(CellDB) ~= "table" then
        return false
    end

    CellDB["midnightTools"] = CellDB["midnightTools"] or {}
    if CellDB["midnightTools"]["showQueueIndicator"] == nil then
        CellDB["midnightTools"]["showQueueIndicator"] = true
    end

    return true
end

local function Colorize(text, color)
    return color .. tostring(text) .. "|r"
end

local function StatusText(flag, activeText, clearText)
    if flag then
        return Colorize(activeText or "active", "|cFFFF3030")
    end

    return Colorize(clearText or "clear", "|cFF80FF00")
end

local function SoftText(text)
    return Colorize(text, "|cFFB2B2B2")
end

local function AgeText(timestamp)
    if not timestamp or timestamp <= 0 then
        return SoftText("never")
    end

    return F.SecondsToTime(max(0, time() - timestamp)) .. " ago"
end

local function AgeTextPlain(timestamp)
    if not timestamp or timestamp <= 0 then
        return "never"
    end

    return F.SecondsToTime(max(0, time() - timestamp)) .. " ago"
end

local function NormalizeFullName(name)
    if not name or name == "" then return name end
    if not strfind(name, "-") then
        name = name .. "-" .. GetNormalizedRealmName()
    end
    return name
end

local function GetCurrentGroupMembers()
    local members = {}
    local sorted = {}

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            name = NormalizeFullName(name)
            if name and not members[name] then
                members[name] = true
                tinsert(sorted, name)
            end
        end
    elseif IsInGroup() then
        local selfName = Cell.vars.playerNameFull or F.UnitFullName("player")
        if selfName then
            members[selfName] = true
            tinsert(sorted, selfName)
        end

        for i = 1, GetNumGroupMembers() - 1 do
            local name = F.UnitFullName("party" .. i)
            if name and not members[name] then
                members[name] = true
                tinsert(sorted, name)
            end
        end
    else
        local selfName = Cell.vars.playerNameFull or F.UnitFullName("player")
        if selfName then
            members[selfName] = true
            tinsert(sorted, selfName)
        end
    end

    table.sort(sorted)
    return members, sorted
end

local function GetSortedPrefixCounts(prefixCounts)
    local sorted = {}

    for prefix, count in pairs(prefixCounts or {}) do
        tinsert(sorted, {
            prefix = prefix,
            count = count,
        })
    end

    table.sort(sorted, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end

        return a.prefix < b.prefix
    end)

    return sorted
end

local function GetRelevantVersionEntries(snapshot, members)
    local entries = {}

    for name, info in pairs(snapshot.entries or {}) do
        if members[name] then
            tinsert(entries, {
                name = name,
                info = info,
            })
        end
    end

    table.sort(entries, function(a, b)
        if a.info.versionNum ~= b.info.versionNum then
            return a.info.versionNum > b.info.versionNum
        end

        return a.name < b.name
    end)

    return entries
end

local function GetMissingVersionNames(snapshot, sortedMembers)
    local missing = {}

    for _, name in ipairs(sortedMembers) do
        if not snapshot.entries[name] then
            tinsert(missing, F.ToShortName(name))
        end
    end

    return missing
end

local function BuildRestrictionText()
    local lines = {
        "Aura restrictions: " .. StatusText(F.IsAuraRestricted()),
        "Cooldown restrictions: " .. StatusText(F.IsCooldownRestricted()),
        "Comm restrictions: " .. StatusText(F.IsCommRestricted()),
        "Secret context: " .. StatusText(F.IsSecretContextActive()),
        "Group channel: " .. SoftText(F.GetGroupCommChannel() or "none"),
    }

    return table.concat(lines, "\n")
end

local function BuildQueueText(snapshot)
    local lines = {
        "Pending messages: " .. SoftText(snapshot.size),
        "Flush state: " .. StatusText(F.IsCommRestricted(), "waiting", "ready"),
        "Last queued: " .. AgeText(snapshot.lastQueuedAt),
        "Last flush: " .. AgeText(snapshot.lastFlushAt),
    }

    local prefixCounts = GetSortedPrefixCounts(snapshot.prefixCounts)
    if #prefixCounts == 0 then
        tinsert(lines, "Prefixes: " .. SoftText("queue is empty"))
    else
        tinsert(lines, "Prefixes:")
        for _, info in ipairs(prefixCounts) do
            tinsert(lines, ("  %s x%d"):format(info.prefix, info.count))
        end
    end

    return table.concat(lines, "\n")
end

local function BuildVersionsText(snapshot)
    local members, sortedMembers = GetCurrentGroupMembers()
    local entries = GetRelevantVersionEntries(snapshot, members)
    local missing = GetMissingVersionNames(snapshot, sortedMembers)
    local lines = {}
    local newer, older = {}, {}

    tinsert(lines, "Your version: " .. SoftText(Cell.version or "?"))
    tinsert(lines, "Last request: " .. AgeText(snapshot.lastVersionRequestAt))
    tinsert(lines, "Last broadcast: " .. AgeText(snapshot.lastVersionBroadcastAt))
    tinsert(lines, "Responders: " .. SoftText(("%d/%d"):format(#entries, #sortedMembers)))

    if #missing > 0 then
        tinsert(lines, "Missing data: " .. SoftText(table.concat(missing, ", ")))
    else
        tinsert(lines, "Missing data: " .. SoftText("none"))
    end

    if #entries == 0 then
        tinsert(lines, "")
        tinsert(lines, SoftText("No sync data received yet. Click Refresh Versions to query the group."))
        return table.concat(lines, "\n")
    end

    tinsert(lines, "")
    for _, entry in ipairs(entries) do
        local status
        if entry.info.versionNum > Cell.versionNum then
            status = Colorize("newer", "|cFFFF3030")
            tinsert(newer, F.ToShortName(entry.name))
        elseif entry.info.versionNum < Cell.versionNum then
            status = Colorize("older", "|cFFFFD100")
            tinsert(older, F.ToShortName(entry.name))
        else
            status = Colorize("ok", "|cFF80FF00")
        end

        tinsert(lines, ("%s  %s  %s  %s"):format(
            status,
            F.ToShortName(entry.name),
            entry.info.version or "?",
            SoftText((entry.info.channel or "?") .. " / " .. AgeTextPlain(entry.info.receivedAt))
        ))
    end

    if #newer > 0 then
        tinsert(lines, "")
        tinsert(lines, "Newer than you: " .. SoftText(table.concat(newer, ", ")))
    end

    if #older > 0 then
        tinsert(lines, "Older than you: " .. SoftText(table.concat(older, ", ")))
    end

    return table.concat(lines, "\n")
end

local function RefreshVersionsHeight()
    if not (mtPane and mtPane.scrollFrame and versionsText) then return end

    C_Timer.After(0, function()
        if not mtPane or not mtPane.scrollFrame or not versionsText then return end
        mtPane.scrollFrame.content:SetHeight(max(versionsText:GetStringHeight() + 12, mtPane.scrollFrame:GetHeight()))
    end)
end

local function UpdateQueueIndicator()
    if not queueIndicator then return end

    if not EnsureMidnightToolsDB() then
        queueIndicator:Hide()
        return
    end

    local snapshot = F.GetCommQueueSnapshot()
    if not CellDB["midnightTools"]["showQueueIndicator"] or snapshot.size == 0 then
        queueIndicator:Hide()
        return
    end

    queueIndicator:SetText(snapshot.size > 99 and "99+" or tostring(snapshot.size))

    if F.IsCommRestricted() then
        queueIndicator.color = {0.55, 0.1, 0.1, 0.9}
        queueIndicator.hoverColor = {0.75, 0.15, 0.15, 1}
    else
        queueIndicator.color = {0.55, 0.45, 0.05, 0.9}
        queueIndicator.hoverColor = {0.75, 0.62, 0.08, 1}
    end

    queueIndicator:SetBackdropColor(unpack(queueIndicator.color))
    queueIndicator:Show()
end

local function UpdateMidnightTools()
    if restrictionText then
        restrictionText:SetText(BuildRestrictionText())
    end

    local queueSnapshot = F.GetCommQueueSnapshot()
    if queueText then
        queueText:SetText(BuildQueueText(queueSnapshot))
    end

    local versionSnapshot = F.GetVersionDiagnosticsSnapshot()
    if versionsText then
        versionsText:SetText(BuildVersionsText(versionSnapshot))
        RefreshVersionsHeight()
    end

    UpdateQueueIndicator()
end

local function StartRefreshTicker()
    if refreshTicker then return end

    refreshTicker = C_Timer.NewTicker(1, function()
        UpdateMidnightTools()
    end)
end

local function StopRefreshTicker()
    if refreshTicker then
        refreshTicker:Cancel()
        refreshTicker = nil
    end
end

function F.ShowMidnightTools()
    F.ShowUtilitiesTab()
    F.ShowMidnightToolsTab()
end

function F.PrintMidnightDiagnostics()
    local queueSnapshot = F.GetCommQueueSnapshot()
    local versionSnapshot = F.GetVersionDiagnosticsSnapshot()
    local members, sortedMembers = GetCurrentGroupMembers()
    local entries = GetRelevantVersionEntries(versionSnapshot, members)
    local missing = GetMissingVersionNames(versionSnapshot, sortedMembers)
    local prefixCounts = GetSortedPrefixCounts(queueSnapshot.prefixCounts)
    local prefixSummary = {}

    for _, info in ipairs(prefixCounts) do
        tinsert(prefixSummary, ("%s x%d"):format(info.prefix, info.count))
    end

    F.Print(("Midnight restrictions: aura=%s, cooldown=%s, comm=%s, secret=%s, channel=%s."):format(
        F.IsAuraRestricted() and "active" or "clear",
        F.IsCooldownRestricted() and "active" or "clear",
        F.IsCommRestricted() and "active" or "clear",
        F.IsSecretContextActive() and "active" or "clear",
        F.GetGroupCommChannel() or "none"
    ))
    F.Print(("Midnight queue: %d pending, last queued %s, last flush %s."):format(
        queueSnapshot.size,
        AgeTextPlain(queueSnapshot.lastQueuedAt),
        AgeTextPlain(queueSnapshot.lastFlushAt)
    ))

    if #prefixSummary > 0 then
        F.Print("Queued prefixes: " .. table.concat(prefixSummary, ", "))
    end

    F.Print(("Midnight versions: %d/%d responders, last request %s, last broadcast %s."):format(
        #entries,
        #sortedMembers,
        AgeTextPlain(versionSnapshot.lastVersionRequestAt),
        AgeTextPlain(versionSnapshot.lastVersionBroadcastAt)
    ))

    if #missing > 0 then
        F.Print("Missing version data: " .. table.concat(missing, ", "))
    end
end

function F.ShowMidnightTestCVars()
    F.ShowMidnightTools()

    local popup = Cell.CreateNotificationPopup(Cell.frames.utilitiesTab, 360,
        "Midnight restriction test CVars:\n\n" ..
        "/run SetCVar(\"secretCombatRestrictionsForced\", 1)\n" ..
        "/run SetCVar(\"secretEncounterRestrictionsForced\", 1)\n" ..
        "/run SetCVar(\"secretChallengeModeRestrictionsForced\", 1)\n" ..
        "/run SetCVar(\"secretPvPMatchRestrictionsForced\", 1)\n\n" ..
        "Reset again with the same command using 0 instead of 1.",
        true
    )
    popup:ClearAllPoints()
    popup:SetPoint("CENTER", mtPane or Cell.frames.utilitiesTab, "CENTER", 0, -10)
    popup:Show()
end

local function MaybeAutoRefreshVersions()
    if not F.GetGroupCommChannel() then return end

    local snapshot = F.GetVersionDiagnosticsSnapshot()
    if not snapshot.lastVersionRequestAt or time() - snapshot.lastVersionRequestAt >= 30 then
        F.RequestVersionDiagnostics()
    end
end

local function CreateTextBlock(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetSpacing(3)
    fs:SetWordWrap(true)
    fs:SetPoint("TOPLEFT", 0, -24)
    fs:SetPoint("TOPRIGHT", 0, -24)
    return fs
end

local function CreateQueueIndicator()
    if queueIndicator then return end

    queueIndicator = Cell.CreateButton(Cell.frames.mainFrame, "", "accent", {28, 16}, false, false, "CELL_FONT_WIDGET_SMALL", "CELL_FONT_WIDGET_SMALL")
    queueIndicator:SetPoint("TOPLEFT", Cell.frames.menuFrame, "BOTTOMLEFT", 0, -3)
    queueIndicator:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    queueIndicator:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if F.FlushCommQueue() then
                F.Print("Midnight comm queue flushed.")
            else
                F.Print("Midnight comm queue is still blocked by restrictions.")
            end
            UpdateMidnightTools()
        else
            F.ShowMidnightTools()
        end
    end)
    queueIndicator:HookScript("OnEnter", function(self)
        local snapshot = F.GetCommQueueSnapshot()
        local prefixCounts = GetSortedPrefixCounts(snapshot.prefixCounts)

        CellTooltip:SetOwner(self, "ANCHOR_NONE")
        CellTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 3)
        CellTooltip:AddLine("Midnight Sync Queue")
        CellTooltip:AddLine(("Pending messages: %d"):format(snapshot.size))
        CellTooltip:AddLine("Comm restrictions: " .. (F.IsCommRestricted() and "active" or "clear"))
        CellTooltip:AddLine("Last queued: " .. AgeTextPlain(snapshot.lastQueuedAt))
        CellTooltip:AddLine("Last flush: " .. AgeTextPlain(snapshot.lastFlushAt))

        for _, info in ipairs(prefixCounts) do
            CellTooltip:AddLine(("%s x%d"):format(info.prefix, info.count), 0.7, 0.7, 0.7)
        end

        CellTooltip:AddLine("Left-Click: open Midnight Tools", 1, 0.71, 0.77)
        CellTooltip:AddLine("Right-Click: flush queue", 1, 0.71, 0.77)
        CellTooltip:Show()
    end)
    queueIndicator:HookScript("OnLeave", function()
        CellTooltip:Hide()
    end)
    queueIndicator:Hide()
end

local function CreateMidnightToolsPane()
    EnsureMidnightToolsDB()

    mtPane = Cell.CreateTitledPane(Cell.frames.utilitiesTab, "Midnight Tools", 422, 520)
    mtPane:SetPoint("TOPLEFT")

    local restrictionPane = Cell.CreateTitledPane(mtPane, "Restrictions", 198, 112)
    restrictionPane:SetPoint("TOPLEFT", 5, -25)
    restrictionText = CreateTextBlock(restrictionPane)

    local queuePane = Cell.CreateTitledPane(mtPane, "Queued Sync", 204, 112)
    queuePane:SetPoint("TOPLEFT", restrictionPane, "TOPRIGHT", 10, 0)
    queueText = CreateTextBlock(queuePane)

    local actionsPane = Cell.CreateTitledPane(mtPane, "Actions", 412, 74)
    actionsPane:SetPoint("TOPLEFT", restrictionPane, "BOTTOMLEFT", 0, -10)

    local refreshBtn = Cell.CreateButton(actionsPane, "Refresh Versions", "accent", {97, 20})
    refreshBtn:SetPoint("TOPLEFT", 0, -24)
    refreshBtn:SetScript("OnClick", function()
        if F.RequestVersionDiagnostics() then
            F.Print("Midnight sync diagnostics refresh requested.")
        else
            F.Print("No group channel is available for Midnight sync diagnostics.")
        end
        UpdateMidnightTools()
    end)

    local flushBtn = Cell.CreateButton(actionsPane, "Flush Queue", "accent", {97, 20})
    flushBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 6, 0)
    flushBtn:SetScript("OnClick", function()
        if F.FlushCommQueue() then
            F.Print("Midnight comm queue flushed.")
        else
            F.Print("Midnight comm queue is still blocked by restrictions.")
        end
        UpdateMidnightTools()
    end)

    local printBtn = Cell.CreateButton(actionsPane, "Print Status", "accent", {97, 20})
    printBtn:SetPoint("LEFT", flushBtn, "RIGHT", 6, 0)
    printBtn:SetScript("OnClick", function()
        F.PrintMidnightDiagnostics()
    end)

    local cvarsBtn = Cell.CreateButton(actionsPane, "Test CVars", "accent", {97, 20})
    cvarsBtn:SetPoint("LEFT", printBtn, "RIGHT", 6, 0)
    cvarsBtn:SetScript("OnClick", function()
        F.ShowMidnightTestCVars()
    end)

    showQueueIndicatorCB = Cell.CreateCheckButton(actionsPane, "Show queue indicator", function(checked)
        CellDB["midnightTools"]["showQueueIndicator"] = checked
        UpdateQueueIndicator()
    end, "Show a small queue badge near the Cell menu while sync messages are delayed.")
    showQueueIndicatorCB:SetPoint("BOTTOMLEFT", 0, 0)

    local versionsPane = Cell.CreateTitledPane(mtPane, "Group Sync Diagnostics", 412, 289)
    versionsPane:SetPoint("TOPLEFT", actionsPane, "BOTTOMLEFT", 0, -10)
    Cell.CreateScrollFrame(versionsPane, -24, 0, {0, 0, 0, 0.2}, {0, 0, 0, 1})
    mtPane.scrollFrame = versionsPane.scrollFrame

    versionsText = versionsPane.scrollFrame.content:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    versionsText:SetJustifyH("LEFT")
    versionsText:SetJustifyV("TOP")
    versionsText:SetSpacing(3)
    versionsText:SetWordWrap(true)
    versionsText:SetPoint("TOPLEFT", 6, -6)
    versionsText:SetPoint("TOPRIGHT", -6, -6)

    mtPane:SetScript("OnShow", function()
        showQueueIndicatorCB:SetChecked(CellDB["midnightTools"]["showQueueIndicator"])
        StartRefreshTicker()
        MaybeAutoRefreshVersions()
        UpdateMidnightTools()
    end)

    mtPane:SetScript("OnHide", function()
        StopRefreshTicker()
    end)

    UpdateMidnightTools()
end

local init
local function ShowUtilitySettings(which)
    if which == "midnightTools" then
        if not init then
            init = true
            CreateMidnightToolsPane()
        end

        showQueueIndicatorCB:SetChecked(CellDB["midnightTools"]["showQueueIndicator"])
        mtPane:Show()
        UpdateMidnightTools()
    elseif init then
        mtPane:Hide()
    end
end
Cell.RegisterCallback("ShowUtilitySettings", "MidnightTools_ShowUtilitySettings", ShowUtilitySettings)

Cell.RegisterCallback("MidnightDiagnosticsUpdated", "MidnightTools_UpdateDisplay", function()
    UpdateMidnightTools()
end)

CreateQueueIndicator()
UpdateQueueIndicator()

Cell.RegisterCallback("AddonLoaded", "MidnightTools_Init", function()
    EnsureMidnightToolsDB()
    UpdateQueueIndicator()
end)
