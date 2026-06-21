--- Title cutoff browser: shows the estimated rating to reach each seasonal title.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI
local Format = UI.Format

UI.TitleView = UI.TitleView or {}
local TitleView = UI.TitleView

TitleView.frame = TitleView.frame or nil
TitleView.linePool = TitleView.linePool or {}
TitleView.titleRowPool = TitleView.titleRowPool or {}
TitleView.achievementRowPool = TitleView.achievementRowPool or {}

local TITLE_VIEW_LAYOUT_VERSION = 7

local FRAME_WIDTH = 520
local FRAME_HEIGHT = 480
local PADDING = 20
local CONTENT_WIDTH = FRAME_WIDTH - (PADDING * 2)
local TEXT_PAD_X = 6
local LINE_HEIGHT = 14
local TITLE_MAIN_HEIGHT = 16
local TITLE_RULE_HEIGHT = 13
local TITLE_BLOCK_GAP = 6
local SECTION_GAP = 8
local ACHIEVEMENT_BLOCK_HEIGHT = 34
local SCROLLBAR_GUTTER = 24

--- Returns a readable label describing the source of a cutoff rating.
--- @param source string|nil Resolution source from ResolveTitleCutoffRating.
--- @return string
local function SourceTag(source)
    if source == "estimated" then
        return Format.Muted(" (est.)")
    elseif source == "estimated-spec" then
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
        return Format.Colorize(Format.COLORS.STANDING, PVL.L("UI.TITLES.ACHIEVED"))
    end

    return Format.Colorize(Format.COLORS.WARNING, string.format("+%s to go", PVL.FormatRating(row.gap)))
end

--- Returns win progress text for one achievement-backed title definition.
--- @param def table|nil
--- @return string|nil
local function FormatWinProgress(def)
    if type(def) ~= "table" then
        return nil
    end

    if def.achievementId then
        local current, required, completed = PVL.GetAchievementProgress(def.achievementId, def.wins)
        required = required or def.wins or 0
        if completed then
            return Format.Colorize(Format.COLORS.STANDING, string.format("%s/%s wins", Format.Count(required), Format.Count(required)))
        end
        return Format.Colorize(
            Format.COLORS.COUNT,
            string.format("%s/%s wins", Format.Count(current or 0), Format.Count(required))
        )
    end

    if def.wins then
        return Format.Muted(string.format("%s wins required", Format.Count(def.wins)))
    end

    return nil
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
    elseif def.kind == "spec_rank" then
        local scope = context and context.specName and (context.specName .. " ladder") or "spec ladder"
        table.insert(parts, string.format("Top %s on %s", PVL.FormatRating(def.rank or PVL.PER_SPEC_RANK1_SLOTS), scope))
    elseif def.kind == "achievement" then
        if row.cutoffRating then
            table.insert(parts, string.format("%s rating", PVL.FormatRating(row.cutoffRating)))
            if row.ratingAchieved == true then
                table.insert(parts, "rating achieved")
            elseif row.gap and row.gap > 0 then
                table.insert(parts, string.format("+%s rating to Elite", PVL.FormatRating(row.gap)))
            end
        end

        local config = row.achievementConfig
        local detail = config and config.ruleDetail or "matches"
        table.insert(parts, string.format("Win %s at Elite during the current season", detail))
    else
        table.insert(parts, string.format("%s rating", PVL.FormatRating(def.rating)))
    end

    local winProgress = FormatWinProgress(def)
    if winProgress then
        table.insert(parts, winProgress)
    elseif def.wins then
        table.insert(parts, string.format("%s wins", def.wins))
    end

    if def.achievementId then
        if PVL.IsAchievementTracked(def.achievementId) then
            table.insert(parts, Format.Colorize(Format.COLORS.STANDING, "tracking"))
        else
            table.insert(parts, Format.Colorize(Format.COLORS.LINK, "click to track"))
        end
    end

    return Format.Muted("    " .. table.concat(parts, " · "))
end

