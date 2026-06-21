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
LadderView.searchText = LadderView.searchText or ""
LadderView.currentPage = LadderView.currentPage or 1
LadderView.searchRefreshTimer = LadderView.searchRefreshTimer or nil
local SEARCH_DEBOUNCE_SECONDS = 0.25
local LADDER_VIEW_LAYOUT_VERSION = 9
local FRAME_WIDTH = 560
local FRAME_HEIGHT = 548
local PADDING = 20
local CONTENT_PAD_LEFT = 16
local CONTENT_PAD_RIGHT = 16
local CONTENT_PAD_BOTTOM = 12
local INPUTBOX_INSET = 6
local ROW_HEIGHT = 16
local HEADER_HEIGHT = 18
local ROW_GAP = 1
local ICON_SIZE = 14
local FACTION_ICON_SIZE = 14
local SUMMARY_GAP = 8
local SEARCH_HEIGHT = 24
local PAGINATION_HEIGHT = 28
local DEFAULT_ROWS_PER_PAGE = 18
local PREV_PAGE_TEXTURE = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
local NEXT_PAGE_TEXTURE = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
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
--- Returns a normalized search string for player-name matching.
--- @param text string|nil
--- @return string
function LadderView.NormalizeSearchText(text)
    return PVL.FoldPlayerSearchText(text)
end

--- Cancels a pending debounced ladder search refresh.
function LadderView.CancelSearchRefreshTimer()
    if LadderView.searchRefreshTimer then
        LadderView.searchRefreshTimer:Cancel()
        LadderView.searchRefreshTimer = nil
    end
end

--- Refreshes the ladder after the search box has been idle briefly.
function LadderView.ScheduleSearchRefresh()
    if PVL.IsCombatLocked and PVL.IsCombatLocked() then
        if PVL.RequestUiRefresh then
            PVL.RequestUiRefresh()
        end
        return
    end

    LadderView.CancelSearchRefreshTimer()
    if C_Timer and C_Timer.NewTimer then
        LadderView.searchRefreshTimer = C_Timer.NewTimer(SEARCH_DEBOUNCE_SECONDS, function()
            LadderView.searchRefreshTimer = nil
            LadderView.Refresh()
        end)
        return
    end

    LadderView.Refresh()
end

--- Returns ladder rows after class/spec filters and optional name search.
--- @param filters table|nil
--- @param searchText string|nil
--- @return table[]
function LadderView.GetDisplayedRows(filters, searchText)
    filters = filters or UI.GetFilters()
    local bracket = filters.bracket or PVL.GetActiveBracketFilter()
    if LadderView.NormalizeSearchText(searchText) == "" then
        return PVL.GetFilteredImportedLadderPlayers(
            bracket,
            filters.classToken,
            filters.specKey,
            PVL.LADDER_VIEW_LIMIT
        )
    end

    return PVL.SearchImportedLadderPlayers(
        bracket,
        filters.classToken,
        filters.specKey,
        searchText
    )
end
--- Returns how many ladder rows fit in the visible table area.
--- @param scrollFrame ScrollFrame|nil
--- @return number
function LadderView.GetRowsPerPage(scrollFrame)
    local scrollHeight = scrollFrame and scrollFrame:GetHeight() or 0
    if scrollHeight <= 0 then
        return DEFAULT_ROWS_PER_PAGE
    end
    local available = scrollHeight - HEADER_HEIGHT - ROW_GAP
    local rowsPerPage = math.floor(available / (ROW_HEIGHT + ROW_GAP))
    return math.max(1, rowsPerPage)
