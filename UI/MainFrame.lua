--- Main window with class/spec filters and a spec detail card.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI
local Format = UI.Format

UI.frame = UI.frame or nil
local UI_LAYOUT_VERSION = 20

local FRAME_WIDTH = 720
local FRAME_HEIGHT = 580
local PADDING = 20
local FILTER_LABEL_X = 16
local FILTER_ROW_Y = -34
local DROPDOWN_MENU_INSET = 16
local COLUMN_GAP = 12
local COLUMN_WIDTH = math.floor((FRAME_WIDTH - (PADDING * 2) - COLUMN_GAP) / 2)
local CONTENT_WIDTH = FRAME_WIDTH - (PADDING * 2)
local TRIPLE_COL_GAP_TOTAL = COLUMN_GAP * 2
local TRIPLE_COL_WIDTH = math.floor((CONTENT_WIDTH - TRIPLE_COL_GAP_TOTAL) / 3)
local MIDDLE_SECTION_HEIGHT = 212
local MATCH_DROPDOWN_HEIGHT = 28
local BOTTOM_SECTION_GAP = 12
local TOP_SECTION_Y = -78

--- Returns the left edge X offset for one of the three top content columns.
--- @param columnIndex number 1=left, 2=middle, 3=right
--- @return number
function UI.GetTopColumnOffset(columnIndex)
    if columnIndex <= 1 then
        return PADDING
    end

    return PADDING + ((columnIndex - 1) * (TRIPLE_COL_WIDTH + COLUMN_GAP))
end

--- Returns persisted UI filter settings.
--- @return table
function UI.GetFilters()
    local db = PVL.GetDB()
    db.settings.uiFilters = db.settings.uiFilters or {}
    return db.settings.uiFilters
end

--- Applies the active bracket filter.
--- @param bracket string
function UI.SetBracketFilter(bracket)
    local filters = UI.GetFilters()
    filters.bracket = bracket
    filters.selectedMatchId = nil
    UI.Refresh()
end

--- Applies a class filter and clears an invalid spec selection.
--- @param classToken string|nil
function UI.SetClassFilter(classToken)
    local filters = UI.GetFilters()
    filters.classToken = classToken

    if filters.specKey and classToken then
        local specClass = filters.specKey:match("^(.-)_")
        if specClass ~= classToken then
            filters.specKey = nil
        end
    end

    UI.Refresh()
end

--- Applies a spec filter and aligns the class filter when needed.
--- @param specKey string|nil
function UI.SetSpecFilter(specKey)
    local filters = UI.GetFilters()
    filters.specKey = specKey

    if specKey then
        filters.classToken = specKey:match("^(.-)_")
    end

    UI.Refresh()
end

