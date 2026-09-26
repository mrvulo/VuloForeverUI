-- VuloForeverUI / Modules / QoL / Mail
--
-- An arrow beside the send tab's name field. It opens a menu with your own
-- characters, the characters you trust, and the names you last sent mail to;
-- a click puts the name into the field.
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
--   Your characters: every login writes the character into an account-wide
--     roster (name, realm, faction, class). The menu offers the ones on this
--     realm and of this faction -- mail goes nowhere else.
--   Trusted: a list you keep yourself -- from the menu ("Trust the name in the
--     field") or on the options page.
--   Recent: `SendMail(name, subject, body)` is hooked, not called: the hook sees
--     the name the moment the mail actually goes out, which is the only moment
--     that proves the name was one you meant.
--
-- All three are account-wide, because the alts you mail are the same from
-- every character.
--
-- WHAT IT LOOKS LIKE
--
-- The client's own: the round arrow of Blizzard's dropdown button, and the
-- client's menu (MenuUtil), so it sits in the mail window's style rather than
-- the suite's.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Mail = QoL.RegisterPart("mail", {})
QoL.Mail = Mail

local MAX_NAMES = 12

local button, hookedSend

local function db() return QoL.db().mail end

local function global()
    return ns.db and ns.db.global
end

local function list(key)
    local g = global()
    if not g then return {} end
    if type(g[key]) ~= "table" then g[key] = {} end
    return g[key]
end

local function recent()  return list("qolMailNames") end
local function trusted() return list("qolMailTrusted") end
local function roster()  return list("qolMailChars") end

local function realmName()
    local r = GetRealmName()
    return type(r) == "string" and r or "?"
end

local function same(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

local function indexOf(t, name)
    for i, v in ipairs(t) do if same(v, name) then return i end end
end

-- ----------------------------------------------------------- the lists --

function Mail.Forget()
    local g = global()
    if g then g.qolMailNames = {} end
end

function Mail.Count()
    return #recent()
end

function Mail.Trusted() return trusted() end

function Mail.AddTrusted(name)
    if type(name) ~= "string" then return false end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or indexOf(trusted(), name) then return false end
    local t = trusted()
    t[#t + 1] = name
    table.sort(t, function(a, b) return a:lower() < b:lower() end)
    return true
end

function Mail.RemoveTrusted(name)
    local t = trusted()
    local i = indexOf(t, name)
    if i then table.remove(t, i) end
end

-- This character, into the roster. The class token and the faction are what
-- the menu needs: the colour, and whether mail can reach it at all.
local function recordMe()
    local name = UnitName("player")
    if type(name) ~= "string" or name == "" then return end
    local _, classFile = UnitClass("player")
    local faction = UnitFactionGroup("player")
    local realm = realmName()
    local r = roster()
    r[realm] = type(r[realm]) == "table" and r[realm] or {}
    r[realm][name] = { class = classFile, faction = faction }
end

-- The other characters mail from this one can reach, sorted by name.
local function myCharacters()
    local out = {}
    local here = roster()[realmName()]
    if type(here) ~= "table" then return out end
    local me = UnitName("player")
    local faction = UnitFactionGroup("player")
    for name, info in pairs(here) do
        if name ~= me and type(info) == "table" and info.faction == faction then
            out[#out + 1] = { name = name, class = info.class }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Most recent first, and never twice. A name that moves back to the top is the
-- whole point: the alt you mail every evening should not sink under the one you
-- mailed once.
local function remember(name)
    if type(name) ~= "string" or name == "" then return end
    local t = recent()
    for i = #t, 1, -1 do
        if same(t[i], name) then table.remove(t, i) end
    end
    table.insert(t, 1, name)
    for i = #t, MAX_NAMES + 1, -1 do table.remove(t, i) end
end

local function onSendMail(name)
    if db().recipients then remember(name) end
end

-- ------------------------------------------------------------ the menu --

local function fill(name)
    local box = _G.SendMailNameEditBox
    if not box then return end
    box:SetText(name)
    box:SetFocus()
    box:HighlightText(0, 0)
    -- The cursor belongs at the end, not on top of the name: the next thing
    -- anyone does here is tab to the subject.
    box:SetCursorPosition(#name)
end

local function classColored(name, classFile)
    local c = ns.ClassColor and ns.ClassColor(classFile)
    if not c then return name end
    local function hex(v) return math.floor((v or 1) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x%s|r", hex(c.r), hex(c.g), hex(c.b), name)
end

local function typedName()
    local box = _G.SendMailNameEditBox
    local text = box and box:GetText()
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end

local function generate(_, root)
    local shown = {}
    local any = false
    local function section(title, names, color)
        if #names == 0 then return end
        if any then root:CreateDivider() end
        any = true
        root:CreateTitle(title)
        for _, e in ipairs(names) do
            local name = type(e) == "table" and e.name or e
            shown[name:lower()] = true
            local text = (color and type(e) == "table") and classColored(name, e.class) or name
            root:CreateButton(text, function() fill(name) end)
        end
    end

    section(L["My characters"], myCharacters(), true)
    section(L["Trusted characters"], trusted())
    local fresh = {}
    for _, name in ipairs(recent()) do
        if not shown[name:lower()] then fresh[#fresh + 1] = name end
    end
    section(L["Recent recipients"], fresh)

    if not any then root:CreateTitle(L["No names yet"]) end

    -- the list keeping itself, below a line
    local typed = typedName()
    local canTrust = typed and not indexOf(trusted(), typed)
    if canTrust or #trusted() > 0 or #recent() > 0 then
        root:CreateDivider()
    end
    if canTrust then
        root:CreateButton(L["Trust %s"]:format(typed), function() Mail.AddTrusted(typed) end)
    end
    if #trusted() > 0 then
        local sub = root:CreateButton(L["Remove from trusted"])
        for _, name in ipairs(trusted()) do
            sub:CreateButton(name, function() Mail.RemoveTrusted(name) end)
        end
    end
    if #recent() > 0 then
        root:CreateButton(L["Forget recent recipients"], Mail.Forget)
    end
end

local function build()
    if button then return button end
    local box = _G.SendMailNameEditBox
    if not box then return nil end

    -- Blizzard's own dropdown arrow (UIDropDownMenuTemplates.xml), so the
    -- button belongs to the mail window rather than to the suite.
    local b = CreateFrame("Button", nil, box:GetParent())
    b:SetSize(24, 24)
    b:SetPoint("LEFT", box, "RIGHT", 2, 0)
    b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    b:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Recipients"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Your characters, the ones you trust, and the names you last sent mail to."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        MenuUtil.CreateContextMenu(self, generate)
    end)

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

    -- Written on every apply, switch or not: the roster only knows the
    -- characters that logged in since, and the one you are on is one of them.
    recordMe()

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
