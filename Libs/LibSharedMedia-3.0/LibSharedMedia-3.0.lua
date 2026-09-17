--[[
Name: LibSharedMedia-3.0
Maintainers: Elkano (elkano@gmx.de), funkydude
Website: http://www.wowace.com/projects/libsharedmedia-3-0/
Description: Shared handling of media data (fonts, sounds, textures, ...) between addons.
Dependencies: LibStub, CallbackHandler-1.0
License: LGPL v2.1
]]

local MAJOR, MINOR = "LibSharedMedia-3.0", 9000200 -- 9.0.2 v2 / increase manually on changes
local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then return end

local _G = getfenv(0)

local pairs		= _G.pairs
local type		= _G.type

local band			= _G.bit.band
local table_sort	= _G.table.sort

local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS

local LOCALE = GetLocale()

-- font language bits: Register() drops fonts whose langmask does not include the client locale
lib.LOCALE_BIT_koKR		= 1
lib.LOCALE_BIT_ruRU		= 2
lib.LOCALE_BIT_zhCN		= 4
lib.LOCALE_BIT_zhTW		= 8
lib.LOCALE_BIT_western	= 128

local locale_is_western
local LOCALE_MASK
if LOCALE == "koKR" then
	LOCALE_MASK = lib.LOCALE_BIT_koKR
elseif LOCALE == "ruRU" then
	LOCALE_MASK = lib.LOCALE_BIT_ruRU
elseif LOCALE == "zhCN" then
	LOCALE_MASK = lib.LOCALE_BIT_zhCN
elseif LOCALE == "zhTW" then
	LOCALE_MASK = lib.LOCALE_BIT_zhTW
else
	LOCALE_MASK = lib.LOCALE_BIT_western
	locale_is_western = true
end

lib.callbacks		= lib.callbacks			or LibStub:GetLibrary("CallbackHandler-1.0"):New(lib)

lib.DefaultMedia	= lib.DefaultMedia		or {}
lib.MediaList		= lib.MediaList			or {}
lib.MediaTable		= lib.MediaTable		or {}
lib.OverrideMedia	= lib.OverrideMedia		or {}

local defaultMedia = lib.DefaultMedia
local mediaList = lib.MediaList
local mediaTable = lib.MediaTable
local overrideMedia = lib.OverrideMedia


-- create mediatype constants
lib.MediaType = lib.MediaType or {}
lib.MediaType.BACKGROUND	= "background"			-- background textures
lib.MediaType.BORDER		= "border"				-- border textures
lib.MediaType.FONT			= "font"				-- fonts
lib.MediaType.STATUSBAR		= "statusbar"			-- statusbar textures
lib.MediaType.SOUND			= "sound"				-- sound files


-- populate lib with default Blizzard data
-- BACKGROUND
if not lib.MediaTable.background then lib.MediaTable.background = {} end
lib.MediaTable.background["None"]									= [[]]
lib.MediaTable.background["Blizzard Collections Background"]		= [[Interface\Collections\CollectionsBackgroundTile]]
lib.MediaTable.background["Blizzard Dialog Background"]				= [[Interface\DialogFrame\UI-DialogBox-Background]]
lib.MediaTable.background["Blizzard Dialog Background Dark"]		= [[Interface\DialogFrame\UI-DialogBox-Background-Dark]]
lib.MediaTable.background["Blizzard Dialog Background Gold"]		= [[Interface\DialogFrame\UI-DialogBox-Gold-Background]]
lib.MediaTable.background["Blizzard Garrison Background"]			= [[Interface\Garrison\GarrisonUIBackground]]
lib.MediaTable.background["Blizzard Garrison Background 2"]			= [[Interface\Garrison\GarrisonUIBackground2]]
lib.MediaTable.background["Blizzard Garrison Background 3"]			= [[Interface\Garrison\GarrisonShipMissionUnavailableBackground]]
lib.MediaTable.background["Blizzard Low Health"]					= [[Interface\FullScreenTextures\LowHealth]]
lib.MediaTable.background["Blizzard Marble"]						= [[Interface\FrameGeneral\UI-Background-Marble]]
lib.MediaTable.background["Blizzard Out of Control"]				= [[Interface\FullScreenTextures\OutOfControl]]
lib.MediaTable.background["Blizzard Parchment"]						= [[Interface\AchievementFrame\UI-Achievement-Parchment-Horizontal]]
lib.MediaTable.background["Blizzard Parchment 2"]					= [[Interface\AchievementFrame\UI-GuildAchievement-Parchment-Horizontal]]
lib.MediaTable.background["Blizzard Rock"]							= [[Interface\FrameGeneral\UI-Background-Rock]]
lib.MediaTable.background["Blizzard Tabard Background"]				= [[Interface\TabardFrame\TabardFrameBackground]]
lib.MediaTable.background["Blizzard Tooltip"]						= [[Interface\Tooltips\UI-Tooltip-Background]]
lib.MediaTable.background["Solid"]									= [[Interface\Buttons\WHITE8X8]]
lib.DefaultMedia.background = "None"

-- BORDER
if not lib.MediaTable.border then lib.MediaTable.border = {} end
lib.MediaTable.border["None"]									= [[]]
lib.MediaTable.border["Blizzard Achievement Wood"]				= [[Interface\AchievementFrame\UI-Achievement-WoodBorder]]
lib.MediaTable.border["Blizzard Chat Bubble"]					= [[Interface\Tooltips\ChatBubble-Backdrop]]
lib.MediaTable.border["Blizzard Dialog"]						= [[Interface\DialogFrame\UI-DialogBox-Border]]
lib.MediaTable.border["Blizzard Dialog Gold"]					= [[Interface\DialogFrame\UI-DialogBox-Gold-Border]]
lib.MediaTable.border["Blizzard Party"]							= [[Interface\CHARACTERFRAME\UI-Party-Border]]
lib.MediaTable.border["Blizzard Tooltip"]						= [[Interface\Tooltips\UI-Tooltip-Border]]
lib.DefaultMedia.border = "None"

