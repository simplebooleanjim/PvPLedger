--- Persistence helpers for match observations and imported ladder snapshots.
--- @class PvPLedger
local PVL = PvPLedger

--- Builds a stable player key from name and realm.
--- @param name string
--- @param realm string|nil
--- @return string
function PVL.MakePlayerKey(name, realm)
    if not name or name == "" then
        return ""
    end

    if realm and realm ~= "" then
        return string.format("%s-%s", name, realm)
    end

    return name
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
    if not classToken or not specKey then
        return nil
    end

    return string.format("%s_%s", classToken, specKey)
end

--- Normalizes a spec display name from scoreboard data into a spec key.
--- @param classToken string
--- @param specName string|nil
--- @return string|nil
function PVL.NormalizeSpecKey(classToken, specName)
    if not classToken or not specName or specName == "" then
        return nil
    end

    local normalized = specName:upper():gsub("%s+", "")
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
    if not db or not participant or not participant.name then
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

--- Attaches an imported ladder snapshot produced by the external collector.
--- @param snapshot table
function PVL.SetImportedSnapshot(snapshot)
    local db = PVL.GetDB()
    if db then
        db.imported = snapshot
    end
end

--- Returns the currently loaded imported snapshot, if any.
--- @return table|nil
function PVL.GetImportedSnapshot()
    local db = PVL.GetDB()
    return db and db.imported or nil
end

--- Returns observed Blitz matches optionally filtered by a minimum timestamp.
--- @param sinceTimestamp number|nil
--- @return table[]
function PVL.GetObservedMatches(sinceTimestamp)
    local db = PVL.GetDB()
    if not db then
        return {}
    end

    local results = {}
    for _, match in ipairs(db.observations.matches) do
        if match.bracket == PVL.BRACKETS.BLITZ then
            if not sinceTimestamp or (match.timestamp and match.timestamp >= sinceTimestamp) then
                table.insert(results, match)
            end
        end
    end

    return results
end

--- Returns total observed spec counts as an array of sortable rows.
--- @return table[]
function PVL.GetObservedSpecRows()
    local db = PVL.GetDB()
    if not db then
        return {}
    end

    local rows = {}
    for specKey, count in pairs(db.observations.specCounts) do
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
