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
    if not exportRecord then
        return
    end

    local appDb = PVL.GetAppHelperDB()
    table.insert(appDb.export.pendingMatches, exportRecord)

    while #appDb.export.pendingMatches > PVL.MAX_EXPORT_MATCHES do
        table.remove(appDb.export.pendingMatches, 1)
    end

    appDb.export.lastMatchAt = exportRecord.timestamp
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
        table.insert(lines, "Match export: disabled (opt in via settings).")
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

    return lines
end
