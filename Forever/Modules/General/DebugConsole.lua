local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local P = Cell.pixelPerfectFuncs

local CATEGORY_ORDER = {"layout", "comm", "errors", "other"}
local CATEGORY_LABELS = {
    ["layout"] = L["Layout"] or "Layout",
    ["comm"] = L["Comm"] or "Comm",
    ["errors"] = L["Errors"] or "Errors",
    ["other"] = L["Other"] or "Other",
}
local CATEGORY_MATCH = {
    ["layout"] = {"UpdateLayout", "UpdateIndicators", "UpdateMenu", "PreUpdateLayout", "UpdateAll"},
    ["comm"] = {"Comm:", "Comm ", "Comm queued", "Comm dropped", "Comm suppressed"},
    ["errors"] = {"FAILED", "Error", "error"},
}

local function CategorizeLine(text)
    for _, category in ipairs(CATEGORY_ORDER) do
        local patterns = CATEGORY_MATCH[category]
        if patterns then
            for _, pattern in ipairs(patterns) do
                if text:find(pattern, 1, true) then
                    return category
                end
            end
        end
    end
    return "other"
end

local MAX_LOG_LINES = 500
local logLines = {}

local consoleFrame, content, categoryCBs, enableCB

local function EscapeForHTML(text)
    text = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    return text
end