--- Creates and returns the addon's primary UI frame.
--- @return Frame
function UI.CreateMainFrame()
    if UI.frame and UI.frame.layoutVersion == UI_LAYOUT_VERSION then
        return UI.frame
    end

    if UI.frame then
        UI.frame:Hide()
        UI.frame = nil
    end

    local frame = CreateFrame("Frame", "PvPLedgerMainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.RegisterEscapeToClose(frame)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("PvPLedger")

    frame.bracketLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.bracketLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", FILTER_LABEL_X, FILTER_ROW_Y)
    frame.bracketLabel:SetText("Bracket")

    frame.bracketDropdown, frame.refreshBracketDropdown = UI.CreateDropdown(
        frame,
        "PvPLedgerBracketDropdown",
        170,
        function()
            return PVL.GetBracketFilterOptions()
        end,
        function()
            local filters = UI.GetFilters()
            return PVL.GetSelectedOptionIndex(PVL.GetBracketFilterOptions(), filters.bracket)
        end,
        function(_, option)
            UI.SetBracketFilter(option.value)
        end
    )
    frame.bracketDropdown:SetPoint("TOPLEFT", frame.bracketLabel, "BOTTOMLEFT", -DROPDOWN_MENU_INSET, -2)

    frame.classLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.classLabel:SetPoint("LEFT", frame.bracketLabel, "LEFT", 190, 0)
    frame.classLabel:SetText("Class")

    frame.classDropdown, frame.refreshClassDropdown = UI.CreateDropdown(
        frame,
        "PvPLedgerClassDropdown",
        150,
        function()
            return PVL.GetClassFilterOptions()
        end,
        function()
            local filters = UI.GetFilters()
            return PVL.GetSelectedOptionIndex(PVL.GetClassFilterOptions(), filters.classToken)
        end,
        function(_, option)
            UI.SetClassFilter(option.value)
            if frame.refreshSpecDropdown then
                frame.refreshSpecDropdown()
            end
        end
    )
    frame.classDropdown:SetPoint("TOPLEFT", frame.classLabel, "BOTTOMLEFT", -DROPDOWN_MENU_INSET, -2)

    frame.specLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.specLabel:SetPoint("LEFT", frame.classLabel, "LEFT", 170, 0)
    frame.specLabel:SetText("Spec")

    frame.specDropdown, frame.refreshSpecDropdown = UI.CreateDropdown(
        frame,
        "PvPLedgerSpecDropdown",
        220,
        function()
            return PVL.GetSpecFilterOptions(UI.GetFilters().classToken)
        end,
        function()
            local filters = UI.GetFilters()
            return PVL.GetSelectedOptionIndex(
                PVL.GetSpecFilterOptions(filters.classToken),
                filters.specKey
            )
        end,
        function(_, option)
            UI.SetSpecFilter(option.value)
        end
    )
    frame.specDropdown:SetPoint("TOPLEFT", frame.specLabel, "BOTTOMLEFT", -DROPDOWN_MENU_INSET, -2)

    frame.regionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.regionLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, FILTER_ROW_Y)
    frame.regionLabel:SetJustifyH("RIGHT")

    frame.summaryHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.summaryHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.GetTopColumnOffset(1), TOP_SECTION_Y)
    frame.summaryHeader:SetText(Format.Header("Overview"))

    frame.summaryScroll, frame.setSummaryText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerSummaryScroll",
        frame.summaryHeader,
        frame,
        frame,
        nil,
        MIDDLE_SECTION_HEIGHT,
        TRIPLE_COL_WIDTH
    )
    frame.summaryScroll:ClearAllPoints()
    frame.summaryScroll:SetPoint("TOPLEFT", frame.summaryHeader, "BOTTOMLEFT", 0, -8)
    frame.summaryScroll:SetSize(TRIPLE_COL_WIDTH, MIDDLE_SECTION_HEIGHT)

    frame.crHistoryHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.crHistoryHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.GetTopColumnOffset(2), TOP_SECTION_Y)
    frame.crHistoryHeader:SetText(Format.Header(PVL.LABELS.CR_HISTORY))

    frame.crHistoryScroll, frame.setCrHistoryText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerCrHistoryScroll",
        frame.crHistoryHeader,
        frame,
        frame,
        nil,
        MIDDLE_SECTION_HEIGHT,
        TRIPLE_COL_WIDTH
    )
    frame.crHistoryScroll:ClearAllPoints()
    frame.crHistoryScroll:SetPoint("TOPLEFT", frame.crHistoryHeader, "BOTTOMLEFT", 0, -8)
    frame.crHistoryScroll:SetSize(TRIPLE_COL_WIDTH, MIDDLE_SECTION_HEIGHT)

    frame.specDetailHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.specDetailHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.GetTopColumnOffset(3), TOP_SECTION_Y)
    frame.specDetailHeader:SetText(Format.Header("Spec Detail"))

    frame.specDetailScroll, frame.setSpecDetailText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerSpecDetailScroll",
        frame.specDetailHeader,
        frame,
        frame,
        nil,
        MIDDLE_SECTION_HEIGHT,
        TRIPLE_COL_WIDTH
    )
    frame.specDetailScroll:ClearAllPoints()
    frame.specDetailScroll:SetPoint("TOPLEFT", frame.specDetailHeader, "BOTTOMLEFT", 0, -8)
    frame.specDetailScroll:SetSize(TRIPLE_COL_WIDTH, MIDDLE_SECTION_HEIGHT)

    frame.topRowBottom = CreateFrame("Frame", nil, frame)
    frame.topRowBottom:SetPoint("TOPLEFT", frame.summaryScroll, "BOTTOMLEFT", 0, -4)
    frame.topRowBottom:SetPoint("TOPRIGHT", frame.specDetailScroll, "BOTTOMRIGHT", 0, -4)
    frame.topRowBottom:SetHeight(1)

    frame.matchDetailHeader = UI.CreateSectionHeader(
        frame,
        "Match Detail",
        { "TOPLEFT", frame.topRowBottom, "BOTTOMLEFT", 0, -BOTTOM_SECTION_GAP }
    )

    frame.combatAnalysisHeader = UI.CreateSectionHeader(
        frame,
        "Combat Analysis",
        { "TOPLEFT", frame.matchDetailHeader, "TOPLEFT", COLUMN_WIDTH + COLUMN_GAP, 0 }
    )

    frame.leftColumnBottom = CreateFrame("Frame", nil, frame)
    frame.leftColumnBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING)
    frame.leftColumnBottom:SetPoint("RIGHT", frame, "CENTER", -(COLUMN_GAP / 2), 0)
    frame.leftColumnBottom:SetHeight(1)

    frame.rightColumnBottom = CreateFrame("Frame", nil, frame)
    frame.rightColumnBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)
    frame.rightColumnBottom:SetPoint("LEFT", frame, "CENTER", COLUMN_GAP / 2, 0)
    frame.rightColumnBottom:SetHeight(1)

    frame.matchDropdown, frame.refreshMatchDropdown = UI.CreateDropdown(
        frame,
        "PvPLedgerMatchDropdown",
        COLUMN_WIDTH - 8,
        function()
            return UI.GetRecentMatchOptions()
        end,
        function()
            return UI.GetSelectedMatchIndex()
        end,
        function(_, option)
            UI.SetSelectedMatchId(option.value)
        end
    )
    frame.matchDropdown:SetPoint("TOPLEFT", frame.matchDetailHeader, "BOTTOMLEFT", -DROPDOWN_MENU_INSET, -2)

    frame.matchDetailScroll, frame.setMatchDetailText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerMatchDetailScroll",
        frame.matchDropdown,
        frame.leftColumnBottom,
        frame.leftColumnBottom,
        frame.leftColumnBottom
    )
    frame.matchDetailScroll:ClearAllPoints()
    frame.matchDetailScroll:SetPoint("TOPLEFT", frame.matchDropdown, "BOTTOMLEFT", DROPDOWN_MENU_INSET, -6)
    frame.matchDetailScroll:SetPoint("BOTTOMLEFT", frame.leftColumnBottom, "BOTTOMLEFT", 0, 0)
    frame.matchDetailScroll:SetPoint("BOTTOMRIGHT", frame.leftColumnBottom, "BOTTOMRIGHT", 0, 0)

    frame.combatStatDropdown, frame.refreshCombatStatDropdown = UI.CreateDropdown(
        frame,
        "PvPLedgerCombatStatDropdown",
        COLUMN_WIDTH - 8,
        function()
            return UI.GetCombatStatOptions()
        end,
        function()
            return UI.GetSelectedCombatStatIndex()
        end,
        function(_, option)
            UI.SetCombatStat(option.value)
        end
    )
    frame.combatStatDropdown:SetPoint("TOPLEFT", frame.combatAnalysisHeader, "BOTTOMLEFT", -DROPDOWN_MENU_INSET, -2)

    frame.combatMeterScroll, frame.updateCombatMeter = UI.CreateCombatMeterPanel(
        frame,
        "PvPLedgerCombatMeterScroll",
        frame.combatStatDropdown,
        frame.rightColumnBottom,
        frame.rightColumnBottom
    )

    frame.layoutVersion = UI_LAYOUT_VERSION
    UI.frame = frame
    return frame
