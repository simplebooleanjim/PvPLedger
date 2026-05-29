--- Color and readability helpers for PvPLedger UI text.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI

UI.Format = UI.Format or {}
local Format = UI.Format

--- UI color tokens in |cAARRGGBB format.
Format.COLORS = {
    RATING = "FFFFD100",
    PERCENT = "FF66CCFF",
    COUNT = "FFF0F0F0",
    LABEL = "FF9CA3AF",
    MUTED = "FF7A7F87",
    HEADER = "FFFFCC00",
    STANDING = "FF54D98C",
    SOURCE = "FF8A929E",
    WARNING = "FFFFA53C",
    SECTION = "FFD8B25A",
    ACCENT = "FFFFDD8A",
    POSITIVE = "FF54D98C",
    NEGATIVE = "FFF26D6D",
}

--- Wraps text in a WoW color escape sequence.
--- @param colorHex string
--- @param text string
--- @return string
function Format.Colorize(colorHex, text)
    return string.format("|c%s%s|r", colorHex, text)
end

--- Strips WoW color and inline-texture markup for width measurement.
--- @param text string|nil
--- @return string
function Format.StripMarkup(text)
    if not text then
        return ""
    end

    local visible = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    visible = visible:gsub("|A.-|a", ""):gsub("|T.-|t", "")
    return visible
end

--- Returns the visible character width of markup text.
--- Inline icons (|A / |T) count as two cells so columns stay aligned in
--- proportional fonts when rows mix icons with variable-length names.
--- @param text string|nil
--- @return number
function Format.VisibleLength(text)
    if not text then
        return 0
    end

    local iconCount = 0
    for _ in text:gmatch("|A.-|a") do
        iconCount = iconCount + 1
    end
    for _ in text:gmatch("|T.-|t") do
        iconCount = iconCount + 1
    end

    return #Format.StripMarkup(text) + (iconCount * 2)
end

--- Pads markup text on the right so the next column starts at a fixed position.
--- @param text string|nil
--- @param width number Target visible width.
--- @return string
function Format.PadRight(text, width)
    text = text or ""
    local padding = width - Format.VisibleLength(text)
    if padding <= 0 then
        return text
    end

    return text .. string.rep(" ", padding)
end

--- Truncates plain text with an ellipsis when it exceeds a max length.
--- @param text string|nil
--- @param maxLen number
--- @return string
function Format.TruncatePlain(text, maxLen)
    text = text or ""
    if maxLen <= 0 or #text <= maxLen then
        return text
    end

    if maxLen <= 1 then
        return text:sub(1, maxLen)
    end

    return text:sub(1, maxLen - 1) .. "."
end

--- Normalizes Blizzard class color strings to eight-digit hex.
--- @param colorStr string|nil
--- @return string
function Format.NormalizeColorHex(colorStr)
    if not colorStr or colorStr == "" then
        return Format.COLORS.COUNT
    end

    if #colorStr == 8 then
        return colorStr
    end

    if #colorStr == 6 then
        return "FF" .. colorStr
    end

    return colorStr
end

--- Returns the UI color hex for one class token.
--- @param classToken string|nil
--- @return string
function Format.GetClassColorHex(classToken)
    if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
        return Format.NormalizeColorHex(RAID_CLASS_COLORS[classToken].colorStr)
    end

    return Format.COLORS.COUNT
end

--- Returns a class name wrapped in its class color.
--- @param classToken string|nil
--- @param displayName string|nil
--- @return string
function Format.ClassName(classToken, displayName)
    displayName = displayName or PVL.CLASS_NAMES[classToken] or PVL.TitleCaseToken(classToken)
    return Format.Colorize(Format.GetClassColorHex(classToken), displayName)
end

--- Returns an inline class icon as atlas markup for a class token.
--- Fixed-width icons form a clean aligned column in list views, unlike spaces.
--- @param classToken string|nil Uppercase class token (e.g. "DEATHKNIGHT").
--- @param size number|nil Icon edge size in pixels (default 14).
--- @return string Atlas markup with a trailing space, or "" when unknown.
function Format.ClassIcon(classToken, size)
    if not classToken or classToken == "" then
        return ""
    end

    if not CreateAtlasMarkup then
        return ""
    end

    size = size or 14
    return CreateAtlasMarkup("classicon-" .. string.lower(classToken), size, size) .. " "
