--- Captures per-match combat summaries from live combat log events.
--- @class PvPLedger
local PVL = PvPLedger

PVL.CombatLogCollector = PVL.CombatLogCollector or {}
local CombatLogCollector = PVL.CombatLogCollector

CombatLogCollector.frame = CombatLogCollector.frame or nil
CombatLogCollector.active = CombatLogCollector.active or false
CombatLogCollector.startedAt = CombatLogCollector.startedAt or nil
CombatLogCollector.startTimestamp = CombatLogCollector.startTimestamp or nil
CombatLogCollector.players = CombatLogCollector.players or {}
CombatLogCollector.killEvents = CombatLogCollector.killEvents or {}

local DAMAGE_SUBEVENTS = {
    SWING_DAMAGE = 12,
    RANGE_DAMAGE = 12,
    SPELL_DAMAGE = 15,
    SPELL_PERIODIC_DAMAGE = 15,
    DAMAGE_SHIELD = 15,
    DAMAGE_SPLIT = 15,
}

local HEAL_SUBEVENTS = {
    SPELL_HEAL = 15,
    SPELL_PERIODIC_HEAL = 15,
}

local AFFILIATION_MASK = 0x7

--- Returns true when combat summary collection is enabled in settings.
--- @return boolean
function CombatLogCollector.IsEnabled()
    local db = PVL.GetDB()
    if not db or not db.settings.enabled then
        return false
    end

    if db.settings.collectCombatSummary == false then
        return false
    end

    return true
end

--- Returns a usable number when the client allows addon access.
--- @param value any
--- @return number|nil
function CombatLogCollector.GetAccessibleNumber(value)
    if PVL.MatchCollector and PVL.MatchCollector.GetAccessibleNumber then
        return PVL.MatchCollector.GetAccessibleNumber(value)
    end

    if value == nil then
        return nil
    end

    return tonumber(value)
end

--- Returns true when a combat log GUID belongs to a player character.
--- @param guid string|nil
--- @return boolean
function CombatLogCollector.IsPlayerGuid(guid)
    return type(guid) == "string" and guid:find("^Player%-") ~= nil
end

--- Returns true when combat log affiliation flags represent a friendly unit.
--- @param flags number|nil
--- @return boolean
function CombatLogCollector.IsFriendlyFlags(flags)
    if not flags or not bit.band or AFFILIATION_MASK == 0 then
        return false
    end

    return bit.band(flags, AFFILIATION_MASK) > 0
end

--- Returns a blank player stats row.
--- @param guid string
--- @param name string|nil
--- @param team string
--- @return table
function CombatLogCollector.CreatePlayerRow(guid, name, team)
    return {
        guid = guid,
        name = name,
        team = team,
        damage = 0,
        healing = 0,
        damageTaken = 0,
        interrupts = 0,
        ccApplied = 0,
        ccTaken = 0,
        deaths = 0,
    }
end

--- Returns or creates one tracked player stats row.
--- @param guid string
--- @param name string|nil
--- @param flags number|nil
--- @return table|nil
function CombatLogCollector.GetPlayerRow(guid, name, flags)
    if not CombatLogCollector.IsPlayerGuid(guid) then
        return nil
    end

    local players = CombatLogCollector.players
    local row = players[guid]
    if not row then
        local team = CombatLogCollector.IsFriendlyFlags(flags) and "friendly" or "enemy"
        row = CombatLogCollector.CreatePlayerRow(guid, name, team)
        players[guid] = row
    end

    if name and name ~= "" then
        row.name = name
    end

    return row
end

--- Adds a numeric stat to one player row when the amount is readable.
--- @param row table|nil
--- @param field string
--- @param amount number|nil
function CombatLogCollector.AddAmount(row, field, amount)
    if not row or not amount or amount <= 0 then
        return
    end

    row[field] = (row[field] or 0) + amount
end

