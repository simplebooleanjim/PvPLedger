--- Match export helpers for the PvPLedger Sync desktop app.
--- Writes match batches and account snapshots to PvPLedger_AppHelperDB SavedVariables on logout.
--- @class PvPLedger
local PVL = PvPLedger

PVL.APP_HELPER_DB_NAME = "PvPLedger_AppHelperDB"
PVL.MAX_EXPORT_MATCHES = 200
PVL.EXPORT_SCHEMA_VERSION = 2

--- Returns the AppHelper SavedVariables table owned by PvPLedger-AppHelper.
--- @return table
function PVL.GetAppHelperDB()
    _G[PVL.APP_HELPER_DB_NAME] = _G[PVL.APP_HELPER_DB_NAME] or {
        version = PVL.EXPORT_SCHEMA_VERSION,
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
    appDb.version = PVL.EXPORT_SCHEMA_VERSION
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

--- Deep-copies one Lua value for export-safe serialization.
--- @param value any
--- @param depth number|nil
--- @param seen table|nil
--- @return any
function PVL.DeepCopyForExport(value, depth, seen)
    depth = depth or 0
    if depth > 14 then
        return nil
    end

    local valueType = type(value)
    if valueType ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return nil
    end
    seen[value] = true

    local copy = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            copy[key] = PVL.DeepCopyForExport(child, depth + 1, seen)
        end
    end

    return copy
end

--- Collects local Battle.net and character identity metadata for export.
--- @return table
function PVL.CollectAccountIdentity()
    local identity = {
        characterName = UnitName("player"),
        realm = GetRealmName(),
        characterGuid = UnitGUID("player"),
        faction = UnitFactionGroup("player"),
        locale = GetLocale(),
    }

    if GetCurrentRegion then
        local ok, region = pcall(GetCurrentRegion)
        if ok then
            identity.region = region
        end
    end

    if WOW_PROJECT_ID then
        identity.wowProjectId = WOW_PROJECT_ID
    end

    if BNGetInfo then
        local _, battleTag, toonId = BNGetInfo()
        identity.battleTag = PVL.GetAccessibleString(battleTag)
        identity.bnetToonId = toonId

        if toonId and C_BattleNet and type(C_BattleNet.GetAccountInfoByID) == "function" then
            local ok, accountInfo = pcall(C_BattleNet.GetAccountInfoByID, toonId)
            if ok and type(accountInfo) == "table" then
                identity.bnetAccountId = accountInfo.bnetAccountID
                identity.battleTagId = accountInfo.battleTagID
                identity.accountName = PVL.GetAccessibleString(accountInfo.accountName)
                identity.isBattleTagFriend = accountInfo.isBattleTagFriend
                identity.isVisible = accountInfo.isVisible
            end
        end
    end

    return identity
end

--- Builds a full account SavedVariables snapshot for export.
--- @return table|nil
function PVL.BuildAccountSnapshot()
    local db = PVL.GetDB()
    if type(db) ~= "table" then
        return nil
    end

    return {
        capturedAt = time(),
        version = db.version,
        meta = PVL.DeepCopyForExport(db.meta),
        settings = PVL.DeepCopyForExport(db.settings),
        observations = PVL.DeepCopyForExport(db.observations),
    }
end

--- Builds a full per-character SavedVariables snapshot for export.
--- @return table|nil
function PVL.BuildCharacterSnapshot()
    local charDb = PVL.GetCharDB()
    if type(charDb) ~= "table" then
        return nil
    end

    return {
        capturedAt = time(),
        version = charDb.version,
        ratings = {
            lastBlitzCR = charDb.lastBlitzCR,
            lastBlitzMMR = charDb.lastBlitzMMR,
            lastBlitzMMRKind = charDb.lastBlitzMMRKind,
            lastBlitzPersonalMMR = charDb.lastBlitzPersonalMMR,
            lastShuffleCR = charDb.lastShuffleCR,
            lastShuffleMMR = charDb.lastShuffleMMR,
            lastShuffleMMRKind = charDb.lastShuffleMMRKind,
            lastShufflePersonalMMR = charDb.lastShufflePersonalMMR,
            lastRbgCR = charDb.lastRbgCR,
            lastRbgMMR = charDb.lastRbgMMR,
            lastRbgMMRKind = charDb.lastRbgMMRKind,
            lastRbgPersonalMMR = charDb.lastRbgPersonalMMR,
            lastArena2v2CR = charDb.lastArena2v2CR,
            lastArena2v2MMR = charDb.lastArena2v2MMR,
            lastArena2v2MMRKind = charDb.lastArena2v2MMRKind,
            lastArena2v2PersonalMMR = charDb.lastArena2v2PersonalMMR,
            lastArena3v3CR = charDb.lastArena3v3CR,
            lastArena3v3MMR = charDb.lastArena3v3MMR,
            lastArena3v3MMRKind = charDb.lastArena3v3MMRKind,
            lastArena3v3PersonalMMR = charDb.lastArena3v3PersonalMMR,
        },
        crHistory = PVL.DeepCopyForExport(charDb.crHistory),
        crHistoryBackfilled = charDb.crHistoryBackfilled,
        pendingCombatSession = PVL.DeepCopyForExport(charDb.pendingCombatSession),
        combatSegmentArchive = PVL.DeepCopyForExport(charDb.combatSegmentArchive),
    }
end

--- Builds one export roster row with scoreboard and identity fields.
--- @param participant table
--- @return table
function PVL.BuildExportRosterRow(participant)
    return {
        guid = participant.guid,
        name = participant.name,
        realm = participant.realm,
        class = participant.class,
        spec = participant.spec,
        rating = participant.rating,
        ratingChange = participant.ratingChange,
        faction = participant.faction,
        team = participant.team,
        isLocalPlayer = participant.isLocalPlayer,
        damageDone = participant.damageDone,
        healingDone = participant.healingDone,
        interrupts = participant.interrupts,
        dispels = participant.dispels,
        deaths = participant.deaths,
    }
end

--- Builds one export combat player row with spell and CC telemetry.
--- @param row table
--- @return table
function PVL.BuildExportCombatPlayerRow(row)
    return {
        guid = row.guid,
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
        spells = PVL.DeepCopyForExport(row.spells),
    }
end

--- Builds a combat summary payload for export, including raw combat-log lines.
--- @param combatSummary table|nil
--- @return table|nil
function PVL.BuildCombatExportSummary(combatSummary)
    if type(combatSummary) ~= "table" then
        return nil
    end

    local players = {}
    for _, row in ipairs(combatSummary.players or {}) do
        table.insert(players, PVL.BuildExportCombatPlayerRow(row))
    end

    return {
        startedAt = combatSummary.startedAt,
        endedAt = combatSummary.endedAt,
        duration = combatSummary.duration,
        dataSource = combatSummary.dataSource,
        combatLogCaptured = combatSummary.combatLogCaptured,
        eventCount = combatSummary.eventCount,
        interruptCount = combatSummary.interruptCount,
        segmentCount = combatSummary.segmentCount,
        matchWindowResolved = combatSummary.matchWindowResolved,
        killEvents = PVL.DeepCopyForExport(combatSummary.killEvents),
        rawCombatEvents = PVL.DeepCopyForExport(combatSummary.rawCombatEvents),
        players = players,
    }
end

--- Builds a full match payload suitable for desktop app upload.
--- @param matchRecord table
--- @return table|nil
function PVL.BuildMatchExportRecord(matchRecord)
    if type(matchRecord) ~= "table" then
        return nil
    end

    local roster = {}
    for _, participant in ipairs(matchRecord.roster or {}) do
        table.insert(roster, PVL.BuildExportRosterRow(participant))
    end

    return {
        matchId = matchRecord.matchId,
        matchFingerprint = matchRecord.matchFingerprint,
        rosterFingerprint = matchRecord.rosterFingerprint,
        bracket = matchRecord.bracket,
        timestamp = matchRecord.timestamp,
        mapID = matchRecord.mapID,
        won = matchRecord.won,
        playerSpec = matchRecord.playerSpec,
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

--- Persists export metadata, account snapshots, and identity for the desktop sync app.
function PVL.SaveAppHelperExport()
    local db = PVL.GetDB()
    if not db or not db.settings.shareMatchData then
        return
    end

    local appDb = PVL.GetAppHelperDB()
    appDb.sync.addonVersion = PVL.VERSION
    appDb.sync.lastCharacter = UnitName("player") .. " - " .. GetRealmName()
    appDb.sync.accountIdentity = PVL.CollectAccountIdentity()
    appDb.export.lastExportedAt = time()
    appDb.export.accountSnapshot = PVL.BuildAccountSnapshot()
    appDb.export.characterSnapshot = PVL.BuildCharacterSnapshot()
    appDb.export.schemaVersion = PVL.EXPORT_SCHEMA_VERSION
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
