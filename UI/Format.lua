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
    COUNT = "FFFFFFFF",
    LABEL = "FFB0B0B0",
    MUTED = "FF888888",
    HEADER = "FFFFCC00",
    STANDING = "FF40C040",
    SOURCE = "FFAAAAAA",
}

--- Wraps text in a WoW color escape sequence.
--- @param colorHex string
--- @param text string
--- @return string
function Format.Colorize(colorHex, text)
    return string.format("|c%s%s|r", colorHex, text)
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

--- Builds one imported class overview line.
--- @param row table
--- @return string header, string stats
function Format.ClassOverviewLines(row)
    local header = string.format(
        "%s  %s listed  %s",
        Format.ClassName(row.classToken, row.displayName),
        Format.Count(row.listedCount),
        Format.Percent(row.representation)
    )
    local stats = string.format(
        "    avg %s   top100 %s   peak %s",
        Format.Rating(row.avgListedRating),
        Format.Rating(row.top100Avg),
        Format.Rating(row.highest)
    )

    return header, stats
end

--- Builds one imported class row for compact side panels.
--- @param row table
--- @return string header, string stats
function Format.ClassSnapshotLines(row)
    local header = string.format(
        "%s  %s listed",
        Format.ClassName(row.classToken, row.displayName),
        Format.Count(row.listedCount)
    )
    local stats = string.format(
        "    avg %s   share %s   peak %s",
        Format.Rating(row.avgListedRating),
        Format.Percent(row.representation),
        Format.Rating(row.highest)
    )

    return header, stats
end

--- Builds one spec row for list panels.
--- @param specKey string
--- @param count number
--- @param percent number|nil
--- @param rating number|nil
--- @return string
function Format.SpecListLine(specKey, count, percent, rating)
    if rating ~= nil then
        return string.format(
            "%s  %s listed   avg %s",
            Format.SpecName(specKey),
            Format.Count(count),
            Format.Rating(rating)
        )
    end

    return string.format(
        "%s  %s  %s",
        Format.SpecName(specKey),
        Format.Count(count),
        Format.Percent(percent)
    )
end

--- Builds one imported spec row with rating and ladder share.
--- @param specKey string
--- @param count number
--- @param avgRating number|nil
--- @param share number|nil
--- @return string
function Format.SpecImportedLine(specKey, count, avgRating, share)
    return string.format(
        "%s  %s listed   avg %s   share %s",
        Format.SpecName(specKey),
        Format.Count(count),
        Format.Rating(avgRating),
        Format.Percent(share)
    )
end

--- Appends imported aggregate stats to a line list.
--- @param lines string[]
--- @param imported table
--- @param representation number|nil
function Format.AppendImportedStats(lines, imported, representation)
    table.insert(lines, Format.StatLine(PVL.LABELS.REPRESENTATION, Format.Count(imported.listedCount)))
    table.insert(lines, Format.StatLine(PVL.LABELS.LISTED_AVG, Format.Rating(imported.avgListedRating)))
    table.insert(lines, Format.StatLine(PVL.LABELS.LISTED_MEDIAN, Format.Rating(imported.medianListedRating)))
    table.insert(lines, Format.StatLine(PVL.LABELS.TOP100_AVG, Format.Rating(imported.top100Avg)))
    table.insert(lines, Format.StatLine("Peak rating", Format.Rating(imported.highest)))

    if representation ~= nil then
        table.insert(lines, Format.StatLine("Ladder share", Format.Percent(representation)))
    end
end
