--- Seasonal PvP title cutoff rules and rating estimates for PvPLedger.
---
--- Titles such as Rank 1, Gladiator, and Hero of the Alliance/Horde are awarded
--- to the top N% of the rated ladder at season end. This module encodes those
--- rules, then resolves the rating needed to reach each title using the loaded
--- ladder snapshot. Percentile cutoffs (and the full rated population they are
--- based on) are computed by the external collector and shipped in each snapshot
--- under ``overall.titleCutoffs`` / ``overall.ratedPopulation``. When that data
--- is missing this module falls back to estimating from listed player ranks.
--- @class PvPLedger
local PVL = PvPLedger

-- ---------------------------------------------------------------------------
-- Title colors
-- ---------------------------------------------------------------------------

--- Hex colors (|cAARRGGBB) used to render each title tier.
PVL.TITLE_COLORS = {
    COMBATANT = "FF9D9D9D",
    CHALLENGER = "FF1EFF00",
    RIVAL = "FF0070DD",
    DUELIST = "FFA335EE",
    ELITE = "FFFF8000",
    GLADIATOR = "FFE6CC80",
    HERO = "FFE6CC80",
    LEGEND = "FFE6CC80",
    RANK_ONE = "FFFF4D4D",
}

-- ---------------------------------------------------------------------------
-- Faction-aware title names
-- ---------------------------------------------------------------------------

--- Returns the player's faction group when it is Alliance or Horde.
--- @return string|nil "Alliance", "Horde", or nil when unknown.
function PVL.GetPlayerFaction()
    if not UnitFactionGroup then
        return nil
    end

    local faction = UnitFactionGroup("player")
    if faction == "Alliance" or faction == "Horde" then
        return faction
    end

    return nil
end

--- Builds a faction-specific title name, defaulting to both when unknown.
--- @param allianceName string Title shown to Alliance players.
--- @param hordeName string Title shown to Horde players.
--- @param faction string|nil Resolved player faction.
--- @return string
local function FactionTitle(allianceKey, hordeKey, faction)
    if faction == "Horde" then
        return PVL.L(hordeKey)
    end

    if faction == "Alliance" then
        return PVL.L(allianceKey)
    end

    return PVL.L("TITLE.FACTION_DUAL", PVL.L(allianceKey), PVL.L(hordeKey))
end

-- ---------------------------------------------------------------------------
-- Title definitions
-- ---------------------------------------------------------------------------
--- Each definition describes one title tier:
---   id        Stable identifier.
---   name      Display name, or function(faction) -> string.
---   kind      "rating" for fixed thresholds, "percentile" for ladder cutoffs,
---             "spec_rank" for per-spec fixed rank cutoffs (Blitz / Shuffle Rank 1).
---   rating    Fixed rating threshold (kind == "rating").
---   percentile Top-percent of the ladder (kind == "percentile", e.g. 0.1).
---   rank      Fixed ladder rank within one spec (kind == "spec_rank", e.g. 8).
---   wins      Season games-won requirement, when applicable.
---   color     TITLE_COLORS hex.
---   feat      True for end-of-season feats of strength (the prestige titles).
---   note      Optional clarifying text.

local C = PVL.TITLE_COLORS

--- Current-season rating required for the Elite title in all brackets.
PVL.ELITE_RATING = 2300

--- Per-spec Rank 1 slots for Solo Shuffle and Battleground Blitz (Galactic Legend /
--- Marshal / Warlord). Blizzard awards these to the top N players of each spec.
PVL.PER_SPEC_RANK1_SLOTS = 8

--- Fixed rating tiers shared by every bracket (Combatant through Elite).
--- @return table[]
local function BuildFixedRatingTiers()
    return {
        { id = "combatant", locKey = "TITLE.COMBATANT", name = "Combatant", kind = "rating", rating = 1000, color = C.COMBATANT },
        { id = "challenger", locKey = "TITLE.CHALLENGER", name = "Challenger", kind = "rating", rating = 1400, color = C.CHALLENGER },
        { id = "rival", locKey = "TITLE.RIVAL", name = "Rival", kind = "rating", rating = 1800, color = C.RIVAL },
        { id = "duelist", locKey = "TITLE.DUELIST", name = "Duelist", kind = "rating", rating = 2100, color = C.DUELIST },
        { id = "elite", locKey = "TITLE.ELITE", name = "Elite", kind = "rating", rating = PVL.ELITE_RATING, color = C.ELITE },
    }