end

--- Builds text for the character and overall summary block.
--- @param summary table
--- @return string
function UI.BuildSummaryText(summary)
    local lines = {}
    local bracketName = PVL.BRACKET_NAMES[summary.bracket] or summary.bracket or "PvP"

    table.insert(lines, string.format(
        "%s  %s",
        Format.Label("Bracket:"),
        Format.Header(bracketName)
    ))
    table.insert(lines, Format.StatLine("Matches tracked", Format.Count(summary.matchCount)))
    table.insert(lines, Format.StatLine(PVL.LABELS.CURRENT_CR, Format.Rating(summary.playerCurrentCR)))
    table.insert(lines, Format.StatLine("Last match CR", Format.Rating(summary.playerCR)))
    table.insert(lines, Format.StatLine(
        PVL.GetObservedMmrLabel(summary.bracket, summary.playerMMRKind),
        Format.Rating(summary.playerMMR)
    ))

    if summary.standing then
        table.insert(lines, Format.StatLine(
            "Estimated standing",
            Format.Colorize(Format.COLORS.STANDING, summary.standing.cutoffLabel)
        ))
    end

    if summary.importedOverall then
        table.insert(lines, "")
        table.insert(lines, string.format(
            "%s  %s",
            Format.Label("Snapshot:"),
            Format.Colorize(Format.COLORS.SOURCE, string.format(
                "%s (%s)",
                summary.imported.source or "unknown",
                summary.imported.snapshotDate or "unknown"
            ))
        ))
        if summary.importedPlayerCount and summary.importedPlayerCount > 0 then
            table.insert(lines, Format.StatLine("Indexed players", Format.Count(summary.importedPlayerCount)))
        end
        if summary.observedPlayerCount and summary.observedPlayerCount > 0 then
            table.insert(lines, Format.StatLine(
                "Observed on ladder",
                string.format("%s / %s", Format.Count(summary.listedObservedCount or 0), Format.Count(summary.observedPlayerCount))
            ))
        end
        table.insert(lines, Format.StatLine(PVL.LABELS.LISTED_AVG, Format.Rating(summary.importedOverall.avgListedRating)))
        table.insert(lines, Format.StatLine(PVL.LABELS.LISTED_MEDIAN, Format.Rating(summary.importedOverall.medianListedRating)))
        table.insert(lines, Format.StatLine(PVL.LABELS.TOP100_AVG, Format.Rating(summary.importedOverall.top100Avg)))
    else
        table.insert(lines, "")
        table.insert(lines, Format.Muted("No imported ladder snapshot loaded."))
    end

    return table.concat(lines, "\n")
