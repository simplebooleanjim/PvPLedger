--- Aggregate math and comparison helpers for imported and observed ladder data.
--- @class PvPLedger
local PVL = PvPLedger

--- Computes the total count from a bucket table keyed by rating ranges.
--- @param buckets table<string, number>|nil
--- @return number
function PVL.SumBuckets(buckets)
    local total = 0
    if not buckets then
        return total
    end

    for _, count in pairs(buckets) do
        total = total + count
    end

    return total
end

--- Returns imported aggregate data for one spec key.
--- @param specKey string
--- @return table|nil
function PVL.GetImportedSpecAggregate(specKey)
    local snapshot = PVL.GetImportedSnapshot()
    if not snapshot or not snapshot.bySpec then
        return nil
    end

    return snapshot.bySpec[specKey]
end

--- Returns imported overall aggregate data.
--- @return table|nil
function PVL.GetImportedOverallAggregate()
    local snapshot = PVL.GetImportedSnapshot()
    return snapshot and snapshot.overall or nil
end

--- Builds a simple representation percentage for one spec among all imported specs.
--- @param specKey string
--- @return number|nil
function PVL.GetImportedSpecRepresentation(specKey)
    local snapshot = PVL.GetImportedSnapshot()
    if not snapshot or not snapshot.bySpec then
        return nil
    end

    local specRow = snapshot.bySpec[specKey]
    if not specRow or not specRow.listedCount then
        return nil
    end

    local totalListed = 0
    for _, row in pairs(snapshot.bySpec) do
        totalListed = totalListed + (row.listedCount or 0)
    end

    if totalListed <= 0 then
        return nil
    end

    return (specRow.listedCount / totalListed) * 100
end

--- Builds observed spec frequency percentages from local match data.
--- @return table[]
function PVL.GetObservedSpecPercentages()
    local rows = PVL.GetObservedSpecRows()
    local total = 0

    for _, row in ipairs(rows) do
        total = total + row.count
    end

    if total <= 0 then
        return {}
    end

    local results = {}
    for _, row in ipairs(rows) do
        table.insert(results, {
            specKey = row.specKey,
            classToken = row.classToken,
            specToken = row.specToken,
            count = row.count,
            percent = (row.count / total) * 100,
        })
    end

    return results
end

--- Compares the current character rating against imported cutoff buckets.
--- @param rating number|nil
--- @return table|nil
function PVL.EstimateListedStanding(rating)
    local overall = PVL.GetImportedOverallAggregate()
    if not overall or not rating or not overall.cutoffs then
        return nil
    end

    local standing = {
        rating = rating,
        cutoffLabel = "Unlisted",
    }

    for _, cutoff in ipairs(overall.cutoffs) do
        if rating >= cutoff.rating then
            standing.cutoffLabel = cutoff.label
            standing.rankThreshold = cutoff.rank
        end
    end

    return standing
end

--- Formats a number for compact UI display.
--- @param value number|nil
--- @return string
function PVL.FormatRating(value)
    if not value then
        return "--"
    end

    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value)
    end

    return tostring(math.floor(value + 0.5))
end

--- Formats a percentage with one decimal place.
--- @param value number|nil
--- @return string
function PVL.FormatPercent(value)
    if not value then
        return "--"
    end

    return string.format("%.1f%%", value)
end

--- Converts a token such as DEVASTATION into title case.
--- @param token string|nil
--- @return string
function PVL.TitleCaseToken(token)
    if not token then
        return ""
    end

    local lower = string.lower(token)
    return string.upper(string.sub(lower, 1, 1)) .. string.sub(lower, 2)
end

--- Returns a readable label for a CLASS_SPEC key.
--- @param specKey string|nil
--- @return string
function PVL.FormatSpecDisplayName(specKey)
    if not specKey then
        return "All Specs"
    end

    local classToken, specToken = specKey:match("^(.-)_(.+)$")
    if not classToken or not specToken then
        return specKey
    end

    local className = PVL.CLASS_NAMES[classToken] or PVL.TitleCaseToken(classToken)
    return string.format("%s %s", PVL.TitleCaseToken(specToken), className)
end

--- Returns dropdown options for class filtering.
--- @return table[]
function PVL.GetClassFilterOptions()
    local options = {
        { label = "All Classes", value = nil },
    }

    for _, classToken in ipairs(PVL.CLASS_ORDER) do
        table.insert(options, {
            label = PVL.CLASS_NAMES[classToken] or classToken,
            value = classToken,
        })
    end

    return options
end

