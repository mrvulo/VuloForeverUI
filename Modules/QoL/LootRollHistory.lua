-- VuloForeverUI / Modules / QoL / LootRollHistory
--
-- The loot history of the session (F-81): every roll that left the list,
-- newest first -- the item, the player's own choice, and the winner with
-- the roll, or that everyone passed.
--
-- A roll leaves the list a few seconds after the player is done with it,
-- often before the others are. Its result arrives later through the client's
-- loot history (LOOT_HISTORY_UPDATE_DROP), so an entry keeps the drop it was
-- matched to and reads the result from there. An entry that left before it
-- was matched takes the next drop with its item link -- only when exactly one
-- entry and no roll in the list has that link, the same rule the list uses.
--
-- The panel hangs on the far side of the header: above it when the list
-- grows down, below it when it grows up. It lives for the session only.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local LR = QoL.LootRoll

local KEEP = 15            -- entries kept
local ROW_GAP = 2

LR.past = {}
local past = LR.past

local panel
local rowsUI = {}

-- ------------------------------------------------------------- data --

function LR.Archive(r)
    if r.test or type(r.name) ~= "string" then return end
    local info = LR.Info(r)     -- nil when the match cannot be trusted
    table.insert(past, 1, {
        texture = r.texture, name = r.name, quality = r.quality,
        link = r.link, count = r.count, choice = r.choice,
        encounterID = info and r.encounterID or nil,
        lootListKey = info and r.lootListKey or nil,
        info = info,
    })
    for i = #past, KEEP + 1, -1 do past[i] = nil end
end

local function rowHasLink(link)
    for _, r in ipairs(LR.rolls) do
        if not r.test and r.link == link then return true end
    end
    return false
end

function LR.PastOwns(e, k)
    for _, p in ipairs(past) do
        if p.encounterID == e and p.lootListKey == k then return true end
    end
    return false
end

-- A drop the client reports changed: its entry gets the new result. True
-- when an entry took it.
function LR.PastDrop(e, info)
    if type(info) ~= "table" then return false end
    local k = ns.Num(info.lootListKey)
    if not k then return false end
    for _, p in ipairs(past) do
        if p.encounterID == e and p.lootListKey == k then
            p.info = info
            return true
        end
    end
    local link = info.itemHyperlink
    if type(link) ~= "string" or not ns.CanRead(link) or rowHasLink(link) then return false end
    local found, n = nil, 0
    for _, p in ipairs(past) do
        if p.link == link then
            n = n + 1
            if not p.encounterID then found = p end
        end
    end
    if n ~= 1 or not found then return false end
    found.encounterID, found.lootListKey, found.info = e, k, info
    if found.choice == nil then
        local s = ns.Num(info.playerRollState)
        local slot = s and LR.SlotOfState(s)
        if slot == 1 then found.choice = LR.NEED
        elseif slot == 2 then found.choice = LR.GREED
        elseif slot == 0 then found.choice = LR.PASS end
    end
    return true
end

-- The right-hand text of an entry: the player's choice, then the winner.
local CHOICE_ATLAS = {
    [0] = "lootroll-icon-pass", [1] = "lootroll-icon-need", [2] = "lootroll-icon-greed",
    [3] = "lootroll-icon-disenchant", [4] = "lootroll-icon-transmog",
}

local function resultText(p)
    local ui = LR._ui
    local info = p.info
    local out
    if type(info) == "table" and type(info.winner) == "table" then
        local w = info.winner
        local r, g, b = ui.classColor(w.playerClass)
        out = ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, LR.Name(w.playerName))
        local roll = ns.Num(w.roll)
        if roll then out = out .. " " .. roll end
    elseif type(info) == "table" and ns.CanRead(info.allPassed) and info.allPassed == true then
        out = "|cff999999" .. L["Everyone passed"] .. "|r"
    else
        out = "|cff999999" .. L["no result yet"] .. "|r"
    end
    local mine = p.choice and CHOICE_ATLAS[p.choice]
    if mine then out = ui.atlasMarkup(mine) .. "  " .. out end
    return out