end

--- Concatenates extra title rows onto the shared fixed rating tiers.
--- @param extras table[] Bracket-specific percentile/feat titles.
--- @return table[]
local function WithFixedTiers(extras)
    local tiers = BuildFixedRatingTiers()
    for _, def in ipairs(extras) do
        table.insert(tiers, def)
    end
    return tiers
end

--- Title definitions keyed by PvPLedger bracket id.
PVL.TITLE_DEFINITIONS = {
    [PVL.BRACKETS.ARENA_3V3] = WithFixedTiers({
        {
            id = "gladiator",
            locKey = "TITLE.GLADIATOR",
            name = "Gladiator",
            kind = "rating",
            rating = PVL.ELITE_RATING,
            wins = 50,
            color = C.GLADIATOR,
            feat = true,
            note = "Win 50 games at Elite (2300+) on the 3v3 ladder; not a percentile.",
        },
        {
            id = "rank1",
            locKey = "TITLE.RANK1_GLADIATOR",
            name = "Rank 1: Prized Gladiator",
            kind = "percentile",
            percentile = 0.1,
            wins = 150,
            color = C.RANK_ONE,
            feat = true,
            note = "Top 0.1% of the overall 3v3 ladder at season end, 150 wins required.",
        },
    }),

    [PVL.BRACKETS.ARENA_2V2] = WithFixedTiers({}),

    [PVL.BRACKETS.SHUFFLE] = WithFixedTiers({
        {
            id = "legend",
            locKey = "TITLE.LEGEND",
            name = "Legend",
            kind = "rating",
            rating = PVL.ELITE_RATING,
            wins = 100,
            color = C.LEGEND,
            feat = true,
            note = "100 Solo Shuffle round wins at Elite (2300+).",
        },
        {
            id = "rank1",
            locKey = "TITLE.RANK1_LEGEND",
            name = "Rank 1: Prized Legend",
            kind = "spec_rank",
            rank = PVL.PER_SPEC_RANK1_SLOTS,
            wins = 50,
            color = C.RANK_ONE,
            feat = true,
            note = string.format(
                "Top %d players on your Solo Shuffle specialization ladder, 50 wins required.",
                PVL.PER_SPEC_RANK1_SLOTS
            ),
        },
    }),

    [PVL.BRACKETS.RBG] = WithFixedTiers({
        {
            id = "guardian",
            name = function(faction)
                return FactionTitle("TITLE.GUARDIAN_ALLIANCE", "TITLE.GUARDIAN_HORDE", faction)
            end,
            kind = "percentile",
            percentile = 3.0,
            color = C.RIVAL,
            note = "Top 3.0% of the Rated Battleground ladder.",
        },
        {
            id = "hero",
            name = function(faction)
                return FactionTitle("TITLE.HERO_ALLIANCE", "TITLE.HERO_HORDE", faction)
            end,
            kind = "percentile",
            percentile = 0.5,
            wins = 50,
            color = C.HERO,
            feat = true,
            note = "Top 0.5% of the Rated Battleground ladder, 50 wins required.",
        },
    }),

    [PVL.BRACKETS.BLITZ] = WithFixedTiers({
        {
            id = "rank1",
            name = function(faction)
                return FactionTitle("TITLE.RANK1_MARSHAL", "TITLE.RANK1_WARLORD", faction)
            end,
            kind = "spec_rank",
            rank = PVL.PER_SPEC_RANK1_SLOTS,
            wins = 50,
            color = C.RANK_ONE,
            feat = true,
            note = string.format(
                "Top %d players on your Battleground Blitz specialization ladder, 50 wins required. Blitz has no Hero title.",
                PVL.PER_SPEC_RANK1_SLOTS
            ),
        },
    }),
}

