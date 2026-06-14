--- Captures per-match combat summaries from live combat log events.
--- @class PvPLedger
local PVL = PvPLedger

PVL.CombatLogCollector = PVL.CombatLogCollector or {}
local CombatLogCollector = PVL.CombatLogCollector

CombatLogCollector.frame = CombatLogCollector.frame or nil
CombatLogCollector.active = CombatLogCollector.active or false
CombatLogCollector.startedAt = CombatLogCollector.startedAt or nil
CombatLogCollector.startTimestamp = CombatLogCollector.startTimestamp or nil
CombatLogCollector.eventCount = CombatLogCollector.eventCount or 0
CombatLogCollector.interruptCount = CombatLogCollector.interruptCount or 0
CombatLogCollector.segmentCount = CombatLogCollector.segmentCount or 1
CombatLogCollector.players = CombatLogCollector.players or {}
CombatLogCollector.killEvents = CombatLogCollector.killEvents or {}
CombatLogCollector.persistTicker = CombatLogCollector.persistTicker or nil
CombatLogCollector.matchContext = CombatLogCollector.matchContext or nil
CombatLogCollector.damageMeterSynced = CombatLogCollector.damageMeterSynced or false
CombatLogCollector.lastDamageMeterSyncAt = CombatLogCollector.lastDamageMeterSyncAt or nil
CombatLogCollector.liveSyncTicker = CombatLogCollector.liveSyncTicker or nil
CombatLogCollector.useDamageMeterPolling = CombatLogCollector.useDamageMeterPolling ~= false
CombatLogCollector.rawCombatEvents = CombatLogCollector.rawCombatEvents or {}
CombatLogCollector.seenCcAuras = CombatLogCollector.seenCcAuras or {}
CombatLogCollector.seenLossOfControl = CombatLogCollector.seenLossOfControl or {}

local PERSIST_INTERVAL_SECONDS = 15
local MAX_RAW_COMBAT_EVENTS = 4000
local LOSS_OF_CONTROL_INTERRUPT_TYPE = "SCHOOL_INTERRUPT"
local LIVE_SYNC_INTERVAL_SECONDS = 3
local DAMAGE_METER_SESSION_OVERALL = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall or 0
local DAMAGE_METER_SESSION_CURRENT = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
local DAMAGE_METER_SYNC_TYPES = {
    [Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0] = "damage",
    [Enum and Enum.DamageMeterType and Enum.DamageMeterType.HealingDone or 2] = "healing",
    [Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageTaken or 7] = "damageTaken",
    [Enum and Enum.DamageMeterType and Enum.DamageMeterType.Deaths or 9] = "deaths",
}
local DAMAGE_METER_SCOREBOARD_SUPPLEMENT_TYPES = {
    [Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageTaken or 7] = "damageTaken",
}
local SUPPLEMENT_COUNT_FIELDS = { "interrupts", "dispels", "deaths", "damageTaken" }
local DAMAGE_METER_TYPE_INTERRUPTS = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Interrupts or 5
local DAMAGE_METER_TYPE_DISPELS = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Dispels or 6
local DAMAGE_METER_SPELL_EXPORT_TYPES = {
    { meterType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0, key = "damage" },
    { meterType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.HealingDone or 2, key = "healing" },
    { meterType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageTaken or 7, key = "damageTaken" },
    { meterType = DAMAGE_METER_TYPE_INTERRUPTS, key = "interrupts" },
    { meterType = DAMAGE_METER_TYPE_DISPELS, key = "dispels" },
    { meterType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Deaths or 9, key = "deaths" },
}
local MERGE_COUNT_FIELDS = { "interrupts", "dispels", "deaths", "ccApplied", "ccTaken" }
local MERGE_AMOUNT_FIELDS = { "damage", "healing", "damageTaken" }
local COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400
local DAMAGE_METER_SESSION_EXPIRED = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Expired or 2
local MATCH_WINDOW_TOLERANCE_SECONDS = 45
local MAX_COMBAT_SEGMENT_ARCHIVE = 32
local SEGMENT_ARCHIVE_MAX_AGE_SECONDS = 3 * 3600

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

--- Returns true when Blizzard's built-in damage meter API is available.
--- Midnight PvP combat stats are exposed here instead of COMBAT_LOG_EVENT_UNFILTERED.
--- @return boolean
function CombatLogCollector.IsDamageMeterAvailable()
    return C_DamageMeter
        and type(C_DamageMeter.GetCombatSessionFromType) == "function"
        and Enum
        and Enum.DamageMeterType
end

--- Returns the active combat data source label for debug output.
--- @return string
function CombatLogCollector.GetDataSourceLabel()
    local hasCleu = (CombatLogCollector.eventCount or 0) > 0
    local hasDamageMeter = CombatLogCollector.damageMeterSynced == true

    if hasCleu and hasDamageMeter then
        return "both"
    end

    if hasDamageMeter then
        return "damageMeter"
    end

    if hasCleu then
        return "cleu"
    end

    if CombatLogCollector.IsDamageMeterAvailable() then
        return "damageMeter"
    end

    return "none"
end

--- Returns one readable player name from a damage meter source row.
--- Midnight may return secret strings that cannot be compared to "" directly.
--- @param source table|nil
--- @return string|nil
function CombatLogCollector.GetDamageMeterSourceName(source)
    if type(source) ~= "table" then
        return nil
    end

    local name = source.name
    if name == nil then
        if source.isLocalPlayer and UnitName then
            return UnitName("player")
        end
        return nil
    end

    if issecretvalue and issecretvalue(name) then
        if canaccessvalue and canaccessvalue(name) then
            return name
        end
        if source.isLocalPlayer and UnitName then
            return UnitName("player")
        end
        return nil
    end

    if type(name) ~= "string" or name == "" then
        return nil
    end

    return name
end

--- Returns one readable amount from a damage meter source row.
--- @param source table|nil
--- @return number|nil
function CombatLogCollector.GetDamageMeterSourceAmount(source)
    if type(source) ~= "table" then
        return nil
    end

    return CombatLogCollector.GetAccessibleNumber(source.totalAmount or source.total)
end

--- Returns one safe numeric amount from a damage meter source row.
--- @param source table|nil
--- @return number|nil
function CombatLogCollector.GetSafeDamageMeterAmount(source)
    if type(source) ~= "table" then
        return nil
    end

    local amount = CombatLogCollector.GetAccessibleNumber(source.totalAmount or source.total)
    if not amount or amount <= 0 then
        return nil
    end

    return amount
end

--- Returns one damage meter session for a session type and meter type.
--- @param sessionType number
--- @param meterType number
--- @return table|nil
function CombatLogCollector.GetDamageMeterSession(sessionType, meterType)
    if not CombatLogCollector.IsDamageMeterAvailable() then
        return nil
    end

    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterType)
    if not ok or type(session) ~= "table" then
        return nil
    end

    return session
end

--- Returns one damage meter session for an expired segment id.
--- @param sessionId number
--- @param meterType number
--- @return table|nil
function CombatLogCollector.GetDamageMeterSessionById(sessionId, meterType)
    if not CombatLogCollector.IsDamageMeterAvailable()
        or not sessionId
        or type(C_DamageMeter.GetCombatSessionFromID) ~= "function" then
        return nil
    end

    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionId, meterType)
    if not ok or type(session) ~= "table" then
        return nil
    end

    return session
end

--- Returns the GUID used for per-player damage meter spell lookups.
--- @param source table|nil
--- @return string|nil
function CombatLogCollector.ResolveDamageMeterLookupGuid(source)
    if type(source) ~= "table" then
        return nil
    end

    if source.isLocalPlayer and UnitGUID then
        local playerGUID = UnitGUID("player")
        if CombatLogCollector.CanUseGuid(playerGUID) then
            return playerGUID
        end
    end

    if CombatLogCollector.CanUseGuid(source.sourceGUID) then
        return source.sourceGUID
    end

    return nil
end

--- Applies one damage meter source row to the in-memory player map.
--- @param source table
--- @param fieldName string
--- @return boolean applied
function CombatLogCollector.ApplyDamageMeterSource(source, fieldName)
    local name = CombatLogCollector.GetDamageMeterSourceName(source)
    local lookupGUID = CombatLogCollector.ResolveDamageMeterLookupGuid(source)
    if not name and not lookupGUID then
        return false
    end

    local amount = CombatLogCollector.GetSafeDamageMeterAmount(source)
    if fieldName == "deaths" then
        amount = CombatLogCollector.SanitizeInterruptCount(source.totalAmount or source.total or source.count)
    end
    if not amount then
        return false
    end

    local row = CombatLogCollector.GetPlayerRow(
        source.sourceGUID,
        name,
        source.isLocalPlayer and COMBATLOG_OBJECT_TYPE_PLAYER or nil
    )
    if not row then
        return false
    end

    if source.isLocalPlayer then
        row.team = "friendly"
    end

    row[fieldName] = math.max(row[fieldName] or 0, amount)
    return true
end

--- Returns spell data for one damage meter source row.
--- @param sessionType number|nil
--- @param sessionId number|nil
--- @param meterType number
--- @param sourceGUID string|nil
--- @return table|nil
function CombatLogCollector.GetDamageMeterSourceSpells(sessionType, sessionId, meterType, sourceGUID)
    if not CombatLogCollector.CanUseGuid(sourceGUID) or not CombatLogCollector.IsDamageMeterAvailable() then
        return nil
    end

    local ok, spells
    if sessionId and type(C_DamageMeter.GetCombatSessionSourceFromID) == "function" then
        ok, spells = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionId, meterType, sourceGUID)
    elseif sessionType ~= nil and type(C_DamageMeter.GetCombatSessionSourceFromType) == "function" then
        ok, spells = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, sourceGUID)
    end

    if ok and type(spells) == "table" then
        return spells
    end

    return nil
end

--- Clamps one interrupt total to a realistic per-match range.
--- @param amount number|nil
--- @return number|nil
function CombatLogCollector.SanitizeInterruptCount(amount)
    amount = CombatLogCollector.GetAccessibleNumber(amount)
    if not amount or amount <= 0 then
        return nil
    end

    amount = math.floor(amount + 0.5)
    if amount > 100 then
        return nil
    end

    return amount
end

--- Returns interrupt count from one damage meter interrupt-session source row.
--- @param source table|nil
--- @return number|nil
function CombatLogCollector.GetDamageMeterInterruptCount(source)
    if type(source) ~= "table" then
        return nil
    end

    return CombatLogCollector.SanitizeInterruptCount(
        source.totalAmount or source.total or source.count
    )
end

--- Returns the summed kick count from one damage meter interrupt spell container.
--- @param spellContainer table|nil
--- @return number|nil
function CombatLogCollector.SumDamageMeterInterruptSpellCount(spellContainer)
    if type(spellContainer) ~= "table" or type(spellContainer.combatSpells) ~= "table" then
        return nil
    end

    local countOk, spellCount = pcall(function()
        return #spellContainer.combatSpells
    end)
    if not countOk or not spellCount or spellCount <= 0 then
        return nil
    end

    local total = 0
    for index = 1, spellCount do
        local spell = spellContainer.combatSpells[index]
        local count = CombatLogCollector.GetAccessibleNumber(spell.count)
        if not count or count <= 0 then
            count = CombatLogCollector.GetAccessibleNumber(spell.totalAmount or spell.total)
        end
        if count and count > 0 and count <= 50 then
            total = total + math.floor(count)
        end
    end

    return CombatLogCollector.SanitizeInterruptCount(total)
end

