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
            if PVL.UI and PVL.UI.Toggle then
                PVL.UI.Toggle()
            else
                Print(PVL.L("SLASH.UI_UNAVAILABLE"))
            end
            return
        end

        if command == "show" then
            if PVL.UI and PVL.UI.Show then
                PVL.UI.Show()
            else
                Print(PVL.L("SLASH.UI_UNAVAILABLE"))
            end
            return
        end

        if command == "titles" or command == "cutoffs" then
            if PVL.UI and PVL.UI.TitleView then
                PVL.UI.TitleView.Show()
            end
            return
        end

        if command == "hide" then
            PVL.UI.Hide()
            return
        end

        if command == "options" or command == "config" or command == "settings" then
            if PVL.OpenSettings then
                PVL.OpenSettings()
            end
            return
        end

        if command == "status" then
            Print(PVL.GetStatusText())
            Print(PVL.L("SLASH.IMPORTED_HEADER"))
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

        if command == "update" or command == "refresh" then
            local summary = PVL.RefreshImportedLadderData()
            if PVL.RequestUiRefresh then
                PVL.RequestUiRefresh()
            end
            if summary.loadedAppHelper then
                Print(PVL.L("SLASH.UPDATE_APP_HELPER"))
            elseif summary.loadedDataAddon then
                Print(PVL.L(
                    "SLASH.UPDATE_DATA_ADDON",
                    PVL.GetDataAddonName(summary.region or PVL.GetActiveLadderRegion())
                ))
            elseif PVL.IsAppHelperInstalled() or PVL.IsDataAddonInstalled(PVL.GetActiveLadderRegion()) then
                Print(PVL.L("SLASH.UPDATE_SOURCES"))
            else
                Print(PVL.L("SLASH.UPDATE_BUNDLED"))
                Print(PVL.APP_HELPER_INSTALL_HINT)
            end
            Print(PVL.L("SLASH.UPDATE_RELOAD_HINT"))
            return
        end

        if command == "share on" or command == "export on" then
            PVL.SetShareMatchData(true)
            Print(PVL.L("SLASH.SHARE_ON"))
            if PVL.RequestUiRefresh then
                PVL.RequestUiRefresh()
            end
            return
        end

        if command == "share off" or command == "export off" then
            PVL.SetShareMatchData(false)
            Print(PVL.L("SLASH.SHARE_OFF"))
            if PVL.RequestUiRefresh then
                PVL.RequestUiRefresh()
            end
            return
        end

        if command == "reload" then
            PVL.LoadImportedSnapshotFromPack()
            if PVL.RequestUiRefresh then
                PVL.RequestUiRefresh()
            end
            Print(PVL.L("SLASH.RELOAD_DONE"))
            return
        end

        if command == "enable" then
            PVL.GetDB().settings.enabled = true
            Print(PVL.L("SLASH.ENABLE_ON"))
            return
        end

        if command == "disable" then
            PVL.GetDB().settings.enabled = false
            Print(PVL.L("SLASH.ENABLE_OFF"))
            return
        end

        if command == "prune" then
            PVL.PruneImportedSnapshotPlayers()
            PVL.LoadImportedSnapshotFromPack()
            Print(PVL.L("SLASH.PRUNE_DONE"))
            return
        end

        if command == "debug score" or command == "debug match" or command == "debug combat" then
            if PVL.MatchCollector and PVL.MatchCollector.PrintScoreDebug then
                PVL.MatchCollector.PrintScoreDebug()
            end
            return
        end

        if command == "debug rated" then
            if PVL.RatedInfo and PVL.RatedInfo.PrintDebug then
                PVL.RatedInfo.PrintDebug()
            end
            return
        end

        if command == "history" or command == "cr" then
            if PVL.CrHistory and PVL.CrHistory.PrintHistory then
                PVL.CrHistory.PrintHistory()
            end
            return
        end

        if command == "match" or command:match("^match ") then
            local bracket = PVL.GetActiveBracketFilter()
            local arg = command == "match" and "last" or strtrim(command:sub(7))
            local matchRecord = nil

            if arg == "" or arg == "last" then
                matchRecord = PVL.GetRecentMatches(bracket, 1)[1]
            else
                local index = tonumber(arg)
                if index then
                    matchRecord = PVL.GetRecentMatches(bracket, index)[index]
                else
                    matchRecord = PVL.GetMatchById(arg)
                end
            end

            if not matchRecord then
                Print(PVL.L("SLASH.MATCH_NOT_FOUND"))
                return
            end

            if PVL.UI then
                PVL.UI.SetSelectedMatchId(matchRecord.matchId)
                PVL.UI.Show()
            end
            return
        end

        if command == "help" then
            Print(PVL.L("SLASH.HELP_COMMANDS"))
            Print(PVL.L("SLASH.HELP_TITLES"))
            Print(PVL.L("SLASH.HELP_SYNC"))
            Print(PVL.L("SLASH.HELP_SHARE"))
            Print(PVL.L("SLASH.HELP_STATUS"))
            return
        end

        Print(PVL.L("SLASH.HELP_COMMANDS"))
    end
end

RegisterSlashCommands()
