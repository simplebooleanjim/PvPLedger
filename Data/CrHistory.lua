--- Persists and summarizes historical CR points from matches and live snapshots.
--- @class PvPLedger
local PVL = PvPLedger

PVL.CrHistory = PVL.CrHistory or {}
local CrHistory = PVL.CrHistory

CrHistory.frame = CrHistory.frame or nil
CrHistory.sessionStartedAt = CrHistory.sessionStartedAt or nil
CrHistory.sessionStartCrByBracket = CrHistory.sessionStartCrByBracket or {}

--- Returns the per-character CR history table.
--- @return table
function CrHistory.GetHistoryTable()
    local charDb = PVL.GetCharDB()
    charDb.crHistory = charDb.crHistory or {}
    return charDb.crHistory
end

--- Returns true when a CR value looks populated.
--- @param value number|nil
--- @return boolean
function CrHistory.IsValidCr(value)
    return type(value) == "number" and value > 0
end

--- Returns the most recent history entry for one bracket.
--- @param bracket string
--- @return table|nil
function CrHistory.GetLatestEntry(bracket)
    local history = CrHistory.GetHistoryTable()
    for index = #history, 1, -1 do
        local entry = history[index]
        if entry and entry.bracket == bracket then
            return entry
        end
    end

    return nil
end

--- Returns true when a history entry is a CR-only point rather than a match result.
--- @param entry table|nil
--- @return boolean
function CrHistory.IsCrOnlyEntry(entry)
    return type(entry) == "table" and entry.source ~= "match"
end

--- Returns the compact activity label shown in CR history lists.
--- @param entry table|nil
--- @return string
function CrHistory.GetEntryTypeLabel(entry)
    if entry and entry.source == "match" then
        return "match"
    end

    return "CR"
end

--- Returns true when a new CR-only entry would not add new information.
--- @param entry table
--- @return boolean
function CrHistory.IsDuplicateSnapshot(entry)
    if not CrHistory.IsCrOnlyEntry(entry) then
        return false
    end

    local latest = CrHistory.GetLatestEntry(entry.bracket)
    if not latest or not CrHistory.IsValidCr(latest.cr) then
        return false
    end

    return latest.cr == entry.cr
end

--- Removes invalid and redundant CR-only rows from saved history.
function CrHistory.PruneRedundantSnapshots()
    local history = CrHistory.GetHistoryTable()
    if #history == 0 then
        return
    end

    local nextCrByBracket = {}
    local kept = {}

    for index = #history, 1, -1 do
        local entry = history[index]
        if type(entry) ~= "table"
            or not entry.bracket
            or not CrHistory.IsValidCr(entry.cr) then
            -- Drop invalid rows such as unloaded CR reads of 0.
        elseif CrHistory.IsCrOnlyEntry(entry)
            and nextCrByBracket[entry.bracket] == entry.cr then
            -- Drop CR-only rows that repeat a newer point for the same bracket.
        else
            table.insert(kept, 1, entry)
            nextCrByBracket[entry.bracket] = entry.cr
        end
    end

    for index = 1, #history do
        history[index] = kept[index]
    end

    for index = #kept + 1, #history do
        history[index] = nil
    end
end

--- Returns recent CR history rows with redundant snapshots collapsed for display.
--- @param entries table[]
--- @param limit number|nil
--- @return table[]
function CrHistory.FilterRecentEntriesForDisplay(entries, limit)
    limit = limit or PVL.CR_HISTORY_UI_LIMIT
    local filtered = {}

    for index, entry in ipairs(entries) do
        if not CrHistory.IsValidCr(entry.cr) then
            -- Skip invalid rows left over from older builds.
        else
            local newerEntry = index > 1 and entries[index - 1] or nil
            local skip = CrHistory.IsCrOnlyEntry(entry)
                and newerEntry
                and newerEntry.cr == entry.cr

            if not skip then
                table.insert(filtered, entry)
            end
        end

        if #filtered >= limit then
            break
        end
    end

    return filtered
end

--- Removes oldest CR history rows when the retention cap is exceeded.
function CrHistory.PruneHistory()
    local history = CrHistory.GetHistoryTable()
    while #history > PVL.MAX_CR_HISTORY do
        table.remove(history, 1)
    end
end

--- Appends one CR history entry when it adds new information.
--- @param entry table
--- @return boolean
function CrHistory.RecordEntry(entry)
    if type(entry) ~= "table"
        or not entry.bracket
        or not CrHistory.IsValidCr(entry.cr)
        or not entry.source then
        return false
    end

    entry.timestamp = entry.timestamp or time()

    if CrHistory.IsDuplicateSnapshot(entry) then
        return false
    end

    local history = CrHistory.GetHistoryTable()
    table.insert(history, entry)
    CrHistory.PruneHistory()
    return true
