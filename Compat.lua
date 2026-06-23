local addonName, Peddler = ...

-- Full bag addon compatibility & icon overlays restored

if not Peddler then Peddler = {} end

--------------------------------------------------
-- Local references
--------------------------------------------------
local GetContainerNumSlots  = GetContainerNumSlots
local GetContainerItemLink  = GetContainerItemLink
local GetItemInfo           = GetItemInfo
local IsAddOnLoaded         = IsAddOnLoaded

--------------------------------------------------
-- Icon helpers
--------------------------------------------------
local function EnsureSellTexture(btn)
	if not btn or btn.coins then return end
	local tex = btn:CreateTexture(nil,"OVERLAY")
	tex:SetTexture("Interface\\AddOns\\Peddler\\coins")
	local px,py=-3,1
	if IconPlacement and IconPlacement:find("TOP") then py=-3 end
	if IconPlacement and IconPlacement:find("LEFT") then px=1 end
	tex:SetPoint(IconPlacement or "BOTTOMLEFT", px, py)
	btn.coins = tex
end

local function EnsureDeleteTexture(btn)
	if not btn or btn.coins_delete then return end
	local tex = btn:CreateTexture(nil,"OVERLAY")
	tex:SetTexture("Interface\\AddOns\\Peddler\\coins_delete")
	local px,py=-3,1
	if IconPlacement and IconPlacement:find("TOP") then py=-3 end
	if IconPlacement and IconPlacement:find("LEFT") then px=1 end
	tex:SetPoint(IconPlacement or "BOTTOMLEFT", px, py)
	btn.coins_delete = tex
end

local function DisplayItemIcons(itemID, unique, btn, bag, slot)
	if not btn then return end
	if not unique then
		if btn.coins then btn.coins:Hide() end
		if btn.coins_delete then btn.coins_delete:Hide() end
		return
	end
	if Peddler.itemIsToBeSoldAtSlot and Peddler.itemIsToBeSoldAtSlot(itemID, unique, bag, slot) then
		EnsureSellTexture(btn)
		btn.coins:Show()
	elseif not Peddler.itemIsToBeSoldAtSlot and Peddler.itemIsToBeSold(itemID, unique) then
		EnsureSellTexture(btn)
		btn.coins:Show()
	elseif btn.coins then
		btn.coins:Hide()
	end
	if ItemsToDelete and ItemsToDelete[unique] and Peddler.ItemDelete.IsUnsellable(itemID)
		and not (Peddler.IsEquipmentSetBagSlot and Peddler.IsEquipmentSetBagSlot(bag, slot)) then
		EnsureDeleteTexture(btn)
		btn.coins_delete:Show()
	elseif btn.coins_delete then
		btn.coins_delete:Hide()
	end
end

local function CheckItem(bag, slot, btn)
	if not btn then return end
	local link = GetContainerItemLink(bag, slot)
	if not link then
		DisplayItemIcons(nil, nil, btn, bag, slot)
		return
	end
	local itemID, unique = Peddler.ParseItemLink(link)
	if itemID then
		DisplayItemIcons(itemID, unique, btn, bag, slot)
	else
		DisplayItemIcons(nil, nil, btn, bag, slot)
	end
end


local function CheckButton(btn)
	local bag, slot
	if Peddler.GetButtonBagSlot then
		bag, slot = Peddler.GetButtonBagSlot(btn)
	end
	-- Guda Bags: fallback if not yet patched in core
	if (not bag or not slot) and btn and btn.bagID and btn.slotID then
		bag, slot = btn.bagID, btn.slotID
	end
	if bag and slot then
		CheckItem(bag, slot, btn)
	end
end
-- Guda Bags support
local function markGudaBags()
	local misses = 0
	for i = 1, 512 do
		local btn = _G["Guda_ItemButton"..i]
		if btn then
			misses = 0
			CheckButton(btn)
		else
			misses = misses + 1
			if misses >= 32 then break end
		end
	end
end

--------------------------------------------------
-- Individual addon scanners (ported from original)
--------------------------------------------------
local function markBagginsBags()
	local Baggins = _G.Baggins
	if not (Baggins and Baggins.bagframes) then return end
	for _, bag in ipairs(Baggins.bagframes) do
		if bag.sections then
			for _, section in ipairs(bag.sections) do
				if section.items then
					for _, btn in ipairs(section.items) do
						local parent = btn:GetParent()
						if parent then CheckItem(parent:GetID(), btn:GetID(), btn) end
					end
				end
			end
		end
	end
