--- Slash command handlers for PvPLedger.
--- @class PvPLedger
local PVL = PvPLedger

--- Prints a formatted chat message.
--- @param message string
local function Print(message)
    print(string.format("|cff66ccffPvPLedger|r: %s", message))
end

--- Registers slash commands.
local function RegisterSlashCommands()
    SLASH_PVPLEDGER1 = "/pvpledger"
    SLASH_PVPLEDGER2 = "/pvl"

    SlashCmdList["PVPLEDGER"] = function(input)
        local command = strtrim(string.lower(input or ""))

        if command == "" or command == "toggle" then
            PVL.UI.Toggle()
            return
        end

        if command == "show" then
            PVL.UI.Show()
            return
        end

        if command == "hide" then
            PVL.UI.Hide()
            return
        end

        if command == "status" then
            Print(PVL.GetStatusText())
            Print("Imported snapshots:")
            for _, line in ipairs(PVL.GetImportedSnapshotStatusLines()) do
                Print("  " .. line)
            end
            for _, line in ipairs(PVL.GetLadderUpdateStatusLines()) do
                Print("  " .. line)
            end
            return
        end

        if command == "update" then
            local summary = PVL.RefreshImportedLadderData()
            PVL.UI.Refresh()
            if summary.loadedDataAddon then
                Print("Loaded PvPLedger-Data-US and refreshed imported ladder snapshots.")
            elseif PVL.IsDataAddonInstalled() then
                Print("Refreshed imported ladder snapshots from installed data sources.")
            else
                Print("Refreshed bundled ladder snapshots.")
                Print(PVL.DATA_ADDON_INSTALL_HINT)
            end
            Print("If you updated addon files on disk, run /reload to pick up the new files.")
            return
        end

        if command == "reload" then
            PVL.LoadImportedSnapshotFromPack()
            PVL.UI.Refresh()
            Print("Reloaded bundled ladder snapshots.")
            return
        end

        if command == "enable" then
            PVL.GetDB().settings.enabled = true
            Print("Match collection enabled.")
            return
        end

        if command == "disable" then
            PVL.GetDB().settings.enabled = false
            Print("Match collection disabled.")
            return
        end

        if command == "prune" then
            PVL.PruneImportedSnapshotPlayers()
            PVL.LoadImportedSnapshotFromPack()
            Print("Removed bulky imported player indexes from SavedVariables.")
            return
        end

        if command == "help" then
            Print("Commands: toggle | show | hide | status | update | reload | prune | enable | disable | help")
            Print("Install PvPLedger-Data-US beside PvPLedger for fresher ladder data between main-addon releases.")
            Print("Use /pvl update after your addon manager updates the data addon, then /reload if needed.")
            Print("Use /pvl status to see snapshot dates and active data source per bracket.")
            return
        end

        Print("Commands: toggle | show | hide | status | update | reload | prune | enable | disable | help")
    end
end

RegisterSlashCommands()
