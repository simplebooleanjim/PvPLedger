--- Main window with class/spec filters and a spec detail card.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI

UI.frame = UI.frame or nil
local UI_LAYOUT_VERSION = 3

local FRAME_WIDTH = 720
local FRAME_HEIGHT = 560
local PADDING = 16
local COLUMN_GAP = 12
local COLUMN_WIDTH = math.floor((FRAME_WIDTH - (PADDING * 2) - COLUMN_GAP) / 2)
local CONTENT_WIDTH = FRAME_WIDTH - (PADDING * 2)

--- Returns persisted UI filter settings.
--- @return table
function UI.GetFilters()
    local db = PVL.GetDB()
    db.settings.uiFilters = db.settings.uiFilters or {}
    return db.settings.uiFilters
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

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("PvPLedger")

    frame.classLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.classLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
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
    frame.classDropdown:SetPoint("TOPLEFT", frame.classLabel, "BOTTOMLEFT", -16, -2)

    frame.specLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.specLabel:SetPoint("LEFT", frame.classLabel, "LEFT", 190, 0)
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
    frame.specDropdown:SetPoint("TOPLEFT", frame.specLabel, "BOTTOMLEFT", -16, -2)

    frame.regionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.regionLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -34)
    frame.regionLabel:SetJustifyH("RIGHT")

    frame.summary = UI.CreateBodyText(frame, CONTENT_WIDTH, { "TOPLEFT", frame.classDropdown, "BOTTOMLEFT", 16, -12 })

    frame.detailHeader = UI.CreateSectionHeader(frame, "Spec Detail", { "TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -16 })
    frame.detailCard = UI.CreateBodyText(frame, CONTENT_WIDTH, { "TOPLEFT", frame.detailHeader, "BOTTOMLEFT", 0, -8 })

    frame.observedHeader = UI.CreateSectionHeader(frame, "Observed Spec Frequency", { "TOPLEFT", frame.detailCard, "BOTTOMLEFT", 0, -16 })

    frame.specListScroll, frame.setObservedListText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerObservedScroll",
        COLUMN_WIDTH,
        frame.observedHeader,
        { "BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING }
    )

    frame.importedHeader = UI.CreateSectionHeader(
        frame,
        "Imported Ladder Snapshot",
        { "TOPLEFT", frame.observedHeader, "TOPLEFT", COLUMN_WIDTH + COLUMN_GAP, 0 }
    )

    frame.importedListScroll, frame.setImportedListText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerImportedScroll",
        COLUMN_WIDTH,
        frame.importedHeader,
        { "BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING + COLUMN_WIDTH + COLUMN_GAP, PADDING }
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

    table.insert(lines, string.format("Tracked Blitz matches: %d", summary.matchCount or 0))
    table.insert(lines, string.format("Your last listed CR: %s", PVL.FormatRating(summary.playerCR)))
    table.insert(lines, string.format("Your last observed MMR: %s", PVL.FormatRating(summary.playerMMR)))

    if summary.standing then
        table.insert(lines, string.format("Estimated listed standing: %s", summary.standing.cutoffLabel))
    end

    if summary.importedOverall then
        table.insert(lines, "")
        table.insert(lines, string.format("%s: %s", PVL.LABELS.LISTED_AVG, PVL.FormatRating(summary.importedOverall.avgListedRating)))
        table.insert(lines, string.format("%s: %s", PVL.LABELS.LISTED_MEDIAN, PVL.FormatRating(summary.importedOverall.medianListedRating)))
        table.insert(lines, string.format("%s: %s", PVL.LABELS.TOP100_AVG, PVL.FormatRating(summary.importedOverall.top100Avg)))
    else
        table.insert(lines, "")
        table.insert(lines, "No imported ladder snapshot loaded.")
    end

    return table.concat(lines, "\n")
end

--- Builds text for the selected spec detail card.
--- @param specKey string|nil
--- @return string
function UI.BuildSpecDetailText(specKey)
    if not specKey then
        return "Select a spec from the dropdown to compare imported ladder stats against your observed match data."
    end

    local detail = PVL.BuildSpecDetailSummary(specKey)
    if not detail then
        return "No detail available for the selected spec."
    end

    local lines = {
        detail.displayName,
        "",
    }

    if detail.imported then
        table.insert(lines, string.format("%s: %d", PVL.LABELS.REPRESENTATION, detail.imported.listedCount or 0))
        table.insert(lines, string.format("%s: %s", PVL.LABELS.LISTED_AVG, PVL.FormatRating(detail.imported.avgListedRating)))
        table.insert(lines, string.format("%s: %s", PVL.LABELS.LISTED_MEDIAN, PVL.FormatRating(detail.imported.medianListedRating)))
        table.insert(lines, string.format("%s: %s", PVL.LABELS.TOP100_AVG, PVL.FormatRating(detail.imported.top100Avg)))
        table.insert(lines, string.format("Highest listed rating: %s", PVL.FormatRating(detail.imported.highest)))
        table.insert(lines, string.format("Share of listed ladder: %s", PVL.FormatPercent(detail.importedRepresentation)))
    else
        table.insert(lines, "No imported listed-ladder data for this spec yet.")
    end

    table.insert(lines, "")
    table.insert(lines, string.format(
        "%s: %d (%s)",
        PVL.LABELS.OBSERVED,
        detail.observedCount,
        PVL.FormatPercent(detail.observedPercent)
    ))

    return table.concat(lines, "\n")
end

--- Builds the observed spec list for the current filters.
--- @param classToken string|nil
--- @param specKey string|nil
--- @return string
function UI.BuildObservedListText(classToken, specKey)
    local observed = PVL.GetFilteredObservedSpecPercentages(classToken, specKey)
    if #observed == 0 then
        if classToken or specKey then
            return "No observed specs match the current filters yet."
        end
        return "No observed specs yet. Play Blitz matches to populate this panel."
    end

    local lines = {}
    for _, row in ipairs(observed) do
        table.insert(lines, string.format(
            "%s — %d (%s)",
            PVL.FormatSpecDisplayName(row.specKey),
            row.count,
            PVL.FormatPercent(row.percent)
        ))
    end

    return table.concat(lines, "\n")
end

--- Builds the imported snapshot list for the current filters.
--- @param classToken string|nil
--- @param specKey string|nil
--- @return string
function UI.BuildImportedListText(classToken, specKey)
    local snapshot = PVL.GetImportedSnapshot()
    if not snapshot then
        return "Run the external collector and replace Data/LadderData_US_Blitz.lua."
    end

    local lines = {
        string.format(
            "Snapshot: %s",
            snapshot.snapshotId or "unknown"
        ),
        string.format(
            "Region: %s | Date: %s",
            snapshot.region or "US",
            snapshot.snapshotDate or "unknown"
        ),
        "",
    }

    local specRows = PVL.GetFilteredImportedSpecRows(classToken, specKey)
    if #specRows == 0 then
        table.insert(lines, "No imported listed-ladder rows match the current filters.")
        return table.concat(lines, "\n")
    end

    for _, row in ipairs(specRows) do
        table.insert(lines, string.format(
            "%s — %d listed",
            PVL.FormatSpecDisplayName(row.specKey),
            row.listedCount
        ))
        table.insert(lines, string.format(
            "  avg %s | share %s",
            PVL.FormatRating(row.avgListedRating),
            PVL.FormatPercent(row.representation)
        ))
    end

    return table.concat(lines, "\n")
end

--- Toggles the main frame visibility.
function UI.Toggle()
    local frame = UI.CreateMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        UI.Refresh()
        frame:Show()
    end
end

--- Refreshes all text regions and dropdowns from current database state.
function UI.Refresh()
    local frame = UI.CreateMainFrame()
    local filters = UI.GetFilters()
    local summary = PVL.BuildDashboardSummary()

    if frame.refreshClassDropdown then
        frame.refreshClassDropdown()
    end
    if frame.refreshSpecDropdown then
        frame.refreshSpecDropdown()
    end

    if summary.imported then
        frame.regionLabel:SetText(string.format(
            "Region: %s | Bracket: %s",
            summary.imported.region or "US",
            summary.imported.bracket or "blitz"
        ))
    else
        frame.regionLabel:SetText("Region: -- | Bracket: blitz")
    end

    frame.summary:SetText(UI.BuildSummaryText(summary))
    frame.detailCard:SetText(UI.BuildSpecDetailText(filters.specKey))
    frame.setObservedListText(UI.BuildObservedListText(filters.classToken, filters.specKey))
    frame.setImportedListText(UI.BuildImportedListText(filters.classToken, filters.specKey))
end

--- Shows the main frame.
function UI.Show()
    local frame = UI.CreateMainFrame()
    UI.Refresh()
    frame:Show()
end

--- Hides the main frame.
function UI.Hide()
    if UI.frame then
        UI.frame:Hide()
    end
end