end
--- Returns pagination metadata for one result set.
--- @param totalRows number
--- @param rowsPerPage number
--- @param currentPage number|nil
--- @return number currentPage, number totalPages, number startIndex, number endIndex
function LadderView.GetPaginationState(totalRows, rowsPerPage, currentPage)
    totalRows = totalRows or 0
    rowsPerPage = math.max(1, rowsPerPage or DEFAULT_ROWS_PER_PAGE)
    local totalPages = math.max(1, math.ceil(totalRows / rowsPerPage))
    currentPage = math.min(math.max(currentPage or 1, 1), totalPages)
    local startIndex = ((currentPage - 1) * rowsPerPage) + 1
    local endIndex = math.min(startIndex + rowsPerPage - 1, totalRows)
    if totalRows == 0 then
        startIndex = 0
        endIndex = 0
    end
    return currentPage, totalPages, startIndex, endIndex
end
--- Returns one page slice from a full ladder row list.
--- @param rows table[]
--- @param startIndex number
--- @param endIndex number
--- @return table[]
function LadderView.GetPageRows(rows, startIndex, endIndex)
    local pageRows = {}
    for index = startIndex, endIndex do
        if rows[index] then
            table.insert(pageRows, rows[index])
        end
    end
    return pageRows
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
        table.insert(parts, PVL.L("UI.LADDER.ALL_CLASSES"))
    end
    return table.concat(parts, " · ")
