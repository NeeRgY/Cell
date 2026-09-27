local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

local backupFrame
local notificationFrame
local buttons = {}
local notificationButtons = {}
local LoadBackups
local LoadNotifications
local DATE_FORMAT = "%Y-%m-%d %H:%M:%S"
local DEFAULT_MAX_AUTO_BACKUPS = 12
local DEFAULT_MAX_NOTIFICATIONS = 40
local AUTO_BACKUP_RECENCY = 120

local function EnsureSupportTables()
    if type(CellDB) ~= "table" then
        return
    end

    if type(CellDBBackup) ~= "table" then
        CellDBBackup = {}
    end

    if type(CellDB["systemTools"]) ~= "table" then
        CellDB["systemTools"] = {}
    end
    if CellDB["systemTools"]["autoBackupsEnabled"] == nil then
        CellDB["systemTools"]["autoBackupsEnabled"] = true
    end
    if CellDB["systemTools"]["maxAutoBackups"] == nil then
        CellDB["systemTools"]["maxAutoBackups"] = DEFAULT_MAX_AUTO_BACKUPS
    end
    if CellDB["systemTools"]["maxNotifications"] == nil then
        CellDB["systemTools"]["maxNotifications"] = DEFAULT_MAX_NOTIFICATIONS
    end

    if type(CellDB["addonNotifications"]) ~= "table" then
        CellDB["addonNotifications"] = {}
    end

    return CellDB["systemTools"], CellDB["addonNotifications"]
end

local function TrimAutoBackups()
    local settings = EnsureSupportTables()
    if not settings then return end

    local autoIndices = {}
    for i, backup in ipairs(CellDBBackup) do
        if backup["automatic"] then
            tinsert(autoIndices, i)
        end
    end

    local overflow = #autoIndices - (settings["maxAutoBackups"] or DEFAULT_MAX_AUTO_BACKUPS)
    if overflow <= 0 then return end

    for removed = 1, overflow do
        tremove(CellDBBackup, autoIndices[removed] - (removed - 1))
    end
end

local function GetBackupDisplayText(backup)
    local prefix = backup["automatic"] and "|cFFB2B2B2[AUTO]|r " or "|cFF80FF00[MANUAL]|r "
    if backup["tag"] and backup["tag"] ~= "" then
        prefix = prefix .. "|cFF00CCFF[" .. backup["tag"] .. "]|r "
    end

    return prefix .. backup["desc"]
end

local function GetBackupCreatedText(backup)
    if backup["createdAt"] then
        return date("%m-%d %H:%M", backup["createdAt"])
    end

    return ""
end

local function GetNotificationColor(kind)
    if kind == "import" then
        return 0.5, 1, 0
    elseif kind == "backup" then
        return 0, 0.8, 1
    elseif kind == "warning" then
        return 1, 0.3, 0.3
    end

    return 1, 1, 1
end

function F.AddAddonNotification(kind, title, message)
    local settings, notifications = EnsureSupportTables()
    if not settings or not notifications then return end

    tinsert(notifications, {
        ["kind"] = kind or "info",
        ["title"] = title or "Notification",
        ["message"] = message or "",
        ["createdAt"] = time(),
    })

    while #notifications > (settings["maxNotifications"] or DEFAULT_MAX_NOTIFICATIONS) do
        tremove(notifications, 1)
    end

    Cell.Fire("AddonNotificationsUpdated")
end

function F.GetAddonNotifications()
    local _, notifications = EnsureSupportTables()
    return notifications or {}
end

function F.ClearAddonNotifications()
    local _, notifications = EnsureSupportTables()
    if not notifications then return end

    wipe(notifications)
    Cell.Fire("AddonNotificationsUpdated")
end