--- Builds one clickable seasonal achievement row model.
--- @param config table Bracket achievement config from TitleCutoffs.
--- @param titleRow table|nil Optional title row to merge rating context from.
--- @return table
local function BuildSeasonAchievementRowModel(config, titleRow)
    local current, required, completed = PVL.GetAchievementProgress(
        config.achievementId,
        config.defaultRequired
    )
    required = required or config.defaultRequired

    return {
        def = {
            id = config.defId,
            kind = "achievement",
            wins = required,
            color = (titleRow and titleRow.def and titleRow.def.color) or config.color,
            achievementId = config.achievementId,
            feat = titleRow and titleRow.def and titleRow.def.feat or nil,
        },
        name = PVL.GetAchievementDisplayName(config.achievementId, config.fallbackName),
        cutoffRating = titleRow and titleRow.cutoffRating or nil,
        source = titleRow and titleRow.source or nil,
        rank = titleRow and titleRow.rank or nil,
        achieved = completed,
        gap = titleRow and titleRow.gap or nil,
        ratingAchieved = titleRow and titleRow.achieved or nil,
        winProgress = completed and required or (current or 0),
        winRequired = required,
        achievementConfig = config,
        clickable = true,
    }
end

--- Builds the right-aligned progress text for one seasonal achievement row.
--- @param row table
--- @return string
local function FormatSeasonAchievementProgress(row)
    if row.achieved then
        return Format.Colorize(Format.COLORS.STANDING, PVL.L("UI.TITLES.COMPLETE"))
    end

    return Format.Colorize(
        Format.COLORS.COUNT,
        string.format("%s/%s", Format.Count(row.winProgress or 0), Format.Count(row.winRequired or 0))
    )
end

--- Toggles one seasonal achievement tracker and refreshes the title window.
--- @param achievementId number
local function HandleAchievementClick(achievementId)
    local ok, message = PVL.ToggleAchievementTracking(achievementId)
    if not ok and message then
        print(string.format("|cff66ccffPvPLedger|r: %s", message))
    end
    TitleView.Refresh(TitleView.frame)
end

--- Clears pooled row widgets so a rebuilt frame never reuses stale children.
function TitleView.ResetPools()
    TitleView.linePool = {}
    TitleView.titleRowPool = {}
    TitleView.achievementRowPool = {}
end

--- Hides pooled row widgets before a full re-render.
--- @param frame Frame
local function HideRowPools(frame)
    for _, line in ipairs(TitleView.linePool) do
        line:Hide()
    end
    for _, row in ipairs(TitleView.titleRowPool) do
        row:Hide()
    end
    for _, row in ipairs(TitleView.achievementRowPool) do
        row:Hide()
    end
    if frame and frame.footerText then
        frame.footerText:Hide()
    end
end

--- Acquires one reusable text line frame.
--- @param parent Frame
--- @param index number
--- @return Frame
local function AcquireTextLine(parent, index)
    local line = TitleView.linePool[index]
    if not line then
        line = CreateFrame("Frame", "PvPLedgerTitleLine" .. index, parent)
        line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.text:SetJustifyH("LEFT")
        line.text:SetJustifyV("TOP")
        line.text:SetPoint("TOPLEFT", line, "TOPLEFT", TEXT_PAD_X, 0)
        TitleView.linePool[index] = line
    end

    line:SetParent(parent)
    line:ClearAllPoints()
    line:Show()
    return line
end

--- Acquires one reusable title block (main line + rule line).
--- @param parent Frame
--- @param index number
--- @return Frame
local function AcquireTitleRow(parent, index)
    local row = TitleView.titleRowPool[index]
    if not row then
        row = CreateFrame("Frame", "PvPLedgerTitleRow" .. index, parent)
        row.mainText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.mainText:SetJustifyH("LEFT")
        row.mainText:SetJustifyV("TOP")
        row.mainText:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_PAD_X, 0)
        row.ruleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.ruleText:SetJustifyH("LEFT")
        row.ruleText:SetJustifyV("TOP")
        row.ruleText:SetPoint("TOPLEFT", row.mainText, "BOTTOMLEFT", 0, -2)
        TitleView.titleRowPool[index] = row
    end

    row:SetParent(parent)
    row:ClearAllPoints()
    row:Show()
    return row
end

--- Acquires one clickable seasonal achievement row.
--- @param parent Frame
--- @param index number
--- @return Button
local function AcquireSeasonAchievementRow(parent, index)
    local row = TitleView.achievementRowPool[index]
    if not row then
        row = CreateFrame("Button", "PvPLedgerTitleAchievementRow" .. index, parent)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.mainText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.mainText:SetJustifyH("LEFT")
        row.mainText:SetJustifyV("TOP")
        row.mainText:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_PAD_X, -2)
        row.ruleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.ruleText:SetJustifyH("LEFT")
        row.ruleText:SetJustifyV("TOP")
        row.ruleText:SetPoint("TOPLEFT", row.mainText, "BOTTOMLEFT", 0, -2)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        TitleView.achievementRowPool[index] = row
    end

    row:SetParent(parent)
    row:ClearAllPoints()
    row:Show()
    return row
