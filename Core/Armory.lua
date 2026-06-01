--- Builds Battle.net armory URLs and shows a copy dialog for the player browser.
--- @class PvPLedger
local PVL = PvPLedger

PVL.ARMORY_BASE_URL = "https://worldofwarcraft.blizzard.com"

--- Parses a Name-Realm display string into separate components.
--- Character names cannot contain hyphens, so the first hyphen separates realm.
--- @param displayName string|nil
--- @return string|nil name, string|nil realm
function PVL.ParseDisplayName(displayName)
    if not displayName or displayName == "" then
        return nil, nil
    end

    local name, realm = displayName:match("^([^-]+)-(.+)$")
    if name and realm and name ~= "" and realm ~= "" then
        return name, realm
    end

    return displayName, nil
end

--- Converts a name or realm label into a Battle.net armory path segment.
--- @param value string|nil
--- @return string|nil
function PVL.NormalizeArmorySlug(value)
    if not value or value == "" then
        return nil
    end

    return string.lower(value):gsub("%s+", "-")
end

--- Returns the Blizzard web locale segment for one ladder region.
--- @param region string|nil
--- @return string
function PVL.GetArmoryLocale(region)
    region = string.upper(region or "US")
    if region == "EU" then
        return "en-gb"
    end
    if region == "KR" then
        return "ko-kr"
    end
    if region == "TW" then
        return "zh-tw"
    end

    return "en-us"
end

--- Builds a Battle.net character armory URL from ladder player metadata.
--- @param region string|nil Snapshot region such as US or EU.
--- @param displayName string|nil Preserved Name-Realm label from ladder data.
--- @param playerKey string|nil Normalized lookup key used when displayName is missing.
--- @return string|nil
function PVL.BuildArmoryUrl(region, displayName, playerKey)
    local name, realm = PVL.ParseDisplayName(displayName)
    if (not name or name == "") and playerKey then
        name, realm = PVL.ParsePlayerKey(playerKey)
    end

    if not name or name == "" then
        return nil
    end

    local regionSlug = PVL.NormalizeArmorySlug(region) or "us"
    local locale = PVL.GetArmoryLocale(region)
    local nameSlug = PVL.NormalizeArmorySlug(name)
    if not nameSlug then
        return nil
    end

    if realm and realm ~= "" then
        local realmSlug = PVL.NormalizeArmorySlug(realm)
        if realmSlug then
            return string.format(
                "%s/%s/character/%s/%s/%s",
                PVL.ARMORY_BASE_URL,
                locale,
                regionSlug,
                realmSlug,
                nameSlug
            )
        end
    end

    return nil
end

--- Shows an armory link dialog so the player can copy it into a browser.
--- WoW restricts addons from opening character URLs or copying to the clipboard directly.
--- @param url string|nil
--- @param displayName string|nil Optional label for chat output.
--- @return boolean shown True when the copy dialog was displayed.
function PVL.ShowArmoryLink(url, displayName)
    if not url or url == "" then
        return false
    end

    local label = displayName or "this character"

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cff66ccffPvPLedger|r Armory link for %s:", label),
            1, 1, 1
        )
        DEFAULT_CHAT_FRAME:AddMessage(url, 0.7, 0.7, 0.7)
    end

    if StaticPopup_Show and (not InCombatLockdown or not InCombatLockdown()) then
        local ok = pcall(StaticPopup_Show, "PVPLedger_ARMORY_LINK", label, nil, { url = url })
        if ok then
            return true
        end
    end

    return false
end

--- @deprecated Use PVL.ShowArmoryLink instead.
--- @param url string|nil
--- @return boolean
function PVL.OpenArmoryUrl(url)
    return PVL.ShowArmoryLink(url)
end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["PVPLedger_ARMORY_LINK"] = {
    text = "WoW cannot open armory pages directly.\n\nCopy the link for %s and paste it into your browser (Ctrl+C):",
    button1 = OKAY,
    hasEditBox = 1,
    editBoxWidth = 340,
    maxLetters = 512,
    OnShow = function(dialog, data)
        local editBox = dialog.editBox or dialog.EditBox
        local url = data and data.url
        if not editBox or not url then
            return
        end

        editBox:SetText(url)
        editBox:SetFocus()
        editBox:HighlightText()

        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                local ok, text = pcall(function()
                    return editBox:GetText()
                end)
                if ok and text == url then
                    pcall(function()
                        editBox:HighlightText()
                        editBox:SetFocus()
                    end)
                end
            end)
        end
    end,
    EditBoxOnEnterPressed = function(dialog)
        dialog:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(editBox)
        editBox:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}
