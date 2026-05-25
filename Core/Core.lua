--- Addon bootstrap, database initialization, and module wiring.
--- @class PvPLedger
local PVL = PvPLedger

--- Copies legacy BlitzLedger saved variables into the PvPLedger names once.
function PVL.MigrateLegacySavedVars()
    -- Legacy global names from the BlitzLedger rename.
    local legacyDb = _G.BlitzLedgerDB
    local legacyCharDb = _G.BlitzLedgerCharDB
    local legacyLadderData = _G.BlitzLedgerLadderData

    if legacyDb and not PvPLedgerDB then
        PvPLedgerDB = legacyDb
    end

    if legacyCharDb and not PvPLedgerCharDB then
        PvPLedgerCharDB = legacyCharDb
    end

    if legacyLadderData and not PvPLedgerLadderData then
        PvPLedgerLadderData = legacyLadderData
    end
end

--- Loads the packaged ladder snapshot into SavedVariables if present.
function PVL.LoadImportedSnapshotFromPack()
    if type(PvPLedgerLadderData) == "table" then
        PVL.SetImportedSnapshot(PvPLedgerLadderData)
    end
end

--- Initializes SavedVariables and starts runtime modules.
function PVL.Init()
    PVL.MigrateLegacySavedVars()

    PvPLedgerDB = PVL.MigrateDB(PvPLedgerDB or PVL.GetDefaultDB())
    PvPLedgerCharDB = PVL.MigrateCharDB(PvPLedgerCharDB or PVL.GetDefaultCharDB())

    PVL.LoadImportedSnapshotFromPack()

    if PVL.InspectQueue then
        PVL.InspectQueue.Init()
    end

    if PVL.MatchCollector then
        PVL.MatchCollector.Init()
    end

    print(string.format("|cff66ccffPvPLedger|r v%s loaded. Type |cffFFFF00/pvl|r for commands.", PVL.VERSION))
end

--- Returns a short status string for slash command output.
--- @return string
function PVL.GetStatusText()
    local db = PVL.GetDB()
    local snapshot = PVL.GetImportedSnapshot()
    local matchCount = db and #(db.observations.matches or {}) or 0
    local snapshotLabel = snapshot and snapshot.snapshotId or "none"

    return string.format(
        "matches=%d snapshot=%s enabled=%s",
        matchCount,
        snapshotLabel,
        tostring(db.settings.enabled)
    )
end

--- Creates the bootstrap frame that runs on ADDON_LOADED / PLAYER_LOGIN.
local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == PVL.ADDON_NAME then
        PVL.Init()
    elseif event == "PLAYER_LOGIN" then
        PVL.LoadImportedSnapshotFromPack()
        if PVL.UI then
            PVL.UI.Refresh()
        end
    end
end)
