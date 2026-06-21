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
        "PVL_AUTO_REFRESH_LADDER",
        "autoRefreshLadderData",
        db.settings,
        PVL.L("SETTINGS.AUTO_REFRESH_NAME"),
        true,
        PVL.L("SETTINGS.AUTO_REFRESH_DESC")
    )

    local defaultLadderRegionChoice = db.settings.ladderRegionChoice or 1
    local ladderRegionSetting = Settings.RegisterAddOnSetting(
        category,
        "PVL_LADDER_REGION",
        "ladderRegionChoice",
        db.settings,
        type(defaultLadderRegionChoice),
        PVL.L("SETTINGS.REGION_NAME"),
        defaultLadderRegionChoice
    )

    local function GetLadderRegionOptions()
        local container = Settings.CreateControlTextContainer()
        for index, region in ipairs(PVL.LADDER_REGION_OPTIONS) do
            container:Add(index, PVL.REGION_NAMES[region] or region)
        end
        return container:GetData()
    end

    Settings.CreateDropdown(
        category,
        ladderRegionSetting,
        GetLadderRegionOptions,
        PVL.L("SETTINGS.REGION_DESC")
    )

    ladderRegionSetting:SetValueChangedCallback(function()
        PVL.RefreshImportedLadderData()
        if PVL.RequestUiRefresh then
            PVL.RequestUiRefresh()
        end
    end)

    RegisterBoolean(
        category,
        "PVL_SHARE_MATCH_DATA",
        "shareMatchData",
        db.settings,
        PVL.L("SETTINGS.SHARE_NAME"),
        false,
        PVL.L("SETTINGS.SHARE_DESC")
    )

    RegisterBoolean(
        category,
        "PVL_HIDE_MINIMAP",
        "hide",
        db.settings.minimap,
        PVL.L("SETTINGS.MINIMAP_HIDE_NAME"),
        false,
        PVL.L("SETTINGS.MINIMAP_HIDE_DESC"),
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
    if not PVL.CanOpenAddonWindows() then
        return
    end

    if not PVL._settingsRegistered then
        PVL.RegisterSettingsPanel()
    end

    if Settings and Settings.OpenToCategory and PVL.settingsCategory then
        Settings.OpenToCategory(PVL.settingsCategory:GetID())
    end
end
