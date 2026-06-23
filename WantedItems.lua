local _, Peddler = ...

local ARMOUR = "Armor"
Peddler.ARMOUR = ARMOUR

local PLATE = "Plate"
local MAIL = "Mail"
local LEATHER = "Leather"
local CLOTH = "Cloth"

local SHIELD = "Shields"
local LIBRAM = "Librams"
local IDOL = "Idols"
local TOTEM = "Totems"
local SIGIL = "Sigils"

local MISC = "Miscellaneous"


local WEAPON = "Weapon"
Peddler.WEAPON = WEAPON

local ONE_HANDED_AXE = "One-Handed Axes"
local TWO_HANDED_AXE = "Two-Handed Axes"

local ONE_HANDED_MACE = "One-Handed Maces"
local TWO_HANDED_MACE = "Two-Handed Maces"

local ONE_HANDED_SWORD = "One-Handed Swords"
local TWO_HANDED_SWORD = "Two-Handed Swords"

local DAGGER = "Daggers"
local FIST_WEAPON = "Fist Weapons"
local POLEARM = "Polearms"
local STAFF = "Staves"

local BOW = "Bows"
local CROSSBOW = "Crossbows"
local GUN = "Guns"
local THROWING = "Thrown"
local WAND = "Wands"

local FISHING_POLE = "Fishing Poles"

Peddler.WANTED_ITEMS = {
	['DEATHKNIGHT'] = {
		[ARMOUR] = {PLATE, SIGIL, MISC},
		[WEAPON] = {ONE_HANDED_AXE, TWO_HANDED_AXE, ONE_HANDED_MACE, TWO_HANDED_MACE, ONE_HANDED_SWORD, TWO_HANDED_SWORD, POLEARM, FISHING_POLE}
	},

	['DRUID'] = {
		[ARMOUR] = {LEATHER, IDOL, MISC},
		[WEAPON] = {ONE_HANDED_MACE, TWO_HANDED_MACE, DAGGER, FIST_WEAPON, POLEARM, STAFF, FISHING_POLE}
	},

	['HUNTER'] = {
		[ARMOUR] = {MAIL, MISC},
		[WEAPON] = {BOW, CROSSBOW, GUN, FISHING_POLE}
	},

	['MAGE'] = {
		[ARMOUR] = {CLOTH, MISC},
		[WEAPON] = {ONE_HANDED_SWORD, STAFF, WAND, FISHING_POLE}
	},

	['PALADIN'] = {
		[ARMOUR] = {PLATE, SHIELD, LIBRAM, MISC},
		[WEAPON] = {ONE_HANDED_AXE, TWO_HANDED_AXE, ONE_HANDED_MACE, TWO_HANDED_MACE, ONE_HANDED_SWORD, TWO_HANDED_SWORD, POLEARM, STAFF, FISHING_POLE}
	},

	['PRIEST'] = {
		[ARMOUR] = {CLOTH, MISC},
		[WEAPON] = {ONE_HANDED_MACE, DAGGER, STAFF, WAND, FISHING_POLE}
	},

	['ROGUE'] = {
		[ARMOUR] = {LEATHER, MISC},
		[WEAPON] = {ONE_HANDED_AXE, ONE_HANDED_MACE, ONE_HANDED_SWORD, DAGGER, FIST_WEAPON, THROWING, FISHING_POLE}
	},

	['SHAMAN'] = {
		[ARMOUR] = {MAIL, SHIELD, TOTEM, MISC},
		[WEAPON] = {ONE_HANDED_AXE, TWO_HANDED_AXE, ONE_HANDED_MACE, TWO_HANDED_MACE, DAGGER, FIST_WEAPON, POLEARM, STAFF, FISHING_POLE}
	},

	['WARLOCK'] = {
		[ARMOUR] = {CLOTH, MISC},
		[WEAPON] = {ONE_HANDED_SWORD, DAGGER, STAFF, WAND, FISHING_POLE}
	},

	['WARRIOR'] = {
		[ARMOUR] = {PLATE, SHIELD, MISC},
		[WEAPON] = {ONE_HANDED_AXE, TWO_HANDED_AXE, ONE_HANDED_MACE, TWO_HANDED_MACE, ONE_HANDED_SWORD, TWO_HANDED_SWORD, DAGGER, FIST_WEAPON, POLEARM, FISHING_POLE}
	}
}

