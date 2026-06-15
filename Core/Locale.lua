--- Localization loader and lookup helpers for PvPLedger.
--- @class PvPLedger
local PVL = PvPLedger

PVL.Locale = PVL.Locale or {}
local Locale = PVL.Locale

Locale._base = Locale._base or {}
Locale._overlay = Locale._overlay or {}

--- Registers the fallback English string table.
--- @param strings table<string, string>
function Locale.RegisterBase(strings)
    for key, value in pairs(strings) do
        Locale._base[key] = value
    end
end

--- Registers strings for the active client locale.
--- @param strings table<string, string>
function Locale.RegisterOverlay(strings)
    for key, value in pairs(strings) do
        Locale._overlay[key] = value
    end
end

--- Returns one localized string, falling back to English and then the key itself.
--- @param key string
--- @param ... any Optional `string.format` arguments.
--- @return string
function PVL.L(key, ...)
    local template = Locale._overlay[key] or Locale._base[key] or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, template, ...)
        if ok then
            return formatted
        end
    end

    return template
end

--- Builds runtime lookup tables that existing code still references.
function PVL.InitLocale()
    PVL.BRACKET_NAMES = {
        [PVL.BRACKETS.BLITZ] = PVL.L("BRACKET.BLITZ"),
        [PVL.BRACKETS.SHUFFLE] = PVL.L("BRACKET.SHUFFLE"),
        [PVL.BRACKETS.RBG] = PVL.L("BRACKET.RBG"),
        [PVL.BRACKETS.ARENA_2V2] = PVL.L("BRACKET.ARENA_2V2"),
        [PVL.BRACKETS.ARENA_3V3] = PVL.L("BRACKET.ARENA_3V3"),
    }

    PVL.LABELS = {
        LISTED_AVG = PVL.L("LABEL.LISTED_AVG"),
        LISTED_MEDIAN = PVL.L("LABEL.LISTED_MEDIAN"),
        TOP100_AVG = PVL.L("LABEL.TOP100_AVG"),
        REPRESENTATION = PVL.L("LABEL.REPRESENTATION"),
        OBSERVED = PVL.L("LABEL.OBSERVED"),
        TEAM_AVG_MMR = PVL.L("LABEL.TEAM_AVG_MMR"),
        PERSONAL_MMR = PVL.L("LABEL.PERSONAL_MMR"),
        CURRENT_CR = PVL.L("LABEL.CURRENT_CR"),
        CR_HISTORY = PVL.L("LABEL.CR_HISTORY"),
        CR_PEAK = PVL.L("LABEL.CR_PEAK"),
        CR_LOW = PVL.L("LABEL.CR_LOW"),
        CR_NET_7D = PVL.L("LABEL.CR_NET_7D"),
        CR_NET_SESSION = PVL.L("LABEL.CR_NET_SESSION"),
        SEASON_RECORD = PVL.L("LABEL.SEASON_RECORD"),
        SEASON_WIN_RATE = PVL.L("LABEL.SEASON_WIN_RATE"),
        ROUND_RECORD = PVL.L("LABEL.ROUND_RECORD"),
        ROUND_WIN_RATE = PVL.L("LABEL.ROUND_WIN_RATE"),
    }

    PVL.REGION_NAMES = {
        [PVL.LADDER_REGION_AUTO] = PVL.L("REGION.AUTO"),
        [PVL.REGIONS.US] = PVL.L("REGION.US"),
        [PVL.REGIONS.EU] = PVL.L("REGION.EU"),
        [PVL.REGIONS.KR] = PVL.L("REGION.KR"),
        [PVL.REGIONS.TW] = PVL.L("REGION.TW"),
    }

    PVL.DATA_ADDON_INSTALL_HINT = PVL.L("HINT.DATA_ADDON_INSTALL")
    PVL.APP_HELPER_INSTALL_HINT = PVL.L("HINT.APP_HELPER_INSTALL")

    PVL.COMBAT_ANALYSIS_STATS = {
        { value = "damage", label = PVL.L("COMBAT.DAMAGE"), field = "damage", useCombatAmount = true, rateLabel = PVL.L("COMBAT.DPS") },
        { value = "healing", label = PVL.L("COMBAT.HEALING"), field = "healing", useCombatAmount = true, rateLabel = PVL.L("COMBAT.HPS") },
        { value = "damageTaken", label = PVL.L("COMBAT.DAMAGE_TAKEN"), field = "damageTaken", useCombatAmount = true, rateLabel = PVL.L("COMBAT.DTPS") },
        { value = "interrupts", label = PVL.L("COMBAT.INTERRUPTS"), field = "interrupts", useCombatAmount = false, rateLabel = PVL.L("COMBAT.PER_MIN") },
        { value = "dispels", label = PVL.L("COMBAT.DISPELS"), field = "dispels", useCombatAmount = false, rateLabel = PVL.L("COMBAT.PER_MIN") },
        { value = "deaths", label = PVL.L("COMBAT.DEATHS"), field = "deaths", useCombatAmount = false, rateLabel = PVL.L("COMBAT.PER_MIN") },
    }
end
