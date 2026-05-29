--- Match detail panel helpers for reviewing stored PvP observations.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI
local Format = UI.Format

--- Returns the selected match id from UI filters.
--- @return string|nil
function UI.GetSelectedMatchId()
    local filters = UI.GetFilters()
    return filters.selectedMatchId
end

--- Stores the selected match id and refreshes the main frame.
--- @param matchId string|nil
function UI.SetSelectedMatchId(matchId)
    local filters = UI.GetFilters()
    filters.selectedMatchId = matchId
    UI.Refresh()
end

--- Returns the match record currently selected for the active bracket.
--- @param bracket string|nil
--- @return table|nil
function UI.ResolveSelectedMatch(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    local selectedId = UI.GetSelectedMatchId()
    if selectedId then
        local selectedMatch = PVL.GetMatchById(selectedId)
        if selectedMatch and selectedMatch.bracket == bracket then
            return selectedMatch
        end
    end

    local recentMatches = PVL.GetRecentMatches(bracket, 1)
    return recentMatches[1]
end

--- Returns dropdown options for recent matches in one bracket.
--- @param bracket string|nil
--- @return table[]
function UI.GetRecentMatchOptions(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    local matches = PVL.GetRecentMatches(bracket, PVL.MATCH_HISTORY_UI_LIMIT)
    local options = {}

    if #matches == 0 then
        table.insert(options, {
            label = "No matches recorded",
            value = nil,
        })
        return options
    end

    for _, match in ipairs(matches) do
        local resultLabel = match.won == true and "W" or (match.won == false and "L" or "-")
        local crText = PVL.FormatRating(match.playerCRAfter)
        local timestampText = PVL.CrHistory and PVL.CrHistory.FormatTimestamp(match.timestamp) or "--"
        table.insert(options, {
            label = string.format("%s  %s  CR %s", timestampText, resultLabel, crText),
            value = match.matchId,
        })
    end

    return options
end

--- Returns the selected index for the recent match dropdown.
--- @param bracket string|nil
--- @return number
function UI.GetSelectedMatchIndex(bracket)
    local options = UI.GetRecentMatchOptions(bracket)
    local selectedMatch = UI.ResolveSelectedMatch(bracket)
    if not selectedMatch or not selectedMatch.matchId then
        return 1
    end

    for index, option in ipairs(options) do
        if option.value == selectedMatch.matchId then
            return index
        end
    end

    return 1
end

--- Returns dropdown options for combat analysis stat selection.
--- @return table[]
function UI.GetCombatStatOptions()
    local options = {}
    for _, stat in ipairs(PVL.COMBAT_ANALYSIS_STATS) do
        table.insert(options, {
            label = stat.label,
            value = stat.value,
        })
    end
    return options
end

--- Returns the combat stat definition for one stat id.
--- @param statId string|nil
--- @return table
function UI.GetCombatStatDefinition(statId)
    for _, stat in ipairs(PVL.COMBAT_ANALYSIS_STATS) do
        if stat.value == statId then
            return stat
        end
    end

    return PVL.COMBAT_ANALYSIS_STATS[1]
end

--- Returns the active combat analysis stat id from UI filters.
--- @return string
function UI.GetSelectedCombatStat()
    local filters = UI.GetFilters()
    return filters.combatStat or PVL.DEFAULT_COMBAT_ANALYSIS_STAT
end

--- Stores the selected combat analysis stat and refreshes the UI.
--- @param statId string|nil
function UI.SetCombatStat(statId)
    local filters = UI.GetFilters()
    filters.combatStat = statId or PVL.DEFAULT_COMBAT_ANALYSIS_STAT
    UI.Refresh()
end

--- Returns the selected index for the combat stat dropdown.
--- @return number
function UI.GetSelectedCombatStatIndex()
    return PVL.GetSelectedOptionIndex(UI.GetCombatStatOptions(), UI.GetSelectedCombatStat())
end

--- Returns one numeric combat stat value from a combat row, with scoreboard fallbacks.
--- @param combatRow table|nil
--- @param statDef table
--- @param participant table|nil
--- @return number
function UI.GetCombatStatValue(combatRow, statDef, participant)
    if not statDef or not statDef.field then
        return 0
    end

    local value = combatRow and tonumber(combatRow[statDef.field]) or 0
    if value > 0 or not participant then
        return value or 0
    end

    if statDef.field == "damage" and participant.damageDone then
        return participant.damageDone
    end

    if statDef.field == "healing" and participant.healingDone then
        return participant.healingDone
    end

    return value or 0
end

--- Formats one combat stat value for display.
--- @param value number|nil
--- @param statDef table
--- @return string
function UI.FormatCombatStatValue(value, statDef)
    if statDef.useCombatAmount then
        return Format.CombatAmount(value)
    end

    return Format.Count(value or 0)
end

--- Returns a readable map label for one match record.
--- @param matchRecord table|nil
--- @return string
function UI.GetMatchMapLabel(matchRecord)
    if not matchRecord or not matchRecord.mapID then
        return "Unknown map"
    end

    if C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(matchRecord.mapID)
        if mapInfo and mapInfo.name then
            return mapInfo.name
        end
    end

    return string.format("Map %s", tostring(matchRecord.mapID))
end

--- Returns true when a roster participant is on the local player's team.
--- @param participant table
--- @param matchRecord table|nil
--- @return boolean
function UI.IsFriendlyParticipant(participant, matchRecord)
    if PVL.MatchCollector and PVL.MatchCollector.GetParticipantTeam then
        local team = PVL.MatchCollector.GetParticipantTeam(
            participant,
            matchRecord and matchRecord.roster or nil,
            nil,
            matchRecord
        )
        if team == "friendly" then
            return true
        end
        if team == "enemy" then
            return false
        end
    end

    return participant.isLocalPlayer == true
end

--- Finds one combat summary row for a roster participant.
--- @param combatSummary table|nil
--- @param participant table
--- @return table|nil
function UI.GetCombatRowForParticipant(combatSummary, participant)
    if type(combatSummary) ~= "table" then
        return nil
    end

    for _, row in ipairs(combatSummary.players or {}) do
        if participant.guid and row.guid == participant.guid then
            return row
        end
        if participant.name and row.name == participant.name then
            return row
        end
    end

    return nil
end

--- Returns true when one match has any stored combat totals.
--- @param matchRecord table|nil
--- @param combatSummary table|nil
--- @return boolean
function UI.MatchHasStoredCombatTotals(matchRecord, combatSummary)
    combatSummary = combatSummary or (matchRecord and matchRecord.combatSummary)
    if type(combatSummary) == "table" then
        for _, row in ipairs(combatSummary.players or {}) do
            if (row.damage or 0) > 0
                or (row.healing or 0) > 0
                or (row.damageTaken or 0) > 0
                or (row.interrupts or 0) > 0
                or (row.ccApplied or 0) > 0
                or (row.ccTaken or 0) > 0
                or (row.deaths or 0) > 0 then
                return true
            end
        end
    end

    for _, participant in ipairs(matchRecord and matchRecord.roster or {}) do
        if (participant.damageDone or 0) > 0 or (participant.healingDone or 0) > 0 then
            return true
        end
    end

    return false
end

--- Returns a combat summary for display, synthesizing roster rows when needed.
--- @param matchRecord table|nil
--- @return table|nil
function UI.ResolveMatchCombatSummary(matchRecord)
    if type(matchRecord) ~= "table" then
        return nil
    end

    if type(matchRecord.combatSummary) == "table" and #(matchRecord.combatSummary.players or {}) > 0 then
        return matchRecord.combatSummary
    end

    local roster = matchRecord.roster or {}
    if #roster == 0 then
        return matchRecord.combatSummary
    end

    local players = {}
    for _, participant in ipairs(roster) do
        local team = participant.team
        if PVL.MatchCollector and PVL.MatchCollector.GetParticipantTeam then
            team = PVL.MatchCollector.GetParticipantTeam(participant, roster, nil, matchRecord) or team
        end

        table.insert(players, {
            guid = participant.guid,
            name = participant.name,
            class = participant.class,
            spec = participant.spec,
            team = team,
            isLocalPlayer = participant.isLocalPlayer,
            damage = participant.damageDone or 0,
            healing = participant.healingDone or 0,
            damageTaken = 0,
            interrupts = 0,
            ccApplied = 0,
            ccTaken = 0,
            deaths = 0,
        })
    end

    return {
        startedAt = matchRecord.timestamp,
        endedAt = matchRecord.timestamp,
        duration = matchRecord.combatSummary and matchRecord.combatSummary.duration or nil,
        killEvents = matchRecord.combatSummary and matchRecord.combatSummary.killEvents or {},
        players = players,
    }
end

--- Formats one participant name using their class color when available.
--- @param participant table
--- @return string
function UI.FormatParticipantName(participant)
    local name = participant.name or "Unknown"
    if participant.class then
        return Format.ClassName(participant.class, name)
    end

    return name
end

--- Formats one participant name with a class icon and short spec on one line.
--- Mirrors the Ladder rows: a fixed-width class icon, the class-colored name,
--- then the spec word only (class already shown by the icon and name color).
--- @param participant table
--- @return string
function UI.FormatParticipantNameLine(participant)
    local nameText = UI.FormatParticipantName(participant)
    local iconText = Format.ClassIcon(participant.class)

    local specText
    if participant.spec and participant.class then
        specText = Format.SpecShortName(string.format("%s_%s", participant.class, participant.spec))
    else
        specText = UI.FormatParticipantSpec(participant)
    end

    return string.format("%s%s  %s", iconText, nameText, specText)
end

--- Formats one participant spec label for compact tables.
--- @param participant table
--- @return string
function UI.FormatParticipantSpec(participant)
    if participant.spec and participant.class then
        return Format.SpecName(string.format("%s_%s", participant.class, participant.spec))
    end

    if participant.class then
        return Format.ClassName(participant.class)
    end

    return Format.Muted("Unknown")
end

--- Formats one roster rating delta for match detail rows.
--- @param participant table
--- @return string
function UI.FormatParticipantRatingDelta(participant)
    if participant.ratingChange == nil then
        return Format.Muted("--")
    end

    if PVL.CrHistory then
        return PVL.CrHistory.FormatDelta(participant.ratingChange)
    end

    local sign = participant.ratingChange >= 0 and "+" or ""
    return sign .. tostring(participant.ratingChange)
end

--- Formats one roster row with player identity and rating on a single line.
--- @param participant table
--- @return string
function UI.FormatParticipantRosterLine(participant)
    return string.format(
        "%s  %s  %s",
        UI.FormatParticipantNameLine(participant),
        Format.Rating(participant.rating),
        UI.FormatParticipantRatingDelta(participant)
    )
end

--- Appends one team roster block with CR and rating change.
--- @param lines string[]
--- @param title string
--- @param participants table[]
function UI.AppendMatchRosterBlock(lines, title, participants)
    table.insert(lines, Format.SectionLabel(title))
    table.insert(lines, Format.Divider(300))

    if #participants == 0 then
        table.insert(lines, Format.Muted("No players recorded."))
        table.insert(lines, "")
        return
    end

    for _, participant in ipairs(participants) do
        table.insert(lines, UI.FormatParticipantRosterLine(participant))
    end

    table.insert(lines, "")
end

--- Returns a usable CR change value for sorting, or nil when missing.
--- @param participant table
--- @return number|nil
function UI.GetParticipantRatingChange(participant)
    if participant.ratingChange == nil then
        return nil
    end

    return participant.ratingChange
end

--- Sorts roster participants by CR change descending.
--- @param participants table[]
--- @return table[]
function UI.SortParticipantsByRatingChange(participants)
    local sorted = {}
    for index, participant in ipairs(participants) do
        sorted[index] = participant
    end

    table.sort(sorted, function(a, b)
        local changeA = UI.GetParticipantRatingChange(a)
        local changeB = UI.GetParticipantRatingChange(b)

        if changeA == nil and changeB == nil then
            return (a.name or "") < (b.name or "")
        end
        if changeA == nil then
            return false
        end
        if changeB == nil then
            return true
        end
        if changeA == changeB then
            return (a.name or "") < (b.name or "")
        end

        return changeA > changeB
    end)

    return sorted
end

--- Returns true when match detail should split players into friendly/enemy teams.
--- @param bracket string|nil
--- @return boolean
function UI.UsesTeamSplitLayout(bracket)
    return bracket ~= PVL.BRACKETS.SHUFFLE
end

--- Returns all roster participants sorted by CR change.
--- @param matchRecord table
--- @return table[]
function UI.GetAllMatchParticipants(matchRecord)
    local participants = {}

    for _, participant in ipairs(matchRecord.roster or {}) do
        table.insert(participants, participant)
    end

    return UI.SortParticipantsByRatingChange(participants)
end

--- Returns roster participants grouped and sorted for one team label.
--- @param matchRecord table
--- @param friendly boolean
--- @return table[]
function UI.GetMatchTeamParticipants(matchRecord, friendly)
    if not UI.UsesTeamSplitLayout(matchRecord.bracket) then
        return friendly and UI.GetAllMatchParticipants(matchRecord) or {}
    end

    local participants = {}

    for _, participant in ipairs(matchRecord.roster or {}) do
        if UI.IsFriendlyParticipant(participant, matchRecord) == friendly then
            table.insert(participants, participant)
        end
    end

    return UI.SortParticipantsByRatingChange(participants)
end

--- Sorts roster participants by one selected combat stat descending.
--- @param participants table[]
--- @param combatSummary table|nil
--- @param statDef table
--- @return table[]
function UI.SortParticipantsByCombatStat(participants, combatSummary, statDef)
    local sorted = {}
    for index, participant in ipairs(participants) do
        sorted[index] = participant
    end

    table.sort(sorted, function(a, b)
        local rowA = UI.GetCombatRowForParticipant(combatSummary, a)
        local rowB = UI.GetCombatRowForParticipant(combatSummary, b)
        local valueA = UI.GetCombatStatValue(rowA, statDef, a)
        local valueB = UI.GetCombatStatValue(rowB, statDef, b)

        if valueA == valueB then
            return (a.name or "") < (b.name or "")
        end

        return valueA > valueB
    end)

    return sorted
end

--- Appends one team combat analysis block for a single selected stat.
--- @param lines string[]
--- @param title string
--- @param participants table[]
--- @param combatSummary table
--- @param statDef table
function UI.AppendMatchCombatTeamBlock(lines, title, participants, combatSummary, statDef)
    table.insert(lines, Format.SectionLabel(title))
    table.insert(lines, Format.Divider(300))

    if #participants == 0 then
        table.insert(lines, Format.Muted("No players recorded."))
        table.insert(lines, "")
        return
    end

    table.insert(lines, string.format("%s  %s", Format.Muted("Player"), Format.Muted(statDef.label)))

    local sortedParticipants = UI.SortParticipantsByCombatStat(participants, combatSummary, statDef)
    for _, participant in ipairs(sortedParticipants) do
        local nameText = participant.name or "Unknown"
        if participant.isLocalPlayer then
            nameText = Format.Colorize("FF66CCFF", nameText)
        end

        local combatRow = UI.GetCombatRowForParticipant(combatSummary, participant)
        local specText = UI.FormatParticipantSpec(participant)
        local statValue = UI.GetCombatStatValue(combatRow, statDef, participant)
        table.insert(lines, string.format(
            "  %s  %s",
            nameText,
            UI.FormatCombatStatValue(statValue, statDef)
        ))
        table.insert(lines, string.format("    %s", specText))
    end

    table.insert(lines, "")
end

--- Builds match summary text for the bottom-left panel.
--- @param matchRecord table|nil
--- @return string
function UI.BuildMatchDetailText(matchRecord)
    if not matchRecord then
        return Format.Muted("No matches recorded for this bracket yet.")
    end

    local lines = {}
    local bracketName = PVL.BRACKET_NAMES[matchRecord.bracket] or matchRecord.bracket or "PvP"
    local resultLabel = matchRecord.won == true and Format.Colorize(Format.COLORS.POSITIVE, "Victory")
        or (matchRecord.won == false and Format.Colorize(Format.COLORS.NEGATIVE, "Defeat") or Format.Muted("Result unknown"))
    local timestampText = PVL.CrHistory and PVL.CrHistory.FormatTimestamp(matchRecord.timestamp) or "--"
    local mapLabel = UI.GetMatchMapLabel(matchRecord)
    local combatSummary = matchRecord.combatSummary

    table.insert(lines, string.format("%s  %s", resultLabel, Format.Header(bracketName)))
    table.insert(lines, string.format("%s  ·  %s", Format.Muted(timestampText), Format.Muted(mapLabel)))

    if combatSummary and combatSummary.duration then
        local minutes = math.floor(combatSummary.duration / 60)
        local seconds = combatSummary.duration % 60
        table.insert(lines, Format.StatLine("Duration", string.format("%d:%02d", minutes, seconds)))
    end

    table.insert(lines, "")
    table.insert(lines, Format.StatLine(
        "Your CR",
        string.format(
            "%s -> %s  (%s)",
            Format.Rating(matchRecord.playerCRBefore),
            Format.Rating(matchRecord.playerCRAfter),
            PVL.CrHistory and PVL.CrHistory.FormatDelta(
                matchRecord.playerCRBefore and matchRecord.playerCRAfter
                    and (matchRecord.playerCRAfter - matchRecord.playerCRBefore)
                    or nil
            ) or "--"
        )
    ))

    if matchRecord.playerMMRAfter then
        local mmrLabel = matchRecord.playerMMRKind == "team" and "Team MMR" or "Your MMR"
        table.insert(lines, Format.StatLine(mmrLabel, Format.Rating(matchRecord.playerMMRAfter)))
    end

    table.insert(lines, "")
    if UI.UsesTeamSplitLayout(matchRecord.bracket) then
        UI.AppendMatchRosterBlock(lines, "Your team", UI.GetMatchTeamParticipants(matchRecord, true))
        UI.AppendMatchRosterBlock(lines, "Enemy team", UI.GetMatchTeamParticipants(matchRecord, false))
    else
        UI.AppendMatchRosterBlock(lines, "Players", UI.GetAllMatchParticipants(matchRecord))
    end

    if not combatSummary and not UI.MatchHasStoredCombatTotals(matchRecord) then
        table.insert(lines, Format.Muted("Combat totals unavailable for this saved match."))
        table.insert(lines, Format.Muted("New games after /reload will record full combat stats."))
    end

    return table.concat(lines, "\n")
end

--- Builds combat analysis text for the bottom-right panel.
--- @param matchRecord table|nil
--- @param statId string|nil
--- @return string
function UI.BuildMatchCombatAnalysisText(matchRecord, statId)
    if not matchRecord then
        return Format.Muted("No matches recorded for this bracket yet.")
    end

    local combatSummary = matchRecord.combatSummary
    if not combatSummary then
        return table.concat({
            Format.Muted("No combat stats were recorded for this match."),
            Format.Muted("Enable Record match combat stats in addon settings, then play new rated games."),
        }, "\n")
    end

    local statDef = UI.GetCombatStatDefinition(statId or UI.GetSelectedCombatStat())
    local lines = {}

    if combatSummary.duration then
        local minutes = math.floor(combatSummary.duration / 60)
        local seconds = combatSummary.duration % 60
        table.insert(lines, Format.StatLine("Duration", string.format("%d:%02d", minutes, seconds)))
        table.insert(lines, "")
    end

    UI.AppendMatchCombatTeamBlock(
        lines,
        "Your team",
        UI.GetMatchTeamParticipants(matchRecord, true),
        combatSummary,
        statDef
    )
    UI.AppendMatchCombatTeamBlock(
        lines,
        "Enemy team",
        UI.GetMatchTeamParticipants(matchRecord, false),
        combatSummary,
        statDef
    )

    if #(combatSummary.killEvents or {}) > 0 then
        table.insert(lines, Format.SectionLabel("Kill order"))
        table.insert(lines, Format.Divider(300))

        for _, killEvent in ipairs(combatSummary.killEvents) do
            local elapsedMinutes = math.floor((killEvent.elapsed or 0) / 60)
            local elapsedSeconds = math.floor((killEvent.elapsed or 0) % 60)
            table.insert(lines, string.format(
                "  %d:%02d  %s",
                elapsedMinutes,
                elapsedSeconds,
                killEvent.victim or "Unknown"
            ))
        end
    end

    return table.concat(lines, "\n")
end
