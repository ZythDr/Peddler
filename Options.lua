local addonName, Peddler = ...

-- Scrollable options panel
local frame = CreateFrame("Frame", "PeddlerOptionsPanel", InterfaceOptionsFramePanelContainer)
frame.name = "Peddler"
frame:Hide()

function frame:refresh() end

frame:SetScript("OnShow", function(self)
	self:CreateOptions()
	self:SetScript("OnShow", nil)
end)

--------------------------------------------------
-- Helpers
--------------------------------------------------
local function SafeMarkWares()
	if Peddler and Peddler.MarkWares then
		Peddler.MarkWares()
	end
end

local function createCheckBox(parent, anchor, yOffset, property, label, tooltip, usableWidth, onClick)
	local checkbox = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
	checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)

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

function frame:CreateOptions()
	local scroll = CreateFrame("ScrollFrame", "PeddlerOptionsScrollFrame", self, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -30, 8)

	local content = CreateFrame("Frame", "PeddlerOptionsContent", scroll)
	content:SetWidth(scroll:GetWidth())
	content:SetHeight(800)
	scroll:SetScrollChild(content)

	local usableWidth = content:GetWidth() - 24

	-- Dynamic version from TOC
	local version = GetAddOnMetadata and (GetAddOnMetadata(addonName or "Peddler", "Version") or GetAddOnMetadata("Peddler", "Version")) or nil
	if version == "" then version = nil end
	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Peddler" .. (version and (" v" .. version) or ""))

	local y = -10

	-- Sell Limit
	local sellLimit, _, y2 = createCheckBox(content, title, y - 16, SellLimit, "Sell Limit",
		"Limits the amount of items sold in one go (so you can buy them back).", usableWidth,
		function(val) SellLimit = val end)
	y = y2

	-- Silent Mode
	local silentMode, _, y3 = createCheckBox(content, title, y, Silent, "Silent Mode",
		"Silence chat output about sold items.", usableWidth,
		function(val) Silent = val end)
	y = y3

	-- Silence Sale Summary
	local silenceSaleSummary, _, y4 = createCheckBox(content, title, y, SilenceSaleSummary, "Silence Sale Summary",
		"Silence the sale summary after a sale.", usableWidth,
		function(val) SilenceSaleSummary = val end)
	y = y4 - 6

	-- Modifier Key
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

	-- Icon Placement
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

	-- Auto-sell header
	local autoSellLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	autoSellLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	autoSellLabel:SetWidth(usableWidth)
	autoSellLabel:SetJustifyH("LEFT")
	autoSellLabel:SetText("Automatically sell...")
	y = y - 18

	-- Restrict to Soulbound
	local soulboundOnly, _, y5 = createCheckBox(content, title, y, SoulboundOnly, "Restrict to Soulbound Items",
		"Only auto-mark soulbound items (except always greys).", usableWidth,
		function(val) SoulboundOnly = val; SafeMarkWares() end)
	y = y5

	-- Quality colored labels
	local labelPoor      = "|cff9d9d9dPoor|r Items"
	local labelCommon    = "|cffffffffCommon|r Items"
	local labelUncommon  = "|cff1eff00Uncommon|r Items"
	local labelRare      = "|cff0070ddRare|r Items"
	local labelEpic      = "|cffa335eeEpic|r Items"

	local autoSellGreyItems, _, y6 = createCheckBox(content, title, y, AutoSellGreyItems, labelPoor,
		"Automatically sells all grey/junk items.", usableWidth,
		function(val) AutoSellGreyItems = val; SafeMarkWares() end)
	y = y6

	local autoSellWhiteItems, _, y7 = createCheckBox(content, title, y, AutoSellWhiteItems, labelCommon,
		"Automatically sells all white/common items.", usableWidth,
		function(val) AutoSellWhiteItems = val; SafeMarkWares() end)
	y = y7

	local autoSellGreenItems, _, y8 = createCheckBox(content, title, y, AutoSellGreenItems, labelUncommon,
		"Automatically sells all green/uncommon items.", usableWidth,
		function(val) AutoSellGreenItems = val; SafeMarkWares() end)
	y = y8

	local autoSellBlueItems, _, y9 = createCheckBox(content, title, y, AutoSellBlueItems, labelRare,
		"Automatically sells all blue/rare items.", usableWidth,
		function(val) AutoSellBlueItems = val; SafeMarkWares() end)
	y = y9

	local autoSellPurpleItems, _, y10 = createCheckBox(content, title, y, AutoSellPurpleItems, labelEpic,
		"Automatically sells all purple/epic items.", usableWidth,
		function(val) AutoSellPurpleItems = val; SafeMarkWares() end)
	y = y10

	local unwantedTooltip =
		"Automatically sell all items unwanted for your class.\n" ..
		"|cffffaa00Recommended: Enable 'Restrict to Soulbound Items' to avoid BoE mistakes.|r"
	local autoSellUnwantedItems, _, y11 = createCheckBox(content, title, y, AutoSellUnwantedItems, "Unwanted Items",
		unwantedTooltip, usableWidth,
		function(val) AutoSellUnwantedItems = val; SafeMarkWares() end)
	y = y11 - 6

	-- Deletion Feature
	local deletionHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	deletionHeader:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	deletionHeader:SetWidth(usableWidth)
	deletionHeader:SetJustifyH("LEFT")
	deletionHeader:SetText("Unsellable Item Deletion")
	y = y - 20

	local deletionTooltip = "Enable deletion of flagged unsellable items (items with no vendor price) when visiting a merchant.\n" ..
		"|cffff2020WARNING: Deleted items cannot be restored.|r\n" ..
		"Flag items via right-click + modifier (same as selling). They will appear with a red coin icon."
	local deleteEnable, _, y12 = createCheckBox(content, title, y, DeleteUnsellablesEnabled, "Enable deletion of unsellable items",
		deletionTooltip, usableWidth,
		function(val) DeleteUnsellablesEnabled = val end)
	y = y12 - 10

	-- Spacing before reset buttons
	y = y - 26

	-- Reset Manual Sell Flags (first button)
	local resetSellBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resetSellBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, y)
	resetSellBtn:SetSize(180, 22)
	resetSellBtn:SetText("Reset Manual Sell Flags")
	resetSellBtn:SetScript("OnClick", function() Peddler.ResetManualFlags() end)

	-- Second button below (with padding)
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

	-- Bottom padding after second button
	y = y - (22 + 14 + 20)

	local bottomY = -y + 220
	content:SetHeight(math.max(800, bottomY))

	self:refresh()
end

InterfaceOptions_AddCategory(frame)