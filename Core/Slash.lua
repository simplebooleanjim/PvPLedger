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
            return
        end

        if command == "reload" then
            PVL.LoadImportedSnapshotFromPack()
            PVL.UI.Refresh()
            Print("Reloaded imported ladder snapshot.")
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

        if command == "help" then
            Print("Commands: toggle | show | hide | status | reload | enable | disable | help")
            Print("Live ladder data: run collector/fetch_ladder.bat, then /reload")
            return
        end

        Print("Commands: toggle | show | hide | status | reload | enable | disable | help")
    end
end

RegisterSlashCommands()
