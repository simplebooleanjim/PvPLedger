--- Persistence helpers for match observations and imported ladder snapshots.
--- @class PvPLedger
local PVL = PvPLedger

--- Returns a readable string when the client allows addon access.
--- Midnight scoreboard fields such as spec names may be secret in instanced PvP.
--- @param value any
--- @return string|nil
function PVL.GetAccessibleString(value)
    if value == nil then
        return nil
    end

    if issecretvalue and issecretvalue(value) then
        if canaccessvalue and canaccessvalue(value) then
            return value
        end
        return nil
    end

    if type(value) ~= "string" then
        return nil
    end

    local emptyOk, isEmpty = pcall(function()
        return value == ""
    end)
    if not emptyOk or isEmpty then
        return nil
    end

    return value
end

--- Returns true when addon code can safely read one string value.
--- @param value any
--- @return boolean
function PVL.CanUseString(value)
    return PVL.GetAccessibleString(value) ~= nil
end

--- Builds a stable player key from name and realm.
--- @param name string
--- @param realm string|nil
--- @return string
function PVL.MakePlayerKey(name, realm)
    name = PVL.GetAccessibleString(name)
    if name == nil then
        return ""
    end

    realm = PVL.GetAccessibleString(realm)
    if realm ~= nil then
        return string.format("%s-%s", name, realm)
    end

    return name
end

--- Builds a normalized player lookup key for imported ladder rows.
--- @param name string
--- @param realm string|nil
--- @return string
function PVL.NormalizePlayerLookupKey(name, realm)
    name = PVL.GetAccessibleString(name)
    if name == nil then
        return ""
    end

    local normalizedName = string.lower(name)
    realm = PVL.GetAccessibleString(realm)
    if realm == nil then
        return normalizedName
    end

    local normalizedRealm = string.lower(realm):gsub("[^a-z0-9]", "")
    return string.format("%s-%s", normalizedName, normalizedRealm)
end

--- Parses a player key into name and realm components.
--- @param playerKey string
--- @return string name, string|nil realm
function PVL.ParsePlayerKey(playerKey)
    if not playerKey then
        return "", nil
    end

    local name, realm = playerKey:match("^(.-)%-(.+)$")
    if name and realm then
        return name, realm
    end

    return playerKey, nil
end

--- Builds a stable spec aggregate key such as EVOKER_DEVASTATION.
--- @param classToken string
--- @param specKey string
--- @return string|nil
function PVL.MakeSpecKey(classToken, specKey)
    if classToken == nil or specKey == nil then
        return nil
    end

    classToken = PVL.GetAccessibleString(classToken) or classToken
    specKey = PVL.GetAccessibleString(specKey)
    if specKey == nil then
        return nil
    end

    return string.format("%s_%s", classToken, specKey)
end

--- Normalizes a spec display name from scoreboard data into a spec key.
--- Scoreboard talentSpec values are often secret in instanced PvP; callers should
--- expect nil when Blizzard withholds the string from addon code.
--- @param classToken string
--- @param specName string|nil Already filtered through GetAccessibleString when possible.
--- @return string|nil
function PVL.NormalizeSpecKey(classToken, specName)
    if classToken == nil then
        return nil
    end

    specName = PVL.GetAccessibleString(specName)
    if specName == nil then
        return nil
    end

    local ok, normalized = pcall(function()
        return specName:upper():gsub("%s+", "")
    end)
    if not ok or normalized == nil then
        return nil
    end

    local emptyOk, isEmpty = pcall(function()
        return normalized == ""
    end)
    if not emptyOk or isEmpty then
        return nil
    end

    local specs = PVL.SPEC_KEYS_BY_CLASS[classToken]
    if not specs then
        return normalized
    end

    for _, specKey in ipairs(specs) do
        if specKey == normalized then
            return specKey
        end
    end

    return normalized
end

--- Returns the live account database table.
--- @return table
function PVL.GetDB()
    return PvPLedgerDB
end

--- Returns the live per-character database table.
--- @return table
function PVL.GetCharDB()
    return PvPLedgerCharDB
end

--- Stores one match observation and updates player/spec aggregates.
--- @param matchRecord table
function PVL.StoreMatch(matchRecord)
    local db = PVL.GetDB()
    if not db or not matchRecord then
        return
    end

    table.insert(db.observations.matches, matchRecord)
    PVL.PruneMatches()

    for _, participant in ipairs(matchRecord.roster or {}) do
        PVL.UpdatePlayerObservation(participant, matchRecord.timestamp)
    end
end

