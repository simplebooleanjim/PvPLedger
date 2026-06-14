--- Blizzard API helpers for localized class and specialization names.
--- @class PvPLedger
local PVL = PvPLedger

--- Maps class tokens to Blizzard class ids.
local CLASS_ID_BY_TOKEN = {
    WARRIOR = 1,
    PALADIN = 2,
    HUNTER = 3,
    ROGUE = 4,
    PRIEST = 5,
    DEATHKNIGHT = 6,
    SHAMAN = 7,
    MAGE = 8,
    WARLOCK = 9,
    MONK = 10,
    DRUID = 11,
    DEMONHUNTER = 12,
    EVOKER = 13,
}

--- Returns the localized class name for one class token.
--- @param classToken string|nil
--- @return string
function PVL.GetLocalizedClassName(classToken)
    if not classToken or classToken == "" then
        return ""
    end

    local classId = CLASS_ID_BY_TOKEN[classToken]
    if classId and GetClassInfo then
        local classInfo = { GetClassInfo(classId) }
        local className = classInfo[2]
        if className and className ~= "" then
            return className
        end
    end

    return PVL.L("CLASS." .. classToken)
end

--- Returns the localized specialization name for one CLASS_SPEC key.
--- @param specKey string|nil
--- @return string|nil
function PVL.GetLocalizedSpecName(specKey)
    if not specKey then
        return nil
    end

    local classToken, specToken = specKey:match("^(.-)_(.+)$")
    if not classToken or not specToken then
        return specKey
    end

    local classId = CLASS_ID_BY_TOKEN[classToken]
    local specKeys = PVL.SPEC_KEYS_BY_CLASS[classToken]
    if classId and specKeys and GetSpecializationInfoForClassID then
        for specIndex, key in ipairs(specKeys) do
            if key == specToken then
                local specId = GetSpecializationInfoForClassID(classId, specIndex)
                if specId and GetSpecializationInfoByID then
                    local _, specName = GetSpecializationInfoByID(specId)
                    if specName and specName ~= "" then
                        return specName
                    end
                end

                if GetSpecializationInfoForClassID then
                    local _, specName = GetSpecializationInfoForClassID(classId, specIndex)
                    if specName and specName ~= "" then
                        return specName
                    end
                end
                break
            end
        end
    end

    return PVL.TitleCaseToken(specToken)
end