-- ---------------------------------------------------------------------------
-- Seasonal title achievement tracking (Blitz Strategist, Shuffle Legend, ...)
-- ---------------------------------------------------------------------------

--- Achievement id for "Strategist: Midnight Season 1" (Battleground Blitz).
PVL.STRATEGIST_ACHIEVEMENT_ID = 61194

--- Achievement id for "Legend: Midnight Season 1" (Solo Shuffle).
PVL.LEGEND_ACHIEVEMENT_ID = 61190

--- Bracket-specific seasonal achievements that can be pinned to the objectives tracker.
--- placement:
---   before_rank1 - insert a dedicated row before the Rank 1 feat line
---   title_row    - replace the matching title definition row with a clickable tracker row
PVL.SEASON_ACHIEVEMENT_BY_BRACKET = {
    [PVL.BRACKETS.BLITZ] = {
        achievementId = PVL.STRATEGIST_ACHIEVEMENT_ID,
        defaultRequired = 25,
        fallbackName = "Strategist",
        defId = "strategist",
        color = PVL.TITLE_COLORS.ELITE,
        placement = "before_rank1",
        ruleDetail = "rated Blitz matches",
    },
    [PVL.BRACKETS.SHUFFLE] = {
        achievementId = PVL.LEGEND_ACHIEVEMENT_ID,
        defaultRequired = 100,
        fallbackName = "Legend",
        defId = "legend",
        titleDefId = "legend",
        color = PVL.TITLE_COLORS.LEGEND,
        placement = "title_row",
        ruleDetail = "rated Solo Shuffle rounds",
    },
}

--- Returns the seasonal achievement config for one bracket, if any.
--- @param bracket string|nil
--- @return table|nil
function PVL.GetBracketSeasonAchievement(bracket)
    if not bracket then
        return nil
    end

    return PVL.SEASON_ACHIEVEMENT_BY_BRACKET[bracket]
end

--- Returns the content-tracking type id for achievements.
--- @return number
function PVL.GetAchievementTrackingType()
    if Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement then
        return Enum.ContentTrackingType.Achievement
    end

    return 2
end

--- Returns the manual stop type for content tracking toggles.
--- @return number
function PVL.GetContentTrackingStopManual()
    if Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual then
        return Enum.ContentTrackingStopType.Manual
    end

    return 2
end

--- Returns true when one achievement is pinned to the objectives tracker.
--- @param achievementId number
--- @return boolean
function PVL.IsAchievementTracked(achievementId)
    if not achievementId or not C_ContentTracking or not C_ContentTracking.IsTracking then
        return false
    end

    local ok, tracked = pcall(
        C_ContentTracking.IsTracking,
        PVL.GetAchievementTrackingType(),
        achievementId
    )
    return ok and tracked == true
end

--- Toggles one achievement on the in-game objectives tracker.
--- @param achievementId number
--- @return boolean success
--- @return string|nil message
function PVL.ToggleAchievementTracking(achievementId)
    if not achievementId then
        return false, "Achievement id is missing."
    end

    if not C_ContentTracking or not C_ContentTracking.ToggleTracking then
        return false, "Content tracking is unavailable in this client."
    end

    local ok, err = pcall(
        C_ContentTracking.ToggleTracking,
        PVL.GetAchievementTrackingType(),
        achievementId,
        PVL.GetContentTrackingStopManual()
    )
    if not ok then
        return false, "Could not toggle achievement tracking."
    end

    if err and Enum and Enum.ContentTrackingError then
        if err == Enum.ContentTrackingError.MaxTracked then
            return false, "Too many objectives are already tracked."
        end
        if err == Enum.ContentTrackingError.Untrackable then
            return false, "This achievement cannot be tracked right now."
        end
    end

    return true, nil
end