end

--- Fixed visible-width ladder columns for aligned list rows in scroll text.
Format.LADDER_COL = {
    RANK = 4,
    PLAYER = 34,
    SPEC = 13,
    CR = 7,
    WL = 8,
}

--- Builds the ladder column header line.
--- @param showSpecColumn boolean When false, the spec column is omitted (spec filter active).
--- @param playerWidth number|nil Override player-column width.
--- @return string
function Format.LadderHeader(showSpecColumn, playerWidth)
    playerWidth = playerWidth or Format.LADDER_COL.PLAYER
    local rankCol = Format.PadRight(Format.SectionLabel("#"), Format.LADDER_COL.RANK)
    local playerCol = Format.PadRight(Format.SectionLabel("Player"), playerWidth)

    if showSpecColumn then
        local specCol = Format.PadRight(Format.SectionLabel("Spec"), Format.LADDER_COL.SPEC)
        local crCol = Format.PadRight(Format.SectionLabel("CR"), Format.LADDER_COL.CR)
        return string.format(
            "%s %s %s %s %s",
            rankCol,
            playerCol,
            specCol,
            crCol,
            Format.SectionLabel("W-L")
        )
    end

    local crCol = Format.PadRight(Format.SectionLabel("CR"), Format.LADDER_COL.CR)
    return string.format(
        "%s %s %s %s",
        rankCol,
        playerCol,
        crCol,
        Format.SectionLabel("W-L")
    )
end

--- Formats one ladder list row with fixed-width columns.
--- @param rankText string
--- @param nameText string
--- @param specText string
--- @param crText string
--- @param wlText string
--- @param showSpecColumn boolean When false, the spec column is omitted.
--- @param playerWidth number|nil Override player-column width.
--- @return string
function Format.LadderRow(rankText, nameText, specText, crText, wlText, showSpecColumn, playerWidth)
    playerWidth = playerWidth or Format.LADDER_COL.PLAYER
    local rankCol = Format.PadRight(rankText, Format.LADDER_COL.RANK)
    local playerCol = Format.PadRight(nameText, playerWidth)

    if showSpecColumn then
        local specCol = Format.PadRight(specText, Format.LADDER_COL.SPEC)
        local crCol = Format.PadRight(crText, Format.LADDER_COL.CR)
        return string.format(
            "%s %s %s %s %s",
            rankCol,
            playerCol,
            specCol,
            crCol,
            wlText
        )
    end

    local crCol = Format.PadRight(crText, Format.LADDER_COL.CR)
    return string.format(
        "%s %s %s %s",
        rankCol,
        playerCol,
        crCol,
        wlText
    )
end

--- Returns a muted label string.
--- @param text string
--- @return string
function Format.Label(text)
    return Format.Colorize(Format.COLORS.LABEL, text)
end

--- Returns a section header string.
--- @param text string
--- @return string
function Format.Header(text)
    return Format.Colorize(Format.COLORS.HEADER, text)
end

--- Returns muted helper copy.
--- @param text string
--- @return string
function Format.Muted(text)
    return Format.Colorize(Format.COLORS.MUTED, text)
end

--- Returns an uppercased, accent-colored sub-section label.
--- Used to group related lines inside a panel (e.g. "RECENT ACTIVITY").
--- @param text string Label text (case is normalized to upper).
--- @return string
function Format.SectionLabel(text)
    return Format.Colorize(Format.COLORS.SECTION, string.upper(text))
end

--- Returns a thin horizontal rule for separating sections inside text panels.
--- Drawn with an inline tinted 1px texture so it renders on every client and
--- font (unlike Unicode line characters, which show as missing-glyph boxes).
--- @param width number|nil Rule width in pixels (default 240).
--- @return string
function Format.Divider(width)
    return string.format(
        "|TInterface\\Buttons\\WHITE8X8:1:%d:0:-3:8:8:0:8:0:8:122:104:62|t",
        width or 240
    )
end

