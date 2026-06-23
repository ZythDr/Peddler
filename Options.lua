local addonName, Peddler = ...

-- Options panels
local frame = CreateFrame("Frame", "PeddlerOptionsPanel", InterfaceOptionsFramePanelContainer)
frame.name = "Peddler"
frame:Hide()

function frame:refresh() end

frame:SetScript("OnShow", function(self)
	self:SetScript("OnShow", nil)
	self:CreateOptions()
end)

local wantedFrame = CreateFrame("Frame", "PeddlerWantedOptionsPanel", InterfaceOptionsFramePanelContainer)
wantedFrame.name = "Wanted Items"
wantedFrame.parent = "Peddler"
wantedFrame:Hide()

function wantedFrame:refresh() end

wantedFrame:SetScript("OnShow", function(self)
	self:SetScript("OnShow", nil)
	self:CreateOptions()
end)

--------------------------------------------------
-- Helpers
--------------------------------------------------
local function SafeMarkWares()
	if Peddler and Peddler.RequestMarkWares then
		Peddler.RequestMarkWares()
	elseif Peddler and Peddler.MarkWares then
		Peddler.MarkWares()
	end
end

local function createCheckBoxOffset(parent, anchor, xOffset, yOffset, property, label, tooltip, usableWidth, onClick)
	local checkbox = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
	checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset, yOffset)

	local textFS = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	textFS:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
	textFS:SetWidth(usableWidth - 32)
	textFS:SetJustifyH("LEFT")
	textFS:SetWordWrap(true)
	textFS:SetText(label)

	checkbox.tooltip = tooltip
	checkbox:SetChecked(property)
	checkbox:SetScript("OnClick", function(self)
		if onClick then onClick(self:GetChecked()) end
	end)

	return checkbox, textFS, yOffset - math.max(26, 14)
end

local function createCheckBox(parent, anchor, yOffset, property, label, tooltip, usableWidth, onClick)
	return createCheckBoxOffset(parent, anchor, 0, yOffset, property, label, tooltip, usableWidth, onClick)
end

local function changeModifierKey(self)
	UIDropDownMenu_SetSelectedID(ModifierKeyDropDown, self:GetID())
	ModifierKey = self.value
end
local function initModifierKeys(self, level)
	local modifierKeys = {"CTRL", "ALT", "SHIFT", "CTRL-SHIFT", "CTRL-ALT", "ALT-SHIFT"}
	for index, modifierKey in ipairs(modifierKeys) do
		local info = UIDropDownMenu_CreateInfo()
		info.text = modifierKey
		info.value = modifierKey
		info.func = changeModifierKey
		UIDropDownMenu_AddButton(info)
		if modifierKey == ModifierKey then
			UIDropDownMenu_SetSelectedID(ModifierKeyDropDown, index)
		end
	end
end

local function changeIconPlacement(self)
	UIDropDownMenu_SetSelectedID(IconPlacementDropDown, self:GetID())
	IconPlacement = self.value
end
local function initIconPlacement(self, level)
	local iconPlacements = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}
	for index, iconPlacement in ipairs(iconPlacements) do
		local info = UIDropDownMenu_CreateInfo()
		info.text = iconPlacement
		info.value = iconPlacement
		info.func = changeIconPlacement
		UIDropDownMenu_AddButton(info)
		if iconPlacement == IconPlacement then
			UIDropDownMenu_SetSelectedID(IconPlacementDropDown, index)
		end
	end
end

local function createWantedCheckBox(parent, anchor, xOffset, yOffset, label, checked, tooltip, onClick)
	local checkbox = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
	checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset, yOffset)
	checkbox:SetChecked(checked)
	checkbox.tooltip = tooltip

	local textFS = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	textFS:SetPoint("LEFT", checkbox, "RIGHT", 3, 0)
	textFS:SetWidth(150)
	textFS:SetJustifyH("LEFT")
	textFS:SetText(label)

	checkbox:SetScript("OnClick", function(self)
		if onClick then onClick(self:GetChecked()) end
	end)
	return checkbox
