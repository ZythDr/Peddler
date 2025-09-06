local _, Peddler = ... -- _G.Peddler = Peddler --(uncomment for debugging)

-- Core (defaults, state, events, selling, manual toggles)

-- =========================================================
-- Default Configuration
-- =========================================================
local DEFAULTS = {
	SellLimit                = true,
	Silent                   = false,
	SilenceSaleSummary       = false,
	ModifierKey              = "ALT",
	IconPlacement            = "BOTTOMLEFT",
	DeleteUnsellablesEnabled = false,

	SoulboundOnly            = true,
	AutoSellGreyItems        = true,
	AutoSellWhiteItems       = false,
	AutoSellGreenItems       = false,
	AutoSellBlueItems        = false,
	AutoSellPurpleItems      = false,
	AutoSellUnwantedItems    = true,
}

local BUYBACK_COUNT = 12

-- =========================================================
-- Local references
-- =========================================================
local GetContainerNumSlots = GetContainerNumSlots
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerItemLink = GetContainerItemLink
local GetItemInfo          = GetItemInfo
local UseContainerItem     = UseContainerItem
local GetBuybackItemInfo   = GetBuybackItemInfo
local GetBuybackItemLink   = GetBuybackItemLink
local GetNumBuybackItems   = GetNumBuybackItems
local IsAltKeyDown         = IsAltKeyDown
local IsControlKeyDown     = IsControlKeyDown
local IsShiftKeyDown       = IsShiftKeyDown

local print = print
local floor = math.floor

-- Event frame
local coreFrame = CreateFrame("Frame")
local salesDelay = CreateFrame("Frame")

-- State
local markCounter = 1
local countLimit  = 1
local usingDefaultBags = false

Peddler._autoSellingActive  = false
Peddler._autoScheduledCount = 0
Peddler._autoLoggedCount    = 0
Peddler._buybackBaseline    = nil

--------------------------------------------------
-- Helper wrappers (use Utils.lua functions)
--------------------------------------------------
local function RunAfter(d,f) Peddler.RunAfter(d,f) end
local function priceToGold(c) return Peddler.PriceToGold(c) end -- backward compatibility

--------------------------------------------------
-- Chat coin formatting (icon-based)
--------------------------------------------------
local GOLD_ICON   = "Interface\\MoneyFrame\\UI-GoldIcon"
local SILVER_ICON = "Interface\\MoneyFrame\\UI-SilverIcon"
local COPPER_ICON = "Interface\\MoneyFrame\\UI-CopperIcon"
local COIN_SIZE   = 12
local function CoinTex(path)
	return "|T"..path..":"..COIN_SIZE..":"..COIN_SIZE..":0:0:64:64:5:59:5:59|t"
end
local GOLD_TEX   = CoinTex(GOLD_ICON)
local SILVER_TEX = CoinTex(SILVER_ICON)
local COPPER_TEX = CoinTex(COPPER_ICON)