Peddler.WANTED_ITEM_CLASS_ORDER = {
	"DEATHKNIGHT",
	"DRUID",
	"HUNTER",
	"MAGE",
	"PALADIN",
	"PRIEST",
	"ROGUE",
	"SHAMAN",
	"WARLOCK",
	"WARRIOR",
}

Peddler.WANTED_ITEM_CLASS_NAMES = {
	DEATHKNIGHT = "Death Knight",
	DRUID = "Druid",
	HUNTER = "Hunter",
	MAGE = "Mage",
	PALADIN = "Paladin",
	PRIEST = "Priest",
	ROGUE = "Rogue",
	SHAMAN = "Shaman",
	WARLOCK = "Warlock",
	WARRIOR = "Warrior",
}

Peddler.WANTED_ITEM_TYPES = {
	[ARMOUR] = {
		CLOTH,
		LEATHER,
		MAIL,
		PLATE,
		SHIELD,
		LIBRAM,
		IDOL,
		TOTEM,
		SIGIL,
		MISC,
	},
	[WEAPON] = {
		ONE_HANDED_AXE,
		TWO_HANDED_AXE,
		ONE_HANDED_MACE,
		TWO_HANDED_MACE,
		ONE_HANDED_SWORD,
		TWO_HANDED_SWORD,
		DAGGER,
		FIST_WEAPON,
		POLEARM,
		STAFF,
		BOW,
		CROSSBOW,
		GUN,
		THROWING,
		WAND,
		FISHING_POLE,
	},
}

local function CopyDefaultWantedSet(classTag, itemType)
	local source = Peddler.WANTED_ITEMS and Peddler.WANTED_ITEMS[classTag]
	source = source and source[itemType]
	local copy = {}
	for _, subType in ipairs(source or {}) do
		copy[subType] = true
	end
	return copy
end

function Peddler.EnsureWantedItemsConfig()
	if type(PeddlerWantedItems) ~= "table" then
		PeddlerWantedItems = {}
	end
	for _, classTag in ipairs(Peddler.WANTED_ITEM_CLASS_ORDER) do
		if type(PeddlerWantedItems[classTag]) ~= "table" then
			PeddlerWantedItems[classTag] = {}
		end
		for itemType in pairs(Peddler.WANTED_ITEM_TYPES) do
			if type(PeddlerWantedItems[classTag][itemType]) ~= "table" then
				PeddlerWantedItems[classTag][itemType] = CopyDefaultWantedSet(classTag, itemType)
			end
		end
	end
end

function Peddler.IsWantedItemForClass(classTag, itemType, subType)
	if not classTag or not itemType or not subType then return false end
	if Peddler.EnsureWantedItemsConfig then Peddler.EnsureWantedItemsConfig() end
	local classConfig = PeddlerWantedItems and PeddlerWantedItems[classTag]
	local typeConfig = classConfig and classConfig[itemType]
	if type(typeConfig) == "table" then
		return typeConfig[subType] and true or false
	end
	return false
end

function Peddler.SetWantedItemForClass(classTag, itemType, subType, wanted)
	if not classTag or not itemType or not subType then return end
	if Peddler.EnsureWantedItemsConfig then Peddler.EnsureWantedItemsConfig() end
	PeddlerWantedItems[classTag][itemType][subType] = wanted and true or nil
end

function Peddler.ResetWantedItemsForClass(classTag)
	if not classTag then return end
	if Peddler.EnsureWantedItemsConfig then Peddler.EnsureWantedItemsConfig() end
	PeddlerWantedItems[classTag] = {}
	for itemType in pairs(Peddler.WANTED_ITEM_TYPES) do
		PeddlerWantedItems[classTag][itemType] = CopyDefaultWantedSet(classTag, itemType)
	end
end

function Peddler.ResetAllWantedItems()
	PeddlerWantedItems = {}
	if Peddler.EnsureWantedItemsConfig then Peddler.EnsureWantedItemsConfig() end
end