function F.CreateBackupSnapshot(desc, options)
    EnsureSupportTables()

    options = options or {}
    desc = strtrim(desc or "")
    if desc == "" then
        desc = date(DATE_FORMAT)
    end

    local backup = {
        ["desc"] = desc,
        ["version"] = Cell.version,
        ["versionNum"] = Cell.versionNum,
        ["DB"] = F.Copy(CellDB),
        ["CharacterDB"] = CellCharacterDB and F.Copy(CellCharacterDB),
        ["automatic"] = options["automatic"] and true or nil,
        ["tag"] = options["tag"],
        ["type"] = options["type"],
        ["createdAt"] = time(),
        ["signature"] = options["signature"],
    }

    tinsert(CellDBBackup, backup)
    TrimAutoBackups()
    Cell.Fire("BackupsUpdated")

    return backup
end

function F.CreateAutoBackup(desc, options)
    local settings = EnsureSupportTables()
    if not settings or not settings["autoBackupsEnabled"] then
        return nil, "disabled"
    end

    options = options or {}
    local signature = options["signature"] or desc

    for i = #CellDBBackup, 1, -1 do
        local backup = CellDBBackup[i]
        if backup["automatic"] and backup["signature"] == signature and backup["createdAt"] and time() - backup["createdAt"] <= AUTO_BACKUP_RECENCY then
            return backup, "reused"
        end
    end

    options["automatic"] = true
    options["signature"] = signature
    return F.CreateBackupSnapshot(desc, options), "created"
end

function F.GetBackupNotificationText(backup, status)
    if backup then
        if status == "reused" then
            return "Backup: " .. backup["desc"] .. " (reused)"
        end

        return "Backup: " .. backup["desc"]
    end

    if status == "disabled" then
        return "Auto backup disabled"
    end
end

---------------------------------------------------------------------
-- create item
---------------------------------------------------------------------
local function CreateItem(index)
    local b = Cell.CreateButton(backupFrame.list.content, nil, "accent-hover", {20, 20})

    b.version = b:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    b.version:SetJustifyH("LEFT")
    b.version:SetPoint("LEFT", 5, 0)

    b.text = b:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.text:SetPoint("LEFT", 100, 0)
    b.text:SetPoint("RIGHT", -45, 0)

    -- restore
    b:SetScript("OnClick", function()
        if b.isInvalid then return end

        backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 20)
        Cell.frames.aboutTab.mask:Show()

        local text = "|cFFFF7070"..L["Restore backup"].."?|r\n"..CellDBBackup[index]["desc"].."\n|cFFB7B7B7"..CellDBBackup[index]["version"]
        local popup = Cell.CreateConfirmPopup(Cell.frames.aboutTab, 200, text, function()
            backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
            CellDB = CellDBBackup[index]["DB"]
            if CellCharacterDB then
                CellCharacterDB = CellDBBackup[index]["CharacterDB"]
            end
            ReloadUI()
        end, function()
            backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
        end)
        popup:SetPoint("TOP", backupFrame, 0, -50)
    end)

    -- delete
    b.del = Cell.CreateButton(b, "", "none", {20, 20}, true, true)
    b.del:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\delete2", {18, 18}, {"CENTER", 0, 0})
    b.del:SetPoint("RIGHT")
    b.del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
    b.del:SetScript("OnEnter", function()
        b:GetScript("OnEnter")(b)
        b.del.tex:SetVertexColor(1, 1, 1, 1)
    end)
    b.del:SetScript("OnLeave",  function()
        b:GetScript("OnLeave")(b)
        b.del.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
    end)
    b.del:SetScript("OnClick", function()
        backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 20)
        Cell.frames.aboutTab.mask:Show()

        local text = "|cFFFF7070"..L["Delete backup"].."?|r\n"..CellDBBackup[index]["desc"]
        local popup = Cell.CreateConfirmPopup(Cell.frames.aboutTab, 200, text, function()
            backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
            local desc = CellDBBackup[index]["desc"]
            tremove(CellDBBackup, index)
            F.AddAddonNotification("backup", "Backup Deleted", desc)
            LoadBackups()
        end, function()
            backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
        end)
        popup:SetPoint("TOP", backupFrame, 0, -50)
    end)

    -- rename
    b.rename = Cell.CreateButton(b, "", "none", {20, 20}, true, true)
    b.rename:SetPoint("RIGHT", b.del, "LEFT", 1, 0)
    b.rename:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\rename", {18, 18}, {"CENTER", 0, 0})
    b.rename.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
    b.rename:SetScript("OnEnter", function()
        b:GetScript("OnEnter")(b)
        b.rename.tex:SetVertexColor(1, 1, 1, 1)
    end)
    b.rename:SetScript("OnLeave",  function()
        b:GetScript("OnLeave")(b)
        b.rename.tex:SetVertexColor(0.6, 0.6, 0.6, 1)
    end)
    b.rename:SetScript("OnClick", function()
        local popup = Cell.CreatePopupEditBox(backupFrame, function(text)
            if strtrim(text) == "" then text = date() end
            CellDBBackup[index]["desc"] = text
            b.text:SetText(text)
        end)
        popup:SetPoint("TOPLEFT", b)
        popup:SetPoint("BOTTOMRIGHT", b)
        popup:ShowEditBox(CellDBBackup[index]["desc"])
    end)

    return b
