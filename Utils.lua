local addonName, Peddler = ...

if not Peddler then Peddler = {} end

-- strsplit polyfill
if not strsplit then
	function strsplit(delim, text)
		if text == nil then return end
		if not delim or delim == "" then return text end
		local list, pos = {}, 1
		while true do
			local s, e = string.find(text, delim, pos, true)
			if not s then
				table.insert(list, string.sub(text, pos))
				break
			end
			table.insert(list, string.sub(text, pos, s - 1))
			pos = e + 1
		end
		return unpack(list)
	end
end

function Peddler.Trim(s)
	if not s then return "" end
	return (s:gsub("^%s+",""):gsub("%s+$",""))
end

-- RunAfter utility
local waitFrame = CreateFrame("Frame")
function Peddler.RunAfter(delay, func)
	local elapsed = 0
	waitFrame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= delay then
			waitFrame:SetScript("OnUpdate", nil)
			func()
		end
	end)
end

-- Copper -> colored string
function Peddler.PriceToGold(price)
	local g = math.floor(price / 10000)
	local s = math.floor((price % 10000) / 100)
	local c = price % 100
	return g.."|cFFFFCC33g|r "..s.."|cFFC9C9C9s|r "..c.."|cFFCC8890c|r"
end
-- Backward compatibility alias
Peddler.priceToGold = Peddler.PriceToGold

-- Parse item link
function Peddler.ParseItemLink(itemLink)
	if not itemLink then return end
	local _, itemID, _, _, _, _, _, suffixID = strsplit(":", itemLink)
	itemID   = tonumber(itemID)
	suffixID = tonumber(suffixID)
	if not itemID then return end
	local unique = itemID
	if suffixID and suffixID ~= 0 then
		unique = itemID .. suffixID
	end
	return itemID, unique
end

-- Soulbound detection
local soulTip
function Peddler.IsSoulbound(link)
	if not link then return false end
	if not soulTip then
		local tip = CreateFrame("GameTooltip")
		local left = {}
		for i=1,4 do
			local l, r = tip:CreateFontString(), tip:CreateFontString()
			l:SetFontObject(GameFontNormal)
			r:SetFontObject(GameFontNormal)
			tip:AddFontStrings(l, r)
			left[i] = l
		end
		tip.leftside = left
		soulTip = tip
	end
	soulTip:SetOwner(UIParent, "ANCHOR_NONE")
	soulTip:ClearLines()
	soulTip:SetHyperlink(link)
	for i=2,4 do
		local txt = soulTip.leftside[i]:GetText()
		if txt == ITEM_SOULBOUND or txt == ITEM_BIND_ON_PICKUP then
			soulTip:Hide()
			return true
		end
	end
	soulTip:Hide()
	return false
end

-- Classification helpers
local _, CLASS_TAG = UnitClass("player")

function Peddler.IsUnwantedClassItem(itemType, subType, equipSlot)
	if not AutoSellUnwantedItems then return false end
	if equipSlot == "INVTYPE_CLOAK" then return false end
	if not (itemType == Peddler.WEAPON or itemType == Peddler.ARMOUR) then return false end

	local classMap = Peddler.WANTED_ITEMS and Peddler.WANTED_ITEMS[CLASS_TAG]
	if classMap then
		local allowed = classMap[itemType]
		if allowed then
			for _, accepted in ipairs(allowed) do
				if subType == accepted then
					return false
				end
			end
		end
	end
	return true
end

function Peddler.ClassifyAutoReason(quality, manualFlag, classUnwanted)
	if manualFlag then
		return "manual"
	elseif classUnwanted then
		return "class"
	elseif quality == 0 then
		return "grey"
	elseif quality == 1 then
		return "common"
	elseif quality == 2 then
		return "uncommon"
	elseif quality == 3 then
		return "rare"
	elseif quality == 4 then
		return "epic"
	else
		return "auto"
	end
end

-- Auto-sell decision (excluding manual ItemsToSell)
function Peddler.ShouldAutoSell(itemID, uniqueID)
	local _, link, quality, _, _, itemType, subType, _, equipSlot, _, price = GetItemInfo(itemID)
	if not price or price <= 0 then
		return false, false
	end

	local unmarked = UnmarkedItems and UnmarkedItems[uniqueID]
	local unwantedGrey   = (quality == 0 and AutoSellGreyItems   and not unmarked)
	local unwantedWhite  = (quality == 1 and AutoSellWhiteItems  and not unmarked)
	local unwantedGreen  = (quality == 2 and AutoSellGreenItems  and not unmarked)
	local unwantedBlue   = (quality == 3 and AutoSellBlueItems   and not unmarked)
	local unwantedPurple = (quality == 4 and AutoSellPurpleItems and not unmarked)
	local classUnwanted  = (Peddler.IsUnwantedClassItem(itemType, subType, equipSlot) and not unmarked)

	local auto = (unwantedGrey or unwantedWhite or unwantedGreen or unwantedBlue or unwantedPurple or classUnwanted)
	if auto and SoulboundOnly and not unwantedGrey then
		auto = Peddler.IsSoulbound(link)
	end
	return auto, classUnwanted
end