local function RefreshLog()
    if not (consoleFrame and consoleFrame:IsShown()) then return end

    local shown = CellDB and CellDB["general"] and CellDB["general"]["debugCategories"]
    local parts = {}
    for _, entry in ipairs(logLines) do
        if not shown or shown[entry.category] then
            parts[#parts + 1] = "<p>" .. EscapeForHTML(entry.text) .. "</p>"
        end
    end

    content:SetText("<html><body>" .. table.concat(parts) .. "</body></html>")

    C_Timer.After(0, function()
        if not consoleFrame:IsShown() then return end
        local height = content:GetContentHeight()
        content:SetHeight(height)
        consoleFrame.scrollFrame.content:SetHeight(height + 20)
        consoleFrame.scrollFrame:ScrollToBottom()
    end)
end

local function BuildPlainTextLog()
    local shown = CellDB and CellDB["general"] and CellDB["general"]["debugCategories"]
    local lines = {}
    for _, entry in ipairs(logLines) do
        if not shown or shown[entry.category] then
            local plain = entry.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            lines[#lines + 1] = plain
        end
    end
    return table.concat(lines, "\n")
end

local copyFrame, copyTextArea

local function ShowCopyPopup()
    if not copyFrame then
        copyFrame = Cell.CreateMovableFrame(L["Copy Debug Log"] or "Copy Debug Log", "CellDebugConsoleCopyFrame", 420, 320, "FULLSCREEN_DIALOG", 10, true)
        copyFrame:SetToplevel(true)

        local hint = copyFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
        hint:SetPoint("TOPLEFT", 5, -5)
        hint:SetText(L["Ctrl+C to copy, then send it wherever you need"] or "Ctrl+C to copy, then send it wherever you need")

        copyTextArea = Cell.CreateScrollEditBox(copyFrame)
        copyTextArea:SetPoint("TOPLEFT", 5, -20)
        copyTextArea:SetPoint("BOTTOMRIGHT", -5, 5)
        Cell.StylizeFrame(copyTextArea.scrollFrame, {0, 0, 0, 0}, Cell.GetAccentColorTable())

        copyTextArea.eb:SetScript("OnEditFocusGained", function() copyTextArea.eb:HighlightText() end)
        copyTextArea.eb:SetScript("OnMouseUp", function() copyTextArea.eb:HighlightText() end)
        copyTextArea.eb:SetScript("OnEditFocusLost", function() copyFrame:Hide() end)
        copyTextArea.eb:SetScript("OnChar", function() copyTextArea.eb:SetText(copyFrame.text); copyTextArea.eb:HighlightText() end)
    end

    copyFrame.text = BuildPlainTextLog()
    copyTextArea.eb:SetText(copyFrame.text)
    copyTextArea.eb:SetCursorPosition(0)

    copyFrame:ClearAllPoints()
    copyFrame:SetPoint("CENTER")
    copyFrame:Show()
    copyTextArea.eb:SetFocus()
    copyTextArea.eb:HighlightText()
end

function F.DebugLog(text)
    text = tostring(text)
    local category = CategorizeLine(text)
    local stamped = "|cff888888" .. date("%H:%M:%S") .. "|r " .. text
    logLines[#logLines + 1] = {category = category, text = stamped}
    if #logLines > MAX_LOG_LINES then
        table.remove(logLines, 1)
    end
    RefreshLog()
end

local function CreateDebugConsoleFrame()
    consoleFrame = Cell.CreateMovableFrame("Cell " .. (L["Debug Console"] or "Debug Console"), "CellDebugConsoleFrame", 450, 500, "DIALOG", 1, true)
    Cell.frames.debugConsoleFrame = consoleFrame
    consoleFrame:SetToplevel(true)

    enableCB = Cell.CreateCheckButton(consoleFrame, L["Enable Debug Logging"] or "Enable Debug Logging", function(checked)
        CellDB["general"]["debugMode"] = checked
    end, nil, L["Prints internal Cell debug messages into this window instead of the chat frame"] or "")
    enableCB:SetPoint("TOPLEFT", 10, -30)

    local clearBtn = Cell.CreateButton(consoleFrame, L["Clear"] or "Clear", "red-hover", {60, 17})
    clearBtn:SetPoint("TOPRIGHT", -10, -28)
    clearBtn:SetScript("OnClick", function()
        wipe(logLines)
        RefreshLog()
    end)

    local copyBtn = Cell.CreateButton(consoleFrame, L["Copy"] or "Copy", "accent-hover", {60, 17})
    copyBtn:SetPoint("RIGHT", clearBtn, "LEFT", -5, 0)
    copyBtn:SetScript("OnClick", ShowCopyPopup)

    categoryCBs = {}
    local prevCB
    for _, category in ipairs(CATEGORY_ORDER) do
        local cb = Cell.CreateCheckButton(consoleFrame, CATEGORY_LABELS[category], function(checked)
            CellDB["general"]["debugCategories"][category] = checked
            RefreshLog()
        end)
        if prevCB then
            cb:SetPoint("LEFT", prevCB.label, "RIGHT", 12, 0)
        else
            cb:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -12)
        end
        categoryCBs[category] = cb
        prevCB = cb
    end

    Cell.CreateScrollFrame(consoleFrame, -75, 5)
    consoleFrame.scrollFrame:SetScrollStep(37)
    Cell.StylizeFrame(consoleFrame.scrollFrame, {0.1, 0.1, 0.1, 0.5})

    content = CreateFrame("SimpleHTML", "CellDebugConsoleContent", consoleFrame.scrollFrame.content)
    content:SetSpacing("p", 2)
    content:SetFontObject("p", "CELL_FONT_WIDGET")
    content:SetPoint("TOPLEFT", 5, -5)
    content:SetWidth(consoleFrame:GetWidth() - 30)

    consoleFrame:SetScript("OnShow", function()
        enableCB:SetChecked(CellDB["general"]["debugMode"])
        for category, cb in pairs(categoryCBs) do
            cb:SetChecked(CellDB["general"]["debugCategories"][category])
        end
        RefreshLog()
    end)
end

function F.ToggleDebugConsole()
    if not consoleFrame then
        CreateDebugConsoleFrame()
    end

    if consoleFrame:IsShown() then
        consoleFrame:Hide()
    else
        consoleFrame:ClearAllPoints()
        consoleFrame:SetPoint("CENTER")
        consoleFrame:Show()
    end
end