-- FONT
if not lib.MediaTable.font then lib.MediaTable.font = {} end
local SML_MT_font = lib.MediaTable.font
--	Fonts available in all locales
SML_MT_font["Arial Narrow"]		= [[Fonts\ARIALN.TTF]]
SML_MT_font["Friz Quadrata TT"]	= [[Fonts\FRIZQT__.TTF]]
SML_MT_font["Morpheus"]			= [[Fonts\MORPHEUS.TTF]]
SML_MT_font["Nimrod MT"]		= [[Fonts\Nim_____.ttf]]
SML_MT_font["Skurri"]			= [[Fonts\SKURRI.TTF]]
lib.DefaultMedia["font"] = "Friz Quadrata TT"

local locale_fonts = {
	koKR = "2002",
	zhCN = "AR ZhongkaiGBK Medium",
	zhTW = "AR Kaiti Medium B5",
	ruRU = "Friz Quadrata TT",
}
lib.DefaultMedia["font"] = locale_fonts[LOCALE] or "Friz Quadrata TT"

-- STATUSBAR
if not lib.MediaTable.statusbar then lib.MediaTable.statusbar = {} end
lib.MediaTable.statusbar["Blizzard"]						= [[Interface\TargetingFrame\UI-StatusBar]]
lib.MediaTable.statusbar["Blizzard Character Skills Bar"]	= [[Interface\PaperDollInfoFrame\UI-Character-Skills-Bar]]
lib.MediaTable.statusbar["Blizzard Raid Bar"]				= [[Interface\RaidFrame\Raid-Bar-Hp-Fill]]
lib.DefaultMedia.statusbar = "Blizzard"

-- SOUND
if not lib.MediaTable.sound then lib.MediaTable.sound = {} end
lib.MediaTable.sound["None"]								= [[Interface\Quiet.ogg]]	-- Relies on the fact that PlaySound[File] doesn't error out on non-existing files
lib.DefaultMedia.sound = "None"

local function rebuildMediaList(mediatype)
	local mtable = mediaTable[mediatype]
	if not mtable then return end
	if not mediaList[mediatype] then mediaList[mediatype] = {} end
	local mlist = mediaList[mediatype]
	-- list can only get larger, so simply overwrite it
	local i = 0
	for k in pairs(mtable) do
		i = i + 1
		mlist[i] = k
	end
	table_sort(mlist)
end

function lib:Register(mediatype, key, data, langmask)
	if type(mediatype) ~= "string" then
		error(MAJOR..":Register(mediatype, key, data, langmask) - mediatype must be string, got "..type(mediatype))
	end
	if type(key) ~= "string" then
		error(MAJOR..":Register(mediatype, key, data, langmask) - key must be string, got "..type(key))
	end
	mediatype = mediatype:lower()
	if mediatype == lib.MediaType.FONT and ((langmask and band(langmask, LOCALE_MASK) == 0) or (not langmask and not locale_is_western)) then return false end
	if mediatype == lib.MediaType.SOUND and type(data) == "string" then
		local path = data:lower()
		-- Only ogg and mp3 are valid sounds.
		if not path:find(".ogg", nil, true) and not path:find(".mp3", nil, true) then
			return false
		end
	end
	local mtable = mediaTable[mediatype]
	if not mtable then mtable = {}; mediaTable[mediatype] = mtable end

	if mtable[key] then return false end
	mtable[key] = data

	rebuildMediaList(mediatype)

	self.callbacks:Fire("LibSharedMedia_Registered", mediatype, key)
	return true
end

function lib:Fetch(mediatype, key, noDefault)
	local mtt = mediaTable[mediatype]
	local overridekey = overrideMedia[mediatype]
	local result = (mtt and ((overridekey and mtt[overridekey] or mtt[key]) or (not noDefault and defaultMedia[mediatype] and mtt[defaultMedia[mediatype]]))) or nil
	return result ~= "" and result or nil
end

function lib:IsValid(mediatype, key)
	return mediaTable[mediatype] and (not key or mediaTable[mediatype][key]) and true or false
end

function lib:HashTable(mediatype)
	return mediaTable[mediatype]
end

function lib:List(mediatype)
	if not mediaTable[mediatype] then
		return nil
	end
	if not mediaList[mediatype] then
		rebuildMediaList(mediatype)
	end
	return mediaList[mediatype]
end

function lib:GetGlobal(mediatype)
	return overrideMedia[mediatype]
end

function lib:SetGlobal(mediatype, key)
	if not mediaTable[mediatype] then
		return false
	end
	overrideMedia[mediatype] = (key and mediaTable[mediatype][key]) and key or nil
	self.callbacks:Fire("LibSharedMedia_SetGlobal", mediatype, overrideMedia[mediatype])
	return true
end

function lib:GetDefault(mediatype)
	return defaultMedia[mediatype]
end

function lib:SetDefault(mediatype, key)
	if mediaTable[mediatype] and mediaTable[mediatype][key] and not defaultMedia[mediatype] then
		defaultMedia[mediatype] = key
		return true
	else
		return false
	end
end