end

--- Builds CR history text for the detail panel.
--- @param bracket string|nil
--- @return string
function UI.BuildCrHistoryText(bracket)
    if not PVL.CrHistory then
        return Format.Muted("CR history is unavailable.")
    end

    bracket = bracket or PVL.GetActiveBracketFilter()
    local summary = PVL.CrHistory.BuildSummary(bracket)
    local lines = {
        Format.StatLine(PVL.LABELS.CR_PEAK, Format.Rating(summary.peakCr)),
        Format.StatLine(PVL.LABELS.CR_LOW, Format.Rating(summary.lowCr)),
        Format.StatLine(PVL.LABELS.CR_NET_7D, PVL.CrHistory.FormatDelta(summary.net7d)),
        Format.StatLine(PVL.LABELS.CR_NET_SESSION, PVL.CrHistory.FormatDelta(summary.netSession)),
        Format.StatLine(
            "Session record",
            string.format(
                "%s-%s  (%s games)",
                Format.Count(summary.winsSession),
                Format.Count(summary.lossesSession),
                Format.Count(summary.gamesSession)
            )
        ),
        "",
    }

    if #summary.recentEntries == 0 then
        table.insert(lines, Format.Muted("No CR history recorded for this bracket yet."))
        table.insert(lines, Format.Muted("Play rated games or open the PvP queue menu to start tracking."))
        return table.concat(lines, "\n")
    end

    table.insert(lines, Format.Label("Recent activity"))
    table.insert(lines, "")

    for _, entry in ipairs(summary.recentEntries) do
        if entry.source == "match" then
            local resultLabel = entry.won == true and Format.Colorize("FF40C040", "W")
                or (entry.won == false and Format.Colorize("FFFF4040", "L") or Format.Muted("-"))
            table.insert(lines, string.format(
                "%s  %s  %s -> %s  (%s)  %s",
                Format.Muted(PVL.CrHistory.FormatTimestamp(entry.timestamp)),
                Format.Muted("match"),
                Format.Rating(entry.crBefore),
                Format.Rating(entry.cr),
                PVL.CrHistory.FormatDelta(entry.delta),
                resultLabel
            ))
        else
            table.insert(lines, string.format(
                "%s  %s  %s",
                Format.Muted(PVL.CrHistory.FormatTimestamp(entry.timestamp)),
                Format.Muted(PVL.CrHistory.GetEntryTypeLabel(entry)),
                Format.Rating(entry.cr)
            ))
        end
    end

    return table.concat(lines, "\n")