--- Applies one interrupt count to the in-memory player map.
--- @param source table
--- @param sessionType number|nil
--- @param sessionId number|nil
--- @return boolean applied
function CombatLogCollector.ApplyInterruptCountFromSource(source, sessionType, sessionId)
    local name = CombatLogCollector.GetDamageMeterSourceName(source)
    local lookupGUID = CombatLogCollector.ResolveDamageMeterLookupGuid(source)
    if not name and not lookupGUID then
        return false
    end

    local amount = CombatLogCollector.GetDamageMeterInterruptCount(source)

    if (not amount or amount <= 0) and lookupGUID then
        local lookupTypes = {}
        if sessionType ~= nil then
            table.insert(lookupTypes, sessionType)
        end
        table.insert(lookupTypes, DAMAGE_METER_SESSION_OVERALL)
        table.insert(lookupTypes, DAMAGE_METER_SESSION_CURRENT)

        for _, lookupSessionType in ipairs(lookupTypes) do
            local spells = CombatLogCollector.GetDamageMeterSourceSpells(
                lookupSessionType,
                sessionId,
                DAMAGE_METER_TYPE_INTERRUPTS,
                lookupGUID
            )
            amount = CombatLogCollector.SumDamageMeterInterruptSpellCount(spells)
            if amount and amount > 0 then
                break
            end
        end
    end

    amount = CombatLogCollector.SanitizeInterruptCount(amount)
    if not amount or amount <= 0 then
        return false
    end

    local creditGuid = lookupGUID or source.sourceGUID
    local flags = nil
    if source.isLocalPlayer or CombatLogCollector.IsAccessibleName(name) then
        flags = COMBATLOG_OBJECT_TYPE_PLAYER
    end

    local row = CombatLogCollector.GetPlayerRow(creditGuid, name, flags)
    if not row then
        return false
    end

    if source.isLocalPlayer then
        row.team = "friendly"
    end

    row.interrupts = math.max(row.interrupts or 0, amount)
    return true
end

--- Imports interrupt counts from Blizzard's per-player damage meter spell data.
--- @param sessionType number|nil
--- @param sessionId number|nil
--- @return boolean synced
function CombatLogCollector.SyncInterruptsFromDamageMeter(sessionType, sessionId)
    local synced = false
    local interruptSession
    if sessionId then
        interruptSession = CombatLogCollector.GetDamageMeterSessionById(sessionId, DAMAGE_METER_TYPE_INTERRUPTS)
    else
        interruptSession = CombatLogCollector.GetDamageMeterSession(sessionType, DAMAGE_METER_TYPE_INTERRUPTS)
    end

    CombatLogCollector.ForEachDamageMeterSource(interruptSession, function(source)
        if CombatLogCollector.ApplyInterruptCountFromSource(source, sessionType, sessionId) then
            synced = true
        end
    end)

    return synced
end

--- Returns dispel count from one damage meter dispel-session source row.
--- @param source table|nil
--- @return number|nil
function CombatLogCollector.GetDamageMeterDispelCount(source)
    return CombatLogCollector.GetDamageMeterInterruptCount(source)
end

--- Returns the summed dispel count from one damage meter dispel spell container.
--- @param spellContainer table|nil
--- @return number|nil
function CombatLogCollector.SumDamageMeterDispelSpellCount(spellContainer)
    return CombatLogCollector.SumDamageMeterInterruptSpellCount(spellContainer)
end

--- Applies one dispel count to the in-memory player map.
--- @param source table
--- @param sessionType number|nil
--- @param sessionId number|nil
--- @return boolean applied
function CombatLogCollector.ApplyDispelCountFromSource(source, sessionType, sessionId)
    local name = CombatLogCollector.GetDamageMeterSourceName(source)
    local lookupGUID = CombatLogCollector.ResolveDamageMeterLookupGuid(source)
    if not name and not lookupGUID then
        return false
    end

    local amount = CombatLogCollector.GetDamageMeterDispelCount(source)

    if (not amount or amount <= 0) and lookupGUID then
        local lookupTypes = {}
        if sessionType ~= nil then
            table.insert(lookupTypes, sessionType)
        end
        table.insert(lookupTypes, DAMAGE_METER_SESSION_OVERALL)
        table.insert(lookupTypes, DAMAGE_METER_SESSION_CURRENT)

        for _, lookupSessionType in ipairs(lookupTypes) do
            local spells = CombatLogCollector.GetDamageMeterSourceSpells(
                lookupSessionType,
                sessionId,
                DAMAGE_METER_TYPE_DISPELS,
                lookupGUID
            )
            amount = CombatLogCollector.SumDamageMeterDispelSpellCount(spells)
            if amount and amount > 0 then
                break
            end
        end
    end

    amount = CombatLogCollector.SanitizeInterruptCount(amount)
    if not amount or amount <= 0 then
        return false
    end

    local creditGuid = lookupGUID or source.sourceGUID
    local flags = nil
    if source.isLocalPlayer or CombatLogCollector.IsAccessibleName(name) then
        flags = COMBATLOG_OBJECT_TYPE_PLAYER
    end

    local row = CombatLogCollector.GetPlayerRow(creditGuid, name, flags)
    if not row then
        return false
    end

    if source.isLocalPlayer then
        row.team = "friendly"
    end

    row.dispels = math.max(row.dispels or 0, amount)
    return true
end

--- Imports dispel counts from Blizzard's per-player damage meter spell data.
--- @param sessionType number|nil
--- @param sessionId number|nil
--- @return boolean synced
function CombatLogCollector.SyncDispelsFromDamageMeter(sessionType, sessionId)
    local synced = false
    local dispelSession
    if sessionId then
        dispelSession = CombatLogCollector.GetDamageMeterSessionById(sessionId, DAMAGE_METER_TYPE_DISPELS)
    else
        dispelSession = CombatLogCollector.GetDamageMeterSession(sessionType, DAMAGE_METER_TYPE_DISPELS)
    end

    CombatLogCollector.ForEachDamageMeterSource(dispelSession, function(source)
        if CombatLogCollector.ApplyDispelCountFromSource(source, sessionType, sessionId) then
            synced = true
        end
    end)

    return synced
end

--- Iterates damage meter sources when Blizzard exposes a readable source table.
--- @param session table|nil
--- @param callback fun(source: table)
function CombatLogCollector.ForEachDamageMeterSource(session, callback)
    if type(session) ~= "table" or type(callback) ~= "function" then
        return
    end

    local sources = session.combatSources
    if type(sources) ~= "table" then
        return
    end

    local visited = {}
    local function visitSource(source)
        if type(source) ~= "table" or visited[source] then
            return
        end

        visited[source] = true
        callback(source)
    end

    local countOk, sourceCount = pcall(function()
        return #sources
    end)
    if countOk and sourceCount and sourceCount > 0 then
        for index = 1, sourceCount do
            visitSource(sources[index])
        end
    end

    for _, source in pairs(sources) do
        visitSource(source)
    end
end

