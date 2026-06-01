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

--- Current-season rating required for the Elite title in all brackets.
PVL.ELITE_RATING = 2300

--- Fixed rating tiers shared by every bracket (Combatant through Elite).
--- @return table[]
local function BuildFixedRatingTiers()
    return {
        { id = "combatant", name = "Combatant", kind = "rating", rating = 1000, color = C.COMBATANT },
        { id = "challenger", name = "Challenger", kind = "rating", rating = 1400, color = C.CHALLENGER },
        { id = "rival", name = "Rival", kind = "rating", rating = 1800, color = C.RIVAL },
        { id = "duelist", name = "Duelist", kind = "rating", rating = 2100, color = C.DUELIST },
        { id = "elite", name = "Elite", kind = "rating", rating = PVL.ELITE_RATING, color = C.ELITE },
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
            kind = "rating",
            rating = PVL.ELITE_RATING,
            wins = 50,
            color = C.GLADIATOR,
            feat = true,
            note = "Win 50 games at Elite (2300+) on the 3v3 ladder; not a percentile.",
        },
        {
            id = "rank1",
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
            name = "Rank 1: Prized Legend",
            kind = "percentile",
            percentile = 0.1,
            wins = 50,
            color = C.RANK_ONE,
            feat = true,
            note = "Top 0.1% of your specialization's Solo Shuffle ladder (at least the top few per spec), 50 wins required.",
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
            id = "rank1",
            name = function(faction)
                return FactionTitle("Rank 1: Prized Marshal", "Rank 1: Prized Warlord", faction)
            end,
            kind = "percentile",
            percentile = 0.1,
            wins = 50,
            color = C.RANK_ONE,
            feat = true,
            note = "Top 0.1% of your specialization's Battleground Blitz ladder (at least the top few per spec), 50 wins required. Blitz has no Hero title.",
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
        if def.kind == "percentile" or def.feat then
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