end

--- Builds text for the spec detail panel from class/spec filters.
--- @param classToken string|nil
--- @param specKey string|nil
--- @return string
function UI.BuildSpecDetailPanelText(classToken, specKey)
    if specKey then
        return UI.BuildSpecDetailText(specKey)
    end

    if classToken then
        return UI.BuildClassDetailText(classToken)
    end

    return UI.BuildOverviewDetailText()
end

--- Builds the combined spec detail and imported ladder snapshot panel.
--- @param classToken string|nil
--- @param specKey string|nil
--- @return string
function UI.BuildCombinedSpecLadderText(classToken, specKey)
    local lines = {
        UI.BuildSpecDetailPanelText(classToken, specKey),
        "",
        Format.Header("Imported Ladder Snapshot"),
        "",
        UI.BuildImportedListText(classToken, specKey),
    }

    return table.concat(lines, "\n")
end

--- Updates the top-row detail panels.
--- @param frame Frame
--- @param filters table
function UI.UpdateDetailPanels(frame, filters)
    local bracket = filters.bracket or PVL.GetActiveBracketFilter()

    frame.summaryHeader:SetText(Format.Header("Overview"))
    frame.crHistoryHeader:SetText(Format.Header(PVL.LABELS.CR_HISTORY))
    frame.specDetailHeader:SetText(Format.Header("Spec Detail"))
    frame.setCrHistoryText(UI.BuildCrHistoryText(bracket))
    frame.setSpecDetailText(UI.BuildCombinedSpecLadderText(filters.classToken, filters.specKey))
end

--- Updates the bottom match review panels for the selected match.
--- @param frame Frame
--- @param filters table
function UI.UpdateMatchDetailPanel(frame, filters)
    local bracket = filters.bracket or PVL.GetActiveBracketFilter()
    local selectedMatch = UI.ResolveSelectedMatch(bracket)

    frame.setMatchDetailText(UI.BuildMatchDetailText(selectedMatch))

    local statDef = UI.GetCombatStatDefinition(filters.combatStat)
    if frame.updateCombatMeter then
        frame.updateCombatMeter(selectedMatch, statDef)
    end

    if frame.refreshMatchDropdown then
        frame.refreshMatchDropdown()
    end
    if frame.refreshCombatStatDropdown then
        frame.refreshCombatStatDropdown()
    end
end

--- Builds text when all classes and all specs are selected.
--- @return string
function UI.BuildOverviewDetailText()
    local bracket = PVL.GetActiveBracketFilter()
    local classRows = PVL.GetImportedClassRows()
    local lines = {
        Format.Header("All Classes"),
        "",
    }

    if PVL.IsImportedSpecBreakdownMissing(bracket) then
        local bracketName = PVL.BRACKET_NAMES[bracket] or "This bracket"
        table.insert(lines, Format.Muted(string.format(
            "%s uses one combined imported ladder without class breakdown.",
            bracketName
        )))
        table.insert(lines, Format.Muted(string.format(
            "Select a class to view observed spec data from %s matches.",
            bracketName
        )))
        return table.concat(lines, "\n")
    end

    if #classRows == 0 then
        table.insert(lines, Format.Muted("No imported class breakdown is available for this bracket yet."))
        return table.concat(lines, "\n")
    end

    table.insert(lines, Format.Label("Listed ladder by class"))
    table.insert(lines, "")

    for _, row in ipairs(classRows) do
        local header, stats = Format.ClassOverviewLines(row)
        table.insert(lines, header)
        table.insert(lines, stats)
    end

    table.insert(lines, "")
    table.insert(lines, Format.Muted("Select a class to drill into specs."))

    return table.concat(lines, "\n")
end