--- Updates rolling player and spec-count aggregates from one participant row.
--- @param participant table
--- @param timestamp number
function PVL.UpdatePlayerObservation(participant, timestamp)
    local db = PVL.GetDB()
    if not db or not participant or not PVL.CanUseString(participant.name) then
        return
    end

    local playerKey = PVL.MakePlayerKey(participant.name, participant.realm)
    if playerKey == "" then
        return
    end

    local players = db.observations.players
    local record = players[playerKey] or {
        name = participant.name,
        realm = participant.realm,
        class = participant.class,
        specs = {},
        matchesSeen = 0,
        lastSeenAt = timestamp,
    }

    record.class = participant.class or record.class
    record.matchesSeen = (record.matchesSeen or 0) + 1
    record.lastSeenAt = timestamp

    if participant.spec then
        record.specs[participant.spec] = (record.specs[participant.spec] or 0) + 1
        PVL.IncrementSpecCount(participant.class, participant.spec)
    end

    players[playerKey] = record
end

--- Increments observed spec frequency counters for the current bracket filter.
--- @param classToken string|nil
--- @param specKey string|nil
function PVL.IncrementSpecCount(classToken, specKey)
    local db = PVL.GetDB()
    local aggregateKey = PVL.MakeSpecKey(classToken, specKey)
    if not db or not aggregateKey then
        return
    end

    local counts = db.observations.specCounts
    counts[aggregateKey] = (counts[aggregateKey] or 0) + 1
end

--- Removes oldest match rows when the local retention cap is exceeded.
function PVL.PruneMatches()
    local db = PVL.GetDB()
    if not db then
        return
    end

    local matches = db.observations.matches
    while #matches > PVL.MAX_MATCHES do
        table.remove(matches, 1)
    end
end

--- Returns the active UI bracket filter.
--- @return string
function PVL.GetActiveBracketFilter()
    local db = PVL.GetDB()
    local bracket = db and db.settings.uiFilters and db.settings.uiFilters.bracket
    if bracket and PVL.BRACKET_NAMES[bracket] then
        return bracket
    end

    return PVL.BRACKETS.BLITZ
end

--- Returns dropdown options for bracket filtering.
--- @return table[]
function PVL.GetBracketFilterOptions()
    local options = {}

    for _, bracket in ipairs(PVL.IMPORTED_BRACKETS) do
        table.insert(options, {
            label = PVL.BRACKET_NAMES[bracket] or bracket,
            value = bracket,
        })
    end

    return options
end

--- Strips bulky player lookup tables from imported snapshots to reduce runtime memory.
--- @param snapshot table
--- @return table
function PVL.CompactImportedSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return snapshot
    end

    local compact = {}
    for key, value in pairs(snapshot) do
        if key ~= "players" then
            compact[key] = value
        end
    end

    return compact
end

--- Removes player lookup tables from all imported snapshots.
function PVL.PruneImportedSnapshotPlayers()
    for bracket, snapshot in pairs(PVL.ImportedSnapshots or {}) do
        if type(snapshot) == "table" and snapshot.players then
            PVL.ImportedSnapshots[bracket] = PVL.CompactImportedSnapshot(snapshot)
        end
    end
end

--- Attaches an imported ladder snapshot produced by the external collector.
--- @param snapshot table
function PVL.SetImportedSnapshot(snapshot)
    if not snapshot or not snapshot.bracket then
        return
    end

    PVL.ImportedSnapshots = PVL.ImportedSnapshots or {}
    PVL.ImportedSnapshots[snapshot.bracket] = snapshot
end

--- Returns the imported snapshot for one bracket.
--- @param bracket string|nil
--- @return table|nil
function PVL.GetImportedSnapshot(bracket)
    local snapshots = PVL.ImportedSnapshots
    if not snapshots then
        return nil
    end

    return snapshots[bracket or PVL.GetActiveBracketFilter()]
end

--- Returns a readable age label for one ISO snapshot date.
--- @param snapshotDate string|nil
--- @return string
function PVL.FormatSnapshotAge(snapshotDate)
    if not snapshotDate then
        return "unknown age"
    end

    local year, month, day = snapshotDate:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not year then
        return snapshotDate
    end

    local snapshotTime = time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = 12,
    })

    if not snapshotTime then
        return snapshotDate
    end

    local ageDays = math.floor((time() - snapshotTime) / 86400)
    if ageDays <= 0 then
        return "today"
    end

    if ageDays == 1 then
        return "1 day old"
    end

    return string.format("%d days old", ageDays)
end

--- Returns chat status lines for all packaged imported snapshots.
--- @return string[]
function PVL.GetImportedSnapshotStatusLines()
    local lines = {}

    for _, bracket in ipairs(PVL.IMPORTED_BRACKETS) do
        local snapshot = PVL.GetImportedSnapshot(bracket)
        local bracketName = PVL.BRACKET_NAMES[bracket] or bracket

        if snapshot then
            local sourceLabel = PVL.GetSnapshotSource(bracket) or "unknown"
            table.insert(lines, string.format(
                "%s: %s (%s) — %s [%s]",
                bracketName,
                snapshot.snapshotDate or "unknown date",
                PVL.FormatSnapshotAge(snapshot.snapshotDate),
                snapshot.source or "unknown source",
                sourceLabel
            ))
        else
            table.insert(lines, string.format("%s: not loaded", bracketName))
        end
    end

    return lines
end