--- Imports player combat totals from Blizzard's damage meter sessions.
--- @return boolean synced
function CombatLogCollector.SyncFromDamageMeter()
    if not CombatLogCollector.IsDamageMeterAvailable() then
        return false
    end

    local ok, syncedAny = pcall(function()
        local synced = false
        local sessionTypes = {
            DAMAGE_METER_SESSION_OVERALL,
            DAMAGE_METER_SESSION_CURRENT,
        }

        for _, sessionType in ipairs(sessionTypes) do
            for meterType, fieldName in pairs(DAMAGE_METER_SYNC_TYPES) do
                local session = CombatLogCollector.GetDamageMeterSession(sessionType, meterType)
                CombatLogCollector.ForEachDamageMeterSource(session, function(source)
                    if CombatLogCollector.ApplyDamageMeterSource(source, fieldName) then
                        synced = true
                    end
                end)
            end

            if CombatLogCollector.SyncInterruptsFromDamageMeter(sessionType, nil) then
                synced = true
            end

            if CombatLogCollector.SyncDispelsFromDamageMeter(sessionType, nil) then
                synced = true
            end
        end

        if C_DamageMeter.GetAvailableCombatSessions then
            local sessionsOk, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
            if sessionsOk and type(sessions) == "table" and #sessions > 0 then
                local latest = sessions[#sessions]
                local sessionId = latest and (latest.sessionID or latest.sessionId)
                if sessionId then
                    for meterType, fieldName in pairs(DAMAGE_METER_SYNC_TYPES) do
                        local session = CombatLogCollector.GetDamageMeterSessionById(sessionId, meterType)
                        CombatLogCollector.ForEachDamageMeterSource(session, function(source)
                            if CombatLogCollector.ApplyDamageMeterSource(source, fieldName) then
                                synced = true
                            end
                        end)
                    end

                    if CombatLogCollector.SyncInterruptsFromDamageMeter(nil, sessionId) then
                        synced = true
                    end

                    if CombatLogCollector.SyncDispelsFromDamageMeter(nil, sessionId) then
                        synced = true
                    end
                end
            end
        end

        if synced then
            CombatLogCollector.damageMeterSynced = true
            CombatLogCollector.lastDamageMeterSyncAt = GetTime()

            local interruptTotal = 0
            for _, row in pairs(CombatLogCollector.players) do
                interruptTotal = interruptTotal + (row.interrupts or 0)
            end
            CombatLogCollector.interruptCount = interruptTotal
        end

        return synced
    end)

    return ok and syncedAny == true
end

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

--- Returns true when addon code can read one combat log GUID.
--- @param guid string|nil
--- @return boolean
function CombatLogCollector.CanUseGuid(guid)
    if guid == nil then
        return false
    end

    if issecretvalue and issecretvalue(guid) then
        return canaccessvalue and canaccessvalue(guid) or false
    end

    return type(guid) == "string" and guid ~= ""
end

--- Returns true when a name value is safe to read or normalize.
--- @param name any
--- @return boolean
function CombatLogCollector.IsAccessibleName(name)
    if name == nil then
        return false
    end

    if issecretvalue and issecretvalue(name) then
        return canaccessvalue and canaccessvalue(name) or false
    end

    return type(name) == "string" and name ~= ""
end

--- Returns true when a combat log GUID belongs to a player character.
--- @param guid string|nil
--- @return boolean
function CombatLogCollector.IsPlayerGuid(guid)
    if not CombatLogCollector.CanUseGuid(guid) then
        return false
    end

    local ok, isPlayer = pcall(function()
        return guid:find("^Player%-") ~= nil
    end)

    return ok and isPlayer or false
end

--- Returns true when combat log flags identify a player unit.
--- @param flags number|nil
--- @return boolean
function CombatLogCollector.IsPlayerSourceFlags(flags)
    if not flags or not bit.band then
        return false
    end

    return bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0
end

--- Returns a stable storage key for one combat-log player row.
--- @param guid string|nil
--- @param name string|nil
--- @param flags number|nil
--- @return string|nil
function CombatLogCollector.ResolveStorageKey(guid, name, flags)
    if CombatLogCollector.IsPlayerGuid(guid) then
        return guid
    end

    if CombatLogCollector.IsAccessibleName(name) and CombatLogCollector.IsPlayerSourceFlags(flags) then
        local nameKey = CombatLogCollector.NormalizeName(name)
        if nameKey then
            return "name:" .. nameKey
        end
    end

    if CombatLogCollector.IsAccessibleName(name) and CombatLogCollector.IsLikelyPlayerName(name, guid, flags) then
        local nameKey = CombatLogCollector.NormalizeName(name)
        if nameKey then
            return "name:" .. nameKey
        end
    end

    if CombatLogCollector.IsAccessibleName(name) then
        local matchCollector = PVL.MatchCollector
        if CombatLogCollector.IsInLivePvpContext()
            or (matchCollector
                and matchCollector.IsInCollectiblePvpInstance
                and matchCollector.IsInCollectiblePvpInstance()) then
            local nameKey = CombatLogCollector.NormalizeName(name)
            if nameKey then
                return "name:" .. nameKey
            end
        end
    end

    return nil
end

--- Returns true when a combat log source should be tracked as a player row.
--- @param name string|nil
--- @param guid string|nil
--- @param flags number|nil
--- @return boolean
function CombatLogCollector.IsLikelyPlayerName(name, guid, flags)
    if not CombatLogCollector.IsAccessibleName(name) then
        return false
    end

    if CombatLogCollector.IsPlayerSourceFlags(flags) then
        return true
    end

    if type(guid) == "string" and guid ~= "" then
        if not CombatLogCollector.CanUseGuid(guid) then
            local matchCollector = PVL.MatchCollector
            return matchCollector
                and matchCollector.IsInCollectiblePvpInstance
                and matchCollector.IsInCollectiblePvpInstance()
        end

        if guid:find("^Pet%-") or guid:find("^Totem%-") or guid:find("^Vehicle%-") then
            return false
        end
    end

    local matchCollector = PVL.MatchCollector
    return matchCollector
        and matchCollector.IsInCollectiblePvpInstance
        and matchCollector.IsInCollectiblePvpInstance()
end

--- Returns a realm-stripped lowercase name key for roster matching.
--- @param name string|nil
--- @return string|nil
function CombatLogCollector.NormalizeName(name)
    if name == nil then
        return nil
    end

    if issecretvalue and issecretvalue(name) then
        if not canaccessvalue or not canaccessvalue(name) then
            return nil
        end
    elseif type(name) ~= "string" or name == "" then
        return nil
    end

    local ok, shortName = pcall(Ambiguate, name, "none")
    if not ok or shortName == nil then
        return nil
    end

    if issecretvalue and issecretvalue(shortName) then
        if not canaccessvalue or not canaccessvalue(shortName) then
            return nil
        end
    elseif type(shortName) ~= "string" or shortName == "" then
        return nil
    end

    local baseName = shortName:match("^(.-)%-.+$") or shortName
    return string.lower(baseName)
end

--- Returns a deep copy of one tracked player row.
--- @param row table|nil
--- @return table|nil
function CombatLogCollector.ClonePlayerRow(row)
    if type(row) ~= "table" then
        return nil
    end

    return {
        guid = row.guid,
        name = row.name,
        team = row.team,
        damage = row.damage or 0,
        healing = row.healing or 0,
        damageTaken = row.damageTaken or 0,
        interrupts = row.interrupts or 0,
        dispels = row.dispels or 0,
        deaths = row.deaths or 0,
        ccApplied = row.ccApplied or 0,
        ccTaken = row.ccTaken or 0,
    }
end

--- Returns true when one spell id is classified as crowd control.
--- @param spellId number|nil
--- @return boolean
function CombatLogCollector.IsCrowdControlSpell(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then
        return false
    end

    if C_Spell and type(C_Spell.IsSpellCrowdControl) == "function" then
        local ok, isCrowdControl = pcall(C_Spell.IsSpellCrowdControl, spellId)
        return ok and isCrowdControl == true
    end

    return false
end

--- Appends one compact combat-log event to the in-memory raw event buffer.
--- @param subEvent string|nil
--- @param sourceGUID string|nil
--- @param sourceName string|nil
--- @param destGUID string|nil
--- @param destName string|nil
--- @param spellId number|nil
--- @param auraType string|nil
--- @param amount number|nil
function CombatLogCollector.AppendRawCombatEvent(subEvent, sourceGUID, sourceName, destGUID, destName, spellId, auraType, amount)
    CombatLogCollector.rawCombatEvents = CombatLogCollector.rawCombatEvents or {}
    if #CombatLogCollector.rawCombatEvents >= MAX_RAW_COMBAT_EVENTS then
        return
    end

    table.insert(CombatLogCollector.rawCombatEvents, {
        t = GetTime(),
        subEvent = subEvent,
        sourceGUID = sourceGUID,
        sourceName = sourceName,
        destGUID = destGUID,
        destName = destName,
        spellId = spellId,
        auraType = auraType,
        amount = amount,
    })
end

--- Returns a copy of one raw combat-log event list.
--- @param events table[]|nil
--- @return table[]
function CombatLogCollector.CloneRawCombatEvents(events)
    local copy = {}
    for _, event in ipairs(events or {}) do
        table.insert(copy, {
            t = event.t,
            subEvent = event.subEvent,
            sourceGUID = event.sourceGUID,
            sourceName = event.sourceName,
            destGUID = event.destGUID,
            destName = event.destName,
            spellId = event.spellId,
            auraType = event.auraType,
            amount = event.amount,
        })
    end
    return copy
end

--- Serializes one damage meter spell container for export.
--- @param spellContainer table|nil
--- @return table[]|nil
function CombatLogCollector.SerializeSpellContainer(spellContainer)
    if type(spellContainer) ~= "table" or type(spellContainer.combatSpells) ~= "table" then
        return nil
    end

    local spells = {}
    for _, spell in ipairs(spellContainer.combatSpells) do
        if type(spell) == "table" then
            table.insert(spells, {
                spellID = spell.spellID,
                totalAmount = CombatLogCollector.GetAccessibleNumber(spell.totalAmount),
                amountPerSecond = CombatLogCollector.GetAccessibleNumber(spell.amountPerSecond),
                overkillAmount = CombatLogCollector.GetAccessibleNumber(spell.overkillAmount),
                isAvoidable = spell.isAvoidable,
                isDeadly = spell.isDeadly,
            })
        end
    end

    if #spells == 0 then
        return nil
    end

    return spells
end

--- Collects per-spell damage meter breakdowns for one player GUID.
--- @param guid string|nil
--- @param sessionId number|nil
--- @return table|nil
function CombatLogCollector.CollectPlayerSpellBreakdown(guid, sessionId)
    if not CombatLogCollector.CanUseGuid(guid) or not CombatLogCollector.IsDamageMeterAvailable() then
        return nil
    end

    local breakdown = nil
    local sessionTypes = { DAMAGE_METER_SESSION_CURRENT, DAMAGE_METER_SESSION_OVERALL }

    for _, exportType in ipairs(DAMAGE_METER_SPELL_EXPORT_TYPES) do
        local spells = nil
        for _, sessionType in ipairs(sessionTypes) do
            spells = CombatLogCollector.GetDamageMeterSourceSpells(
                sessionType,
                sessionId,
                exportType.meterType,
                guid
            )
            if spells then
                break
            end
        end

        local serialized = CombatLogCollector.SerializeSpellContainer(spells)
        if serialized then
            breakdown = breakdown or {}
            breakdown[exportType.key] = serialized
        end
    end

    return breakdown
end

--- Increments crowd-control applied/taken counters for one aura application.
--- @param sourceGUID string|nil
--- @param sourceName string|nil
--- @param sourceFlags number|nil
--- @param destGUID string|nil
--- @param destName string|nil
--- @param destFlags number|nil
--- @param spellId number|nil
function CombatLogCollector.ProcessCrowdControlAppliedEvent(sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId)
    if not CombatLogCollector.IsCrowdControlSpell(spellId) then
        return
    end

    local sourceRow = CombatLogCollector.GetPlayerRow(sourceGUID, sourceName, sourceFlags)
    if sourceRow then
        CombatLogCollector.AddCount(sourceRow, "ccApplied")
    end

    local destRow = CombatLogCollector.GetPlayerRow(destGUID, destName, destFlags)
    if destRow then
        CombatLogCollector.AddCount(destRow, "ccTaken")
    end
end

--- Clears dedupe state used by aura and loss-of-control tracking.
function CombatLogCollector.ResetCrowdControlTracking()
    CombatLogCollector.seenCcAuras = {}
    CombatLogCollector.seenLossOfControl = {}
end

--- Returns true when one loss-of-control type should count as crowd control.
--- @param locType string|nil
--- @return boolean
function CombatLogCollector.ShouldCountLossOfControlType(locType)
    if type(locType) ~= "string" or locType == "" then
        return false
    end

    return locType ~= LOSS_OF_CONTROL_INTERRUPT_TYPE
end

--- Returns true when one unit token should be scanned for aura-based CC tracking.
--- @param unit string|nil
--- @return boolean
function CombatLogCollector.ShouldWatchAuraUnit(unit)
    if type(unit) ~= "string" or unit == "" then
        return false
    end

    if unit == "player"
        or unit == "target"
        or unit:find("^party%d")
        or unit:find("^raid%d")
        or unit:find("^arena%d")
        or unit:find("^nameplate%d") then
        return UnitExists(unit) == true
    end

    return false
end

--- Applies friendly/enemy team metadata to one tracked player row.
--- @param row table
--- @param unit string
function CombatLogCollector.ApplyTeamFromUnit(row, unit)
    if type(row) ~= "table" or type(unit) ~= "string" then
        return
    end

    if UnitIsUnit(unit, "player") or (UnitIsFriend and UnitIsFriend("player", unit)) then
        row.team = "friendly"
        return
    end

    if UnitIsEnemy and UnitIsEnemy("player", unit) then
        row.team = "enemy"
    end
end

--- Returns one tracked player row for a live unit token.
--- @param unit string
--- @return table|nil
function CombatLogCollector.GetPlayerRowFromUnit(unit)
    if not CombatLogCollector.ShouldWatchAuraUnit(unit) then
        return nil
    end

    local guid = UnitGUID(unit)
    local name = UnitName(unit)
    local row = CombatLogCollector.GetPlayerRow(guid, name, COMBATLOG_OBJECT_TYPE_PLAYER)
    if row then
        CombatLogCollector.ApplyTeamFromUnit(row, unit)
        if CombatLogCollector.IsPlayerGuid(guid) then
            row.guid = guid
        end
    end

    return row
end

--- Returns true when one aura instance has already been counted.
--- @param auraInstanceID number|nil
--- @return boolean
function CombatLogCollector.HasSeenCrowdControlAura(auraInstanceID)
    if not auraInstanceID then
        return false
    end

    return CombatLogCollector.seenCcAuras[auraInstanceID] == true
end

--- Marks one aura instance as counted for crowd-control tracking.
--- @param auraInstanceID number|nil
function CombatLogCollector.MarkCrowdControlAuraSeen(auraInstanceID)
    if auraInstanceID then
        CombatLogCollector.seenCcAuras[auraInstanceID] = true
    end
end

--- Returns true when one loss-of-control effect has already been counted.
--- @param spellId number|nil
--- @param startTime number|nil
--- @return boolean
function CombatLogCollector.HasSeenLossOfControlEffect(spellId, startTime)
    if not spellId or not startTime then
        return false
    end

    local key = string.format("%s:%s", tostring(spellId), tostring(startTime))
    return CombatLogCollector.seenLossOfControl[key] == true
end

--- Marks one loss-of-control effect as counted.
--- @param spellId number|nil
--- @param startTime number|nil
function CombatLogCollector.MarkLossOfControlEffectSeen(spellId, startTime)
    if not spellId or not startTime then
        return
    end

    local key = string.format("%s:%s", tostring(spellId), tostring(startTime))
    CombatLogCollector.seenLossOfControl[key] = true
end

--- Reads one aura table from the modern unit aura API.
--- @param unit string
--- @param auraInstanceID number
--- @return table|nil
function CombatLogCollector.GetAuraDataForInstance(unit, auraInstanceID)
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByAuraInstanceID) ~= "function" then
        return nil
    end

    local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
    if ok and type(aura) == "table" then
        return aura
    end

    return nil
end

--- Credits crowd-control counters for one newly applied aura.
--- @param unit string
--- @param aura table
function CombatLogCollector.CreditCrowdControlFromAura(unit, aura)
    if type(aura) ~= "table" or not CombatLogCollector.ShouldTrackCrowdControlEvents() then
        return
    end

    local spellId = aura.spellId or aura.spellID
    if not CombatLogCollector.IsCrowdControlSpell(spellId) then
        return
    end

    local auraInstanceID = aura.auraInstanceID
    if CombatLogCollector.HasSeenCrowdControlAura(auraInstanceID) then
        return
    end
    CombatLogCollector.MarkCrowdControlAuraSeen(auraInstanceID)

    local destRow = CombatLogCollector.GetPlayerRowFromUnit(unit)
    if destRow then
        CombatLogCollector.AddCount(destRow, "ccTaken")
    end

    local sourceUnit = aura.sourceUnit
    if type(sourceUnit) ~= "string" or sourceUnit == "" or UnitIsUnit(sourceUnit, unit) then
        return
    end

    local sourceGuid = UnitGUID(sourceUnit)
    local sourceName = UnitName(sourceUnit)
    local creditGuid, creditName, creditFlags = CombatLogCollector.ResolveInterruptSource(
        sourceGuid,
        sourceName,
        COMBATLOG_OBJECT_TYPE_PLAYER
    )
    local sourceRow = CombatLogCollector.GetPlayerRow(creditGuid, creditName, creditFlags)
    if sourceRow and (not destRow or sourceRow ~= destRow) then
        if sourceUnit == "player" or (UnitIsUnit and UnitIsUnit(sourceUnit, "player")) then
            sourceRow.team = "friendly"
        end
        CombatLogCollector.AddCount(sourceRow, "ccApplied")
    end
end

--- Processes newly added auras from one UNIT_AURA payload.
--- @param unit string
--- @param updateInfo table|nil
function CombatLogCollector.ProcessUnitAuraUpdate(unit, updateInfo)
    if not CombatLogCollector.ShouldWatchAuraUnit(unit)
        or type(updateInfo) ~= "table"
        or type(updateInfo.addedAuras) ~= "table" then
        return
    end

    CombatLogCollector.EnsureArmedForEvent()

    for _, auraInfo in ipairs(updateInfo.addedAuras) do
        local auraInstanceID = type(auraInfo) == "table" and auraInfo.auraInstanceID or auraInfo
        if auraInstanceID then
            local aura = CombatLogCollector.GetAuraDataForInstance(unit, auraInstanceID)
            if aura then
                CombatLogCollector.CreditCrowdControlFromAura(unit, aura)
            end
        end
    end
end

--- Records one loss-of-control effect for the local player.
--- @param effectIndex number|nil
function CombatLogCollector.ProcessLossOfControlAdded(effectIndex)
    if not CombatLogCollector.ShouldTrackCrowdControlEvents() then
        return
    end

    if not C_LossOfControl or type(C_LossOfControl.GetActiveLossOfControlData) ~= "function" then
        return
    end

    CombatLogCollector.EnsureArmedForEvent()

    local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlData, effectIndex)
    if not ok or type(data) ~= "table" then
        return
    end

    if not CombatLogCollector.ShouldCountLossOfControlType(data.locType) then
        return
    end

    local spellId = data.spellID or data.spellId
    local startTime = data.startTime
    if CombatLogCollector.HasSeenLossOfControlEffect(spellId, startTime) then
        return
    end
    CombatLogCollector.MarkLossOfControlEffectSeen(spellId, startTime)

    local row = CombatLogCollector.GetPlayerRowFromUnit("player")
    if row then
        CombatLogCollector.AddCount(row, "ccTaken")
    end
