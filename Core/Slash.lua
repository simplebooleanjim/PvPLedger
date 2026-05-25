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
            if PVL.GetAppExportStatusLines then
                for _, line in ipairs(PVL.GetAppExportStatusLines()) do
                    Print("  " .. line)
                end
            end
            return
        end

        if command == "update" then
            local summary = PVL.RefreshImportedLadderData()
            PVL.UI.Refresh()
            if summary.loadedAppHelper then
                Print("Loaded PvPLedger-AppHelper and refreshed imported ladder snapshots.")
            elseif summary.loadedDataAddon then
                Print("Loaded PvPLedger-Data-US and refreshed imported ladder snapshots.")
            elseif PVL.IsAppHelperInstalled() or PVL.IsDataAddonInstalled() then
                Print("Refreshed imported ladder snapshots from installed data sources.")
            else
                Print("Refreshed bundled ladder snapshots.")
                Print(PVL.APP_HELPER_INSTALL_HINT)
            end
            Print("If you updated addon files on disk, run /reload to pick up the new files.")
            return
        end

        if command == "share on" or command == "export on" then
            PVL.GetDB().settings.shareMatchData = true
            Print("Match export enabled for PvPLedger Sync.")
            return
        end

        if command == "share off" or command == "export off" then
            PVL.GetDB().settings.shareMatchData = false
            Print("Match export disabled.")
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
            Print("Commands: toggle | show | hide | status | update | reload | share on|off | enable | disable | help")
            Print("Install PvPLedger-AppHelper + PvPLedger Sync for automatic ladder updates.")
            Print("Use /pvl share on to queue match exports for the desktop sync app.")
            Print("Use /pvl update after sync updates AppData.lua, then /reload if needed.")
            Print("Use /pvl status to see snapshot dates and active data source per bracket.")
            return
        end

        Print("Commands: toggle | show | hide | status | update | reload | share on|off | enable | disable | help")
    end
end

RegisterSlashCommands()
