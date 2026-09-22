-- VuloForeverUI / Modules / QoL / Mail
--
-- A list of who you last sent mail to, next to the name field.
--
-- WHY IT WAITS
--
-- The mail window is a load-on-demand addon (Blizzard_MailFrame), so
-- `SendMailNameEditBox` does not exist at login -- it exists the first time a
-- mailbox is opened. Everything here is therefore built on MAIL_SHOW, once,
-- and the build is a no-op if the frame still is not there.
--
-- WHERE THE NAMES COME FROM
--
-- `SendMail(name, subject, body)` is hooked, not called: the hook sees the name
-- the moment the mail actually goes out, which is the only moment that proves
-- the name was one you meant. Typing into the field proves nothing -- half of
-- what is typed there is a name you abandoned.
--
-- The list is account-wide, because the alts you mail are the same from every
-- character, and capped: a list you have to read is not a shortcut.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Mail = QoL.RegisterPart("mail", {})
QoL.Mail = Mail

local MAX_NAMES = 12

local button, hookedSend

local function db() return QoL.db().mail end

local function names()
    local g = ns.db and ns.db.global
    if not g then return {} end
    if type(g.qolMailNames) ~= "table" then g.qolMailNames = {} end
    return g.qolMailNames
end

function Mail.Forget()
    local g = ns.db and ns.db.global
    if g then g.qolMailNames = {} end
end

function Mail.Count()
    return #names()
end

-- Most recent first, and never twice. A name that moves back to the top is the
-- whole point: the alt you mail every evening should not sink under the one you
-- mailed once.
local function remember(name)
    if type(name) ~= "string" or name == "" then return end
    local list = names()
    for i = #list, 1, -1 do
        if list[i]:lower() == name:lower() then table.remove(list, i) end
    end
    table.insert(list, 1, name)
    for i = #list, MAX_NAMES + 1, -1 do table.remove(list, i) end
end

local function onSendMail(name)
    if db().recipients then remember(name) end
end

-- ------------------------------------------------------------ menu --

local function menu()
    local list = names()
    if #list == 0 then
        return { { text = L["No recipients yet"], title = true } }
    end
    local entries = { { text = L["Recent recipients"], title = true } }
    for _, name in ipairs(list) do
        entries[#entries + 1] = { text = name, func = function()
            local box = _G.SendMailNameEditBox
            if not box then return end
            box:SetText(name)
            box:SetFocus()
            box:HighlightText(0, 0)
            -- The cursor belongs at the end, not on top of the name: the next
            -- thing anyone does here is tab to the subject.
            box:SetCursorPosition(#name)
        end }
    end
    entries[#entries + 1] = { separator = true }
    entries[#entries + 1] = { text = L["Forget these"], func = Mail.Forget }
    return entries
end

local function build()
    if button then return button end
    local box = _G.SendMailNameEditBox
    if not box then return nil end

    local b = CreateFrame("Button", nil, box:GetParent())
    b:SetSize(18, 18)
    b:SetPoint("LEFT", box, "RIGHT", 2, 0)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(b)
    tex:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\arrow_down.tga")
    tex:SetVertexColor(0.85, 0.85, 0.9, 0.9)
    b.icon = tex

    b:SetScript("OnEnter", function(self)
        tex:SetVertexColor(1, 1, 1, 1)
        ns.UI:ShowTooltip(self, { title = L["Recent recipients"], accent = true,
            lines = { L["The names you last sent mail to."] } })
    end)
    b:SetScript("OnLeave", function()
        tex:SetVertexColor(0.85, 0.85, 0.9, 0.9)
        ns.UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self) ns:ShowPopupMenu(menu(), self, self) end)

    button = b
    return b
end

local function onMailShow()
    if not db().recipients then
        if button then button:Hide() end
        return
    end
    if build() then button:Show() end
end

-- ----------------------------------------------------------- apply --

function Mail.Apply()
    local on = db().recipients and true or false

    -- The hook stays for the session once placed: hooksecurefunc cannot be
    -- undone, so the switch is read inside the hook rather than around it.
    if not hookedSend and _G.SendMail then
        hooksecurefunc("SendMail", onSendMail)
        hookedSend = true
    end

    QoL.SyncEvent(on, "MAIL_SHOW", onMailShow)
    if not on and button then button:Hide() end
    if on and _G.SendMailNameEditBox then onMailShow() end
end

function Mail.Disable()
    QoL.SyncEvent(false, "MAIL_SHOW", onMailShow)
    if button then button:Hide() end
end
