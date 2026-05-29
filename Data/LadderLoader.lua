--- Loads bundled and companion data-addon ladder snapshots with merge precedence.
--- WoW addons cannot fetch HTTP URLs, so public updates ship via the optional
--- PvPLedger-Data-US companion addon or PvPLedger-AppHelper + desktop sync app.
--- @class PvPLedger
local PVL = PvPLedger

--- Snapshot origin labels used in status output.
PVL.LADDER_DATA_SOURCES = {
    BUNDLED = "bundled",
    DATA_ADDON = "data-addon",
    DESKTOP_APP = "desktop-app",
}

PVL._bundledLadderData = PVL._bundledLadderData or {}
PVL._appHelperSnapshots = PVL._appHelperSnapshots or {}
PVL._appSyncInfo = PVL._appSyncInfo or nil
PVL._snapshotSources = PVL._snapshotSources or {}

--- Parses an ISO snapshot date into a unix timestamp.
--- @param snapshotDate string|nil
--- @return number|nil
function PVL.ParseSnapshotDate(snapshotDate)
    if not snapshotDate then
        return nil
    end

    local year, month, day = snapshotDate:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not year then
        return nil
    end

    return time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = 12,
    })
end

--- Returns true when the candidate snapshot is strictly newer than the baseline.
--- @param candidate table|nil
--- @param baseline table|nil
--- @return boolean
function PVL.IsSnapshotNewer(candidate, baseline)
    if not candidate then
        return false
    end

    if not baseline then
        return true
    end

    local candidateTime = PVL.ParseSnapshotDate(candidate.snapshotDate)
    local baselineTime = PVL.ParseSnapshotDate(baseline.snapshotDate)
    if candidateTime and baselineTime then
        if candidateTime ~= baselineTime then
            return candidateTime > baselineTime
        end
    elseif candidateTime and not baselineTime then
        return true
    elseif baselineTime and not candidateTime then
        return false
    end

    local candidateId = candidate.snapshotId or ""
    local baselineId = baseline.snapshotId or ""
    if candidateId ~= baselineId then
        return candidateId > baselineId
    end

    local candidateGenerated = PVL.ParseIsoTimestamp(candidate.generatedAt)
    local baselineGenerated = PVL.ParseIsoTimestamp(baseline.generatedAt)
    if candidateGenerated and baselineGenerated then
        return candidateGenerated > baselineGenerated
    end

    return false
end

--- Returns a unix timestamp for one ISO-8601 UTC timestamp string.
--- @param isoTimestamp string|nil
--- @return number|nil
function PVL.ParseIsoTimestamp(isoTimestamp)
    if not isoTimestamp then
        return nil
    end

    local year, month, day, hour, minute, second = isoTimestamp:match(
        "^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)"
    )
    if not year then
        return nil
    end

    return time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(minute),
        sec = tonumber(second),
    })
end

--- Returns a readable age label for one sync payload timestamp.
--- @param isoTimestamp string|nil
--- @return string
function PVL.FormatSyncAge(isoTimestamp)
    local syncTime = PVL.ParseIsoTimestamp(isoTimestamp)
    if not syncTime then
        return "unknown age"
    end

    local ageSeconds = math.max(0, time() - syncTime)
    if ageSeconds < 3600 then
        local minutes = math.max(1, math.floor(ageSeconds / 60))
        if minutes == 1 then
            return "1 minute"
        end
        return string.format("%d minutes", minutes)
    end

    if ageSeconds < 86400 then
        local hours = math.max(1, math.floor(ageSeconds / 3600))
        if hours == 1 then
            return "1 hour"
        end
        return string.format("%d hours", hours)
    end

    return PVL.FormatSnapshotAge(isoTimestamp:sub(1, 10))
end

--- Returns a readable label for one ladder snapshot source key.
--- @param source string|nil
--- @return string
function PVL.FormatLadderSourceLabel(source)
    if source == PVL.LADDER_DATA_SOURCES.DESKTOP_APP then
        return "PvPLedger Sync"
    end

    if source == PVL.LADDER_DATA_SOURCES.DATA_ADDON then
        return "PvPLedger-Data-US"
    end

    if source == PVL.LADDER_DATA_SOURCES.BUNDLED then
        return "bundled addon files"
    end

    return source or "unknown"
end

