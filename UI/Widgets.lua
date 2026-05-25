--- Reusable UI widgets for PvPLedger panels.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI

--- Creates a Blizzard-style dropdown bound to an option list.
--- @param parent Frame
--- @param name string
--- @param width number
--- @param getOptions fun(): table
--- @param getSelectedIndex fun(): number
--- @param onSelect fun(index: number, option: table)
--- @return Frame dropdown, fun(): nil refresh
function UI.CreateDropdown(parent, name, width, getOptions, getSelectedIndex, onSelect)
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")

    local function Refresh()
        local options = getOptions()
        local selectedIndex = getSelectedIndex()
        local selectedOption = options[selectedIndex]
        local label = selectedOption and selectedOption.label or "Select"

        UIDropDownMenu_SetSelectedID(dropdown, selectedIndex)
        UIDropDownMenu_SetText(dropdown, label)
    end

    UIDropDownMenu_Initialize(dropdown, function(_, level)
        local options = getOptions()
        local selectedIndex = getSelectedIndex()

        for index, option in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label
            info.checked = (index == selectedIndex)
            info.func = function()
                onSelect(index, option)
                Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    Refresh()
    return dropdown, Refresh
end

--- Creates a labeled section header font string.
--- @param parent Frame
--- @param text string
--- @param point table
--- @param font string|nil
--- @return FontString
function UI.CreateSectionHeader(parent, text, point, font)
    local header = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalLarge")
    header:SetPoint(unpack(point))
    if PVL.UI.Format and PVL.UI.Format.Header then
        header:SetText(PVL.UI.Format.Header(text))
    else
        header:SetText(text)
    end
    return header
end

--- Creates a multiline body font string.
--- @param parent Frame
--- @param width number
--- @param point table
--- @return FontString
function UI.CreateBodyText(parent, width, point)
    local body = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint(unpack(point))
    body:SetWidth(width)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    return body
end

--- Creates a scrollable text area for long spec lists.
--- @param parent Frame
--- @param name string
--- @param topAnchor Region
--- @param leftAnchor Region
--- @param rightAnchor Region
--- @param bottomAnchor Region|nil
--- @param fixedHeight number|nil
--- @return Frame scrollFrame, fun(text: string): nil setText
function UI.CreateScrollableTextArea(parent, name, topAnchor, leftAnchor, rightAnchor, bottomAnchor, fixedHeight)
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -8)

    if fixedHeight then
        scrollFrame:SetHeight(fixedHeight)
    elseif bottomAnchor then
        scrollFrame:SetPoint("BOTTOMLEFT", leftAnchor, "BOTTOMLEFT", 0, 0)
        scrollFrame:SetPoint("BOTTOMRIGHT", rightAnchor, "BOTTOMRIGHT", 0, 0)
    end

    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -4, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -4, 18)
    end

    local scrollChild = CreateFrame("Frame", name .. "Child", scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)

    local text = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, -4)

    local TEXT_INSET_X = 10
    local SCROLLBAR_GUTTER = 28

    --- Updates the scroll area content and resets scroll position.
    --- @param content string
    local function SetText(content)
        text:SetText(content or "")

        local frameWidth = scrollFrame:GetWidth() or 1
        local textWidth = math.max(frameWidth - TEXT_INSET_X - SCROLLBAR_GUTTER, 1)
        text:SetWidth(textWidth)

        local textHeight = text:GetStringHeight() or 1
        local frameHeight = scrollFrame:GetHeight() or 1
        scrollChild:SetSize(textWidth + TEXT_INSET_X, math.max(textHeight + 8, frameHeight))

        scrollFrame:SetVerticalScroll(0)
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
    end

    scrollFrame:SetScript("OnSizeChanged", function()
        local currentText = text:GetText()
        if currentText and currentText ~= "" and not scrollFrame._pvlUpdating then
            scrollFrame._pvlUpdating = true
            SetText(currentText)
            scrollFrame._pvlUpdating = false
        end
    end)

    return scrollFrame, SetText
end
