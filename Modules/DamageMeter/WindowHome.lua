-- VuloForeverUI / Modules / DamageMeter / WindowHome: a window's home view of bookmarked meter types
local _, ns = ...
local L  = ns.L
local DM = ns.DM

-- ---------------------------------------------------------------- home view --

local CARD_H, CARD_GAP, HOME_PAD = 26, 4, 8

function DM.AttachHome(W)
    local frame, header = W.frame, W.header
    local home, scroll, child
    local tiles = {}
    local addBtn, hint
    local homeScrollMax = 0

    local function tileMenu()
        local items = {}
        local marks = DM.Bookmarks()
        for _, t in ipairs(DM.TYPE_ORDER) do
            local have = false
            for _, m in ipairs(marks) do if m == t then have = true end end
            if not have then
                items[#items + 1] = { text = DM.TypeName(t), func = function()
                    marks[#marks + 1] = t
                    DM.ForEach(function(o) if o.homeOpen then o.RefreshHome() end end)
                end }
            end
        end
        if #items == 0 then items[1] = { text = L["All types are bookmarked"], disabled = true } end
        return items
    end

    local function makeTile()
        local b = CreateFrame("Button", nil, child)
        b:SetHeight(CARD_H)
        b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
        local bgT = b:CreateTexture(nil, "BACKGROUND")
        bgT:SetAllPoints(b); bgT:SetColorTexture(0.12, 0.12, 0.12, 0.8)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b); hl:SetColorTexture(1, 1, 1, 0.06)
        local stripe = b:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        stripe:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        stripe:SetWidth(2)
        b.stripe = stripe
        local ic = b:CreateTexture(nil, "ARTWORK")
        ic:SetSize(CARD_H - 8, CARD_H - 8)
        ic:SetPoint("LEFT", b, "LEFT", 6, 0)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ic:SetDesaturated(true)
        b.icon = ic
        local txt = b:CreateFontString(nil, "OVERLAY")
        DM.Font(txt, 11)
        txt:SetPoint("LEFT", ic, "RIGHT", 6, 0)
        txt:SetPoint("RIGHT", b, "RIGHT", -16, 0)
        txt:SetJustifyH("LEFT"); txt:SetWordWrap(false)
        b.text = txt
        local arrow = b:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(10, 10)
        arrow:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        arrow:SetTexture(DM.ICON .. "arrow_right")
        arrow:SetVertexColor(0.6, 0.6, 0.65)
        b:SetScript("OnClick", function(self, button)
            if button == "MiddleButton" then
                local marks = DM.Bookmarks()
                for i, m in ipairs(marks) do if m == self.dmType then table.remove(marks, i); break end end
                DM.ForEach(function(o) if o.homeOpen then o.RefreshHome() end end)
                return
            end
            W.SetType(self.dmType)
        end)
        return b
    end

    function W.RefreshHome()
        if not home then return end
        local marks = DM.Bookmarks()
        local ar, ag, ab = DM.Accent()
        local width = child:GetWidth() or frame:GetWidth()
        local colW = (width - HOME_PAD * 2 - CARD_GAP) / 2
        local y = -6
        for i, t in ipairs(marks) do
            local b = tiles[i]
            if not b then b = makeTile(); tiles[i] = b end
            b.dmType = t
            b.icon:SetTexture(DM.TYPE_ICONS[t])
            b.icon:SetVertexColor(ar, ag, ab)
            b.text:SetText(DM.TypeName(t))
            local active = (t == W.dmType)
            b.stripe:SetColorTexture(ar, ag, ab, active and 1 or 0)
            local col = (i - 1) % 2
            local rowI = math.floor((i - 1) / 2)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", child, "TOPLEFT", HOME_PAD + col * (colW + CARD_GAP), y - rowI * (CARD_H + CARD_GAP))
            b:SetWidth(math.max(40, colW))
            b:Show()
        end
        for i = #marks + 1, #tiles do tiles[i]:Hide() end
        local rows = math.ceil(#marks / 2)
        addBtn:ClearAllPoints()
        addBtn:SetPoint("TOPLEFT", child, "TOPLEFT", HOME_PAD, y - rows * (CARD_H + CARD_GAP))
        addBtn:SetWidth(math.max(40, width - HOME_PAD * 2))
        local contentH = -y + (rows + 1) * (CARD_H + CARD_GAP) + 16
        child:SetHeight(math.max(10, contentH))
        homeScrollMax = math.max(0, contentH - (scroll:GetHeight() or 0))
    end

    function W.ShowHome()
        if not home then
            home = CreateFrame("Frame", nil, frame)
            home:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            -- The row area's corner: on Classic it sits inside the box's rim.
            home:SetPoint("BOTTOMRIGHT", W.viewport, "BOTTOMRIGHT", 0, 0)
            home:SetFrameLevel(frame:GetFrameLevel() + 25)
            home:EnableMouse(true)
            local hb = home:CreateTexture(nil, "BACKGROUND")
            hb:SetAllPoints(home); hb:SetColorTexture(0.03, 0.03, 0.03, 0.95)
            scroll = CreateFrame("ScrollFrame", nil, home)
            scroll:SetAllPoints(home)
            scroll:SetClipsChildren(true)
            child = CreateFrame("Frame", nil, scroll)
            child:SetSize(1, 1)
            scroll:SetScrollChild(child)
            scroll:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w); W.RefreshHome() end)
            local function hw(_, delta)
                local cur = scroll:GetVerticalScroll() or 0
                scroll:SetVerticalScroll(math.max(0, math.min(homeScrollMax, cur - delta * 30)))
            end
            home:EnableMouseWheel(true); home:SetScript("OnMouseWheel", hw)
            scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", hw)
            home:SetScript("OnMouseDown", function(_, button) if button == "RightButton" then W.HideHome() end end)

            addBtn = CreateFrame("Button", nil, child)
            addBtn:SetHeight(CARD_H)
            local abg = addBtn:CreateTexture(nil, "BACKGROUND")
            abg:SetAllPoints(addBtn); abg:SetColorTexture(0.08, 0.08, 0.08, 0.8)
            local ahl = addBtn:CreateTexture(nil, "HIGHLIGHT")
            ahl:SetAllPoints(addBtn); ahl:SetColorTexture(1, 1, 1, 0.06)
            local at = addBtn:CreateFontString(nil, "OVERLAY")
            DM.Font(at, 11)
            at:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
            at:SetText("+ " .. L["ADD NEW"])
            at:SetTextColor(0.7, 0.7, 0.75)
            addBtn:SetScript("OnClick", function(self) ns:ShowPopupMenu(tileMenu(), self) end)
            hint = child:CreateFontString(nil, "OVERLAY")
            DM.Font(hint, 9)
            hint:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -3)
            hint:SetText(L["(middle click to remove)"])
            hint:SetTextColor(0.45, 0.45, 0.5)
        end
        W.homeOpen = true
        W.viewport:Hide()
        W.sticky.row:Hide(); W.stickySep:Hide()
        W.bg:Hide()
        if W.sourceOpen then W.CloseSource() end
        home:Show()
        child:SetWidth(scroll:GetWidth() or frame:GetWidth())
        W.RefreshHome()
    end

    function W.HideHome()
        if home then home:Hide() end
        W.homeOpen = false
        W.viewport:Show()
        W.bg:Show()
    end

    function W.ToggleHome()
        if W.homeOpen then W.HideHome() else W.ShowHome() end
    end
end
