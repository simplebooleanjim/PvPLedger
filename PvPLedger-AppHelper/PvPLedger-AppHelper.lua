--- Bridges PvPLedger Sync AppData payloads into the main PvPLedger addon.
--- @class PvPLedgerAppHelper
local APP_HELPER = {}

--- Processes ladder snapshots written by PvPLedger Sync into the main addon.
function APP_HELPER.ProcessPendingSnapshots()
    if not PvPLedger or not PvPLedger.ApplyAppSyncSnapshots then
        return
    end

    if type(PVL_AppHelperPendingSnapshots) ~= "table" then
        return
    end

    PvPLedger.ApplyAppSyncSnapshots(PVL_AppHelperPendingSnapshots, PVL_AppHelperSyncInfo)
end

--- Clears uploaded matches from the export queue after Sync confirms ingestion.
function APP_HELPER.ProcessExportAck()
    if not PvPLedger or not PvPLedger.ApplyExportAck then
        return
    end

    if type(PVL_AppHelperExportAck) ~= "table" then
        return
    end

    PvPLedger.ApplyExportAck(PVL_AppHelperExportAck)
end

APP_HELPER.ProcessPendingSnapshots()
APP_HELPER.ProcessExportAck()