end

--- Returns true when aura and loss-of-control listeners should record events.
--- @return boolean
function CombatLogCollector.ShouldTrackCrowdControlEvents()
    if not CombatLogCollector.IsEnabled() then
        return false
    end

    return CombatLogCollector.active or CombatLogCollector.IsInLivePvpContext()
end

--- Handles UNIT_AURA updates for crowd-control tracking.
--- @param unit string
--- @param updateInfo table|nil
function CombatLogCollector.OnUnitAura(unit, updateInfo)
    if not CombatLogCollector.ShouldTrackCrowdControlEvents() then
        return
    end

    CombatLogCollector.ProcessUnitAuraUpdate(unit, updateInfo)
end

--- Handles LOSS_OF_CONTROL_ADDED for local crowd-control tracking.
--- @param effectIndex number|nil
function CombatLogCollector.OnLossOfControlAdded(effectIndex)
    CombatLogCollector.ProcessLossOfControlAdded(effectIndex)
end

--- Handles one registered combat telemetry event.
--- @param event string
--- @param ... any
function CombatLogCollector.OnEvent(event, ...)
    if event == "LOSS_OF_CONTROL_ADDED" then
        CombatLogCollector.OnLossOfControlAdded(...)
    elseif event == "UNIT_AURA" then
        CombatLogCollector.OnUnitAura(...)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        CombatLogCollector.OnCombatLogEvent()
    end
end

--- Registers aura and loss-of-control listeners used when combat log access is blocked.
function CombatLogCollector.EnsureEventFrame()
    if CombatLogCollector.frame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("LOSS_OF_CONTROL_ADDED")
    frame:RegisterEvent("UNIT_AURA")
    if CombatLogCollector.TryRegisterCombatLogEvent(frame) then
        CombatLogCollector.combatLogListenerActive = true
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        CombatLogCollector.OnEvent(event, ...)
    end)
    CombatLogCollector.frame = frame
end

--- Attempts to register COMBAT_LOG_EVENT_UNFILTERED when the client allows it.
--- @param frame Frame
--- @return boolean registered
function CombatLogCollector.TryRegisterCombatLogEvent(frame)
    if type(frame) ~= "table" or type(frame.RegisterEvent) ~= "function" then
        return false
    end

    local ok = pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
    return ok == true
end

--- Returns a deep copy of the in-memory player map keyed by GUID.
--- @param players table|nil
--- @return table
function CombatLogCollector.ClonePlayerMap(players)
    local copy = {}
    for guid, row in pairs(players or {}) do
        copy[guid] = CombatLogCollector.ClonePlayerRow(row)
    end
    return copy
end

--- Merges one source player row into a destination row.
--- @param destination table
--- @param source table|nil
function CombatLogCollector.MergePlayerRow(destination, source)
    if type(destination) ~= "table" or type(source) ~= "table" then
        return
    end

    for _, field in ipairs(MERGE_AMOUNT_FIELDS) do
        destination[field] = (destination[field] or 0) + (source[field] or 0)
    end

    for _, field in ipairs(MERGE_COUNT_FIELDS) do
        destination[field] = (destination[field] or 0) + (source[field] or 0)
    end

    if source.name and source.name ~= "" then
        destination.name = source.name
    end

    if source.team == "friendly" or source.team == "enemy" then
        destination.team = source.team
    end
end

--- Merges one source player map into a destination map keyed by GUID.
--- @param destination table
--- @param source table|nil
function CombatLogCollector.MergePlayerMaps(destination, source)
    for guid, row in pairs(source or {}) do
        local existing = destination[guid]
        if existing then
            CombatLogCollector.MergePlayerRow(existing, row)
        else
            destination[guid] = CombatLogCollector.ClonePlayerRow(row)
        end
    end
end

--- Replaces combat amount fields in one player map from an authoritative meter snapshot.
--- @param destination table
--- @param source table|nil
function CombatLogCollector.ReplaceCombatAmountsFromMeter(destination, source)
    if type(destination) ~= "table" or type(source) ~= "table" then
        return
    end

    local function replaceRow(destinationRow, sourceRow)
        for _, field in ipairs(MERGE_AMOUNT_FIELDS) do
            local amount = sourceRow[field]
            if amount and amount > 0 then
                destinationRow[field] = amount
            end
        end

        for _, field in ipairs(MERGE_COUNT_FIELDS) do
            local amount = sourceRow[field]
            if amount and amount > 0 then
                destinationRow[field] = amount
            end
        end

        if sourceRow.name and sourceRow.name ~= "" then
            destinationRow.name = sourceRow.name
        end

        if sourceRow.team == "friendly" or sourceRow.team == "enemy" then
            destinationRow.team = sourceRow.team
        end
    end

    for storageKey, sourceRow in pairs(source) do
        local destinationRow = destination[storageKey]
        if destinationRow then
            replaceRow(destinationRow, sourceRow)
        else
            local matchedKey = nil
            local sourceNameKey = sourceRow.name and CombatLogCollector.NormalizeName(sourceRow.name) or nil
            if sourceNameKey then
                for key, row in pairs(destination) do
                    if row.name and CombatLogCollector.NormalizeName(row.name) == sourceNameKey then
                        matchedKey = key
                        break
                    end
                end
            end

            if matchedKey then
                replaceRow(destination[matchedKey], sourceRow)
            else
                destination[storageKey] = CombatLogCollector.ClonePlayerRow(sourceRow)
            end
        end
    end
end

--- Merges one source player map into a destination map using per-field maximums.
--- @param destination table
--- @param source table|nil
function CombatLogCollector.MergePlayerMapsMax(destination, source)
    for guid, row in pairs(source or {}) do
        local existing = destination[guid]
        if not existing then
            destination[guid] = CombatLogCollector.ClonePlayerRow(row)
        else
            for _, field in ipairs(MERGE_AMOUNT_FIELDS) do
                existing[field] = math.max(existing[field] or 0, row[field] or 0)
            end
            for _, field in ipairs(MERGE_COUNT_FIELDS) do
                existing[field] = math.max(existing[field] or 0, row[field] or 0)
            end
            if row.name and row.name ~= "" then
                existing.name = row.name
            end
            if row.team == "friendly" or row.team == "enemy" then
                existing.team = row.team
            end
        end
    end
end

--- Fills only missing combat amount fields from one archived snapshot map.
--- @param destination table
--- @param source table|nil
function CombatLogCollector.MergePlayerMapsFillGaps(destination, source)
    if type(destination) ~= "table" or type(source) ~= "table" then
        return
    end

    local function fillGaps(destinationRow, sourceRow)
        for _, field in ipairs(MERGE_AMOUNT_FIELDS) do
            local amount = sourceRow[field]
            if amount and amount > 0 and (not destinationRow[field] or destinationRow[field] <= 0) then
                destinationRow[field] = amount
            end
        end

        for _, field in ipairs(MERGE_COUNT_FIELDS) do
            local amount = sourceRow[field]
            if amount and amount > 0 and (not destinationRow[field] or destinationRow[field] <= 0) then
                destinationRow[field] = amount
            end
        end

        if (not destinationRow.name or destinationRow.name == "") and sourceRow.name then
            destinationRow.name = sourceRow.name
        end

        if destinationRow.team ~= "friendly"
            and destinationRow.team ~= "enemy"
            and (sourceRow.team == "friendly" or sourceRow.team == "enemy") then
            destinationRow.team = sourceRow.team
        end
    end

    for storageKey, sourceRow in pairs(source) do
        local destinationRow = destination[storageKey]
        if destinationRow then
            fillGaps(destinationRow, sourceRow)
        else
            local matchedKey = nil
            local sourceNameKey = sourceRow.name and CombatLogCollector.NormalizeName(sourceRow.name) or nil
            if sourceNameKey then
                for key, row in pairs(destination) do
                    if row.name and CombatLogCollector.NormalizeName(row.name) == sourceNameKey then
                        matchedKey = key
                        break
                    end
                end
            end

            if matchedKey then
                fillGaps(destination[matchedKey], sourceRow)
            else
                destination[storageKey] = CombatLogCollector.ClonePlayerRow(sourceRow)
            end
        end
    end
end

--- Returns the authoritative unix match window from battlefield runtime and fallbacks.
--- @param matchContext table|nil
--- @return table window `{ startedAt, endedAt, durationSeconds }`
function CombatLogCollector.ResolveMatchWindow(matchContext)
    local endedAt = time()
    local durationSeconds = nil
    local matchCollector = PVL.MatchCollector

    if matchCollector and matchCollector.GetBattlefieldRuntimeMs then
        local runtimeMs = matchCollector.GetBattlefieldRuntimeMs()
        if runtimeMs and runtimeMs > 0 then
            durationSeconds = math.floor(runtimeMs / 1000)
        end
    end

    if (not durationSeconds or durationSeconds <= 0) and type(matchContext) == "table" then
        local runtimeMs = matchContext.runtimeMs or matchContext.minRuntimeMs
        if runtimeMs and runtimeMs > 0 then
            durationSeconds = math.floor(runtimeMs / 1000)
        end
    end

    if (not durationSeconds or durationSeconds <= 0) and CombatLogCollector.startedAt then
        durationSeconds = math.max(0, endedAt - CombatLogCollector.startedAt)
    end

    if (not durationSeconds or durationSeconds <= 0)
        and CombatLogCollector.IsDamageMeterAvailable()
        and C_DamageMeter.GetSessionDurationSeconds then
        local ok, seconds = pcall(C_DamageMeter.GetSessionDurationSeconds, DAMAGE_METER_SESSION_OVERALL)
        if ok and seconds and seconds > 0 then
            durationSeconds = math.floor(seconds)
        end
    end

    local startedAt = CombatLogCollector.startedAt
    if durationSeconds and durationSeconds > 0 then
        startedAt = endedAt - durationSeconds
    end

    return {
        startedAt = startedAt,
        endedAt = endedAt,
        durationSeconds = durationSeconds,
    }
end

--- Prunes old archived combat snapshots from the per-character database.
--- @param archive table[]|nil
function CombatLogCollector.PruneCombatSegmentArchive(archive)
    if type(archive) ~= "table" then
        return
    end

    local cutoff = time() - SEGMENT_ARCHIVE_MAX_AGE_SECONDS
    local kept = {}
    for _, snapshot in ipairs(archive) do
        if type(snapshot) == "table" and snapshot.savedAt and snapshot.savedAt >= cutoff then
            table.insert(kept, snapshot)
        end
    end

    while #kept > MAX_COMBAT_SEGMENT_ARCHIVE do
        table.remove(kept, 1)
    end

    for index = 1, #kept do
        archive[index] = kept[index]
    end
    for index = #kept + 1, #archive do
        archive[index] = nil
    end
end