--- Returns a readable number from achievement criteria fields.
--- @param value any
--- @return number|nil
local function GetAccessibleAchievementNumber(value)
    if PVL.MatchCollector and PVL.MatchCollector.GetAccessibleNumber then
        return PVL.MatchCollector.GetAccessibleNumber(value)
    end

    return tonumber(value)
end

--- Returns win progress for one seasonal achievement.
--- @param achievementId number
--- @param defaultRequired number|nil
--- @return number|nil current
--- @return number|nil required
--- @return boolean completed
function PVL.GetAchievementProgress(achievementId, defaultRequired)
    defaultRequired = defaultRequired or 25

    if GetAchievementInfo then
        -- GetAchievementInfo returns: id, name, points, completed, ...
        -- When wrapped in pcall, "completed" is the fifth value (not points).
        local ok, _, _, _, completed = pcall(GetAchievementInfo, achievementId)
        if ok and completed == true then
            return defaultRequired, defaultRequired, true
        end
    end

    if GetAchievementNumCriteria and GetAchievementCriteriaInfo then
        local countOk, numCriteria = pcall(GetAchievementNumCriteria, achievementId)
        if countOk and numCriteria and numCriteria > 0 then
            local bestCurrent = nil
            local bestRequired = nil
            local bestCompleted = false

            for index = 1, numCriteria do
                local criteriaOk, _, _, criteriaCompleted, quantity, reqQuantity = pcall(
                    GetAchievementCriteriaInfo,
                    achievementId,
                    index
                )
                local requiredCount = GetAccessibleAchievementNumber(reqQuantity)
                if criteriaOk and requiredCount and requiredCount > 0 then
                    local currentCount = GetAccessibleAchievementNumber(quantity) or 0
                    local isBetterCriterion = not bestRequired or requiredCount >= bestRequired
                    if isBetterCriterion then
                        bestRequired = requiredCount
                        bestCurrent = currentCount
                        bestCompleted = criteriaCompleted == true or currentCount >= requiredCount
                    end
                end
            end

            if bestRequired then
                return bestCurrent or 0, bestRequired, bestCompleted
            end
        end
    end

    return nil, defaultRequired, false
end

--- Returns the display name for one achievement when available.
--- @param achievementId number
--- @param fallbackName string|nil
--- @return string
function PVL.GetAchievementDisplayName(achievementId, fallbackName)
    if GetAchievementInfo and achievementId then
        local ok, _, name = pcall(GetAchievementInfo, achievementId)
        if ok and name and name ~= "" then
            return name
        end
    end

    return fallbackName or "Season achievement"
end

--- Returns true when the Strategist achievement is pinned to the objectives tracker.
--- @return boolean
function PVL.IsStrategistTracked()
    return PVL.IsAchievementTracked(PVL.STRATEGIST_ACHIEVEMENT_ID)
end

--- Toggles the Strategist achievement on the in-game objectives tracker.
--- @return boolean success
--- @return string|nil message
function PVL.ToggleStrategistTracking()
    return PVL.ToggleAchievementTracking(PVL.STRATEGIST_ACHIEVEMENT_ID)
end

--- Returns Strategist win progress while at Elite rank for the current season.
--- @return number|nil current
--- @return number|nil required
--- @return boolean completed
function PVL.GetStrategistProgress()
    return PVL.GetAchievementProgress(PVL.STRATEGIST_ACHIEVEMENT_ID, 25)
end

--- Returns the display name for the Strategist achievement when available.
--- @return string
function PVL.GetStrategistAchievementName()
    return PVL.GetAchievementDisplayName(PVL.STRATEGIST_ACHIEVEMENT_ID, "Strategist")
end

--- Returns true when the Legend achievement is pinned to the objectives tracker.
--- @return boolean
function PVL.IsLegendTracked()
    return PVL.IsAchievementTracked(PVL.LEGEND_ACHIEVEMENT_ID)
end

--- Toggles the Legend achievement on the in-game objectives tracker.
--- @return boolean success
--- @return string|nil message
function PVL.ToggleLegendTracking()
    return PVL.ToggleAchievementTracking(PVL.LEGEND_ACHIEVEMENT_ID)
end

