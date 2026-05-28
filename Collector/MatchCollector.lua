--- Captures PvP match context from scoreboard APIs at match end.
--- @class PvPLedger
local PVL = PvPLedger

PVL.MatchCollector = PVL.MatchCollector or {}
local MatchCollector = PVL.MatchCollector

MatchCollector.frame = MatchCollector.frame or nil
MatchCollector.activeMatch = MatchCollector.activeMatch or nil
MatchCollector.pendingComplete = MatchCollector.pendingComplete or nil

local COMPLETE_RETRY_SECONDS = 0.25
local COMPLETE_MAX_ATTEMPTS = 12

--- Returns true when an MMR reading looks populated by the client.
--- Arena often returns 0 for hidden personal MMR fields instead of nil.
--- @param value number|nil
--- @return boolean
function MatchCollector.IsValidMmr(value)
    return type(value) == "number" and value > 0
end

--- Returns a usable number when the client allows addon access.
--- @param value any
--- @return number|nil
function MatchCollector.GetAccessibleNumber(value)
    if value == nil then
        return nil
    end

    if issecretvalue and issecretvalue(value) then
        if canaccessvalue and not canaccessvalue(value) then
            return nil
        end
    end

    return tonumber(value)
end

--- Initializes the event-driven match collector.
function MatchCollector.Init()
    if MatchCollector.frame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PVP_MATCH_ACTIVE")
    frame:RegisterEvent("PVP_MATCH_COMPLETE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event, ...)
        MatchCollector.OnEvent(event, ...)
    end)

    MatchCollector.frame = frame
end

--- Dispatches addon events to collector handlers.
--- @param event string
function MatchCollector.OnEvent(event)
    if event == "PLAYER_LOGIN" then
        PVL.LoadImportedSnapshotFromPack()
    elseif event == "PVP_MATCH_ACTIVE" then
        MatchCollector.OnMatchActive()
    elseif event == "PVP_MATCH_COMPLETE" then
        MatchCollector.OnMatchComplete()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if C_PvP and C_PvP.IsMatchActive and C_PvP.IsMatchActive() then
            MatchCollector.OnMatchActive()
        end
    end
end

--- Returns the current bracket identifier, or nil when unsupported.
--- @return string|nil
function MatchCollector.GetCurrentBracket()
    if C_PvP.IsBrawlSoloRBG and C_PvP.IsBrawlSoloRBG() then
        return PVL.BRACKETS.BLITZ
    end

    if C_PvP.IsSoloRBG and C_PvP.IsSoloRBG() then
        return PVL.BRACKETS.BLITZ
    end

    if C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() then
        return PVL.BRACKETS.SHUFFLE
    end

    if C_PvP.IsRatedArena and C_PvP.IsRatedArena() then
        if GetBattlefieldArenaFaction and C_PvP.GetTeamInfo then
            local factionIndex = GetBattlefieldArenaFaction()
            local teamInfo = C_PvP.GetTeamInfo(factionIndex)
            local teamSize = teamInfo and teamInfo.size or 0
            if teamSize > 0 and teamSize <= 2 then
                return PVL.BRACKETS.ARENA_2V2
            end
        end

        return PVL.BRACKETS.ARENA_3V3
    end

    if C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground() then
        return PVL.BRACKETS.RBG
    end

    return nil
end

--- Returns whether the current bracket should be collected based on settings.
--- @param bracket string|nil
--- @return boolean
function MatchCollector.ShouldCollectBracket(bracket)
    if not bracket then
        return false
    end

    if bracket == PVL.BRACKETS.BLITZ
        or bracket == PVL.BRACKETS.SHUFFLE
        or bracket == PVL.BRACKETS.RBG
        or bracket == PVL.BRACKETS.ARENA_2V2
        or bracket == PVL.BRACKETS.ARENA_3V3 then
        return true
    end

    local db = PVL.GetDB()
    return db and db.settings.collectNonBlitz or false
end

--- Begins tracking a newly active match shell.
function MatchCollector.OnMatchActive()
    local db = PVL.GetDB()
    if not db or not db.settings.enabled then
        return
    end

    local bracket = MatchCollector.GetCurrentBracket()
    if not MatchCollector.ShouldCollectBracket(bracket) then
        MatchCollector.activeMatch = nil
        if PVL.CombatLogCollector then
            PVL.CombatLogCollector.StopMatch()
        end
        return
    end

    MatchCollector.pendingComplete = nil
    local startCr = nil
    if PVL.RatedInfo then
        PVL.RatedInfo.RefreshAll()
        startCr = MatchCollector.GetAccessibleNumber(PVL.RatedInfo.GetCurrentRating(bracket))
    end

    MatchCollector.activeMatch = {
        bracket = bracket,
        startedAt = time(),
        mapID = C_Map.GetBestMapForUnit("player"),
        playerCrBefore = startCr,
    }

    if PVL.CombatLogCollector then
        PVL.CombatLogCollector.StartMatch(MatchCollector.activeMatch)
    end

    if db.settings.collectSpecs and PVL.InspectQueue then
        PVL.InspectQueue.EnqueueMatchRoster(function(participant)
            MatchCollector.MergeLiveSpec(participant)
        end)
    end
