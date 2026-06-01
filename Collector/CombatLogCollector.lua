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

local PERSIST_INTERVAL_SECONDS = 15
local LIVE_SYNC_INTERVAL_SECONDS = 3
local DAMAGE_METER_SESSION_OVERALL = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall or 0
local DAMAGE_METER_SESSION_CURRENT = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
local DAMAGE_METER_SYNC_TYPES = {
    [Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0] = "damage",
    [Enum and Enum.DamageMeterType and Enum.DamageMeterType.HealingDone or 2] = "healing",
    [Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageTaken or 7] = "damageTaken",
    [Enum and Enum.DamageMeterType and Enum.DamageMeterType.Deaths or 9] = "deaths",
}
local DAMAGE_METER_TYPE_INTERRUPTS = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Interrupts or 5
local DAMAGE_METER_TYPE_DISPELS = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Dispels or 6
local MERGE_COUNT_FIELDS = { "interrupts", "dispels", "deaths" }
local MERGE_AMOUNT_FIELDS = { "damage", "healing", "damageTaken" }
local COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400

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

    local countOk, sourceCount = pcall(function()
        return #sources
    end)
    if not countOk or not sourceCount or sourceCount <= 0 then
        return
    end

    for index = 1, sourceCount do
        local source = sources[index]
        if type(source) == "table" then
            callback(source)
        end
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
    }
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
        savedAt = time(),
    }
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

--- Initializes the combat log collector for damage meter polling.
--- RegisterEvent is blocked in Midnight instanced PvP and still triggers BugGrabber via pcall.
function CombatLogCollector.Init()
    CombatLogCollector.useDamageMeterPolling = true
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
            CombatLogCollector.ProcessInterruptEvent(sourceGUID, sourceName, sourceFlags)
        end
        return
    end

    if subEvent == "SPELL_DISPEL" and CombatLogCollector.IsInLivePvpContext() then
        if CombatLogCollector.EnsureArmedForEvent() then
            CombatLogCollector.eventCount = (CombatLogCollector.eventCount or 0) + 1
            CombatLogCollector.ProcessDispelEvent(sourceGUID, sourceName, sourceFlags)
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
    local damage = combatRow and combatRow.damage or 0
    local healing = combatRow and combatRow.healing or 0
    local damageTaken = combatRow and combatRow.damageTaken or 0
    local interrupts = combatRow and combatRow.interrupts or 0
    local dispels = combatRow and combatRow.dispels or 0
    local deaths = combatRow and combatRow.deaths or 0

    if participant then
        if participant.damageDone and participant.damageDone > damage then
            damage = participant.damageDone
        end
        if participant.healingDone and participant.healingDone > healing then
            healing = participant.healingDone
        end
        if participant.interrupts and participant.interrupts > interrupts then
            interrupts = participant.interrupts
        end
        if participant.dispels and participant.dispels > dispels then
            dispels = participant.dispels
        end
        if participant.deaths and participant.deaths > deaths then
            deaths = participant.deaths
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
        interrupts = interrupts,
        dispels = dispels,
        deaths = deaths,
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
--- @return table|nil
function CombatLogCollector.BuildSummary(roster)
    CombatLogCollector.RestorePendingSession()
    if CombatLogCollector.IsDamageMeterAvailable() then
        CombatLogCollector.SyncFromDamageMeter()
    end
    local endedAt = time()
    local duration = CombatLogCollector.startedAt and math.max(0, endedAt - CombatLogCollector.startedAt) or nil
    if (not duration or duration <= 0)
        and CombatLogCollector.IsDamageMeterAvailable()
        and C_DamageMeter
        and C_DamageMeter.GetSessionDurationSeconds then
        local ok, seconds = pcall(C_DamageMeter.GetSessionDurationSeconds, DAMAGE_METER_SESSION_CURRENT)
        if ok and seconds and seconds > 0 then
            duration = seconds
        end
    end
    local rosterByGuid = {}
    local rosterByName = {}
    local includedGuids = {}

    for _, participant in ipairs(roster or {}) do
        if participant.guid then
            rosterByGuid[participant.guid] = participant
        end
        local nameKey = CombatLogCollector.NormalizeName(participant.name)
        if nameKey then
            rosterByName[nameKey] = participant
        end
    end

    local capturedEventCount = CombatLogCollector.eventCount or 0
    local capturedInterruptCount = CombatLogCollector.interruptCount or 0
    local damageMeterCaptured = CombatLogCollector.damageMeterSynced == true
    local dataSource = CombatLogCollector.GetDataSourceLabel()
    local playerRows = {}
    for storageKey, row in pairs(CombatLogCollector.players) do
        includedGuids[storageKey] = true
        local participant = rosterByGuid[storageKey]
        if not participant and type(storageKey) == "string" and storageKey:find("^name:") then
            participant = rosterByName[storageKey:sub(6)]
        end
        if not participant and row.name then
            participant = rosterByName[CombatLogCollector.NormalizeName(row.name)]
        end

        local rowGuid = row.guid
        if not rowGuid and type(storageKey) == "string" and not storageKey:find("^name:") then
            rowGuid = storageKey
        end

        table.insert(playerRows, CombatLogCollector.BuildPlayerSummaryRow(rowGuid, row, participant))
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
            local participantKey = CombatLogCollector.NormalizeName(participant.name)
            for _, row in ipairs(playerRows) do
                if participant.guid and row.guid == participant.guid then
                    existing = true
                    break
                end
                if participantKey and CombatLogCollector.NormalizeName(row.name) == participantKey then
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
            local leftDamage = tonumber(a.damage) or 0
            local rightDamage = tonumber(b.damage) or 0
            if leftDamage == rightDamage then
                return (a.name or "") < (b.name or "")
            end
            return leftDamage > rightDamage
        end

        return a.team == "friendly"
    end)

    if #playerRows == 0 then
        CombatLogCollector.StopMatch(true)
        return nil
    end

    local summary = {
        startedAt = CombatLogCollector.startedAt,
        endedAt = endedAt,
        duration = duration,
        killEvents = CombatLogCollector.killEvents,
        players = playerRows,
        combatLogCaptured = capturedEventCount > 0
            or damageMeterCaptured
            or capturedInterruptCount > 0,
        dataSource = dataSource,
        eventCount = capturedEventCount,
        interruptCount = capturedInterruptCount,
        segmentCount = CombatLogCollector.segmentCount or 1,
    }

    CombatLogCollector.StopMatch(true)
    return summary
end
