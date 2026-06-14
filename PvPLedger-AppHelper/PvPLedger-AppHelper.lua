--- Bridges PvPLedger Sync AppData payloads into the main PvPLedger addon.
--- @class PvPLedgerAppHelper
local APP_HELPER = {}

--- Applies one regional snapshot payload into the main addon.
--- @param snapshots table<string, table>|nil
--- @param syncInfo table|nil
function APP_HELPER.ApplyRegionalSnapshots(snapshots, syncInfo)
    if not PvPLedger or not PvPLedger.ApplyAppSyncSnapshots then
        return
    end

    if type(snapshots) ~= "table" then
        return
    end

    PvPLedger.ApplyAppSyncSnapshots(snapshots, syncInfo)
end

--- Processes ladder snapshots written by PvPLedger Sync into the main addon.
function APP_HELPER.ProcessPendingSnapshots()
    if type(PVL_AppHelperPendingSnapshotsByRegion) == "table" then
        for region, snapshots in pairs(PVL_AppHelperPendingSnapshotsByRegion) do
            local syncInfo = type(PVL_AppHelperSyncInfoByRegion) == "table"
                and PVL_AppHelperSyncInfoByRegion[region]
                or { region = region }
            APP_HELPER.ApplyRegionalSnapshots(snapshots, syncInfo)
        end
    end

    APP_HELPER.ApplyRegionalSnapshots(PVL_AppHelperPendingSnapshots, PVL_AppHelperSyncInfo)
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