end

---------------------------------------------------------------------
-- create frame
---------------------------------------------------------------------
local function CreateBackupFrame()
    backupFrame = CreateFrame("Frame", "CellOptionsFrame_Backup", Cell.frames.aboutTab, "BackdropTemplate")
    backupFrame:Hide()
    Cell.StylizeFrame(backupFrame, nil, Cell.GetAccentColorTable())
    backupFrame:EnableMouse(true)
    backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
    P.Size(backupFrame, 430, 185)
    backupFrame:SetPoint("BOTTOMLEFT", P.Scale(1), 27)

    if not Cell.frames.aboutTab.mask then
        Cell.CreateMask(Cell.frames.aboutTab, nil, {1, -1, -1, 1})
        Cell.frames.aboutTab.mask:Hide()
    end

    -- title
    local title = backupFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText(L["Backups"])

    -- tips
    local tips = Cell.CreateScrollTextFrame(backupFrame, "|cffb7b7b7"..L["BACKUP_TIPS"], 0.02, nil, 2)
    tips:SetPoint("TOPRIGHT", -30, -1)
    tips:SetPoint("LEFT", title, "RIGHT", 5, 0)

    -- close
    local closeBtn = Cell.CreateButton(backupFrame, "×", "red", {18, 18}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetPoint("TOPRIGHT", P.Scale(-5), P.Scale(-1))
    closeBtn:SetScript("OnClick", function() backupFrame:Hide() end)

    -- list
    local listFrame = Cell.CreateFrame(nil, backupFrame)
    listFrame:SetPoint("TOPLEFT", 5, -25)
    listFrame:SetPoint("BOTTOMRIGHT", -5, 5)
    listFrame:Show()

    Cell.CreateScrollFrame(listFrame)
    backupFrame.list = listFrame.scrollFrame
    Cell.StylizeFrame(listFrame.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    listFrame.scrollFrame:SetScrollStep(25)

    -- create new
    buttons[0] = Cell.CreateButton(listFrame.scrollFrame.content, " ", "accent-hover", {20, 20})
    buttons[0]:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\create", {18, 18}, {"LEFT", 2, 0})
    buttons[0]:SetScript("OnClick", function(self)
        local popup = Cell.CreatePopupEditBox(backupFrame, function(text)
            if strtrim(text) == "" then text = date(DATE_FORMAT) end
            local backup = F.CreateBackupSnapshot(text, {
                ["tag"] = "Manual",
                ["type"] = "manual",
            })
            F.AddAddonNotification("backup", "Manual Backup Created", backup["desc"])
            LoadBackups()
        end)
        popup:SetPoint("TOPLEFT", self)
        popup:SetPoint("BOTTOMRIGHT", self)
        popup:ShowEditBox(date(DATE_FORMAT))
    end)
    Cell.SetTooltips(buttons[0], "ANCHOR_TOPLEFT", 0, 3, L["Create Backup"], L["BACKUP_TIPS2"])

    -- OnHide
    backupFrame:SetScript("OnHide", function()
        backupFrame:Hide()
        -- hide mask
        Cell.frames.aboutTab.mask:Hide()
    end)

    -- OnShow
    backupFrame:SetScript("OnShow", function()
        -- raise frame level
        backupFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
        Cell.frames.aboutTab.mask:Show()
    end)
end

---------------------------------------------------------------------
-- notifications
---------------------------------------------------------------------
local function CreateNotificationItem(index)
    local b = CreateFrame("Button", nil, notificationFrame.list.content, "BackdropTemplate")
    Cell.StylizeFrame(b, {0.115, 0.115, 0.115, 0.9}, {0, 0, 0, 1})

    b.title = b:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    b.title:SetPoint("TOPLEFT", 5, -5)
    b.title:SetPoint("RIGHT", -80, 0)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)

    b.time = b:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_SMALL")
    b.time:SetPoint("TOPRIGHT", -5, -5)
    b.time:SetJustifyH("RIGHT")

    b.message = b:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_SMALL")
    b.message:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -3)
    b.message:SetPoint("TOPRIGHT", -5, -18)
    b.message:SetJustifyH("LEFT")
    b.message:SetSpacing(2)
    b.message:SetWordWrap(true)

    return b