end

local FALLBACK_WANTED_ITEM_TYPES = {
	["Armor"] = {
		"Cloth",
		"Leather",
		"Mail",
		"Plate",
		"Shields",
		"Librams",
		"Idols",
		"Totems",
		"Sigils",
		"Miscellaneous",
	},
	["Weapon"] = {
		"One-Handed Axes",
		"Two-Handed Axes",
		"One-Handed Maces",
		"Two-Handed Maces",
		"One-Handed Swords",
		"Two-Handed Swords",
		"Daggers",
		"Fist Weapons",
		"Polearms",
		"Staves",
		"Bows",
		"Crossbows",
		"Guns",
		"Thrown",
		"Wands",
		"Fishing Poles",
	},
}

local function GetWantedSubtypeList(itemType)
	local configured = Peddler.WANTED_ITEM_TYPES and Peddler.WANTED_ITEM_TYPES[itemType]
	if type(configured) == "table" and #configured > 0 then
		return configured
	end

	local found = {}
	local list = {}
	local classOrder = Peddler.WANTED_ITEM_CLASS_ORDER
	if type(classOrder) ~= "table" then
		classOrder = {}
		for classTag in pairs(Peddler.WANTED_ITEMS or {}) do
			classOrder[#classOrder+1] = classTag
		end
	end
	for _, classTag in ipairs(classOrder) do
		local classMap = Peddler.WANTED_ITEMS and Peddler.WANTED_ITEMS[classTag]
		local defaults = classMap and classMap[itemType]
		if type(defaults) == "table" then
			for _, subType in ipairs(defaults) do
				if not found[subType] then
					found[subType] = true
					list[#list+1] = subType
				end
			end
		end
	end
	if #list == 0 then
		for _, subType in ipairs(FALLBACK_WANTED_ITEM_TYPES[itemType] or {}) do
			if not found[subType] then
				found[subType] = true
				list[#list+1] = subType
			end
		end
	end
	return list
end

local function IsWantedForOptions(classTag, itemType, subType)
	if Peddler.IsWantedItemForClass then
		local ok, wanted = pcall(Peddler.IsWantedItemForClass, classTag, itemType, subType)
		if ok then return wanted end
	end
	return false
end

function frame:CreateOptions()
	if self._peddlerCreated then return end
	self._peddlerCreated = true

	local scroll = CreateFrame("ScrollFrame", "PeddlerOptionsScrollFrame", self, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -30, 8)

	local content = CreateFrame("Frame", "PeddlerOptionsContent", scroll)
	content:SetPoint("TOPLEFT")
	content:SetSize(540, 820)
	scroll:SetScrollChild(content)

	local usableWidth = 500

	-- Dynamic version from TOC
	local version = GetAddOnMetadata and (GetAddOnMetadata(addonName or "Peddler", "Version") or GetAddOnMetadata("Peddler", "Version")) or nil
	if version == "" then version = nil end
	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Peddler" .. (version and (" v" .. version) or ""))

	local y = -26

	local sellLimit, _, y1 = createCheckBox(content, title, y, SellLimit, "Sell Limit",
		"Limits the amount of items sold in one go (so you can buy them back).", usableWidth,
		function(val) SellLimit = val end)
	y = y1

	local silentMode, _, y2 = createCheckBox(content, title, y, Silent, "Silent Mode",
		"Silence chat output about sold items.", usableWidth,
		function(val) Silent = val end)
	y = y2

	local silenceSaleSummary, _, y3 = createCheckBox(content, title, y, SilenceSaleSummary, "Silence Sale Summary",
		"Silence the sale summary after a sale.", usableWidth,
		function(val) SilenceSaleSummary = val end)
	y = y3 - 6

	local modifierKeyLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	modifierKeyLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	modifierKeyLabel:SetWidth(usableWidth)
	modifierKeyLabel:SetJustifyH("LEFT")
	modifierKeyLabel:SetText("Modifier Key (right-click + modifier to mark/unmark):")
	y = y - 18

	local modifierKey = CreateFrame("Button", "ModifierKeyDropDown", content, "UIDropDownMenuTemplate")
	modifierKey:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	UIDropDownMenu_Initialize(ModifierKeyDropDown, initModifierKeys)
	UIDropDownMenu_SetWidth(ModifierKeyDropDown, 120)
	UIDropDownMenu_SetButtonWidth(ModifierKeyDropDown, 140)
	y = y - 40

	local iconPlacementLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	iconPlacementLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	iconPlacementLabel:SetWidth(usableWidth)
	iconPlacementLabel:SetJustifyH("LEFT")
	iconPlacementLabel:SetText("Icon Placement (reload may be required):")
	y = y - 18

	local iconPlacement = CreateFrame("Button", "IconPlacementDropDown", content, "UIDropDownMenuTemplate")
	iconPlacement:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	UIDropDownMenu_Initialize(IconPlacementDropDown, initIconPlacement)
	UIDropDownMenu_SetWidth(IconPlacementDropDown, 140)
	UIDropDownMenu_SetButtonWidth(IconPlacementDropDown, 160)
	y = y - 40

	local autoSellLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	autoSellLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	autoSellLabel:SetWidth(usableWidth)
	autoSellLabel:SetJustifyH("LEFT")
	autoSellLabel:SetText("Automatically sell...")
	y = y - 18

	local soulboundOnly, _, y4 = createCheckBox(content, title, y, SoulboundOnly, "Restrict to Soulbound Items",
		"Only auto-mark soulbound items (except always greys).", usableWidth,
		function(val) SoulboundOnly = val; SafeMarkWares() end)
	y = y4

	local labelPoor      = "|cff9d9d9dPoor|r Items"
	local labelCommon    = "|cffffffffCommon|r Items"
	local labelUncommon  = "|cff1eff00Uncommon|r Items"
	local labelRare      = "|cff0070ddRare|r Items"
	local labelEpic      = "|cffa335eeEpic|r Items"

	local autoSellGreyItems, _, y5 = createCheckBox(content, title, y, AutoSellGreyItems, labelPoor,
		"Automatically sells all grey/junk items.", usableWidth,
		function(val) AutoSellGreyItems = val; SafeMarkWares() end)
	y = y5

	local autoSellWhiteItems, _, y6 = createCheckBox(content, title, y, AutoSellWhiteItems, labelCommon,
		"Automatically sells all white/common items.", usableWidth,
		function(val) AutoSellWhiteItems = val; SafeMarkWares() end)
	y = y6

	local autoSellGreenItems, _, y7 = createCheckBox(content, title, y, AutoSellGreenItems, labelUncommon,
		"Automatically sells all green/uncommon items.", usableWidth,
		function(val) AutoSellGreenItems = val; SafeMarkWares() end)
	y = y7

	local autoSellBlueItems, _, y8 = createCheckBox(content, title, y, AutoSellBlueItems, labelRare,
		"Automatically sells all blue/rare items.", usableWidth,
		function(val) AutoSellBlueItems = val; SafeMarkWares() end)
	y = y8

	local autoSellPurpleItems, _, y9 = createCheckBox(content, title, y, AutoSellPurpleItems, labelEpic,
		"Automatically sells all purple/epic items.", usableWidth,
		function(val) AutoSellPurpleItems = val; SafeMarkWares() end)
	y = y9

	local unwantedTooltip =
		"Automatically sell all items unwanted for your class.\n" ..
		"|cffffaa00Recommended: Enable 'Restrict to Soulbound Items' to avoid BoE mistakes.|r"
	local autoSellUnwantedItems, _, y10 = createCheckBox(content, title, y, AutoSellUnwantedItems, "Unwanted Items",
		unwantedTooltip, usableWidth,
		function(val) AutoSellUnwantedItems = val; SafeMarkWares() end)
	y = y10 - 6

	local protectSetTooltip =
		"Do not manually flag or auto-sell the exact bag slots used by Blizzard Equipment Manager sets.\n" ..
		"Duplicate matching items in other bag slots can still be flagged."
	local protectEquipmentSetItems, _, yProtect = createCheckBox(content, title, y, ProtectEquipmentSetItems, "Protect Equipment Set Items",
		protectSetTooltip, usableWidth,
		function(val) ProtectEquipmentSetItems = val; SafeMarkWares() end)
	y = yProtect - 6

	local deletionHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	deletionHeader:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	deletionHeader:SetWidth(usableWidth)
	deletionHeader:SetJustifyH("LEFT")
	deletionHeader:SetText("Unsellable Item Deletion")
	y = y - 20

	local deletionTooltip = "Enable deletion of flagged unsellable items (items with no vendor price) when visiting a merchant.\n" ..
		"|cffff2020WARNING: Deleted items cannot be restored.|r\n" ..
		"Flag items via right-click + modifier (same as selling). They will appear with a red coin icon."
	local deleteEnable, _, y11 = createCheckBox(content, title, y, DeleteUnsellablesEnabled, "Enable deletion of unsellable items",
		deletionTooltip, usableWidth,
		function(val) DeleteUnsellablesEnabled = val end)
	y = y11 - 36

	local resetSellBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resetSellBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	resetSellBtn:SetSize(180, 22)
	resetSellBtn:SetText("Reset Manual Sell Flags")
	resetSellBtn:SetScript("OnClick", function() Peddler.ResetManualFlags() end)

	local resetDeleteBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resetDeleteBtn:SetPoint("TOPLEFT", resetSellBtn, "BOTTOMLEFT", 0, -14)
	resetDeleteBtn:SetSize(180, 22)
	resetDeleteBtn:SetText("Reset Deletion Flags")
	resetDeleteBtn:SetScript("OnClick", function()
		if not ItemsToDelete then ItemsToDelete = {} end
		local count=0
		for _ in pairs(ItemsToDelete) do count=count+1 end
		for k in pairs(ItemsToDelete) do ItemsToDelete[k]=nil end
		print("|cff33ff99Peddler:|r Reset "..count.." deletion flag(s).")
		SafeMarkWares()
	end)

	self:refresh()
end

InterfaceOptions_AddCategory(frame)

function wantedFrame:CreateOptions()
	if self._peddlerCreated then return end
	self._peddlerCreated = true

	local scroll = CreateFrame("ScrollFrame", "PeddlerWantedOptionsScrollFrame", self, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -30, 8)

	local content = CreateFrame("Frame", "PeddlerWantedOptionsContent", scroll)
	content:SetPoint("TOPLEFT")
	content:SetSize(540, 900)
	scroll:SetScrollChild(content)

	local usableWidth = 500
	if Peddler.EnsureWantedItemsConfig then Peddler.EnsureWantedItemsConfig() end

	local _, playerClassTag = UnitClass("player")
	local selectedWantedClass = playerClassTag or "WARRIOR"
	local wantedCheckboxes = {}

	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Wanted Item Filters")

	local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	note:SetWidth(usableWidth)
	note:SetJustifyH("LEFT")
	note:SetText("Account-wide filters used by Unwanted Items auto-selling.")

	local y = -48

	local wantedClassLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	wantedClassLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, y)
	wantedClassLabel:SetWidth(usableWidth)
	wantedClassLabel:SetJustifyH("LEFT")
	wantedClassLabel:SetText("Class:")
	y = y - 14

	local function refreshWantedCheckboxes()
		if Peddler.EnsureWantedItemsConfig then Peddler.EnsureWantedItemsConfig() end
		for _, data in ipairs(wantedCheckboxes) do
			data.checkbox:SetChecked(IsWantedForOptions(selectedWantedClass, data.itemType, data.subType))
		end
		if PeddlerWantedClassDropDown and UIDropDownMenu_SetText then
			local label = Peddler.WANTED_ITEM_CLASS_NAMES and Peddler.WANTED_ITEM_CLASS_NAMES[selectedWantedClass]
			UIDropDownMenu_SetText(PeddlerWantedClassDropDown, label or selectedWantedClass)
		end
	end

	local function changeWantedClass(self)
		selectedWantedClass = self.value
		UIDropDownMenu_SetSelectedID(PeddlerWantedClassDropDown, self:GetID())
		refreshWantedCheckboxes()
	end

	local function initWantedClasses(self, level)
		if not level then return end
		for index, classTag in ipairs(Peddler.WANTED_ITEM_CLASS_ORDER or {}) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = (Peddler.WANTED_ITEM_CLASS_NAMES and Peddler.WANTED_ITEM_CLASS_NAMES[classTag]) or classTag
			info.value = classTag
			info.func = changeWantedClass
			info.checked = (classTag == selectedWantedClass)
			UIDropDownMenu_AddButton(info, level)
			if classTag == selectedWantedClass then
				UIDropDownMenu_SetSelectedID(PeddlerWantedClassDropDown, index)
			end
		end
	end

	local wantedClassDropDown = CreateFrame("Button", "PeddlerWantedClassDropDown", content, "UIDropDownMenuTemplate")
	wantedClassDropDown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, y)
	UIDropDownMenu_Initialize(PeddlerWantedClassDropDown, initWantedClasses)
	UIDropDownMenu_SetWidth(PeddlerWantedClassDropDown, 150)
	UIDropDownMenu_SetButtonWidth(PeddlerWantedClassDropDown, 170)
	y = y - 38

	local function addWantedGroup(itemType, label, xOffset, startY)
		local groupLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		groupLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", xOffset, startY)
		groupLabel:SetWidth(220)
		groupLabel:SetJustifyH("LEFT")
		groupLabel:SetText(label)
		local groupY = startY - 17

		local items = GetWantedSubtypeList(itemType)
		for index, subType in ipairs(items) do
			local itemTypeForClick = itemType
			local subTypeForClick = subType
			local checkbox = createWantedCheckBox(
				content,
				title,
				xOffset,
				groupY - ((index - 1) * 23),
				subType,
				IsWantedForOptions(selectedWantedClass, itemType, subType),
				"Checked item subtypes are wanted for this class. Unchecked subtypes are treated as unwanted.",
				function(val)
					if Peddler.SetWantedItemForClass then
						Peddler.SetWantedItemForClass(selectedWantedClass, itemTypeForClick, subTypeForClick, val)
					end
					SafeMarkWares()
				end
			)
			wantedCheckboxes[#wantedCheckboxes+1] = {
				checkbox = checkbox,
				itemType = itemTypeForClick,
				subType = subTypeForClick,
			}
		end
		return groupY - (#items * 23) - 8
	end

	local armorBottom = addWantedGroup(Peddler.ARMOUR or "Armor", "Armor", 0, y)
	local weaponBottom = addWantedGroup(Peddler.WEAPON or "Weapon", "Weapons", 180, y)
	y = math.min(armorBottom, weaponBottom)

	local resetClassBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resetClassBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, y)
	resetClassBtn:SetSize(170, 22)
	resetClassBtn:SetText("Reset Selected Class")
	resetClassBtn:SetScript("OnClick", function()
		if Peddler.ResetWantedItemsForClass then
			Peddler.ResetWantedItemsForClass(selectedWantedClass)
			refreshWantedCheckboxes()
			SafeMarkWares()
		end
	end)

	local resetAllWantedBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resetAllWantedBtn:SetPoint("LEFT", resetClassBtn, "RIGHT", 10, 0)
	resetAllWantedBtn:SetSize(150, 22)
	resetAllWantedBtn:SetText("Reset All Classes")
	resetAllWantedBtn:SetScript("OnClick", function()
		if Peddler.ResetAllWantedItems then
			Peddler.ResetAllWantedItems()
			refreshWantedCheckboxes()
			SafeMarkWares()
		end
	end)

	refreshWantedCheckboxes()
	self:refresh()
end

InterfaceOptions_AddCategory(wantedFrame)