end
--- Builds summary text shown above the aligned ladder table.
--- @param filters table|nil
--- @param searchText string|nil
--- @param totalRows number|nil
--- @return string summary, boolean showSpecColumn, string|nil region
function LadderView.BuildSummaryText(filters, searchText, totalRows)
    filters = filters or UI.GetFilters()
    searchText = searchText or ""
    local bracket = filters.bracket or PVL.GetActiveBracketFilter()
    local snapshot = PVL.GetImportedSnapshot(bracket)
    local lines = {}
    if not snapshot then
        table.insert(lines, Format.Muted(PVL.L("UI.LADDER.NO_DATA")))
        for _, hintLine in ipairs(PVL.GetLadderStalenessLines(bracket)) do
            table.insert(lines, Format.Colorize(Format.COLORS.WARNING, hintLine))
        end
        return table.concat(lines, "\n"), false, PVL.GetActiveLadderRegion()
    end
    local totalPlayers = PVL.GetImportedPlayerCount(bracket)
    if totalPlayers == 0 then
        table.insert(lines, Format.Muted(PVL.L("UI.LADDER.NO_PLAYER_LIST")))
        table.insert(lines, Format.Muted(PVL.L("UI.LADDER.REFRESH_WILL_POPULATE")))
        table.insert(lines, "")
        table.insert(lines, Format.Muted(string.format(
            "Snapshot: %s (%s)",
            snapshot.snapshotDate or "--",
            snapshot.snapshotId or "--"
        )))
        return table.concat(lines, "\n"), false, snapshot.region
    end
    totalRows = totalRows or 0
    local searchActive = LadderView.NormalizeSearchText(searchText) ~= ""
    if searchActive then
        table.insert(lines, string.format(
            "%s players match \"%s\"",
            Format.Count(totalRows),
            searchText
        ))
    elseif filters.classToken or filters.specKey then
        table.insert(lines, string.format(
            "%s matching players shown",
            Format.Count(totalRows)
        ))
    else
        table.insert(lines, string.format(
            "%s listed players shown (of %s in snapshot)",
            Format.Count(totalRows),
            Format.Count(totalPlayers)
        ))
    end
    if not searchActive and totalRows >= PVL.LADDER_VIEW_LIMIT then
        table.insert(lines, Format.Muted(string.format(
            "Showing top %s by rank. Search to find players outside the top list.",
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
    if totalRows == 0 then
        table.insert(lines, "")
        if searchActive then
            table.insert(lines, Format.Muted(PVL.L("UI.LADDER.NO_SEARCH_RESULTS")))
        else
            table.insert(lines, Format.Muted(PVL.L("UI.LADDER.NO_FILTER_RESULTS")))
        end
    end
    return table.concat(lines, "\n"), not filters.specKey, snapshot.region
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
    AddHeaderLabel("RANK", PVL.L("UI.LADDER.COL_RANK"), "RIGHT")
    AddHeaderLabel("PLAYER", PVL.L("UI.LADDER.COL_PLAYER"), "LEFT")
    if showSpecColumn then
        AddHeaderLabel("SPEC", PVL.L("UI.LADDER.COL_SPEC"), "LEFT")
    end
    AddHeaderLabel("CR", PVL.L("UI.LADDER.COL_CR"), "LEFT")
    AddHeaderLabel("WL", PVL.L("UI.LADDER.COL_WL"), "LEFT")
    AddHeaderLabel("WINPCT", PVL.L("UI.LADDER.COL_WINPCT"), "LEFT")
    header.divider = header:CreateTexture(nil, "ARTWORK")
    header.divider:SetColorTexture(122 / 255, 104 / 255, 62 / 255, 0.85)
    header.divider:SetHeight(1)
    header.divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header.divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    return header
end
--- Opens the armory page for one ladder row when a URL is available.
--- @param row Frame
local function OpenRowArmory(row)
    if not row or not row.armoryUrl then
        return
    end

    PVL.ShowArmoryLink(row.armoryUrl, row.displayName)
end
--- Shows the armory tooltip for one ladder row button.
--- @param row Frame
--- @param button Frame
local function ShowRowArmoryTooltip(row, button)
    if not row or not row.armoryUrl then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText("Armory link", 1, 1, 1)
    GameTooltip:AddLine("Click to copy the Battle.net link.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Paste it into your browser (Ctrl+C).", 0.65, 0.65, 0.65, true)
    GameTooltip:Show()
end
--- Configures the invisible click target that covers the player column.
--- @param row Frame
--- @param left number
--- @param width number
local function LayoutPlayerClickTarget(row, left, width)
    row.playerClick:SetPoint("TOPLEFT", row, "TOPLEFT", left, 0)
    row.playerClick:SetSize(width, ROW_HEIGHT)
    row.playerClick:SetFrameLevel(row:GetFrameLevel() + 20)
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
    row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetJustifyV("MIDDLE")
    row.nameText:SetWordWrap(false)
    row.playerClick = CreateFrame("Button", nil, row)
    row.playerClick:Hide()
    row.playerClick:EnableMouse(true)
    row.playerClick:RegisterForClicks("AnyUp")
    row.playerClick:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            OpenRowArmory(row)
        end
    end)
    row.playerClick:SetScript("OnEnter", function(button)
        ShowRowArmoryTooltip(row, button)
    end)
    row.playerClick:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    local highlight = row.playerClick:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
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
--- @param region string|nil
local function UpdateDataRow(row, entry, showSpecColumn, region)
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
    local nameWidth = cols.PLAYER.w - iconOffset - ICON_SIZE - 6
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", nameOffset, 0)
    row.nameText:SetSize(nameWidth, ROW_HEIGHT)
    row.armoryUrl = PVL.BuildArmoryUrl(region, entry.displayName, entry.playerKey)
    row.displayName = entry.displayName
    if row.armoryUrl then
        row.nameText:SetText(Format.PlayerLinkName(entry.displayName, entry.specKey))
        LayoutPlayerClickTarget(row, cols.PLAYER.x, cols.PLAYER.w)
        row.playerClick:Show()
    else
        row.nameText:SetText(Format.PlayerName(entry.displayName, entry.specKey))
        row.playerClick:Hide()
    end
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
--- @return Frame tableHost, fun(rows: table|nil, showSpecColumn: boolean, region: string|nil): nil updateRows
local function CreateLadderTablePanel(parent, name, topAnchor, bottomLeft, bottomRight)
    local tableHost = CreateFrame("Frame", name, parent)
    tableHost:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -SUMMARY_GAP)
    tableHost:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMLEFT", 0, 0)
    tableHost:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMRIGHT", 0, 0)
    local content = CreateFrame("Frame", name .. "Content", tableHost)
    content:SetPoint("TOPLEFT", tableHost, "TOPLEFT", 0, 0)
    content:SetPoint("TOPRIGHT", tableHost, "TOPRIGHT", 0, 0)
    content:EnableMouse(true)
    local panel = {
        tableHost = tableHost,
        content = content,
        headerRow = nil,
        rows = {},
        showSpecColumn = true,
        region = nil,
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
    --- @param region string|nil
    function panel:Update(rows, showSpecColumn, region)
        self.showSpecColumn = showSpecColumn
        self.region = region
        self:ClearRows()
        if not rows or #rows == 0 then
            self.content:SetSize(1, 1)
            return
        end
        local contentWidth = math.max((tableHost:GetWidth() or 440), 320)
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
            UpdateDataRow(row, entry, showSpecColumn, region)
            yOffset = yOffset + ROW_HEIGHT + ROW_GAP
        end
        local contentHeight = math.max(yOffset + 4, tableHost:GetHeight() or 1)
        self.content:SetSize(contentWidth, contentHeight)
    end
    tableHost:SetScript("OnSizeChanged", function()
        if tableHost._pvlUpdating then
            return
        end
        tableHost._pvlUpdating = true
        LadderView.Refresh()
        tableHost._pvlUpdating = false
    end)
    tableHost.UpdateLadderRows = function(rows, showSpecColumn, region)
        panel._lastRows = rows
        panel._lastShowSpec = showSpecColumn
        panel._lastRegion = region
        panel:Update(rows, showSpecColumn, region)
    end
    return tableHost, tableHost.UpdateLadderRows
end
--- Creates one icon-only pagination button.
--- @param parent Frame
--- @param texturePath string
--- @param tooltipText string
--- @return Button
local function CreatePageArrowButton(parent, texturePath, tooltipText)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(24, 24)
    button.normal = button:CreateTexture(nil, "ARTWORK")
    button.normal:SetAllPoints()
    button.normal:SetTexture(texturePath)
    button.disabled = button:CreateTexture(nil, "OVERLAY")
    button.disabled:SetAllPoints()
    button.disabled:SetTexture(texturePath)
    button.disabled:SetDesaturated(true)
    button.disabled:SetAlpha(0.35)
    button.disabled:Hide()
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.12)
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltipText, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return button
end
--- Returns the inset host frame for in-window content placement.
--- @param frame Frame
--- @return Frame
local function GetContentHost(frame)
    return frame.Inset or frame
end

--- Creates the player search box beneath the ladder header note.
--- @param parent Frame
--- @param topAnchor Region
--- @param rightAnchor Region
--- @return FontString label, EditBox searchBox
local function CreateSearchBox(parent, topAnchor, rightAnchor)
    local searchLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("TOPLEFT", topAnchor, "TOPLEFT", 0, 0)
    searchLabel:SetText(Format.SectionLabel(PVL.L("UI.LADDER.SEARCH")))
    local searchBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    searchBox:SetAutoFocus(false)
    searchBox:SetHeight(SEARCH_HEIGHT)
    searchBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", INPUTBOX_INSET, -4)
    searchBox:SetPoint("TOPRIGHT", rightAnchor, "TOPRIGHT", -INPUTBOX_INSET, 0)
    searchBox:SetMaxLetters(64)
    searchBox:SetText(LadderView.searchText or "")
    searchBox:SetScript("OnTextChanged", function(self)
        LadderView.searchText = self:GetText() or ""
        LadderView.currentPage = 1
        LadderView.ScheduleSearchRefresh()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        LadderView.searchText = self:GetText() or ""
        LadderView.currentPage = 1
        LadderView.Refresh()
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return searchLabel, searchBox
end
--- Creates the pagination bar shown beneath the ladder table.
--- @param parent Frame
--- @return Frame
local function CreatePaginationBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(PAGINATION_HEIGHT)
    bar.prevButton = CreatePageArrowButton(bar, PREV_PAGE_TEXTURE, PVL.L("UI.LADDER.PAGE_PREV"))
    bar.prevButton:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.prevButton:SetScript("OnClick", function()
        if LadderView.currentPage > 1 then
            LadderView.currentPage = LadderView.currentPage - 1
            LadderView.Refresh()
        end
    end)
    bar.nextButton = CreatePageArrowButton(bar, NEXT_PAGE_TEXTURE, PVL.L("UI.LADDER.PAGE_NEXT"))
    bar.nextButton:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    bar.nextButton:SetScript("OnClick", function()
        LadderView.currentPage = LadderView.currentPage + 1
        LadderView.Refresh()
    end)
    bar.pageText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.pageText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.pageText:SetJustifyH("CENTER")
    bar.rangeText = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bar.rangeText:SetPoint("RIGHT", bar.nextButton, "LEFT", -12, 0)
    bar.rangeText:SetJustifyH("RIGHT")
    return bar
end
--- Updates pagination controls for the current result set.
--- @param frame Frame
--- @param currentPage number
--- @param totalPages number
--- @param totalRows number
--- @param startIndex number
--- @param endIndex number
function LadderView.UpdatePaginationControls(frame, currentPage, totalPages, totalRows, startIndex, endIndex)
    local bar = frame.paginationBar
    if not bar then
        return
    end
    if totalRows <= 0 then
        bar.pageText:SetText(Format.Muted(PVL.L("UI.LADDER.NO_RESULTS")))
        bar.rangeText:SetText("")
        bar.prevButton:Disable()
        bar.nextButton:Disable()
        bar.prevButton.disabled:Show()
        bar.nextButton.disabled:Show()
        bar:Show()
        return
    end
    bar.pageText:SetText(string.format("Page %d of %d", currentPage, totalPages))
    bar.rangeText:SetText(string.format("%d-%d of %s", startIndex, endIndex, Format.Count(totalRows)))
    if currentPage <= 1 then
        bar.prevButton:Disable()
        bar.prevButton.disabled:Show()
    else
        bar.prevButton:Enable()
        bar.prevButton.disabled:Hide()
    end
    if currentPage >= totalPages then
        bar.nextButton:Disable()
        bar.nextButton.disabled:Show()
    else
        bar.nextButton:Enable()
        bar.nextButton.disabled:Hide()
    end
    if totalPages <= 1 then
        bar.prevButton:Disable()
        bar.nextButton:Disable()
        bar.prevButton.disabled:Show()
        bar.nextButton.disabled:Show()
    end
    bar:Show()
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
    UI.RegisterEscapeToClose(frame, false)
    UI.AddWindowLogo(frame)
    UI.AddWindowWatermark(frame)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText(PVL.L("UI.LADDER.TITLE"))
    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.header:SetPoint("TOPLEFT", GetContentHost(frame), "TOPLEFT", CONTENT_PAD_LEFT, -34)
    frame.header:SetJustifyH("LEFT")
    frame.header:SetWidth(FRAME_WIDTH - (CONTENT_PAD_LEFT + CONTENT_PAD_RIGHT))
    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.note:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -4)
    frame.note:SetPoint("RIGHT", GetContentHost(frame), "RIGHT", -CONTENT_PAD_RIGHT, 0)
    frame.note:SetJustifyH("LEFT")
    frame.note:SetText(Format.Muted(PVL.L("UI.LADDER.ARMORY_HINT")))
    local contentHost = GetContentHost(frame)
    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOP", frame.note, "BOTTOM", 0, -8)
    frame.body:SetPoint("LEFT", contentHost, "LEFT", CONTENT_PAD_LEFT, 0)
    frame.body:SetPoint("RIGHT", contentHost, "RIGHT", -CONTENT_PAD_RIGHT, 0)
    frame.body:SetPoint("BOTTOM", contentHost, "BOTTOM", 0, CONTENT_PAD_BOTTOM)
    frame.searchLabel, frame.searchBox = CreateSearchBox(frame.body, frame.body, frame.body)
    frame.summaryText = frame.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summaryText:SetPoint("TOPLEFT", frame.searchBox, "BOTTOMLEFT", -INPUTBOX_INSET, -10)
    frame.summaryText:SetPoint("RIGHT", frame.body, "RIGHT", 0, 0)
    frame.summaryText:SetJustifyH("LEFT")
    frame.summaryText:SetJustifyV("TOP")
    frame.summaryBottom = CreateFrame("Frame", nil, frame.body)
    frame.summaryBottom:SetPoint("TOPLEFT", frame.summaryText, "BOTTOMLEFT", 0, -4)
    frame.summaryBottom:SetPoint("RIGHT", frame.body, "RIGHT", 0, 0)
    frame.summaryBottom:SetHeight(1)
    frame.paginationBar = CreatePaginationBar(frame.body)
    frame.paginationBar:SetPoint("BOTTOMLEFT", frame.body, "BOTTOMLEFT", 0, 0)
    frame.paginationBar:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", 0, 0)
    frame.listBottom = CreateFrame("Frame", nil, frame.body)
    frame.listBottom:SetPoint("BOTTOMLEFT", frame.paginationBar, "TOPLEFT", 0, 6)
    frame.listBottom:SetPoint("BOTTOMRIGHT", frame.paginationBar, "TOPRIGHT", 0, 6)
    frame.listBottom:SetHeight(1)
    frame.listScroll, frame.updateLadderRows = CreateLadderTablePanel(
        frame.body,
        "PvPLedgerLadderTableHost",
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
    if PVL.IsCombatLocked and PVL.IsCombatLocked() then
        if PVL.RequestUiRefresh then
            PVL.RequestUiRefresh()
        end
        return
    end

    LadderView.CancelSearchRefreshTimer()
    local frame = LadderView.CreateFrame()
    local filters = UI.GetFilters()
    local filterKey = string.format(
        "%s:%s:%s",
        tostring(filters.bracket or ""),
        tostring(filters.classToken or ""),
        tostring(filters.specKey or "")
    )
    if frame._lastFilterKey ~= filterKey then
        LadderView.currentPage = 1
        frame._lastFilterKey = filterKey
    end
    frame.header:SetText(LadderView.BuildFilterLabel(filters))
    local allRows = LadderView.GetDisplayedRows(filters, LadderView.searchText)
    local rowsPerPage = LadderView.GetRowsPerPage(frame.listScroll)
    local currentPage, totalPages, startIndex, endIndex = LadderView.GetPaginationState(
        #allRows,
        rowsPerPage,
        LadderView.currentPage
    )
    LadderView.currentPage = currentPage
    local summaryText, showSpecColumn, region = LadderView.BuildSummaryText(
        filters,
        LadderView.searchText,
        #allRows
    )
    frame.summaryText:SetText(summaryText or "")
    local summaryHeight = frame.summaryText:GetStringHeight() or 1
    frame.summaryBottom:ClearAllPoints()
    frame.summaryBottom:SetPoint("TOPLEFT", frame.summaryText, "TOPLEFT", 0, -(summaryHeight + 4))
    frame.summaryBottom:SetPoint("RIGHT", frame.summaryText, "RIGHT", 0, 0)
    frame.summaryBottom:SetHeight(1)
    local pageRows = LadderView.GetPageRows(allRows, startIndex, endIndex)
    if frame.updateLadderRows then
        frame.updateLadderRows(pageRows, showSpecColumn, region)
    end
    LadderView.UpdatePaginationControls(
        frame,
        currentPage,
        totalPages,
        #allRows,
        startIndex,
        endIndex
    )
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
    if PVL.CanOpenAddonWindows and not PVL.CanOpenAddonWindows() then
        return
    end

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