local function CoinsString(amount)
	amount = amount or 0
	local g = floor(amount / 10000)
	local s = floor((amount % 10000) / 100)
	local c = amount % 100
	local parts = {}
	if g > 0 then parts[#parts+1] = "|cffffffff"..g.."|r "..GOLD_TEX end
	if s > 0 or g > 0 then parts[#parts+1] = "|cffffffff"..s.."|r "..SILVER_TEX end
	parts[#parts+1] = "|cffffffff"..c.."|r "..COPPER_TEX
	return table.concat(parts, " ")
end

--------------------------------------------------
-- Defaults / Initialization
--------------------------------------------------
local function ApplyDefaultsIfNil()
	if SellLimit == nil then SellLimit = DEFAULTS.SellLimit end
	if Silent == nil then Silent = DEFAULTS.Silent end
	if SilenceSaleSummary == nil then SilenceSaleSummary = DEFAULTS.SilenceSaleSummary end
	if not ModifierKey then ModifierKey = DEFAULTS.ModifierKey end
	if not IconPlacement then IconPlacement = DEFAULTS.IconPlacement end
	if DeleteUnsellablesEnabled == nil then DeleteUnsellablesEnabled = DEFAULTS.DeleteUnsellablesEnabled end

	if SoulboundOnly == nil then SoulboundOnly = DEFAULTS.SoulboundOnly end
	if AutoSellGreyItems == nil then AutoSellGreyItems = DEFAULTS.AutoSellGreyItems end
	if AutoSellWhiteItems == nil then AutoSellWhiteItems = DEFAULTS.AutoSellWhiteItems end
	if AutoSellGreenItems == nil then AutoSellGreenItems = DEFAULTS.AutoSellGreenItems end
	if AutoSellBlueItems == nil then AutoSellBlueItems = DEFAULTS.AutoSellBlueItems end
	if AutoSellPurpleItems == nil then AutoSellPurpleItems = DEFAULTS.AutoSellPurpleItems end
	if AutoSellUnwantedItems == nil then AutoSellUnwantedItems = DEFAULTS.AutoSellUnwantedItems end
end

local function SetupDefaults()
	if not ItemsToSell then ItemsToSell = {} end
	if not UnmarkedItems then UnmarkedItems = {} end
	if not ItemsToDelete then ItemsToDelete = {} end
	ApplyDefaultsIfNil()
end

--------------------------------------------------
-- Classification & Sell Decision
--------------------------------------------------
function Peddler.itemIsToBeSold(itemID, unique)
	local auto, _ = Peddler.ShouldAutoSell(itemID, unique)
	if not auto then
		return ItemsToSell[unique]
	end
	return ItemsToSell[unique] or auto
end

local function GetSaleReasonCode(itemID, unique)
	local _, link, quality, _, _, itemType, subType, _, equipSlot = GetItemInfo(itemID)
	local manual = ItemsToSell and ItemsToSell[unique]
	local _, classUnwanted = Peddler.ShouldAutoSell(itemID, unique)
	return Peddler.ClassifyAutoReason(quality, manual, classUnwanted)
end

--------------------------------------------------
-- Buyback baseline & manual sell detection
--------------------------------------------------
local function BuildBuybackBaseline()
	local baseline = {}
	for i=1,(GetNumBuybackItems() or 0) do
		local link = GetBuybackItemLink(i)
		local name, _, price, qty = GetBuybackItemInfo(i)
		local key
		if link then
			key = link.."@"..(price or 0).."@"..(qty or 1)
		elseif name then
			key = name.."@NOLINK@"..(price or 0).."@"..(qty or 1)
		end
		if key then baseline[key] = (baseline[key] or 0) + 1 end
	end
	Peddler._buybackBaseline = baseline
end

local function DetectManualSell()
	if Peddler._autoSellingActive then return end
	if not Peddler._buybackBaseline then
		BuildBuybackBaseline()
		return
	end
	local current = {}
	for i=1,(GetNumBuybackItems() or 0) do
		local link = GetBuybackItemLink(i)
		local name, _, price, qty = GetBuybackItemInfo(i)
		local key
		if link then key = link.."@"..(price or 0).."@"..(qty or 1)
		else key = (name or "?").."@NOLINK@"..(price or 0).."@"..(qty or 1)
		end
		current[key] = (current[key] or 0) + 1
	end
	for key, count in pairs(current) do
		local base = Peddler._buybackBaseline[key] or 0
		if count > base then
			local added = count - base
			local linkPart, pricePart, qtyPart = key:match("^(.-)@(%d+)@(%d+)$")
			local price = tonumber(pricePart) or 0
			local qty = tonumber(qtyPart) or 1
			local itemID
			if linkPart and linkPart:find("|Hitem:") then
				itemID = tonumber(linkPart:match("|Hitem:(%d+):"))
			end
			for _=1,added do
				if Peddler.LogSale then
					Peddler.LogSale(itemID or 0, linkPart, qty, price*qty, "manualsell")
				end
			end
		end
	end
	Peddler._buybackBaseline = current
end

--------------------------------------------------
-- Auto Selling
--------------------------------------------------
local function FinalizeAutoSelling()
	Peddler._autoSellingActive = false
	BuildBuybackBaseline()
end

local function OnAutoSaleLoggedIncrement()
	if not Peddler._autoSellingActive then return end
	Peddler._autoLoggedCount = Peddler._autoLoggedCount + 1
	if Peddler._autoLoggedCount >= Peddler._autoScheduledCount then
		RunAfter(0.1, FinalizeAutoSelling)
	end
end

local function PeddleGoods()
	local total = 0
	local sellCount = 0
	local sellDelay = 0
	local planned = {}

	for bag=0,4 do
		local slots = GetContainerNumSlots(bag)
		for slot=1,slots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local itemID, unique = Peddler.ParseItemLink(link)
				if unique and Peddler.itemIsToBeSold(itemID, unique) then
					planned[#planned+1] = { bag=bag, slot=slot, slots=slots, itemID=itemID, unique=unique }
					if SellLimit and #planned >= BUYBACK_COUNT then break end
				end
			end
		end
		if SellLimit and #planned >= BUYBACK_COUNT then break end
	end

	Peddler._autoScheduledCount = #planned
	Peddler._autoLoggedCount = 0
	Peddler._autoSellingActive = (#planned > 0)
	Peddler._buybackBaseline = nil

	for _, data in ipairs(planned) do
		local bag, slot, slots, itemID, unique = data.bag, data.slot, data.slots, data.itemID, data.unique
		local btn = _G["ContainerFrame"..(bag+1).."Item"..(slots - slot + 1)]
		if btn and btn.coins then btn.coins:Hide() end

		local _, countInStack = GetContainerItemInfo(bag, slot)
		countInStack = countInStack or 1
		local _, link, _, _, _, _, _, _, _, _, price = GetItemInfo(itemID)

		if price and price > 0 then
			local value = price * countInStack
			if total == 0 and (not Silent or not SilenceSaleSummary) then
				print("Peddler sold:")
			end
			total = total + value
			if not Silent then
				local msg = "    "..(sellCount+1)..". "..(link or ("item:"..itemID))
				if countInStack > 1 then msg = msg.."x"..countInStack end
				msg = msg.." for "..CoinsString(value)
				print(msg)
			end
		end

		local reason = GetSaleReasonCode(itemID, unique)

		local function DoSell()
			UseContainerItem(bag, slot)
			if Peddler.LogSale then
				local _, usedLink = GetItemInfo(itemID)
				Peddler.LogSale(itemID, usedLink or ("item:"..itemID), countInStack, (price or 0)*countInStack, reason)
			end
			OnAutoSaleLoggedIncrement()
		end

		if sellDelay > 0 then
			local grp = salesDelay:CreateAnimationGroup("PeddlerSellDelay"..sellCount)
			local anim = grp:CreateAnimation("Translation")
			anim:SetDuration(sellDelay)
			anim:SetSmoothing("OUT")
			grp:SetScript("OnFinished", DoSell)
			grp:Play()
		else
			DoSell()
		end

		sellCount = sellCount + 1
		sellDelay = math.floor(sellCount / 6)
	end

	if total > 0 and not SilenceSaleSummary then
		print("For a total of "..CoinsString(total))
	end

	if Peddler._autoScheduledCount == 0 then
		BuildBuybackBaseline()
	end
end

--------------------------------------------------
-- Buyback Hook
--------------------------------------------------
hooksecurefunc("BuybackItem", function(index)
	local link = GetBuybackItemLink(index)
	local name, _, price, quantity = GetBuybackItemInfo(index)
	if not (link or name) then return end
	if Peddler.LogSale then
		Peddler.LogSale(0, link or name, quantity or 1, price or 0, "buyback")
	end
	RunAfter(0.05, BuildBuybackBaseline)
end)

--------------------------------------------------
-- Manual Flag Resets
--------------------------------------------------
function Peddler.ResetManualFlags()
	if not ItemsToSell then ItemsToSell = {} end
	local c=0 for _ in pairs(ItemsToSell) do c=c+1 end
	for k in pairs(ItemsToSell) do ItemsToSell[k]=nil end
	print("|cff33ff99Peddler:|r Reset "..c.." manually flagged sell item"..(c==1 and "" or "s")..".")
	if Peddler.MarkWares then Peddler.MarkWares() end
end

function Peddler.ResetAll()
	for k,v in pairs(DEFAULTS) do _G[k] = v end

	ItemsToSell = {}
	UnmarkedItems = {}
	ItemsToDelete = {}
	PeddlerSalesHistory = {}
	-- Recreate state instead of nil (prevents nil indexing in History module)
	PeddlerHistoryFrameState = { width = 730, height = 480 }
	PeddlerHistorySessionNet = 0
	PeddlerSessionGoldBaseline = nil

	if Peddler.ResetHistoryWindow then Peddler.ResetHistoryWindow() end
	if Peddler.MarkWares then Peddler.MarkWares() end
	print("|cff33ff99Peddler:|r All settings reset to defaults.")
end

--------------------------------------------------
-- Right-click + Modifier Handling
--------------------------------------------------
local function ToggleSellFlag(itemID, unique)
	local _, _, quality, _, _, itemType, subType, _, equipSlot, _, price = GetItemInfo(itemID)
	if price == 0 then return false end
	local autoSellable = Peddler.ShouldAutoSell(itemID, unique)
	autoSellable = autoSellable and true or false
	if autoSellable then
		if UnmarkedItems[unique] then
			UnmarkedItems[unique] = nil
		else
			UnmarkedItems[unique] = 1
			ItemsToSell[unique] = nil
		end
	elseif ItemsToSell[unique] then
		ItemsToSell[unique] = nil
	else
		ItemsToSell[unique] = 1
	end
	return true
end

local function HandleItemClick(btn, button)
	local ctrl  = IsControlKeyDown()
	local shift = IsShiftKeyDown()
	local alt   = IsAltKeyDown()
	local modifierDown =
		   (ModifierKey == "CTRL" and ctrl)
		or (ModifierKey == "SHIFT" and shift)
		or (ModifierKey == "ALT" and alt)
		or (ModifierKey == "CTRL-SHIFT" and ctrl and shift)
		or (ModifierKey == "CTRL-ALT" and ctrl and alt)
		or (ModifierKey == "ALT-SHIFT" and alt and shift)

	if not (modifierDown and button == "RightButton") then return end
	local parent = btn:GetParent()
	if not parent then return end
	local bag = parent:GetID()
	local slot = btn:GetID()
	local link = GetContainerItemLink(bag, slot)
	if not link then return end
	local itemID, unique = Peddler.ParseItemLink(link)
	if not itemID then return end
	local _,_,_,_,_,_,_,_,_,_, price = GetItemInfo(itemID)
	if price == 0 or price == nil then
		Peddler.ItemDelete.ToggleDeleteFlag(itemID, unique)
	else
		ToggleSellFlag(itemID, unique)
	end
	if Peddler.MarkWares then Peddler.MarkWares() end
end
hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", HandleItemClick)

--------------------------------------------------
-- Quest Reward Hook (ALT-click)
--------------------------------------------------
local listeningToRewards = {}
local function CheckQuestReward(button)
	local rewardIndex = button:GetID()
	local function test(link)
		if not link then return end
		local itemID, unique = Peddler.ParseItemLink(link)
		if itemID and unique then
			local _, _, _, _, _, _, _, _, _, _, price = GetItemInfo(itemID)
			if price and price > 0 then
				ToggleSellFlag(itemID, unique)
			else
				Peddler.ItemDelete.ToggleDeleteFlag(itemID, unique)
			end
		end
	end
	test(GetQuestLogItemLink("reward", rewardIndex))
	test(GetQuestLogItemLink("choice", rewardIndex))
end

local function QuestRewardClick(self)
	if not IsAltKeyDown() then return end
	CheckQuestReward(self)
	if Peddler.MarkWares then Peddler.MarkWares() end
end

local function SetupQuestFrame(base)
	for i=1,6 do
		local name = base..i
		local btn = _G[name]
		if btn and not listeningToRewards[name] then
			listeningToRewards[name] = true
			btn:HookScript("OnClick", QuestRewardClick)
		end
	end
end
if QuestInfoRewardsFrame then
	QuestInfoRewardsFrame:HookScript("OnShow", function() SetupQuestFrame("QuestInfoRewardsFrameQuestInfoItem") end)
end
if MapQuestInfoRewardsFrame then
	MapQuestInfoRewardsFrame:HookScript("OnShow", function() SetupQuestFrame("MapQuestInfoRewardsFrameQuestInfoItem") end)
end

--------------------------------------------------
-- Events
--------------------------------------------------
coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("MERCHANT_SHOW")
coreFrame:RegisterEvent("MERCHANT_CLOSED")
coreFrame:RegisterEvent("MERCHANT_UPDATE")
coreFrame:RegisterEvent("BAG_UPDATE")

local function OnUpdateDriver()
	markCounter = markCounter + 1
	if markCounter > countLimit then
		markCounter = 0
		if Peddler.MarkWares then Peddler.MarkWares() end
	end
end

local function HandleEvent(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "Peddler" then
		self:UnregisterEvent("ADDON_LOADED")
		SetupDefaults()
		if Peddler.CompatRegister then Peddler.CompatRegister() end
		countLimit = 400
		self:SetScript("OnUpdate", OnUpdateDriver)
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- nothing special
	elseif event == "BAG_UPDATE" then
		if markCounter == 0 then
			self:SetScript("OnUpdate", OnUpdateDriver)
		end
	elseif event == "MERCHANT_SHOW" then
		if Peddler.InitHistoryButton then Peddler.InitHistoryButton() end
		PeddleGoods()
		Peddler.ItemDelete.MaybeShowPopup()
	elseif event == "MERCHANT_UPDATE" then
		DetectManualSell()
	elseif event == "MERCHANT_CLOSED" then
		if StaticPopup_Visible("PEDDLER_DELETE_UNSELLABLES") then
			StaticPopup_Hide("PEDDLER_DELETE_UNSELLABLES")
		end
	end
end
coreFrame:SetScript("OnEvent", HandleEvent)

--------------------------------------------------
-- Slash Commands
--------------------------------------------------
local function PrintHelp()
	print("|cff33ff99Peddler Commands:|r")
	print(" /peddler config        - open options")
	print(" /peddler history       - toggle history window")
	print(" /peddler setup         - run setup wizard again")
	print(" /peddler reset flags   - reset sell flags")
	print(" /peddler reset delete  - reset deletion flags")
	print(" /peddler reset history - reset history window")
	print(" /peddler reset all     - full reset")
	print(" /peddler help          - show this help")
end

SLASH_PEDDLER_COMMAND1 = "/peddler"
SlashCmdList["PEDDLER_COMMAND"] = function(cmd)
	cmd = Peddler.Trim(string.lower(cmd or ""))

	local function ShowHelp()
		print("|cff33ff99Peddler Commands:|r")
		print(" /peddler config        - open options")
		print(" /peddler history       - toggle history window")
		print(" /peddler setup         - run setup wizard again")
		print(" /peddler reset flags   - reset sell flags")
		print(" /peddler reset delete  - reset deletion flags")
		print(" /peddler reset history - reset history window")
		print(" /peddler reset all     - full reset")
		print(" /peddler help          - show this help")
	end

	if cmd == "" or cmd == "help" then
		ShowHelp()
	elseif cmd == "config" or cmd == "options" then
		if InterfaceOptionsFrame_OpenToCategory then
			InterfaceOptionsFrame_OpenToCategory("Peddler")
			InterfaceOptionsFrame_OpenToCategory("Peddler")
		end
	elseif cmd == "setup" then
		if Peddler.StartSetupWizard then
			Peddler.StartSetupWizard(true)
		else
			print("|cff33ff99Peddler:|r Setup module not loaded.")
		end
	elseif cmd == "history" or cmd == "hist" then
		if Peddler.ToggleHistory then Peddler.ToggleHistory() end
	elseif cmd == "reset flags" or cmd == "reset manual" then
		Peddler.ResetManualFlags()
	elseif cmd == "reset delete" then
		Peddler.ItemDelete.ToggleDeleteFlag = Peddler.ItemDelete.ToggleDeleteFlag -- ensure load
		Peddler.ItemDelete.Reset()
	elseif cmd == "reset history" then
		if Peddler.ResetHistoryWindow then Peddler.ResetHistoryWindow() end
	elseif cmd == "reset all" then
		Peddler.ResetAll()
	else
		ShowHelp()
	end
end

-- Safety shim: ensure history functions exist (in case History.lua failed to load)
if not Peddler.ShowHistory then
	function Peddler.ShowHistory()
		print("|cff33ff99Peddler:|r History module not loaded (fallback).")
	end
end
if not Peddler.ToggleHistory then
	function Peddler.ToggleHistory()
		Peddler.ShowHistory()
	end
end

PeddlerAPI = Peddler