end

--- Merges a live inspect result into the active match cache by player name.
--- @param participant table
function MatchCollector.MergeLiveSpec(participant)
    if not MatchCollector.activeMatch or not participant or not participant.name then
        return
    end

    MatchCollector.activeMatch.liveSpecs = MatchCollector.activeMatch.liveSpecs or {}
    MatchCollector.activeMatch.liveSpecs[participant.name] = participant.spec
end

--- Builds one participant row from scoreboard data.
--- @param scoreInfo table
--- @return table|nil
function MatchCollector.BuildParticipantFromScore(scoreInfo)
    if not scoreInfo or not scoreInfo.name then
        return nil
    end

    local name, realm = Ambiguate(scoreInfo.name, "none"):match("^(.-)%-(.+)$")
    if not name then
        name = Ambiguate(scoreInfo.name, "none")
        realm = nil
    end

    local classToken = scoreInfo.classToken
    local specKey = PVL.NormalizeSpecKey(classToken, scoreInfo.talentSpec)
    local listedPlayer = PVL.LookupListedPlayer(name, realm)

    local prematchMMR = MatchCollector.GetAccessibleNumber(scoreInfo.prematchMMR)
    local postmatchMMR = MatchCollector.GetAccessibleNumber(scoreInfo.postmatchMMR)
    local mmrChange = MatchCollector.GetAccessibleNumber(scoreInfo.mmrChange)

    if not MatchCollector.IsValidMmr(postmatchMMR) and MatchCollector.IsValidMmr(prematchMMR) and mmrChange then
        postmatchMMR = prematchMMR + mmrChange
    elseif not MatchCollector.IsValidMmr(prematchMMR) and MatchCollector.IsValidMmr(postmatchMMR) and mmrChange then
        prematchMMR = postmatchMMR - mmrChange
    end

    if not MatchCollector.IsValidMmr(postmatchMMR) then
        postmatchMMR = nil
    end
    if not MatchCollector.IsValidMmr(prematchMMR) then
        prematchMMR = nil
    end

    return {
        name = name,
        realm = realm,
        class = classToken,
        spec = specKey,
        faction = scoreInfo.faction,
        rating = MatchCollector.GetAccessibleNumber(scoreInfo.rating),
        ratingChange = MatchCollector.GetAccessibleNumber(scoreInfo.ratingChange),
        prematchMMR = prematchMMR,
        postmatchMMR = postmatchMMR,
        mmrChange = mmrChange,
        isLocalPlayer = MatchCollector.IsLocalPlayerScore(scoreInfo),
        guid = scoreInfo.guid,
        damageDone = MatchCollector.GetAccessibleNumber(scoreInfo.damageDone),
        healingDone = MatchCollector.GetAccessibleNumber(scoreInfo.healingDone),
        listedRating = listedPlayer and listedPlayer.rating or nil,
        listedRank = listedPlayer and listedPlayer.rank or nil,
    }
end

--- Returns true when one scoreboard row belongs to the local player.
--- @param scoreInfo table|nil
--- @return boolean
function MatchCollector.IsLocalPlayerScore(scoreInfo)
    if not scoreInfo then
        return false
    end

    if scoreInfo.guid and UnitGUID("player") == scoreInfo.guid then
        return true
    end

    if not scoreInfo.name or not UnitFullName then
        return false
    end

    local playerName, playerRealm = UnitFullName("player")
    if not playerName then
        return false
    end

    local scoreName = Ambiguate(scoreInfo.name, "none")
    local playerFullName = playerRealm and (playerName .. "-" .. playerRealm) or playerName
    if scoreName == Ambiguate(playerFullName, "none") or scoreName == playerName then
        return true
    end

    return false
end

--- Returns the fixed team size for one bracket, or nil for non-team modes like Shuffle.
--- @param bracket string|nil
--- @return number|nil
function MatchCollector.GetBracketTeamSize(bracket)
    if not bracket or not PVL.TEAM_SIZE_BY_BRACKET then
        return nil
    end

    return PVL.TEAM_SIZE_BY_BRACKET[bracket]
