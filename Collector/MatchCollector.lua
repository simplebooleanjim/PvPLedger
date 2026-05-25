--- Captures Blitz match context from PvP events and scoreboard APIs.
--- @class PvPLedger
local PVL = PvPLedger

PVL.MatchCollector = PVL.MatchCollector or {}
local MatchCollector = PVL.MatchCollector

MatchCollector.frame = MatchCollector.frame or nil
MatchCollector.activeMatch = MatchCollector.activeMatch or nil

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

    if bracket == PVL.BRACKETS.BLITZ then
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
        return
    end

    MatchCollector.activeMatch = {
        bracket = bracket,
        startedAt = time(),
        mapID = C_Map.GetBestMapForUnit("player"),
    }

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

    return {
        name = name,
        realm = realm,
        class = classToken,
        spec = specKey,
        faction = scoreInfo.faction,
        rating = scoreInfo.rating,
        ratingChange = scoreInfo.ratingChange,
        prematchMMR = scoreInfo.prematchMMR,
        postmatchMMR = scoreInfo.postmatchMMR,
        mmrChange = scoreInfo.mmrChange,
        isLocalPlayer = scoreInfo.guid and UnitGUID("player") == scoreInfo.guid or false,
    }
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

--- Persists a completed match and updates character rating context.
function MatchCollector.OnMatchComplete()
    local db = PVL.GetDB()
    if not db or not db.settings.enabled then
        return
    end

    local bracket = MatchCollector.GetCurrentBracket()
    if not MatchCollector.ShouldCollectBracket(bracket) then
        MatchCollector.activeMatch = nil
        return
    end

    local roster = MatchCollector.CollectScoreboard()
    local localPlayer = MatchCollector.FindLocalParticipant(roster)
    local charDb = PVL.GetCharDB()

    if localPlayer then
        charDb.lastBlitzCR = localPlayer.rating
        charDb.lastBlitzMMR = localPlayer.postmatchMMR or localPlayer.prematchMMR
    end

    local matchRecord = {
        matchId = MatchCollector.BuildMatchId(bracket, roster),
        bracket = bracket,
        timestamp = time(),
        mapID = MatchCollector.activeMatch and MatchCollector.activeMatch.mapID or C_Map.GetBestMapForUnit("player"),
        won = MatchCollector.DidLocalPlayerWin(localPlayer),
        playerCRBefore = localPlayer and localPlayer.rating and (localPlayer.rating - (localPlayer.ratingChange or 0)) or nil,
        playerCRAfter = localPlayer and localPlayer.rating or nil,
        playerMMRBefore = localPlayer and localPlayer.prematchMMR or nil,
        playerMMRAfter = localPlayer and localPlayer.postmatchMMR or nil,
        roster = roster,
    }

    PVL.StoreMatch(matchRecord)
    db.meta.lastMatchAt = matchRecord.timestamp

    MatchCollector.activeMatch = nil
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
    if not localPlayer or localPlayer.ratingChange == nil then
        return nil
    end

    return localPlayer.ratingChange > 0
end