--- Archives the current in-memory combat buffer for later match-window merging.
--- @param matchContext table|nil
function CombatLogCollector.ArchiveSegmentSnapshot(matchContext)
    local charDb = PVL.GetCharDB()
    if type(charDb) ~= "table" then
        return
    end

    charDb.combatSegmentArchive = charDb.combatSegmentArchive or {}
    local hasPlayers = CombatLogCollector.players and next(CombatLogCollector.players) ~= nil
    if not hasPlayers and CombatLogCollector.damageMeterSynced ~= true then
        return
    end

    table.insert(charDb.combatSegmentArchive, {
        savedAt = time(),
        startedAt = CombatLogCollector.startedAt,
        bracket = matchContext and matchContext.bracket or nil,
        sessionKey = matchContext and matchContext.sessionKey or nil,
        runtimeMs = matchContext and matchContext.runtimeMs or nil,
        segmentCount = CombatLogCollector.segmentCount or 1,
        eventCount = CombatLogCollector.eventCount or 0,
        damageMeterSynced = CombatLogCollector.damageMeterSynced == true,
        players = CombatLogCollector.ClonePlayerMap(CombatLogCollector.players),
    })

    CombatLogCollector.PruneCombatSegmentArchive(charDb.combatSegmentArchive)
end

--- Returns true when one archived snapshot falls inside a resolved match window.
--- @param snapshot table
--- @param window table
--- @param bracket string|nil
--- @return boolean
function CombatLogCollector.SnapshotMatchesMatchWindow(snapshot, window, bracket)
    if type(snapshot) ~= "table" or type(window) ~= "table" then
        return false
    end

    if bracket and snapshot.bracket and snapshot.bracket ~= bracket then
        return false
    end

    local savedAt = snapshot.savedAt
    if not savedAt then
        return false
    end

    local startedAt = window.startedAt
    local endedAt = window.endedAt or time()
    if startedAt then
        return savedAt >= (startedAt - MATCH_WINDOW_TOLERANCE_SECONDS)
            and savedAt <= (endedAt + MATCH_WINDOW_TOLERANCE_SECONDS)
    end

    return true
end

--- Merges archived combat snapshots that fall inside one match window.
--- @param window table
--- @param bracket string|nil
--- @return number mergedCount
function CombatLogCollector.MergeArchivedSnapshotsForWindow(window, bracket)
    local charDb = PVL.GetCharDB()
    if type(charDb) ~= "table" or type(charDb.combatSegmentArchive) ~= "table" then
        return 0
    end

    local mergedCount = 0
    local remaining = {}

    for _, snapshot in ipairs(charDb.combatSegmentArchive) do
        if CombatLogCollector.SnapshotMatchesMatchWindow(snapshot, window, bracket) then
            CombatLogCollector.MergePlayerMapsFillGaps(CombatLogCollector.players, snapshot.players)
            mergedCount = mergedCount + 1
        else
            table.insert(remaining, snapshot)
        end
    end

    charDb.combatSegmentArchive = remaining
    return mergedCount
end

--- Returns true when one roster participant has end-of-match scoreboard combat totals.
--- @param participant table|nil
--- @return boolean
function CombatLogCollector.ParticipantHasScoreboardCombatTotals(participant)
    if type(participant) ~= "table" then
        return false
    end

    return participant.damageDone ~= nil
        or participant.healingDone ~= nil
        or participant.interrupts ~= nil
        or participant.dispels ~= nil
        or participant.deaths ~= nil
end

--- Returns true when a roster has scoreboard combat totals for at least one player.
--- @param roster table[]|nil
--- @return boolean
function CombatLogCollector.RosterHasScoreboardCombatTotals(roster)
    for _, participant in ipairs(roster or {}) do
        if CombatLogCollector.ParticipantHasScoreboardCombatTotals(participant) then
            return true
        end
    end

    return false
end

--- Finds one tracked meter row for a roster participant.
--- @param participant table
--- @param meterPlayers table|nil
--- @return table|nil
function CombatLogCollector.LookupMeterRowForParticipant(participant, meterPlayers)
    if type(participant) ~= "table" or type(meterPlayers) ~= "table" then
        return nil
    end

    if participant.guid and meterPlayers[participant.guid] then
        return meterPlayers[participant.guid]
    end

    local nameKey = CombatLogCollector.NormalizeName(participant.name)
    if nameKey and meterPlayers["name:" .. nameKey] then
        return meterPlayers["name:" .. nameKey]
    end

    if nameKey then
        for _, row in pairs(meterPlayers) do
            if row.name and CombatLogCollector.NormalizeName(row.name) == nameKey then
                return row
            end
        end
    end

    return nil
end

--- Returns interrupt/dispel count for one GUID from a damage meter session source.
--- @param guid string|nil
--- @param meterType number
--- @param sessionId number|nil
--- @param sessionTypes number[]|nil
--- @return number
function CombatLogCollector.FetchMeterCountForGuid(guid, meterType, sessionId, sessionTypes)
    if not CombatLogCollector.CanUseGuid(guid) or not CombatLogCollector.IsDamageMeterAvailable() then
        return 0
    end

    local function readSourceAmount(source)
        if type(source) ~= "table" then
            return 0
        end

        local amount = CombatLogCollector.GetDamageMeterInterruptCount(source)
        if (not amount or amount <= 0) and type(source.combatSpells) == "table" then
            amount = CombatLogCollector.SumDamageMeterInterruptSpellCount(source)
        end

        return amount or 0
    end

    if sessionId then
        if type(C_DamageMeter.GetCombatSessionSourceFromID) == "function" then
            local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionId, meterType, guid)
            if ok then
                local amount = readSourceAmount(source)
                if amount > 0 then
                    return amount
                end
            end
        end
    end

    for _, sessionType in ipairs(sessionTypes or {}) do
        if type(C_DamageMeter.GetCombatSessionSourceFromType) == "function" then
            local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, guid)
            if ok then
                local amount = readSourceAmount(source)
                if amount > 0 then
                    return amount
                end
            end
        end
    end

    return 0
end

--- Returns interrupt/dispel count for one roster participant from damage meter sessions.
--- @param participant table
--- @param meterType number
--- @param sessionId number|nil
--- @param sessionTypes number[]|nil
--- @return number
function CombatLogCollector.FetchMeterCountForParticipant(participant, meterType, sessionId, sessionTypes)
    if type(participant) ~= "table" then
        return 0
    end

    local guidCount = CombatLogCollector.FetchMeterCountForGuid(
        participant.guid,
        meterType,
        sessionId,
        sessionTypes
    )
    if guidCount > 0 then
        return guidCount
    end

    local nameKey = participant.name and CombatLogCollector.NormalizeName(participant.name)
    if not nameKey then
        if participant.isLocalPlayer then
            local localGuid = UnitGUID and UnitGUID("player")
            return CombatLogCollector.FetchMeterCountForGuid(localGuid, meterType, sessionId, sessionTypes)
        end
        return 0
    end

    local sessions = {}
    if sessionId then
        local session = CombatLogCollector.GetDamageMeterSessionById(sessionId, meterType)
        if session then
            table.insert(sessions, session)
        end
    else
        for _, sessionType in ipairs(sessionTypes or {}) do
            local session = CombatLogCollector.GetDamageMeterSession(sessionType, meterType)
            if session then
                table.insert(sessions, session)
            end
        end
    end

    local best = 0
    for _, session in ipairs(sessions) do
        CombatLogCollector.ForEachDamageMeterSource(session, function(source)
            if participant.isLocalPlayer and source.isLocalPlayer then
                local amount = CombatLogCollector.GetDamageMeterInterruptCount(source) or 0
                if amount > best then
                    best = amount
                end
                return
            end

            local sourceName = CombatLogCollector.GetDamageMeterSourceName(source)
            if sourceName and CombatLogCollector.NormalizeName(sourceName) == nameKey then
                local amount = CombatLogCollector.GetDamageMeterInterruptCount(source) or 0
                if amount > best then
                    best = amount
                end
            end
        end)
    end

    return best
end

--- Upserts supplemental meter counts for one roster participant.
--- @param destination table
--- @param participant table
--- @param interrupts number|nil
--- @param dispels number|nil
function CombatLogCollector.UpsertSupplementRowForParticipant(destination, participant, interrupts, dispels)
    if type(destination) ~= "table" or type(participant) ~= "table" then
        return
    end

    interrupts = tonumber(interrupts) or 0
    dispels = tonumber(dispels) or 0
    if interrupts <= 0 and dispels <= 0 then
        return
    end

    local row = CombatLogCollector.LookupMeterRowForParticipant(participant, destination)
    if not row then
        local storageKey = participant.guid
        local nameKey = participant.name and CombatLogCollector.NormalizeName(participant.name)
        if not storageKey and nameKey then
            storageKey = "name:" .. nameKey
        end
        if not storageKey then
            return
        end

        row = {
            guid = participant.guid,
            name = participant.name,
            team = participant.team,
            interrupts = 0,
            dispels = 0,
            damageTaken = 0,
            deaths = 0,
        }
        destination[storageKey] = row
    end

    row.interrupts = math.max(row.interrupts or 0, interrupts)
    row.dispels = math.max(row.dispels or 0, dispels)
    if participant.name and participant.name ~= "" then
        row.name = participant.name
    end
    if participant.guid then
        row.guid = participant.guid
    end
end

--- Pulls per-player interrupt/dispel totals using roster GUIDs and names.
--- @param roster table[]|nil
--- @param window table|nil
--- @param destination table
--- @return boolean synced
function CombatLogCollector.FetchSupplementCountsForRoster(roster, window, destination)
    if not CombatLogCollector.IsDamageMeterAvailable() or type(destination) ~= "table" then
        return false
    end

    local synced = false
    local targetDuration = window and window.durationSeconds or nil
    local bestSessionId = CombatLogCollector.SelectBestDamageMeterSessionId(targetDuration)
    local sessionTypes = { DAMAGE_METER_SESSION_OVERALL, DAMAGE_METER_SESSION_CURRENT }

    for _, participant in ipairs(roster or {}) do
        local interrupts = CombatLogCollector.FetchMeterCountForParticipant(
            participant,
            DAMAGE_METER_TYPE_INTERRUPTS,
            bestSessionId,
            bestSessionId and nil or sessionTypes
        )
        local dispels = CombatLogCollector.FetchMeterCountForParticipant(
            participant,
            DAMAGE_METER_TYPE_DISPELS,
            bestSessionId,
            bestSessionId and nil or sessionTypes
        )

        if interrupts > 0 or dispels > 0 then
            CombatLogCollector.UpsertSupplementRowForParticipant(destination, participant, interrupts, dispels)
            synced = true
        end
    end

    return synced
end

--- Imports one damage meter session id into a destination player map.
--- @param sessionId number
--- @param destination table
--- @param meterTypes table|nil Optional meter-type map; defaults to all tracked stats.
--- @return boolean synced
function CombatLogCollector.ImportDamageMeterSessionId(sessionId, destination, meterTypes)
    if not sessionId or type(destination) ~= "table" then
        return false
    end

    meterTypes = meterTypes or DAMAGE_METER_SYNC_TYPES
    local previousPlayers = CombatLogCollector.players
    CombatLogCollector.players = destination
    local synced = false

    for meterType, fieldName in pairs(meterTypes) do
        local session = CombatLogCollector.GetDamageMeterSessionById(sessionId, meterType)
        CombatLogCollector.ForEachDamageMeterSource(session, function(source)
            if CombatLogCollector.ApplyDamageMeterSource(source, fieldName) then
                synced = true
            end
        end)
    end

    CombatLogCollector.players = destination
    if CombatLogCollector.SyncInterruptsFromDamageMeter(nil, sessionId) then
        synced = true
    end

    if CombatLogCollector.SyncDispelsFromDamageMeter(nil, sessionId) then
        synced = true
    end

    CombatLogCollector.players = previousPlayers
    return synced
end

--- Returns the best available supplemental count, preferring scoreboard values.
--- @param scoreboardValue number|nil
--- @param meterValue number|nil
--- @return number
function CombatLogCollector.ResolveSupplementCount(scoreboardValue, meterValue)
    local scoreboard = tonumber(scoreboardValue) or 0
    local meter = tonumber(meterValue) or 0
    if scoreboard > 0 then
        return scoreboard
    end

    return meter
end

