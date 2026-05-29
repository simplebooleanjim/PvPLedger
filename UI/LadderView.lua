--- Scrollable imported ladder browser filtered by the main UI dropdowns.
--- The player list uses fixed-position row frames so columns stay aligned;
--- space-padding in a single FontString cannot align columns in WoW's font.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI
local Format = UI.Format

UI.LadderView = UI.LadderView or {}
local LadderView = UI.LadderView

LadderView.frame = LadderView.frame or nil
local LADDER_VIEW_LAYOUT_VERSION = 4

local FRAME_WIDTH = 560
local FRAME_HEIGHT = 520
local PADDING = 20

local ROW_HEIGHT = 16
local HEADER_HEIGHT = 18
local ROW_GAP = 1
local ICON_SIZE = 14
local FACTION_ICON_SIZE = 14
local SUMMARY_GAP = 8

--- Pixel column layout when the spec column is visible.
local COL_WITH_SPEC = {
    RANK = { x = 0, w = 26 },
    PLAYER = { x = 28, w = 188 },
    SPEC = { x = 218, w = 72 },
    CR = { x = 294, w = 50 },
    WL = { x = 348, w = 56 },
    WINPCT = { x = 408, w = 44 },
}

--- Pixel column layout when a spec filter hides the spec column.
local COL_NO_SPEC = {
    RANK = { x = 0, w = 26 },
    PLAYER = { x = 28, w = 262 },
    CR = { x = 294, w = 50 },
    WL = { x = 348, w = 56 },
    WINPCT = { x = 408, w = 44 },
}

--- Returns the active column layout table.
--- @param showSpecColumn boolean
--- @return table
local function GetColumnLayout(showSpecColumn)
    return showSpecColumn and COL_WITH_SPEC or COL_NO_SPEC
end

--- Applies a class icon texture to one row icon.
--- @param texture Texture
--- @param classToken string|nil
local function SetClassIcon(texture, classToken)
    if classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken] then
        texture:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        local coords = CLASS_ICON_TCOORDS[classToken]
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        texture:Show()
        return
    end

    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    texture:SetTexCoord(0, 1, 0, 1)
    texture:Show()
end

--- Applies a faction crest texture when known.
--- @param texture Texture
--- @param faction string|nil
local function SetFactionIcon(texture, faction)
    if not faction or faction == "" then
        texture:Hide()
        return
    end

    local upper = string.upper(faction)
    local key
    if upper == "HORDE" then
        key = "Horde"
    elseif upper == "ALLIANCE" then
        key = "Alliance"
    end

    local path = key and Format.FACTION_ICONS[key]
    if not path then
        texture:Hide()
        return
    end

    texture:SetTexture(path)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:Show()
end

--- Builds the subtitle describing the active ladder filters.
--- @param filters table
--- @return string
function LadderView.BuildFilterLabel(filters)
    local bracket = filters.bracket or PVL.GetActiveBracketFilter()
    local bracketName = PVL.BRACKET_NAMES[bracket] or bracket or "PvP"
    local parts = { bracketName }

    if filters.specKey then
        table.insert(parts, Format.SpecName(filters.specKey))
    elseif filters.classToken then
        table.insert(parts, Format.ClassName(filters.classToken))
    else
        table.insert(parts, "All classes")
    end

    return table.concat(parts, " · ")
end

