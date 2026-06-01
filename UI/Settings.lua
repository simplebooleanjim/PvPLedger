--- Registers PvPLedger options in Game Menu > Options > AddOns.
--- @class PvPLedger
local PVL = PvPLedger

PVL._settingsRegistered = PVL._settingsRegistered or false

--- Registers a single boolean checkbox bound to a settings-table key.
--- @param category table The settings category the checkbox belongs to.
--- @param variable string Unique CVar-like identifier for the setting.
--- @param key string Field name within the backing table.
--- @param tbl table Table that stores the boolean value.
--- @param name string Checkbox label shown to the player.
--- @param default boolean Default value when unset.
--- @param tooltip string Hover description for the checkbox.
--- @param onChanged fun(value: boolean)|nil Optional value-changed callback.
--- @return table setting The registered setting object.
local function RegisterBoolean(category, variable, key, tbl, name, default, tooltip, onChanged)
    local setting = Settings.RegisterAddOnSetting(
        category,
        variable,
        key,
        tbl,
        type(default),
        name,
        default
    )

    Settings.CreateCheckbox(category, setting, tooltip)

    if onChanged then
        setting:SetValueChangedCallback(function(_, value)
            onChanged(value)
        end)
    end

    return setting
end

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
    db.settings.minimap = db.settings.minimap or { hide = false, position = 220 }

    local category = Settings.RegisterVerticalLayoutCategory(PVL.ADDON_NAME or "PvPLedger")

    RegisterBoolean(
        category,
        "PVL_ENABLED",
        "enabled",
        db.settings,
        "Enable match collection",
        true,
        "Record rated PvP matches and player observations as you play."
    )

    RegisterBoolean(
        category,
        "PVL_COLLECT_COMBAT_SUMMARY",
        "collectCombatSummary",
        db.settings,
        "Record match combat stats",
        true,
        "Silently capture per-player damage, healing, interrupts, CC, and kills from the live combat log for later review."
    )

    RegisterBoolean(
        category,
        "PVL_AUTO_REFRESH_LADDER",
        "autoRefreshLadderData",
        db.settings,
        "Auto-refresh ladder data on login",
        true,
        "Reload bundled and synced ladder snapshots automatically when you log in."
    )

    RegisterBoolean(
        category,
        "PVL_SHARE_MATCH_DATA",
        "shareMatchData",
        db.settings,
        "Share match data with PvPLedger Sync",
        false,
        "When enabled, completed matches are queued for export to the desktop sync app on logout."
    )

    RegisterBoolean(
        category,
        "PVL_HIDE_MINIMAP",
        "hide",
        db.settings.minimap,
        "Hide minimap button",
        false,
        "Hide the PvPLedger minimap button. Left-click the button to open the window; right-click for these options.",
        function()
            if PVL.UI and PVL.UI.MinimapButton and PVL.UI.MinimapButton.Update then
                PVL.UI.MinimapButton.Update()
            end
        end
    )

    Settings.RegisterAddOnCategory(category)

    PVL.settingsCategory = category
    PVL._settingsRegistered = true
end

--- Opens the Blizzard Settings UI to the PvPLedger category.
--- Registers the panel on demand so right-click works even before login hooks.
function PVL.OpenSettings()
    if not PVL._settingsRegistered then
        PVL.RegisterSettingsPanel()
    end

    if Settings and Settings.OpenToCategory and PVL.settingsCategory then
        Settings.OpenToCategory(PVL.settingsCategory:GetID())
    end
end