--- Builds text for one selected class with all specs.
--- @param classToken string
--- @return string
function UI.BuildClassDetailText(classToken)
    local detail = PVL.BuildClassDetailSummary(classToken)
    if not detail then
        return Format.Muted("No detail available for the selected class.")
    end

    local lines = {
        string.format("%s  %s", Format.ClassName(classToken, detail.displayName), Format.Label("All Specs")),
        "",
    }

    if detail.imported then
        Format.AppendImportedStats(lines, detail.imported, detail.importedRepresentation)
    elseif PVL.IsImportedSpecBreakdownMissing() then
        table.insert(lines, Format.Muted(string.format(
            "No imported class breakdown for %s.",
            PVL.BRACKET_NAMES[PVL.GetActiveBracketFilter()] or "this bracket"
        )))
    else
        table.insert(lines, Format.Muted("No imported listed-ladder data for this class yet."))
    end

    if detail.importedSpecRows and #detail.importedSpecRows > 0 then
        table.insert(lines, "")
        table.insert(lines, Format.Label("Listed specs"))
        for _, row in ipairs(detail.importedSpecRows) do
            table.insert(lines, Format.SpecListLine(row.specKey, row.listedCount, nil, row.avgListedRating))
        end
    end

    table.insert(lines, "")
    table.insert(lines, Format.StatLine(
        PVL.LABELS.OBSERVED,
        string.format("%s  %s", Format.Count(detail.observedCount), Format.Percent(detail.observedPercent))
    ))

    if detail.observedSpecRows and #detail.observedSpecRows > 0 then
        table.insert(lines, "")
        table.insert(lines, Format.Label("Observed specs"))
        for _, row in ipairs(detail.observedSpecRows) do
            table.insert(lines, Format.SpecListLine(row.specKey, row.count, row.percent))
        end
    end

    return table.concat(lines, "\n")
end

--- Builds text for the selected spec detail card.
--- @param specKey string
--- @return string
function UI.BuildSpecDetailText(specKey)
    if not specKey then
        return Format.Muted("Select a class or spec to compare imported ladder stats against your observed match data.")
    end

    local detail = PVL.BuildSpecDetailSummary(specKey)
    if not detail then
        return Format.Muted("No detail available for the selected spec.")
    end

    local lines = {
        Format.SpecName(specKey),
        "",
    }

    if detail.imported then
        Format.AppendImportedStats(lines, detail.imported, detail.importedRepresentation)
    elseif PVL.IsImportedSpecBreakdownMissing() then
        table.insert(lines, Format.Muted(string.format(
            "%s has one combined imported ladder without per-spec breakdown.",
            PVL.BRACKET_NAMES[PVL.GetActiveBracketFilter()] or "This bracket"
        )))
    else
        table.insert(lines, Format.Muted("No imported listed-ladder data for this spec yet."))
    end

    table.insert(lines, "")
    table.insert(lines, Format.StatLine(
        PVL.LABELS.OBSERVED,
        string.format("%s  %s", Format.Count(detail.observedCount), Format.Percent(detail.observedPercent))
    ))

    return table.concat(lines, "\n")
end

