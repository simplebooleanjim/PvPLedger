--- Details-style combat meter bars for match analysis.
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI
local Format = UI.Format

UI.CombatMeter = UI.CombatMeter or {}

local CombatMeter = UI.CombatMeter

CombatMeter.ROW_HEIGHT = 20
CombatMeter.ROW_GAP = 2
CombatMeter.HEADER_HEIGHT = 16
CombatMeter.ICON_SIZE = 16
CombatMeter.RANK_WIDTH = 18
CombatMeter.RATE_WIDTH = 44
CombatMeter.BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"

--- Applies a class icon texture to one row icon.
--- @param texture Texture
--- @param classToken string|nil
function CombatMeter.SetClassIcon(texture, classToken)
    if classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken] then
        texture:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        local coords = CLASS_ICON_TCOORDS[classToken]
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return
    end

    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    texture:SetTexCoord(0, 1, 0, 1)
end

--- Returns RGB values for one class token bar fill.
--- @param classToken string|nil
--- @return number r, number g, number b
function CombatMeter.GetClassBarColor(classToken)
    if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
        local color = RAID_CLASS_COLORS[classToken]
        return color.r, color.g, color.b
    end

    return 0.7, 0.7, 0.7
end

--- Creates one combat meter row frame.
--- @param parent Frame
--- @return Frame
function CombatMeter.CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(CombatMeter.ROW_HEIGHT)

    row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rankText:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.rankText:SetWidth(CombatMeter.RANK_WIDTH)
    row.rankText:SetJustifyH("RIGHT")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(CombatMeter.ICON_SIZE, CombatMeter.ICON_SIZE)
    row.icon:SetPoint("LEFT", row.rankText, "RIGHT", 2, 0)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.bar:SetPoint("RIGHT", row, "RIGHT", -CombatMeter.RATE_WIDTH, 0)
    row.bar:SetHeight(CombatMeter.ROW_HEIGHT - 2)
    row.bar:SetStatusBarTexture(CombatMeter.BAR_TEXTURE)
    row.bar:SetMinMaxValues(0, 1)

    row.barBackground = row.bar:CreateTexture(nil, "BACKGROUND")
    row.barBackground:SetAllPoints()
    row.barBackground:SetColorTexture(0.08, 0.08, 0.08, 0.95)

    row.nameText = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row.bar, "LEFT", 4, 0)
    row.nameText:SetPoint("RIGHT", row.bar, "RIGHT", -56, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.amountText = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.amountText:SetPoint("RIGHT", row.bar, "RIGHT", -4, 0)
    row.amountText:SetWidth(52)
    row.amountText:SetJustifyH("RIGHT")

    row.rateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rateText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.rateText:SetWidth(CombatMeter.RATE_WIDTH)
    row.rateText:SetJustifyH("RIGHT")

    return row
end

--- Creates the column header row for one stat view.
--- @param parent Frame
--- @return Frame
function CombatMeter.CreateHeaderRow(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(CombatMeter.HEADER_HEIGHT)

    header.rankText = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.rankText:SetPoint("LEFT", header, "LEFT", 0, 0)
    header.rankText:SetText("#")

    header.statLabel = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.statLabel:SetPoint("LEFT", header, "LEFT", CombatMeter.RANK_WIDTH + CombatMeter.ICON_SIZE + 6, 0)

    header.rateLabel = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.rateLabel:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    header.rateLabel:SetWidth(CombatMeter.RATE_WIDTH)
    header.rateLabel:SetJustifyH("RIGHT")

    -- Match the section-label gold used across the text panels.
    header.rankText:SetTextColor(0.847, 0.698, 0.353)
    header.statLabel:SetTextColor(0.847, 0.698, 0.353)
    header.rateLabel:SetTextColor(0.847, 0.698, 0.353)

    header.divider = header:CreateTexture(nil, "ARTWORK")
    header.divider:SetColorTexture(122 / 255, 104 / 255, 62 / 255, 0.85)
    header.divider:SetHeight(1)
    header.divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header.divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)

    return header
end

--- Returns true when one match roster includes scoreboard combat totals.
--- @param matchRecord table|nil
--- @return boolean
function CombatMeter.RosterHasScoreboardStats(matchRecord)
    return UI.MatchHasStoredCombatTotals(matchRecord)
end

--- Builds sorted combat meter entries for one match.
--- @param matchRecord table
--- @param statDef table
--- @param combatSummary table|nil
--- @return table[]
function CombatMeter.BuildEntries(matchRecord, statDef, combatSummary)
    combatSummary = combatSummary or UI.ResolveMatchCombatSummary(matchRecord)
    local entries = {}

    for _, participant in ipairs(matchRecord.roster or {}) do
        local combatRow = UI.GetCombatRowForParticipant(combatSummary, participant)
        table.insert(entries, {
            participant = participant,
            name = participant.name or "Unknown",
            classToken = participant.class,
            isLocalPlayer = participant.isLocalPlayer,
            amount = UI.GetCombatStatValue(combatRow, statDef, participant),
        })
    end

    table.sort(entries, function(a, b)
        if a.amount == b.amount then
            return a.name < b.name
        end
        return a.amount > b.amount
    end)

    return entries
end

--- Updates one combat meter row with ranked values.
--- @param row Frame
--- @param rank number
--- @param entry table
--- @param maxAmount number
--- @param duration number|nil
--- @param statDef table
function CombatMeter.UpdateRow(row, rank, entry, maxAmount, duration, statDef)
    local classToken = entry.classToken
    local r, g, b = CombatMeter.GetClassBarColor(classToken)

    CombatMeter.SetClassIcon(row.icon, classToken)
    row.rankText:SetText(tostring(rank) .. ".")

    local nameText = entry.name
    if entry.isLocalPlayer then
        nameText = Format.Colorize("FF66CCFF", nameText)
    end
    row.nameText:SetText(nameText)

    row.bar:SetMinMaxValues(0, maxAmount)
    row.bar:SetValue(entry.amount)
    row.bar:SetStatusBarColor(r, g, b, 0.92)

    if statDef.useCombatAmount then
        row.amountText:SetText(Format.CombatMeterAmount(entry.amount))
    else
        row.amountText:SetText(tostring(entry.amount))
    end

    if statDef.useCombatAmount and duration and duration > 0 then
        row.rateText:SetText(Format.CombatMeterRate(entry.amount / duration))
    elseif duration and duration > 0 then
        row.rateText:SetText(Format.CombatMeterCountRate((entry.amount * 60) / duration))
    else
        row.rateText:SetText("--")
    end

    row:Show()
end

--- Creates a scrollable Details-style combat meter panel.
--- @param parent Frame
--- @param name string
--- @param topAnchor Region
--- @param bottomLeft Region
--- @param bottomRight Region
--- @return Frame scrollFrame, fun(matchRecord: table|nil, statDef: table): nil update
function UI.CreateCombatMeterPanel(parent, name, topAnchor, bottomLeft, bottomRight)
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 16, -6)
    scrollFrame:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMRIGHT", 0, 0)

    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -2, -16)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -2, 16)
    end

    local content = CreateFrame("Frame", name .. "Content", scrollFrame)
    scrollFrame:SetScrollChild(content)

    local panel = {
        scrollFrame = scrollFrame,
        content = content,
        rows = {},
        headerRow = nil,
        emptyText = nil,
        noticeText = nil,
    }

    --- Hides all dynamic rows in the panel.
    function panel:ClearRows()
        for _, row in ipairs(self.rows) do
            row:Hide()
        end
        if self.headerRow then
            self.headerRow:Hide()
        end
        if self.emptyText then
            self.emptyText:Hide()
        end
        if self.noticeText then
            self.noticeText:Hide()
        end
    end

    --- Shows a muted footnote below the meter rows.
    --- @param message string
    --- @param yOffset number
    --- @param contentWidth number
    --- @return number nextYOffset
    function panel:ShowNotice(message, yOffset, contentWidth)
        if not self.noticeText then
            self.noticeText = self.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            self.noticeText:SetJustifyH("LEFT")
            self.noticeText:SetJustifyV("TOP")
        end

        self.noticeText:ClearAllPoints()
        self.noticeText:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4, -yOffset)
        self.noticeText:SetWidth(contentWidth - 8)
        self.noticeText:SetText(message)
        self.noticeText:Show()
        return yOffset + self.noticeText:GetStringHeight() + 6
    end

    --- Shows an empty-state message in the panel.
    --- @param message string
    function panel:ShowEmpty(message)
        self:ClearRows()
        if not self.emptyText then
            self.emptyText = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            self.emptyText:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4, -4)
            self.emptyText:SetJustifyH("LEFT")
            self.emptyText:SetJustifyV("TOP")
        end

        local width = math.max((self.scrollFrame:GetWidth() or 200) - 28, 120)
        self.emptyText:SetWidth(width)
        self.emptyText:SetTextColor(0.55, 0.55, 0.55)
        self.emptyText:SetText(message)
        self.emptyText:Show()
        self.content:SetSize(width, self.emptyText:GetStringHeight() + 8)
        self.scrollFrame:SetVerticalScroll(0)
        if self.scrollFrame.UpdateScrollChildRect then
            self.scrollFrame:UpdateScrollChildRect()
        end
        UI.UpdateScrollBarVisibility(self.scrollFrame)
    end

    --- Refreshes the meter rows for one match and stat selection.
    --- @param matchRecord table|nil
    --- @param statDef table|nil
    function panel:Update(matchRecord, statDef)
        self._lastMatchRecord = matchRecord
        self._lastStatDef = statDef

        if not matchRecord then
            self:ShowEmpty("No matches recorded for this bracket yet.")
            return
        end

        local roster = matchRecord.roster or {}
        if #roster == 0 then
            self:ShowEmpty("No players found for this match.")
            return
        end

        statDef = statDef or UI.GetCombatStatDefinition(UI.GetSelectedCombatStat())
        local combatSummary = UI.ResolveMatchCombatSummary(matchRecord)
        local hasTotals = UI.MatchHasStoredCombatTotals(matchRecord, combatSummary)
        local entries = CombatMeter.BuildEntries(matchRecord, statDef, combatSummary)
        if #entries == 0 then
            self:ShowEmpty("No players found for this match.")
            return
        end

        self:ClearRows()

        local topAmount = entries[1].amount or 0
        local maxAmount = topAmount
        if maxAmount <= 0 then
            maxAmount = 1
        end

        local duration = combatSummary and combatSummary.duration or nil
        local contentWidth = math.max((self.scrollFrame:GetWidth() or 200) - 28, 120)
        local yOffset = 0

        if not self.headerRow then
            self.headerRow = CombatMeter.CreateHeaderRow(self.content)
        end

        self.headerRow:ClearAllPoints()
        self.headerRow:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -yOffset)
        self.headerRow:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
        self.headerRow.statLabel:SetText(string.upper(statDef.label))
        self.headerRow.rateLabel:SetText(string.upper(statDef.rateLabel or (statDef.useCombatAmount and "DPS" or "/min")))
        self.headerRow:Show()
        yOffset = yOffset + CombatMeter.HEADER_HEIGHT + CombatMeter.ROW_GAP

        for index, entry in ipairs(entries) do
            local row = self.rows[index]
            if not row then
                row = CombatMeter.CreateRow(self.content)
                self.rows[index] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
            CombatMeter.UpdateRow(row, index, entry, maxAmount, duration, statDef)
            yOffset = yOffset + CombatMeter.ROW_HEIGHT + CombatMeter.ROW_GAP
        end

        if not hasTotals and statDef.useCombatAmount then
            yOffset = self:ShowNotice(
                "Combat totals unavailable for this saved match. New games after /reload will populate these bars.",
                yOffset,
                contentWidth
            )
        elseif topAmount <= 0 then
            local message = "No " .. string.lower(statDef.label) .. " recorded for this match."
            if not statDef.useCombatAmount then
                local summary = matchRecord.combatSummary
                if summary and summary.combatLogCaptured ~= true then
                    message = "Kicks and dispels are tracked from Blizzard combat data during live matches. "
                        .. "Enable combat recording in settings, /reload, then play a new match."
                end
            end
            yOffset = self:ShowNotice(message, yOffset, contentWidth)
        end

        local contentHeight = math.max(yOffset + 4, self.scrollFrame:GetHeight() or 1)
        self.content:SetSize(contentWidth, contentHeight)
        self.scrollFrame:SetVerticalScroll(0)
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
        UI.UpdateScrollBarVisibility(scrollFrame)
    end

    scrollFrame:SetScript("OnSizeChanged", function()
        if scrollFrame._pvlUpdating then
            return
        end

        scrollFrame._pvlUpdating = true
        if panel._lastMatchRecord and panel._lastStatDef then
            panel:Update(panel._lastMatchRecord, panel._lastStatDef)
        end
        scrollFrame._pvlUpdating = false
    end)

    scrollFrame._combatMeterPanel = panel
    scrollFrame.UpdateCombatMeter = function(matchRecord, statDef)
        panel:Update(matchRecord, statDef)
    end

    return scrollFrame, scrollFrame.UpdateCombatMeter
end