end

--- Returns true when one bracket uses fixed-size constraint team assignment.
--- @param bracket string|nil
--- @return boolean
function MatchCollector.UsesConstraintTeamSplit(bracket)
    return MatchCollector.GetBracketTeamSize(bracket) ~= nil
end

--- Returns true when arena-style exact rating deltas should be used as a fallback.
--- @param bracket string|nil
--- @return boolean
function MatchCollector.UsesExactRatingTeamSplit(bracket)
    return bracket == PVL.BRACKETS.ARENA_2V2 or bracket == PVL.BRACKETS.ARENA_3V3
end

--- Normalizes scoreboard faction values to Horde/Alliance labels.
--- @param faction number|string|nil
--- @return string|nil
function MatchCollector.NormalizeScoreboardFaction(faction)
    if faction == nil then
        return nil
    end

    if type(faction) == "string" then
        if faction == "Horde" or faction == "Alliance" then
            return faction
        end
        return nil
    end

    if faction == 0 then
        return "Horde"
    end

    if faction == 1 then
        return "Alliance"
    end

    return nil
end

--- Returns the live combat-log team row for one participant when available.
--- @param participant table
--- @param combatPlayers table|nil
--- @return table|nil
function MatchCollector.GetCombatLogTeamRow(participant, combatPlayers)
    if type(combatPlayers) ~= "table" or type(participant) ~= "table" then
        return nil
    end

    if participant.guid and combatPlayers[participant.guid] then
        return combatPlayers[participant.guid]
    end

    for _, row in pairs(combatPlayers) do
        if participant.name and row.name == participant.name then
            return row
        end
    end

    return nil
end

--- Returns the stored combat summary team for one participant.
--- @param participant table
--- @param matchRecord table|nil
--- @return string|nil
function MatchCollector.GetStoredCombatSummaryTeam(participant, matchRecord)
    if type(matchRecord) ~= "table" or type(participant) ~= "table" then
        return nil
    end

    local combatSummary = matchRecord.combatSummary
    if type(combatSummary) ~= "table" then
        return nil
    end

    for _, row in ipairs(combatSummary.players or {}) do
        if participant.guid and row.guid == participant.guid then
            return row.team
        end
        if participant.name and row.name == participant.name then
            return row.team
        end
    end

    return nil
end

--- Returns the rating-change bucket for one participant.
--- @param participant table|nil
--- @return string gain|loss|neutral|unknown
function MatchCollector.GetRatingChangeBucket(participant)
    if type(participant) ~= "table" then
        return "unknown"
    end

    local change = participant.ratingChange
    if change == nil then
        return "unknown"
    end
    if change > 0 then
        return "gain"
    end
    if change < 0 then
        return "loss"
    end

    return "neutral"
end

--- Returns true when one participant appears in one roster list.
--- @param participants table[]
--- @param target table|nil
--- @return boolean
function MatchCollector.RosterContainsParticipant(participants, target)
    if type(target) ~= "table" then
        return false
    end

    for _, participant in ipairs(participants or {}) do
        if target.guid and participant.guid == target.guid then
            return true
        end
        if target.name and participant.name == target.name then
            return true
        end
    end

    return false
end

--- Removes one participant from a list when present.
--- @param participants table[]
--- @param target table|nil
--- @return table|nil removed
function MatchCollector.RemoveParticipantFromList(participants, target)
    if type(target) ~= "table" then
        return nil
    end

    for index, participant in ipairs(participants or {}) do
        if target.guid and participant.guid == target.guid then
            return table.remove(participants, index)
        end
        if target.name and participant.name == target.name then
            return table.remove(participants, index)
        end
    end

    return nil
end

--- Resolves whether the local player won when rating change alone is inconclusive.
--- @param localPlayer table|nil
--- @return boolean|nil
function MatchCollector.ResolveLocalMatchWon(localPlayer)
    if localPlayer and localPlayer.ratingChange ~= nil then
        if localPlayer.ratingChange > 0 then
            return true
        end
        if localPlayer.ratingChange < 0 then
            return false
        end
    end

    if GetBattlefieldWinner and GetBattlefieldArenaFaction then
        local winner = GetBattlefieldWinner()
        local playerTeam = GetBattlefieldArenaFaction()
        if winner ~= nil and playerTeam ~= nil then
            return winner == playerTeam
        end
    end

    return nil
end

