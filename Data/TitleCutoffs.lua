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
local function FactionTitle(allianceName, hordeName, faction)
    if faction == "Horde" then
        return hordeName
    end

    if faction == "Alliance" then
        return allianceName
    end

    return string.format("%s / %s", allianceName, hordeName)
end

-- ---------------------------------------------------------------------------
-- Title definitions
-- ---------------------------------------------------------------------------
--- Each definition describes one title tier:
---   id        Stable identifier.
---   name      Display name, or function(faction) -> string.
---   kind      "rating" for fixed thresholds, "percentile" for ladder cutoffs.
---   rating    Fixed rating threshold (kind == "rating").
---   percentile Top-percent of the ladder (kind == "percentile", e.g. 0.1).
---   wins      Season games-won requirement, when applicable.
---   color     TITLE_COLORS hex.
---   feat      True for end-of-season feats of strength (the prestige titles).
---   note      Optional clarifying text.

local C = PVL.TITLE_COLORS

--- Fixed rating tiers shared by every bracket (Combatant through Elite).
--- @return table[]
local function BuildFixedRatingTiers()
    return {
        { id = "combatant", name = "Combatant", kind = "rating", rating = 1000, color = C.COMBATANT },
        { id = "challenger", name = "Challenger", kind = "rating", rating = 1400, color = C.CHALLENGER },
        { id = "rival", name = "Rival", kind = "rating", rating = 1800, color = C.RIVAL },
        { id = "duelist", name = "Duelist", kind = "rating", rating = 2100, color = C.DUELIST },
        { id = "elite", name = "Elite", kind = "rating", rating = 2400, color = C.ELITE },
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
            name = "Gladiator",
            kind = "percentile",
            percentile = 0.5,
            wins = 50,
            color = C.GLADIATOR,
            feat = true,
            note = "Top 0.5% of 3v3, plus 50 wins at Elite (2400+).",
        },
        {
            id = "rank1",
            name = "Rank 1: Prized Gladiator",
            kind = "percentile",
            percentile = 0.1,
            wins = 150,
            color = C.RANK_ONE,
            feat = true,
            note = "Top 0.1% of 3v3 at season end, 150 wins required.",
        },
    }),

    [PVL.BRACKETS.ARENA_2V2] = WithFixedTiers({}),

    [PVL.BRACKETS.SHUFFLE] = WithFixedTiers({
        {
            id = "legend",
            name = "Legend",
            kind = "rating",
            rating = 2400,
            wins = 100,
            color = C.LEGEND,
            feat = true,
            note = "100 Solo Shuffle round wins at Elite (2400+).",
        },
        {
            id = "rank1",
            name = "Rank 1: Prized Legend",
            kind = "percentile",
            percentile = 0.1,
            wins = 50,
            color = C.RANK_ONE,
            feat = true,
            note = "Top 0.1% of Solo Shuffle at season end, 50 wins required.",
        },
    }),

    [PVL.BRACKETS.RBG] = WithFixedTiers({
        {
            id = "guardian",
            name = function(faction)
                return FactionTitle("Guardian of the Alliance", "Guardian of the Horde", faction)
            end,
            kind = "percentile",
            percentile = 3.0,
            color = C.RIVAL,
            note = "Top 3.0% of the Rated Battleground ladder.",
        },
        {
            id = "hero",
            name = function(faction)
                return FactionTitle("Hero of the Alliance", "Hero of the Horde", faction)
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
            id = "hero",
            name = function(faction)
                return FactionTitle("Hero of the Alliance", "Hero of the Horde", faction)
            end,
            kind = "percentile",
            percentile = 0.5,
            wins = 50,
            color = C.HERO,
            feat = true,
            note = "Top 0.5% of the Battleground Blitz ladder, 50 wins required.",
        },
        {
            id = "rank1",
            name = function(faction)
                return FactionTitle("Rank 1: Prized Marshal", "Rank 1: Prized Warlord", faction)
            end,
            kind = "percentile",
            percentile = 0.1,
            wins = 50,
            color = C.RANK_ONE,
            feat = true,
            note = "Top 0.1% of Battleground Blitz at season end, 50 wins required.",
        },
    }),
}

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

    table.sort(points, function(left, right)
        return left.rank < right.rank
    end)

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

--- Resolves the rating threshold for one title in one bracket.
--- @param snapshot table|nil Imported ladder snapshot.
--- @param def table Title definition.
--- @param bracket string Bracket id.
--- @return number|nil rating, string source, number|nil rank
function PVL.ResolveTitleCutoffRating(snapshot, def, bracket)
    if def.kind == "rating" then
        return def.rating, "fixed", nil
    end

    -- Percentile titles: prefer the collector's exact cutoff.
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

    local rows = {}
    for _, def in ipairs(definitions) do
        local rating, source, rank = PVL.ResolveTitleCutoffRating(snapshot, def, bracket)
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

    local context = {
        bracket = bracket,
        snapshot = snapshot,
        faction = faction,
        playerRating = playerRating,
        ratedPopulation = snapshot and snapshot.overall and snapshot.overall.ratedPopulation or nil,
        hasExactCutoffs = snapshot
            and snapshot.overall
            and type(snapshot.overall.titleCutoffs) == "table"
            and #snapshot.overall.titleCutoffs > 0
            or false,
    }

    return rows, context
end