--- Counts indexed player rows in one imported snapshot.
--- @param snapshot table|nil
--- @return number
function PVL.CountSnapshotPlayers(snapshot)
    if not snapshot or type(snapshot.players) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(snapshot.players) do
        count = count + 1
    end

    return count
end

--- Returns ladder snapshot candidates available for one bracket.
--- @param bracket string
--- @return table[]
function PVL.GetLadderSnapshotCandidates(bracket)
    PVL.CaptureBundledLadderData()

    return {
        { snapshot = PVL._bundledLadderData[bracket], source = PVL.LADDER_DATA_SOURCES.BUNDLED },
        { snapshot = PVL.ReadLadderSnapshotFromGlobal(bracket), source = PVL.LADDER_DATA_SOURCES.DATA_ADDON },
        { snapshot = PVL._appHelperSnapshots[bracket], source = PVL.LADDER_DATA_SOURCES.DESKTOP_APP },
    }
end

--- Returns user-facing hint lines when fresher ladder data is available elsewhere.
--- @param bracket string|nil
--- @return string[]
function PVL.GetLadderStalenessLines(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    local lines = {}
    local activeSnapshot = PVL.GetImportedSnapshot(bracket)
    local activeSource = PVL.GetSnapshotSource(bracket)

    if not activeSnapshot then
        return lines
    end

    local idealSnapshot, idealSource = PVL.PickBestSnapshot(PVL.GetLadderSnapshotCandidates(bracket))
    local activePlayerCount = PVL.CountSnapshotPlayers(activeSnapshot)
    local idealPlayerCount = PVL.CountSnapshotPlayers(idealSnapshot)

    if idealSnapshot and idealSource and activeSource and idealSource ~= activeSource then
        table.insert(lines, string.format(
            "Fresher ladder data is available from %s. Run /pvl update or /reload.",
            PVL.FormatLadderSourceLabel(idealSource)
        ))
    elseif idealSnapshot
        and idealSource == activeSource
        and idealSnapshot ~= activeSnapshot
        and idealPlayerCount > activePlayerCount then
        table.insert(lines, string.format(
            "The loaded snapshot looks incomplete (%s indexed vs %s available). Run /pvl update.",
            PVL.FormatRating(activePlayerCount),
            PVL.FormatRating(idealPlayerCount)
        ))
    end

    if activeSource == PVL.LADDER_DATA_SOURCES.BUNDLED
        and PVL.IsAppHelperInstalled()
        and not PVL.IsAppHelperLoaded()
        and PVL._appHelperSnapshots[bracket] then
        table.insert(lines, "PvPLedger-AppHelper is installed but not loaded yet. /reload to use synced ladder data.")
    end

    if activeSource == PVL.LADDER_DATA_SOURCES.BUNDLED
        and not PVL._appHelperSnapshots[bracket]
        and not PVL.ReadLadderSnapshotFromGlobal(bracket) then
        table.insert(lines, "Using bundled ladder files only. Install PvPLedger Sync or PvPLedger-Data-US for automatic same-day refreshes.")
    end

    local syncInfo = PVL.GetAppSyncInfo()
    local syncGeneratedAt = syncInfo and syncInfo.generatedAt or nil
    local syncTime = PVL.ParseIsoTimestamp(syncGeneratedAt)
    if syncTime and activeSource == PVL.LADDER_DATA_SOURCES.DESKTOP_APP then
        local ageSeconds = time() - syncTime
        if ageSeconds > (45 * 60) then
            table.insert(lines, string.format(
                "Desktop sync payload is %s old. Run PvPLedger Sync > Sync ladder now, then /pvl update and /reload.",
                PVL.FormatSyncAge(syncGeneratedAt)
            ))
        end
    end

    if UnitName and PVL.LookupPlayerInSnapshot then
        local name = UnitName("player")
        local realm = GetRealmName and GetRealmName() or ""
        local listedInActive = PVL.LookupPlayerInSnapshot(activeSnapshot, name, realm)
        local listedInIdeal = idealSnapshot and PVL.LookupPlayerInSnapshot(idealSnapshot, name, realm) or nil

        if not listedInActive and listedInIdeal then
            table.insert(lines, string.format(
                "Your character is listed in %s but not the currently loaded snapshot. Run /pvl update.",
                PVL.FormatLadderSourceLabel(idealSource)
            ))
        end
    end

    return lines
end

--- Returns a numeric priority for one ladder snapshot source when dates tie.
--- @param source string|nil
--- @return number
function PVL.GetSnapshotSourcePriority(source)
    if source == PVL.LADDER_DATA_SOURCES.DESKTOP_APP then
        return 3
    end

    if source == PVL.LADDER_DATA_SOURCES.DATA_ADDON then
        return 2
    end

    if source == PVL.LADDER_DATA_SOURCES.BUNDLED then
        return 1
    end

    return 0
end

--- Returns true when the candidate snapshot should replace the baseline.
--- @param candidate table|nil
--- @param baseline table|nil
--- @param candidateSource string|nil
--- @param baselineSource string|nil
--- @return boolean
function PVL.ShouldPreferSnapshot(candidate, baseline, candidateSource, baselineSource)
    if not candidate then
        return false
    end

    if not baseline then
        return true
    end

    if PVL.IsSnapshotNewer(candidate, baseline) then
        return true
    end

    if PVL.IsSnapshotNewer(baseline, candidate) then
        return false
    end

    return PVL.GetSnapshotSourcePriority(candidateSource) > PVL.GetSnapshotSourcePriority(baselineSource)
end

--- Returns true when the optional US data companion addon is installed.
--- @return boolean
function PVL.IsDataAddonInstalled()
    if not C_AddOns or not C_AddOns.DoesAddOnExist then
        return false
    end

    return C_AddOns.DoesAddOnExist(PVL.DATA_ADDON_NAME)
end

--- Returns true when the optional US data companion addon is loaded.
--- @return boolean
function PVL.IsDataAddonLoaded()
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then
        return false
    end

    return C_AddOns.IsAddOnLoaded(PVL.DATA_ADDON_NAME)
end

--- Returns true when the AppHelper bridge addon is installed.
--- @return boolean
function PVL.IsAppHelperInstalled()
    if not C_AddOns or not C_AddOns.DoesAddOnExist then
        return false
    end

    return C_AddOns.DoesAddOnExist(PVL.APP_HELPER_NAME)
end

--- Returns true when the AppHelper bridge addon is loaded.
--- @return boolean
function PVL.IsAppHelperLoaded()
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then
        return false
    end

    return C_AddOns.IsAddOnLoaded(PVL.APP_HELPER_NAME)
end

--- Attempts to load the AppHelper bridge addon written by PvPLedger Sync.
--- @return boolean loaded
--- @return string|nil reason
function PVL.TryLoadAppHelper()
    if not PVL.IsAppHelperInstalled() then
        return false, "PvPLedger-AppHelper is not installed."
    end

    if PVL.IsAppHelperLoaded() then
        return true, "already loaded"
    end

    local loaded, reason = C_AddOns.LoadAddOn(PVL.APP_HELPER_NAME)
    if not loaded then
        return false, reason or "failed to load PvPLedger-AppHelper"
    end

    return true, "loaded"
end

--- Applies ladder snapshots pushed by PvPLedger-AppHelper/AppData.lua.
--- @param snapshots table<string, table>
--- @param syncInfo table|nil
function PVL.ApplyAppSyncSnapshots(snapshots, syncInfo)
    if type(snapshots) ~= "table" then
        return
    end

    PVL._appHelperSnapshots = PVL._appHelperSnapshots or {}
    for bracket, snapshot in pairs(snapshots) do
        if type(snapshot) == "table" and snapshot.snapshotId then
            PVL._appHelperSnapshots[bracket] = snapshot
        end
    end

    PVL._appSyncInfo = syncInfo

    local db = PVL.GetDB()
    if db and db.meta then
        db.meta.appHelperInstalled = true
        db.meta.appSyncGeneratedAt = syncInfo and syncInfo.generatedAt or nil
    end
end

--- Returns sync metadata supplied by the desktop app through AppHelper.
--- @return table|nil
function PVL.GetAppSyncInfo()
    return PVL._appSyncInfo
end

--- Returns metadata for the AppHelper bridge addon.
--- @return string|nil version
--- @return string|nil title
function PVL.GetAppHelperMetadata()
    if not PVL.IsAppHelperInstalled() or not C_AddOns or not C_AddOns.GetAddOnMetadata then
        return nil, nil
    end

    return C_AddOns.GetAddOnMetadata(PVL.APP_HELPER_NAME, "Version"),
        C_AddOns.GetAddOnMetadata(PVL.APP_HELPER_NAME, "Title")
end

--- Returns metadata for the optional US data companion addon.
--- @return string|nil version
--- @return string|nil title
function PVL.GetDataAddonMetadata()
    if not PVL.IsDataAddonInstalled() or not C_AddOns or not C_AddOns.GetAddOnMetadata then
        return nil, nil
    end

    return C_AddOns.GetAddOnMetadata(PVL.DATA_ADDON_NAME, "Version"),
        C_AddOns.GetAddOnMetadata(PVL.DATA_ADDON_NAME, "Title")
end

--- Caches ladder snapshots bundled with the main addon before loading the companion.
function PVL.CaptureBundledLadderData()
    if PVL._bundledLadderDataCaptured then
        return
    end

    if type(PvPLedgerLadderData) ~= "table" then
        PVL._bundledLadderDataCaptured = true
        return
    end

    if PvPLedgerLadderData.snapshotId then
        local bracket = PvPLedgerLadderData.bracket
        if bracket then
            PVL._bundledLadderData[bracket] = PvPLedgerLadderData
        end
        PVL._bundledLadderDataCaptured = true
        return
    end

    for bracket, snapshot in pairs(PvPLedgerLadderData) do
        if type(snapshot) == "table" and snapshot.snapshotId then
            PVL._bundledLadderData[bracket] = snapshot
        end
    end

    PVL._bundledLadderDataCaptured = true
end

--- Attempts to load the optional US data companion addon.
--- @return boolean loaded
--- @return string|nil reason
function PVL.TryLoadDataAddon()
    if not PVL.IsDataAddonInstalled() then
        return false, "PvPLedger-Data-US is not installed."
    end

    if PVL.IsDataAddonLoaded() then
        return true, "already loaded"
    end

    local loaded, reason = C_AddOns.LoadAddOn(PVL.DATA_ADDON_NAME)
    if not loaded then
        return false, reason or "failed to load PvPLedger-Data-US"
    end

    return true, "loaded"
end

--- Reads one bracket snapshot from the live ladder global table.
--- @param bracket string
--- @return table|nil
function PVL.ReadLadderSnapshotFromGlobal(bracket)
    if type(PvPLedgerLadderData) ~= "table" then
        return nil
    end

    if PvPLedgerLadderData.snapshotId and PvPLedgerLadderData.bracket == bracket then
        return PvPLedgerLadderData
    end

    local snapshot = PvPLedgerLadderData[bracket]
    if type(snapshot) == "table" and snapshot.snapshotId then
        return snapshot
    end

    return nil
end

--- Chooses the newest snapshot from multiple candidate sources.
--- @param candidates table[]
--- @return table|nil snapshot
--- @return string|nil source
function PVL.PickBestSnapshot(candidates)
    local bestSnapshot = nil
    local bestSource = nil

    for _, candidate in ipairs(candidates) do
        local snapshot = candidate.snapshot
        local source = candidate.source
        if snapshot and PVL.ShouldPreferSnapshot(snapshot, bestSnapshot, source, bestSource) then
            bestSnapshot = snapshot
            bestSource = source
        end
    end

    return bestSnapshot, bestSource
end

--- Chooses the newest snapshot between bundled and companion sources.
--- @param bracket string
--- @param bundled table|nil
--- @param remote table|nil
--- @return table|nil snapshot
--- @return string|nil source
function PVL.PickSnapshotForBracket(bracket, bundled, remote)
    if bundled and remote then
        if bundled == remote then
            return bundled, PVL.LADDER_DATA_SOURCES.BUNDLED
        end

        if PVL.IsSnapshotNewer(remote, bundled) then
            return remote, PVL.LADDER_DATA_SOURCES.DATA_ADDON
        end

        return bundled, PVL.LADDER_DATA_SOURCES.BUNDLED
    end

    if remote then
        local source = PVL.LADDER_DATA_SOURCES.DATA_ADDON
        if not PVL.IsDataAddonInstalled() or not PVL.IsDataAddonLoaded() then
            source = PVL.LADDER_DATA_SOURCES.BUNDLED
        end
        return remote, source
    end

    if bundled then
        return bundled, PVL.LADDER_DATA_SOURCES.BUNDLED
    end

    return nil, nil
end

--- Returns the active source label for one imported bracket snapshot.
--- @param bracket string|nil
--- @return string|nil
function PVL.GetSnapshotSource(bracket)
    local activeBracket = bracket or PVL.GetActiveBracketFilter()
    return PVL._snapshotSources[activeBracket]
end

--- Loads bundled snapshots, optionally loads the companion addon, and merges by freshness.
--- @param options table|nil
--- @return table summary
function PVL.RefreshImportedLadderData(options)
    options = options or {}
    local summary = {
        loadedDataAddon = false,
        dataAddonReason = nil,
        loadedAppHelper = false,
        appHelperReason = nil,
        updatedBrackets = {},
        sources = {},
    }

    PVL.CaptureBundledLadderData()

    if options.loadAppHelper ~= false then
        local loaded, reason = PVL.TryLoadAppHelper()
        summary.loadedAppHelper = loaded
        summary.appHelperReason = reason
    end

    if options.loadDataAddon ~= false then
        local loaded, reason = PVL.TryLoadDataAddon()
        summary.loadedDataAddon = loaded
        summary.dataAddonReason = reason
    end

    PVL.ImportedSnapshots = PVL.ImportedSnapshots or {}
    PVL._snapshotSources = {}

    for _, bracket in ipairs(PVL.IMPORTED_BRACKETS) do
        local snapshot, source = PVL.PickBestSnapshot({
            { snapshot = PVL._bundledLadderData[bracket], source = PVL.LADDER_DATA_SOURCES.BUNDLED },
            { snapshot = PVL.ReadLadderSnapshotFromGlobal(bracket), source = PVL.LADDER_DATA_SOURCES.DATA_ADDON },
            { snapshot = PVL._appHelperSnapshots[bracket], source = PVL.LADDER_DATA_SOURCES.DESKTOP_APP },
        })

        if snapshot then
            PVL.SetImportedSnapshot(snapshot)
            PVL._snapshotSources[bracket] = source
            summary.sources[bracket] = source
            table.insert(summary.updatedBrackets, bracket)
        end
    end

    local db = PVL.GetDB()
    if db and db.meta then
        db.meta.lastLadderRefreshAt = time()
        db.meta.dataAddonInstalled = PVL.IsDataAddonInstalled()
        db.meta.dataAddonVersion = select(1, PVL.GetDataAddonMetadata())
        db.meta.appHelperInstalled = PVL.IsAppHelperInstalled()
        db.meta.appSyncGeneratedAt = PVL.GetAppSyncInfo() and PVL.GetAppSyncInfo().generatedAt or nil
    end

    return summary
end

--- Returns user-facing lines describing companion data update availability.
--- @return string[]
function PVL.GetLadderUpdateStatusLines()
    local lines = {}

    if PVL.IsAppHelperInstalled() then
        local version = select(1, PVL.GetAppHelperMetadata())
        local syncInfo = PVL.GetAppSyncInfo()
        local loadedText = PVL.IsAppHelperLoaded() and "loaded" or "installed, not loaded yet"
        table.insert(lines, string.format(
            "AppHelper: PvPLedger-AppHelper (%s) — %s",
            version or "unknown version",
            loadedText
        ))
        if syncInfo and syncInfo.generatedAt then
            table.insert(lines, string.format("Desktop sync payload: %s", syncInfo.generatedAt))
        end
    else
        table.insert(lines, "AppHelper: not installed.")
        table.insert(lines, PVL.APP_HELPER_INSTALL_HINT)
    end

    if PVL.IsDataAddonInstalled() then
        local version = select(1, PVL.GetDataAddonMetadata())
        local loadedText = PVL.IsDataAddonLoaded() and "loaded" or "installed, not loaded yet"
        table.insert(lines, string.format(
            "Data addon: PvPLedger-Data-US (%s) — %s",
            version or "unknown version",
            loadedText
        ))
    else
        table.insert(lines, "Data addon: not installed (using bundled snapshots only).")
        table.insert(lines, "Install PvPLedger-Data-US and keep it updated for fresher ladder data.")
    end

    local db = PVL.GetDB()
    if db and db.meta and db.meta.lastLadderRefreshAt then
        table.insert(lines, string.format(
            "Last refresh: %s",
            date("%Y-%m-%d %H:%M", db.meta.lastLadderRefreshAt)
        ))
    end

    for _, hintLine in ipairs(PVL.GetLadderStalenessLines(PVL.GetActiveBracketFilter())) do
        table.insert(lines, string.format("Stale data: %s", hintLine))
    end

    return lines
end
