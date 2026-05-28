--- Registers PvPLedger options in Game Menu > Options > AddOns.
--- @class PvPLedger
local PVL = PvPLedger

PVL._settingsRegistered = PVL._settingsRegistered or false

--- Registers the addon settings category with the Blizzard Settings UI.
function PVL.RegisterSettingsPanel()
    if PVL._settingsRegistered then
        return
    end

    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        return
    end

    local db = PVL.GetDB()
    db.settings = db.settings or {}

    local category = Settings.RegisterVerticalLayoutCategory(PVL.ADDON_NAME or "PvPLedger")
    local variable = "PVL_SHARE_MATCH_DATA"
    local variableKey = "shareMatchData"
    local variableTbl = db.settings
    local defaultValue = false
    local name = "Share match data with PvPLedger Sync"
    local tooltip = "When enabled, completed matches are queued for export to the desktop sync app on logout."

    local setting = Settings.RegisterAddOnSetting(
        category,
        variable,
        variableKey,
        variableTbl,
        type(defaultValue),
        name,
        defaultValue
    )

    Settings.CreateCheckbox(category, setting, tooltip)

    local combatSetting = Settings.RegisterAddOnSetting(
        category,
        "PVL_COLLECT_COMBAT_SUMMARY",
        "collectCombatSummary",
        variableTbl,
        type(true),
        "Record match combat stats",
        true
    )
    Settings.CreateCheckbox(
        category,
        combatSetting,
        "Silently capture per-player damage, healing, interrupts, CC, and kills for later review."
    )

    Settings.RegisterAddOnCategory(category)

    PVL._settingsRegistered = true
end
