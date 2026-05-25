--- Loads bundled and companion data-addon ladder snapshots with merge precedence.
--- WoW addons cannot fetch HTTP URLs, so public updates ship via the optional
--- PvPLedger-Data-US companion addon refreshed by GitHub Actions.
--- @class PvPLedger
local PVL = PvPLedger

--- Snapshot origin labels used in status output.
PVL.LADDER_DATA_SOURCES = {
    BUNDLED = "bundled",
    DATA_ADDON = "data-addon",
}

PVL._bundledLadderData = PVL._bundledLadderData or {}
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

    return false
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
        updatedBrackets = {},
        sources = {},
    }

    PVL.CaptureBundledLadderData()

    if options.loadDataAddon ~= false then
        local loaded, reason = PVL.TryLoadDataAddon()
        summary.loadedDataAddon = loaded
        summary.dataAddonReason = reason
    end

    PVL.ImportedSnapshots = PVL.ImportedSnapshots or {}
    PVL._snapshotSources = {}

    for _, bracket in ipairs(PVL.IMPORTED_BRACKETS) do
        local bundled = PVL._bundledLadderData[bracket]
        local remote = PVL.ReadLadderSnapshotFromGlobal(bracket)
        local snapshot, source = PVL.PickSnapshotForBracket(bracket, bundled, remote)

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
    end

    return summary
end

--- Returns user-facing lines describing companion data update availability.
--- @return string[]
function PVL.GetLadderUpdateStatusLines()
    local lines = {}

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

    return lines
end
