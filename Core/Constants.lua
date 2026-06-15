--- Global constants, bracket identifiers, and class/spec metadata for PvPLedger.
--- @class PvPLedger
PvPLedger = PvPLedger or {}

local PVL = PvPLedger

PVL.ADDON_NAME = "PvPLedger"
PVL.VERSION = "0.8.1"
PVL.DB_VERSION = 1

--- Bracket identifiers used throughout SavedVariables and imported ladder packs.
PVL.BRACKETS = {
    BLITZ = "blitz",
    SHUFFLE = "shuffle",
    ARENA_3V3 = "arena3v3",
    ARENA_2V2 = "arena2v2",
    RBG = "rbg",
}

--- Brackets that support imported Battle.net ladder snapshots.
PVL.IMPORTED_BRACKETS = {
    PVL.BRACKETS.BLITZ,
    PVL.BRACKETS.SHUFFLE,
    PVL.BRACKETS.RBG,
    PVL.BRACKETS.ARENA_2V2,
    PVL.BRACKETS.ARENA_3V3,
}

--- Brackets that collect local match observations by default.
PVL.DEFAULT_COLLECTED_BRACKETS = {
    PVL.BRACKETS.BLITZ,
    PVL.BRACKETS.SHUFFLE,
    PVL.BRACKETS.RBG,
    PVL.BRACKETS.ARENA_2V2,
    PVL.BRACKETS.ARENA_3V3,
}

--- Human-readable bracket labels for UI dropdowns (populated in PVL.InitLocale).
PVL.BRACKET_NAMES = PVL.BRACKET_NAMES or {}

--- Imported brackets that use one combined Battle.net ladder slug from Blizzard.
PVL.COMBINED_IMPORTED_BRACKETS = {
    PVL.BRACKETS.RBG,
    PVL.BRACKETS.ARENA_2V2,
    PVL.BRACKETS.ARENA_3V3,
}

--- Supported ladder regions for imported snapshots.
PVL.REGIONS = {
    US = "US",
    EU = "EU",
    KR = "KR",
    TW = "TW",
}

--- Settings value that follows the player's WoW client region.
PVL.LADDER_REGION_AUTO = "auto"

--- Default US companion addon name kept for legacy references.
PVL.DATA_ADDON_NAME = "PvPLedger-Data-US"

--- GitHub folder users can install as a sibling addon for public data updates.
PVL.DATA_ADDON_INSTALL_HINT = PVL.DATA_ADDON_INSTALL_HINT or ""

--- Bridge addon written by PvPLedger Sync (TSM/Raider.io-style desktop sync).
PVL.APP_HELPER_NAME = "PvPLedger-AppHelper"

--- Install hint for the AppHelper + future desktop sync app.
PVL.APP_HELPER_INSTALL_HINT = PVL.APP_HELPER_INSTALL_HINT or ""

--- Ordered class tokens for stable UI sorting.
PVL.CLASS_ORDER = {
    "DEATHKNIGHT",
    "DEMONHUNTER",
    "DRUID",
    "EVOKER",
    "HUNTER",
    "MAGE",
    "MONK",
    "PALADIN",
    "PRIEST",
    "ROGUE",
    "SHAMAN",
    "WARLOCK",
    "WARRIOR",
}

--- Maps WoW class tokens to localized display names via Blizzard APIs (see Core/ClassSpec.lua).
PVL.CLASS_NAMES = PVL.CLASS_NAMES or {}

--- Maps spec index (1-4) to a stable spec key per class.
--- Keys are uppercase CLASS_SPEC tokens used in aggregates and imports.
PVL.SPEC_KEYS_BY_CLASS = {
    DEATHKNIGHT = { "BLOOD", "FROST", "UNHOLY" },
    DEMONHUNTER = { "HAVOC", "VENGEANCE", "DEVOURER" },
    DRUID = { "BALANCE", "FERAL", "GUARDIAN", "RESTORATION" },
    EVOKER = { "DEVASTATION", "PRESERVATION", "AUGMENTATION" },
    HUNTER = { "BEASTMASTERY", "MARKSMANSHIP", "SURVIVAL" },
    MAGE = { "ARCANE", "FIRE", "FROST" },
    MONK = { "BREWMASTER", "MISTWEAVER", "WINDWALKER" },
    PALADIN = { "HOLY", "PROTECTION", "RETRIBUTION" },
    PRIEST = { "DISCIPLINE", "HOLY", "SHADOW" },
    ROGUE = { "ASSASSINATION", "OUTLAW", "SUBTLETY" },
    SHAMAN = { "ELEMENTAL", "ENHANCEMENT", "RESTORATION" },
    WARLOCK = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION" },
    WARRIOR = { "ARMS", "FURY", "PROTECTION" },
}

--- Brackets where the post-game score screen shows team average MMR, not personal MMR.
PVL.TEAM_OBSERVED_MMR_BRACKETS = {
    [PVL.BRACKETS.ARENA_2V2] = true,
    [PVL.BRACKETS.ARENA_3V3] = true,
    [PVL.BRACKETS.RBG] = true,
    [PVL.BRACKETS.BLITZ] = true,
}

--- UI copy that keeps ladder wording honest about data limits (populated in PVL.InitLocale).
PVL.LABELS = PVL.LABELS or {}

--- Maximum CR history points retained per character.
PVL.MAX_CR_HISTORY = 1000

--- Number of recent CR history rows shown in the main UI panel.
PVL.CR_HISTORY_UI_LIMIT = 15

--- Number of arena rounds played in one rated Solo Shuffle match.
PVL.SHUFFLE_ROUNDS_PER_MATCH = 6

--- Maximum listed players shown in the ladder browser panel.
PVL.LADDER_VIEW_LIMIT = 1000

--- Seconds to suppress redundant queue-screen CR snapshots after a match entry.
PVL.CR_SNAPSHOT_SUPPRESS_SECONDS = 120

PVL.COMBAT_ANALYSIS_STATS = PVL.COMBAT_ANALYSIS_STATS or {}

PVL.DEFAULT_COMBAT_ANALYSIS_STAT = "damage"

--- Number of recent matches shown in the match detail dropdown.
PVL.MATCH_HISTORY_UI_LIMIT = 25

--- Maps PvPLedger bracket ids to GetPersonalRatedInfo index values.
PVL.RATED_INFO_INDEX_BY_BRACKET = {
    [PVL.BRACKETS.ARENA_2V2] = 1,
    [PVL.BRACKETS.ARENA_3V3] = 2,
    [PVL.BRACKETS.RBG] = 4,
    [PVL.BRACKETS.SHUFFLE] = 7,
    [PVL.BRACKETS.BLITZ] = 9,
}

--- Players per team for brackets that use roster constraint team assignment.
PVL.TEAM_SIZE_BY_BRACKET = {
    [PVL.BRACKETS.BLITZ] = 8,
    [PVL.BRACKETS.RBG] = 10,
    [PVL.BRACKETS.ARENA_2V2] = 2,
    [PVL.BRACKETS.ARENA_3V3] = 3,
}

--- Maximum number of match rows retained locally before pruning oldest entries.
PVL.MAX_MATCHES = 500

--- Minimum delay between inspect requests to avoid API throttling.
PVL.INSPECT_DELAY_SECONDS = 1.25