--- Assigns teams using fixed roster size and rating-change buckets.
--- Gainers form the winning side, losers form the losing side, and neutral (+0) players
--- fill whichever side still needs players to reach the bracket team size.
--- @param roster table[]
--- @param localPlayer table|nil
--- @param won boolean|nil
--- @param bracket string|nil
function MatchCollector.AssignTeamsByConstraint(roster, localPlayer, won, bracket)
    local teamSize = MatchCollector.GetBracketTeamSize(bracket)
    if not teamSize then
        return
    end

    local gainers = {}
    local losers = {}
    local neutralPool = {}

    for _, participant in ipairs(roster or {}) do
        local bucket = MatchCollector.GetRatingChangeBucket(participant)
        if bucket == "gain" then
            table.insert(gainers, participant)
        elseif bucket == "loss" then
            table.insert(losers, participant)
        else
            table.insert(neutralPool, participant)
        end
    end

    local winningSide = {}
    local losingSide = {}
    for _, participant in ipairs(gainers) do
        table.insert(winningSide, participant)
    end
    for _, participant in ipairs(losers) do
        table.insert(losingSide, participant)
    end

    if won == nil and localPlayer then
        won = MatchCollector.ResolveLocalMatchWon(localPlayer)
    end

    if localPlayer and MatchCollector.GetRatingChangeBucket(localPlayer) == "neutral" then
        MatchCollector.RemoveParticipantFromList(neutralPool, localPlayer)
        if won == true then
            table.insert(winningSide, localPlayer)
        elseif won == false then
            table.insert(losingSide, localPlayer)
        else
            table.insert(neutralPool, localPlayer)
        end
    end

    local function fillSide(side, needed)
        while needed > 0 and #neutralPool > 0 do
            table.insert(side, table.remove(neutralPool, 1))
            needed = needed - 1
        end
    end

    fillSide(losingSide, math.max(0, teamSize - #losingSide))
    fillSide(winningSide, math.max(0, teamSize - #winningSide))

    while #neutralPool > 0 do
        if #losingSide <= #winningSide then
            table.insert(losingSide, table.remove(neutralPool, 1))
        else
            table.insert(winningSide, table.remove(neutralPool, 1))
        end
    end

    local friendlySide
    local enemySide
    if won == true or (won == nil and localPlayer and MatchCollector.GetRatingChangeBucket(localPlayer) == "gain") then
        friendlySide = winningSide
        enemySide = losingSide
    elseif won == false or (won == nil and localPlayer and MatchCollector.GetRatingChangeBucket(localPlayer) == "loss") then
        friendlySide = losingSide
        enemySide = winningSide
    elseif localPlayer and MatchCollector.RosterContainsParticipant(losingSide, localPlayer) then
        friendlySide = losingSide
        enemySide = winningSide
    elseif localPlayer and MatchCollector.RosterContainsParticipant(winningSide, localPlayer) then
        friendlySide = winningSide
        enemySide = losingSide
    else
        friendlySide = winningSide
        enemySide = losingSide
    end

    for _, participant in ipairs(friendlySide) do
        participant.team = "friendly"
    end
    for _, participant in ipairs(enemySide) do
        participant.team = "enemy"
    end

    for _, participant in ipairs(roster or {}) do
        if participant.isLocalPlayer then
            participant.team = "friendly"
        elseif participant.team ~= "friendly" and participant.team ~= "enemy" then
            participant.team = MatchCollector.InferTeamFromRatingChange(participant, localPlayer, bracket)
                or MatchCollector.InferTeamFromFaction(participant, bracket)
                or "enemy"
        end
    end
end

--- Infers team membership from rating change.
--- Arena brackets use exact deltas as a fallback; larger team brackets use win/loss sign.
--- @param participant table
--- @param localPlayer table|nil
--- @param bracket string|nil
--- @return string|nil
function MatchCollector.InferTeamFromRatingChange(participant, localPlayer, bracket)
    if type(participant) ~= "table" or type(localPlayer) ~= "table" then
        return nil
    end

    if participant.isLocalPlayer then
        return "friendly"
    end

    local localChange = localPlayer.ratingChange
    local participantChange = participant.ratingChange
    if localChange == nil or participantChange == nil then
        return nil
    end

    if MatchCollector.UsesExactRatingTeamSplit(bracket) then
        if participantChange == localChange then
            return "friendly"
        end

        if participantChange == -localChange then
            return "enemy"
        end

        return nil
    end

    if localChange == 0 and participantChange == 0 then
        return "friendly"
    end

    if localChange > 0 and participantChange > 0 then
        return "friendly"
    end

    if localChange < 0 and participantChange < 0 then
        return "friendly"
    end

    if localChange > 0 and participantChange < 0 then
        return "enemy"
    end

    if localChange < 0 and participantChange > 0 then
        return "enemy"
    end

    return nil
end

--- Infers team membership from BG faction when other signals are unavailable.
--- @param participant table
--- @param bracket string|nil
--- @return string|nil
function MatchCollector.InferTeamFromFaction(participant, bracket)
    if bracket ~= PVL.BRACKETS.RBG and bracket ~= PVL.BRACKETS.BLITZ then
        return nil
    end

    local participantFaction = MatchCollector.NormalizeScoreboardFaction(participant.faction)
    local playerFaction = UnitFactionGroup and UnitFactionGroup("player")
    if not participantFaction or not playerFaction then
        return nil
    end

    return participantFaction == playerFaction and "friendly" or "enemy"
end

--- Assigns friendly/enemy team labels to all roster rows before saving a match.
--- @param roster table[]
--- @param localPlayer table|nil
--- @param bracket string|nil
--- @param won boolean|nil
function MatchCollector.AssignRosterTeams(roster, localPlayer, bracket, won)
    if bracket == PVL.BRACKETS.SHUFFLE then
        return
    end

    if MatchCollector.UsesConstraintTeamSplit(bracket) then
        MatchCollector.AssignTeamsByConstraint(roster, localPlayer, won, bracket)
    end
end

--- Returns the resolved team for one participant, including legacy match fallbacks.
--- @param participant table
--- @param roster table[]|nil
--- @param localPlayer table|nil
--- @param matchRecord table|nil
--- @return string|nil
function MatchCollector.GetParticipantTeam(participant, roster, localPlayer, matchRecord)
    if type(participant) ~= "table" then
        return nil
    end

    if participant.isLocalPlayer then
        return "friendly"
    end

    roster = roster or (matchRecord and matchRecord.roster) or {}
    localPlayer = localPlayer or MatchCollector.FindLocalParticipant(roster)
    local bracket = matchRecord and matchRecord.bracket or nil

    if MatchCollector.UsesConstraintTeamSplit(bracket) then
        if type(matchRecord) == "table" then
            if not matchRecord._teamsResolved then
                MatchCollector.AssignTeamsByConstraint(
                    roster,
                    localPlayer,
                    matchRecord.won,
                    bracket
                )
                matchRecord._teamsResolved = true
            end
        else
            MatchCollector.AssignTeamsByConstraint(roster, localPlayer, nil, bracket)
        end
        return participant.team
    end

    if participant.team == "friendly" or participant.team == "enemy" then
        return participant.team
    end

    local ratingTeam = MatchCollector.InferTeamFromRatingChange(participant, localPlayer, bracket)
    if ratingTeam then
        return ratingTeam
    end

    local storedTeam = MatchCollector.GetStoredCombatSummaryTeam(participant, matchRecord)
    if storedTeam == "friendly" or storedTeam == "enemy" then
        return storedTeam
    end

    return MatchCollector.InferTeamFromFaction(participant, bracket)
end

--- Returns the local player's scoreboard row when available.
--- @return table|nil
function MatchCollector.CollectLocalPlayerScore()
    local playerGuid = UnitGUID("player")
    if C_PvP.GetScoreInfoByPlayerGuid and playerGuid then
        local scoreInfo = C_PvP.GetScoreInfoByPlayerGuid(playerGuid)
        local participant = MatchCollector.BuildParticipantFromScore(scoreInfo)
        if participant then
            participant.isLocalPlayer = true
            return participant
        end
    end

    for _, participant in ipairs(MatchCollector.CollectScoreboard()) do
        if participant.isLocalPlayer then
            return participant
        end
    end

    return nil
end

--- Returns team average MMR shown on the post-game screen for arena/BG modes.
--- @return number|nil
function MatchCollector.CollectFriendlyTeamMmr()
    if not GetBattlefieldArenaFaction or not C_PvP.GetTeamInfo then
        return nil
    end

    local factionIndex = GetBattlefieldArenaFaction()
    local teamInfo = C_PvP.GetTeamInfo(factionIndex)
    if not teamInfo then
        return nil
    end

    return MatchCollector.GetAccessibleNumber(teamInfo.ratingMMR)
end

--- Reads the full scoreboard and returns participant rows.
--- @return table[]
function MatchCollector.CollectScoreboard()
    local roster = {}
    local scoreCount = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0

    for index = 1, scoreCount do
        local scoreInfo = C_PvP.GetScoreInfo(index)
        local participant = MatchCollector.BuildParticipantFromScore(scoreInfo)
        if participant then
            if MatchCollector.activeMatch and MatchCollector.activeMatch.liveSpecs then
                participant.spec = participant.spec or MatchCollector.activeMatch.liveSpecs[participant.name]
            end
            table.insert(roster, participant)
        end
    end

    return roster
end

--- Finds the local player's scoreboard row.
--- @param roster table[]
--- @return table|nil
function MatchCollector.FindLocalParticipant(roster)
    for _, participant in ipairs(roster) do
        if participant.isLocalPlayer then
            return participant
        end
    end

    return nil
end

--- Resolves the MMR value shown on the post-game score screen for one match.
--- Arena, RBG, and Blitz expose team average MMR; Shuffle exposes personal MMR.
--- @param localPlayer table|nil
--- @param bracket string|nil
--- @return number|nil mmrAfter, number|nil mmrBefore, string|nil mmrKind
function MatchCollector.ResolveObservedMmr(localPlayer, bracket)
    if PVL.IsTeamObservedMmrBracket(bracket) then
        local teamMmr = MatchCollector.CollectFriendlyTeamMmr()
        if MatchCollector.IsValidMmr(teamMmr) then
            return teamMmr, teamMmr, "team"
        end

        return nil, nil, nil
    end

    local personalAfter = nil
    local personalBefore = nil

    if localPlayer then
        if MatchCollector.IsValidMmr(localPlayer.postmatchMMR) then
            personalAfter = localPlayer.postmatchMMR
        elseif MatchCollector.IsValidMmr(localPlayer.prematchMMR) then
            personalAfter = localPlayer.prematchMMR
        end

        if MatchCollector.IsValidMmr(localPlayer.prematchMMR) then
            personalBefore = localPlayer.prematchMMR
        end
    end

    if personalAfter then
        return personalAfter, personalBefore, "personal"
    end

    return nil, nil, nil
end

--- Ensures the local player's scoreboard row is present in one roster snapshot.
--- @param roster table[]
--- @param localPlayer table|nil
function MatchCollector.MergeLocalPlayerIntoRoster(roster, localPlayer)
    if not localPlayer then
        return
    end

    for _, participant in ipairs(roster or {}) do
        if localPlayer.guid and participant.guid == localPlayer.guid then
            participant.isLocalPlayer = true
            participant.team = "friendly"
            return
        end

        if localPlayer.name and participant.name == localPlayer.name then
            participant.isLocalPlayer = true
            participant.team = "friendly"
            return
        end
    end

    localPlayer.isLocalPlayer = true
    localPlayer.team = "friendly"
    table.insert(roster, localPlayer)
end

--- Returns true when scoreboard data looks ready to finalize.
--- @param localPlayer table|nil
--- @param roster table[]
--- @param bracket string|nil
--- @param attempt number|nil
--- @return boolean
function MatchCollector.ScoreboardLooksReady(localPlayer, roster, bracket, attempt)
    local teamSize = MatchCollector.GetBracketTeamSize(bracket)
    if teamSize then
        local expectedPlayers = teamSize * 2
        if #roster >= expectedPlayers then
            return true
        end

        if attempt and attempt >= COMPLETE_MAX_ATTEMPTS then
            return localPlayer ~= nil or #roster > 0
        end

        if localPlayer and localPlayer.rating and #roster >= teamSize then
            return true
        end

        return false
    end

    if localPlayer and localPlayer.rating then
        return true
    end

    if #roster > 0 then
        return true
    end

    if C_PvP.IsMatchComplete and C_PvP.IsMatchComplete() then
        return MatchCollector.CollectLocalPlayerScore() ~= nil
    end

    return false
end

--- Schedules the next attempt to read post-match scoreboard data.
--- @param attempt number
function MatchCollector.ScheduleCompleteAttempt(attempt)
    C_Timer.After(COMPLETE_RETRY_SECONDS, function()
        MatchCollector.TryFinalizeMatchComplete(attempt)
    end)
end

--- Starts deferred post-match collection when score data may not be ready yet.
function MatchCollector.OnMatchComplete()
    local db = PVL.GetDB()
    if not db or not db.settings.enabled then
        return
    end

    local bracket = MatchCollector.activeMatch and MatchCollector.activeMatch.bracket or MatchCollector.GetCurrentBracket()
    if not MatchCollector.ShouldCollectBracket(bracket) then
        MatchCollector.activeMatch = nil
        MatchCollector.pendingComplete = nil
        return
    end

    MatchCollector.pendingComplete = {
        bracket = bracket,
        playerCrBefore = MatchCollector.activeMatch and MatchCollector.activeMatch.playerCrBefore or nil,
    }
    MatchCollector.ScheduleCompleteAttempt(1)
end

--- Attempts to read scoreboard data and finalize the match record.
--- @param attempt number
function MatchCollector.TryFinalizeMatchComplete(attempt)
    local pending = MatchCollector.pendingComplete
    if not pending then
        return
    end

    local roster = MatchCollector.CollectScoreboard()
    local localPlayer = MatchCollector.CollectLocalPlayerScore()
    MatchCollector.MergeLocalPlayerIntoRoster(roster, localPlayer)
    localPlayer = MatchCollector.FindLocalParticipant(roster) or localPlayer
    if not MatchCollector.ScoreboardLooksReady(localPlayer, roster, pending.bracket, attempt) and attempt < COMPLETE_MAX_ATTEMPTS then
        MatchCollector.ScheduleCompleteAttempt(attempt + 1)
        return
    end

    MatchCollector.pendingComplete = nil
    MatchCollector.FinalizeMatchComplete(
        pending.bracket,
        roster,
        localPlayer,
        pending.playerCrBefore
    )
end

--- Returns match CR fields using pre-match queue CR plus scoreboard rating change.
--- @param localPlayer table|nil
--- @param bracket string|nil
--- @param matchStartCr number|nil CR captured from the PvP queue menu at match start.
--- @return number|nil crBefore
--- @return number|nil crAfter
function MatchCollector.ResolveMatchCrFields(localPlayer, bracket, matchStartCr)
    if not localPlayer then
        return MatchCollector.GetAccessibleNumber(matchStartCr), MatchCollector.GetAccessibleNumber(matchStartCr)
    end

    local ratingChange = MatchCollector.GetAccessibleNumber(localPlayer.ratingChange)
    local scoreboardAfter = MatchCollector.GetAccessibleNumber(localPlayer.rating)
    local scoreboardBefore = nil
    if scoreboardAfter and ratingChange then
        scoreboardBefore = scoreboardAfter - ratingChange
    end

    local crBefore = MatchCollector.GetAccessibleNumber(matchStartCr)
    local crAfter = nil

    if crBefore and ratingChange then
        crAfter = crBefore + ratingChange
    end

    if PVL.RatedInfo then
        PVL.RatedInfo.RefreshAll()
        local ratedAfter = MatchCollector.GetAccessibleNumber(PVL.RatedInfo.GetCurrentRating(bracket))
        if ratedAfter then
            if crBefore and ratingChange then
                -- Keep start CR + scoreboard delta when we captured a trusted pre-match rating.
                crAfter = crBefore + ratingChange
            else
                crAfter = ratedAfter
                if ratingChange then
                    crBefore = ratedAfter - ratingChange
                end
            end
        end
    end

    if not crBefore then
        crBefore = scoreboardBefore
    end
    if not crAfter then
        crAfter = scoreboardAfter
    end
    if crBefore and ratingChange and not crAfter then
        crAfter = crBefore + ratingChange
    end

    return crBefore, crAfter
end

--- Persists a completed match and updates character rating context.
--- @param bracket string|nil
--- @param roster table[]
--- @param localPlayer table|nil
--- @param matchStartCr number|nil
function MatchCollector.FinalizeMatchComplete(bracket, roster, localPlayer, matchStartCr)
    local db = PVL.GetDB()
    if not db or not db.settings.enabled then
        return
    end

    if not MatchCollector.ShouldCollectBracket(bracket) then
        MatchCollector.activeMatch = nil
        return
    end

    local charDb = PVL.GetCharDB()
    local mmrAfter, mmrBefore, mmrKind = MatchCollector.ResolveObservedMmr(localPlayer, bracket)
    local playerCrBefore, playerCrAfter = MatchCollector.ResolveMatchCrFields(
        localPlayer,
        bracket,
        matchStartCr
    )

    if localPlayer then
        local storedCr = playerCrAfter or localPlayer.rating
        if bracket == PVL.BRACKETS.SHUFFLE then
            charDb.lastShuffleCR = storedCr
            charDb.lastShuffleMMR = mmrAfter
            charDb.lastShuffleMMRKind = mmrKind
        elseif bracket == PVL.BRACKETS.RBG then
            charDb.lastRbgCR = storedCr
            charDb.lastRbgMMR = mmrAfter
            charDb.lastRbgMMRKind = mmrKind
        elseif bracket == PVL.BRACKETS.ARENA_2V2 then
            charDb.lastArena2v2CR = storedCr
            charDb.lastArena2v2MMR = mmrAfter
            charDb.lastArena2v2MMRKind = mmrKind
        elseif bracket == PVL.BRACKETS.ARENA_3V3 then
            charDb.lastArena3v3CR = storedCr
            charDb.lastArena3v3MMR = mmrAfter
            charDb.lastArena3v3MMRKind = mmrKind
        else
            charDb.lastBlitzCR = storedCr
            charDb.lastBlitzMMR = mmrAfter
            charDb.lastBlitzMMRKind = mmrKind
        end
    end

    MatchCollector.AssignRosterTeams(
        roster,
        localPlayer,
        bracket,
        MatchCollector.ResolveLocalMatchWon(localPlayer)
    )

    local combatSummary = nil
    if PVL.CombatLogCollector then
        combatSummary = PVL.CombatLogCollector.BuildSummary(roster)
    end
    if not combatSummary and #roster > 0 and PVL.UI and PVL.UI.ResolveMatchCombatSummary then
        combatSummary = PVL.UI.ResolveMatchCombatSummary({
            roster = roster,
            timestamp = time(),
            bracket = bracket,
        })
    end

    local matchRecord = {
        matchId = MatchCollector.BuildMatchId(bracket, roster),
        bracket = bracket,
        timestamp = time(),
        mapID = MatchCollector.activeMatch and MatchCollector.activeMatch.mapID or C_Map.GetBestMapForUnit("player"),
        won = MatchCollector.ResolveLocalMatchWon(localPlayer),
        playerCRBefore = playerCrBefore,
        playerCRAfter = playerCrAfter,
        playerMMRBefore = mmrBefore,
        playerMMRAfter = mmrAfter,
        playerMMRKind = mmrKind,
        roster = roster,
        combatSummary = combatSummary,
    }

    PVL.StoreMatch(matchRecord)
    db.meta.lastMatchAt = matchRecord.timestamp
    db.meta.lastMatchBracket = bracket

    if PVL.CrHistory then
        PVL.CrHistory.RecordMatch(matchRecord)
    end

    if bracket and db.settings.uiFilters then
        db.settings.uiFilters.bracket = bracket
    end

    if PVL.UI and PVL.UI.GetFilters then
        PVL.UI.GetFilters().selectedMatchId = matchRecord.matchId
    end

    if PVL.QueueMatchExport then
        PVL.QueueMatchExport(matchRecord)
    end

    MatchCollector.activeMatch = nil

    if PVL.RatedInfo then
        PVL.RatedInfo.RequestUpdate()
    end

    if PVL.UI and PVL.UI.Refresh then
        PVL.UI.Refresh()
    end
end

--- Builds a lightweight match identifier from time and participant names.
--- @param bracket string
--- @param roster table[]
--- @return string
function MatchCollector.BuildMatchId(bracket, roster)
    local parts = { bracket or "unknown", tostring(time()) }
    for index = 1, math.min(3, #roster) do
        table.insert(parts, roster[index].name or "?")
    end
    return table.concat(parts, ":")
end

--- Returns true when the local player's rating change indicates a win.
--- @param localPlayer table|nil
--- @return boolean|nil
function MatchCollector.DidLocalPlayerWin(localPlayer)
    return MatchCollector.ResolveLocalMatchWon(localPlayer)
end

--- Prints current scoreboard debug details to chat.
function MatchCollector.PrintScoreDebug()
    local bracket = MatchCollector.activeMatch and MatchCollector.activeMatch.bracket or MatchCollector.GetCurrentBracket()
    local localPlayer = MatchCollector.CollectLocalPlayerScore()
    local teamMmr = MatchCollector.CollectFriendlyTeamMmr()

    print(string.format("|cff66ccffPvPLedger|r score debug: bracket=%s scores=%d matchComplete=%s",
        tostring(bracket),
        GetNumBattlefieldScores and GetNumBattlefieldScores() or 0,
        tostring(C_PvP.IsMatchComplete and C_PvP.IsMatchComplete() or false)
    ))

    if localPlayer then
        print(string.format("  CR=%s (%+d) prematchMMR=%s postmatchMMR=%s mmrChange=%s",
            tostring(localPlayer.rating),
            localPlayer.ratingChange or 0,
            tostring(localPlayer.prematchMMR or "nil"),
            tostring(localPlayer.postmatchMMR or "nil"),
            tostring(localPlayer.mmrChange or "nil")
        ))
    else
        print("  local player score row not available yet")
    end

    if teamMmr then
        print(string.format("  friendly team MMR=%s (used when personal MMR is hidden)", tostring(teamMmr)))
    end

    local mmrAfter, _, mmrKind = MatchCollector.ResolveObservedMmr(localPlayer, bracket)
    if mmrAfter then
        print(string.format("  resolved MMR=%s kind=%s", tostring(mmrAfter), tostring(mmrKind)))
    else
        print("  resolved MMR=nil")
    end
end