--- Returns a small inline color swatch used as a bullet/legend marker.
--- @param colorHex string Eight-digit |cAARRGGBB color (alpha ignored).
--- @param size number|nil Swatch edge size in pixels (default 10).
--- @return string
function Format.Swatch(colorHex, size)
    size = size or 10
    local r = tonumber(colorHex:sub(3, 4), 16) or 255
    local g = tonumber(colorHex:sub(5, 6), 16) or 255
    local b = tonumber(colorHex:sub(7, 8), 16) or 255
    return string.format(
        "|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t",
        size,
        size,
        r,
        g,
        b
    )
end

--- Returns a highlighted rating string.
--- @param value number|nil
--- @return string
function Format.Rating(value)
    local text = PVL.FormatRating(value)
    if text == "--" then
        return Format.Muted(text)
    end

    return Format.Colorize(Format.COLORS.RATING, text)
end

--- Returns a highlighted percentage string.
--- @param value number|nil
--- @return string
function Format.Percent(value)
    local text = PVL.FormatPercent(value)
    if text == "--" then
        return Format.Muted(text)
    end

    return Format.Colorize(Format.COLORS.PERCENT, text)
end

--- Returns a highlighted count string.
--- @param value number|nil
--- @return string
function Format.Count(value)
    if value == nil then
        return Format.Muted("--")
    end

    return Format.Colorize(Format.COLORS.COUNT, tostring(value))
end

--- Returns a win-loss record with wins in green and losses in red.
--- Matches the W/L coloring used in CR history recent activity.
--- @param wins number|nil
--- @param losses number|nil
--- @return string
function Format.WinLossRecord(wins, losses)
    if wins == nil and losses == nil then
        return Format.Muted("--")
    end

    wins = wins or 0
    losses = losses or 0
    return string.format(
        "%s-%s",
        Format.Colorize(Format.COLORS.POSITIVE, tostring(wins)),
        Format.Colorize(Format.COLORS.NEGATIVE, tostring(losses))
    )
end

--- Returns win rate as a percentage from wins and losses.
--- Colors above 50% green, below 50% red, and exactly 50% neutral.
--- @param wins number|nil
--- @param losses number|nil
--- @return string
function Format.WinPercent(wins, losses)
    if wins == nil and losses == nil then
        return Format.Muted("--")
    end

    wins = wins or 0
    losses = losses or 0
    local total = wins + losses
    if total <= 0 then
        return Format.Muted("--")
    end

    local pct = (wins / total) * 100
    local text = PVL.FormatPercent(pct)
    if pct > 50 then
        return Format.Colorize(Format.COLORS.POSITIVE, text)
    end
    if pct < 50 then
        return Format.Colorize(Format.COLORS.NEGATIVE, text)
    end

    return Format.Percent(pct)
end

--- Builds a label/value line for stat blocks.
--- @param label string
--- @param valueText string
--- @return string
function Format.StatLine(label, valueText)
    return string.format("%s  %s", Format.Label(label), valueText)
end

--- Returns a compact combat stat amount for match detail tables.
--- @param value number|nil
--- @return string
function Format.CombatAmount(value)
    if value == nil or value <= 0 then
        return Format.Muted("--")
    end

    if value >= 1000000 then
        return Format.Colorize(Format.COLORS.COUNT, string.format("%.1fM", value / 1000000))
    end

    if value >= 1000 then
        return Format.Colorize(Format.COLORS.COUNT, string.format("%.1fK", value / 1000))
    end

    return Format.Count(value)
end

--- Returns a Details-style total amount label for combat meters.
--- @param value number|nil
--- @return string
function Format.CombatMeterAmount(value)
    if value == nil or value <= 0 then
        return "0"
    end

    if value >= 1000000 then
        return string.format("%.2fM", value / 1000000)
    end

    if value >= 1000 then
        return string.format("%.2fK", value / 1000)
    end

    return tostring(math.floor(value))
end

--- Returns a Details-style per-second rate label for combat meters.
--- @param value number|nil
--- @return string
function Format.CombatMeterRate(value)
    if value == nil or value <= 0 then
        return "0"
    end

    if value >= 1000000 then
        return string.format("%.2fM", value / 1000000)
    end

    if value >= 1000 then
        return string.format("%.1fK", value / 1000)
    end

    return string.format("%.0f", value)