end

local function markCombuctorBags()
	for bag=0,4 do
		for slot=1,36 do
			local btn=_G["ContainerFrame"..(bag+1).."Item"..slot]
			if btn then
				CheckButton(btn)
			end
		end
	end
end

local function markDragonUICombuctorBags()
	local misses = 0
	for itemID = 1, 512 do
		local btn = _G["DragonUI_CombuctorItem"..itemID]
		if btn then
			misses = 0
			CheckButton(btn)
		else
			misses = misses + 1
			if misses >= 32 then
				break
			end
		end
	end
end

local function markOneBagBags()
	for bag=0,4 do
		local slots=GetContainerNumSlots(bag)
		for slot=1,slots do
			local btn=_G["OneBagFrameBag"..bag.."Item"..(slots-slot+1)]
			if btn then
				local p=btn:GetParent()
				if p then CheckItem(p:GetID(), btn:GetID(), btn) end
			end
		end
	end
end

local function markBaudBagBags()
	for bag=0,4 do
		local slots=GetContainerNumSlots(bag)
		for slot=1,slots do
			CheckItem(bag, slot, _G["BaudBagSubBag"..bag.."Item"..slot])
		end
	end
end

local function markAdiBagBags()
	local total=0
	for bag=0,4 do total=total+GetContainerNumSlots(bag) end
	total=math.max(100,total+160)
	for i=1,total do
		local btn=_G["AdiBagsItemButton"..i]
		if btn then
			local _, b, s = strsplit('-', tostring(btn))
			b=tonumber(b); s=tonumber(s)
			if b and s then CheckItem(b,s,btn) end
		end
	end
end

local function markArkInventoryBags()
	for bag=0,4 do
		local slots=GetContainerNumSlots(bag)
		for slot=1,slots do
			CheckItem(bag, slot, _G["ARKINV_Frame1ScrollContainerBag"..(bag+1).."Item"..slot])
		end
	end
end

local function markfamBagsBags()
	for bag=0,4 do
		local slots=GetContainerNumSlots(bag)
		for slot=1,slots do
			CheckItem(bag, slot, _G["famBagsButton_"..bag.."_"..slot])
		end
	end
end

local function markCargBagsNivayaBags()
	local total=0
	for bag=0,4 do total=total+GetContainerNumSlots(bag) end
	total=total*5
	for i=1,total do
		local btn=_G["NivayaSlot"..i]
		if btn then
			local p=btn:GetParent()
			if p then CheckItem(p:GetID(), btn:GetID(), btn) end
		end
	end
end

local function markMonoBags()
	local total=0
	for bag=0,4 do total=total+GetContainerNumSlots(bag) end
	for i=1,total do
		local btn=_G["m_BagsSlot"..i]
		if btn then
			local p=btn:GetParent()
			if p then CheckItem(p:GetID(), btn:GetID(), btn) end
		end
	end
end

local function markDerpyBags()
	for bag=0,4 do
		local slots=GetContainerNumSlots(bag)
		for slot=1,slots do
			CheckItem(bag, slot, _G["StuffingBag"..bag.."_"..slot])
		end
	end
end

local function markElvUIBags()
	for bag=0,4 do
		local slots=GetContainerNumSlots(bag)
		for slot=1,slots do
			CheckItem(bag, slot, _G["ElvUI_ContainerFrameBag"..bag.."Slot"..slot])
		end
	end
end

local function markInventorianBags()
	for bag=0,NUM_CONTAINER_FRAMES do
		for slot=1,36 do
			local btn=_G["ContainerFrame"..(bag+1).."Item"..slot]
			if btn then
				local p=btn:GetParent()
				if p then CheckItem(p:GetID(), btn:GetID(), btn) end
			end
		end
	end
end

local function markLiteBagBags()
	if not _G.LiteBagInventoryPanel or not LiteBagInventoryPanel.itemButtons then return end
	for _, btn in pairs(LiteBagInventoryPanel.itemButtons) do
		if btn then
			local p=btn:GetParent()
			if p then CheckItem(p:GetID(), btn:GetID(), btn) end
		end
	end
