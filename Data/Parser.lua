--- Aggregate math and comparison helpers for imported and observed ladder data.
--- @class PvPLedger
local PVL = PvPLedger

--- Returns true when a bracket uses one combined Blizzard imported ladder slug.
--- @param bracket string|nil
--- @return boolean
function PVL.IsCombinedImportedBracket(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    for _, combinedBracket in ipairs(PVL.COMBINED_IMPORTED_BRACKETS) do
        if bracket == combinedBracket then
            return true
        end
    end

    return false
end

--- Returns true when the active imported snapshot includes class/spec aggregates.
--- @param bracket string|nil
--- @return boolean
function PVL.HasImportedSpecBreakdown(bracket)
    local snapshot = PVL.GetImportedSnapshot(bracket)
    if not snapshot or type(snapshot.bySpec) ~= "table" then
        return false
    end

    for _ in pairs(snapshot.bySpec) do
        return true
    end

    return false
end

--- Returns true when imported class/spec breakdown is unavailable for the bracket.
--- @param bracket string|nil
--- @return boolean
function PVL.IsImportedSpecBreakdownMissing(bracket)
    return PVL.IsCombinedImportedBracket(bracket) and not PVL.HasImportedSpecBreakdown(bracket)
end

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

--- Returns imported class aggregate data.
--- @param classToken string
--- @return table|nil
function PVL.GetImportedClassAggregate(classToken)
    local snapshot = PVL.GetImportedSnapshot()
    if not snapshot or not snapshot.byClass or not classToken then
        return nil
    end

    return snapshot.byClass[classToken]
end

--- Builds a representation percentage for one class among all imported classes.
--- @param classToken string
--- @return number|nil
function PVL.GetImportedClassRepresentation(classToken)
    local snapshot = PVL.GetImportedSnapshot()
    if not snapshot or not snapshot.byClass or not classToken then
        return nil
    end

    local classRow = snapshot.byClass[classToken]
    if not classRow or not classRow.listedCount then
        return nil
    end

    local totalListed = 0
    for _, row in pairs(snapshot.byClass) do
        totalListed = totalListed + (row.listedCount or 0)
    end

    if totalListed <= 0 then
        return nil
    end

    return (classRow.listedCount / totalListed) * 100
end

--- Returns imported class rows sorted by listed count.
--- @return table[]
function PVL.GetImportedClassRows()
    local snapshot = PVL.GetImportedSnapshot()
    if not snapshot or not snapshot.byClass then
        return {}
    end

    local rows = {}
    for classToken, row in pairs(snapshot.byClass) do
        table.insert(rows, {
            classToken = classToken,
            displayName = PVL.CLASS_NAMES[classToken] or PVL.TitleCaseToken(classToken),
            listedCount = row.listedCount or 0,
            avgListedRating = row.avgListedRating,
            medianListedRating = row.medianListedRating,
            top100Avg = row.top100Avg,
            highest = row.highest,
            representation = PVL.GetImportedClassRepresentation(classToken),
        })
    end

    table.sort(rows, function(a, b)
        if a.listedCount == b.listedCount then
            return a.classToken < b.classToken
        end
        return a.listedCount > b.listedCount
    end)

    return rows
end

--- Builds imported and observed detail metrics for one class with all specs selected.
--- @param classToken string
--- @return table|nil
function PVL.BuildClassDetailSummary(classToken)
    if not classToken then
        return nil
    end

    local imported = PVL.GetImportedClassAggregate(classToken)
    local specRows = PVL.GetFilteredImportedSpecRows(classToken, nil)
    local observedRows = PVL.GetFilteredObservedSpecPercentages(classToken, nil)
    local observedCount = 0
    local observedPercentTotal = 0

    for _, row in ipairs(observedRows) do
        observedCount = observedCount + row.count
        observedPercentTotal = observedPercentTotal + (row.percent or 0)
    end

    return {
        classToken = classToken,
        displayName = PVL.CLASS_NAMES[classToken] or PVL.TitleCaseToken(classToken),
        imported = imported,
        importedRepresentation = PVL.GetImportedClassRepresentation(classToken),
        importedSpecRows = specRows,
        observedCount = observedCount,
        observedPercent = observedPercentTotal > 0 and observedPercentTotal or nil,
        observedSpecRows = observedRows,
    }
end

--- Returns one imported listed player row from the snapshot player index.
--- @param snapshot table|nil
--- @param name string
--- @param realm string|nil
--- @return table|nil
function PVL.LookupPlayerInSnapshot(snapshot, name, realm)
    if not snapshot or not snapshot.players or not name or name == "" then
        return nil
    end

    local playerKey = PVL.NormalizePlayerLookupKey(name, realm)
    if playerKey == "" then
        return nil
    end

    return snapshot.players[playerKey]
end

--- Returns one imported listed player row from the snapshot player index.
--- @param name string
--- @param realm string|nil
--- @param bracket string|nil
--- @return table|nil
function PVL.LookupListedPlayer(name, realm, bracket)
    local snapshot = PVL.GetImportedSnapshot(bracket)
    return PVL.LookupPlayerInSnapshot(snapshot, name, realm)
end

--- Returns how many imported listed players are present in the snapshot player index.
--- @param bracket string|nil
--- @return number
function PVL.GetImportedPlayerCount(bracket)
    local snapshot = PVL.GetImportedSnapshot(bracket)
    if not snapshot or not snapshot.players then
        return 0
    end

    local count = 0
    for _ in pairs(snapshot.players) do
        count = count + 1
    end

    return count
end

--- Formats one normalized player lookup key for UI display.
--- @param playerKey string|nil
--- @param row table|nil Optional imported player row with a preserved displayName.
--- @return string
function PVL.FormatPlayerKeyDisplay(playerKey, row)
    if row and row.displayName and row.displayName ~= "" then
        return row.displayName
    end

    if not playerKey or playerKey == "" then
        return "--"
    end

    local name, realm = PVL.ParsePlayerKey(playerKey)
    local displayName = PVL.TitleCaseToken(name)
    if realm and realm ~= "" then
        return string.format("%s-%s", displayName, PVL.TitleCaseToken(realm))
    end

    return displayName
end

--- Returns true when one imported player row matches class/spec filters.
--- @param row table
--- @param classToken string|nil
--- @param specKey string|nil
--- @return boolean
local function ImportedPlayerMatchesFilters(row, classToken, specKey)
    if specKey then
        return row.specKey == specKey
    end

    if classToken then
        local rowClass = row.specKey and row.specKey:match("^(.-)_")
        return rowClass == classToken
    end

    return true
end

--- Returns imported ladder player rows filtered by bracket/class/spec.
--- @param bracket string|nil
--- @param classToken string|nil
--- @param specKey string|nil
--- @param limit number|nil
--- @return table[]
function PVL.GetFilteredImportedLadderPlayers(bracket, classToken, specKey, limit)
    bracket = bracket or PVL.GetActiveBracketFilter()
    limit = limit or PVL.LADDER_VIEW_LIMIT

    local snapshot = PVL.GetImportedSnapshot(bracket)
    if not snapshot or not snapshot.players then
        return {}
    end

    local rows = {}
    for playerKey, row in pairs(snapshot.players) do
        if type(row) == "table" and ImportedPlayerMatchesFilters(row, classToken, specKey) then
            table.insert(rows, {
                playerKey = playerKey,
                displayName = PVL.FormatPlayerKeyDisplay(playerKey, row),
                specKey = row.specKey,
                rating = row.rating,
                rank = row.rank,
                wins = row.wins,
                losses = row.losses,
                faction = row.faction,
            })
        end
    end

    table.sort(rows, function(left, right)
        local leftRank = left.rank or 999999
        local rightRank = right.rank or 999999
        if leftRank ~= rightRank then
            return leftRank < rightRank
        end

        local leftRating = left.rating or 0
        local rightRating = right.rating or 0
        if leftRating ~= rightRating then
            return leftRating > rightRating
        end

        return (left.displayName or "") < (right.displayName or "")
    end)

    if #rows > limit then
        local trimmed = {}
        for index = 1, limit do
            trimmed[index] = rows[index]
        end
        return trimmed
    end

    return rows
end

--- Counts how many observed match participants appear in the imported player index.
--- @return number listedCount, number observedCount
function PVL.CountListedObservedPlayers()
    local db = PVL.GetDB()
    if not db then
        return 0, 0
    end

    local seen = {}
    local observedCount = 0
    local activeBracket = PVL.GetActiveBracketFilter()

    for _, match in ipairs(db.observations.matches or {}) do
        if match.bracket == activeBracket then
            for _, participant in ipairs(match.roster or {}) do
                local playerKey = PVL.MakePlayerKey(participant.name, participant.realm)
                if playerKey ~= "" and not seen[playerKey] then
                    seen[playerKey] = true
                    observedCount = observedCount + 1
                end
            end
        end
    end

    local listedCount = 0
    for playerKey, _ in pairs(seen) do
        local name, realm = PVL.ParsePlayerKey(playerKey)
        if PVL.LookupListedPlayer(name, realm) then
            listedCount = listedCount + 1
        end
    end

    return listedCount, observedCount
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

--- Returns the imported ladder row for the current character when listed.
--- @param bracket string|nil
--- @return table|nil
function PVL.GetListedCharacterRow(bracket)
    if not UnitName then
        return nil
    end

    local name = UnitName("player")
    if not name or name == "" then
        return nil
    end

    local realm = GetRealmName and GetRealmName() or ""
    return PVL.LookupListedPlayer(name, realm, bracket)
end

--- Estimates overall ladder rank by counting imported players above a rating.
--- @param rating number|nil
--- @param bracket string|nil
--- @return number|nil estimatedRank
--- @return number ladderSize
function PVL.EstimateRankFromImportedLadder(rating, bracket)
    if not rating then
        return nil, 0
    end

    bracket = bracket or PVL.GetActiveBracketFilter()
    local rows = PVL.GetFilteredImportedLadderPlayers(bracket, nil, nil, 100000)
    if #rows == 0 then
        return nil, 0
    end

    local higherCount = 0
    for _, row in ipairs(rows) do
        if row.rating and row.rating > rating then
            higherCount = higherCount + 1
        end
    end

    return higherCount + 1, #rows
end

--- Builds a display label for an estimated or listed ladder standing.
--- @param standing table|nil
--- @return string
function PVL.FormatStandingLabel(standing)
    if not standing then
        return "Unlisted"
    end

    if standing.listedRank then
        return string.format("#%s", PVL.FormatRating(standing.listedRank))
    end

    if standing.estimatedRank then
        local prefix = standing.isEstimated and "~" or ""
        return string.format("%s#%s", prefix, PVL.FormatRating(standing.estimatedRank))
    end

    return standing.cutoffLabel or "Unlisted"
end

--- Compares the current character rating against imported ladder rows and cutoffs.
--- @param rating number|nil
--- @param bracket string|nil
--- @return table|nil
function PVL.EstimateListedStanding(rating, bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    local snapshot = PVL.GetImportedSnapshot(bracket)
    local overall = snapshot and snapshot.overall or nil
    if not overall or not rating then
        return nil
    end

    local standing = {
        rating = rating,
        cutoffLabel = "Unlisted",
        isEstimated = true,
    }

    for _, cutoff in ipairs(overall.cutoffs or {}) do
        if rating >= cutoff.rating then
            standing.cutoffLabel = cutoff.label
            standing.rankThreshold = cutoff.rank
        end
    end

    local listedRow = PVL.GetListedCharacterRow(bracket)
    if listedRow and listedRow.rank then
        standing.listedRank = listedRow.rank
        standing.isEstimated = false
        standing.isListed = true
        return standing
    end

    local estimatedRank, ladderSize = PVL.EstimateRankFromImportedLadder(rating, bracket)
    if estimatedRank then
        standing.estimatedRank = estimatedRank
        standing.ladderSize = ladderSize
        standing.isListed = false

        if ladderSize > 0 and estimatedRank > ladderSize then
            standing.cutoffLabel = string.format("Below #%s", PVL.FormatRating(ladderSize))
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

--- Returns the UTF-8 byte length of the character starting at one position.
--- @param str string
--- @param startIndex number|nil
--- @return number
function PVL.Utf8CharByteLength(str, startIndex)
    startIndex = startIndex or 1
    local byte = str:byte(startIndex)
    if not byte then
        return 0
    end

    if byte >= 0xF0 then
        return 4
    elseif byte >= 0xE0 then
        return 3
    elseif byte >= 0xC0 then
        return 2
    end

    return 1
end

--- Converts a token such as DEVASTATION into title case.
--- @param token string|nil
--- @return string
function PVL.TitleCaseToken(token)
    if not token then
        return ""
    end

    local lower = string.lower(token)
    local firstLength = PVL.Utf8CharByteLength(lower, 1)
    if firstLength <= 0 then
        return lower
    end

    local first = lower:sub(1, firstLength)
    local rest = lower:sub(firstLength + 1)
    return string.upper(first) .. rest
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
    local formatClass = PVL.UI and PVL.UI.Format and PVL.UI.Format.ClassName

    for _, classToken in ipairs(PVL.CLASS_ORDER) do
        table.insert(options, {
            label = formatClass and formatClass(classToken) or (PVL.CLASS_NAMES[classToken] or classToken),
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
    local formatSpec = PVL.UI and PVL.UI.Format and PVL.UI.Format.SpecName

    local function addSpecOption(token, specToken)
        local specKey = PVL.MakeSpecKey(token, specToken)
        table.insert(options, {
            label = formatSpec and formatSpec(specKey) or PVL.FormatSpecDisplayName(specKey),
            value = specKey,
        })
    end

    if classToken and PVL.SPEC_KEYS_BY_CLASS[classToken] then
        for _, specToken in ipairs(PVL.SPEC_KEYS_BY_CLASS[classToken]) do
            addSpecOption(classToken, specToken)
        end
        return options
    end

    for _, token in ipairs(PVL.CLASS_ORDER) do
        for _, specToken in ipairs(PVL.SPEC_KEYS_BY_CLASS[token] or {}) do
            addSpecOption(token, specToken)
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

--- Returns true when a bracket exposes team average MMR on the score screen.
--- @param bracket string|nil
--- @return boolean
function PVL.IsTeamObservedMmrBracket(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    return PVL.TEAM_OBSERVED_MMR_BRACKETS[bracket] == true
end

--- Returns true when a stored MMR value looks populated.
--- @param value number|nil
--- @return boolean
function PVL.IsValidObservedMmr(value)
    return type(value) == "number" and value > 0
end

--- Returns the UI label for the observed MMR field for one bracket.
--- @param bracket string|nil
--- @param mmrKind string|nil
--- @return string
function PVL.GetObservedMmrLabel(bracket, mmrKind)
    if mmrKind == "team" or (not mmrKind and PVL.IsTeamObservedMmrBracket(bracket)) then
        return PVL.LABELS.TEAM_AVG_MMR
    end

    return PVL.LABELS.PERSONAL_MMR
end

--- Normalizes stored MMR values and infers kind for legacy rows.
--- @param mmr number|nil
--- @param mmrKind string|nil
--- @param bracket string
--- @return number|nil, string|nil
function PVL.NormalizeObservedMmrFields(mmr, mmrKind, bracket)
    if not PVL.IsValidObservedMmr(mmr) then
        return nil, nil
    end

    if not mmrKind then
        if PVL.IsTeamObservedMmrBracket(bracket) then
            mmrKind = "team"
        else
            mmrKind = "personal"
        end
    end

    return mmr, mmrKind
end

--- Returns the latest character rating and MMR for one bracket.
--- @param bracket string|nil
--- @return number|nil rating, number|nil mmr, string|nil mmrKind
function PVL.GetCharacterRatingFields(bracket)
    local charDb = PVL.GetCharDB()
    if not charDb then
        return nil, nil, nil
    end

    local activeBracket = bracket or PVL.GetActiveBracketFilter()
    local rating, mmr, mmrKind

    if activeBracket == PVL.BRACKETS.SHUFFLE then
        rating, mmr, mmrKind = charDb.lastShuffleCR, charDb.lastShuffleMMR, charDb.lastShuffleMMRKind
    elseif activeBracket == PVL.BRACKETS.RBG then
        rating, mmr, mmrKind = charDb.lastRbgCR, charDb.lastRbgMMR, charDb.lastRbgMMRKind
    elseif activeBracket == PVL.BRACKETS.ARENA_2V2 then
        rating, mmr, mmrKind = charDb.lastArena2v2CR, charDb.lastArena2v2MMR, charDb.lastArena2v2MMRKind
    elseif activeBracket == PVL.BRACKETS.ARENA_3V3 then
        rating, mmr, mmrKind = charDb.lastArena3v3CR, charDb.lastArena3v3MMR, charDb.lastArena3v3MMRKind
    else
        rating, mmr, mmrKind = charDb.lastBlitzCR, charDb.lastBlitzMMR, charDb.lastBlitzMMRKind
    end

    mmr, mmrKind = PVL.NormalizeObservedMmrFields(mmr, mmrKind, activeBracket)
    return rating, mmr, mmrKind
end

--- Builds a short summary table for the main UI panel.
--- @return table
function PVL.BuildDashboardSummary()
    local bracket = PVL.GetActiveBracketFilter()
    local snapshot = PVL.GetImportedSnapshot(bracket)
    local observedRows = PVL.GetObservedSpecRows(bracket)
    local playerCR, playerMMR, playerMMRKind = PVL.GetCharacterRatingFields(bracket)
    local playerCurrentCR = PVL.RatedInfo and PVL.RatedInfo.GetCurrentRating(bracket) or nil
    local listedObservedCount, observedPlayerCount = PVL.CountListedObservedPlayers()

    return {
        bracket = bracket,
        imported = snapshot,
        importedOverall = snapshot and snapshot.overall or nil,
        importedPlayerCount = PVL.GetImportedPlayerCount(bracket),
        listedObservedCount = listedObservedCount,
        observedPlayerCount = observedPlayerCount,
        observedTopSpecs = { observedRows[1], observedRows[2], observedRows[3] },
        matchCount = #(PVL.GetObservedMatches(bracket) or {}),
        seasonRecord = PVL.RatedInfo and PVL.RatedInfo.GetSeasonRecord(bracket) or nil,
        playerCR = playerCR,
        playerCurrentCR = playerCurrentCR,
        playerMMR = playerMMR,
        playerMMRKind = playerMMRKind,
        standing = PVL.EstimateListedStanding(playerCurrentCR or playerCR, bracket),
        ladderStalenessLines = PVL.GetLadderStalenessLines(bracket),
    }
end