end

--- Records CR history from one completed match.
--- @param matchRecord table
--- @return boolean
function CrHistory.RecordMatch(matchRecord)
    if type(matchRecord) ~= "table" or not matchRecord.bracket then
        return false
    end

    local crAfter = matchRecord.playerCRAfter
    if not CrHistory.IsValidCr(crAfter) then
        return false
    end

    local crBefore = matchRecord.playerCRBefore
    local delta = nil
    if CrHistory.IsValidCr(crBefore) then
        delta = crAfter - crBefore
    end

    if matchRecord.matchId then
        local latest = CrHistory.GetLatestEntry(matchRecord.bracket)
        if latest and latest.matchId == matchRecord.matchId then
            return false
        end
    end

    return CrHistory.RecordEntry({
        timestamp = matchRecord.timestamp or time(),
        bracket = matchRecord.bracket,
        cr = crAfter,
        crBefore = crBefore,
        delta = delta,
        won = matchRecord.won,
        source = "match",
        matchId = matchRecord.matchId,
    })
end

--- Records a live CR snapshot for one bracket.
--- @param bracket string
--- @param cr number|nil
--- @param timestamp number|nil
--- @return boolean
function CrHistory.RecordSnapshot(bracket, cr, timestamp)
    if not bracket or not CrHistory.IsValidCr(cr) then
        return false
    end

    return CrHistory.RecordEntry({
        timestamp = timestamp or time(),
        bracket = bracket,
        cr = cr,
        source = "cr",
    })
end

--- Records live CR snapshots for all supported brackets.
function CrHistory.RecordAllSnapshots()
    if not PVL.RatedInfo then
        return
    end

    for bracket in pairs(PVL.RATED_INFO_INDEX_BY_BRACKET) do
        local cr = PVL.RatedInfo.GetCurrentRating(bracket)
        CrHistory.RecordSnapshot(bracket, cr)
    end
end

--- Captures session-start CR baselines for net session calculations.
function CrHistory.BeginSession()
    CrHistory.sessionStartedAt = time()
    CrHistory.sessionStartCrByBracket = {}

    if not PVL.RatedInfo then
        return
    end

    for bracket in pairs(PVL.RATED_INFO_INDEX_BY_BRACKET) do
        CrHistory.sessionStartCrByBracket[bracket] = PVL.RatedInfo.GetCurrentRating(bracket)
    end
end

--- Imports CR points from stored match observations once per character.
function CrHistory.BackfillFromMatches()
    local charDb = PVL.GetCharDB()
    if not charDb or charDb.crHistoryBackfilled then
        return
    end

    local db = PVL.GetDB()
    if not db or type(db.observations) ~= "table" then
        charDb.crHistoryBackfilled = true
        return
    end

    for _, match in ipairs(db.observations.matches or {}) do
        CrHistory.RecordMatch(match)
    end

    charDb.crHistoryBackfilled = true
end

--- Returns CR history entries for one bracket, newest first.
--- @param bracket string|nil
--- @param limit number|nil
--- @return table[]
function CrHistory.GetEntriesForBracket(bracket, limit)
    bracket = bracket or PVL.GetActiveBracketFilter()
    limit = limit or PVL.MAX_CR_HISTORY

    local results = {}
    local history = CrHistory.GetHistoryTable()
    for index = #history, 1, -1 do
        local entry = history[index]
        if entry and entry.bracket == bracket then
            table.insert(results, entry)
            if #results >= limit then
                break
            end
        end
    end

    return results
end

--- Formats one CR delta with sign and color when possible.
--- @param delta number|nil
--- @return string
function CrHistory.FormatDelta(delta)
    if delta == nil then
        return "--"
    end

    local sign = delta >= 0 and "+" or ""
    local text = sign .. tostring(delta)
    if delta > 0 then
        return string.format("|cff40c040%s|r", text)
    end
    if delta < 0 then
        return string.format("|cffff4040%s|r", text)
    end

    return text
end

--- Formats a unix timestamp for compact UI display.
--- @param timestamp number|nil
--- @return string
function CrHistory.FormatTimestamp(timestamp)
    if not timestamp then
        return "--"
    end

    if date then
        return date("%m/%d %H:%M", timestamp)
    end

    return tostring(timestamp)
end

