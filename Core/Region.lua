--- Ladder region detection and normalization helpers.
--- @class PvPLedger
local PVL = PvPLedger

--- Ordered ladder region options shown in settings.
PVL.LADDER_REGION_OPTIONS = {
    PVL.LADDER_REGION_AUTO,
    PVL.REGIONS.US,
    PVL.REGIONS.EU,
    PVL.REGIONS.KR,
    PVL.REGIONS.TW,
}

--- Human-readable labels for ladder region settings (populated in PVL.InitLocale).
PVL.REGION_NAMES = PVL.REGION_NAMES or {}

--- Maps WoW ``GetCurrentRegion()`` ids to ladder region codes.
PVL.CLIENT_REGION_BY_ID = {
    [1] = PVL.REGIONS.US,
    [2] = PVL.REGIONS.KR,
    [3] = PVL.REGIONS.EU,
    [4] = PVL.REGIONS.TW,
}

--- Returns a normalized supported ladder region code.
--- @param region string|nil
--- @return string
function PVL.NormalizeLadderRegion(region)
    region = string.upper(tostring(region or PVL.REGIONS.US))
    if PVL.REGIONS[region] then
        return region
    end

    return PVL.REGIONS.US
end

--- Returns the player's Battle.net region inferred from the WoW client.
--- @return string
function PVL.DetectClientRegion()
    if GetCurrentRegion then
        local regionId = GetCurrentRegion()
        local mapped = PVL.CLIENT_REGION_BY_ID[regionId]
        if mapped then
            return mapped
        end
    end

    return PVL.REGIONS.US
end

--- Returns the settings dropdown index for one ladder region option.
--- @param region string|nil
--- @return number
function PVL.GetLadderRegionChoiceIndex(region)
    for index, option in ipairs(PVL.LADDER_REGION_OPTIONS) do
        if option == region then
            return index
        end
    end

    return 1
end

--- Returns the ladder region option for one settings dropdown index.
--- @param choiceIndex number|nil
--- @return string
function PVL.GetLadderRegionChoiceValue(choiceIndex)
    return PVL.LADDER_REGION_OPTIONS[choiceIndex] or PVL.LADDER_REGION_AUTO
end

--- Returns the ladder region selected in settings, or auto-detected when set to Auto.
--- @return string
function PVL.GetActiveLadderRegion()
    local db = PVL.GetDB and PVL.GetDB()
    local choice = db and db.settings and db.settings.ladderRegionChoice
    local setting = PVL.GetLadderRegionChoiceValue(choice)
    if setting ~= PVL.LADDER_REGION_AUTO then
        return PVL.NormalizeLadderRegion(setting)
    end

    return PVL.DetectClientRegion()
end

--- Returns the optional companion addon name for one ladder region.
--- @param region string|nil
--- @return string
function PVL.GetDataAddonName(region)
    return string.format("PvPLedger-Data-%s", PVL.NormalizeLadderRegion(region))
end

--- Returns an install hint for one region's companion data addon.
--- @param region string|nil
--- @return string
function PVL.GetDataAddonInstallHint(region)
    return PVL.L("HINT.DATA_ADDON_INSTALL_REGION", PVL.GetDataAddonName(region))
end

--- Returns true when a snapshot belongs to the requested ladder region.
--- @param snapshot table|nil
--- @param region string|nil
--- @return boolean
function PVL.SnapshotMatchesRegion(snapshot, region)
    if not snapshot then
        return false
    end

    local snapshotRegion = PVL.NormalizeLadderRegion(snapshot.region or PVL.REGIONS.US)
    return snapshotRegion == PVL.NormalizeLadderRegion(region)
end

--- Returns true when one table key is a supported ladder region code.
--- @param key string|number
--- @return boolean
function PVL.IsLadderRegionKey(key)
    if type(key) ~= "string" then
        return false
    end

    return PVL.REGIONS[key] ~= nil
end