--- Copies supplemental combat fields from one player map into another.
--- @param destination table
--- @param source table|nil
function CombatLogCollector.ImportSupplementFieldsFromPlayerMap(destination, source)
    if type(destination) ~= "table" or type(source) ~= "table" then
        return
    end

    local function upsertRow(sourceRow)
        local destinationRow = nil
        if sourceRow.guid and destination[sourceRow.guid] then
            destinationRow = destination[sourceRow.guid]
        end

        local nameKey = sourceRow.name and CombatLogCollector.NormalizeName(sourceRow.name) or nil
        if not destinationRow and nameKey and destination["name:" .. nameKey] then
            destinationRow = destination["name:" .. nameKey]
        end

        if not destinationRow and nameKey then
            for key, row in pairs(destination) do
                if row.name and CombatLogCollector.NormalizeName(row.name) == nameKey then
                    destinationRow = row
                    break
                end
            end
        end

        if not destinationRow then
            local storageKey = sourceRow.guid or (nameKey and ("name:" .. nameKey) or nil)
            if not storageKey then
                return
            end

            destinationRow = CombatLogCollector.ClonePlayerRow(sourceRow) or {
                guid = sourceRow.guid,
                name = sourceRow.name,
                team = sourceRow.team,
            }
            destination[storageKey] = destinationRow
        end

        for _, field in ipairs(SUPPLEMENT_COUNT_FIELDS) do
            destinationRow[field] = math.max(destinationRow[field] or 0, sourceRow[field] or 0)
        end

        if sourceRow.name and sourceRow.name ~= "" then
            destinationRow.name = sourceRow.name
        end

        if sourceRow.team == "friendly" or sourceRow.team == "enemy" then
            destinationRow.team = sourceRow.team
        end
    end

    for _, row in pairs(source) do
        if type(row) == "table" then
            upsertRow(row)
        end
    end
end

--- Imports scoreboard supplement stats from the best damage meter session.
--- @param window table|nil
--- @param destination table
--- @return boolean synced
function CombatLogCollector.SyncDamageMeterSupplementForWindow(window, destination)
    if not CombatLogCollector.IsDamageMeterAvailable() or type(destination) ~= "table" then
        return false
    end

    local previousPlayers = CombatLogCollector.players
    CombatLogCollector.players = destination
    local synced = false
    local targetDuration = window and window.durationSeconds or nil
    local bestSessionId = CombatLogCollector.SelectBestDamageMeterSessionId(targetDuration)

    if bestSessionId then
        if CombatLogCollector.ImportDamageMeterSessionId(
            bestSessionId,
            destination,
            DAMAGE_METER_SCOREBOARD_SUPPLEMENT_TYPES
        ) then
            synced = true
        end

        CombatLogCollector.players = destination
        if CombatLogCollector.SyncInterruptsFromDamageMeter(nil, bestSessionId) then
            synced = true
        end

        if CombatLogCollector.SyncDispelsFromDamageMeter(nil, bestSessionId) then
            synced = true
        end
    else
        for _, sessionType in ipairs({ DAMAGE_METER_SESSION_OVERALL, DAMAGE_METER_SESSION_CURRENT }) do
            if CombatLogCollector.ImportDamageMeterSessionType(
                sessionType,
                destination,
                DAMAGE_METER_SCOREBOARD_SUPPLEMENT_TYPES
            ) then
                synced = true
            end

            CombatLogCollector.players = destination
            if CombatLogCollector.SyncInterruptsFromDamageMeter(sessionType, nil) then
                synced = true
            end

            if CombatLogCollector.SyncDispelsFromDamageMeter(sessionType, nil) then
                synced = true
            end
        end
    end

    CombatLogCollector.players = previousPlayers
    return synced
end

--- Returns the damage meter session id that best matches one match duration.
--- @param targetDuration number|nil
--- @return number|nil sessionId
function CombatLogCollector.SelectBestDamageMeterSessionId(targetDuration)
    if not C_DamageMeter or type(C_DamageMeter.GetAvailableCombatSessions) ~= "function" then
        return nil
    end

    local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(sessions) ~= "table" or #sessions == 0 then
        return nil
    end

    local bestSessionId = nil
    local bestDuration = -1
    local bestDelta = nil

    for _, session in ipairs(sessions) do
        local sessionId = session.sessionID or session.sessionId
        local duration = CombatLogCollector.GetAccessibleNumber(session.durationSeconds) or 0
        if sessionId and duration > 0 then
            if targetDuration and targetDuration > 0 then
                local delta = math.abs(duration - targetDuration)
                if bestDelta == nil
                    or delta < bestDelta
                    or (delta == bestDelta and duration > bestDuration) then
                    bestDelta = delta
                    bestDuration = duration
                    bestSessionId = sessionId
                end
            elseif duration > bestDuration then
                bestDuration = duration
                bestSessionId = sessionId
            end
        end
    end

    return bestSessionId
end

--- Imports one damage meter session type into a destination player map.
--- @param sessionType number
--- @param destination table
--- @param meterTypes table|nil Optional meter-type map; defaults to all tracked stats.
--- @return boolean synced
function CombatLogCollector.ImportDamageMeterSessionType(sessionType, destination, meterTypes)
    if type(destination) ~= "table" then
        return false
    end

    meterTypes = meterTypes or DAMAGE_METER_SYNC_TYPES
    local previousPlayers = CombatLogCollector.players
    CombatLogCollector.players = destination
    local synced = false

    for meterType, fieldName in pairs(meterTypes) do
        local session = CombatLogCollector.GetDamageMeterSession(sessionType, meterType)
        CombatLogCollector.ForEachDamageMeterSource(session, function(source)
            if CombatLogCollector.ApplyDamageMeterSource(source, fieldName) then
                synced = true
            end
        end)
    end

    CombatLogCollector.players = destination
    if CombatLogCollector.SyncInterruptsFromDamageMeter(sessionType, nil) then
        synced = true
    end

    if CombatLogCollector.SyncDispelsFromDamageMeter(sessionType, nil) then
        synced = true
    end

    CombatLogCollector.players = previousPlayers
    return synced
end

--- Syncs one authoritative damage meter snapshot for a resolved match window.
--- Uses a single best session to avoid double-counting overlapping Blizzard sessions.
--- @param window table|nil
--- @return boolean synced
function CombatLogCollector.SyncDamageMeterSessionsForWindow(window)
    if not CombatLogCollector.IsDamageMeterAvailable() then
        return false
    end

    local targetDuration = window and window.durationSeconds or nil
    local meterPlayers = {}
    local synced = false
    local bestSessionId = CombatLogCollector.SelectBestDamageMeterSessionId(targetDuration)

    if bestSessionId then
        synced = CombatLogCollector.ImportDamageMeterSessionId(bestSessionId, meterPlayers)
    end

    if next(meterPlayers) == nil then
        synced = CombatLogCollector.ImportDamageMeterSessionType(DAMAGE_METER_SESSION_OVERALL, meterPlayers) or synced
    end

    if next(meterPlayers) ~= nil then
        CombatLogCollector.ReplaceCombatAmountsFromMeter(CombatLogCollector.players, meterPlayers)
        CombatLogCollector.damageMeterSynced = true

        local interruptTotal = 0
        for _, row in pairs(CombatLogCollector.players) do
            interruptTotal = interruptTotal + (row.interrupts or 0)
        end
        CombatLogCollector.interruptCount = interruptTotal
    end

    return synced
end

--- Returns a resumable pending session for one match context when available.
--- @param matchContext table|nil
--- @return table|nil
function CombatLogCollector.GetResumablePendingSession(matchContext)
    if type(matchContext) ~= "table" or not matchContext.sessionKey then
        return nil
    end

    local matchCollector = PVL.MatchCollector
    if not matchCollector
        or not matchCollector.CanResumeCombatSession
        or not matchCollector.CanResumeCombatSession(
            matchContext.sessionKey,
            matchContext.runtimeMs,
            matchContext.rosterFingerprint,
            matchContext.playerCrBefore
        ) then
        return nil
    end

    return matchCollector.GetPendingCombatSession()
end

--- Restores in-memory combat stats from one persisted pending session.
--- @param pending table|nil
--- @param matchContext table|nil
function CombatLogCollector.ImportPendingSession(pending, matchContext)
    CombatLogCollector.players = CombatLogCollector.ClonePlayerMap(pending and pending.players)
    CombatLogCollector.killEvents = {}
    for _, event in ipairs(pending and pending.killEvents or {}) do
        table.insert(CombatLogCollector.killEvents, {
            elapsed = event.elapsed,
            victim = event.victim,
            killer = event.killer,
        })
    end

    CombatLogCollector.eventCount = pending and pending.eventCount or 0
    CombatLogCollector.interruptCount = pending and pending.interruptCount or 0
    CombatLogCollector.damageMeterSynced = pending and pending.damageMeterSynced == true or false
    CombatLogCollector.segmentCount = matchContext and matchContext.segmentCount or (pending and pending.segmentCount) or 1
    CombatLogCollector.startedAt = (pending and pending.startedAt) or (matchContext and matchContext.startedAt) or time()
    CombatLogCollector.rawCombatEvents = CombatLogCollector.CloneRawCombatEvents(pending and pending.rawCombatEvents)
end

--- Persists the current in-memory combat buffer for the active match instance.
--- @param matchContext table|nil
function CombatLogCollector.PersistPendingSession(matchContext)
    matchContext = matchContext or CombatLogCollector.matchContext
    if not CombatLogCollector.active or type(matchContext) ~= "table" or not matchContext.sessionKey then
        return
    end

    if CombatLogCollector.IsDamageMeterAvailable() then
        CombatLogCollector.SyncFromDamageMeter()
    end

    local charDb = PVL.GetCharDB()
    if type(charDb) ~= "table" then
        return
    end

    charDb.pendingCombatSession = {
        sessionKey = matchContext.sessionKey,
        bracket = matchContext.bracket,
        startedAt = CombatLogCollector.startedAt,
        minRuntimeMs = matchContext.minRuntimeMs or matchContext.runtimeMs or 0,
        mapID = matchContext.mapID,
        playerCrBefore = matchContext.playerCrBefore,
        playerMmrBefore = matchContext.playerMmrBefore,
        rosterFingerprint = matchContext.rosterFingerprint,
        segmentCount = CombatLogCollector.segmentCount or 1,
        eventCount = CombatLogCollector.eventCount or 0,
        interruptCount = CombatLogCollector.interruptCount or 0,
        damageMeterSynced = CombatLogCollector.damageMeterSynced == true,
        dataSource = CombatLogCollector.GetDataSourceLabel(),
        players = CombatLogCollector.ClonePlayerMap(CombatLogCollector.players),
        killEvents = CombatLogCollector.CloneKillEvents(CombatLogCollector.killEvents),
        rawCombatEvents = CombatLogCollector.CloneRawCombatEvents(CombatLogCollector.rawCombatEvents),
        savedAt = time(),
    }

    CombatLogCollector.ArchiveSegmentSnapshot(matchContext)
end

--- Returns a copy of one kill-event list.
--- @param killEvents table[]|nil
--- @return table[]
function CombatLogCollector.CloneKillEvents(killEvents)
    local copy = {}
    for _, event in ipairs(killEvents or {}) do
        table.insert(copy, {
            elapsed = event.elapsed,
            victim = event.victim,
            killer = event.killer,
        })
    end
    return copy
end

--- Starts periodic persistence while a match is actively tracked.
function CombatLogCollector.StartPersistTicker()
    if CombatLogCollector.persistTicker or not C_Timer or not C_Timer.NewTicker then
        return
    end

    CombatLogCollector.persistTicker = C_Timer.NewTicker(PERSIST_INTERVAL_SECONDS, function()
        if CombatLogCollector.active then
            CombatLogCollector.PersistPendingSession(CombatLogCollector.matchContext)
        end
    end)
end

--- Stops periodic session persistence.
function CombatLogCollector.StopPersistTicker()
    if CombatLogCollector.persistTicker then
        CombatLogCollector.persistTicker:Cancel()
        CombatLogCollector.persistTicker = nil
    end
end

