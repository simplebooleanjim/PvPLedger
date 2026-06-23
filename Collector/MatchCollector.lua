--- Captures PvP match context from scoreboard APIs at match end.
--- @class PvPLedger
local PVL = PvPLedger

PVL.MatchCollector = PVL.MatchCollector or {}
local MatchCollector = PVL.MatchCollector

MatchCollector.frame = MatchCollector.frame or nil
MatchCollector.activeMatch = MatchCollector.activeMatch or nil
MatchCollector.pendingComplete = MatchCollector.pendingComplete or nil
MatchCollector.lastLifecyclePhase = MatchCollector.lastLifecyclePhase or "inactive"
MatchCollector.syncTicker = MatchCollector.syncTicker or nil

local COMPLETE_RETRY_SECONDS = 0.25
local COMPLETE_MAX_ATTEMPTS = 12
local LIFECYCLE_SYNC_SECONDS = 2
local SESSION_RUNTIME_TOLERANCE_MS = 30000
local MATCH_FINGERPRINT_DEDUP_SECONDS = 3600
local MATCH_FINGERPRINT_MIN_NAMES = 4

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

--- Returns true when addon code can read one GUID value.
--- @param guid any
--- @return boolean
function MatchCollector.CanUseGuid(guid)
    if PVL.CombatLogCollector and PVL.CombatLogCollector.CanUseGuid then
        return PVL.CombatLogCollector.CanUseGuid(guid)
    end

    if guid == nil then
        return false
    end

    if issecretvalue and issecretvalue(guid) then
        return canaccessvalue and canaccessvalue(guid) or false
    end

    return type(guid) == "string" and guid ~= ""
end

--- Returns a readable GUID when the client allows addon access.
--- @param guid any
--- @return string|nil
function MatchCollector.GetAccessibleGuid(guid)
    if not MatchCollector.CanUseGuid(guid) then
        return nil
    end

    return guid
end

--- Compares two GUID values without touching secret strings the addon cannot read.
--- @param left any
--- @param right any
--- @return boolean
function MatchCollector.GuidsEqual(left, right)
    if not MatchCollector.CanUseGuid(left) or not MatchCollector.CanUseGuid(right) then
        return false
    end

    local ok, same = pcall(function()
        return left == right
    end)

    return ok and same == true
end

