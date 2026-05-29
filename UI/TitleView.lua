--- Title cutoff browser: shows the estimated rating to reach each seasonal title.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI
local Format = UI.Format

UI.TitleView = UI.TitleView or {}
local TitleView = UI.TitleView

TitleView.frame = TitleView.frame or nil
local TITLE_VIEW_LAYOUT_VERSION = 1

local FRAME_WIDTH = 520
local FRAME_HEIGHT = 480
local PADDING = 20

--- Returns a readable label describing the source of a cutoff rating.
--- @param source string|nil Resolution source from ResolveTitleCutoffRating.
--- @return string
local function SourceTag(source)
    if source == "estimated" then
        return Format.Muted(" (est.)")
    end

    return ""
end

--- Builds the right-aligned achievement/gap text for one title row.
--- @param row table Title cutoff row.
--- @return string
local function FormatProgress(row)
    if not row.cutoffRating then
        return Format.Muted("needs full ladder data")
    end

    if row.achieved == nil then
        return Format.Muted("your rating unknown")
    end

    if row.achieved then
        return Format.Colorize(Format.COLORS.STANDING, "Achieved")
    end

    return Format.Colorize(Format.COLORS.WARNING, string.format("+%s to go", PVL.FormatRating(row.gap)))
end

--- Builds the muted rule line describing how one title is earned.
--- @param row table Title cutoff row.
--- @return string
local function FormatRule(row)
    local def = row.def
    local parts = {}

    if def.kind == "percentile" then
        table.insert(parts, string.format("Top %s%% of ladder", def.percentile))
        if row.rank then
            table.insert(parts, string.format("~rank %s", PVL.FormatRating(row.rank)))
        end
    else
        table.insert(parts, string.format("%s rating", PVL.FormatRating(def.rating)))
    end

    if def.wins then
        table.insert(parts, string.format("%s wins", def.wins))
    end

    return Format.Muted("    " .. table.concat(parts, " · "))
end

--- Builds the scrollable body text for the title cutoff window.
--- @param bracket string|nil Bracket id; defaults to the active filter.
--- @return string
function TitleView.BuildText(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    local rows, context = PVL.BuildTitleCutoffRows(bracket)
    local bracketName = PVL.BRACKET_NAMES[bracket] or bracket or "PvP"

    local lines = {
        Format.Muted(bracketName),
        "",
    }

    local snapshot = context.snapshot
    if not snapshot then
        table.insert(lines, Format.Muted("No imported ladder snapshot is loaded for this bracket."))
        table.insert(lines, Format.Muted("Run /pvl update or install PvPLedger Sync for ladder data."))
        return table.concat(lines, "\n")
    end

    table.insert(lines, Format.StatLine(
        "Your current rating",
        Format.Rating(context.playerRating)
    ))
    if context.ratedPopulation then
        table.insert(lines, Format.StatLine(
            "Rated players",
            Format.Count(context.ratedPopulation)
        ))
    end
    table.insert(lines, Format.Muted(string.format(
        "Snapshot: %s%s · Source: %s",
        snapshot.snapshotDate or "--",
        snapshot.season and string.format(" · S%s", snapshot.season) or "",
        PVL.GetSnapshotSource(bracket) or snapshot.source or "unknown"
    )))

    if not context.hasExactCutoffs then
        if context.ratedPopulation then
            table.insert(lines, Format.Colorize(
                Format.COLORS.WARNING,
                "Percentile cutoffs are estimated from listed ranks. Refresh for exact values."
            ))
        else
            table.insert(lines, Format.Colorize(
                Format.COLORS.WARNING,
                "This snapshot predates title-cutoff data. Run /pvl update for exact cutoffs."
            ))
        end
    end

    table.insert(lines, "")

    for _, row in ipairs(rows) do
        local nameText = Format.Colorize(row.def.color or Format.COLORS.COUNT, row.name)
        if row.def.feat then
            nameText = nameText .. Format.Muted("  ★")
        end

        table.insert(lines, string.format(
            "%s%s  %s  %s",
            nameText,
            SourceTag(row.source),
            Format.Rating(row.cutoffRating),
            FormatProgress(row)
        ))
        table.insert(lines, FormatRule(row))
    end

    table.insert(lines, "")
    table.insert(lines, Format.Muted("★ End-of-season feat of strength (awarded at the final cutoff)."))
    table.insert(lines, Format.Muted("Cutoffs move as the ladder shifts; treat them as live estimates."))

    return table.concat(lines, "\n")
end

--- Creates (or reuses) the title cutoff window frame.
--- @return Frame
function TitleView.CreateFrame()
    if TitleView.frame and TitleView.frame.layoutVersion == TITLE_VIEW_LAYOUT_VERSION then
        return TitleView.frame
    end

    if TitleView.frame then
        TitleView.frame:Hide()
        TitleView.frame = nil
    end

    local frame = CreateFrame("Frame", "PvPLedgerTitleFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 120, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.RegisterEscapeToClose(frame)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("Title Cutoffs")

    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -34)
    frame.header:SetJustifyH("LEFT")
    frame.header:SetWidth(FRAME_WIDTH - (PADDING * 2))

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.note:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -4)
    frame.note:SetJustifyH("LEFT")
    frame.note:SetText(Format.Muted("Estimated rating to reach each seasonal title in this bracket."))

    frame.scroll, frame.setText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerTitleViewScroll",
        frame.note,
        frame,
        frame,
        frame,
        FRAME_HEIGHT - 118,
        FRAME_WIDTH - (PADDING * 2)
    )
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -10)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)

    frame.layoutVersion = TITLE_VIEW_LAYOUT_VERSION
    TitleView.frame = frame
    return frame
end

--- Refreshes the title cutoff window from the active bracket.
function TitleView.Refresh()
    local frame = TitleView.CreateFrame()
    local bracket = PVL.GetActiveBracketFilter()
    frame.header:SetText(Format.Header(PVL.BRACKET_NAMES[bracket] or bracket or "PvP"))
    frame.setText(TitleView.BuildText(bracket))
end

--- Shows the title cutoff window.
function TitleView.Show()
    if PVL.RatedInfo then
        PVL.RatedInfo.RequestUpdate()
        PVL.RatedInfo.RefreshAll()
    end
    TitleView.Refresh()
    TitleView.frame:Show()
end

--- Hides the title cutoff window.
function TitleView.Hide()
    if TitleView.frame then
        TitleView.frame:Hide()
    end
end

--- Toggles the title cutoff window.
function TitleView.Toggle()
    local frame = TitleView.CreateFrame()
    if frame:IsShown() then
        TitleView.Hide()
    else
        TitleView.Show()
    end
end