--- Returns Legend win progress while at Elite rank for the current season.
--- @return number|nil current
--- @return number|nil required
--- @return boolean completed
function PVL.GetLegendProgress()
    return PVL.GetAchievementProgress(PVL.LEGEND_ACHIEVEMENT_ID, 100)
end

--- Returns the display name for the Legend achievement when available.
--- @return string
function PVL.GetLegendAchievementName()
    return PVL.GetAchievementDisplayName(PVL.LEGEND_ACHIEVEMENT_ID, "Legend")
end

-- ---------------------------------------------------------------------------
-- Cutoff rating resolution
-- ---------------------------------------------------------------------------

--- Resolves the display name for one title definition.
--- @param def table Title definition.
--- @param faction string|nil Resolved player faction.
--- @return string
function PVL.GetTitleName(def, faction)
    if type(def.name) == "function" then
        return def.name(faction)
    end

    if def.locKey then
        return PVL.L(def.locKey)
    end

    return def.name
end

--- Finds the collector-supplied cutoff entry for one percentile.
--- @param snapshot table|nil Imported ladder snapshot.
--- @param percentile number Top-percent threshold (e.g. 0.5).
--- @return table|nil { pct, rank, rating }
local function FindSnapshotTitleCutoff(snapshot, percentile)
    local overall = snapshot and snapshot.overall
    local cutoffs = overall and overall.titleCutoffs
    if type(cutoffs) ~= "table" then
        return nil
    end

    for _, entry in ipairs(cutoffs) do
        if entry.pct and math.abs(entry.pct - percentile) < 0.001 then
            return entry
        end
    end

    return nil
end

--- Returns true when the snapshot ships per-specialization cutoffs.
--- Solo Shuffle and Battleground Blitz award Rank 1 titles per spec, so their
--- snapshots include ``overall.specCutoffs`` keyed by spec.
--- @param snapshot table|nil Imported ladder snapshot.
--- @return boolean
local function SnapshotHasSpecCutoffs(snapshot)
    local overall = snapshot and snapshot.overall
    return overall ~= nil and type(overall.specCutoffs) == "table"
end

--- Finds the per-spec cutoff entry for one percentile within one spec.
--- @param snapshot table|nil Imported ladder snapshot.
--- @param specKey string|nil Player spec key (e.g. "WARRIOR_FURY").
--- @param percentile number Top-percent threshold (e.g. 0.1).
--- @return table|nil cutoff { pct, rank, rating }, number|nil specPopulation
local function FindSpecTitleCutoff(snapshot, specKey, percentile)
    if not specKey then
        return nil, nil
    end

    local overall = snapshot and snapshot.overall
    local specCutoffs = overall and overall.specCutoffs
    if type(specCutoffs) ~= "table" then
        return nil, nil
    end

    local specEntry = specCutoffs[specKey]
    if type(specEntry) ~= "table" or type(specEntry.cutoffs) ~= "table" then
        return nil, nil
    end

    for _, entry in ipairs(specEntry.cutoffs) do
        if entry.pct and math.abs(entry.pct - percentile) < 0.001 then
            return entry, specEntry.population
        end
    end

    return nil, specEntry.population
end

--- Finds the per-spec cutoff entry for one fixed ladder rank within one spec.
--- @param snapshot table|nil Imported ladder snapshot.
--- @param specKey string|nil Player spec key (e.g. "WARRIOR_FURY").
--- @param targetRank number Ladder rank within the spec (e.g. 8).
--- @return table|nil cutoff { pct, rank, rating }, number|nil specPopulation
local function FindSpecRankCutoff(snapshot, specKey, targetRank)
    if not specKey or not targetRank or targetRank < 1 then
        return nil, nil
    end

    local overall = snapshot and snapshot.overall
    local specCutoffs = overall and overall.specCutoffs
    if type(specCutoffs) ~= "table" then
        return nil, nil
    end

    local specEntry = specCutoffs[specKey]
    if type(specEntry) ~= "table" or type(specEntry.cutoffs) ~= "table" then
        return nil, nil
    end

    for _, entry in ipairs(specEntry.cutoffs) do
        if entry.rank and entry.rank == targetRank then
            return entry, specEntry.population
        end
    end

    return nil, specEntry.population