--- Returns true when two roster rows refer to the same player.
--- @param left table|nil
--- @param right table|nil
--- @return boolean
function MatchCollector.ParticipantsMatch(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end

    if MatchCollector.GuidsEqual(left.guid, right.guid) then
        return true
    end

    local leftName = PVL.GetAccessibleString(left.name)
    local rightName = PVL.GetAccessibleString(right.name)
    if leftName and rightName then
        local ok, same = pcall(function()
            return leftName == rightName
        end)
        return ok and same == true
    end

    return false
end

--- Returns the normalized PvP match lifecycle phase for the current client state.
--- Uses C_PvP.GetActiveMatchState when available, with IsMatchActive/IsMatchComplete fallbacks.
--- @return "inactive"|"waiting"|"startup"|"engaged"|"postround"|"complete"
function MatchCollector.GetMatchLifecyclePhase()
    if C_PvP and C_PvP.GetActiveMatchState then
        local state = C_PvP.GetActiveMatchState()
        if Enum and Enum.PvPMatchState then
            if state == Enum.PvPMatchState.Inactive then
                return "inactive"
            end
            if state == Enum.PvPMatchState.Waiting then
                return "waiting"
            end
            if state == Enum.PvPMatchState.StartUp then
                return "startup"
            end
            if state == Enum.PvPMatchState.Engaged then
                return "engaged"
            end
            if state == Enum.PvPMatchState.PostRound then
                return "postround"
            end
            if state == Enum.PvPMatchState.Complete then
                return "complete"
            end
        end

        if state == 0 then
            return "inactive"
        end
        if state == 1 then
            return "waiting"
        end
        if state == 2 then
            return "startup"
        end
        if state == 3 then
            return "engaged"
        end
        if state == 4 then
            return "postround"
        end
        if state == 5 then
            return "complete"
        end
    end

    if C_PvP and C_PvP.IsMatchComplete and C_PvP.IsMatchComplete() then
        return "complete"
    end

    if C_PvP and C_PvP.IsMatchActive and C_PvP.IsMatchActive() then
        return "engaged"
    end

    return "inactive"
end

--- Returns true when live combat-log collection should run for one lifecycle phase.
--- @param phase string|nil
--- @return boolean
function MatchCollector.ShouldCollectCombatForPhase(phase)
    return phase == "waiting"
        or phase == "startup"
        or phase == "engaged"
        or phase == "postround"
end

--- Returns true when the player is inside a PvP instance that PvPLedger tracks.
--- @return boolean
function MatchCollector.IsInCollectiblePvpInstance()
    if C_PvP then
        if C_PvP.IsBattleground and C_PvP.IsBattleground() then
            return true
        end

        if C_PvP.IsArena and C_PvP.IsArena() then
            return true
        end

        if C_PvP.IsMatchActive and C_PvP.IsMatchActive() then
            return true
        end
    end

    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return false
    end

    return instanceType == "pvp" or instanceType == "arena" or instanceType == "scenario"
end

--- Returns the best instance type label for the current PvP context.
--- @return string|nil
function MatchCollector.GetCollectibleInstanceType()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType and instanceType ~= "none" then
        return instanceType
    end

    if C_PvP and C_PvP.IsArena and C_PvP.IsArena() then
        return "arena"
    end

    if C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground() then
        return "pvp"
    end

    if MatchCollector.IsInCollectiblePvpInstance() then
        return "pvp"
    end

    return instanceType
end

--- Returns the battleground/arena runtime in milliseconds when available.
--- @return number
function MatchCollector.GetBattlefieldRuntimeMs()
    if not GetBattlefieldInstanceRunTime then
        return 0
    end

    return MatchCollector.GetAccessibleNumber(GetBattlefieldInstanceRunTime()) or 0
end

--- Returns the UiMapID for the current PvP instance when available.
--- Prefer ``GetInstanceInfo`` over ``GetBestMapForUnit``, which reports open-world
--- zones such as capital cities after leaving an instance.
--- @param preferredMapId number|nil
--- @return number|nil
function MatchCollector.ResolveMatchMapId(preferredMapId)
    if type(preferredMapId) == "number" and preferredMapId > 0 then
        return preferredMapId
    end

    if GetInstanceInfo then
        local inInstance = select(1, GetInstanceInfo())
        local instanceMapId = select(8, GetInstanceInfo())
        if inInstance and type(instanceMapId) == "number" and instanceMapId > 0 then
            return instanceMapId
        end
    end

    if MatchCollector.IsInCollectiblePvpInstance() and C_Map and C_Map.GetBestMapForUnit then
        local mapId = C_Map.GetBestMapForUnit("player")
        if type(mapId) == "number" and mapId > 0 then
            return mapId
        end
    end

    return nil
end

--- Builds a stable session key for the current PvP instance.
--- @param bracket string|nil
--- @return string|nil sessionKey
--- @return string|nil instanceType
--- @return number|nil instanceMapID
--- @return number runtimeMs
function MatchCollector.BuildMatchSessionKey(bracket)
    if not MatchCollector.IsInCollectiblePvpInstance() then
        local _, instanceType = IsInInstance()
        return nil, instanceType, nil, MatchCollector.GetBattlefieldRuntimeMs()
    end

    local instanceType = MatchCollector.GetCollectibleInstanceType() or "pvp"
    local instanceMapID = MatchCollector.ResolveMatchMapId(select(8, GetInstanceInfo()))
    local runtimeMs = MatchCollector.GetBattlefieldRuntimeMs()
    local sessionKey = string.format(
        "%s:%s:%s",
        bracket or "unknown",
        instanceType or "none",
        tostring(instanceMapID or 0)
    )

    return sessionKey, instanceType, instanceMapID, runtimeMs
end

--- Returns true when roster fingerprinting is reliable for one bracket.
--- Solo Shuffle rosters change every round, so name matching is disabled there.
--- @param bracket string|nil
--- @return boolean
function MatchCollector.SupportsRosterFingerprint(bracket)
    return bracket ~= PVL.BRACKETS.SHUFFLE
end

--- Normalizes one scoreboard player name for roster comparisons.
--- @param name string|nil
--- @return string|nil
function MatchCollector.NormalizeRosterName(name)
    if PVL.CombatLogCollector and PVL.CombatLogCollector.NormalizeName then
        return PVL.CombatLogCollector.NormalizeName(name)
    end

    name = PVL.GetAccessibleString(name)
    if not name then
        return nil
    end

    local ok, shortName = pcall(Ambiguate, name, "none")
    if not ok or not shortName then
        return nil
    end

    local baseName = shortName:match("^(.-)%-.+$") or shortName
    return string.lower(baseName)
end

--- Builds a sorted roster name key from scoreboard participants.
--- @param roster table[]|nil
--- @return string|nil nameKey, number validCount
function MatchCollector.BuildRosterNameKey(roster)
    local names = {}

    for _, participant in ipairs(roster or {}) do
        local nameKey = MatchCollector.NormalizeRosterName(participant.name)
        if nameKey then
            table.insert(names, nameKey)
        end
    end

    if #names == 0 then
        return nil, 0
    end

    table.sort(names)
    return table.concat(names, "|"), #names
end

--- Returns the minimum roster size required before trusting one fingerprint.
--- @param bracket string|nil
--- @return number
function MatchCollector.GetFingerprintMinRosterSize(bracket)
    local teamSize = MatchCollector.GetBracketTeamSize(bracket)
    if teamSize and teamSize >= MATCH_FINGERPRINT_MIN_NAMES then
        return teamSize
    end

    if bracket == PVL.BRACKETS.ARENA_2V2 then
        return 4
    end

    if bracket == PVL.BRACKETS.ARENA_3V3 then
        return 6
    end

    return MATCH_FINGERPRINT_MIN_NAMES
end

--- Builds a stable fingerprint from bracket, exact roster names, and pre-match CR/MMR.
--- @param bracket string|nil
--- @param roster table[]|nil
--- @param playerCrBefore number|nil
--- @param playerMmrBefore number|nil
--- @return string|nil
function MatchCollector.BuildMatchFingerprint(bracket, roster, playerCrBefore, playerMmrBefore)
    if not MatchCollector.SupportsRosterFingerprint(bracket) then
        return nil
    end

    local nameKey, validCount = MatchCollector.BuildRosterNameKey(roster)
    if not nameKey or validCount < MatchCollector.GetFingerprintMinRosterSize(bracket) then
        return nil
    end

    local parts = { bracket or "unknown", nameKey }
    local crBefore = MatchCollector.GetAccessibleNumber(playerCrBefore)
    if crBefore and crBefore > 0 then
        table.insert(parts, "cr:" .. math.floor(crBefore + 0.5))
    end

    local mmrBefore = MatchCollector.GetAccessibleNumber(playerMmrBefore)
    if MatchCollector.IsValidMmr(mmrBefore) then
        table.insert(parts, "mmr:" .. math.floor(mmrBefore + 0.5))
    end

    return table.concat(parts, ":")
end

--- Returns a live scoreboard fingerprint for the current match when enough names are visible.
--- @param bracket string|nil
--- @param playerCrBefore number|nil
--- @param playerMmrBefore number|nil
--- @return string|nil
function MatchCollector.TryBuildLiveMatchFingerprint(bracket, playerCrBefore, playerMmrBefore)
    if not MatchCollector.SupportsRosterFingerprint(bracket) then
        return nil
    end

    local roster = MatchCollector.CollectScoreboard()
    if #roster == 0 then
        return nil
    end

    playerCrBefore = playerCrBefore
        or (MatchCollector.activeMatch and MatchCollector.activeMatch.playerCrBefore)

    if not playerMmrBefore then
        playerMmrBefore = MatchCollector.CollectFriendlyTeamMmr()
        if not MatchCollector.IsValidMmr(playerMmrBefore) then
            local localPlayer = MatchCollector.CollectLocalPlayerScore()
            playerMmrBefore = localPlayer and localPlayer.prematchMMR
        end
    end

    return MatchCollector.BuildMatchFingerprint(
        bracket,
        roster,
        playerCrBefore,
        playerMmrBefore
    )
end

--- Updates the active match fingerprint when the scoreboard exposes enough player names.
--- @return string|nil
function MatchCollector.RefreshActiveMatchFingerprint()
    if not MatchCollector.activeMatch then
        return nil
    end

    local fingerprint = MatchCollector.TryBuildLiveMatchFingerprint(
        MatchCollector.activeMatch.bracket,
        MatchCollector.activeMatch.playerCrBefore,
        MatchCollector.activeMatch.playerMmrBefore
    )
    if fingerprint then
        MatchCollector.activeMatch.rosterFingerprint = fingerprint
    end

    return fingerprint
end

--- Returns true when two fingerprints describe the same observed match.
--- @param fingerprintA string|nil
--- @param fingerprintB string|nil
--- @return boolean
function MatchCollector.MatchesSameMatchFingerprint(fingerprintA, fingerprintB)
    return type(fingerprintA) == "string"
        and fingerprintA ~= ""
        and fingerprintA == fingerprintB
end

--- Returns true when one candidate match matches a stored or active observation.
--- @param bracket string|nil
--- @param roster table[]|nil
--- @param playerCrBefore number|nil
--- @param playerMmrBefore number|nil
--- @param reference table|nil
--- @return boolean
function MatchCollector.IsSameObservedMatch(bracket, roster, playerCrBefore, playerMmrBefore, reference)
    if type(reference) ~= "table" then
        return false
    end

    local referenceFingerprint = reference.rosterFingerprint
        or reference.matchFingerprint
        or MatchCollector.BuildMatchFingerprint(
            reference.bracket or bracket,
            reference.roster,
            reference.playerCRBefore or reference.playerCrBefore,
            reference.playerMMRBefore or reference.playerMmrBefore
        )
    local candidateFingerprint = MatchCollector.BuildMatchFingerprint(
        bracket,
        roster,
        playerCrBefore,
        playerMmrBefore
    )

    return MatchCollector.MatchesSameMatchFingerprint(referenceFingerprint, candidateFingerprint)
end

--- Returns true when the current scoreboard still describes the active match context.
--- @param activeMatch table|nil
--- @param bracket string|nil
--- @return boolean
function MatchCollector.ShouldTreatAsSameActiveMatch(activeMatch, bracket)
    if type(activeMatch) ~= "table" or activeMatch.bracket ~= bracket then
        return false
    end

    if not activeMatch.rosterFingerprint then
        MatchCollector.RefreshActiveMatchFingerprint()
    end

    local liveFingerprint = MatchCollector.TryBuildLiveMatchFingerprint(
        bracket,
        activeMatch.playerCrBefore,
        activeMatch.playerMmrBefore
    )
    if not liveFingerprint or not activeMatch.rosterFingerprint then
        return false
    end

    return MatchCollector.MatchesSameMatchFingerprint(liveFingerprint, activeMatch.rosterFingerprint)
end

--- Returns a recently stored match with the same roster fingerprint, if any.
--- @param bracket string|nil
--- @param roster table[]|nil
--- @param playerCrBefore number|nil
--- @param playerMmrBefore number|nil
--- @param maxAgeSeconds number|nil
--- @return table|nil
function MatchCollector.FindRecentDuplicateMatch(bracket, roster, playerCrBefore, playerMmrBefore, maxAgeSeconds)
    local fingerprint = MatchCollector.BuildMatchFingerprint(
        bracket,
        roster,
        playerCrBefore,
        playerMmrBefore
    )
    if not fingerprint then
        return nil
    end

    local db = PVL.GetDB()
    if not db or type(db.observations) ~= "table" then
        return nil
    end

    maxAgeSeconds = maxAgeSeconds or MATCH_FINGERPRINT_DEDUP_SECONDS
    local now = time()
    for index = #db.observations.matches, 1, -1 do
        local match = db.observations.matches[index]
        if match.bracket == bracket
            and match.timestamp
            and (now - match.timestamp) <= maxAgeSeconds
            and MatchCollector.IsSameObservedMatch(
                bracket,
                roster,
                playerCrBefore,
                playerMmrBefore,
                match
            ) then
            return match
        end
    end

    return nil
end

--- Returns a simple completeness score for one stored combat summary.
--- @param combatSummary table|nil
--- @return number
function MatchCollector.ScoreCombatSummary(combatSummary)
    local score = 0
    for _, row in ipairs(combatSummary and combatSummary.players or {}) do
        score = score + (row.damage or 0) + (row.healing or 0) + (row.damageTaken or 0)
        score = score + ((row.interrupts or 0) * 1000)
    end
    return score
end

--- Updates one stored match when a duplicate finalize captured richer combat data.
--- @param existing table|nil
--- @param incoming table|nil
--- @return table|nil
function MatchCollector.UpdateStoredMatchIfBetter(existing, incoming)
    if type(existing) ~= "table" or type(incoming) ~= "table" then
        return existing
    end

    local existingScore = MatchCollector.ScoreCombatSummary(existing.combatSummary)
    local incomingScore = MatchCollector.ScoreCombatSummary(incoming.combatSummary)
    if incoming.combatSummary and incomingScore >= existingScore then
        existing.combatSummary = incoming.combatSummary
    end

    return existing
end

--- Returns the persisted combat session for the current character, if any.
--- @return table|nil
function MatchCollector.GetPendingCombatSession()
    local charDb = PVL.GetCharDB()
    if type(charDb) ~= "table" then
        return nil
    end

    return charDb.pendingCombatSession
end

--- Clears any persisted in-progress combat session for the current character.
function MatchCollector.ClearPendingCombatSession()
    local charDb = PVL.GetCharDB()
    if type(charDb) ~= "table" then
        return
    end

    charDb.pendingCombatSession = nil
end

--- Returns true when a saved combat session belongs to the current instance.
--- @param sessionKey string|nil
--- @param runtimeMs number|nil
--- @param rosterFingerprint string|nil
--- @param playerCrBefore number|nil
--- @return boolean
function MatchCollector.CanResumeCombatSession(sessionKey, runtimeMs, rosterFingerprint, playerCrBefore)
    local pending = MatchCollector.GetPendingCombatSession()
    if type(pending) ~= "table" or not pending.sessionKey or not sessionKey then
        return false
    end

    if pending.sessionKey == sessionKey then
        runtimeMs = runtimeMs or 0
        local minRuntimeMs = pending.minRuntimeMs or 0
        if runtimeMs + SESSION_RUNTIME_TOLERANCE_MS < minRuntimeMs then
            return false
        end

        return true
    end

    if not MatchCollector.SupportsRosterFingerprint(pending.bracket) then
        return false
    end

    if not MatchCollector.MatchesSameMatchFingerprint(rosterFingerprint, pending.rosterFingerprint) then
        return false
    end

    local pendingCr = MatchCollector.GetAccessibleNumber(pending.playerCrBefore)
    local compareCr = MatchCollector.GetAccessibleNumber(playerCrBefore)
    if pendingCr and compareCr and pendingCr ~= compareCr then
        return false
    end

    return true
end

--- Builds the active-match context used by scoreboard and combat-log collectors.
--- @param bracket string|nil
--- @param resumePending boolean|nil
--- @return table|nil
function MatchCollector.BuildActiveMatchContext(bracket, resumePending)
    local sessionKey, instanceType, instanceMapID, runtimeMs = MatchCollector.BuildMatchSessionKey(bracket)
    if not sessionKey then
        return nil
    end

    local pending = resumePending and MatchCollector.GetPendingCombatSession() or nil

    local startCr = nil
    if PVL.RatedInfo then
        PVL.RatedInfo.RefreshAll()
        startCr = MatchCollector.GetAccessibleNumber(PVL.RatedInfo.GetCurrentRating(bracket))
    end

    local startMmr = MatchCollector.CollectFriendlyTeamMmr()
    if not MatchCollector.IsValidMmr(startMmr) then
        local localPlayer = MatchCollector.CollectLocalPlayerScore()
        startMmr = localPlayer and localPlayer.prematchMMR
    end

    local rosterFingerprint = MatchCollector.TryBuildLiveMatchFingerprint(bracket, startCr, startMmr)
    local canResume = pending and MatchCollector.CanResumeCombatSession(
        sessionKey,
        runtimeMs,
        rosterFingerprint,
        startCr
    ) or false

    local context = {
        bracket = bracket,
        sessionKey = sessionKey,
        instanceType = instanceType,
        instanceMapID = instanceMapID,
        runtimeMs = runtimeMs,
        minRuntimeMs = canResume and pending.minRuntimeMs or runtimeMs,
        startedAt = canResume and pending.startedAt or time(),
        mapID = MatchCollector.ResolveMatchMapId(instanceMapID),
        playerCrBefore = canResume and pending.playerCrBefore or startCr,
        playerMmrBefore = canResume and pending.playerMmrBefore or startMmr,
        rosterFingerprint = canResume and pending.rosterFingerprint or rosterFingerprint,
        resumedFromSession = canResume,
        segmentCount = canResume and ((pending.segmentCount or 1) + 1) or 1,
    }

    return context
end

--- Stops lifecycle polling when no match work remains.
function MatchCollector.StopLifecycleSync()
    if MatchCollector.syncTicker then
        MatchCollector.syncTicker:Cancel()
        MatchCollector.syncTicker = nil
    end
end

--- Polls match lifecycle state to recover from missed enter/leave events.
function MatchCollector.StartLifecycleSync()
    if MatchCollector.syncTicker or not C_Timer or not C_Timer.NewTicker then
        return
    end

    MatchCollector.syncTicker = C_Timer.NewTicker(LIFECYCLE_SYNC_SECONDS, function()
        if PVL.IsCombatLocked and PVL.IsCombatLocked() then
            if PVL.EnsureCombatLockEvents then
                PVL._deferredLifecycleSync = true
                PVL.EnsureCombatLockEvents()
            end
            return
        end

        MatchCollector.SyncMatchLifecycle()
    end)
end

--- Reconciles match enter/leave/combat collection using client lifecycle APIs.
function MatchCollector.SyncMatchLifecycle()
    local db = PVL.GetDB()
    if not db or not db.settings.enabled then
        MatchCollector.StopLifecycleSync()
        return
    end

    if PVL.IsCombatLocked and PVL.IsCombatLocked() then
        if PVL.EnsureCombatLockEvents then
            PVL._deferredLifecycleSync = true
            PVL.EnsureCombatLockEvents()
        end
        return
    end

    local phase = MatchCollector.GetMatchLifecyclePhase()
    local previousPhase = MatchCollector.lastLifecyclePhase or "inactive"
    MatchCollector.lastLifecyclePhase = phase

    if phase == "inactive" then
        MatchCollector.HandleMatchInactive(previousPhase)
        MatchCollector.StopLifecycleSync()
        return
    end

    MatchCollector.StartLifecycleSync()

    if phase == "complete" then
        MatchCollector.HandleMatchCompletePhase()
        return
    end

    local combatLocked = PVL.IsCombatLocked and PVL.IsCombatLocked()

    if MatchCollector.ShouldCollectCombatForPhase(phase) then
        MatchCollector.OnMatchEngaged()
        MatchCollector.EnsureCombatLogStarted()
        if not combatLocked
            and PVL.CombatLogCollector
            and PVL.CombatLogCollector.TryLiveSync then
            pcall(PVL.CombatLogCollector.TryLiveSync)
        end
        return
    end

    if phase == "waiting" or phase == "startup" then
        MatchCollector.OnMatchWaiting()
        MatchCollector.EnsureCombatLogStarted()
        if not combatLocked
            and PVL.CombatLogCollector
            and PVL.CombatLogCollector.TryLiveSync then
            pcall(PVL.CombatLogCollector.TryLiveSync)
        end
    end
end

--- Ensures match and combat-log tracking are active when the client reports a live PvP match.
function MatchCollector.EnsureMatchTracking()
    MatchCollector.SyncMatchLifecycle()
end

--- Prepares match metadata while the instance is loading or players are waiting to start.
function MatchCollector.OnMatchWaiting()
    local db = PVL.GetDB()
    if not db or not db.settings.enabled then
        return
    end

    local bracket = MatchCollector.InferCollectibleBracket()
    if not MatchCollector.ShouldCollectBracket(bracket) then
        return
    end

    local context = MatchCollector.BuildActiveMatchContext(bracket, true)
    if not context then
        return
    end

    MatchCollector.pendingComplete = nil
    if MatchCollector.activeMatch then
        MatchCollector.RefreshActiveMatchFingerprint()
        if MatchCollector.activeMatch.sessionKey == context.sessionKey
            or MatchCollector.ShouldTreatAsSameActiveMatch(MatchCollector.activeMatch, bracket) then
            MatchCollector.activeMatch.runtimeMs = context.runtimeMs
            MatchCollector.activeMatch.minRuntimeMs = math.min(
                MatchCollector.activeMatch.minRuntimeMs or context.runtimeMs,
                context.runtimeMs
            )
            if context.rosterFingerprint and not MatchCollector.activeMatch.rosterFingerprint then
                MatchCollector.activeMatch.rosterFingerprint = context.rosterFingerprint
            end
            if PVL.CombatLogCollector
                and PVL.CombatLogCollector.IsEnabled()
                and not PVL.CombatLogCollector.active then
                PVL.CombatLogCollector.StartMatch(MatchCollector.activeMatch)
            end
            return
        end
    end

    MatchCollector.activeMatch = context

    if PVL.CombatLogCollector
        and PVL.CombatLogCollector.IsEnabled()
        and not PVL.CombatLogCollector.active then
        PVL.CombatLogCollector.StartMatch(MatchCollector.activeMatch)
    end
end

--- Arms scoreboard and combat-log collection once the match is actively running.
function MatchCollector.OnMatchEngaged()
    local db = PVL.GetDB()
    if not db or not db.settings.enabled then
        return
    end

    local bracket = MatchCollector.InferCollectibleBracket()
    if not MatchCollector.ShouldCollectBracket(bracket) then
        MatchCollector.activeMatch = nil
        if PVL.CombatLogCollector then
            PVL.CombatLogCollector.StopMatch(true)
        end
        MatchCollector.ClearPendingCombatSession()
        return
    end

    MatchCollector.pendingComplete = nil
    local resumePending = true
    if MatchCollector.activeMatch
        and MatchCollector.activeMatch.sessionKey then
        local sessionKey, _, _, runtimeMs = MatchCollector.BuildMatchSessionKey(bracket)
        if sessionKey == MatchCollector.activeMatch.sessionKey then
            if PVL.CombatLogCollector
                and PVL.CombatLogCollector.IsEnabled()
                and not PVL.CombatLogCollector.active then
                PVL.CombatLogCollector.StartMatch(MatchCollector.activeMatch)
            end
            return
        end

        MatchCollector.RefreshActiveMatchFingerprint()
        if MatchCollector.ShouldTreatAsSameActiveMatch(MatchCollector.activeMatch, bracket) then
            MatchCollector.activeMatch.runtimeMs = runtimeMs
            MatchCollector.activeMatch.minRuntimeMs = math.min(
                MatchCollector.activeMatch.minRuntimeMs or runtimeMs,
                runtimeMs
            )
            MatchCollector.activeMatch.segmentCount = (MatchCollector.activeMatch.segmentCount or 1) + 1
            if PVL.CombatLogCollector then
                PVL.CombatLogCollector.StartMatch(MatchCollector.activeMatch)
            end
            return
        end

        resumePending = false
    end

    local context = MatchCollector.BuildActiveMatchContext(bracket, resumePending)
    if not context then
        return
    end

    MatchCollector.activeMatch = context

    if PVL.CombatLogCollector then
        PVL.CombatLogCollector.StartMatch(context)
    end

    if db.settings.collectSpecs and PVL.InspectQueue and not MatchCollector.IsInCollectiblePvpInstance() then
        if PVL.IsCombatLocked and PVL.IsCombatLocked() then
            PVL.InspectQueue.pendingRosterCallback = function(participant)
                MatchCollector.MergeLiveSpec(participant)
            end
            if PVL.InspectQueue.DeferForCombat then
                PVL.InspectQueue.DeferForCombat()
            end
        else
            PVL.InspectQueue.EnqueueMatchRoster(function(participant)
                MatchCollector.MergeLiveSpec(participant)
            end)
        end
    end
end

--- Handles a definitive leave when the client reports the match is over.
--- @param previousPhase string|nil
function MatchCollector.HandleMatchInactive(previousPhase)
    if previousPhase == "inactive" or previousPhase == "complete" then
        return
    end

    if MatchCollector.pendingComplete and MatchCollector.activeMatch then
        MatchCollector.pendingComplete.mapID = MatchCollector.pendingComplete.mapID
            or MatchCollector.ResolveMatchMapId(MatchCollector.activeMatch.mapID)
    end

    if MatchCollector.activeMatch and PVL.CombatLogCollector then
        MatchCollector.PersistActiveCombatSession()
    elseif PVL.CombatLogCollector and PVL.CombatLogCollector.active then
        MatchCollector.PersistActiveCombatSession()
    end

    MatchCollector.activeMatch = nil

    -- Keep pending combat sessions until FinalizeMatchComplete consumes them.
    -- Leaving the instance makes BuildMatchSessionKey return nil, which previously
    -- caused CanResumeCombatSession to fail and wiped captured combat data.
end

--- Ensures post-match finalization runs even when PVP_MATCH_COMPLETE was missed.
function MatchCollector.HandleMatchCompletePhase()
    if MatchCollector.pendingComplete then
        return
    end

    if MatchCollector.activeMatch and PVL.CombatLogCollector then
        MatchCollector.PersistActiveCombatSession()
    end

    MatchCollector.OnMatchComplete()
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
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:RegisterEvent("LOADING_SCREEN_DISABLED")
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
        MatchCollector.SyncMatchLifecycle()
        MatchCollector.EnsureCombatLogStarted()
    elseif event == "PVP_MATCH_ACTIVE" then
        MatchCollector.SyncMatchLifecycle()
        MatchCollector.EnsureCombatLogStarted()
    elseif event == "PVP_MATCH_COMPLETE" then
        MatchCollector.PersistActiveCombatSession()
        MatchCollector.OnMatchComplete()
    elseif event == "PLAYER_LOGOUT" then
        MatchCollector.PersistActiveCombatSession()
    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "LOADING_SCREEN_DISABLED" then
        MatchCollector.SyncMatchLifecycle()
        MatchCollector.EnsureCombatLogStarted()
    end
end

--- Back-compat alias for event handlers that still call the old match-start hook.
function MatchCollector.OnMatchActive()
    MatchCollector.SyncMatchLifecycle()
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

    if C_PvP.IsRatedBGBlitz and C_PvP.IsRatedBGBlitz() then
        return PVL.BRACKETS.BLITZ
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

--- Returns the best bracket guess when C_PvP helpers are unavailable.
--- @return string|nil
function MatchCollector.InferCollectibleBracket()
    local bracket = MatchCollector.GetCurrentBracket()
    if bracket then
        return bracket
    end

    if not MatchCollector.IsInCollectiblePvpInstance() then
        return nil
    end

    local instanceType = MatchCollector.GetCollectibleInstanceType() or "pvp"

    if instanceType == "arena" then
        if C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() then
            return PVL.BRACKETS.SHUFFLE
        end

        if C_PvP.IsRatedArena and C_PvP.IsRatedArena() and GetBattlefieldArenaFaction and C_PvP.GetTeamInfo then
            local factionIndex = GetBattlefieldArenaFaction()
            local teamInfo = C_PvP.GetTeamInfo(factionIndex)
            local teamSize = teamInfo and teamInfo.size or 0
            if teamSize > 0 and teamSize <= 2 then
                return PVL.BRACKETS.ARENA_2V2
            end
        end

        return PVL.BRACKETS.ARENA_3V3
    end

    if instanceType == "pvp" or instanceType == "scenario" or instanceType == "none" then
        if C_PvP.IsRatedBGBlitz and C_PvP.IsRatedBGBlitz() then
            return PVL.BRACKETS.BLITZ
        end

        if C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground() then
            return PVL.BRACKETS.RBG
        end

        return PVL.BRACKETS.BLITZ
    end

    return nil
end

--- Ensures combat-log capture is armed for the current PvP instance.
function MatchCollector.EnsureCombatLogStarted()
    MatchCollector.RefreshActiveMatchFingerprint()
    if not PVL.CombatLogCollector or not PVL.CombatLogCollector.ArmForCurrentInstance then
        return
    end

    PVL.CombatLogCollector.ArmForCurrentInstance()
end

--- Persists any in-progress combat session before match metadata is cleared.
function MatchCollector.PersistActiveCombatSession()
    MatchCollector.RefreshActiveMatchFingerprint()
    if not PVL.CombatLogCollector or not PVL.CombatLogCollector.PersistPendingSession then
        return
    end

    local matchContext = MatchCollector.activeMatch or PVL.CombatLogCollector.matchContext
    if matchContext then
        PVL.CombatLogCollector.PersistPendingSession(matchContext)
    end
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

--- Merges a live inspect result into the active match cache by player name.
--- @param participant table
function MatchCollector.MergeLiveSpec(participant)
    if not MatchCollector.activeMatch or not participant or not participant.name then
        return
    end

    MatchCollector.activeMatch.liveSpecs = MatchCollector.activeMatch.liveSpecs or {}
    MatchCollector.activeMatch.liveSpecs[participant.name] = participant.spec
end

--- Returns true when a lowercase label matches any keyword fragment.
--- @param label string|nil
--- @param keywords string[]
--- @return boolean
function MatchCollector.ScoreboardStatMatches(label, keywords)
    label = PVL.GetAccessibleString(label)
    if not label then
        return false
    end

    for _, keyword in ipairs(keywords) do
        local ok, matched = pcall(function()
            return label:find(keyword, 1, true) ~= nil
        end)
        if ok and matched then
            return true
        end
    end

    return false
end

--- Returns true when the current scoreboard context is Solo Shuffle.
--- @return boolean
function MatchCollector.IsShuffleScoreboardContext()
    if MatchCollector.activeMatch and MatchCollector.activeMatch.bracket == PVL.BRACKETS.SHUFFLE then
        return true
    end

    return C_PvP and C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() or false
end

--- Returns the custom victory stat id for the active match (Solo Shuffle round wins).
--- @return number|nil
function MatchCollector.GetShuffleVictoryStatId()
    if not C_PvP or not C_PvP.GetCustomVictoryStatID then
        return nil
    end

    local ok, statId = pcall(C_PvP.GetCustomVictoryStatID)
    if ok and type(statId) == "number" and statId > 0 then
        return statId
    end

    return nil
end

--- Builds a lowercase search blob for one scoreboard stat row.
--- @param stat table
--- @return string
function MatchCollector.BuildScoreboardStatBlob(stat)
    local statName = PVL.GetAccessibleString(stat.name) or ""
    local statTooltip = PVL.GetAccessibleString(stat.tooltip) or ""
    local statIcon = PVL.GetAccessibleString(stat.iconName) or ""
    local columnName = ""
    local columnTooltip = ""
    local columnTitle = ""

    if stat.pvpStatID and C_PvP and C_PvP.GetMatchPVPStatColumn then
        local columnOk, column = pcall(C_PvP.GetMatchPVPStatColumn, stat.pvpStatID)
        if columnOk and type(column) == "table" then
            columnName = PVL.GetAccessibleString(column.name) or ""
            columnTooltip = PVL.GetAccessibleString(column.tooltip) or ""
            columnTitle = PVL.GetAccessibleString(column.tooltipTitle) or ""
        end
    end

    local blobOk, blob = pcall(function()
        return string.lower(string.format(
            "%s %s %s %s %s %s",
            statName,
            statTooltip,
            statIcon,
            columnName,
            columnTooltip,
            columnTitle
        ))
    end)
    if not blobOk or not blob then
        return ""
    end

    return blob
end

--- Parses Solo Shuffle round win/loss totals from scoreboard stat rows.
--- Blizzard exposes round wins through ``GetCustomVictoryStatID`` and the per-player
--- ``stats`` array on ``C_PvP.GetScoreInfo``.
--- @param stats table[]|nil
--- @return table { roundsWon, roundsLost, roundsPlayed }
function MatchCollector.ParseShuffleRoundStats(stats)
    local parsed = {
        roundsWon = nil,
        roundsLost = nil,
        roundsPlayed = nil,
    }

    if type(stats) ~= "table" then
        return parsed
    end

    local victoryStatId = MatchCollector.GetShuffleVictoryStatId()

    for _, stat in ipairs(stats) do
        local value = MatchCollector.GetAccessibleNumber(stat.pvpStatValue)
        if value == nil or value < 0 then
            -- Skip empty or unavailable rows.
        elseif victoryStatId and stat.pvpStatID == victoryStatId then
            parsed.roundsWon = value
        else
            local blob = MatchCollector.BuildScoreboardStatBlob(stat)
            if MatchCollector.ScoreboardStatMatches(blob, { "round", "won" }) then
                parsed.roundsWon = value
            elseif MatchCollector.ScoreboardStatMatches(blob, { "round", "lost" }) then
                parsed.roundsLost = value
            elseif MatchCollector.ScoreboardStatMatches(blob, { "round", "played" }) then
                parsed.roundsPlayed = value
            end
        end
    end

    if parsed.roundsWon ~= nil and parsed.roundsLost == nil then
        local played = parsed.roundsPlayed or PVL.SHUFFLE_ROUNDS_PER_MATCH
        if played >= parsed.roundsWon then
            parsed.roundsLost = played - parsed.roundsWon
        end
    elseif parsed.roundsWon == nil and parsed.roundsLost ~= nil and parsed.roundsPlayed then
        parsed.roundsWon = math.max(0, parsed.roundsPlayed - parsed.roundsLost)
    elseif parsed.roundsWon ~= nil and parsed.roundsLost ~= nil and not parsed.roundsPlayed then
        parsed.roundsPlayed = parsed.roundsWon + parsed.roundsLost
    end

    return parsed
end

--- Parses extended PvP scoreboard stats when Blizzard exposes them.
--- Battleground Blitz does not include kick counts on the scoreboard; those come from the combat log.
--- @param stats table[]|nil
--- @return table
function MatchCollector.ParseScoreboardStats(stats)
    local parsed = {
        interrupts = 0,
        dispels = 0,
        deaths = 0,
    }

    if type(stats) ~= "table" then
        return parsed
    end

    for _, stat in ipairs(stats) do
        local value = MatchCollector.GetAccessibleNumber(stat.pvpStatValue) or 0
        if value <= 0 then
            -- Skip empty rows.
        else
            local blob = MatchCollector.BuildScoreboardStatBlob(stat)

            if MatchCollector.ScoreboardStatMatches(blob, {
                "interrupt",
                "kick",
                "counterspell",
                "pummel",
                "spell lock",
                "skull bash",
                "rebuke",
                "wind shear",
            }) then
                parsed.interrupts = parsed.interrupts + value
            elseif MatchCollector.ScoreboardStatMatches(blob, {
                "dispel",
                "purify",
                "cleanse",
                "mass dispel",
                "offensive dispel",
            }) then
                parsed.dispels = parsed.dispels + value
            elseif MatchCollector.ScoreboardStatMatches(blob, {
                "death",
                "killing blow",
            }) then
                parsed.deaths = parsed.deaths + value
            end
        end
    end

    return parsed
end

--- Builds one participant row from scoreboard data.
--- @param scoreInfo table
--- @return table|nil
function MatchCollector.BuildParticipantFromScore(scoreInfo)
    if type(scoreInfo) ~= "table" then
        return nil
    end

    local rawName = PVL.GetAccessibleString(scoreInfo.name)
    if not rawName then
        return nil
    end

    local name
    local realm
    local parseOk
    parseOk, name, realm = pcall(function()
        local parsedName, parsedRealm = Ambiguate(rawName, "none"):match("^(.-)%-(.+)$")
        if parsedName then
            return parsedName, parsedRealm
        end
        return Ambiguate(rawName, "none"), nil
    end)
    if not parseOk or not name then
        return nil
    end

    local classToken = scoreInfo.classToken
    local specKey = nil
    local accessibleSpec = PVL.GetAccessibleString(scoreInfo.talentSpec)
    if accessibleSpec ~= nil then
        specKey = PVL.NormalizeSpecKey(classToken, accessibleSpec)
    end
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

    local scoreboardStats = MatchCollector.ParseScoreboardStats(scoreInfo.stats)
    local deaths = MatchCollector.GetAccessibleNumber(scoreInfo.deaths) or scoreboardStats.deaths or 0
    local shuffleRounds = MatchCollector.IsShuffleScoreboardContext()
        and MatchCollector.ParseShuffleRoundStats(scoreInfo.stats)
        or nil

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
        guid = MatchCollector.GetAccessibleGuid(scoreInfo.guid),
        damageDone = MatchCollector.GetAccessibleNumber(scoreInfo.damageDone),
        healingDone = MatchCollector.GetAccessibleNumber(scoreInfo.healingDone),
        interrupts = scoreboardStats.interrupts,
        dispels = scoreboardStats.dispels,
        deaths = deaths,
        roundsWon = shuffleRounds and shuffleRounds.roundsWon or nil,
        roundsLost = shuffleRounds and shuffleRounds.roundsLost or nil,
        roundsPlayed = shuffleRounds and shuffleRounds.roundsPlayed or nil,
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

    local playerGuid = UnitGUID and UnitGUID("player")
    if MatchCollector.GuidsEqual(playerGuid, scoreInfo.guid) then
        return true
    end

    local scoreName = PVL.GetAccessibleString(scoreInfo.name)
    if not scoreName or not UnitFullName then
        return false
    end

    local playerName, playerRealm = UnitFullName("player")
    if not playerName then
        return false
    end

    local ambiguateOk, scoreShortName = pcall(Ambiguate, scoreName, "none")
    if not ambiguateOk or not scoreShortName then
        return false
    end

    local playerFullName = playerRealm and (playerName .. "-" .. playerRealm) or playerName
    local playerShortOk, playerShortName = pcall(Ambiguate, playerFullName, "none")
    if playerShortOk and scoreShortName == playerShortName then
        return true
    end

    if scoreShortName == playerName then
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

    local participantGuid = MatchCollector.GetAccessibleGuid(participant.guid)
    if participantGuid and combatPlayers[participantGuid] then
        return combatPlayers[participantGuid]
    end

    for _, row in pairs(combatPlayers) do
        if participant.name and row.name then
            local participantKey = PVL.CombatLogCollector and PVL.CombatLogCollector.NormalizeName(participant.name)
            local rowKey = PVL.CombatLogCollector and PVL.CombatLogCollector.NormalizeName(row.name)
            if participantKey and rowKey and participantKey == rowKey then
                return row
            end
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
        if MatchCollector.GuidsEqual(participant.guid, row.guid) then
            return row.team
        end
        local participantName = PVL.GetAccessibleString(participant.name)
        local rowName = PVL.GetAccessibleString(row.name)
        if participantName and rowName then
            local ok, same = pcall(function()
                return participantName == rowName
            end)
            if ok and same then
                return row.team
            end
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
        if MatchCollector.ParticipantsMatch(participant, target) then
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
        if MatchCollector.ParticipantsMatch(participant, target) then
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
        return nil
    end

    if localChange == 0 and participantChange > 0 then
        return "enemy"
    end

    if localChange == 0 and participantChange < 0 then
        return "friendly"
    end

    if localChange > 0 and participantChange == 0 then
        return "enemy"
    end

    if localChange < 0 and participantChange == 0 then
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

--- Returns true when one bracket uses win/loss plus rating-change team assignment.
--- @param bracket string|nil
--- @return boolean
function MatchCollector.UsesRatingTeamSplit(bracket)
    return bracket == PVL.BRACKETS.RBG or bracket == PVL.BRACKETS.BLITZ
end

--- Resolves whether the local player won using stored match data when available.
--- @param matchRecord table|nil
--- @param localPlayer table|nil
--- @return boolean|nil
function MatchCollector.ResolveMatchWon(matchRecord, localPlayer)
    if type(matchRecord) == "table" and matchRecord.won ~= nil then
        return matchRecord.won
    end

    if type(localPlayer) == "table" and localPlayer.ratingChange ~= nil then
        if localPlayer.ratingChange > 0 then
            return true
        end
        if localPlayer.ratingChange < 0 then
            return false
        end
    end

    if type(matchRecord) == "table"
        and matchRecord.playerCRBefore
        and matchRecord.playerCRAfter then
        local delta = matchRecord.playerCRAfter - matchRecord.playerCRBefore
        if delta > 0 then
            return true
        end
        if delta < 0 then
            return false
        end
    end

    return MatchCollector.ResolveLocalMatchWon(localPlayer)
end

--- Resolves one participant's team from match outcome and rating-change buckets.
--- Cross-faction Blitz uses this instead of faction because team membership is not
--- tied to Alliance/Horde on the scoreboard.
--- @param participant table
--- @param localPlayer table|nil
--- @param won boolean|nil
--- @param bracket string|nil
--- @return string|nil
function MatchCollector.ResolveParticipantTeamByRating(participant, localPlayer, won, bracket)
    if type(participant) ~= "table" then
        return nil
    end

    if participant.isLocalPlayer then
        return "friendly"
    end

    if type(localPlayer) ~= "table" then
        return nil
    end

    if won == true or won == false then
        local bucket = MatchCollector.GetRatingChangeBucket(participant)
        if bucket == "gain" then
            return won and "friendly" or "enemy"
        end
        if bucket == "loss" then
            return won and "enemy" or "friendly"
        end
        if bucket == "neutral" then
            if won == true then
                return "enemy"
            end
            if won == false then
                return "friendly"
            end
            if MatchCollector.GetRatingChangeBucket(localPlayer) == "neutral" then
                return "friendly"
            end
            return nil
        end
    end

    return MatchCollector.InferTeamFromRatingChange(participant, localPlayer, bracket)
end

--- Assigns teams from match outcome and per-player rating change for Blitz/RBG.
--- @param roster table[]|nil
--- @param localPlayer table|nil
--- @param won boolean|nil
--- @param bracket string|nil
function MatchCollector.AssignTeamsByRatingChange(roster, localPlayer, won, bracket)
    localPlayer = localPlayer or MatchCollector.FindLocalParticipant(roster)
    if not localPlayer then
        return
    end

    if won == nil then
        won = MatchCollector.ResolveLocalMatchWon(localPlayer)
    end

    for _, participant in ipairs(roster or {}) do
        participant.team = MatchCollector.ResolveParticipantTeamByRating(
            participant,
            localPlayer,
            won,
            bracket
        ) or "enemy"
    end
end

--- Returns true when a roster has enough players for fixed-size constraint assignment.
--- @param roster table[]|nil
--- @param bracket string|nil
--- @return boolean
function MatchCollector.RosterLooksCompleteForTeamSplit(roster, bracket)
    local teamSize = MatchCollector.GetBracketTeamSize(bracket)
    if not teamSize then
        return false
    end

    return #(roster or {}) >= (teamSize * 2)
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

    localPlayer = localPlayer or MatchCollector.FindLocalParticipant(roster)

    if MatchCollector.UsesRatingTeamSplit(bracket) then
        MatchCollector.AssignTeamsByRatingChange(roster, localPlayer, won, bracket)
        return
    end

    if MatchCollector.UsesConstraintTeamSplit(bracket)
        and MatchCollector.RosterLooksCompleteForTeamSplit(roster, bracket) then
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

    if MatchCollector.UsesRatingTeamSplit(bracket) then
        local won = MatchCollector.ResolveMatchWon(matchRecord, localPlayer)
        return MatchCollector.ResolveParticipantTeamByRating(
            participant,
            localPlayer,
            won,
            bracket
        ) or "enemy"
    end

    if MatchCollector.UsesConstraintTeamSplit(bracket)
        and MatchCollector.RosterLooksCompleteForTeamSplit(roster, bracket) then
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

    return "enemy"
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

--- Resolves personal MMR from one scoreboard participant row.
--- @param localPlayer table|nil
--- @return number|nil mmrAfter, number|nil mmrBefore
function MatchCollector.ResolvePersonalMmr(localPlayer)
    if not localPlayer then
        return nil, nil
    end

    local personalAfter = nil
    local personalBefore = nil

    if MatchCollector.IsValidMmr(localPlayer.postmatchMMR) then
        personalAfter = localPlayer.postmatchMMR
    elseif MatchCollector.IsValidMmr(localPlayer.prematchMMR) then
        personalAfter = localPlayer.prematchMMR
    end

    if MatchCollector.IsValidMmr(localPlayer.prematchMMR) then
        personalBefore = localPlayer.prematchMMR
    end

    return personalAfter, personalBefore
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

    local personalAfter, personalBefore = MatchCollector.ResolvePersonalMmr(localPlayer)
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
        if MatchCollector.ParticipantsMatch(participant, localPlayer) then
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

        return false
    end

    if bracket == PVL.BRACKETS.SHUFFLE then
        local expectedPlayers = PVL.SHUFFLE_ROUNDS_PER_MATCH or 6
        local playersWithRounds = 0

        for _, participant in ipairs(roster) do
            if participant.roundsWon ~= nil then
                playersWithRounds = playersWithRounds + 1
            end
        end

        if #roster >= expectedPlayers and playersWithRounds >= expectedPlayers then
            return true
        end

        if localPlayer and localPlayer.roundsWon ~= nil and playersWithRounds >= math.max(1, #roster) then
            return true
        end

        if attempt and attempt >= COMPLETE_MAX_ATTEMPTS then
            return localPlayer ~= nil or #roster > 0
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

    local bracket = MatchCollector.activeMatch and MatchCollector.activeMatch.bracket
        or MatchCollector.GetCurrentBracket()
        or MatchCollector.InferCollectibleBracket()
    if not MatchCollector.ShouldCollectBracket(bracket) then
        MatchCollector.activeMatch = nil
        MatchCollector.pendingComplete = nil
        return
    end

    if MatchCollector.activeMatch and PVL.CombatLogCollector then
        MatchCollector.PersistActiveCombatSession()
    elseif PVL.CombatLogCollector and PVL.CombatLogCollector.active then
        MatchCollector.PersistActiveCombatSession()
    end

    MatchCollector.pendingComplete = {
        bracket = bracket,
        playerCrBefore = MatchCollector.activeMatch and MatchCollector.activeMatch.playerCrBefore or nil,
        mapID = MatchCollector.ResolveMatchMapId(MatchCollector.activeMatch and MatchCollector.activeMatch.mapID),
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

    if PVL.CombatLogCollector and PVL.CombatLogCollector.SyncFromDamageMeter then
        if not (PVL.IsCombatLocked and PVL.IsCombatLocked()) then
            pcall(PVL.CombatLogCollector.SyncFromDamageMeter)
        end
    end

    if PVL.CombatLogCollector then
        pcall(MatchCollector.PersistActiveCombatSession)
    end

    if not MatchCollector.ScoreboardLooksReady(localPlayer, roster, pending.bracket, attempt) and attempt < COMPLETE_MAX_ATTEMPTS then
        MatchCollector.ScheduleCompleteAttempt(attempt + 1)
        return
    end

    MatchCollector.pendingComplete = nil
    MatchCollector.FinalizeMatchComplete(
        pending.bracket,
        roster,
        localPlayer,
        pending.playerCrBefore,
        pending.mapID
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
--- @param matchMapId number|nil
function MatchCollector.FinalizeMatchComplete(bracket, roster, localPlayer, matchStartCr, matchMapId)
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
    local personalMmrAfter, personalMmrBefore = MatchCollector.ResolvePersonalMmr(localPlayer)
    local playerCrBefore, playerCrAfter = MatchCollector.ResolveMatchCrFields(
        localPlayer,
        bracket,
        matchStartCr
    )

    if localPlayer then
        local storedCr = playerCrAfter or localPlayer.rating
        local storedPersonalMmr = personalMmrAfter
        if bracket == PVL.BRACKETS.SHUFFLE then
            charDb.lastShuffleCR = storedCr
            charDb.lastShuffleMMR = mmrAfter
            charDb.lastShuffleMMRKind = mmrKind
            charDb.lastShufflePersonalMMR = storedPersonalMmr
        elseif bracket == PVL.BRACKETS.RBG then
            charDb.lastRbgCR = storedCr
            charDb.lastRbgMMR = mmrAfter
            charDb.lastRbgMMRKind = mmrKind
            charDb.lastRbgPersonalMMR = storedPersonalMmr
        elseif bracket == PVL.BRACKETS.ARENA_2V2 then
            charDb.lastArena2v2CR = storedCr
            charDb.lastArena2v2MMR = mmrAfter
            charDb.lastArena2v2MMRKind = mmrKind
            charDb.lastArena2v2PersonalMMR = storedPersonalMmr
        elseif bracket == PVL.BRACKETS.ARENA_3V3 then
            charDb.lastArena3v3CR = storedCr
            charDb.lastArena3v3MMR = mmrAfter
            charDb.lastArena3v3MMRKind = mmrKind
            charDb.lastArena3v3PersonalMMR = storedPersonalMmr
        else
            charDb.lastBlitzCR = storedCr
            charDb.lastBlitzMMR = mmrAfter
            charDb.lastBlitzMMRKind = mmrKind
            charDb.lastBlitzPersonalMMR = storedPersonalMmr
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
        pcall(MatchCollector.PersistActiveCombatSession)
        local matchContext = MatchCollector.activeMatch or PVL.CombatLogCollector.matchContext
        local ok, result = pcall(PVL.CombatLogCollector.BuildSummary, roster, matchContext)
        if ok then
            combatSummary = result
        end
    end
    if not combatSummary and #roster > 0 and PVL.UI and PVL.UI.ResolveMatchCombatSummary then
        combatSummary = PVL.UI.ResolveMatchCombatSummary({
            roster = roster,
            timestamp = time(),
            bracket = bracket,
        })
    end

    local matchFingerprint = MatchCollector.BuildMatchFingerprint(
        bracket,
        roster,
        playerCrBefore,
        mmrBefore
    )
    local duplicateMatch = MatchCollector.FindRecentDuplicateMatch(
        bracket,
        roster,
        playerCrBefore,
        mmrBefore,
        MATCH_FINGERPRINT_DEDUP_SECONDS
    )
    if duplicateMatch then
        MatchCollector.UpdateStoredMatchIfBetter(duplicateMatch, {
            combatSummary = combatSummary,
            roster = roster,
        })

        MatchCollector.activeMatch = nil
        MatchCollector.ClearPendingCombatSession()
        MatchCollector.StopLifecycleSync()
        MatchCollector.lastLifecyclePhase = "inactive"

        if PVL.UI and PVL.UI.GetFilters then
            PVL.UI.GetFilters().selectedMatchId = duplicateMatch.matchId
        end
        if PVL.RequestUiRefresh then
            pcall(PVL.RequestUiRefresh)
        end
        return
    end

    local playerSpec = nil
    if localPlayer then
        playerSpec = PVL.GetMatchPlayerSpec({ roster = { localPlayer } })
            or PVL.MakeSpecKey(localPlayer.class, localPlayer.spec)
    end

    local resolvedMapId = MatchCollector.ResolveMatchMapId(matchMapId)
    if not resolvedMapId and MatchCollector.activeMatch then
        resolvedMapId = MatchCollector.ResolveMatchMapId(MatchCollector.activeMatch.mapID)
    end
    if not resolvedMapId then
        local pendingSession = MatchCollector.GetPendingCombatSession()
        resolvedMapId = MatchCollector.ResolveMatchMapId(pendingSession and pendingSession.mapID)
    end
    if not resolvedMapId and PVL.CombatLogCollector and PVL.CombatLogCollector.matchContext then
        resolvedMapId = MatchCollector.ResolveMatchMapId(PVL.CombatLogCollector.matchContext.mapID)
    end

    local matchRecord = {
        matchId = MatchCollector.BuildMatchId(bracket, roster),
        matchFingerprint = matchFingerprint,
        rosterFingerprint = matchFingerprint,
        bracket = bracket,
        timestamp = time(),
        mapID = resolvedMapId,
        won = MatchCollector.ResolveLocalMatchWon(localPlayer),
        playerSpec = playerSpec,
        playerCRBefore = playerCrBefore,
        playerCRAfter = playerCrAfter,
        playerMMRBefore = mmrBefore,
        playerMMRAfter = mmrAfter,
        playerMMRKind = mmrKind,
        playerPersonalMMRBefore = personalMmrBefore,
        playerPersonalMMRAfter = personalMmrAfter,
        playerRoundWins = localPlayer and localPlayer.roundsWon or nil,
        playerRoundLosses = localPlayer and localPlayer.roundsLost or nil,
        playerRoundsPlayed = localPlayer and localPlayer.roundsPlayed or nil,
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
    MatchCollector.ClearPendingCombatSession()
    MatchCollector.StopLifecycleSync()
    MatchCollector.lastLifecyclePhase = "inactive"

    if PVL.RatedInfo then
        PVL.RatedInfo.RequestUpdate()
    end

    if PVL.RequestUiRefresh then
        pcall(PVL.RequestUiRefresh)
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
    local bracket = MatchCollector.activeMatch and MatchCollector.activeMatch.bracket
        or MatchCollector.InferCollectibleBracket()
    local localPlayer = MatchCollector.CollectLocalPlayerScore()
    local teamMmr = MatchCollector.CollectFriendlyTeamMmr()
    local phase = MatchCollector.GetMatchLifecyclePhase()
    local sessionKey = MatchCollector.BuildMatchSessionKey(bracket)
    local pending = MatchCollector.GetPendingCombatSession()
    local runtimeMs = MatchCollector.GetBattlefieldRuntimeMs()

    print(string.format("|cff66ccffPvPLedger|r score debug: bracket=%s phase=%s scores=%d matchComplete=%s",
        tostring(bracket),
        tostring(phase),
        GetNumBattlefieldScores and GetNumBattlefieldScores() or 0,
        tostring(C_PvP.IsMatchComplete and C_PvP.IsMatchComplete() or false)
    ))

    print(string.format("  sessionKey=%s runtimeMs=%s activeMatch=%s fingerprint=%s",
        tostring(sessionKey),
        tostring(runtimeMs),
        tostring(MatchCollector.activeMatch ~= nil),
        tostring(MatchCollector.activeMatch and MatchCollector.activeMatch.rosterFingerprint or "nil")
    ))

    if pending then
        local pendingPlayers = 0
        for _ in pairs(pending.players or {}) do
            pendingPlayers = pendingPlayers + 1
        end
        print(string.format("  pendingSession key=%s segments=%s events=%s interrupts=%s players=%s savedAt=%s",
            tostring(pending.sessionKey),
            tostring(pending.segmentCount or 1),
            tostring(pending.eventCount or 0),
            tostring(pending.interruptCount or 0),
            tostring(pendingPlayers),
            tostring(pending.savedAt or "nil")
        ))
    else
        print("  pendingSession=nil")
    end

    if PVL.CombatLogCollector then
        print(string.format("  combatLog active=%s events=%s interrupts=%s segments=%s shouldTrack=%s inBg=%s inArena=%s matchActive=%s",
            tostring(PVL.CombatLogCollector.active),
            tostring(PVL.CombatLogCollector.eventCount or 0),
            tostring(PVL.CombatLogCollector.interruptCount or 0),
            tostring(PVL.CombatLogCollector.segmentCount or 1),
            tostring(PVL.CombatLogCollector.ShouldTrackCombatLog and PVL.CombatLogCollector.ShouldTrackCombatLog() or false),
            tostring(C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground() or false),
            tostring(C_PvP and C_PvP.IsArena and C_PvP.IsArena() or false),
            tostring(C_PvP and C_PvP.IsMatchActive and C_PvP.IsMatchActive() or false)
        ))
        print(string.format("  combatContext sessionKey=%s lastInterrupt=%s dataSource=%s damageMeter=%s synced=%s liveSync=%s",
            tostring(PVL.CombatLogCollector.matchContext and PVL.CombatLogCollector.matchContext.sessionKey),
            tostring(PVL.CombatLogCollector.lastInterruptName or "none"),
            tostring(PVL.CombatLogCollector.GetDataSourceLabel and PVL.CombatLogCollector.GetDataSourceLabel() or "unknown"),
            tostring(PVL.CombatLogCollector.IsDamageMeterAvailable and PVL.CombatLogCollector.IsDamageMeterAvailable() or false),
            tostring(PVL.CombatLogCollector.damageMeterSynced == true),
            tostring(PVL.CombatLogCollector.liveSyncTicker ~= nil)
        ))
    end

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