--- Pulls live combat totals from C_DamageMeter while a match is active.
--- Midnight blocks COMBAT_LOG_EVENT_UNFILTERED in instanced PvP, so polling is the reliable path.
function CombatLogCollector.TryLiveSync()
    if not CombatLogCollector.IsEnabled() then
        return
    end

    if not CombatLogCollector.active and not CombatLogCollector.IsInLivePvpContext() then
        return
    end

    CombatLogCollector.EnsureArmedForEvent()
    if CombatLogCollector.IsDamageMeterAvailable() then
        pcall(CombatLogCollector.SyncFromDamageMeter)
    end
end

--- Starts frequent damage meter polling for live in-match stat tracking.
function CombatLogCollector.StartLiveSyncTicker()
    if CombatLogCollector.liveSyncTicker or not C_Timer or not C_Timer.NewTicker then
        return
    end

    CombatLogCollector.liveSyncTicker = C_Timer.NewTicker(LIVE_SYNC_INTERVAL_SECONDS, function()
        CombatLogCollector.TryLiveSync()
    end)

    CombatLogCollector.TryLiveSync()
end

--- Stops live damage meter polling.
function CombatLogCollector.StopLiveSyncTicker()
    if CombatLogCollector.liveSyncTicker then
        CombatLogCollector.liveSyncTicker:Cancel()
        CombatLogCollector.liveSyncTicker = nil
    end
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
--- @param storageKey string
--- @param name string|nil
--- @param team string
--- @return table
function CombatLogCollector.CreatePlayerRow(storageKey, name, team)
    return {
        guid = nil,
        name = name,
        team = team,
        damage = 0,
        healing = 0,
        damageTaken = 0,
        interrupts = 0,
        dispels = 0,
        deaths = 0,
        ccApplied = 0,
        ccTaken = 0,
    }
end

--- Returns or creates one tracked player stats row.
--- @param guid string|nil
--- @param name string|nil
--- @param flags number|nil
--- @return table|nil
function CombatLogCollector.GetPlayerRow(guid, name, flags)
    local storageKey = CombatLogCollector.ResolveStorageKey(guid, name, flags)
    if not storageKey then
        return nil
    end

    local players = CombatLogCollector.players
    local row = players[storageKey]
    if not row then
        local team = CombatLogCollector.IsFriendlyFlags(flags) and "friendly" or "enemy"
        row = CombatLogCollector.CreatePlayerRow(storageKey, name, team)
        if CombatLogCollector.IsPlayerGuid(guid) then
            row.guid = guid
        end
        players[storageKey] = row
    end

    if CombatLogCollector.IsAccessibleName(name) then
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

--- Adds one to a numeric counter on a player row.
--- @param row table|nil
--- @param field string
function CombatLogCollector.AddCount(row, field)
    if not row then
        return
    end

    row[field] = (row[field] or 0) + 1
end

--- Returns true when live combat-log events should be processed for the current zone.
--- @return boolean
function CombatLogCollector.IsInLivePvpContext()
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

    local matchCollector = PVL.MatchCollector
    return matchCollector
        and matchCollector.IsInCollectiblePvpInstance
        and matchCollector.IsInCollectiblePvpInstance()
end

--- Returns the player GUID that should receive credit for one interrupt event.
--- Pet kicks (for example Spell Lock) are credited to the local player when applicable.
--- @param sourceGUID string|nil
--- @param sourceName string|nil
--- @param sourceFlags number|nil
--- @return string|nil guid, string|nil name, number|nil flags
function CombatLogCollector.ResolveInterruptSource(sourceGUID, sourceName, sourceFlags)
    if CombatLogCollector.IsAccessibleName(sourceName) then
        if CombatLogCollector.IsPlayerGuid(sourceGUID) then
            return sourceGUID, sourceName, sourceFlags
        end

        if CombatLogCollector.CanUseGuid(sourceGUID) then
            local ok, isPet = pcall(function()
                return sourceGUID:find("^Pet%-") ~= nil
            end)
            if ok and isPet and UnitGUID and UnitGUID("pet") == sourceGUID and UnitName then
                return UnitGUID("player"), UnitName("player"), sourceFlags
            end
        end

        return sourceGUID, sourceName, sourceFlags
    end

    if CombatLogCollector.IsPlayerGuid(sourceGUID) then
        return sourceGUID, nil, sourceFlags
    end

    return nil
end

--- Records one SPELL_INTERRUPT event using Details-style name-first attribution.
--- @param sourceGUID string|nil
--- @param sourceName string|nil
--- @param sourceFlags number|nil
--- @return boolean recorded
function CombatLogCollector.ProcessInterruptEvent(sourceGUID, sourceName, sourceFlags)
    local creditGUID, creditName, creditFlags = CombatLogCollector.ResolveInterruptSource(
        sourceGUID,
        sourceName,
        sourceFlags
    )
    if not CombatLogCollector.IsAccessibleName(creditName) and not CombatLogCollector.CanUseGuid(creditGUID) then
        return false
    end

    local sourceRow = CombatLogCollector.GetPlayerRow(creditGUID, creditName, creditFlags)
    if not sourceRow then
        return false
    end

    CombatLogCollector.AddCount(sourceRow, "interrupts")
    CombatLogCollector.interruptCount = (CombatLogCollector.interruptCount or 0) + 1
    CombatLogCollector.lastInterruptName = creditName
    CombatLogCollector.lastInterruptAt = GetTime()
    return true
end

--- Records one SPELL_DISPEL event using the same source attribution as interrupts.
--- @param sourceGUID string|nil
--- @param sourceName string|nil
--- @param sourceFlags number|nil
--- @return boolean recorded
function CombatLogCollector.ProcessDispelEvent(sourceGUID, sourceName, sourceFlags)
    local creditGUID, creditName, creditFlags = CombatLogCollector.ResolveInterruptSource(
        sourceGUID,
        sourceName,
        sourceFlags
    )
    if not CombatLogCollector.IsAccessibleName(creditName) and not CombatLogCollector.CanUseGuid(creditGUID) then
        return false
    end

    local sourceRow = CombatLogCollector.GetPlayerRow(creditGUID, creditName, creditFlags)
    if not sourceRow then
        return false
    end

    CombatLogCollector.AddCount(sourceRow, "dispels")
    return true
end

--- Forces a minimal capture session when lifecycle hooks were missed but CLEU is firing.
--- @return boolean active
function CombatLogCollector.ForceArmMinimalSession()
    if CombatLogCollector.active then
        return true
    end

    if not CombatLogCollector.IsEnabled() or not CombatLogCollector.IsInLivePvpContext() then
        return false
    end

    if C_PvP and C_PvP.IsMatchComplete and C_PvP.IsMatchComplete() then
        return false
    end

    local matchCollector = PVL.MatchCollector
    local bracket = matchCollector and matchCollector.InferCollectibleBracket and matchCollector.InferCollectibleBracket()
        or (matchCollector and matchCollector.GetCurrentBracket and matchCollector.GetCurrentBracket())
    if not bracket then
        bracket = PVL.BRACKETS.BLITZ
    end

    local matchContext = matchCollector and matchCollector.activeMatch
    if not matchContext then
        if matchCollector and matchCollector.BuildActiveMatchContext then
            matchContext = matchCollector.BuildActiveMatchContext(bracket, true)
            if matchContext and matchCollector then
                matchCollector.activeMatch = matchContext
            end
        end
    end

    if not matchContext then
        matchContext = {
            bracket = bracket,
            sessionKey = string.format(
                "cleu:%s:%s",
                bracket or "pvp",
                tostring(C_Map.GetBestMapForUnit("player") or 0)
            ),
            startedAt = time(),
            runtimeMs = matchCollector and matchCollector.GetBattlefieldRuntimeMs and matchCollector.GetBattlefieldRuntimeMs() or 0,
            mapID = C_Map.GetBestMapForUnit("player"),
            segmentCount = 1,
        }
        if matchCollector then
            matchCollector.activeMatch = matchContext
        end
    end

    CombatLogCollector.StartMatch(matchContext)
    return CombatLogCollector.active
end

--- Returns true when combat log events should be tracked for the current match.
--- @return boolean
function CombatLogCollector.ShouldTrackCombatLog()
    if not CombatLogCollector.IsEnabled() then
        return false
    end

    if C_PvP and C_PvP.IsMatchComplete and C_PvP.IsMatchComplete() then
        return false
    end

    return CombatLogCollector.IsInLivePvpContext()
end

--- Arms combat-log capture for the current PvP instance, even when lifecycle hooks were missed.
--- @return boolean active
function CombatLogCollector.ArmForCurrentInstance()
    if CombatLogCollector.active then
        return true
    end

    if not CombatLogCollector.ShouldTrackCombatLog() then
        return false
    end

    local matchCollector = PVL.MatchCollector
    if not matchCollector then
        return false
    end

    if not matchCollector.activeMatch then
        if matchCollector.SyncMatchLifecycle then
            matchCollector.SyncMatchLifecycle()
        end
    end

    local bracket = matchCollector.InferCollectibleBracket and matchCollector.InferCollectibleBracket()
        or matchCollector.GetCurrentBracket and matchCollector.GetCurrentBracket()
    if not bracket and matchCollector.IsInCollectiblePvpInstance and matchCollector.IsInCollectiblePvpInstance() then
        bracket = PVL.BRACKETS.BLITZ
    end

    if matchCollector.ShouldCollectBracket and bracket and not matchCollector.ShouldCollectBracket(bracket) then
        return false
    end

    local matchContext = matchCollector.activeMatch
    if not matchContext and matchCollector.BuildActiveMatchContext then
        matchContext = matchCollector.BuildActiveMatchContext(bracket, true)
        if matchContext then
            matchCollector.activeMatch = matchContext
        end
    end

    if not matchContext then
        matchContext = {
            bracket = bracket,
            sessionKey = string.format(
                "live:%s:%s",
                bracket or "pvp",
                tostring(C_Map.GetBestMapForUnit("player") or 0)
            ),
            startedAt = time(),
            runtimeMs = matchCollector.GetBattlefieldRuntimeMs and matchCollector.GetBattlefieldRuntimeMs() or 0,
            mapID = C_Map.GetBestMapForUnit("player"),
            segmentCount = 1,
        }
    end

    CombatLogCollector.StartMatch(matchContext)
    return CombatLogCollector.active
end

--- Initializes the combat log collector for damage meter polling and CC listeners.
--- RegisterEvent is blocked in Midnight instanced PvP and still triggers BugGrabber via pcall.
function CombatLogCollector.Init()
    CombatLogCollector.useDamageMeterPolling = true
    CombatLogCollector.EnsureEventFrame()
end

--- Legacy hook retained for callers; combat data is polled instead of event-driven.
function CombatLogCollector.UpdateListening()
end

--- Starts tracking when a match is active but collection was not armed yet.
--- @return boolean active True when a match buffer is ready to receive events.
function CombatLogCollector.TryAutoStart()
    return CombatLogCollector.ArmForCurrentInstance()
end

--- Ensures capture is armed before processing one combat log event.
--- @return boolean active
function CombatLogCollector.EnsureArmedForEvent()
    if CombatLogCollector.active then
        return true
    end

    if not CombatLogCollector.IsInLivePvpContext() then
        return CombatLogCollector.TryAutoStart()
    end

    CombatLogCollector.ArmForCurrentInstance()
    if not CombatLogCollector.active then
        CombatLogCollector.ForceArmMinimalSession()
    end

    return CombatLogCollector.active
end

