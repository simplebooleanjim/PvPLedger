--- Rate-limited inspect queue for capturing specialization data mid-match.
--- @class PvPLedger
local PVL = PvPLedger

PVL.InspectQueue = PVL.InspectQueue or {}
local InspectQueue = PVL.InspectQueue

InspectQueue.pending = InspectQueue.pending or {}
InspectQueue.processing = false
InspectQueue.frame = InspectQueue.frame or nil
InspectQueue.pendingRosterCallback = InspectQueue.pendingRosterCallback or nil

--- Initializes the inspect queue event frame.
function InspectQueue.Init()
    if InspectQueue.frame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("INSPECT_READY")
    frame:SetScript("OnEvent", function(_, event, guid)
        if event == "INSPECT_READY" then
            InspectQueue.OnInspectReady(guid)
        end
    end)

    InspectQueue.frame = frame
end

--- Enqueues one unit for spec inspection if not already queued.
--- @param unit string
--- @param callback function|nil
function InspectQueue.Enqueue(unit, callback)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
        return
    end

    local guid = UnitGUID(unit)
    if not guid or InspectQueue.pending[guid] then
        return
    end

    InspectQueue.pending[guid] = {
        unit = unit,
        callback = callback,
        queuedAt = GetTime(),
    }

    InspectQueue.ProcessNext()
end

--- Processes the next queued inspect request when the queue is idle.
function InspectQueue.ProcessNext()
    InspectQueue.Init()

    if PVL.IsCombatLocked and PVL.IsCombatLocked() then
        if PVL.EnsureCombatLockEvents then
            PVL.EnsureCombatLockEvents()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(PVL.INSPECT_DELAY_SECONDS, InspectQueue.ProcessNext)
        end
        return
    end

    if InspectQueue.processing then
        return
    end

    local nextGuid, request = next(InspectQueue.pending)
    if not nextGuid or not request then
        return
    end

    if not UnitExists(request.unit) then
        InspectQueue.pending[nextGuid] = nil
        C_Timer.After(PVL.INSPECT_DELAY_SECONDS, InspectQueue.ProcessNext)
        return
    end

    InspectQueue.processing = true
    NotifyInspect(request.unit)
end

--- Handles INSPECT_READY and invokes the queued callback with spec info.
--- @param guid string
function InspectQueue.OnInspectReady(guid)
    if PVL.IsCombatLocked and PVL.IsCombatLocked() then
        if PVL.EnsureCombatLockEvents then
            PVL.EnsureCombatLockEvents()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(PVL.INSPECT_DELAY_SECONDS, function()
                InspectQueue.OnInspectReady(guid)
            end)
        end
        return
    end

    local request = InspectQueue.pending[guid]
    InspectQueue.processing = false

    if not request then
        C_Timer.After(PVL.INSPECT_DELAY_SECONDS, InspectQueue.ProcessNext)
        return
    end

    local classToken = select(2, UnitClass(request.unit))
    local specIndex = GetInspectSpecialization(request.unit)
    local specKey

    if specIndex and specIndex > 0 and classToken then
        local specKeys = PVL.SPEC_KEYS_BY_CLASS[classToken]
        specKey = specKeys and specKeys[specIndex] or nil
    end

    if request.callback then
        request.callback({
            guid = guid,
            unit = request.unit,
            name = GetUnitName(request.unit, true),
            class = classToken,
            spec = specKey,
        })
    end

    InspectQueue.pending[guid] = nil
    C_Timer.After(PVL.INSPECT_DELAY_SECONDS, InspectQueue.ProcessNext)
end

--- Clears all pending inspect requests.
function InspectQueue.Clear()
    wipe(InspectQueue.pending)
    InspectQueue.processing = false
    InspectQueue.pendingRosterCallback = nil
end

--- Scans raid/party/nameplate units and queues spec inspects for one match roster.
--- @param callback function
function InspectQueue.RunMatchRosterEnqueue(callback)
    if type(callback) ~= "function" then
        return
    end

    local function scan(prefix, maxCount)
        for index = 1, maxCount do
            local unit = string.format("%s%d", prefix, index)
            if UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
                InspectQueue.Enqueue(unit, callback)
            end
        end
    end

    scan("raid", 40)
    scan("party", 4)
    scan("nameplate", 40)
end

--- Runs a roster inspect pass that was deferred until combat ended.
function InspectQueue.FlushPendingRosterEnqueue()
    local callback = InspectQueue.pendingRosterCallback
    if not callback or (PVL.IsCombatLocked and PVL.IsCombatLocked()) then
        return
    end

    InspectQueue.pendingRosterCallback = nil
    InspectQueue.RunMatchRosterEnqueue(callback)
end

--- Queues inspects for all visible enemy and friendly players in the active match.
--- @param callback function
function InspectQueue.EnqueueMatchRoster(callback)
    if type(callback) ~= "function" then
        return
    end

    if PVL.IsCombatLocked and PVL.IsCombatLocked() then
        InspectQueue.pendingRosterCallback = callback
        if PVL.EnsureCombatLockEvents then
            PVL.EnsureCombatLockEvents()
        end
        return
    end

    InspectQueue.RunMatchRosterEnqueue(callback)
end