end

--- Places one plain text line in the scroll content.
--- @param parent Frame
--- @param index number
--- @param yOffset number
--- @param text string
--- @param width number
--- @return number nextYOffset
local function PlaceTextLine(parent, index, yOffset, text, width)
    local line = AcquireTextLine(parent, index)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    line:SetWidth(width)
    line.text:SetWidth(width - TEXT_PAD_X)
    line.text:SetText(text or "")
    local height = math.max(line.text:GetStringHeight() or LINE_HEIGHT, LINE_HEIGHT)
    line:SetHeight(height)
    return yOffset - height - 2
end

--- Places one title block in the scroll content.
--- @param parent Frame
--- @param index number
--- @param yOffset number
--- @param row table
--- @param context table
--- @param width number
--- @return number nextYOffset
local function PlaceTitleRow(parent, index, yOffset, row, context, width)
    local block = AcquireTitleRow(parent, index)
    block:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    block:SetWidth(width)

    local nameText = Format.Colorize(row.def.color or Format.COLORS.COUNT, row.name)
    if row.def.feat then
        nameText = nameText .. "  " .. Format.FeatIcon()
    end

    block.mainText:SetWidth(width - TEXT_PAD_X)
    block.mainText:SetText(string.format(
        "%s%s  %s  %s",
        nameText,
        SourceTag(row.source),
        Format.Rating(row.cutoffRating),
        FormatProgress(row)
    ))

    block.ruleText:SetWidth(width - TEXT_PAD_X)
    block.ruleText:SetText(FormatRule(row, context))

    local height = (block.mainText:GetStringHeight() or TITLE_MAIN_HEIGHT)
        + 2
        + (block.ruleText:GetStringHeight() or TITLE_RULE_HEIGHT)
    block:SetHeight(height)
    return yOffset - height - TITLE_BLOCK_GAP
end

--- Places one clickable seasonal achievement row in the scroll content.
--- @param parent Frame
--- @param index number
--- @param yOffset number
--- @param row table
--- @param context table
--- @param width number
--- @return number nextYOffset
local function PlaceSeasonAchievementRow(parent, index, yOffset, row, context, width)
    local block = AcquireSeasonAchievementRow(parent, index)
    local achievementId = row.def and row.def.achievementId
    block:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    block:SetSize(width, ACHIEVEMENT_BLOCK_HEIGHT)

    block:SetScript("OnClick", function()
        if achievementId then
            HandleAchievementClick(achievementId)
        end
    end)
    block:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Track on objectives", 1, 1, 1)
        GameTooltip:AddLine("Click to toggle Blizzard's achievement tracker.", 0.8, 0.8, 0.8, true)
        if achievementId and PVL.IsAchievementTracked(achievementId) then
            GameTooltip:AddLine("Currently tracking.", 0.33, 0.85, 0.55, true)
        end
        GameTooltip:Show()
    end)

    local nameText = Format.Colorize(row.def.color or Format.COLORS.COUNT, row.name)
    if row.def.feat then
        nameText = nameText .. "  " .. Format.FeatIcon()
    end
    if achievementId and PVL.IsAchievementTracked(achievementId) then
        nameText = nameText .. "  " .. Format.Colorize(Format.COLORS.STANDING, "(tracking)")
    end

    block.mainText:SetWidth(width - TEXT_PAD_X)
    block.mainText:SetText(string.format(
        "%s  %s",
        nameText,
        FormatSeasonAchievementProgress(row)
    ))

    block.ruleText:SetWidth(width - TEXT_PAD_X)
    block.ruleText:SetText(FormatRule(row, context))

    return yOffset - ACHIEVEMENT_BLOCK_HEIGHT - TITLE_BLOCK_GAP
end

