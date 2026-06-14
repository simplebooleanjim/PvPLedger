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

--- Loads packaged ladder snapshots into runtime memory if present.
function PVL.LoadImportedSnapshotFromPack()
    PVL.RefreshImportedLadderData({ loadDataAddon = false, loadAppHelper = false })
end

--- Initializes SavedVariables and starts runtime modules.
function PVL.Init()
    PVL.MigrateLegacySavedVars()

    if PVL.InitLocale then
        PVL.InitLocale()
    end

    PvPLedgerDB = PVL.MigrateDB(PvPLedgerDB or PVL.GetDefaultDB())
    PvPLedgerCharDB = PVL.MigrateCharDB(PvPLedgerCharDB or PVL.GetDefaultCharDB())

    PVL.CaptureBundledLadderData()
    if PVL.GetDB().settings.autoRefreshLadderData then
        PVL.RefreshImportedLadderData()
    else
        PVL.LoadImportedSnapshotFromPack()
    end

    if PVL.InspectQueue then
        PVL.InspectQueue.Init()
    end

    if PVL.MatchCollector then
        PVL.MatchCollector.Init()
        if PVL.MatchCollector.EnsureMatchTracking then
            PVL.MatchCollector.EnsureMatchTracking()
        end
    end

    if PVL.CombatLogCollector then
        PVL.CombatLogCollector.Init()
    end

    if PVL.RatedInfo then
        PVL.RatedInfo.Init()
    end

    if PVL.CrHistory then
        PVL.CrHistory.Init()
    end

    if PVL.RegisterSettingsPanel then
        PVL.RegisterSettingsPanel()
    end

    print(string.format("|cff66ccffPvPLedger|r %s", PVL.L("CHAT.LOADED", PVL.VERSION)))
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
        "region=%s | viewing=%s | matches=%d | snapshot=%s (%s) | enabled=%s",
        PVL.GetActiveLadderRegion(),
        bracketName,
        matchCount,
        snapshot and (snapshot.snapshotDate or snapshot.snapshotId or "loaded") or "none",
        snapshot and PVL.FormatSnapshotAge(snapshot.snapshotDate) or "n/a",
        tostring(db.settings.enabled)
    )
end

--- Returns true when one addon name is a ladder data or bridge dependency.
--- @param addonName string|nil
--- @return boolean
function PVL.IsLadderDependencyAddon(addonName)
    if not addonName then
        return false
    end

    if addonName == PVL.APP_HELPER_NAME then
        return true
    end

    return addonName:match("^PvPLedger%-Data%-") ~= nil
end

--- Creates the bootstrap frame that runs on ADDON_LOADED / PLAYER_LOGIN.
local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("PLAYER_LOGOUT")
bootstrap:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == PVL.ADDON_NAME then
        PVL.Init()
    elseif event == "ADDON_LOADED" and PVL.IsLadderDependencyAddon(arg1) then
        PVL.RefreshImportedLadderData()
        if PVL.UI and PVL.UI.Refresh then
            PVL.UI.Refresh()
        end
    elseif event == "PLAYER_LOGIN" then
        if PVL.GetDB().settings.autoRefreshLadderData then
            PVL.RefreshImportedLadderData()
        else
            PVL.LoadImportedSnapshotFromPack()
        end
        if PVL.UI then
            PVL.UI.Refresh()
        end
    elseif event == "PLAYER_LOGOUT" then
        if PVL.SaveAppHelperExport then
            PVL.SaveAppHelperExport()
        end
    end
end)