--- Builds summary text shown above the aligned ladder table.
--- @param filters table|nil
--- @return string summary, table|nil rows, boolean showSpecColumn
function LadderView.BuildSummaryText(filters)
    filters = filters or UI.GetFilters()
    local bracket = filters.bracket or PVL.GetActiveBracketFilter()
    local snapshot = PVL.GetImportedSnapshot(bracket)
    local lines = {}

    if not snapshot then
        table.insert(lines, Format.Muted("No ladder data is loaded for this bracket."))
        return table.concat(lines, "\n"), nil, false
    end

    local totalPlayers = PVL.GetImportedPlayerCount(bracket)
    if totalPlayers == 0 then
        table.insert(lines, Format.Muted("This snapshot does not include a player list yet."))
        table.insert(lines, Format.Muted("The next ladder data refresh will populate listed players."))
        table.insert(lines, "")
        table.insert(lines, Format.Muted(string.format(
            "Snapshot: %s (%s)",
            snapshot.snapshotDate or "--",
            snapshot.snapshotId or "--"
        )))
        return table.concat(lines, "\n"), nil, false
    end

    local rows = PVL.GetFilteredImportedLadderPlayers(
        bracket,
        filters.classToken,
        filters.specKey,
        PVL.LADDER_VIEW_LIMIT
    )

    if filters.classToken or filters.specKey then
        table.insert(lines, string.format(
            "%s matching players shown",
            Format.Count(#rows)
        ))
    else
        table.insert(lines, string.format(
            "%s listed players shown (of %s in snapshot)",
            Format.Count(#rows),
            Format.Count(totalPlayers)
        ))
    end

    if #rows >= PVL.LADDER_VIEW_LIMIT then
        table.insert(lines, Format.Muted(string.format(
            "Showing top %s by rank.",
            Format.Count(PVL.LADDER_VIEW_LIMIT)
        )))
    end

    table.insert(lines, Format.Muted(string.format(
        "Snapshot: %s · Source: %s",
        snapshot.snapshotDate or "--",
        PVL.GetSnapshotSource(bracket) or snapshot.source or "unknown"
    )))
    table.insert(lines, Format.Muted(string.format(
        "Loaded from: %s",
        PVL.FormatLadderSourceLabel(PVL.GetSnapshotSource(bracket))
    )))

    for _, hintLine in ipairs(PVL.GetLadderStalenessLines(bracket)) do
        table.insert(lines, Format.Colorize(Format.COLORS.WARNING, hintLine))
    end

    if #rows == 0 then
        table.insert(lines, "")
        table.insert(lines, Format.Muted("No listed players match the current class/spec filter."))
    end

    return table.concat(lines, "\n"), rows, not filters.specKey
end

--- Creates the column header row for the ladder table.
--- @param parent Frame
--- @param showSpecColumn boolean
--- @return Frame
local function CreateHeaderRow(parent, showSpecColumn)
    local cols = GetColumnLayout(showSpecColumn)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(HEADER_HEIGHT)

    local function AddHeaderLabel(key, text, justify)
        local label = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", header, "TOPLEFT", cols[key].x, 0)
        label:SetWidth(cols[key].w)
        label:SetHeight(HEADER_HEIGHT)
        label:SetJustifyH(justify or "LEFT")
        label:SetText(Format.SectionLabel(text))
        return label
    end

    AddHeaderLabel("RANK", "#", "RIGHT")
    AddHeaderLabel("PLAYER", "Player", "LEFT")
    if showSpecColumn then
        AddHeaderLabel("SPEC", "Spec", "LEFT")
    end
    AddHeaderLabel("CR", "CR", "LEFT")
    AddHeaderLabel("WL", "W-L", "LEFT")
    AddHeaderLabel("WINPCT", "Win%", "LEFT")

    header.divider = header:CreateTexture(nil, "ARTWORK")
    header.divider:SetColorTexture(122 / 255, 104 / 255, 62 / 255, 0.85)
    header.divider:SetHeight(1)
    header.divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header.divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)

    return header
end

--- Creates one aligned ladder data row.
--- @param parent Frame
--- @return Frame
local function CreateDataRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rankText:SetJustifyH("RIGHT")
    row.rankText:SetJustifyV("MIDDLE")

    row.factionIcon = row:CreateTexture(nil, "ARTWORK")
    row.factionIcon:SetSize(FACTION_ICON_SIZE, FACTION_ICON_SIZE)

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(ICON_SIZE, ICON_SIZE)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetJustifyV("MIDDLE")
    row.nameText:SetWordWrap(false)

    row.specText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.specText:SetJustifyH("LEFT")
    row.specText:SetJustifyV("MIDDLE")
    row.specText:SetWordWrap(false)

    row.crText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.crText:SetJustifyH("LEFT")
    row.crText:SetJustifyV("MIDDLE")

    row.wlText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.wlText:SetJustifyH("LEFT")
    row.wlText:SetJustifyV("MIDDLE")

    row.winPctText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.winPctText:SetJustifyH("LEFT")
    row.winPctText:SetJustifyV("MIDDLE")

    return row
end

--- Positions and populates one ladder data row.
--- @param row Frame
--- @param entry table
--- @param showSpecColumn boolean
local function UpdateDataRow(row, entry, showSpecColumn)
    local cols = GetColumnLayout(showSpecColumn)

    row.rankText:ClearAllPoints()
    row.rankText:SetPoint("TOPLEFT", row, "TOPLEFT", cols.RANK.x, 0)
    row.rankText:SetSize(cols.RANK.w, ROW_HEIGHT)
    row.rankText:SetText(Format.Muted(tostring(entry.rank or "--")))

    row.factionIcon:ClearAllPoints()
    row.factionIcon:SetPoint("LEFT", row, "LEFT", cols.PLAYER.x, 0)
    SetFactionIcon(row.factionIcon, entry.faction)

    local classToken = entry.classToken or (entry.specKey and entry.specKey:match("^(.-)_"))
    local iconOffset = entry.faction and (FACTION_ICON_SIZE + 2) or 0

    row.classIcon:ClearAllPoints()
    row.classIcon:SetPoint("LEFT", row, "LEFT", cols.PLAYER.x + iconOffset, 0)
    SetClassIcon(row.classIcon, classToken)

    local nameOffset = cols.PLAYER.x + iconOffset + ICON_SIZE + 4
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", nameOffset, 0)
    row.nameText:SetSize(cols.PLAYER.w - iconOffset - ICON_SIZE - 6, ROW_HEIGHT)
    row.nameText:SetText(Format.PlayerName(entry.displayName, entry.specKey))

    if showSpecColumn then
        row.specText:Show()
        row.specText:ClearAllPoints()
        row.specText:SetPoint("TOPLEFT", row, "TOPLEFT", cols.SPEC.x, 0)
        row.specText:SetSize(cols.SPEC.w, ROW_HEIGHT)
        row.specText:SetText(entry.specKey and Format.SpecShortName(entry.specKey) or Format.Muted("--"))
    else
        row.specText:Hide()
    end

    row.crText:ClearAllPoints()
    row.crText:SetPoint("TOPLEFT", row, "TOPLEFT", cols.CR.x, 0)
    row.crText:SetSize(cols.CR.w, ROW_HEIGHT)
    row.crText:SetText(Format.Rating(entry.rating))

    row.wlText:ClearAllPoints()
    row.wlText:SetPoint("TOPLEFT", row, "TOPLEFT", cols.WL.x, 0)
    row.wlText:SetSize(cols.WL.w, ROW_HEIGHT)
    if entry.wins or entry.losses then
        row.wlText:SetText(Format.WinLossRecord(entry.wins, entry.losses))
    else
        row.wlText:SetText(Format.Muted("--"))
    end

    row.winPctText:ClearAllPoints()
    row.winPctText:SetPoint("TOPLEFT", row, "TOPLEFT", cols.WINPCT.x, 0)
    row.winPctText:SetSize(cols.WINPCT.w, ROW_HEIGHT)
    row.winPctText:SetText(Format.WinPercent(entry.wins, entry.losses))

    row:Show()
end

--- Creates the scrollable ladder table panel beneath the summary text.
--- @param parent Frame
--- @param name string
--- @param topAnchor Region
--- @param bottomLeft Region
--- @param bottomRight Region
--- @return Frame scrollFrame, fun(rows: table|nil, showSpecColumn: boolean): nil updateRows
local function CreateLadderTablePanel(parent, name, topAnchor, bottomLeft, bottomRight)
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -SUMMARY_GAP)
    scrollFrame:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMRIGHT", 0, 0)

    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -2, -16)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -2, 16)
    end

    local content = CreateFrame("Frame", name .. "Content", scrollFrame)
    scrollFrame:SetScrollChild(content)

    local panel = {
        scrollFrame = scrollFrame,
        content = content,
        headerRow = nil,
        rows = {},
        showSpecColumn = true,
    }

    --- Hides all table rows.
    function panel:ClearRows()
        for _, row in ipairs(self.rows) do
            row:Hide()
        end
        if self.headerRow then
            self.headerRow:Hide()
        end
    end

    --- Refreshes aligned ladder rows.
    --- @param rows table|nil
    --- @param showSpecColumn boolean
    function panel:Update(rows, showSpecColumn)
        self.showSpecColumn = showSpecColumn
        self:ClearRows()

        if not rows or #rows == 0 then
            self.content:SetSize(1, 1)
            scrollFrame:SetVerticalScroll(0)
            if scrollFrame.UpdateScrollChildRect then
                scrollFrame:UpdateScrollChildRect()
            end
            UI.UpdateScrollBarVisibility(scrollFrame)
            return
        end

        local contentWidth = math.max((scrollFrame:GetWidth() or 440) - 28, 320)
        local yOffset = 0

        if not self.headerRow or self.headerRow.showSpecColumn ~= showSpecColumn then
            if self.headerRow then
                self.headerRow:Hide()
                self.headerRow = nil
            end
            self.headerRow = CreateHeaderRow(self.content, showSpecColumn)
            self.headerRow.showSpecColumn = showSpecColumn
        end

        self.headerRow:ClearAllPoints()
        self.headerRow:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -yOffset)
        self.headerRow:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
        self.headerRow:Show()
        yOffset = yOffset + HEADER_HEIGHT + ROW_GAP

        for index, entry in ipairs(rows) do
            local row = self.rows[index]
            if not row then
                row = CreateDataRow(self.content)
                self.rows[index] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
            UpdateDataRow(row, entry, showSpecColumn)
            yOffset = yOffset + ROW_HEIGHT + ROW_GAP
        end

        local contentHeight = math.max(yOffset + 4, scrollFrame:GetHeight() or 1)
        self.content:SetSize(contentWidth, contentHeight)
        scrollFrame:SetVerticalScroll(0)
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
        UI.UpdateScrollBarVisibility(scrollFrame)
    end

    scrollFrame:SetScript("OnSizeChanged", function()
        if scrollFrame._pvlUpdating then
            return
        end

        scrollFrame._pvlUpdating = true
        if panel._lastRows then
            panel:Update(panel._lastRows, panel._lastShowSpec)
        end
        scrollFrame._pvlUpdating = false
    end)

    scrollFrame.UpdateLadderRows = function(rows, showSpecColumn)
        panel._lastRows = rows
        panel._lastShowSpec = showSpecColumn
        panel:Update(rows, showSpecColumn)
    end

    return scrollFrame, scrollFrame.UpdateLadderRows