--- Builds structured display sections for the title cutoff window.
--- @param bracket string|nil
--- @return table sections, table|nil context
function TitleView.BuildDisplaySections(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    local rows, context = PVL.BuildTitleCutoffRows(bracket)
    local bracketName = PVL.BRACKET_NAMES[bracket] or bracket or "PvP"
    local sections = {
        { kind = "text", text = Format.Muted(bracketName) },
        { kind = "spacer" },
    }

    local snapshot = context.snapshot
    if not snapshot then
        table.insert(sections, { kind = "text", text = Format.Muted(PVL.L("UI.TITLES.NO_DATA")) })
        table.insert(sections, { kind = "text", text = Format.Muted(PVL.L("UI.TITLES.UPDATE_HINT")) })
        return sections, context
    end

    table.insert(sections, {
        kind = "text",
        text = Format.StatLine(PVL.L("UI.TITLES.YOUR_RATING"), Format.Rating(context.playerRating)),
    })

    if context.perSpec then
        table.insert(sections, {
            kind = "text",
            text = Format.StatLine(
                PVL.L("UI.TITLES.YOUR_SPEC"),
                context.specName and Format.Colorize(Format.COLORS.COUNT, context.specName)
                    or Format.Muted(PVL.L("UI.TITLES.SPEC_NOT_DETECTED"))
            ),
        })
        if context.specPopulation then
            table.insert(sections, {
                kind = "text",
                text = Format.StatLine(PVL.L("UI.TITLES.RATED_IN_SPEC"), Format.Count(context.specPopulation)),
            })
        end
    elseif context.ratedPopulation then
        table.insert(sections, {
            kind = "text",
            text = Format.StatLine(PVL.L("UI.TITLES.RATED_PLAYERS"), Format.Count(context.ratedPopulation)),
        })
    end

    table.insert(sections, {
        kind = "text",
        text = Format.Muted(string.format(
            "Snapshot: %s%s · Source: %s",
            snapshot.snapshotDate or "--",
            snapshot.season and string.format(" · S%s", snapshot.season) or "",
            PVL.GetSnapshotSource(bracket) or snapshot.source or "unknown"
        )),
    })

    if context.perSpec then
        if not context.hasSpecCutoffs then
            table.insert(sections, {
                kind = "text",
                text = Format.Colorize(
                    Format.COLORS.WARNING,
                    "This snapshot predates per-spec cutoffs. Run /pvl update for exact values."
                ),
            })
        elseif not context.specKey then
            table.insert(sections, {
                kind = "text",
                text = Format.Colorize(
                    Format.COLORS.WARNING,
                    "Couldn't detect your specialization; per-spec cutoffs are hidden."
                ),
            })
        end
    elseif not context.hasExactCutoffs then
        if context.ratedPopulation then
            table.insert(sections, {
                kind = "text",
                text = Format.Colorize(
                    Format.COLORS.WARNING,
                    "Percentile cutoffs are estimated from listed ranks. Refresh for exact values."
                ),
            })
        else
            table.insert(sections, {
                kind = "text",
                text = Format.Colorize(
                    Format.COLORS.WARNING,
                    "This snapshot predates title-cutoff data. Run /pvl update for exact cutoffs."
                ),
            })
        end
    end

    table.insert(sections, { kind = "spacer" })
    table.insert(sections, { kind = "divider" })
    table.insert(sections, { kind = "spacer" })

    local seasonAchievement = PVL.GetBracketSeasonAchievement(context.bracket)

    for _, row in ipairs(rows) do
        if seasonAchievement
            and seasonAchievement.placement == "before_rank1"
            and row.def.id == "rank1" then
            table.insert(sections, {
                kind = "achievement",
                row = BuildSeasonAchievementRowModel(seasonAchievement),
            })
        end

        if seasonAchievement
            and seasonAchievement.placement == "title_row"
            and row.def.id == seasonAchievement.titleDefId then
            table.insert(sections, {
                kind = "achievement",
                row = BuildSeasonAchievementRowModel(seasonAchievement, row),
            })
        else
            table.insert(sections, { kind = "title", row = row })
        end
    end

    local specSection = TitleView.BuildSelectedSpecSection(bracket, context)
    for _, section in ipairs(specSection) do
        table.insert(sections, section)
    end

    table.insert(sections, { kind = "spacer" })
    table.insert(sections, { kind = "divider" })
    table.insert(sections, {
        kind = "footer",
        text = table.concat({
            Format.FeatIcon() .. " " .. Format.Muted("End-of-season feat of strength (awarded at the final cutoff)."),
            Format.Muted("Cutoffs move as the ladder shifts; treat them as live estimates."),
        }, "\n"),
    })

    return sections, context
end

--- Builds optional selected-spec sections for the display model.
--- @param bracket string
--- @param context table
--- @return table sections
function TitleView.BuildSelectedSpecSection(bracket, context)
    local sections = {}
    if not context.perSpec then
        return sections
    end

    local filters = (UI.GetFilters and UI.GetFilters()) or {}
    local selectedSpecKey = filters.specKey
    if not selectedSpecKey then
        return sections
    end

    local specRows = PVL.BuildSpecTitleCutoffRows(bracket, selectedSpecKey)
    if #specRows == 0 then
        return sections
    end

    if context.perSpec and context.specKey == selectedSpecKey then
        return sections
    end

    table.insert(sections, { kind = "spacer" })
    table.insert(sections, { kind = "divider" })
    table.insert(sections, {
        kind = "text",
        text = Format.SectionLabel(PVL.L("UI.TITLES.SELECTED_SPEC")) .. "  " .. Format.SpecName(selectedSpecKey),
    })
    table.insert(sections, {
        kind = "text",
        text = Format.Muted("    Estimated title cutoffs for this spec (e.g. to check a friend)."),
    })

    local hasAny = false
    for _, row in ipairs(specRows) do
        if row.cutoffRating then
            hasAny = true
            table.insert(sections, { kind = "specTitle", row = row })
        end
    end

    if not hasAny then
        table.insert(sections, {
            kind = "text",
            text = Format.Muted("    No cutoff data for this spec in the current snapshot."),
        })
    end

    return sections
end

--- Renders the title cutoff scroll content from structured sections.
--- @param frame Frame
--- @param bracket string|nil
function TitleView.RenderContent(frame, bracket)
    local scroll = frame.scroll
    local content = frame.scrollContent
    if not scroll or not content then
        return
    end

    HideRowPools(frame)

    local sections, context = TitleView.BuildDisplaySections(bracket)
    local contentWidth = CONTENT_WIDTH
    local yOffset = -4
    local lineIndex = 0
    local titleIndex = 0
    local achievementIndex = 0

    for _, section in ipairs(sections) do
        if section.kind == "text" then
            lineIndex = lineIndex + 1
            yOffset = PlaceTextLine(content, lineIndex, yOffset, section.text, contentWidth)
        elseif section.kind == "spacer" then
            yOffset = yOffset - SECTION_GAP
        elseif section.kind == "divider" then
            lineIndex = lineIndex + 1
            yOffset = PlaceTextLine(content, lineIndex, yOffset, Format.Divider(456), contentWidth)
        elseif section.kind == "title" then
            titleIndex = titleIndex + 1
            yOffset = PlaceTitleRow(content, titleIndex, yOffset, section.row, context, contentWidth)
        elseif section.kind == "achievement" then
            achievementIndex = achievementIndex + 1
            yOffset = PlaceSeasonAchievementRow(content, achievementIndex, yOffset, section.row, context, contentWidth)
        elseif section.kind == "specTitle" then
            titleIndex = titleIndex + 1
            local row = section.row
            local nameText = Format.Colorize(row.def.color or Format.COLORS.COUNT, row.name)
            if row.def.feat then
                nameText = nameText .. "  " .. Format.FeatIcon()
            end
            local tag = (row.source == "estimated") and Format.Muted(" (est.)") or ""
            lineIndex = lineIndex + 1
            yOffset = PlaceTextLine(content, lineIndex, yOffset, string.format(
                "%s%s  %s",
                nameText,
                tag,
                Format.Rating(row.cutoffRating)
            ), contentWidth)
        elseif section.kind == "footer" then
            if not frame.footerText then
                frame.footerText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                frame.footerText:SetJustifyH("LEFT")
                frame.footerText:SetJustifyV("TOP")
            end
            frame.footerText:ClearAllPoints()
            frame.footerText:SetPoint("TOPLEFT", content, "TOPLEFT", TEXT_PAD_X, yOffset)
            frame.footerText:SetWidth(contentWidth - TEXT_PAD_X)
            frame.footerText:SetText(section.text or "")
            frame.footerText:Show()
            local footerHeight = frame.footerText:GetStringHeight() or (LINE_HEIGHT * 2)
            yOffset = yOffset - footerHeight - 4
        end
    end

    local totalHeight = math.abs(yOffset) + 12
    local frameHeight = scroll:GetHeight() or 1
    content:SetSize(contentWidth, math.max(totalHeight, frameHeight))
    scroll:SetVerticalScroll(0)
    if scroll.UpdateScrollChildRect then
        scroll:UpdateScrollChildRect()
    end
    UI.UpdateScrollBarVisibility(scroll)
end

--- Shows a fallback error message when row rendering fails.
--- @param frame Frame
--- @param message string|nil
function TitleView.ShowRenderError(frame, message)
    if not frame or not frame.scrollContent then
        return
    end

    HideRowPools(frame)
    TitleView.ResetPools()

    if not frame.errorText then
        frame.errorText = frame.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.errorText:SetJustifyH("LEFT")
        frame.errorText:SetJustifyV("TOP")
        frame.errorText:SetPoint("TOPLEFT", frame.scrollContent, "TOPLEFT", TEXT_PAD_X, -4)
    end

    frame.errorText:SetWidth(CONTENT_WIDTH - TEXT_PAD_X)
    frame.errorText:SetText(Format.Colorize(
        Format.COLORS.WARNING,
        message or PVL.L("UI.TITLES.RENDER_ERROR")
    ))
    frame.errorText:Show()
    frame.scrollContent:SetSize(CONTENT_WIDTH, math.max(frame.errorText:GetStringHeight() or LINE_HEIGHT, frame.scroll:GetHeight() or 1))
end

--- Creates (or reuses) the title cutoff window frame.
--- @return Frame
function TitleView.CreateFrame()
    if TitleView.frame and TitleView.frame.layoutVersion == TITLE_VIEW_LAYOUT_VERSION then
        return TitleView.frame
    end

    if TitleView.frame then
        TitleView.frame:Hide()
        TitleView.frame:SetParent(nil)
        TitleView.frame = nil
    end

    TitleView.ResetPools()

    local frame = CreateFrame("Frame", "PvPLedgerTitleFrame", UIParent, "BasicFrameTemplateWithInset")
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
    frame.title:SetText(PVL.L("UI.TITLES.WINDOW_TITLE"))

    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -34)
    frame.header:SetJustifyH("LEFT")
    frame.header:SetWidth(FRAME_WIDTH - (PADDING * 2))

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.note:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -4)
    frame.note:SetJustifyH("LEFT")
    frame.note:SetText(Format.Muted(PVL.L("UI.TITLES.SUBTITLE")))

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -10)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)
    frame.scroll:SetWidth(CONTENT_WIDTH)

    local scrollBar = frame.scroll.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", frame.scroll, "TOPRIGHT", -4, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", frame.scroll, "BOTTOMRIGHT", -4, 18)
    end

    frame.scrollContent = CreateFrame("Frame", nil, frame.scroll)
    frame.scroll:SetScrollChild(frame.scrollContent)
    frame.errorText = nil

    frame:RegisterEvent("CRITERIA_UPDATE")
    local trackedEventOk = pcall(frame.RegisterEvent, frame, "TRACKED_ACHIEVEMENT_UPDATE")
    if not trackedEventOk then
        pcall(frame.RegisterEvent, frame, "ACHIEVEMENT_EARNED")
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "CRITERIA_UPDATE"
            or event == "TRACKED_ACHIEVEMENT_UPDATE"
            or event == "ACHIEVEMENT_EARNED" then
            if frame:IsShown() then
                TitleView.Refresh(frame)
            end
        end
    end)

    frame.layoutVersion = TITLE_VIEW_LAYOUT_VERSION
    TitleView.frame = frame
    return frame
