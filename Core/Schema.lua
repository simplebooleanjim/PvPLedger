--- SavedVariables schema helpers and default database initialization.
--- @class PvPLedger
local PVL = PvPLedger

--- Returns a fresh default account database table.
--- @return table
function PVL.GetDefaultDB()
    return {
        version = PVL.DB_VERSION,
        meta = {
            addonVersion = PVL.VERSION,
            lastMatchAt = nil,
            lastLadderRefreshAt = nil,
            dataAddonInstalled = nil,
            dataAddonVersion = nil,
            appHelperInstalled = nil,
            appSyncGeneratedAt = nil,
        },
        settings = {
            enabled = true,
            collectSpecs = true,
            collectCombatSummary = true,
            collectNonBlitz = false,
            autoRefreshLadderData = true,
            shareMatchData = false,
            uiFilters = {
                bracket = PVL.BRACKETS.BLITZ,
                classToken = nil,
                specKey = nil,
                combatStat = PVL.DEFAULT_COMBAT_ANALYSIS_STAT,
            },
        },
        observations = {
            matches = {},
            players = {},
            specCounts = {},
        },
    }
end

--- Runtime-only imported snapshots loaded from packaged ladder files.
--- Intentionally not stored in SavedVariables to keep login fast.
PVL.ImportedSnapshots = PVL.ImportedSnapshots or {}

--- Returns a fresh per-character database table.
--- @return table
function PVL.GetDefaultCharDB()
    return {
        version = PVL.DB_VERSION,
        lastBlitzCR = nil,
        lastBlitzMMR = nil,
        lastBlitzMMRKind = nil,
        lastShuffleCR = nil,
        lastShuffleMMR = nil,
        lastShuffleMMRKind = nil,
        lastRbgCR = nil,
        lastRbgMMR = nil,
        lastRbgMMRKind = nil,
        lastArena2v2CR = nil,
        lastArena2v2MMR = nil,
        lastArena2v2MMRKind = nil,
        lastArena3v3CR = nil,
        lastArena3v3MMR = nil,
        lastArena3v3MMRKind = nil,
        crHistory = {},
        crHistoryBackfilled = false,
    }
end

--- Ensures the account database contains all expected keys after upgrades.
--- @param db table
function PVL.MigrateDB(db)
    if type(db) ~= "table" then
        return PVL.GetDefaultDB()
    end

    local defaults = PVL.GetDefaultDB()
    db.version = db.version or defaults.version
    db.meta = db.meta or defaults.meta
    db.meta.addonVersion = db.meta.addonVersion or defaults.meta.addonVersion
    db.meta.lastMatchAt = db.meta.lastMatchAt
    db.meta.lastLadderRefreshAt = db.meta.lastLadderRefreshAt
    db.meta.dataAddonInstalled = db.meta.dataAddonInstalled
    db.meta.dataAddonVersion = db.meta.dataAddonVersion
    db.meta.appHelperInstalled = db.meta.appHelperInstalled
    db.meta.appSyncGeneratedAt = db.meta.appSyncGeneratedAt
    db.settings = db.settings or defaults.settings
    if db.settings.autoRefreshLadderData == nil then
        db.settings.autoRefreshLadderData = defaults.settings.autoRefreshLadderData
    end
    if db.settings.shareMatchData == nil then
        db.settings.shareMatchData = defaults.settings.shareMatchData
    end
    if db.settings.collectCombatSummary == nil then
        db.settings.collectCombatSummary = defaults.settings.collectCombatSummary
    end
    db.settings.uiFilters = db.settings.uiFilters or defaults.settings.uiFilters
    db.settings.uiFilters.bracket = db.settings.uiFilters.bracket or defaults.settings.uiFilters.bracket
    if db.settings.uiFilters.combatStat == nil then
        db.settings.uiFilters.combatStat = defaults.settings.uiFilters.combatStat
    end
    db.observations = db.observations or defaults.observations
    db.observations.matches = db.observations.matches or {}
    db.observations.players = db.observations.players or {}
    db.observations.specCounts = db.observations.specCounts or {}

    if type(db.imported) == "table" then
        db.imported = nil
    end

    return db
end

--- Ensures the per-character database contains all expected keys.
--- @param charDb table
function PVL.MigrateCharDB(charDb)
    if type(charDb) ~= "table" then
        return PVL.GetDefaultCharDB()
    end

    charDb.version = charDb.version or PVL.DB_VERSION
    charDb.lastBlitzCR = charDb.lastBlitzCR
    charDb.lastBlitzMMR = charDb.lastBlitzMMR
    charDb.lastBlitzMMRKind = charDb.lastBlitzMMRKind
    charDb.lastShuffleCR = charDb.lastShuffleCR
    charDb.lastShuffleMMR = charDb.lastShuffleMMR
    charDb.lastShuffleMMRKind = charDb.lastShuffleMMRKind
    charDb.lastRbgCR = charDb.lastRbgCR
    charDb.lastRbgMMR = charDb.lastRbgMMR
    charDb.lastRbgMMRKind = charDb.lastRbgMMRKind
    charDb.lastArena2v2CR = charDb.lastArena2v2CR
    charDb.lastArena2v2MMR = charDb.lastArena2v2MMR
    charDb.lastArena2v2MMRKind = charDb.lastArena2v2MMRKind
    charDb.lastArena3v3CR = charDb.lastArena3v3CR
    charDb.lastArena3v3MMR = charDb.lastArena3v3MMR
    charDb.lastArena3v3MMRKind = charDb.lastArena3v3MMRKind
    charDb.crHistory = charDb.crHistory or {}
    charDb.crHistoryBackfilled = charDb.crHistoryBackfilled == true

    return charDb
end
