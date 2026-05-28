--- Scrollable imported ladder browser filtered by the main UI dropdowns.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI
local Format = UI.Format

UI.LadderView = UI.LadderView or {}
local LadderView = UI.LadderView

LadderView.frame = LadderView.frame or nil
local LADDER_VIEW_LAYOUT_VERSION = 1

local FRAME_WIDTH = 560
local FRAME_HEIGHT = 520
local PADDING = 20

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

--- Builds scrollable text for the ladder browser.
--- @param filters table|nil
--- @return string
function LadderView.BuildText(filters)
    filters = filters or UI.GetFilters()
    local bracket = filters.bracket or PVL.GetActiveBracketFilter()
    local snapshot = PVL.GetImportedSnapshot(bracket)
    local lines = {
        Format.Muted(LadderView.BuildFilterLabel(filters)),
        "",
    }

    if not snapshot then
        table.insert(lines, Format.Muted("No imported ladder snapshot is loaded for this bracket."))
        return table.concat(lines, "\n")
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
        return table.concat(lines, "\n")
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
    table.insert(lines, "")
    table.insert(lines, string.format(
        "%s  %s  %s  %s  %s",
        Format.Muted("#"),
        Format.Muted("Player"),
        Format.Muted("Spec"),
        Format.Muted("CR"),
        Format.Muted("W-L")
    ))

    if #rows == 0 then
        table.insert(lines, "")
        table.insert(lines, Format.Muted("No listed players match the current class/spec filter."))
        return table.concat(lines, "\n")
    end

    for _, row in ipairs(rows) do
        local specLabel = row.specKey and Format.SpecName(row.specKey) or Format.Muted("--")
        local recordText = Format.Muted("--")
        if row.wins or row.losses then
            recordText = Format.Muted(string.format("%s-%s", Format.Count(row.wins or 0), Format.Count(row.losses or 0)))
        end

        table.insert(lines, string.format(
            "%s  %s  %s  %s  %s",
            Format.Muted(tostring(row.rank or "--")),
            Format.PlayerName(row.displayName, row.specKey),
            specLabel,
            Format.Rating(row.rating),
            recordText
        ))
    end

    return table.concat(lines, "\n")
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

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("Imported Ladder")

    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -34)
    frame.header:SetJustifyH("LEFT")
    frame.header:SetWidth(FRAME_WIDTH - (PADDING * 2))

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.note:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -4)
    frame.note:SetJustifyH("LEFT")
    frame.note:SetText(Format.Muted("Uses the Bracket, Class, and Spec filters from the main window."))

    frame.scroll, frame.setText = UI.CreateScrollableTextArea(
        frame,
        "PvPLedgerLadderViewScroll",
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

    frame.layoutVersion = LADDER_VIEW_LAYOUT_VERSION
    LadderView.frame = frame
    return frame
end

--- Refreshes ladder browser content from the current UI filters.
function LadderView.Refresh()
    local frame = LadderView.CreateFrame()
    local filters = UI.GetFilters()
    frame.header:SetText(LadderView.BuildFilterLabel(filters))
    frame.setText(LadderView.BuildText(filters))
end

--- Shows the ladder browser window.
function LadderView.Show()
    LadderView.Refresh()
    LadderView.frame:Show()
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