--- Handles one combat log event while a match is being tracked.
function CombatLogCollector.OnCombatLogEvent()
    if not CombatLogCollector.active then
        return
    end

    local timestamp, subEvent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags =
        CombatLogGetCurrentEventInfo()

    local amountIndex = DAMAGE_SUBEVENTS[subEvent] or HEAL_SUBEVENTS[subEvent]
    if amountIndex then
        local amount = CombatLogCollector.GetAccessibleNumber(select(amountIndex, CombatLogGetCurrentEventInfo()))
        if DAMAGE_SUBEVENTS[subEvent]
            and CombatLogCollector.IsPlayerGuid(sourceGUID)
            and CombatLogCollector.IsPlayerGuid(destGUID) then
            local sourceRow = CombatLogCollector.GetPlayerRow(sourceGUID, sourceName, sourceFlags)
            local destRow = CombatLogCollector.GetPlayerRow(destGUID, destName, destFlags)
            if amount and amount > 0 then
                CombatLogCollector.AddAmount(sourceRow, "damage", amount)
                CombatLogCollector.AddAmount(destRow, "damageTaken", amount)
            end
        elseif HEAL_SUBEVENTS[subEvent] and CombatLogCollector.IsPlayerGuid(sourceGUID) then
            local sourceRow = CombatLogCollector.GetPlayerRow(sourceGUID, sourceName, sourceFlags)
            if amount and amount > 0 then
                CombatLogCollector.AddAmount(sourceRow, "healing", amount)
            end
        end
    elseif subEvent == "SPELL_INTERRUPT" and CombatLogCollector.IsPlayerGuid(sourceGUID) then
        local sourceRow = CombatLogCollector.GetPlayerRow(sourceGUID, sourceName, sourceFlags)
        if sourceRow then
            sourceRow.interrupts = (sourceRow.interrupts or 0) + 1
        end
    elseif subEvent == "SPELL_AURA_APPLIED" then
        local auraType = select(15, CombatLogGetCurrentEventInfo())
        if auraType == "DEBUFF"
            and CombatLogCollector.IsPlayerGuid(sourceGUID)
            and CombatLogCollector.IsPlayerGuid(destGUID) then
            if CombatLogCollector.IsFriendlyFlags(sourceFlags)
                and not CombatLogCollector.IsFriendlyFlags(destFlags) then
                local sourceRow = CombatLogCollector.GetPlayerRow(sourceGUID, sourceName, sourceFlags)
                if sourceRow then
                    sourceRow.ccApplied = (sourceRow.ccApplied or 0) + 1
                end
            elseif not CombatLogCollector.IsFriendlyFlags(sourceFlags)
                and CombatLogCollector.IsFriendlyFlags(destFlags) then
                local destRow = CombatLogCollector.GetPlayerRow(destGUID, destName, destFlags)
                if destRow then
                    destRow.ccTaken = (destRow.ccTaken or 0) + 1
                end
            end
        end
    elseif subEvent == "UNIT_DIED" and CombatLogCollector.IsPlayerGuid(destGUID) then
        local destRow = CombatLogCollector.GetPlayerRow(destGUID, destName, destFlags)
        if destRow then
            destRow.deaths = (destRow.deaths or 0) + 1
        end

        local elapsed = 0
        if CombatLogCollector.startTimestamp and timestamp then
            elapsed = math.max(0, timestamp - CombatLogCollector.startTimestamp)
        end

        table.insert(CombatLogCollector.killEvents, {
            elapsed = elapsed,
            victim = destName,
            killer = sourceName,
        })
    end
end

--- Clears the in-memory combat log buffer without saving.
function CombatLogCollector.Reset()
    CombatLogCollector.active = false
    CombatLogCollector.startedAt = nil
    CombatLogCollector.startTimestamp = nil
    CombatLogCollector.players = {}
    CombatLogCollector.killEvents = {}
end

--- Starts combat log capture for one active match.
--- @param matchContext table|nil
function CombatLogCollector.StartMatch(matchContext)
    if not CombatLogCollector.IsEnabled() then
        CombatLogCollector.Reset()
        return
    end

    CombatLogCollector.Reset()
    CombatLogCollector.active = true
    CombatLogCollector.startedAt = matchContext and matchContext.startedAt or time()
    CombatLogCollector.startTimestamp = GetTime()

    if CombatLogCollector.frame then
        CombatLogCollector.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

--- Stops combat log capture without building a summary.
function CombatLogCollector.StopMatch()
    CombatLogCollector.Reset()

    if CombatLogCollector.frame then
        CombatLogCollector.frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

