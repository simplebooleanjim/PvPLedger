--- Global constants, bracket identifiers, and class/spec metadata for PvPLedger.
--- @class PvPLedger
PvPLedger = PvPLedger or {}

local PVL = PvPLedger

PVL.ADDON_NAME = "PvPLedger"
PVL.VERSION = "0.7.0"
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

--- Human-readable bracket labels for UI dropdowns.
PVL.BRACKET_NAMES = {
    [PVL.BRACKETS.BLITZ] = "Battleground Blitz",
    [PVL.BRACKETS.SHUFFLE] = "Solo Shuffle",
    [PVL.BRACKETS.RBG] = "Rated Battlegrounds",
    [PVL.BRACKETS.ARENA_2V2] = "Arena 2v2",
    [PVL.BRACKETS.ARENA_3V3] = "Arena 3v3",
}

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
}

--- Optional companion addon that ships frequently refreshed US ladder snapshots.
PVL.DATA_ADDON_NAME = "PvPLedger-Data-US"

--- GitHub folder users can install as a sibling addon for public data updates.
PVL.DATA_ADDON_INSTALL_HINT = "Copy PvPLedger-Data-US into Interface/AddOns beside PvPLedger."

--- Bridge addon written by PvPLedger Sync (TSM/Raider.io-style desktop sync).
PVL.APP_HELPER_NAME = "PvPLedger-AppHelper"

--- Install hint for the AppHelper + future desktop sync app.
PVL.APP_HELPER_INSTALL_HINT = "Install PvPLedger-AppHelper and PvPLedger Sync for automatic ladder updates."

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