end

--- Faction crest texture paths keyed by normalized faction name.
Format.FACTION_ICONS = {
    Alliance = "Interface\\WorldStateFrame\\AllianceIcon",
    Horde = "Interface\\WorldStateFrame\\HordeIcon",
}

--- Returns an inline gold-star icon marking end-of-season feats of strength.
--- Uses a texture rather than a Unicode star, which the default WoW font cannot
--- render (it would show as a blank "missing glyph" box).
--- @param size number|nil Icon edge size in pixels (default 12).
--- @return string
function Format.FeatIcon(size)
    size = size or 12
    return string.format("|TInterface\\COMMON\\FavoritesIcon:%d:%d|t", size, size)
end

--- Returns an inline faction crest icon for a player faction token.
--- Accepts "HORDE"/"ALLIANCE" or "Horde"/"Alliance"; returns "" when unknown.
--- @param faction string|nil Faction token.
--- @param size number|nil Icon edge size in pixels (default 14).
--- @return string
function Format.FactionIcon(faction, size)
    if not faction or faction == "" then
        return ""
    end

    size = size or 14
    local key
    local upper = string.upper(faction)
    if upper == "HORDE" then
        key = "Horde"
    elseif upper == "ALLIANCE" then
        key = "Alliance"
    end

    local texture = key and Format.FACTION_ICONS[key]
    if not texture then
        return ""
    end

    return string.format("|T%s:%d:%d|t ", texture, size, size)
end

--- Returns a player name wrapped in its class color when spec/class is known.
--- @param displayName string|nil
--- @param specKey string|nil
--- @return string
function Format.PlayerName(displayName, specKey)
    displayName = displayName or "--"
    if not specKey then
        return displayName
    end

    local classToken = specKey:match("^(.-)_")
    if not classToken then
        return displayName
    end

    return Format.Colorize(Format.GetClassColorHex(classToken), displayName)
end

--- Returns a readable spec label with the class name colorized.
--- @param specKey string|nil
--- @return string
function Format.SpecName(specKey)
    if not specKey then
        return Format.Muted("All Specs")
    end

    local classToken, specToken = specKey:match("^(.-)_(.+)$")
    if not classToken or not specToken then
        return specKey
    end

    return string.format("%s %s", PVL.TitleCaseToken(specToken), Format.ClassName(classToken))
end

--- Returns just the spec name (without the class), colored by class.
--- Used where the class is already conveyed by a class icon/color, so the
--- redundant class word can be dropped to keep rows short (e.g. ladder lists).
--- @param specKey string|nil
--- @return string
function Format.SpecShortName(specKey)
    if not specKey then
        return Format.Muted("--")
    end

    local classToken, specToken = specKey:match("^(.-)_(.+)$")
    if not classToken or not specToken then
        return specKey
    end

    return Format.Colorize(Format.GetClassColorHex(classToken), PVL.TitleCaseToken(specToken))
end

--- Appends imported ladder rating stats using full descriptive labels.
--- @param lines string[]
--- @param imported table
function Format.AppendImportedRatingStats(lines, imported)
    if not imported then
        return
    end

    table.insert(lines, Format.StatLine(PVL.LABELS.LISTED_AVG, Format.Rating(imported.avgListedRating)))
    table.insert(lines, Format.StatLine(PVL.LABELS.LISTED_MEDIAN, Format.Rating(imported.medianListedRating)))
    table.insert(lines, Format.StatLine(PVL.LABELS.TOP100_AVG, Format.Rating(imported.top100Avg)))
end

--- Builds one compact CR history activity row.
--- Match rows show W/L, time, CR, and change on a single line.
--- CR-only rows use a muted dash so they read differently from games.
--- @param entry table
--- @return string
function Format.RecentActivityLine(entry)
    local timeText = Format.Muted(PVL.CrHistory.FormatTimestamp(entry.timestamp))

    if entry.source == "match" then
        local resultLabel = entry.won == true and Format.Colorize(Format.COLORS.POSITIVE, "W")
            or (entry.won == false and Format.Colorize(Format.COLORS.NEGATIVE, "L") or Format.Muted("-"))
        local deltaText = (entry.delta == 0) and Format.Muted("0")
            or PVL.CrHistory.FormatDelta(entry.delta)

        return string.format(
            "%s  %s  %s  %s",
            resultLabel,
            timeText,
            Format.Rating(entry.cr),
            deltaText
        )
    end

    return string.format(
        "%s  %s  %s",
        Format.Muted("--"),
        timeText,
        Format.Rating(entry.cr)
    )
