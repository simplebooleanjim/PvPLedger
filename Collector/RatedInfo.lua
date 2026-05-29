--- Tracks live rated PvP CR from the same source as the in-game queue menu.
--- @class PvPLedger
local PVL = PvPLedger

PVL.RatedInfo = PVL.RatedInfo or {}
local RatedInfo = PVL.RatedInfo

RatedInfo.frame = RatedInfo.frame or nil
RatedInfo.ratedInfoByBracket = RatedInfo.ratedInfoByBracket or {}
RatedInfo.requestPending = RatedInfo.requestPending or false

local LOGIN_REFRESH_SECONDS = 1.5

--- Returns a usable number when the client allows addon access.
--- @param value any
--- @return number|nil
local function GetAccessibleNumber(value)
    if PVL.MatchCollector and PVL.MatchCollector.GetAccessibleNumber then
        return PVL.MatchCollector.GetAccessibleNumber(value)
    end

    if value == nil then
        return nil
    end

    return tonumber(value)
end

--- Returns the GetPersonalRatedInfo index for one PvPLedger bracket.
--- @param bracket string|nil
--- @return number|nil
function RatedInfo.GetRatedInfoIndex(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    return PVL.RATED_INFO_INDEX_BY_BRACKET[bracket]
end

--- Reads rated PvP stats for one bracket from the client (same source as the PvP UI).
--- @param bracket string|nil
--- @return table|nil info `{ rating, seasonBest, seasonPlayed, seasonWon, seasonLost, winPct, ... }`
function RatedInfo.ReadPersonalRatedInfo(bracket)
    if not GetPersonalRatedInfo then
        return nil
    end

    local index = RatedInfo.GetRatedInfoIndex(bracket)
    if not index then
        return nil
    end

    local rating, seasonBest, weeklyBest, seasonPlayed, seasonWon, weeklyPlayed, weeklyWon, cap =
        GetPersonalRatedInfo(index)

    seasonPlayed = GetAccessibleNumber(seasonPlayed) or 0
    seasonWon = GetAccessibleNumber(seasonWon) or 0
    local seasonLost = math.max(seasonPlayed - seasonWon, 0)

    return {
        rating = GetAccessibleNumber(rating),
        seasonBest = GetAccessibleNumber(seasonBest),
        weeklyBest = GetAccessibleNumber(weeklyBest),
        seasonPlayed = seasonPlayed,
        seasonWon = seasonWon,
        seasonLost = seasonLost,
        weeklyPlayed = GetAccessibleNumber(weeklyPlayed) or 0,
        weeklyWon = GetAccessibleNumber(weeklyWon) or 0,
        cap = GetAccessibleNumber(cap),
        winPct = seasonPlayed > 0 and ((seasonWon / seasonPlayed) * 100) or nil,
    }
end

--- Reads the current CR for one bracket from client rated-info cache.
--- @param bracket string|nil
--- @return number|nil
function RatedInfo.ReadCurrentRating(bracket)
    local info = RatedInfo.ReadPersonalRatedInfo(bracket)
    return info and info.rating or nil
end

--- Refreshes cached rated-info values for all supported brackets.
function RatedInfo.RefreshAll()
    RatedInfo.ratedInfoByBracket = {}

    for bracket in pairs(PVL.RATED_INFO_INDEX_BY_BRACKET) do
        RatedInfo.ratedInfoByBracket[bracket] = RatedInfo.ReadPersonalRatedInfo(bracket)
    end
end

--- Refreshes rated CR and updates the main UI when it is visible.
function RatedInfo.RefreshAndNotify()
    RatedInfo.RefreshAll()

    if PVL.UI and PVL.UI.frame and PVL.UI.frame:IsShown() and PVL.UI.Refresh then
        PVL.UI.Refresh()
    end
end

--- Returns cached rated-info for one bracket, reading from the client when needed.
--- @param bracket string|nil
--- @return table|nil
function RatedInfo.GetRatedInfo(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()
    RatedInfo.ratedInfoByBracket = RatedInfo.ratedInfoByBracket or {}

    local info = RatedInfo.ratedInfoByBracket[bracket]
    if info == nil then
        info = RatedInfo.ReadPersonalRatedInfo(bracket)
        RatedInfo.ratedInfoByBracket[bracket] = info
    end

    return info
end

--- Returns the cached current CR for one bracket.
--- @param bracket string|nil
--- @return number|nil
function RatedInfo.GetCurrentRating(bracket)
    local info = RatedInfo.GetRatedInfo(bracket)
    return info and info.rating or nil
end

--- Returns the current season win/loss record for one bracket from the PvP rated menu.
--- @param bracket string|nil
--- @return table|nil record `{ wins, losses, games, winPct, seasonBest }`
function RatedInfo.GetSeasonRecord(bracket)
    local info = RatedInfo.GetRatedInfo(bracket)
    if not info or not info.seasonPlayed or info.seasonPlayed <= 0 then
        return nil
    end

    return {
        wins = info.seasonWon,
        losses = info.seasonLost,
        games = info.seasonPlayed,
        winPct = info.winPct,
        seasonBest = info.seasonBest,
    }
end

--- Asks the client to refresh rated PvP stats from the server.
function RatedInfo.RequestUpdate()
    if not RequestRatedInfo or RatedInfo.requestPending then
        return
    end

    RatedInfo.requestPending = true
    RequestRatedInfo()
end

--- Clears the pending request flag after the client responds.
function RatedInfo.OnRatedStatsUpdate()
    RatedInfo.requestPending = false
    RatedInfo.RefreshAll()

    if PVL.CrHistory then
        PVL.CrHistory.RecordAllSnapshots()
    end

    if PVL.UI and PVL.UI.frame and PVL.UI.frame:IsShown() and PVL.UI.Refresh then
        PVL.UI.Refresh()
    end
end

--- Schedules an initial rated-info refresh shortly after login.
function RatedInfo.ScheduleLoginRefresh()
    C_Timer.After(LOGIN_REFRESH_SECONDS, function()
        RatedInfo.RequestUpdate()
    end)
end

--- Dispatches rated-info collector events.
--- @param event string
function RatedInfo.OnEvent(event)
    if event == "PLAYER_LOGIN" then
        RatedInfo.ScheduleLoginRefresh()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RatedInfo.RequestUpdate()
    elseif event == "PVP_RATED_STATS_UPDATE" then
        RatedInfo.OnRatedStatsUpdate()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        RatedInfo.RequestUpdate()
    end
end

--- Initializes the rated-info collector frame and events.
function RatedInfo.Init()
    if RatedInfo.frame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PVP_RATED_STATS_UPDATE")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:SetScript("OnEvent", function(_, event)
        RatedInfo.OnEvent(event)
    end)

    RatedInfo.frame = frame
end

--- Prints current rated-info values for debugging.
function RatedInfo.PrintDebug()
    RatedInfo.RefreshAll()

    print("|cff66ccffPvPLedger|r rated-info debug:")
    for _, bracket in ipairs(PVL.DEFAULT_COLLECTED_BRACKETS) do
        local index = RatedInfo.GetRatedInfoIndex(bracket)
        local info = RatedInfo.GetRatedInfo(bracket)
        local bracketName = PVL.BRACKET_NAMES[bracket] or bracket
        print(string.format(
            "  %s index=%s currentCR=%s season=%s-%s (%.1f%%)",
            bracketName,
            tostring(index),
            tostring(info and info.rating or "nil"),
            tostring(info and info.seasonWon or 0),
            tostring(info and info.seasonLost or 0),
            info and info.winPct or 0
        ))
    end
end