--- Builds the imported snapshot list for the current filters.
--- @param classToken string|nil
--- @param specKey string|nil
--- @return string
function UI.BuildImportedListText(classToken, specKey)
    local bracket = PVL.GetActiveBracketFilter()
    local snapshot = PVL.GetImportedSnapshot(bracket)
    if not snapshot then
        if PVL.IsDataAddonInstalled() then
            return Format.Muted("No imported ladder snapshot loaded. Try /pvl update, then /reload.")
        end

        return Format.Muted(string.format(
            "No imported ladder snapshot loaded. Install PvPLedger-Data-US or update PvPLedger, then /reload."
        ))
    end

    local sourceLabel = PVL.GetSnapshotSource(bracket) or "unknown"
    local lines = {
        string.format("%s  %s", Format.Label("Snapshot"), Format.Colorize(Format.COLORS.SOURCE, snapshot.snapshotId or "unknown")),
        string.format(
            "%s  %s   %s  %s   %s  %s   %s  %s",
            Format.Label("Source:"),
            Format.Colorize(Format.COLORS.SOURCE, snapshot.source or "unknown"),
            Format.Label("Region:"),
            Format.Colorize(Format.COLORS.SOURCE, snapshot.region or "US"),
            Format.Label("Date:"),
            Format.Colorize(Format.COLORS.SOURCE, snapshot.snapshotDate or "unknown"),
            Format.Label("Loaded from:"),
            Format.Colorize(Format.COLORS.SOURCE, sourceLabel)
        ),
        "",
    }

    local specRows = PVL.GetFilteredImportedSpecRows(classToken, specKey)
    if PVL.IsImportedSpecBreakdownMissing(bracket) then
        local bracketName = PVL.BRACKET_NAMES[bracket] or "This bracket"
        table.insert(lines, Format.Muted(string.format("%s uses one combined ladder on Battle.net.", bracketName)))
        table.insert(lines, Format.Muted("Imported class/spec breakdown is not available for this bracket."))
        if snapshot.overall then
            table.insert(lines, Format.StatLine("Listed players", Format.Count(snapshot.overall.listedCount)))
            table.insert(lines, Format.StatLine("Average rating", Format.Rating(snapshot.overall.avgListedRating)))
        end
        return table.concat(lines, "\n")
    end

    if not classToken and not specKey then
        local classRows = PVL.GetImportedClassRows()
        if #classRows == 0 then
            table.insert(lines, Format.Muted("No imported class breakdown is available for this bracket."))
            return table.concat(lines, "\n")
        end

        table.insert(lines, Format.Label("Listed ladder by class"))
        table.insert(lines, "")
        for _, row in ipairs(classRows) do
            local header, stats = Format.ClassSnapshotLines(row)
            table.insert(lines, header)
            table.insert(lines, stats)
        end
        return table.concat(lines, "\n")
    end

    if classToken and not specKey then
        local classRow = PVL.GetImportedClassAggregate(classToken)
        if classRow then
            table.insert(lines, string.format(
                "%s  %s",
                Format.ClassName(classToken),
                Format.Label("all specs")
            ))
            table.insert(lines, string.format(
                "    %s listed   avg %s   share %s",
                Format.Count(classRow.listedCount),
                Format.Rating(classRow.avgListedRating),
                Format.Percent(PVL.GetImportedClassRepresentation(classToken))
            ))
            table.insert(lines, "")
        end
    end

    if #specRows == 0 then
        table.insert(lines, Format.Muted("No imported listed-ladder rows match the current filters."))
        return table.concat(lines, "\n")
    end

    for _, row in ipairs(specRows) do
        table.insert(lines, Format.SpecImportedLine(row.specKey, row.listedCount, row.avgListedRating, row.representation))
    end

    return table.concat(lines, "\n")
end

--- Toggles the main frame visibility.
function UI.Toggle()
    local frame = UI.CreateMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        UI.Show()
    end
end

--- Refreshes all text regions and dropdowns from current database state.
function UI.Refresh()
    local frame = UI.CreateMainFrame()
    local filters = UI.GetFilters()
    local summary = PVL.BuildDashboardSummary()

    if frame.refreshBracketDropdown then
        frame.refreshBracketDropdown()
    end
    if frame.refreshClassDropdown then
        frame.refreshClassDropdown()
    end
    if frame.refreshSpecDropdown then
        frame.refreshSpecDropdown()
    end
    if frame.refreshMatchDropdown then
        frame.refreshMatchDropdown()
    end
    if frame.refreshCombatStatDropdown then
        frame.refreshCombatStatDropdown()
    end

    if summary.imported then
        frame.regionLabel:SetText(string.format(
            "Region: %s | Bracket: %s",
            summary.imported.region or "US",
            summary.imported.bracket or "blitz"
        ))
    else
        local bracketName = PVL.BRACKET_NAMES[summary.bracket] or summary.bracket or "PvP"
        frame.regionLabel:SetText(string.format("Region: -- | Bracket: %s", bracketName))
    end

    frame.setSummaryText(UI.BuildSummaryText(summary))
    UI.UpdateDetailPanels(frame, filters)
    UI.UpdateMatchDetailPanel(frame, filters)
end

--- Shows the main frame.
function UI.Show()
    local frame = UI.CreateMainFrame()
    if PVL.RatedInfo then
        PVL.RatedInfo.RequestUpdate()
        PVL.RatedInfo.RefreshAll()
    end
    if PVL.CrHistory then
        PVL.CrHistory.RecordAllSnapshots()
    end
    UI.Refresh()
    frame:Show()
end

--- Hides the main frame.
function UI.Hide()
    if UI.frame then
        UI.frame:Hide()
    end
end