end

--- Refreshes the title cutoff window from the active bracket.
--- @param frame Frame|nil
function TitleView.Refresh(frame)
    if PVL.IsCombatLocked and PVL.IsCombatLocked() then
        if PVL.RequestUiRefresh then
            PVL.RequestUiRefresh()
        end
        return
    end

    frame = frame or TitleView.CreateFrame()
    local bracket = PVL.GetActiveBracketFilter()
    frame.header:SetText(Format.Header(PVL.BRACKET_NAMES[bracket] or bracket or "PvP"))

    if frame.errorText then
        frame.errorText:Hide()
    end

    local ok, err = pcall(TitleView.RenderContent, frame, bracket)
    if not ok then
        TitleView.ShowRenderError(frame, string.format(
            "Title cutoffs failed to render: %s",
            tostring(err)
        ))
    end
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
    if PVL.CanOpenAddonWindows and not PVL.CanOpenAddonWindows() then
        return
    end

    local frame = TitleView.CreateFrame()

    if PVL.RatedInfo then
        pcall(PVL.RatedInfo.RequestUpdate)
        pcall(PVL.RatedInfo.RefreshAll)
    end

    TitleView.PositionDefault()
    frame:Show()
    if frame.Raise then
        frame:Raise()
    end

    TitleView.Refresh(frame)
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
