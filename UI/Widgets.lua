--- Reusable UI widgets for PvPLedger panels.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI

--- Texture path for the PvPLedger brand logo (shipped as a TGA under Media/).
UI.LOGO_TEXTURE = "Interface\\AddOns\\PvPLedger\\Media\\PvPLedgerLogo"

--- Stamps the PvPLedger logo onto a window's title bar for consistent branding.
--- @param frame Frame Window created from a Basic frame template.
--- @param size number|nil Logo edge size in pixels (default 22).
--- @return Texture logo The created brand texture.
function UI.AddWindowLogo(frame, size)
    size = size or 22

    local logo = frame:CreateTexture(nil, "OVERLAY")
    logo:SetTexture(UI.LOGO_TEXTURE)
    logo:SetSize(size, size)
    logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -2)

    frame.brandLogo = logo
    return logo
end

--- Adds a large, faint centered logo watermark behind a window's content.
--- Anchored to the frame's inset so it sits above the dark backdrop but below
--- the scrolling text, giving each page subtle branding without hurting reading.
--- @param frame Frame Window created from a Basic frame template.
--- @param size number|nil Watermark edge size in pixels (default 240).
--- @param alpha number|nil Opacity 0-1 (default 0.08).
--- @return Texture watermark The created watermark texture.
function UI.AddWindowWatermark(frame, size, alpha)
    local host = frame.Inset or frame
    local watermark = host:CreateTexture(nil, "ARTWORK")
    watermark:SetTexture(UI.LOGO_TEXTURE)
    watermark:SetSize(size or 240, size or 240)
    watermark:SetPoint("CENTER", host, "CENTER", 0, 0)
    watermark:SetAlpha(alpha or 0.08)

    frame.watermark = watermark
    return watermark
end

--- Shows or hides a scroll frame scrollbar when content does not overflow.
--- @param scrollFrame ScrollFrame|nil
--- @return boolean needsScroll
function UI.UpdateScrollBarVisibility(scrollFrame)
    if not scrollFrame then
        return false
    end

    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end

    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
    local needsScroll = false

    local scrollRange = scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange()
    if type(scrollRange) == "number" then
        needsScroll = scrollRange > 0.5
    elseif scrollChild then
        local frameHeight = scrollFrame:GetHeight() or 0
        local contentHeight = scrollChild:GetHeight() or 0
        needsScroll = contentHeight > (frameHeight + 1)
    end

    if scrollBar then
        if needsScroll then
            scrollBar:Show()
        else
            scrollBar:Hide()
            scrollFrame:SetVerticalScroll(0)
        end
    end

    return needsScroll
end

--- Registers one frame to close when the player presses Escape.
--- Closing any PvPLedger window also closes the rest via ``UI.CloseAll()``.
--- @param frame Frame
function UI.RegisterEscapeToClose(frame)
    if not frame then
        return
    end

    local frameName = frame.GetName and frame:GetName()
    if frameName then
        UISpecialFrames = UISpecialFrames or {}
        local alreadyRegistered = false
        for _, registeredName in ipairs(UISpecialFrames) do
            if registeredName == frameName then
                alreadyRegistered = true
                break
            end
        end

        if not alreadyRegistered then
            table.insert(UISpecialFrames, frameName)
        end
    end

    if frame.CloseButton and not frame.CloseButton._pvlCloseAllHooked then
        frame.CloseButton._pvlCloseAllHooked = true
        frame.CloseButton:SetScript("OnClick", function()
            if UI.CloseAll then
                UI.CloseAll()
            else
                frame:Hide()
            end
        end)
    end

    if not frame._pvlEscapeHooked then
        frame._pvlEscapeHooked = true
        frame:HookScript("OnHide", function()
            if UI._closingAll or not UI.CloseAll then
                return
            end

            if UI.AnyWindowShown and UI.AnyWindowShown() then
                UI.CloseAll()
            end
        end)
    end
end

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
--- @param fixedWidth number|nil
--- @return Frame scrollFrame, fun(text: string): nil setText
function UI.CreateScrollableTextArea(parent, name, topAnchor, leftAnchor, rightAnchor, bottomAnchor, fixedHeight, fixedWidth)
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -8)

    if fixedHeight then
        scrollFrame:SetHeight(fixedHeight)
    elseif bottomAnchor then
        scrollFrame:SetPoint("BOTTOMLEFT", leftAnchor, "BOTTOMLEFT", 0, 0)
        scrollFrame:SetPoint("BOTTOMRIGHT", rightAnchor, "BOTTOMRIGHT", 0, 0)
    end

    if fixedWidth then
        scrollFrame:SetWidth(fixedWidth)
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

    local TEXT_INSET_X = 8
    local SCROLLBAR_GUTTER = 24

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
        UI.UpdateScrollBarVisibility(scrollFrame)
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