--- Returns dropdown options for spec filtering.
--- @param classToken string|nil
--- @return table[]
function PVL.GetSpecFilterOptions(classToken)
    local options = {
        { label = "All Specs", value = nil },
    }

    if classToken and PVL.SPEC_KEYS_BY_CLASS[classToken] then
        for _, specToken in ipairs(PVL.SPEC_KEYS_BY_CLASS[classToken]) do
            local specKey = PVL.MakeSpecKey(classToken, specToken)
            table.insert(options, {
                label = PVL.FormatSpecDisplayName(specKey),
                value = specKey,
            })
        end
        return options
    end

    for _, token in ipairs(PVL.CLASS_ORDER) do
        for _, specToken in ipairs(PVL.SPEC_KEYS_BY_CLASS[token] or {}) do
            local specKey = PVL.MakeSpecKey(token, specToken)
            table.insert(options, {
                label = PVL.FormatSpecDisplayName(specKey),
                value = specKey,
            })
        end
    end

    return options
end

--- Finds the selected index for a dropdown option list.
--- @param options table[]
--- @param value any
--- @return number
function PVL.GetSelectedOptionIndex(options, value)
    for index, option in ipairs(options) do
        if option.value == value then
            return index
        end
    end

    return 1
end

--- Returns observed spec rows filtered by class and/or spec.
--- @param classToken string|nil
--- @param specKey string|nil
--- @return table[]
function PVL.GetFilteredObservedSpecPercentages(classToken, specKey)
    local rows = PVL.GetObservedSpecPercentages()
    local filtered = {}

    for _, row in ipairs(rows) do
        local classMatches = not classToken or row.classToken == classToken
        local specMatches = not specKey or row.specKey == specKey
        if classMatches and specMatches then
            table.insert(filtered, row)
        end
    end

    if #filtered == 0 then
        return filtered
    end

    local total = 0
    for _, row in ipairs(filtered) do
        total = total + row.count
    end

    for _, row in ipairs(filtered) do
        row.percent = (row.count / total) * 100
    end

    return filtered
end

--- Builds imported and observed detail metrics for one spec card.
--- @param specKey string|nil
--- @return table|nil
function PVL.BuildSpecDetailSummary(specKey)
    if not specKey then
        return nil
    end

    local imported = PVL.GetImportedSpecAggregate(specKey)
    local observedRows = PVL.GetFilteredObservedSpecPercentages(nil, specKey)
    local observed = observedRows[1]

    return {
        specKey = specKey,
        displayName = PVL.FormatSpecDisplayName(specKey),
        imported = imported,
        importedRepresentation = PVL.GetImportedSpecRepresentation(specKey),
        observedCount = observed and observed.count or 0,
        observedPercent = observed and observed.percent or nil,
    }
end

--- Builds imported spec rows optionally filtered by class/spec.
--- @param classToken string|nil
--- @param specKey string|nil
--- @return table[]
function PVL.GetFilteredImportedSpecRows(classToken, specKey)
    local snapshot = PVL.GetImportedSnapshot()
    if not snapshot or not snapshot.bySpec then
        return {}
    end

    local rows = {}
    for key, row in pairs(snapshot.bySpec) do
        local rowClass, rowSpec = key:match("^(.-)_(.+)$")
        local classMatches = not classToken or rowClass == classToken
        local specMatches = not specKey or key == specKey
        if classMatches and specMatches then
            table.insert(rows, {
                specKey = key,
                listedCount = row.listedCount or 0,
                avgListedRating = row.avgListedRating,
                medianListedRating = row.medianListedRating,
                top100Avg = row.top100Avg,
                highest = row.highest,
                representation = PVL.GetImportedSpecRepresentation(key),
            })
        end
    end

    table.sort(rows, function(a, b)
        if a.listedCount == b.listedCount then
            return a.specKey < b.specKey
        end
        return a.listedCount > b.listedCount
    end)

    return rows
end

--- Builds a short summary table for the main UI panel.
--- @return table
function PVL.BuildDashboardSummary()
    local snapshot = PVL.GetImportedSnapshot()
    local observedRows = PVL.GetObservedSpecPercentages()
    local charDb = PVL.GetCharDB()

    return {
        imported = snapshot,
        importedOverall = snapshot and snapshot.overall or nil,
        observedTopSpecs = { observedRows[1], observedRows[2], observedRows[3] },
        matchCount = #(PVL.GetObservedMatches() or {}),
        playerCR = charDb and charDb.lastBlitzCR or nil,
        playerMMR = charDb and charDb.lastBlitzMMR or nil,
        standing = PVL.EstimateListedStanding(charDb and charDb.lastBlitzCR or nil),
    }
end