--- Handles one combat log event while a match is being tracked.
function CombatLogCollector.OnCombatLogEvent()
    if not CombatLogCollector.IsEnabled() then
        return
    end

    local timestamp, subEvent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags =
        CombatLogGetCurrentEventInfo()

    if subEvent == "SPELL_INTERRUPT" and CombatLogCollector.IsInLivePvpContext() then
        if CombatLogCollector.EnsureArmedForEvent() then
            CombatLogCollector.eventCount = (CombatLogCollector.eventCount or 0) + 1
            local spellId = select(12, CombatLogGetCurrentEventInfo())
            CombatLogCollector.AppendRawCombatEvent(subEvent, sourceGUID, sourceName, destGUID, destName, spellId, nil, nil)
            CombatLogCollector.ProcessInterruptEvent(sourceGUID, sourceName, sourceFlags)
        end
        return
    end

    if subEvent == "SPELL_DISPEL" and CombatLogCollector.IsInLivePvpContext() then
        if CombatLogCollector.EnsureArmedForEvent() then
            CombatLogCollector.eventCount = (CombatLogCollector.eventCount or 0) + 1
            local spellId = select(12, CombatLogGetCurrentEventInfo())
            CombatLogCollector.AppendRawCombatEvent(subEvent, sourceGUID, sourceName, destGUID, destName, spellId, nil, nil)
            CombatLogCollector.ProcessDispelEvent(sourceGUID, sourceName, sourceFlags)
        end
        return
    end

    if subEvent == "SPELL_AURA_APPLIED" and CombatLogCollector.IsInLivePvpContext() then
        if CombatLogCollector.EnsureArmedForEvent() then
            CombatLogCollector.eventCount = (CombatLogCollector.eventCount or 0) + 1
            local spellId, _, auraType = select(12, CombatLogGetCurrentEventInfo())
            CombatLogCollector.AppendRawCombatEvent(subEvent, sourceGUID, sourceName, destGUID, destName, spellId, auraType, nil)
            CombatLogCollector.ProcessCrowdControlAppliedEvent(
                sourceGUID,
                sourceName,
                sourceFlags,
                destGUID,
                destName,
                destFlags,
                spellId
            )
        end
        return
    end

    if not CombatLogCollector.EnsureArmedForEvent() then
        return
    end

    CombatLogCollector.eventCount = (CombatLogCollector.eventCount or 0) + 1

    local amountIndex = DAMAGE_SUBEVENTS[subEvent] or HEAL_SUBEVENTS[subEvent]
    if amountIndex then
        local amount = CombatLogCollector.GetAccessibleNumber(select(amountIndex, CombatLogGetCurrentEventInfo()))
        local spellId = select(12, CombatLogGetCurrentEventInfo())
        CombatLogCollector.AppendRawCombatEvent(subEvent, sourceGUID, sourceName, destGUID, destName, spellId, nil, amount)
        if DAMAGE_SUBEVENTS[subEvent] then
            local sourceRow = CombatLogCollector.GetPlayerRow(sourceGUID, sourceName, sourceFlags)
            local destRow = CombatLogCollector.GetPlayerRow(destGUID, destName, destFlags)
            if sourceRow and destRow and amount and amount > 0 then
                CombatLogCollector.AddAmount(sourceRow, "damage", amount)
                CombatLogCollector.AddAmount(destRow, "damageTaken", amount)
            end
        elseif HEAL_SUBEVENTS[subEvent] then
            local sourceRow = CombatLogCollector.GetPlayerRow(sourceGUID, sourceName, sourceFlags)
            if sourceRow and amount and amount > 0 then
                CombatLogCollector.AddAmount(sourceRow, "healing", amount)
            end
        end
    elseif subEvent == "UNIT_DIED" then
        CombatLogCollector.AppendRawCombatEvent(subEvent, sourceGUID, sourceName, destGUID, destName, nil, nil, nil)
        local destRow = CombatLogCollector.GetPlayerRow(destGUID, destName, destFlags)
        if destRow then
            CombatLogCollector.AddCount(destRow, "deaths")

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
end

--- Clears the in-memory combat log buffer without saving.
--- @param preserveListener boolean|nil
function CombatLogCollector.Reset(preserveListener)
    CombatLogCollector.active = false
    CombatLogCollector.startedAt = nil
    CombatLogCollector.startTimestamp = nil
    CombatLogCollector.eventCount = 0
    CombatLogCollector.interruptCount = 0
    CombatLogCollector.segmentCount = 1
    CombatLogCollector.players = {}
    CombatLogCollector.killEvents = {}
    CombatLogCollector.rawCombatEvents = {}
    CombatLogCollector.ResetCrowdControlTracking()
    CombatLogCollector.matchContext = nil
    CombatLogCollector.damageMeterSynced = false
    CombatLogCollector.lastDamageMeterSyncAt = nil
    CombatLogCollector.StopPersistTicker()
    CombatLogCollector.StopLiveSyncTicker()
end

--- Starts combat log capture for one active match.
--- @param matchContext table|nil
function CombatLogCollector.StartMatch(matchContext)
    if not CombatLogCollector.IsEnabled() then
        CombatLogCollector.StopMatch(true)
        return
    end

    if CombatLogCollector.active
        and matchContext
        and CombatLogCollector.matchContext then
        local sameSessionKey = matchContext.sessionKey
            and CombatLogCollector.matchContext.sessionKey == matchContext.sessionKey
        local sameFingerprint = matchContext.rosterFingerprint
            and CombatLogCollector.matchContext.rosterFingerprint == matchContext.rosterFingerprint
        if sameSessionKey or sameFingerprint then
            CombatLogCollector.matchContext = matchContext
            if matchContext.segmentCount then
                CombatLogCollector.segmentCount = matchContext.segmentCount
            end
            return
        end
    end

    local pending = CombatLogCollector.GetResumablePendingSession(matchContext)
    CombatLogCollector.active = true
    CombatLogCollector.matchContext = matchContext
    CombatLogCollector.startTimestamp = GetTime()

    if pending then
        CombatLogCollector.ImportPendingSession(pending, matchContext)
    else
        CombatLogCollector.startedAt = matchContext and matchContext.startedAt or time()
        CombatLogCollector.eventCount = 0
        CombatLogCollector.interruptCount = 0
        CombatLogCollector.segmentCount = matchContext and matchContext.segmentCount or 1
        CombatLogCollector.players = {}
        CombatLogCollector.killEvents = {}
        CombatLogCollector.rawCombatEvents = {}
        CombatLogCollector.ResetCrowdControlTracking()
    end

    CombatLogCollector.StartPersistTicker()
    CombatLogCollector.StartLiveSyncTicker()
    CombatLogCollector.PersistPendingSession(matchContext)
end

--- Stops combat log capture without building a summary.
--- @param preserveListener boolean|nil
function CombatLogCollector.StopMatch(preserveListener)
    CombatLogCollector.Reset(preserveListener)
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
    local damage = 0
    local healing = 0
    local interrupts = 0
    local dispels = 0
    local deaths = 0
    local ccApplied = 0
    local ccTaken = 0
    local damageTaken = combatRow and combatRow.damageTaken or 0

    if participant then
        damage = participant.damageDone or 0
        healing = participant.healingDone or 0
        interrupts = CombatLogCollector.ResolveSupplementCount(participant.interrupts, combatRow and combatRow.interrupts)
        dispels = CombatLogCollector.ResolveSupplementCount(participant.dispels, combatRow and combatRow.dispels)
        deaths = CombatLogCollector.ResolveSupplementCount(participant.deaths, combatRow and combatRow.deaths)
        damageTaken = CombatLogCollector.ResolveSupplementCount(nil, combatRow and combatRow.damageTaken)
        ccApplied = CombatLogCollector.ResolveSupplementCount(nil, combatRow and combatRow.ccApplied)
        ccTaken = CombatLogCollector.ResolveSupplementCount(nil, combatRow and combatRow.ccTaken)
    else
        damage = combatRow and combatRow.damage or 0
        healing = combatRow and combatRow.healing or 0
        interrupts = combatRow and combatRow.interrupts or 0
        dispels = combatRow and combatRow.dispels or 0
        deaths = combatRow and combatRow.deaths or 0
        ccApplied = combatRow and combatRow.ccApplied or 0
        ccTaken = combatRow and combatRow.ccTaken or 0
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
        interrupts = interrupts,
        dispels = dispels,
        deaths = deaths,
        ccApplied = ccApplied,
        ccTaken = ccTaken,
    }
end

--- Restores in-memory combat stats from the persisted pending session when needed.
--- @return boolean restored
function CombatLogCollector.RestorePendingSession()
    local matchCollector = PVL.MatchCollector
    if not matchCollector or not matchCollector.GetPendingCombatSession then
        return false
    end

    local pending = matchCollector.GetPendingCombatSession()
    if type(pending) ~= "table" then
        return false
    end

    local hasPlayers = pending.players and next(pending.players) ~= nil
    local hasEvents = (pending.eventCount or 0) > 0 or pending.damageMeterSynced == true
    if not hasPlayers and not hasEvents then
        return false
    end

    if (CombatLogCollector.eventCount or 0) > 0 and next(CombatLogCollector.players or {}) ~= nil then
        return false
    end

    CombatLogCollector.ImportPendingSession(pending, {
        bracket = pending.bracket,
        segmentCount = pending.segmentCount,
        startedAt = pending.startedAt,
    })
    return true
end

--- Builds a compact export-friendly combat summary for one match.
--- @param roster table[]|nil
--- @param matchContext table|nil Active match metadata used to resolve the match window.
--- @return table|nil
function CombatLogCollector.BuildSummary(roster, matchContext)
    matchContext = matchContext or CombatLogCollector.matchContext
    roster = roster or {}

    local window = CombatLogCollector.ResolveMatchWindow(matchContext)
    local meterSupplement = {}
    local supplementSynced = false
    local matchCollector = PVL.MatchCollector
    local pending = matchCollector and matchCollector.GetPendingCombatSession and matchCollector.GetPendingCombatSession()

    if pending and pending.players then
        CombatLogCollector.ImportSupplementFieldsFromPlayerMap(meterSupplement, pending.players)
    end

    if CombatLogCollector.IsDamageMeterAvailable() then
        supplementSynced = CombatLogCollector.SyncDamageMeterSupplementForWindow(window, meterSupplement) or supplementSynced
        supplementSynced = CombatLogCollector.FetchSupplementCountsForRoster(roster, window, meterSupplement) or supplementSynced
    end

    local endedAt = window.endedAt or time()
    local duration = window.durationSeconds
    if (not duration or duration <= 0) and CombatLogCollector.startedAt then
        duration = math.max(0, endedAt - CombatLogCollector.startedAt)
    end
    if (not duration or duration <= 0)
        and CombatLogCollector.IsDamageMeterAvailable()
        and C_DamageMeter
        and C_DamageMeter.GetSessionDurationSeconds then
        local ok, seconds = pcall(C_DamageMeter.GetSessionDurationSeconds, DAMAGE_METER_SESSION_CURRENT)
        if ok and seconds and seconds > 0 then
            duration = seconds
        end
    end

    local useScoreboard = CombatLogCollector.RosterHasScoreboardCombatTotals(roster)
    local dataSource = useScoreboard and "scoreboard" or CombatLogCollector.GetDataSourceLabel()
    local playerRows = {}

    for _, participant in ipairs(roster) do
        local meterRow = CombatLogCollector.LookupMeterRowForParticipant(participant, meterSupplement)
        table.insert(playerRows, CombatLogCollector.BuildPlayerSummaryRow(
            participant.guid,
            meterRow,
            participant
        ))
    end

    table.sort(playerRows, function(a, b)
        if a.team == b.team then
            local leftDamage = tonumber(a.damage) or 0
            local rightDamage = tonumber(b.damage) or 0
            if leftDamage == rightDamage then
                return (a.name or "") < (b.name or "")
            end
            return leftDamage > rightDamage
        end

        return a.team == "friendly"
    end)

    local sessionId = nil
    if CombatLogCollector.IsDamageMeterAvailable() and C_DamageMeter.GetCurrentSessionID then
        local ok, currentSessionId = pcall(C_DamageMeter.GetCurrentSessionID)
        if ok then
            sessionId = currentSessionId
        end
    end

    for _, row in ipairs(playerRows) do
        if row.guid then
            row.spells = CombatLogCollector.CollectPlayerSpellBreakdown(row.guid, sessionId)
        end
    end

    if #playerRows == 0 then
        CombatLogCollector.StopMatch(true)
        return nil
    end

    local summary = {
        startedAt = window.startedAt or CombatLogCollector.startedAt,
        endedAt = endedAt,
        duration = duration,
        killEvents = CombatLogCollector.killEvents or {},
        players = playerRows,
        combatLogCaptured = useScoreboard or supplementSynced or (pending and pending.players ~= nil),
        dataSource = dataSource,
        eventCount = CombatLogCollector.eventCount or 0,
        interruptCount = CombatLogCollector.interruptCount or 0,
        rawCombatEvents = CombatLogCollector.CloneRawCombatEvents(CombatLogCollector.rawCombatEvents),
        segmentCount = CombatLogCollector.segmentCount or 1,
        matchWindowResolved = window.durationSeconds ~= nil,
    }

    CombatLogCollector.StopMatch(true)
    return summary
end