end

local function CreateNotificationFrame()
    notificationFrame = CreateFrame("Frame", "CellOptionsFrame_Notifications", Cell.frames.aboutTab, "BackdropTemplate")
    notificationFrame:Hide()
    Cell.StylizeFrame(notificationFrame, nil, Cell.GetAccentColorTable())
    notificationFrame:EnableMouse(true)
    notificationFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
    P.Size(notificationFrame, 430, 215)
    notificationFrame:SetPoint("BOTTOMLEFT", P.Scale(1), 27)

    if not Cell.frames.aboutTab.mask then
        Cell.CreateMask(Cell.frames.aboutTab, nil, {1, -1, -1, 1})
        Cell.frames.aboutTab.mask:Hide()
    end

    local title = notificationFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("Notifications")

    local clearBtn = Cell.CreateButton(notificationFrame, "Clear", "accent", {50, 18})
    clearBtn:SetPoint("TOPRIGHT", -28, -1)
    clearBtn:SetScript("OnClick", function()
        F.ClearAddonNotifications()
        LoadNotifications()
    end)

    local closeBtn = Cell.CreateButton(notificationFrame, "×", "red", {18, 18}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetPoint("TOPRIGHT", P.Scale(-5), P.Scale(-1))
    closeBtn:SetScript("OnClick", function()
        notificationFrame:Hide()
    end)

    local listFrame = Cell.CreateFrame(nil, notificationFrame)
    listFrame:SetPoint("TOPLEFT", 5, -25)
    listFrame:SetPoint("BOTTOMRIGHT", -5, 5)
    listFrame:Show()

    Cell.CreateScrollFrame(listFrame)
    notificationFrame.list = listFrame.scrollFrame
    Cell.StylizeFrame(listFrame.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())
    listFrame.scrollFrame:SetScrollStep(44)

    notificationFrame:SetScript("OnHide", function()
        notificationFrame:Hide()
        Cell.frames.aboutTab.mask:Hide()
    end)

    notificationFrame:SetScript("OnShow", function()
        notificationFrame:SetFrameLevel(Cell.frames.aboutTab:GetFrameLevel() + 50)
        Cell.frames.aboutTab.mask:Show()
    end)
end

---------------------------------------------------------------------
-- load
---------------------------------------------------------------------
function LoadBackups()
    backupFrame.list:ResetScroll()

    -- backups
    for i, t in ipairs(CellDBBackup) do
        if not buttons[i] then
            buttons[i] = CreateItem(i)

            if i == 1 then
                buttons[i]:SetPoint("TOPLEFT", 5, -5)
            else
                buttons[i]:SetPoint("TOPLEFT", buttons[i-1], "BOTTOMLEFT", 0, -5)
            end
            buttons[i]:SetPoint("RIGHT", -5, 0)
        end

        if t["versionNum"] < Cell.MIN_VERSION then
            buttons[i].version:SetText("|cffff2222"..L["Invalid"])
            buttons[i].isInvalid = true
        else
            buttons[i].version:SetText(t["version"] .. (GetBackupCreatedText(t) ~= "" and " |cFF777777" .. GetBackupCreatedText(t) .. "|r" or ""))
            buttons[i].isInvalid = nil
        end
        buttons[i].text:SetText(GetBackupDisplayText(t))
        buttons[i]:Show()
    end

    local n = #CellDBBackup

    -- creation button
    buttons[0]:ClearAllPoints()
    buttons[0]:SetPoint("RIGHT", -5, 0)
    if n == 0 then
        buttons[0]:SetPoint("TOPLEFT", 5, -5)
    else
        buttons[0]:SetPoint("TOPLEFT", buttons[n], "BOTTOMLEFT", 0, -5)
    end

    -- hide unused
    for i = n + 1, #buttons do
        buttons[i]:Hide()
    end

    -- scroll range
    backupFrame.list:SetContentHeight((n + 1) * P.Scale(20) + (n + 2) * P.Scale(5))
end

function LoadNotifications()
    notificationFrame.list:ResetScroll()

    local notifications = F.GetAddonNotifications()
    local shown = 0

    for index = #notifications, 1, -1 do
        local entry = notifications[index]
        shown = shown + 1

        if not notificationButtons[shown] then
            notificationButtons[shown] = CreateNotificationItem(shown)
            if shown == 1 then
                notificationButtons[shown]:SetPoint("TOPLEFT", 5, -5)
            else
                notificationButtons[shown]:SetPoint("TOPLEFT", notificationButtons[shown-1], "BOTTOMLEFT", 0, -5)
            end
            notificationButtons[shown]:SetPoint("RIGHT", -5, 0)
            P.Height(notificationButtons[shown], 40)
        end

        local r, g, b = GetNotificationColor(entry["kind"])
        notificationButtons[shown].title:SetText(entry["title"] or "Notification")
        notificationButtons[shown].title:SetTextColor(r, g, b)
        notificationButtons[shown].time:SetText(entry["createdAt"] and date("%m-%d %H:%M", entry["createdAt"]) or "")
        notificationButtons[shown].message:SetText(entry["message"] or "")
        notificationButtons[shown]:Show()
    end

    for i = shown + 1, #notificationButtons do
        notificationButtons[i]:Hide()
    end

    if shown == 0 then
        if not notificationButtons[1] then
            notificationButtons[1] = CreateNotificationItem(1)
            notificationButtons[1]:SetPoint("TOPLEFT", 5, -5)
            notificationButtons[1]:SetPoint("RIGHT", -5, 0)
            P.Height(notificationButtons[1], 40)
        end

        notificationButtons[1].title:SetText("No notifications yet")
        notificationButtons[1].title:SetTextColor(0.7, 0.7, 0.7)
        notificationButtons[1].time:SetText("")
        notificationButtons[1].message:SetText("Imports, backups, and other important addon actions will show up here.")
        notificationButtons[1]:Show()
        shown = 1
    end

    notificationFrame.list:SetContentHeight(shown * P.Scale(40) + (shown + 1) * P.Scale(5))
end

---------------------------------------------------------------------
-- show
---------------------------------------------------------------------
function F.ShowBackupFrame()
    if not backupFrame then
        CreateBackupFrame()
    end

    LoadBackups()
    backupFrame:Show()
end

function F.ShowNotificationCenter()
    if not notificationFrame then
        CreateNotificationFrame()
    end

    LoadNotifications()
    notificationFrame:Show()
end

Cell.RegisterCallback("AddonNotificationsUpdated", "AboutNotifications_Reload", function()
    if notificationFrame and notificationFrame:IsShown() then
        LoadNotifications()
    end
end)

Cell.RegisterCallback("BackupsUpdated", "AboutBackups_Reload", function()
    if backupFrame and backupFrame:IsShown() then
        LoadBackups()
    end
end)