end

--- Clamps a per-spec Rank 1 target rank to the spec's rated population.
--- @param targetRank number Desired ladder rank (e.g. 8).
--- @param specPopulation number|nil Rated players in that spec.
--- @return number
local function ClampSpecRankTarget(targetRank, specPopulation)
    if not specPopulation or specPopulation < 1 then
        return targetRank
    end

    return math.min(targetRank, specPopulation)
end

--- Interpolates a rating from sorted rank/rating sample points.
--- @param points table[] { rank, rating } rows sorted by rank ascending.
--- @param targetRank number
--- @return number|nil
local function InterpolateRatingAtRank(points, targetRank)
    if #points == 0 then
        return nil
    end

    table.sort(points, function(left, right)
        return left.rank < right.rank
    end)

    for _, point in ipairs(points) do
        if point.rank == targetRank then
            return point.rating
        end
    end

    if targetRank <= points[1].rank then
        return points[1].rating
    end

    local last = points[#points]
    if targetRank >= last.rank then
        return last.rating
    end

    for index = 1, #points - 1 do
        local low = points[index]
        local high = points[index + 1]
        if targetRank >= low.rank and targetRank <= high.rank then
            local span = high.rank - low.rank
            if span <= 0 then
                return low.rating
            end

            local progress = (targetRank - low.rank) / span
            return low.rating + (high.rating - low.rating) * progress
        end
    end

    return last.rating
end

--- Estimates the rating at one rank on a specialization ladder from listed players.
--- @param snapshot table|nil Imported ladder snapshot.
--- @param specKey string|nil Player spec key (e.g. "EVOKER_DEVASTATION").
--- @param targetRank number Ladder rank within the spec.
--- @return number|nil
function PVL.EstimateSpecRatingAtRank(snapshot, specKey, targetRank)
    if not snapshot or not specKey or not targetRank or targetRank < 1 then
        return nil
    end

    local points = {}
    if snapshot.players then
        for _, row in pairs(snapshot.players) do
            if type(row) == "table" and row.specKey == specKey and row.rank and row.rating then
                table.insert(points, { rank = row.rank, rating = row.rating })
            end
        end
    end

    if #points == 0 then
        return nil
    end

    return InterpolateRatingAtRank(points, targetRank)
end

--- Resolves the player's current specialization key and localized name.
--- The key matches the collector format (``CLASS_SPEC``, e.g. "WARRIOR_FURY")
--- so it can be matched against per-spec cutoff data.
--- @return string|nil specKey, string|nil specName
function PVL.GetPlayerSpecInfo()
    if not GetSpecialization or not GetSpecializationInfo or not UnitClass then
        return nil, nil
    end

    local specIndex = GetSpecialization()
    if not specIndex then
        return nil, nil
    end

    local _, classToken = UnitClass("player")
    if not classToken then
        return nil, nil
    end

    local _, specName = GetSpecializationInfo(specIndex)
    if not specName or specName == "" then
        return nil, nil
    end

    local specToken = PVL.NormalizeSpecKey(classToken, specName)
    if not specToken then
        return nil, specName
    end

    return PVL.MakeSpecKey(classToken, specToken), specName
end

--- Interpolates the rating at one ladder rank from known (rank, rating) points.
--- Used as a fallback when the collector did not ship an exact percentile cutoff
--- but the rated population and listed ranks are available.
--- @param snapshot table|nil Imported ladder snapshot.
--- @param bracket string Bracket id.
--- @param targetRank number Ladder rank to estimate a rating for.
--- @return number|nil
function PVL.EstimateRatingAtRank(snapshot, bracket, targetRank)
    if not snapshot or not targetRank or targetRank < 1 then
        return nil
    end

    local points = {}

    -- Listed player ranks are only globally meaningful for single-ladder
    -- brackets (arena/RBG); per-spec brackets store per-spec ranks.
    if snapshot.players and PVL.IsCombinedImportedBracket(bracket) then
        for _, row in pairs(snapshot.players) do
            if type(row) == "table" and row.rank and row.rating then
                table.insert(points, { rank = row.rank, rating = row.rating })
            end
        end
    end

    local overall = snapshot.overall
    if overall and overall.cutoffs then
        for _, cutoff in ipairs(overall.cutoffs) do
            if cutoff.rank and cutoff.rating then
                table.insert(points, { rank = cutoff.rank, rating = cutoff.rating })
            end
        end
    end

    if #points == 0 then
        return nil
    end

    return InterpolateRatingAtRank(points, targetRank)
end

--- Resolves the rating threshold for one title in one bracket.
---
--- Solo Shuffle and Battleground Blitz award percentile titles per
--- specialization, so for those brackets the player's own spec cutoff is used
--- when available. Combined brackets (Arena, RBG) use the single-ladder cutoff.
--- @param snapshot table|nil Imported ladder snapshot.
--- @param def table Title definition.
--- @param bracket string Bracket id.
--- @param specKey string|nil Player spec key, for per-spec brackets.
--- @return number|nil rating, string source, number|nil rank
function PVL.ResolveTitleCutoffRating(snapshot, def, bracket, specKey)
    if def.kind == "rating" then
        return def.rating, "fixed", nil
    end

    local perSpec = not PVL.IsCombinedImportedBracket(bracket)

    if def.kind == "spec_rank" then
        if not perSpec then
            return nil, "unavailable", nil
        end

        if SnapshotHasSpecCutoffs(snapshot) then
            local overall = snapshot.overall
            local specEntry = specKey and overall.specCutoffs and overall.specCutoffs[specKey] or nil
            local specPopulation = type(specEntry) == "table" and specEntry.population or nil
            local targetRank = ClampSpecRankTarget(def.rank, specPopulation)

            local specCutoff = FindSpecRankCutoff(snapshot, specKey, targetRank)
            if specCutoff and specCutoff.rating then
                return specCutoff.rating, "exact-spec", targetRank
            end

            -- Snapshots exported before the top-8 rule may only have legacy 0.1%
            -- cutoffs (often rank 3). Derive rank 8 from listed spec ladder players.
            local estimated = PVL.EstimateSpecRatingAtRank(snapshot, specKey, targetRank)
            if estimated then
                return math.floor(estimated + 0.5), "estimated-spec", targetRank
            end

            return nil, "needs-spec", nil
        end

        return nil, "unavailable", nil
    end

    -- Per-spec brackets: the title is awarded against the player's own spec
    -- ladder, so prefer the per-spec cutoff over the combined ladder number.
    if perSpec and SnapshotHasSpecCutoffs(snapshot) then
        local specCutoff = FindSpecTitleCutoff(snapshot, specKey, def.percentile)
        if specCutoff and specCutoff.rating then
            return specCutoff.rating, "exact-spec", specCutoff.rank
        end

        -- Data supports per-spec cutoffs but this spec is missing or unknown.
        return nil, "needs-spec", nil
    end

    -- Combined brackets (or legacy snapshots without per-spec data): prefer the
    -- collector's exact combined cutoff.
    local exact = FindSnapshotTitleCutoff(snapshot, def.percentile)
    if exact and exact.rating then
        return exact.rating, "exact", exact.rank
    end

    -- Fallback: derive the cutoff rank from the rated population, then estimate
    -- the rating at that rank from listed ladder data.
    local overall = snapshot and snapshot.overall
    local population = overall and overall.ratedPopulation
    if population and population > 0 then
        local rank = math.max(1, math.ceil((def.percentile / 100) * population))
        local rating = PVL.EstimateRatingAtRank(snapshot, bracket, rank)
        if rating then
            return math.floor(rating + 0.5), "estimated", rank
        end
    end

    return nil, "unavailable", nil
end

-- ---------------------------------------------------------------------------
-- Row building
-- ---------------------------------------------------------------------------

--- Returns the player's best-known current rating for one bracket.
--- @param bracket string Bracket id.
--- @return number|nil
function PVL.GetPlayerRatingForTitles(bracket)
    local current = PVL.RatedInfo and PVL.RatedInfo.GetCurrentRating(bracket) or nil
    if current and current > 0 then
        return current
    end

    local stored = PVL.GetCharacterRatingFields(bracket)
    if stored and stored > 0 then
        return stored
    end

    return nil
end

--- Builds title cutoff rows with per-title rating, gap, and achievement state.
--- @param bracket string|nil Bracket id; defaults to the active filter.
--- @return table rows, table context
function PVL.BuildTitleCutoffRows(bracket)
    bracket = bracket or PVL.GetActiveBracketFilter()

    local snapshot = PVL.GetImportedSnapshot(bracket)
    local faction = PVL.GetPlayerFaction()
    local playerRating = PVL.GetPlayerRatingForTitles(bracket)
    local definitions = PVL.TITLE_DEFINITIONS[bracket] or {}

    local perSpec = not PVL.IsCombinedImportedBracket(bracket)
    local specKey, specName = nil, nil
    if perSpec then
        specKey, specName = PVL.GetPlayerSpecInfo()
    end

    local rows = {}
    for _, def in ipairs(definitions) do
        local rating, source, rank = PVL.ResolveTitleCutoffRating(snapshot, def, bracket, specKey)
        local achieved = nil
        local gap = nil

        if rating and playerRating then
            achieved = playerRating >= rating
            gap = rating - playerRating
        end

        table.insert(rows, {
            def = def,
            name = PVL.GetTitleName(def, faction),
            cutoffRating = rating,
            source = source,
            rank = rank,
            achieved = achieved,
            gap = gap,
        })
    end

    local overall = snapshot and snapshot.overall
    local specPopulation = nil
    if perSpec and specKey and overall and type(overall.specCutoffs) == "table" then
        local specEntry = overall.specCutoffs[specKey]
        if type(specEntry) == "table" then
            specPopulation = specEntry.population
        end
    end

    local context = {
        bracket = bracket,
        snapshot = snapshot,
        faction = faction,
        playerRating = playerRating,
        perSpec = perSpec,
        specKey = specKey,
        specName = specName,
        specPopulation = specPopulation,
        ratedPopulation = overall and overall.ratedPopulation or nil,
        hasSpecCutoffs = overall and type(overall.specCutoffs) == "table" or false,
        hasExactCutoffs = overall
            and type(overall.titleCutoffs) == "table"
            and #overall.titleCutoffs > 0
            or false,
    }

    return rows, context
end

--- Builds prestige title cutoff rows for an arbitrary specialization.
---
--- Unlike ``BuildTitleCutoffRows`` this omits the player's own rating, gap, and
--- achievement state. It is used to look up the cutoffs for the spec selected in
--- the main window (e.g. to estimate a friend's titles without the addon). Only
--- percentile cutoffs and feat-of-strength titles are included, since the fixed
--- Combatant–Elite tiers are identical for every spec.
--- @param bracket string Bracket id.
--- @param specKey string|nil Spec key to resolve cutoffs for (per-spec brackets).
--- @return table rows (def, name, cutoffRating, source, rank)
function PVL.BuildSpecTitleCutoffRows(bracket, specKey)
    local snapshot = PVL.GetImportedSnapshot(bracket)
    local definitions = PVL.TITLE_DEFINITIONS[bracket] or {}

    local rows = {}
    for _, def in ipairs(definitions) do
        if def.kind == "percentile" or def.kind == "spec_rank" or def.feat then
            local rating, source, rank = PVL.ResolveTitleCutoffRating(snapshot, def, bracket, specKey)
            table.insert(rows, {
                def = def,
                -- Faction-neutral name: the cutoff rating is faction-independent,
                -- and the looked-up spec may belong to either faction.
                name = PVL.GetTitleName(def, nil),
                cutoffRating = rating,
                source = source,
                rank = rank,
            })
        end
    end

    return rows
end