end

local function markLUIBags()
	for bag=0,4 do
		local slots=GetContainerNumSlots(bag)
		for slot=1,slots do
			CheckItem(bag, slot, _G["LUIBags_Item"..bag.."_"..slot])
		end
	end
end

local function markSortedItems()
	for bag=0,4 do
		local slots=GetContainerNumSlots(bag)
		for slot=1,slots do
			CheckItem(bag, slot, _G["SortedSlot_Bag"..bag.."Item"..slot.."FavoriteButton"])
		end
	end
end

local function markNormalBags()
	for bag=0,4 do
		local frame=_G["ContainerFrame"..(bag+1)]
		if frame and frame:IsShown() then
			local slots=GetContainerNumSlots(bag)
			for slot=1,slots do
				local btn=_G["ContainerFrame"..(bag+1).."Item"..(slots-slot+1)]
				if btn then
					local p=btn:GetParent()
					if p then CheckItem(p:GetID(), btn:GetID(), btn) end
				end
			end
		end
	end
end

--------------------------------------------------
-- Public MarkWares (used by core OnUpdate driver)
--------------------------------------------------
function Peddler.MarkWares()
	if IsAddOnLoaded("Baggins") then
		markBagginsBags()
	elseif _G.Guda_ItemButton1 then
		markGudaBags()
	elseif _G.DragonUI_CombuctorFrame1 or _G.DragonUI_CombuctorItem1 then
		markDragonUICombuctorBags()
	elseif IsAddOnLoaded("Combuctor") or IsAddOnLoaded("Bagnon") then
		markCombuctorBags()
	elseif IsAddOnLoaded("OneBag3") then
		markOneBagBags()
	elseif IsAddOnLoaded("BaudBag") then
		markBaudBagBags()
	elseif IsAddOnLoaded("AdiBags") then
		markAdiBagBags()
	elseif IsAddOnLoaded("ArkInventory") then
		markArkInventoryBags()
	elseif IsAddOnLoaded("famBags") then
		markfamBagsBags()
	elseif IsAddOnLoaded("cargBags_Nivaya") then
		markCargBagsNivayaBags()
	elseif IsAddOnLoaded("m_Bags") then
		markMonoBags()
	elseif IsAddOnLoaded("DerpyStuffing") then
		markDerpyBags()
	elseif IsAddOnLoaded("Inventorian") then
		markInventorianBags()
	elseif IsAddOnLoaded("LiteBag") then
		markLiteBagBags()
	elseif IsAddOnLoaded("LUI") and _G["LUIBags_Item0_1"] then
		markLUIBags()
	elseif IsAddOnLoaded("Sorted") then
		markSortedItems()
	elseif IsAddOnLoaded("ElvUI") then
		markElvUIBags()
	else
		markNormalBags()
	end
end

--------------------------------------------------
-- Optional addon specific hook registration
--------------------------------------------------
function Peddler.CompatRegister()
	if IsAddOnLoaded("Baggins") and _G.Baggins and _G.Baggins.RegisterSignal and not Peddler._bagginsRegistered then
		Peddler._bagginsRegistered = true
		_G.Baggins:RegisterSignal("Baggins_BagOpened", function()
			if Peddler.RequestMarkWares then Peddler.RequestMarkWares(0.01) elseif Peddler.MarkWares then Peddler.MarkWares() end
		end, _G.Baggins)
	end
	if not Peddler._bagShowHooksRegistered then
		Peddler._bagShowHooksRegistered = true
		local function request()
			if Peddler.RequestMarkWares then Peddler.RequestMarkWares(0.01) elseif Peddler.MarkWares then Peddler.MarkWares() end
		end
		for i=1,(NUM_CONTAINER_FRAMES or 13) do
			local frame = _G["ContainerFrame"..i]
			if frame and frame.HookScript then
				frame:HookScript("OnShow", request)
			end
		end
		local knownFrames = {
			"BagnonFrameinventory",
			"CombuctorFrameinventory",
			"ElvUI_ContainerFrame",
			"BaudBagContainer1_1",
			"LiteBagInventoryPanel",
		}
		for _, name in ipairs(knownFrames) do
			local frame = _G[name]
			if frame and frame.HookScript then
				frame:HookScript("OnShow", request)
			end
		end
	end
end
