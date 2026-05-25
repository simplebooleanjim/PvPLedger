--- Global constants, bracket identifiers, and class/spec metadata for PvPLedger.
--- @class PvPLedger
PvPLedger = PvPLedger or {}

local PVL = PvPLedger

PVL.ADDON_NAME = "PvPLedger"
PVL.VERSION = "0.3.1"
PVL.DB_VERSION = 1

--- Bracket identifiers used throughout SavedVariables and imported ladder packs.
PVL.BRACKETS = {
    BLITZ = "blitz",
    SHUFFLE = "shuffle",
    ARENA_3V3 = "arena3v3",
    ARENA_2V2 = "arena2v2",
    RBG = "rbg",
}

--- Supported ladder regions for imported snapshots.
PVL.REGIONS = {
    US = "US",
    EU = "EU",
}

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

--- Maps WoW class tokens to localized display names.
PVL.CLASS_NAMES = {
    DEATHKNIGHT = "Death Knight",
    DEMONHUNTER = "Demon Hunter",
    DRUID = "Druid",
    EVOKER = "Evoker",
    HUNTER = "Hunter",
    MAGE = "Mage",
    MONK = "Monk",
    PALADIN = "Paladin",
    PRIEST = "Priest",
    ROGUE = "Rogue",
    SHAMAN = "Shaman",
    WARLOCK = "Warlock",
    WARRIOR = "Warrior",
}

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

--- UI copy that keeps ladder wording honest about data limits.
PVL.LABELS = {
    LISTED_AVG = "Average listed rating",
    LISTED_MEDIAN = "Median listed rating",
    TOP100_AVG = "Top-100 listed average",
    REPRESENTATION = "Top-ladder representation",
    OBSERVED = "Observed in your matches",
}

--- Maximum number of match rows retained locally before pruning oldest entries.
PVL.MAX_MATCHES = 500

--- Minimum delay between inspect requests to avoid API throttling.
PVL.INSPECT_DELAY_SECONDS = 1.25
