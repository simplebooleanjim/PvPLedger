--- Minimap button: left-click opens/closes PvPLedger, right-click opens options.
--- The button is draggable around the minimap edge and its angle persists in
--- SavedVariables (settings.minimap.position).
--- @class PvPLedger
local PVL = PvPLedger

PVL.UI = PVL.UI or {}
local UI = PVL.UI

UI.MinimapButton = UI.MinimapButton or {}
local MinimapButton = UI.MinimapButton

--- Distance, in pixels, from the minimap center to the button's anchor.
local EDGE_PADDING = 8

--- The single button instance, created lazily on first use.
--- @type Button|nil
local button

--- Returns the persistent minimap settings table, creating it if needed.
--- @return table minimap Table with `hide` and `position` fields.
local function GetMinimapSettings()
    local db = PVL.GetDB()
    db.settings = db.settings or {}
    db.settings.minimap = db.settings.minimap or { hide = false, position = 220 }
    return db.settings.minimap
end

--- Repositions the button along the minimap edge for the stored angle.
local function ApplyPosition()
    if not button then
        return
    end

    local angle = math.rad(GetMinimapSettings().position or 220)
    local radius = (Minimap:GetWidth() / 2) + EDGE_PADDING
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

--- Updates the stored angle from the current cursor position while dragging.
--- @param self Button The button being dragged.
local function DragToCursor(self)
    local centerX, centerY = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    GetMinimapSettings().position = math.deg(math.atan2(cursorY - centerY, cursorX - centerX))
    ApplyPosition()
end

--- Builds the button's tooltip when hovered.
--- @param self Button The hovered button.
local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff66ccffPvPLedger|r")
    GameTooltip:AddLine(PVL.L("UI.MINIMAP.CLICK_LEFT"), 1, 1, 1)
    GameTooltip:AddLine(PVL.L("UI.MINIMAP.CLICK_RIGHT"), 1, 1, 1)
    GameTooltip:AddLine(PVL.L("UI.MINIMAP.DRAG"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

--- Routes a click to the window toggle or the options panel.
--- @param self Button The clicked button.
--- @param mouseButton string The mouse button name.
local function OnClick(self, mouseButton)
    if mouseButton == "RightButton" then
        if PVL.OpenSettings then
            PVL.OpenSettings()
        end
    else
        if UI.Toggle then
            UI.Toggle()
        end
    end
end

--- Creates the minimap button once, wiring textures, dragging, and clicks.
--- @return Button button The created (or existing) button.
function MinimapButton.Create()
    if button then
        return button
    end

    button = CreateFrame("Button", "PvPLedgerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("CENTER", 0, 1)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(UI.LOGO_TEXTURE)
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", 0, 1)

    local mask = button:CreateMaskTexture()
    mask:SetTexture(
        "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT")

    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", DragToCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    ApplyPosition()
    return button
end

--- Creates the button if needed, then shows or hides it per saved settings.
function MinimapButton.Update()
    MinimapButton.Create()
    ApplyPosition()

    if GetMinimapSettings().hide then
        button:Hide()
    else
        button:Show()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    MinimapButton.Update()
end)
