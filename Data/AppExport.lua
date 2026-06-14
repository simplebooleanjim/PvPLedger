--- Match export helpers for the PvPLedger Sync desktop app.
--- Writes compact match batches to PvPLedger_AppHelperDB SavedVariables on logout.
--- @class PvPLedger
local PVL = PvPLedger

PVL.APP_HELPER_DB_NAME = "PvPLedger_AppHelperDB"
PVL.MAX_EXPORT_MATCHES = 200

--- Returns the AppHelper SavedVariables table owned by PvPLedger-AppHelper.
--- @return table
function PVL.GetAppHelperDB()
    _G[PVL.APP_HELPER_DB_NAME] = _G[PVL.APP_HELPER_DB_NAME] or {
        version = 1,
        export = {
            pendingMatches = {},
            lastExportedAt = nil,
            lastMatchAt = nil,
        },
        sync = {
            lastCharacter = nil,
            addonVersion = PVL.VERSION,
        },
    }

    local appDb = _G[PVL.APP_HELPER_DB_NAME]
    appDb.export = appDb.export or { pendingMatches = {} }
    appDb.export.pendingMatches = appDb.export.pendingMatches or {}
    appDb.sync = appDb.sync or {}
    return appDb
end

--- Enables or disables match export sharing with PvPLedger Sync.
--- @param enabled boolean
function PVL.SetShareMatchData(enabled)
    local db = PVL.GetDB()
    db.settings.shareMatchData = enabled and true or false
end

--- Returns whether match export sharing is enabled.
--- @return boolean
function PVL.IsShareMatchDataEnabled()
    return PVL.GetDB().settings.shareMatchData == true
end

--- Builds a compact match payload suitable for desktop app upload.
--- @param matchRecord table
--- @return table|nil
function PVL.BuildMatchExportRecord(matchRecord)
    if type(matchRecord) ~= "table" then
        return nil
    end

    local roster = {}
    for _, participant in ipairs(matchRecord.roster or {}) do
        table.insert(roster, {
            name = participant.name,
            realm = participant.realm,
            class = participant.class,
            spec = participant.spec,
            rating = participant.rating,
            ratingChange = participant.ratingChange,
            faction = participant.faction,
            team = participant.team,
            isLocalPlayer = participant.isLocalPlayer,
        })
    end

    return {
        matchId = matchRecord.matchId,
        bracket = matchRecord.bracket,
        timestamp = matchRecord.timestamp,
        mapID = matchRecord.mapID,
        won = matchRecord.won,
        playerCRBefore = matchRecord.playerCRBefore,
        playerCRAfter = matchRecord.playerCRAfter,
        playerMMRBefore = matchRecord.playerMMRBefore,
        playerMMRAfter = matchRecord.playerMMRAfter,
        playerMMRKind = matchRecord.playerMMRKind,
        playerPersonalMMRBefore = matchRecord.playerPersonalMMRBefore,
        playerPersonalMMRAfter = matchRecord.playerPersonalMMRAfter,
        combatSummary = PVL.BuildCombatExportSummary(matchRecord.combatSummary),
        roster = roster,
    }
end

--- Builds a compact combat summary payload for export.
--- @param combatSummary table|nil
--- @return table|nil
function PVL.BuildCombatExportSummary(combatSummary)
    if type(combatSummary) ~= "table" then
        return nil
    end

    local players = {}
    for _, row in ipairs(combatSummary.players or {}) do
        table.insert(players, {
            name = row.name,
            class = row.class,
            spec = row.spec,
            team = row.team,
            isLocalPlayer = row.isLocalPlayer,
            damage = row.damage,
            healing = row.healing,
            damageTaken = row.damageTaken,
            interrupts = row.interrupts,
            dispels = row.dispels,
            deaths = row.deaths,
        })
    end

    return {
        duration = combatSummary.duration,
        killEvents = combatSummary.killEvents,
        players = players,
    }
end

--- Queues one match for export when telemetry sharing is enabled.
--- @param matchRecord table
function PVL.QueueMatchExport(matchRecord)
    local db = PVL.GetDB()
    if not db or not db.settings.shareMatchData then
        return
    end

    local exportRecord = PVL.BuildMatchExportRecord(matchRecord)
    if not exportRecord or not exportRecord.matchId then
        return
    end

    local appDb = PVL.GetAppHelperDB()
    for _, pending in ipairs(appDb.export.pendingMatches) do
        if pending.matchId == exportRecord.matchId then
            return
        end
    end

    table.insert(appDb.export.pendingMatches, exportRecord)

    while #appDb.export.pendingMatches > PVL.MAX_EXPORT_MATCHES do
        table.remove(appDb.export.pendingMatches, 1)
    end

    appDb.export.lastMatchAt = exportRecord.timestamp
end

--- Removes uploaded matches from the export queue after Sync confirms ingestion.
--- @param ack table
--- @return number removedCount
function PVL.ApplyExportAck(ack)
    if type(ack) ~= "table" or type(ack.uploadedMatchIds) ~= "table" then
        return 0
    end

    local appDb = PVL.GetAppHelperDB()
    if ack.batchId and appDb.export.lastAckBatchId == ack.batchId then
        return 0
    end

    local uploadedIds = {}
    for _, matchId in ipairs(ack.uploadedMatchIds) do
        if matchId then
            uploadedIds[tostring(matchId)] = true
        end
    end

    if not next(uploadedIds) then
        return 0
    end

    local kept = {}
    local removedCount = 0
    for _, matchRecord in ipairs(appDb.export.pendingMatches or {}) do
        local matchId = matchRecord and matchRecord.matchId and tostring(matchRecord.matchId)
        if matchId and uploadedIds[matchId] then
            removedCount = removedCount + 1
        else
            table.insert(kept, matchRecord)
        end
    end

    appDb.export.pendingMatches = kept
    appDb.export.lastAckAt = time()
    appDb.export.lastAckBatchId = ack.batchId
    appDb.export.lastAckUploadedAt = ack.uploadedAt
    appDb.export.lastAckRemovedCount = removedCount
    return removedCount
end

--- Persists export metadata for the desktop sync app to read from WTF.
function PVL.SaveAppHelperExport()
    local db = PVL.GetDB()
    if not db or not db.settings.shareMatchData then
        return
    end

    local appDb = PVL.GetAppHelperDB()
    appDb.sync.addonVersion = PVL.VERSION
    appDb.sync.lastCharacter = UnitName("player") .. " - " .. GetRealmName()
    appDb.export.lastExportedAt = time()
end

--- Returns status lines describing AppHelper export state.
--- @return string[]
function PVL.GetAppExportStatusLines()
    local lines = {}
    local db = PVL.GetDB()

    if not db or not db.settings.shareMatchData then
        table.insert(lines, "Match export: disabled (enable in Options > AddOns > PvPLedger).")
        return lines
    end

    local appDb = PVL.GetAppHelperDB()
    local pendingCount = #(appDb.export.pendingMatches or {})
    table.insert(lines, string.format("Match export: enabled (%d pending upload).", pendingCount))

    if appDb.export.lastMatchAt then
        table.insert(lines, string.format(
            "Last queued match: %s",
            date("%Y-%m-%d %H:%M", appDb.export.lastMatchAt)
        ))
    end

    if appDb.export.lastAckAt then
        table.insert(lines, string.format(
            "Last upload ack: %s (%d cleared).",
            date("%Y-%m-%d %H:%M", appDb.export.lastAckAt),
            appDb.export.lastAckRemovedCount or 0
        ))
    end

    return lines
end