--- Returns the local player's spec key from one stored match record.
--- @param matchRecord table|nil
--- @return string|nil
function PVL.GetMatchPlayerSpec(matchRecord)
    if type(matchRecord) ~= "table" then
        return nil
    end

    if matchRecord.playerSpec then
        return matchRecord.playerSpec
    end

    for _, participant in ipairs(matchRecord.roster or {}) do
        if participant.isLocalPlayer and participant.spec then
            if participant.spec:find("_", 1, true) then
                return participant.spec
            end

            return PVL.MakeSpecKey(participant.class, participant.spec)
        end
    end

    return nil
end

--- Returns true when a player spec key matches class/spec UI filters.
--- @param playerSpec string|nil
--- @param classToken string|nil
--- @param specKey string|nil
--- @return boolean
function PVL.PlayerSpecMatchesFilter(playerSpec, classToken, specKey)
    if specKey then
        return playerSpec == specKey
    end

    if classToken then
        if not playerSpec then
            return false
        end

        return playerSpec:match("^(.-)_") == classToken
    end

    return true
end

--- Returns true when one stored match matches class/spec UI filters.
--- @param matchRecord table|nil
--- @param classToken string|nil
--- @param specKey string|nil
--- @return boolean
function PVL.MatchMatchesPlayerSpecFilter(matchRecord, classToken, specKey)
    if not classToken and not specKey then
        return true
    end

    return PVL.PlayerSpecMatchesFilter(PVL.GetMatchPlayerSpec(matchRecord), classToken, specKey)
end

--- Backfills playerSpec on stored matches that predate per-spec tracking.
function PVL.BackfillMatchPlayerSpecs()
    local db = PVL.GetDB()
    if not db or type(db.observations) ~= "table" then
        return
    end

    for _, match in ipairs(db.observations.matches or {}) do
        if type(match) == "table" and not match.playerSpec then
            match.playerSpec = PVL.GetMatchPlayerSpec(match)
        end
    end
end

--- Returns observed matches for one bracket optionally filtered by timestamp and player spec.
--- @param bracket string|nil
--- @param sinceTimestamp number|nil
--- @param filters table|nil Optional `{ classToken, specKey }` player-spec filters.
--- @return table[]
function PVL.GetObservedMatches(bracket, sinceTimestamp, filters)
    local db = PVL.GetDB()
    if not db then
        return {}
    end

    local activeBracket = bracket or PVL.GetActiveBracketFilter()
    local classToken = filters and filters.classToken or nil
    local specKey = filters and filters.specKey or nil
    local results = {}
    for _, match in ipairs(db.observations.matches) do
        if match.bracket == activeBracket then
            if not sinceTimestamp or (match.timestamp and match.timestamp >= sinceTimestamp) then
                if PVL.MatchMatchesPlayerSpecFilter(match, classToken, specKey) then
                    table.insert(results, match)
                end
            end
        end
    end

    return results
end

--- Returns one stored match observation by match id.
--- @param matchId string|nil
--- @return table|nil
function PVL.GetMatchById(matchId)
    if not matchId or matchId == "" then
        return nil
    end

    local db = PVL.GetDB()
    if not db or type(db.observations) ~= "table" then
        return nil
    end

    for index = #db.observations.matches, 1, -1 do
        local match = db.observations.matches[index]
        if match and match.matchId == matchId then
            return match
        end
    end

    return nil
end

--- Returns observed matches for one bracket, newest first.
--- @param bracket string|nil
--- @param limit number|nil
--- @param filters table|nil Optional `{ classToken, specKey }` player-spec filters.
--- @return table[]
function PVL.GetRecentMatches(bracket, limit, filters)
    local matches = PVL.GetObservedMatches(bracket, nil, filters)
    table.sort(matches, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    if not limit or #matches <= limit then
        return matches
    end

    local results = {}
    for index = 1, limit do
        results[index] = matches[index]
    end

    return results
end

--- Returns total observed spec counts as an array of sortable rows.
--- @param bracket string|nil
--- @return table[]
function PVL.GetObservedSpecRows(bracket)
    local db = PVL.GetDB()
    if not db then
        return {}
    end

    local activeBracket = bracket or PVL.GetActiveBracketFilter()
    local counts = {}

    for _, match in ipairs(db.observations.matches) do
        if match.bracket == activeBracket then
            for _, participant in ipairs(match.roster or {}) do
                local aggregateKey = PVL.MakeSpecKey(participant.class, participant.spec)
                if aggregateKey then
                    counts[aggregateKey] = (counts[aggregateKey] or 0) + 1
                end
            end
        end
    end

    local rows = {}
    for specKey, count in pairs(counts) do
        local classToken, specToken = specKey:match("^(.-)_(.+)$")
        table.insert(rows, {
            specKey = specKey,
            classToken = classToken,
            specToken = specToken,
            count = count,
        })
    end

    table.sort(rows, function(a, b)
        if a.count == b.count then
            return a.specKey < b.specKey
        end
        return a.count > b.count
    end)

    return rows
end