--- Resolves friendly/enemy team for one roster participant.
--- @param participant table|nil
--- @param fallbackTeam string|nil
--- @return string
function CombatLogCollector.ResolveParticipantTeam(participant, fallbackTeam)
    if participant and participant.isLocalPlayer then
        return "friendly"
    end

    if participant and (participant.team == "friendly" or participant.team == "enemy") then
        return participant.team
    end

    if fallbackTeam == "friendly" or fallbackTeam == "enemy" then
        return fallbackTeam
    end

    return "enemy"
end

--- Builds one export row from combat stats and optional roster metadata.
--- @param guid string|nil
--- @param combatRow table|nil
--- @param participant table|nil
--- @return table
function CombatLogCollector.BuildPlayerSummaryRow(guid, combatRow, participant)
    local team = CombatLogCollector.ResolveParticipantTeam(participant, combatRow and combatRow.team)
    local damage = combatRow and combatRow.damage or 0
    local healing = combatRow and combatRow.healing or 0
    local damageTaken = combatRow and combatRow.damageTaken or 0

    if participant then
        if participant.damageDone and participant.damageDone > damage then
            damage = participant.damageDone
        end
        if participant.healingDone and participant.healingDone > healing then
            healing = participant.healingDone
        end
    end

    return {
        guid = guid or (participant and participant.guid) or nil,
        name = (combatRow and combatRow.name) or (participant and participant.name) or "Unknown",
        class = participant and participant.class or nil,
        spec = participant and participant.spec or nil,
        team = team,
        isLocalPlayer = participant and participant.isLocalPlayer or false,
        damage = damage,
        healing = healing,
        damageTaken = damageTaken,
        interrupts = combatRow and combatRow.interrupts or 0,
        ccApplied = combatRow and combatRow.ccApplied or 0,
        ccTaken = combatRow and combatRow.ccTaken or 0,
        deaths = combatRow and combatRow.deaths or 0,
    }
end

--- Builds a compact export-friendly combat summary for one match.
--- @param roster table[]|nil
--- @return table|nil
function CombatLogCollector.BuildSummary(roster)
    local endedAt = time()
    local duration = CombatLogCollector.startedAt and math.max(0, endedAt - CombatLogCollector.startedAt) or nil
    local rosterByGuid = {}
    local rosterByName = {}
    local includedGuids = {}

    for _, participant in ipairs(roster or {}) do
        if participant.guid then
            rosterByGuid[participant.guid] = participant
        end
        if participant.name then
            rosterByName[participant.name] = participant
        end
    end

    local playerRows = {}
    for guid, row in pairs(CombatLogCollector.players) do
        includedGuids[guid] = true
        local participant = rosterByGuid[guid] or rosterByName[row.name]
        table.insert(playerRows, CombatLogCollector.BuildPlayerSummaryRow(guid, row, participant))
    end

    for _, participant in ipairs(roster or {}) do
        local guid = participant.guid
        if guid then
            if not includedGuids[guid] then
                includedGuids[guid] = true
                table.insert(playerRows, CombatLogCollector.BuildPlayerSummaryRow(guid, nil, participant))
            end
        elseif participant.name then
            local existing = false
            for _, row in ipairs(playerRows) do
                if row.name == participant.name then
                    existing = true
                    break
                end
            end

            if not existing then
                table.insert(playerRows, CombatLogCollector.BuildPlayerSummaryRow(nil, nil, participant))
            end
        end
    end

    table.sort(playerRows, function(a, b)
        if a.team == b.team then
            if a.damage == b.damage then
                return (a.name or "") < (b.name or "")
            end
            return a.damage > b.damage
        end

        return a.team == "friendly"
    end)

    if #playerRows == 0 then
        CombatLogCollector.StopMatch()
        return nil
    end

    local summary = {
        startedAt = CombatLogCollector.startedAt,
        endedAt = endedAt,
        duration = duration,
        killEvents = CombatLogCollector.killEvents,
        players = playerRows,
    }

    CombatLogCollector.StopMatch()
    return summary
end

--- Initializes the combat log collector frame.
function CombatLogCollector.Init()
    if CombatLogCollector.frame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            CombatLogCollector.OnCombatLogEvent()
        end
    end)

    CombatLogCollector.frame = frame
end
