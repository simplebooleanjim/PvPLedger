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
        },
        settings = {
            enabled = true,
            collectSpecs = true,
            collectNonBlitz = false,
            uiFilters = {
                classToken = nil,
                specKey = nil,
            },
        },
        observations = {
            matches = {},
            players = {},
            specCounts = {},
        },
        imported = nil,
    }
end

--- Returns a fresh per-character database table.
--- @return table
function PVL.GetDefaultCharDB()
    return {
        version = PVL.DB_VERSION,
        lastBlitzCR = nil,
        lastBlitzMMR = nil,
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
    db.settings = db.settings or defaults.settings
    db.settings.uiFilters = db.settings.uiFilters or defaults.settings.uiFilters
    db.observations = db.observations or defaults.observations
    db.observations.matches = db.observations.matches or {}
    db.observations.players = db.observations.players or {}
    db.observations.specCounts = db.observations.specCounts or {}

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

    return charDb
end