--- Builds summary stats for one bracket's CR history.
--- @param bracket string|nil
--- @return table
function CrHistory.BuildSummary(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    local entries = CrHistory.GetEntriesForBracket(bracket, PVL.MAX_CR_HISTORY)
    local currentCr = PVL.RatedInfo and PVL.RatedInfo.GetCurrentRating(bracket) or nil

    local summary = {
        bracket = bracket,
        entryCount = #entries,
        currentCr = currentCr,
        peakCr = nil,
        lowCr = nil,
        net7d = nil,
        netSession = nil,
        gamesSession = 0,
        winsSession = 0,
        lossesSession = 0,
        recentEntries = {},
    }

    local sevenDaysAgo = time() - (7 * 86400)
    local sessionStartedAt = CrHistory.sessionStartedAt or time()
    local baseline7d = nil

    local history = CrHistory.GetHistoryTable()
    for index = 1, #history do
        local entry = history[index]
        if entry and entry.bracket == bracket and entry.timestamp and entry.timestamp >= sevenDaysAgo then
            if CrHistory.IsValidCr(entry.crBefore or entry.cr) then
                baseline7d = entry.crBefore or entry.cr
                break
            end
        end
    end

    for index = #entries, 1, -1 do
        local entry = entries[index]
        if CrHistory.IsValidCr(entry.cr) then
            summary.peakCr = summary.peakCr and math.max(summary.peakCr, entry.cr) or entry.cr
            summary.lowCr = summary.lowCr and math.min(summary.lowCr, entry.cr) or entry.cr
        end
    end

    if baseline7d and CrHistory.IsValidCr(currentCr) then
        summary.net7d = currentCr - baseline7d
    end

    local sessionStartCr = CrHistory.sessionStartCrByBracket[bracket]
    if CrHistory.IsValidCr(sessionStartCr) and CrHistory.IsValidCr(currentCr) then
        summary.netSession = currentCr - sessionStartCr
    end

    for _, entry in ipairs(entries) do
        if entry.timestamp and entry.timestamp >= sessionStartedAt and entry.source == "match" then
            summary.gamesSession = summary.gamesSession + 1
            if entry.won == true then
                summary.winsSession = summary.winsSession + 1
            elseif entry.won == false then
                summary.lossesSession = summary.lossesSession + 1
            end
        end
    end

    summary.recentEntries = CrHistory.FilterRecentEntriesForDisplay(entries, PVL.CR_HISTORY_UI_LIMIT)

    if CrHistory.IsValidCr(currentCr) then
        summary.peakCr = summary.peakCr and math.max(summary.peakCr, currentCr) or currentCr
        summary.lowCr = summary.lowCr and math.min(summary.lowCr, currentCr) or currentCr
    end

    return summary
end

--- Prints CR history for one bracket to chat.
--- @param bracket string|nil
function CrHistory.PrintHistory(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    local bracketName = PVL.BRACKET_NAMES[bracket] or bracket
    local summary = CrHistory.BuildSummary(bracket)

    print(string.format("|cff66ccffPvPLedger|r CR history — %s", bracketName))
    print(string.format(
        "  current=%s peak=%s low=%s net7d=%s netSession=%s gamesSession=%d",
        tostring(summary.currentCr or "--"),
        tostring(summary.peakCr or "--"),
        tostring(summary.lowCr or "--"),
        tostring(summary.net7d or "--"),
        tostring(summary.netSession or "--"),
        summary.gamesSession
    ))

    if #summary.recentEntries == 0 then
        print("  No CR history recorded for this bracket yet.")
        return
    end

    for _, entry in ipairs(summary.recentEntries) do
        if entry.source == "match" then
            print(string.format(
                "  %s  %s -> %s (%s) %s",
                CrHistory.FormatTimestamp(entry.timestamp),
                tostring(entry.crBefore or "?"),
                tostring(entry.cr),
                CrHistory.FormatDelta(entry.delta),
                entry.won == true and "W" or (entry.won == false and "L" or "-")
            ))
        else
            print(string.format(
                "  %s  CR %s",
                CrHistory.FormatTimestamp(entry.timestamp),
                tostring(entry.cr)
            ))
        end
    end
end

--- Dispatches CR history lifecycle events.
--- @param event string
function CrHistory.OnEvent(event)
    if event == "PLAYER_LOGIN" then
        CrHistory.BeginSession()
        CrHistory.BackfillFromMatches()
        CrHistory.PruneRedundantSnapshots()
    end
end

--- Initializes CR history event hooks.
function CrHistory.Init()
    if CrHistory.frame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event)
        CrHistory.OnEvent(event)
    end)

    CrHistory.frame = frame
end
