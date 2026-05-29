--- Title cutoff browser: shows the estimated rating to reach each seasonal title.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI
local Format = UI.Format

UI.TitleView = UI.TitleView or {}
local TitleView = UI.TitleView

TitleView.frame = TitleView.frame or nil
local TITLE_VIEW_LAYOUT_VERSION = 2

local FRAME_WIDTH = 520
local FRAME_HEIGHT = 480
local PADDING = 20

--- Returns a readable label describing the source of a cutoff rating.
--- @param source string|nil Resolution source from ResolveTitleCutoffRating.
--- @return string
local function SourceTag(source)
    if source == "estimated" then
        return Format.Muted(" (est.)")
    elseif source == "exact-spec" then
        return Format.Muted(" (your spec)")
    end

    return ""
end

--- Builds the right-aligned achievement/gap text for one title row.
--- @param row table Title cutoff row.
--- @return string
local function FormatProgress(row)
    if not row.cutoffRating then
        if row.source == "needs-spec" then
            return Format.Muted("per-spec data unavailable")
        end
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
--- @param context table Title cutoff context (bracket, perSpec, specName, ...).
--- @return string
local function FormatRule(row, context)
    local def = row.def
    local parts = {}

    if def.kind == "percentile" then
        local scope = "ladder"
        if context and context.perSpec then
            scope = context.specName and (context.specName .. " ladder") or "spec ladder"
        end
        table.insert(parts, string.format("Top %s%% of %s", def.percentile, scope))
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
        table.insert(lines, Format.Muted("No ladder data is loaded for this bracket."))
        table.insert(lines, Format.Muted("Run /pvl update or install PvPLedger Sync for ladder data."))
        return table.concat(lines, "\n")
    end

    table.insert(lines, Format.StatLine(
        "Your current rating",
        Format.Rating(context.playerRating)
    ))

    if context.perSpec then
        table.insert(lines, Format.StatLine(
            "Your spec",
            context.specName and Format.Colorize(Format.COLORS.COUNT, context.specName)
                or Format.Muted("not detected")
        ))
        if context.specPopulation then
            table.insert(lines, Format.StatLine(
                "Rated in your spec",
                Format.Count(context.specPopulation)
            ))
        end
    elseif context.ratedPopulation then
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

    if context.perSpec then
        if not context.hasSpecCutoffs then
            table.insert(lines, Format.Colorize(
                Format.COLORS.WARNING,
                "This snapshot predates per-spec cutoffs. Run /pvl update for exact values."
            ))
        elseif not context.specKey then
            table.insert(lines, Format.Colorize(
                Format.COLORS.WARNING,
                "Couldn't detect your specialization; per-spec cutoffs are hidden."
            ))
        end
    elseif not context.hasExactCutoffs then
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
    table.insert(lines, Format.Divider(456))
    table.insert(lines, "")

    for _, row in ipairs(rows) do
        local nameText = Format.Colorize(row.def.color or Format.COLORS.COUNT, row.name)
        if row.def.feat then
            nameText = nameText .. "  " .. Format.FeatIcon()
        end

        table.insert(lines, string.format(
            "%s%s  %s  %s",
            nameText,
            SourceTag(row.source),
            Format.Rating(row.cutoffRating),
            FormatProgress(row)
        ))
        table.insert(lines, FormatRule(row, context))
    end

    TitleView.AppendSelectedSpecSection(lines, bracket, context)

    table.insert(lines, "")
    table.insert(lines, Format.Divider(456))
    table.insert(lines, Format.FeatIcon() .. " " .. Format.Muted("End-of-season feat of strength (awarded at the final cutoff)."))
    table.insert(lines, Format.Muted("Cutoffs move as the ladder shifts; treat them as live estimates."))

    return table.concat(lines, "\n")
end

--- Appends a "selected spec" section using the main window's spec dropdown.
---
--- Lets the user look up the prestige title cutoffs for any spec (e.g. a friend
--- who lacks the addon) without leaving the title window. The player's own
--- rating gap is intentionally omitted since the selected spec may not be theirs.
--- @param lines table Line buffer being assembled by BuildText.
--- @param bracket string Bracket id.
--- @param context table Title cutoff context for the player's own section.
function TitleView.AppendSelectedSpecSection(lines, bracket, context)
    -- Only per-spec brackets (Solo Shuffle, Battleground Blitz) award titles
    -- against each spec's own ladder. Combined brackets (Arena, RBG) are decided
    -- purely by ladder placement, so a per-spec lookup would just repeat the same
    -- combined cutoff already shown in the player's section.
    if not context.perSpec then
        return
    end

    local filters = (UI.GetFilters and UI.GetFilters()) or {}
    local selectedSpecKey = filters.specKey
    if not selectedSpecKey then
        return
    end

    local specRows = PVL.BuildSpecTitleCutoffRows(bracket, selectedSpecKey)
    if #specRows == 0 then
        return
    end

    -- Avoid duplicating the player's own section when the dropdown matches it.
    if context.perSpec and context.specKey == selectedSpecKey then
        return
    end

    table.insert(lines, "")
    table.insert(lines, Format.Divider(456))
    table.insert(lines, Format.SectionLabel("Selected spec") .. "  " .. Format.SpecName(selectedSpecKey))
    table.insert(lines, Format.Muted("    Estimated title cutoffs for this spec (e.g. to check a friend)."))

    local hasAny = false
    for _, row in ipairs(specRows) do
        if row.cutoffRating then
            hasAny = true

            local nameText = Format.Colorize(row.def.color or Format.COLORS.COUNT, row.name)
            if row.def.feat then
                nameText = nameText .. "  " .. Format.FeatIcon()
            end

            -- This section describes a looked-up spec, so the "(your spec)" tag
            -- used elsewhere does not apply; only flag estimated values.
            local tag = (row.source == "estimated") and Format.Muted(" (est.)") or ""

            table.insert(lines, string.format(
                "%s%s  %s",
                nameText,
                tag,
                Format.Rating(row.cutoffRating)
            ))
        end
    end

    if not hasAny then
        table.insert(lines, Format.Muted("    No cutoff data for this spec in the current snapshot."))
    end
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

    UI.AddWindowLogo(frame)
    UI.AddWindowWatermark(frame)

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

--- Positions the title window to the left of the main window when possible.
function TitleView.PositionDefault()
    local frame = TitleView.frame
    if not frame then
        return
    end

    frame:ClearAllPoints()
    local main = PVL.UI and PVL.UI.frame
    if main and main:IsShown() then
        frame:SetPoint("TOPRIGHT", main, "TOPLEFT", -8, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -360, 0)
    end
end

--- Shows the title cutoff window.
function TitleView.Show()
    if PVL.RatedInfo then
        PVL.RatedInfo.RequestUpdate()
        PVL.RatedInfo.RefreshAll()
    end
    TitleView.Refresh()
    TitleView.PositionDefault()
    TitleView.frame:Show()
    TitleView.frame:Raise()
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