end

--- Creates the ladder browser frame.
--- @return Frame
function LadderView.CreateFrame()
    if LadderView.frame and LadderView.frame.layoutVersion == LADDER_VIEW_LAYOUT_VERSION then
        return LadderView.frame
    end

    if LadderView.frame then
        LadderView.frame:Hide()
        LadderView.frame = nil
    end

    local frame = CreateFrame("Frame", "PvPLedgerLadderFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 120, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.RegisterEscapeToClose(frame)

    UI.AddWindowLogo(frame)
    UI.AddWindowWatermark(frame)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("Ladder")

    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -34)
    frame.header:SetJustifyH("LEFT")
    frame.header:SetWidth(FRAME_WIDTH - (PADDING * 2))

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.note:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -4)
    frame.note:SetJustifyH("LEFT")
    frame.note:SetText(Format.Muted("Uses the Bracket, Class, and Spec filters from the main window."))

    local contentWidth = FRAME_WIDTH - (PADDING * 2)
    local contentTop = frame.note

    frame.summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summaryText:SetPoint("TOPLEFT", contentTop, "BOTTOMLEFT", 0, -10)
    frame.summaryText:SetWidth(contentWidth - 24)
    frame.summaryText:SetJustifyH("LEFT")
    frame.summaryText:SetJustifyV("TOP")

    frame.summaryBottom = CreateFrame("Frame", nil, frame)
    frame.summaryBottom:SetPoint("TOPLEFT", frame.summaryText, "BOTTOMLEFT", 0, -4)
    frame.summaryBottom:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
    frame.summaryBottom:SetHeight(1)

    frame.listBottom = CreateFrame("Frame", nil, frame)
    frame.listBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING)
    frame.listBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)
    frame.listBottom:SetHeight(1)

    frame.listScroll, frame.updateLadderRows = CreateLadderTablePanel(
        frame,
        "PvPLedgerLadderTableScroll",
        frame.summaryBottom,
        frame.listBottom,
        frame.listBottom
    )

    frame.layoutVersion = LADDER_VIEW_LAYOUT_VERSION
    LadderView.frame = frame
    return frame
