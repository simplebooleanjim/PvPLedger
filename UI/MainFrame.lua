--- Main window with class/spec filters and a spec detail card.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI
local Format = UI.Format

UI.frame = UI.frame or nil
local UI_LAYOUT_VERSION = 31

local FRAME_WIDTH = 720
local FRAME_HEIGHT = 580
local CONTENT_PAD_LEFT = 12
local CONTENT_PAD_RIGHT = 12
local CONTENT_PAD_BOTTOM = 12
local FILTER_ROW_Y = -34
local DROPDOWN_MENU_INSET = 16
local COLUMN_GAP = 12
local MIDDLE_SECTION_HEIGHT = 228
local MATCH_DROPDOWN_HEIGHT = 28
local BOTTOM_SECTION_GAP = 12
local FILTER_LABEL_TO_DROPDOWN_GAP = 4
local FILTER_DROPDOWN_TO_SECTION_GAP = 12
local VIEW_LADDER_BUTTON_WIDTH = 56
local VIEW_LADDER_BUTTON_HEIGHT = 22
local TITLES_BUTTON_WIDTH = 52
local FILTER_BUTTON_GAP = 4
local SPEC_DROPDOWN_WIDTH = 170

--- Returns the inset content host for a framed window.
--- @param hostFrame Frame
--- @return Frame
local function GetContentHost(hostFrame)
    return hostFrame.Inset or hostFrame
end

--- Returns layout metrics for the main frame.
--- @return table|nil
function UI.GetMainFrameLayout()
    if UI.frame and UI.frame.layout then
        return UI.frame.layout
    end

    return nil
end

--- Returns the left edge X offset for one of the three top content columns.
--- @param columnIndex number 1=left, 2=middle, 3=right
--- @return number
function UI.GetTopColumnOffset(columnIndex)
    local layout = UI.GetMainFrameLayout()
    if layout then
        if columnIndex <= 1 then
            return layout.contentPadLeft
        end

        return layout.contentPadLeft + ((columnIndex - 1) * (layout.tripleColWidth + COLUMN_GAP))
    end

    local contentWidth = FRAME_WIDTH - 20 - CONTENT_PAD_LEFT - CONTENT_PAD_RIGHT
    local tripleColWidth = math.floor((contentWidth - (COLUMN_GAP * 2)) / 3)
    if columnIndex <= 1 then
        return CONTENT_PAD_LEFT
    end

    return CONTENT_PAD_LEFT + ((columnIndex - 1) * (tripleColWidth + COLUMN_GAP))
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
    if PVL.RequestUiRefresh then
        PVL.RequestUiRefresh()
    else
        UI.Refresh()
    end
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

    if PVL.RequestUiRefresh then
        PVL.RequestUiRefresh()
    else
        UI.Refresh()
    end
end

--- Applies a spec filter and aligns the class filter when needed.
--- @param specKey string|nil
function UI.SetSpecFilter(specKey)
    local filters = UI.GetFilters()
    filters.specKey = specKey

    if specKey then
        filters.classToken = specKey:match("^(.-)_")
    end

    if PVL.RequestUiRefresh then
        PVL.RequestUiRefresh()
    else
        UI.Refresh()
    end
end

