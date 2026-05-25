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

--- Loads packaged ladder snapshots into SavedVariables if present.
function PVL.LoadImportedSnapshotFromPack()
    if type(PvPLedgerLadderData) ~= "table" then
        return
    end

    if PvPLedgerLadderData.snapshotId then
        PVL.SetImportedSnapshot(PvPLedgerLadderData)
        return
    end

    for _, snapshot in pairs(PvPLedgerLadderData) do
        if type(snapshot) == "table" and snapshot.snapshotId then
            PVL.SetImportedSnapshot(snapshot)
        end
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
    local bracket = PVL.GetActiveBracketFilter()
    local snapshot = PVL.GetImportedSnapshot(bracket)
    local matchCount = #(PVL.GetObservedMatches(bracket) or {})
    local bracketName = PVL.BRACKET_NAMES[bracket] or bracket

    return string.format(
        "viewing=%s | matches=%d | snapshot=%s (%s) | enabled=%s",
        bracketName,
        matchCount,
        snapshot and (snapshot.snapshotDate or snapshot.snapshotId or "loaded") or "none",
        snapshot and PVL.FormatSnapshotAge(snapshot.snapshotDate) or "n/a",
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