end

--- Refreshes ladder browser content from the current UI filters.
function LadderView.Refresh()
    local frame = LadderView.CreateFrame()
    local filters = UI.GetFilters()
    frame.header:SetText(LadderView.BuildFilterLabel(filters))

    local summaryText, rows, showSpecColumn = LadderView.BuildSummaryText(filters)
    frame.summaryText:SetText(summaryText or "")

    local summaryHeight = frame.summaryText:GetStringHeight() or 1
    frame.summaryBottom:ClearAllPoints()
    frame.summaryBottom:SetPoint("TOPLEFT", frame.summaryText, "TOPLEFT", 0, -(summaryHeight + 4))
    frame.summaryBottom:SetPoint("RIGHT", frame.summaryText, "RIGHT", 0, 0)
    frame.summaryBottom:SetHeight(1)

    if frame.updateLadderRows then
        frame.updateLadderRows(rows, showSpecColumn)
    end
end

--- Positions the ladder window to the right of the main window when possible.
function LadderView.PositionDefault()
    local frame = LadderView.frame
    if not frame then
        return
    end

    frame:ClearAllPoints()
    local main = PVL.UI and PVL.UI.frame
    if main and main:IsShown() then
        frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 360, 0)
    end
end

--- Shows the ladder browser window.
function LadderView.Show()
    LadderView.Refresh()
    LadderView.PositionDefault()
    LadderView.frame:Show()
    LadderView.frame:Raise()
end

--- Hides the ladder browser window.
function LadderView.Hide()
    if LadderView.frame then
        LadderView.frame:Hide()
    end
end

--- Toggles the ladder browser window.
function LadderView.Toggle()
    local frame = LadderView.CreateFrame()
    if frame:IsShown() then
        LadderView.Hide()
    else
        LadderView.Show()
    end
end
