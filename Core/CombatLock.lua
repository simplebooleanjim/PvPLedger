--- Helpers to avoid tainting secure Blizzard UI such as action bars during combat.
--- @class PvPLedger
local PVL = PvPLedger

PVL._pendingUiRefresh = PVL._pendingUiRefresh or false
PVL._deferredLifecycleSync = PVL._deferredLifecycleSync or false
PVL._combatLockFrame = PVL._combatLockFrame or nil

--- Returns true when secure Blizzard UI must not be modified by addon code.
--- @return boolean
function PVL.IsCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

--- Returns true when addon windows and settings may be opened safely.
--- @return boolean
function PVL.CanOpenAddonWindows()
    return not PVL.IsCombatLocked()
end

--- Returns true when any PvPLedger window is currently visible.
--- @return boolean
function PVL.IsAnyAddonWindowShown()
    return PVL.UI
        and PVL.UI.AnyWindowShown
        and PVL.UI.AnyWindowShown()
        or false
end

--- Runs deferred collector and UI work after combat ends.
function PVL.FlushCombatDeferredWork()
    PVL.FlushPendingUiRefresh()

    if PVL.InspectQueue then
        if PVL.InspectQueue.FlushDeferredInspect then
            PVL.InspectQueue.FlushDeferredInspect()
        end
        if PVL.InspectQueue.FlushPendingRosterEnqueue then
            PVL.InspectQueue.FlushPendingRosterEnqueue()
        end
        if PVL.InspectQueue.ProcessNext then
            PVL.InspectQueue.ProcessNext()
        end
    end

    if PVL.CombatLogCollector then
        if PVL.CombatLogCollector.ResumeBackgroundSync then
            PVL.CombatLogCollector.ResumeBackgroundSync()
        elseif PVL.CombatLogCollector.TryLiveSync and PVL.CombatLogCollector.active then
            pcall(PVL.CombatLogCollector.TryLiveSync)
        end
    end

    if PVL._deferredLifecycleSync and PVL.MatchCollector and PVL.MatchCollector.SyncMatchLifecycle then
        PVL._deferredLifecycleSync = false
        pcall(PVL.MatchCollector.SyncMatchLifecycle)
    end
end

--- Pauses background collectors that must not run during combat lockdown.
function PVL.OnCombatLockdownStarted()
    PVL._deferredLifecycleSync = true
    PVL.EnsureCombatLockEvents()

    if PVL.InspectQueue and PVL.InspectQueue.Clear then
        PVL.InspectQueue.Clear()
    end

    if PVL.CombatLogCollector and PVL.CombatLogCollector.PauseBackgroundSync then
        PVL.CombatLogCollector.PauseBackgroundSync()
    end
end

--- Registers the out-of-combat flush listener once.
function PVL.EnsureCombatLockEvents()
    if PVL._combatLockFrame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            PVL.FlushCombatDeferredWork()
        elseif event == "PLAYER_REGEN_DISABLED" then
            PVL.OnCombatLockdownStarted()
        end
    end)
    PVL._combatLockFrame = frame
end

--- Refreshes addon UI immediately or defers until combat ends.
function PVL.RequestUiRefresh()
    if not PVL.IsAnyAddonWindowShown() then
        return
    end

    if PVL.IsCombatLocked() then
        PVL._pendingUiRefresh = true
        PVL.EnsureCombatLockEvents()
        return
    end

    if PVL.UI and PVL.UI.Refresh then
        pcall(PVL.UI.Refresh)
    end
end

--- Runs a deferred UI refresh after combat ends when one was requested.
function PVL.FlushPendingUiRefresh()
    if not PVL._pendingUiRefresh or PVL.IsCombatLocked() then
        return
    end

    PVL._pendingUiRefresh = false

    if not PVL.IsAnyAddonWindowShown() then
        return
    end

    if PVL.UI and PVL.UI.Refresh then
        pcall(PVL.UI.Refresh)
    end
end