end

-- -------------------------------------------------------------- rows --

local function rowEnter(self)
    local p = self.entry
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if type(p.link) == "string" then
        GameTooltip:SetHyperlink(p.link)
    else
        GameTooltip:SetText(p.name, LR.QualityColor(p.quality))
    end
    local info = p.info
    if type(info) == "table" and type(info.rollInfos) == "table" and #info.rollInfos > 0 then
        GameTooltip:AddLine(" ")
        for _, pl in ipairs(info.rollInfos) do LR._ui.addPlayer(pl) end
    end
    GameTooltip:Show()
end

local function rowClick(self)
    local p = self.entry
    if p and p.link and HandleModifiedItemClick then HandleModifiedItemClick(p.link) end
end

local function makeRow()
    local row = CreateFrame("Button", nil, panel)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.result = row:CreateFontString(nil, "OVERLAY")
    row.result:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.result:SetJustifyH("RIGHT")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.result, "LEFT", -8, 0)
    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", rowClick)
    return row
end

local function build()
    if panel then return end
    panel = CreateFrame("Frame", nil, LR._list)
    panel:EnableMouse(true)
    panel.ground = LR._ui.makeGround(panel)
    panel.empty = panel:CreateFontString(nil, "OVERLAY")
    panel.empty:SetPoint("CENTER")
end

-- Called from the list's layout, after the header is placed.
function LR.LayoutHistory(d, up)
    local list = LR._list
    if not list then return end
    local show = LR.historyOpen and not LR.hidden and not LR.collapsed and list.head:IsShown()
    if not show then
        if panel then panel:Hide() end
        return
    end
    build()
    local font, outline = QoL.Font(), QoL.Outline()
    local fs = math.max(9, d.fontSize - 1)
    local rh = fs + 8
    local pad = 6
    local n = #past
    local height = pad * 2 + math.max(1, n) * rh + math.max(0, n - 1) * ROW_GAP

    panel:SetSize(d.width, height)
    LR._ui.styleGround(panel.ground, panel, d.rounded)
    panel:ClearAllPoints()
    if up then
        panel:SetPoint("TOPLEFT", list.head, "BOTTOMLEFT", 0, -d.spacing)
    else
        panel:SetPoint("BOTTOMLEFT", list.head, "TOPLEFT", 0, d.spacing)
    end

    panel.empty:SetFont(font, fs, outline)
    panel.empty:SetTextColor(0.6, 0.6, 0.6)
    panel.empty:SetText(L["No rolls yet this session."])
    panel.empty:SetShown(n == 0)

    for i, p in ipairs(past) do
        local row = rowsUI[i]
        if not row then row = makeRow(); rowsUI[i] = row end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", pad, -pad - (i - 1) * (rh + ROW_GAP))
        row:SetSize(d.width - pad * 2, rh)
        row.icon:SetSize(rh - 2, rh - 2)
        row.icon:SetTexture(p.texture)
        row.name:SetFont(font, fs, outline)
        row.result:SetFont(font, fs, outline)
        local count = (p.count or 1) > 1 and (p.count .. "x ") or ""
        row.name:SetText(count .. p.name)
        row.name:SetTextColor(LR.QualityColor(p.quality))
        row.result:SetText(resultText(p))
        row.entry = p
        row:Show()
    end
    for i = n + 1, #rowsUI do
        rowsUI[i]:Hide()
        rowsUI[i].entry = nil
    end
    panel:Show()
end

function LR.ToggleHistory()
    if not LR._list or not LR.IsActive() then return end
    LR.historyOpen = not LR.historyOpen or nil
    if LR.historyOpen then LR.hidden, LR.collapsed = nil, nil end
    LR.Layout()
end