end

--- Builds one imported class overview block (header + stat lines).
--- @param row table
--- @return string header, string shareLine, string statsLine
function Format.ClassOverviewLines(row)
    local header = string.format(
        "%s%s",
        Format.ClassIcon(row.classToken),
        Format.ClassName(row.classToken, row.displayName)
    )
    local shareLine = string.format(
        "     %s  %s",
        Format.StatLine("Share", Format.Percent(row.representation)),
        Format.Muted(string.format("(%s listed)", Format.Count(row.listedCount)))
    )
    local statsLine = string.format(
        "     %s %s  %s %s",
        Format.Label("Avg listed"),
        Format.Rating(row.avgListedRating),
        Format.Label("Peak"),
        Format.Rating(row.highest)
    )

    return header, shareLine, statsLine
end

--- Builds one spec row for list panels.
--- @param specKey string
--- @param count number
--- @param percent number|nil
--- @param rating number|nil
--- @return string
function Format.SpecListLine(specKey, count, percent, rating)
    if rating ~= nil then
        local header, shareLine, statsLine = Format.SpecOverviewLines(specKey, count, rating, percent)
        return header .. "\n" .. shareLine .. "\n" .. statsLine
    end

    local classToken = specKey:match("^(.-)_")
    return string.format(
        "%s%s  %s  %s",
        Format.ClassIcon(classToken),
        Format.SpecShortName(specKey),
        Format.Count(count),
        Format.Percent(percent)
    )
end

--- Builds a compact three-line spec overview (icon, share, avg rating).
--- @param specKey string
--- @param count number
--- @param avgRating number|nil
--- @param share number|nil
--- @return string header, string shareLine, string statsLine
function Format.SpecOverviewLines(specKey, count, avgRating, share)
    local classToken = specKey:match("^(.-)_")
    local header = string.format(
        "%s%s",
        Format.ClassIcon(classToken),
        Format.SpecShortName(specKey)
    )
    local shareLine = string.format(
        "     %s  %s",
        Format.StatLine("Share", share and Format.Percent(share) or Format.Muted("--")),
        Format.Muted(string.format("(%s listed)", Format.Count(count)))
    )
    local statsLine = string.format(
        "     %s %s",
        Format.Label("Avg listed"),
        Format.Rating(avgRating)
    )

    return header, shareLine, statsLine
end

--- Appends imported aggregate stats to a line list.
--- @param lines string[]
--- @param imported table
--- @param representation number|nil
--- @param compact boolean|nil When true, uses shorter labels and groups rating stats.
function Format.AppendImportedStats(lines, imported, representation, compact)
    if compact then
        table.insert(lines, Format.StatLine("Listed", Format.Count(imported.listedCount)))
        if representation ~= nil then
            table.insert(lines, Format.StatLine("Share", Format.Percent(representation)))
        end
        table.insert(lines, Format.StatLine("Avg listed", Format.Rating(imported.avgListedRating)))
        table.insert(lines, Format.StatLine("Peak rating", Format.Rating(imported.highest)))
        return
    end

    table.insert(lines, Format.StatLine(PVL.LABELS.REPRESENTATION, Format.Count(imported.listedCount)))
    table.insert(lines, Format.StatLine(PVL.LABELS.LISTED_AVG, Format.Rating(imported.avgListedRating)))
    table.insert(lines, Format.StatLine(PVL.LABELS.LISTED_MEDIAN, Format.Rating(imported.medianListedRating)))
    table.insert(lines, Format.StatLine(PVL.LABELS.TOP100_AVG, Format.Rating(imported.top100Avg)))
    table.insert(lines, Format.StatLine("Peak rating", Format.Rating(imported.highest)))

    if representation ~= nil then
        table.insert(lines, Format.StatLine("Ladder share", Format.Percent(representation)))
    end
end