--- Registers events that should refresh personal panels when the player changes spec.
function UI.EnsureSpecRefreshEvents()
    if UI.specRefreshFrame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:SetScript("OnEvent", function()
        if UI.frame and UI.frame:IsShown() and PVL.RequestUiRefresh then
            PVL.RequestUiRefresh()
        end
    end)

    UI.specRefreshFrame = frame
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

    UI.AddWindowLogo(frame)
    UI.AddWindowWatermark(frame, 280)

    local contentHost = GetContentHost(frame)
    local hostWidth = contentHost:GetWidth()
    if not hostWidth or hostWidth <= 0 then
        hostWidth = FRAME_WIDTH - 10
    end

    local contentWidth = hostWidth - CONTENT_PAD_LEFT - CONTENT_PAD_RIGHT
    local tripleColWidth = math.floor((contentWidth - (COLUMN_GAP * 2)) / 3)
    local columnWidth = math.floor((contentWidth - COLUMN_GAP) / 2)

    frame.layout = {
        contentPadLeft = CONTENT_PAD_LEFT,
        contentPadRight = CONTENT_PAD_RIGHT,
        contentPadBottom = CONTENT_PAD_BOTTOM,
        contentWidth = contentWidth,
        tripleColWidth = tripleColWidth,
        columnWidth = columnWidth,
    }

    --- @param columnIndex number
    --- @return number
    local function GetColumnOffset(columnIndex)
        if columnIndex <= 1 then
            return CONTENT_PAD_LEFT
        end

        return CONTENT_PAD_LEFT + ((columnIndex - 1) * (tripleColWidth + COLUMN_GAP))
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("PvPLedger")

    frame.bracketLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.bracketLabel:SetPoint("TOPLEFT", contentHost, "TOPLEFT", CONTENT_PAD_LEFT, FILTER_ROW_Y)
    frame.bracketLabel:SetText(PVL.L("UI.FILTER.BRACKET"))

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
    frame.bracketDropdown:SetPoint("TOPLEFT", frame.bracketLabel, "BOTTOMLEFT", -DROPDOWN_MENU_INSET, -FILTER_LABEL_TO_DROPDOWN_GAP)

    frame.classLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.classLabel:SetPoint("LEFT", frame.bracketLabel, "LEFT", 190, 0)
    frame.classLabel:SetText(PVL.L("UI.FILTER.CLASS"))

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
    frame.classDropdown:SetPoint("TOPLEFT", frame.classLabel, "BOTTOMLEFT", -DROPDOWN_MENU_INSET, -FILTER_LABEL_TO_DROPDOWN_GAP)

    frame.specLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.specLabel:SetPoint("LEFT", frame.classLabel, "LEFT", 170, 0)
    frame.specLabel:SetText(PVL.L("UI.FILTER.SPEC"))

    frame.specDropdown, frame.refreshSpecDropdown = UI.CreateDropdown(
        frame,
        "PvPLedgerSpecDropdown",
        SPEC_DROPDOWN_WIDTH,
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
    frame.specDropdown:SetPoint("TOPLEFT", frame.specLabel, "BOTTOMLEFT", -DROPDOWN_MENU_INSET, -FILTER_LABEL_TO_DROPDOWN_GAP)

    frame.viewLadderButton = CreateFrame("Button", "PvPLedgerViewLadderButton", frame, "UIPanelButtonTemplate")
    frame.viewLadderButton:SetSize(VIEW_LADDER_BUTTON_WIDTH, VIEW_LADDER_BUTTON_HEIGHT)
    frame.viewLadderButton:SetPoint("RIGHT", contentHost, "RIGHT", -CONTENT_PAD_RIGHT, 0)
    frame.viewLadderButton:SetPoint("CENTER", frame.specDropdown, "CENTER", 0, 0)
    frame.viewLadderButton:SetText(PVL.L("UI.BUTTON.LADDER"))
    frame.viewLadderButton:SetScript("OnClick", function()
        if UI.LadderView then
            UI.LadderView.Show()
        end
    end)

    frame.viewTitlesButton = CreateFrame("Button", "PvPLedgerViewTitlesButton", frame, "UIPanelButtonTemplate")
    frame.viewTitlesButton:SetSize(TITLES_BUTTON_WIDTH, VIEW_LADDER_BUTTON_HEIGHT)
    frame.viewTitlesButton:SetPoint("RIGHT", frame.viewLadderButton, "LEFT", -FILTER_BUTTON_GAP, 0)
    frame.viewTitlesButton:SetPoint("CENTER", frame.viewLadderButton, "CENTER", 0, 0)
    frame.viewTitlesButton:SetText(PVL.L("UI.BUTTON.TITLES"))
    frame.viewTitlesButton:SetScript("OnClick", function()
        if UI.TitleView then
            UI.TitleView.Show()
        end
    end)

    frame.regionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.regionLabel:SetPoint("TOPRIGHT", contentHost, "TOPRIGHT", -CONTENT_PAD_RIGHT, FILTER_ROW_Y)
    frame.regionLabel:SetJustifyH("RIGHT")

    frame.sectionStart = CreateFrame("Frame", nil, frame)
    frame.sectionStart:SetHeight(1)
    frame.sectionStart:SetPoint("TOP", frame.specDropdown, "BOTTOM", 0, -FILTER_DROPDOWN_TO_SECTION_GAP)
    frame.sectionStart:SetPoint("LEFT", contentHost, "LEFT", 0, 0)
    frame.sectionStart:SetPoint("RIGHT", contentHost, "RIGHT", 0, 0)

    frame.summaryHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.summaryHeader:SetPoint("TOPLEFT", frame.sectionStart, "BOTTOMLEFT", GetColumnOffset(1), 0)
    frame.summaryHeader:SetText(Format.Header(PVL.L("UI.SECTION.OVERVIEW")))

    frame.summaryScroll, frame.setSummaryText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerSummaryScroll",
        frame.summaryHeader,
        frame,
        frame,
        nil,
        MIDDLE_SECTION_HEIGHT,
        tripleColWidth
    )
    frame.summaryScroll:ClearAllPoints()
    frame.summaryScroll:SetPoint("TOPLEFT", frame.summaryHeader, "BOTTOMLEFT", 0, -8)
    frame.summaryScroll:SetSize(tripleColWidth, MIDDLE_SECTION_HEIGHT)

    frame.crHistoryHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.crHistoryHeader:SetPoint("TOPLEFT", frame.sectionStart, "BOTTOMLEFT", GetColumnOffset(2), 0)
    frame.crHistoryHeader:SetText(Format.Header(PVL.LABELS.CR_HISTORY))

    frame.crHistoryScroll, frame.setCrHistoryText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerCrHistoryScroll",
        frame.crHistoryHeader,
        frame,
        frame,
        nil,
        MIDDLE_SECTION_HEIGHT,
        tripleColWidth
    )
    frame.crHistoryScroll:ClearAllPoints()
    frame.crHistoryScroll:SetPoint("TOPLEFT", frame.crHistoryHeader, "BOTTOMLEFT", 0, -8)
    frame.crHistoryScroll:SetSize(tripleColWidth, MIDDLE_SECTION_HEIGHT)

    frame.specDetailHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.specDetailHeader:SetPoint("TOPLEFT", frame.sectionStart, "BOTTOMLEFT", GetColumnOffset(3), 0)
    frame.specDetailHeader:SetWidth(tripleColWidth)
    frame.specDetailHeader:SetJustifyH("LEFT")
    frame.specDetailHeader:SetText(Format.Header(PVL.L("UI.SECTION.CLASS_BREAKDOWN")))

    frame.specDetailScroll, frame.setSpecDetailText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerSpecDetailScroll",
        frame.specDetailHeader,
        frame,
        frame,
        nil,
        MIDDLE_SECTION_HEIGHT,
        tripleColWidth
    )
    frame.specDetailScroll:ClearAllPoints()
    frame.specDetailScroll:SetPoint("TOPLEFT", frame.specDetailHeader, "BOTTOMLEFT", 0, -8)
    frame.specDetailScroll:SetSize(tripleColWidth, MIDDLE_SECTION_HEIGHT)

    frame.topRowBottom = CreateFrame("Frame", nil, frame)
    frame.topRowBottom:SetPoint("TOPLEFT", frame.summaryScroll, "BOTTOMLEFT", 0, -4)
    frame.topRowBottom:SetPoint("TOPRIGHT", frame.specDetailScroll, "BOTTOMRIGHT", 0, -4)
    frame.topRowBottom:SetHeight(1)

    frame.matchDetailHeader = UI.CreateSectionHeader(
        frame,
        PVL.L("UI.SECTION.MATCH_DETAIL"),
        { "TOPLEFT", frame.topRowBottom, "BOTTOMLEFT", 0, -BOTTOM_SECTION_GAP }
    )

    frame.combatAnalysisHeader = UI.CreateSectionHeader(
        frame,
        PVL.L("UI.SECTION.COMBAT_ANALYSIS"),
        { "TOPLEFT", frame.matchDetailHeader, "TOPLEFT", columnWidth + COLUMN_GAP, 0 }
    )

    frame.leftColumnBottom = CreateFrame("Frame", nil, frame)
    frame.leftColumnBottom:SetPoint("BOTTOMLEFT", contentHost, "BOTTOMLEFT", CONTENT_PAD_LEFT, CONTENT_PAD_BOTTOM)
    frame.leftColumnBottom:SetPoint("RIGHT", contentHost, "CENTER", -(COLUMN_GAP / 2), 0)
    frame.leftColumnBottom:SetHeight(1)

    frame.rightColumnBottom = CreateFrame("Frame", nil, frame)
    frame.rightColumnBottom:SetPoint("BOTTOMRIGHT", contentHost, "BOTTOMRIGHT", -CONTENT_PAD_RIGHT, CONTENT_PAD_BOTTOM)
    frame.rightColumnBottom:SetPoint("LEFT", contentHost, "CENTER", COLUMN_GAP / 2, 0)
    frame.rightColumnBottom:SetHeight(1)

    frame.matchDropdown, frame.refreshMatchDropdown = UI.CreateDropdown(
        frame,
        "PvPLedgerMatchDropdown",
        columnWidth - 8,
        function()
            return UI.GetRecentMatchOptions(nil, PVL.GetPersonalTrackingFilters())
        end,
        function()
            return UI.GetSelectedMatchIndex(nil, PVL.GetPersonalTrackingFilters())
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
        columnWidth - 8,
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
    UI.EnsureSpecRefreshEvents()
    return frame
end

--- Builds text for the character and overall summary block.
--- @param summary table
--- @return string
function UI.BuildSummaryText(summary)
    local lines = {}
    local bracketName = PVL.BRACKET_NAMES[summary.bracket] or summary.bracket or PVL.L("COMMON.PVP")

    table.insert(lines, string.format(
        "%s  %s",
        Format.Label(PVL.L("UI.SUMMARY.BRACKET_LABEL")),
        Format.Header(bracketName)
    ))

    if summary.specUnavailable then
        table.insert(lines, Format.Muted(PVL.L("UI.SUMMARY.SPEC_UNDETECTED")))
    elseif summary.specKey then
        table.insert(lines, Format.StatLine(PVL.L("UI.SUMMARY.CURRENT_SPEC"), Format.SpecShortName(summary.specKey)))
    end

    table.insert(lines, Format.StatLine(PVL.L("UI.SUMMARY.MATCHES_TRACKED"), Format.Count(summary.matchCount)))

    if summary.blizzardSeasonRecord then
        local blizzardLabel = PVL.L("UI.SUMMARY.BLIZZARD_SEASON")
        if summary.bracket == PVL.BRACKETS.SHUFFLE then
            blizzardLabel = PVL.L("UI.SUMMARY.BLIZZARD_SEASON_ROUNDS")
        end

        local specSuffix = summary.specKey and (" (" .. Format.SpecShortName(summary.specKey) .. ")") or ""
        table.insert(lines, Format.StatLine(
            blizzardLabel .. specSuffix,
            string.format(
                "%s  %s  %s",
                Format.WinLossRecord(summary.blizzardSeasonRecord.wins, summary.blizzardSeasonRecord.losses),
                Format.WinPercent(summary.blizzardSeasonRecord.wins, summary.blizzardSeasonRecord.losses),
                Format.Muted(PVL.L("UI.SUMMARY.UNIT_MATCH", Format.Count(summary.blizzardSeasonRecord.games)))
            )
        ))
    end

    local recordLabel = PVL.L("UI.SUMMARY.TRACKED_RECORD")
    local winRateLabel = PVL.L("UI.SUMMARY.TRACKED_WIN_RATE")
    if summary.bracket == PVL.BRACKETS.SHUFFLE then
        recordLabel = PVL.L("UI.SUMMARY.TRACKED_ROUNDS")
        winRateLabel = PVL.L("UI.SUMMARY.TRACKED_ROUND_WIN_RATE")
    end

    if summary.seasonRecord then
        local specSuffix = summary.specKey and (" (" .. Format.SpecShortName(summary.specKey) .. ")") or ""
        table.insert(lines, Format.StatLine(
            recordLabel .. specSuffix,
            string.format(
                "%s  %s",
                Format.WinLossRecord(summary.seasonRecord.wins, summary.seasonRecord.losses),
                Format.Muted(PVL.L("UI.SUMMARY.LOGGED", Format.Count(summary.matchCount)))
            )
        ))
        table.insert(lines, Format.StatLine(
            winRateLabel,
            Format.WinPercent(summary.seasonRecord.wins, summary.seasonRecord.losses)
        ))
        if summary.bracket == PVL.BRACKETS.SHUFFLE
            and summary.seasonRecord.matchesPlayed
            and summary.seasonRecord.matchesPlayed > 0 then
            table.insert(lines, Format.StatLine(
                PVL.L("UI.SUMMARY.MATCHES_PLAYED"),
                Format.WinLossRecord(
                    summary.seasonRecord.matchesWon or 0,
                    math.max((summary.seasonRecord.matchesPlayed or 0) - (summary.seasonRecord.matchesWon or 0), 0)
                )
            ))
        end
    elseif summary.specUnavailable then
        table.insert(lines, Format.Muted(PVL.L("UI.SUMMARY.SELECT_SPEC_STATS")))
    elseif summary.specKey then
        table.insert(lines, Format.Muted(PVL.L(
            "UI.SUMMARY.NO_TRACKED_MATCHES_SPEC",
            Format.SpecShortName(summary.specKey)
        )))
    end

    table.insert(lines, Format.StatLine(PVL.L("UI.SUMMARY.LATEST_CR"), Format.Rating(summary.playerCurrentCR)))

    if summary.playerMMRKind == "team" then
        if PVL.IsValidObservedMmr(summary.playerPersonalMMR) then
            table.insert(lines, Format.StatLine(PVL.LABELS.PERSONAL_MMR, Format.Rating(summary.playerPersonalMMR)))
        end
        if PVL.IsValidObservedMmr(summary.playerMMR) then
            table.insert(lines, Format.StatLine(PVL.LABELS.TEAM_AVG_MMR, Format.Rating(summary.playerMMR)))
        end
    elseif PVL.IsValidObservedMmr(summary.playerMMR) then
        table.insert(lines, Format.StatLine(PVL.LABELS.PERSONAL_MMR, Format.Rating(summary.playerMMR)))
    end

    local standingLabel = "--"
    if summary.standing then
        standingLabel = PVL.FormatStandingLabel(summary.standing)
    elseif (summary.playerCurrentCR or summary.playerCR) and PVL.GetImportedSnapshot(summary.bracket) then
        standingLabel = PVL.L("STANDING.UNLISTED")
    end

    table.insert(lines, Format.StatLine(
        PVL.L("UI.SUMMARY.ESTIMATED_STANDING"),
        Format.Colorize(Format.COLORS.STANDING, standingLabel)
    ))

    if summary.standing then
        if summary.standing.isEstimated and summary.standing.estimatedRank and not summary.standing.isListed then
            if summary.ladderStalenessLines and #summary.ladderStalenessLines > 0 then
                table.insert(lines, Format.Muted(
                    PVL.L("UI.SUMMARY.NOT_IN_SNAPSHOT")
                ))
            else
                table.insert(lines, Format.Muted(
                    PVL.L("UI.SUMMARY.NOT_IN_SNAPSHOT_ESTIMATE")
                ))
            end
        elseif summary.standing.isEstimated
            and summary.standing.isListed
            and summary.standing.snapshotRank
            and summary.standing.snapshotRating then
            table.insert(lines, Format.Muted(PVL.L(
                "UI.SUMMARY.SNAPSHOT_RANK_HINT",
                PVL.FormatRating(summary.standing.snapshotRank),
                PVL.FormatRating(summary.standing.snapshotRating)
            )))
        end
    end

    if summary.ladderStalenessLines then
        for _, hintLine in ipairs(summary.ladderStalenessLines) do
            table.insert(lines, Format.Colorize(Format.COLORS.WARNING, hintLine))
        end
    end

    if summary.importedOverall then
        table.insert(lines, "")
        table.insert(lines, Format.Divider(190))
        table.insert(lines, Format.SectionLabel(PVL.L("UI.SUMMARY.LADDER_SNAPSHOT")))
        table.insert(lines, Format.StatLine(
            PVL.L("UI.SUMMARY.SOURCE"),
            Format.Colorize(Format.COLORS.SOURCE, summary.imported.source or PVL.L("COMMON.UNKNOWN"))
        ))
        table.insert(lines, Format.StatLine(
            PVL.L("UI.SUMMARY.SNAPSHOT_DATE"),
            Format.Colorize(Format.COLORS.SOURCE, summary.imported.snapshotDate or PVL.L("COMMON.UNKNOWN"))
        ))
        table.insert(lines, Format.StatLine(
            PVL.L("UI.SUMMARY.LOADED_FROM"),
            Format.Colorize(Format.COLORS.SOURCE, PVL.FormatLadderSourceLabel(PVL.GetSnapshotSource(summary.bracket)))
        ))
        if summary.importedPlayerCount and summary.importedPlayerCount > 0 then
            table.insert(lines, Format.StatLine(PVL.L("UI.SUMMARY.INDEXED_PLAYERS"), Format.Count(summary.importedPlayerCount)))
        end
        if summary.observedPlayerCount and summary.observedPlayerCount > 0 then
            table.insert(lines, Format.StatLine(
                PVL.L("UI.SUMMARY.OBSERVED_ON_LADDER"),
                string.format("%s / %s", Format.Count(summary.listedObservedCount or 0), Format.Count(summary.observedPlayerCount))
            ))
        end
        Format.AppendBlockGap(lines)
        Format.AppendImportedRatingStats(lines, summary.importedOverall)
    else
        table.insert(lines, "")
        table.insert(lines, Format.Muted(PVL.L("UI.SUMMARY.NO_LADDER_DATA")))
        for _, hintLine in ipairs(PVL.GetLadderStalenessLines(summary.bracket)) do
            table.insert(lines, Format.Colorize(Format.COLORS.WARNING, hintLine))
        end
    end

    return table.concat(lines, "\n")
end

--- Builds CR history text for the detail panel.
--- @param bracket string|nil
--- @param filters table|nil Optional `{ classToken, specKey }` player-spec filters.
--- @return string
function UI.BuildCrHistoryText(bracket, filters)
    if not PVL.CrHistory then
        return Format.Muted(PVL.L("UI.CR_HISTORY.UNAVAILABLE"))
    end

    bracket = bracket or PVL.GetActiveBracketFilter()
    filters = filters or PVL.GetPersonalTrackingFilters()
    local summary = PVL.CrHistory.BuildSummary(bracket, filters)
    local lines = {
        Format.StatLine(PVL.LABELS.CR_PEAK, Format.Rating(summary.peakCr)),
        Format.StatLine(PVL.LABELS.CR_LOW, Format.Rating(summary.lowCr)),
        Format.StatLine(PVL.LABELS.CR_NET_7D, PVL.CrHistory.FormatDelta(summary.net7d)),
        Format.StatLine(PVL.LABELS.CR_NET_SESSION, PVL.CrHistory.FormatDelta(summary.netSession)),
        Format.StatLine(
            PVL.L("UI.CR_HISTORY.SESSION_RECORD"),
            string.format(
                "%s  %s",
                Format.WinLossRecord(summary.winsSession, summary.lossesSession),
                Format.Muted(PVL.L("UI.CR_HISTORY.GAMES", Format.Count(summary.gamesSession)))
            )
        ),
        "",
    }

    if #summary.recentEntries == 0 then
        if summary.specUnavailable then
            table.insert(lines, Format.Muted(PVL.L("UI.CR_HISTORY.SELECT_SPEC")))
        elseif summary.specKey then
            table.insert(lines, Format.Muted(PVL.L(
                "UI.CR_HISTORY.NONE_SPEC",
                Format.SpecShortName(summary.specKey)
            )))
        else
            table.insert(lines, Format.Muted(PVL.L("UI.CR_HISTORY.NONE")))
            table.insert(lines, Format.Muted(PVL.L("UI.CR_HISTORY.START_HINT")))
        end
        return table.concat(lines, "\n")
    end

    table.insert(lines, Format.Divider(190))
    table.insert(lines, Format.SectionLabel(PVL.L("UI.CR_HISTORY.RECENT_ACTIVITY")))
    table.insert(lines, "")

    for _, entry in ipairs(summary.recentEntries) do
        table.insert(lines, Format.RecentActivityLine(entry))
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

--- Appends the current player spec label to one section header.
--- @param headerText string
--- @param personalFilters table
--- @return string
function UI.AppendPlayerSpecHeader(headerText, personalFilters)
    if personalFilters.specKey then
        return headerText .. "  " .. Format.SpecShortName(personalFilters.specKey)
    end

    return headerText
end

--- Updates the top-row detail panels.
--- @param frame Frame
--- @param ladderFilters table Ladder/class breakdown filters from the UI dropdowns.
--- @param personalFilters table Player-spec filters for personal tracking panels.
function UI.UpdateDetailPanels(frame, ladderFilters, personalFilters)
    local bracket = ladderFilters.bracket or PVL.GetActiveBracketFilter()

    frame.summaryHeader:SetText(UI.AppendPlayerSpecHeader(Format.Header(PVL.L("UI.SECTION.OVERVIEW")), personalFilters))
    frame.crHistoryHeader:SetText(UI.AppendPlayerSpecHeader(Format.Header(PVL.LABELS.CR_HISTORY), personalFilters))

    local specHeader = Format.Header(PVL.L("UI.SECTION.CLASS_BREAKDOWN"))
    if ladderFilters.specKey then
        local classToken = ladderFilters.specKey:match("^(.-)_")
        specHeader = Format.ClassIcon(classToken) .. Format.SpecShortName(ladderFilters.specKey)
    elseif ladderFilters.classToken then
        specHeader = Format.ClassIcon(ladderFilters.classToken) .. Format.ClassName(ladderFilters.classToken)
    end
    frame.specDetailHeader:SetText(specHeader)
    frame.setCrHistoryText(UI.BuildCrHistoryText(bracket, personalFilters))
    frame.setSpecDetailText(UI.BuildSpecDetailPanelText(ladderFilters.classToken, ladderFilters.specKey))
end

--- Updates the bottom match review panels for the selected match.
--- @param frame Frame
--- @param ladderFilters table Ladder/class breakdown filters from the UI dropdowns.
--- @param personalFilters table Player-spec filters for personal tracking panels.
function UI.UpdateMatchDetailPanel(frame, ladderFilters, personalFilters)
    local bracket = ladderFilters.bracket or PVL.GetActiveBracketFilter()
    local selectedMatch = UI.ResolveSelectedMatch(bracket, personalFilters)

    frame.matchDetailHeader:SetText(UI.AppendPlayerSpecHeader(Format.Header(PVL.L("UI.SECTION.MATCH_DETAIL")), personalFilters))
    frame.combatAnalysisHeader:SetText(UI.AppendPlayerSpecHeader(Format.Header(PVL.L("UI.SECTION.COMBAT_ANALYSIS")), personalFilters))
    frame.setMatchDetailText(UI.BuildMatchDetailText(selectedMatch))

    local statDef = UI.GetCombatStatDefinition(ladderFilters.combatStat)
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
    local lines = {}

    if PVL.IsImportedSpecBreakdownMissing(bracket) then
        local bracketName = PVL.BRACKET_NAMES[bracket] or PVL.L("COMMON.THIS_BRACKET")
        table.insert(lines, Format.Muted(PVL.L(
            "UI.SPEC.COMBINED_LADDER",
            bracketName
        )))
        table.insert(lines, Format.Muted(PVL.L(
            "UI.SPEC.SELECT_CLASS_OBSERVED",
            bracketName
        )))
        return table.concat(lines, "\n")
    end

    if #classRows == 0 then
        table.insert(lines, Format.Muted(PVL.L("UI.SPEC.NO_CLASS_BREAKDOWN")))
        return table.concat(lines, "\n")
    end

    table.insert(lines, Format.SectionLabel(PVL.L("UI.SPEC.LISTED_BY_CLASS")))
    table.insert(lines, "")

    for index, row in ipairs(classRows) do
        local header, shareLine, statsLine = Format.ClassOverviewLines(row)
        table.insert(lines, header)
        table.insert(lines, shareLine)
        table.insert(lines, statsLine)
        if index < #classRows then
            Format.AppendBlockGap(lines)
        end
    end

    table.insert(lines, "")
    table.insert(lines, Format.Muted(PVL.L("UI.SPEC.SELECT_CLASS_DRILL")))

    return table.concat(lines, "\n")
end

--- Builds text for one selected class with all specs.
--- @param classToken string
--- @return string
function UI.BuildClassDetailText(classToken)
    local detail = PVL.BuildClassDetailSummary(classToken)
    if not detail then
        return Format.Muted(PVL.L("UI.SPEC.NO_DETAIL_CLASS"))
    end

    local lines = {}

    if detail.imported then
        Format.AppendImportedStats(lines, detail.imported, detail.importedRepresentation, true)
    elseif PVL.IsImportedSpecBreakdownMissing() then
        table.insert(lines, Format.Muted(PVL.L(
            "UI.SPEC.NO_IMPORTED_CLASS",
            PVL.BRACKET_NAMES[PVL.GetActiveBracketFilter()] or PVL.L("COMMON.THIS_BRACKET")
        )))
    else
        table.insert(lines, Format.Muted(PVL.L("UI.SPEC.NO_IMPORTED_LISTED")))
    end

    if detail.importedSpecRows and #detail.importedSpecRows > 0 then
        table.insert(lines, "")
        table.insert(lines, Format.SectionLabel(PVL.L("UI.SPEC.LISTED_SPECS")))
        for specIndex, row in ipairs(detail.importedSpecRows) do
            local header, detailLine = Format.SpecOverviewLines(
                row.specKey,
                row.listedCount,
                row.avgListedRating,
                row.representation
            )
            table.insert(lines, header)
            table.insert(lines, detailLine)
            if specIndex < #detail.importedSpecRows then
                Format.AppendBlockGap(lines)
            end
        end
    end

    table.insert(lines, "")
    table.insert(lines, Format.StatLine(
        PVL.LABELS.OBSERVED,
        string.format("%s  %s", Format.Count(detail.observedCount), Format.Percent(detail.observedPercent))
    ))

    if detail.observedSpecRows and #detail.observedSpecRows > 0 then
        table.insert(lines, "")
        table.insert(lines, Format.SectionLabel(PVL.L("UI.SPEC.OBSERVED_SPECS")))
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
        return Format.Muted(PVL.L("UI.SPEC.SELECT_TO_COMPARE"))
    end

    local detail = PVL.BuildSpecDetailSummary(specKey)
    if not detail then
        return Format.Muted(PVL.L("UI.SPEC.NO_DETAIL_SPEC"))
    end

    local lines = {}

    if detail.imported then
        Format.AppendImportedStats(lines, detail.imported, detail.importedRepresentation, true)
    elseif PVL.IsImportedSpecBreakdownMissing() then
        table.insert(lines, Format.Muted(PVL.L(
            "UI.SPEC.COMBINED_SPEC",
            PVL.BRACKET_NAMES[PVL.GetActiveBracketFilter()] or PVL.L("COMMON.THIS_BRACKET")
        )))
    else
        table.insert(lines, Format.Muted(PVL.L("UI.SPEC.NO_IMPORTED_SPEC")))
    end

    table.insert(lines, "")
    table.insert(lines, Format.StatLine(
        PVL.LABELS.OBSERVED,
        string.format("%s  %s", Format.Count(detail.observedCount), Format.Percent(detail.observedPercent))
    ))

    return table.concat(lines, "\n")
end

--- Returns whether any PvPLedger window is currently visible.
--- @return boolean
function UI.AnyWindowShown()
    if UI.frame and UI.frame:IsShown() then
        return true
    end

    if UI.LadderView and UI.LadderView.frame and UI.LadderView.frame:IsShown() then
        return true
    end

    if UI.TitleView and UI.TitleView.frame and UI.TitleView.frame:IsShown() then
        return true
    end

    return false
end

--- Hides every PvPLedger window (main, ladder, title cutoffs).
function UI.CloseAll()
    if UI._closingAll then
        return
    end

    UI._closingAll = true

    if UI.TitleView and UI.TitleView.Hide then
        UI.TitleView.Hide()
    end

    if UI.LadderView and UI.LadderView.Hide then
        UI.LadderView.Hide()
    end

    if UI.frame then
        UI.frame:Hide()
    end

    UI._closingAll = false
end

--- Toggles all PvPLedger windows: closes everything when any are open, otherwise opens the main window.
function UI.Toggle()
    if UI.AnyWindowShown() then
        UI.CloseAll()
        return
    end

    if PVL.CanOpenAddonWindows and not PVL.CanOpenAddonWindows() then
        return
    end

    UI.Show()
end

--- Refreshes all text regions and dropdowns from current database state.
function UI.Refresh()
    if PVL.IsCombatLocked and PVL.IsCombatLocked() then
        if PVL.EnsureCombatLockEvents then
            PVL._pendingUiRefresh = true
            PVL.EnsureCombatLockEvents()
        end
        return
    end

    local frame = UI.CreateMainFrame()
    local ladderFilters = UI.GetFilters()
    local personalFilters = PVL.GetPersonalTrackingFilters()
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
        frame.regionLabel:SetText(PVL.L(
            "UI.REGION_BRACKET_FORMAT",
            summary.imported.region or PVL.GetActiveLadderRegion(),
            summary.imported.bracket or "blitz"
        ))
    else
        local bracketName = PVL.BRACKET_NAMES[summary.bracket] or summary.bracket or PVL.L("COMMON.PVP")
        frame.regionLabel:SetText(PVL.L(
            "UI.REGION_BRACKET_FORMAT",
            PVL.GetActiveLadderRegion(),
            bracketName
        ))
    end

    frame.setSummaryText(UI.BuildSummaryText(summary))
    UI.UpdateDetailPanels(frame, ladderFilters, personalFilters)
    UI.UpdateMatchDetailPanel(frame, ladderFilters, personalFilters)

    if UI.LadderView and UI.LadderView.frame and UI.LadderView.frame:IsShown() then
        UI.LadderView.Refresh()
    end

    if UI.TitleView and UI.TitleView.frame and UI.TitleView.frame:IsShown() then
        UI.TitleView.Refresh()
    end
end

--- Shows the main frame.
function UI.Show()
    if PVL.CanOpenAddonWindows and not PVL.CanOpenAddonWindows() then
        return
    end

    local frame = UI.CreateMainFrame()

    if PVL.RatedInfo then
        pcall(PVL.RatedInfo.RequestUpdate)
        pcall(PVL.RatedInfo.RefreshAll)
    end

    frame:Show()
    if frame.Raise then
        frame:Raise()
    end

    local ok, err = pcall(UI.Refresh)
    if not ok then
        print(string.format(
            "|cff66ccffPvPLedger|r: %s",
            PVL.L("UI.MAIN.RENDER_ERROR", tostring(err))
        ))
    end
end

--- Hides every PvPLedger window.
function UI.Hide()
    UI.CloseAll()
end
