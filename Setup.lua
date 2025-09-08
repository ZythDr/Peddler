-- Peddler Setup Wizard

local addonName, Peddler = ...
_G.Peddler = _G.Peddler or Peddler

local DEBUG = false
local function dbg(...)
	if DEBUG then
		local t={}
		for i=1,select("#", ...) do
			local v=select(i,...)
			t[#t+1]=v==nil and "nil" or tostring(v)
		end
		DEFAULT_CHAT_FRAME:AddMessage("|cff8855FFPeddlerSetupDBG:|r "..table.concat(t," "))
	end
end

local Wizard = { frame=nil, stepIndex=1, steps={}, answers={}, applied=false }

local PREFIX        = "|cff33ff99Peddler:|r "
local COLOR_HEADER  = "|cffffd100"
local COLOR_RECO    = "|cff80ff80"
local COLOR_DIM     = "|cffaaaaaa"

local MIN_FRAME_HEIGHT = 210
local LIVE_SYNC_MODIFIER = false
local DROPDOWN_X_OFFSET = -60  -- left shift for modifier dropdown

--------------------------------------------------
-- Step Definitions
--------------------------------------------------
local function BuildSteps()
	Wizard.steps = {
		{
			key="SellLimit", type="boolean",
			header="Sell Limit",
			body="Would you like to enable the Sell Limit option? This will limit Peddler to only sell up to 12 items per vendor visit.\nThis is intended for people who prefer the safety of being able to buy back anything that Peddler sells automatically.",
			recommended="Recommended: User Preference",
			yesLabel="Enable", noLabel="Disable",
			frameHeight=230, containerHeight=90,
		},
		{
			key="Silent", type="boolean",
			header="Silent Mode",
			body="Would you like to enable the Silent Mode?\nThis removes the chat display of each individual item that Peddler automatically sells.",
			recommended="Recommended: User Preference",
			yesLabel="Enable", noLabel="Disable",
			frameHeight=210, containerHeight=80,
		},
		{
			key="ModifierKey", type="modifier",
			header="Modifier Key",
			body="Choose which modifier key combination you want to use with Right-Click to flag or unflag items.",
			recommended="Recommended: Ctrl or Alt",
			frameHeight=220, containerHeight=85,
		},
		{
			type="quality", key="__QUALITY__",
			header="Quality Filters",
			body="Select which quality items to automatically flag to be auto-sold at vendors:",
			recommended="Recommended: Poor Items. Restrict \nto Soulbound, Unwanted Items",
			frameHeight=340, containerHeight=200,
			list = {
				{ var="AutoSellGreyItems",   label="Poor",     color="|cff9d9d9d", default=true,  tooltip="Automatically sell Poor (grey) quality items." },
				{ var="AutoSellWhiteItems",  label="Common",   color="|cffffffff", default=false, tooltip="Automatically sell Common (white) quality items." },
				{ var="AutoSellGreenItems",  label="Uncommon", color="|cff1eff00", default=false, tooltip="Automatically sell Uncommon (green) quality items." },
				{ var="AutoSellBlueItems",   label="Rare",     color="|cff0070dd", default=false, tooltip="Automatically sell Rare (blue) quality items." },
				{ var="AutoSellPurpleItems", label="Epic",     color="|cffa335ee", default=false, tooltip="Automatically sell Epic (purple) quality items." },
			},
			extras = {
				{ var="SoulboundOnly",        label="Only Soulbound items", color="|cffffffff", default=true,  tooltip="If enabled, only soulbound (non-grey) items are sold for enabled qualities." },
				{ var="AutoSellUnwantedItems",label="Unwanted Items",       color="|cffffffff", default=true,  tooltip="Automatically sell class-unusable equipment." },
			}
		},
		{
			key="DeleteUnsellablesEnabled", type="boolean",
			header="Enable item deletions?",
			body="Allow Peddler to delete manually flagged unsellable items (no vendor price) after confirmation at vendor.",
			recommended="Recommended: User Preference",
			yesLabel="Enable", noLabel="Disable",
			frameHeight=230, containerHeight=90,
		},
		{
			type="summary", header="Summary",
			body="Review your choices below.",
			recommended="Apply to save or Back to adjust.",
			frameHeight=360, containerHeight=190,
		},
	}
	Wizard.stepIndex=1
	Wizard.answers={}
	Wizard.applied=false
	-- Preload from saved vars
	for _, step in ipairs(Wizard.steps) do
		if step.type == "boolean" and step.key then
			if _G[step.key] ~= nil then
				Wizard.answers[step.key] = _G[step.key] and true or false
			end
		elseif step.type == "modifier" then
			if _G["ModifierKey"] then
				Wizard.answers.ModifierKey = _G["ModifierKey"]
			end
		elseif step.type == "quality" then
			for _, q in ipairs(step.list) do
				if _G[q.var] ~= nil then
					Wizard.answers[q.var] = _G[q.var] and true or false
				end
			end
			for _, e in ipairs(step.extras or {}) do
				if _G[e.var] ~= nil then
					Wizard.answers[e.var] = _G[e.var] and true or false
				end
			end
		end
	end
end

--------------------------------------------------
-- Apply Answers
--------------------------------------------------
local function ApplyAnswers()
	for _, step in ipairs(Wizard.steps) do
		if step.type=="boolean" and step.key and Wizard.answers[step.key] ~= nil then
			_G[step.key]=Wizard.answers[step.key]
		elseif step.type=="modifier" and Wizard.answers.ModifierKey then
			_G["ModifierKey"]=Wizard.answers.ModifierKey
		elseif step.type=="quality" then
			for _, q in ipairs(step.list) do
				if Wizard.answers[q.var] ~= nil then _G[q.var]=Wizard.answers[q.var] end
			end
			for _, e in ipairs(step.extras or {}) do
				if Wizard.answers[e.var] ~= nil then _G[e.var]=Wizard.answers[e.var] end
			end
		end
	end
	PeddlerSetupDoneGlobal=true
	Wizard.applied=true
end

local function PrintCompletion()
	print(PREFIX.."Setup complete.")
	print("|cff33ff99Peddler Commands:|r")
	print(" /peddler config")
	print(" /peddler history")
	print(" /peddler setup")
	print(" /peddler reset flags")
	print(" /peddler reset delete")
	print(" /peddler reset history")
	print(" /peddler reset all")
	print(" /peddler help")
end

--------------------------------------------------
-- UI Creation
--------------------------------------------------
local BASE_WIDTH=366
local PROGRESS_Y=18

local function EnsureFrame()
	if Wizard.frame then return end
	local f=CreateFrame("Frame","PeddlerSetupFrame",UIParent,"UIPanelDialogTemplate")
	f:SetSize(BASE_WIDTH, MIN_FRAME_HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	if f.TitleText then f.TitleText:SetText("") end
	local closeBtn=_G[f:GetName().."CloseButton"]

	local title=f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
	title:SetPoint("TOP", f, "TOP", 0, -8)
	title:SetText(COLOR_HEADER.."Peddler Setup|r")

	local headerFS=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
	headerFS:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -44)
	headerFS:SetWidth(BASE_WIDTH-36)
	headerFS:SetJustifyH("LEFT")

	local bodyFS=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	bodyFS:SetPoint("TOPLEFT", headerFS, "BOTTOMLEFT", 0, -5)
	bodyFS:SetWidth(BASE_WIDTH-36)
	bodyFS:SetJustifyH("LEFT")

	local reco=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
	reco:SetPoint("TOPLEFT", bodyFS, "BOTTOMLEFT", 0, -3)
	reco:SetWidth(BASE_WIDTH-36)
	reco:SetJustifyH("LEFT")

	local choiceContainer=CreateFrame("Frame", nil, f)
	choiceContainer:SetPoint("TOPLEFT", reco, "BOTTOMLEFT", 0, -6)
	choiceContainer:SetSize(BASE_WIDTH-36, 90)

	local yesBtn=CreateFrame("Button", nil, choiceContainer, "UIPanelButtonTemplate")
	yesBtn:SetSize(110,22)
	local noBtn=CreateFrame("Button", nil, choiceContainer, "UIPanelButtonTemplate")
	noBtn:SetSize(110,22)

	-- Modifier dropdown
	local modifierLabel = choiceContainer:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	modifierLabel:SetWidth(choiceContainer:GetWidth())
	modifierLabel:SetJustifyH("CENTER")
	modifierLabel:Hide()

	local modifierDropdown = CreateFrame("Button","PeddlerSetupModifierDropdown",choiceContainer,"UIDropDownMenuTemplate")
	modifierDropdown:Hide()

	local function ModifierDropdown_Change(self)
		UIDropDownMenu_SetSelectedID(modifierDropdown, self:GetID())
		Wizard.answers.ModifierKey = self.value
		if LIVE_SYNC_MODIFIER then
			_G["ModifierKey"] = self.value
		end
	end

	local function ModifierDropdown_Init(self, level)
		if not level then return end
		local choices = {"CTRL","ALT","SHIFT","CTRL-SHIFT","CTRL-ALT","ALT-SHIFT"}
		local current = Wizard.answers.ModifierKey or _G.ModifierKey or "ALT"
		for i,key in ipairs(choices) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = key
			info.value = key
			info.func = ModifierDropdown_Change
			UIDropDownMenu_AddButton(info, level)
			if current == key then
				UIDropDownMenu_SetSelectedID(modifierDropdown, i)
			end
		end
	end

	-- Shared Continue button (used on Step 3 & 4)
	local continueBtn=CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	continueBtn:SetSize(90,22)
	continueBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
	continueBtn:SetText("Continue")
	continueBtn:Hide()

	-- Quality header
	local qualityHeader=choiceContainer:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	qualityHeader:SetWidth(choiceContainer:GetWidth())
	qualityHeader:SetJustifyH("LEFT")
	qualityHeader:SetPoint("TOPLEFT", choiceContainer, "TOPLEFT", 0, 0)
	qualityHeader:Hide()

	local leftCol  = CreateFrame("Frame", nil, choiceContainer)
	local rightCol = CreateFrame("Frame", nil, choiceContainer)
	leftCol:SetPoint("TOPLEFT", choiceContainer, "TOPLEFT", 0, -18)
	rightCol:SetPoint("TOPRIGHT", choiceContainer, "TOPRIGHT", 0, -18)
	leftCol:SetSize(math.floor((choiceContainer:GetWidth()/2)-6), 10)
	rightCol:SetSize(math.floor((choiceContainer:GetWidth()/2)-6), 10)
	leftCol:Hide(); rightCol:Hide()

	local qualityChecks={}
	local flagChecks={}
	f.qualityLeftHeader=nil
	f.qualityRightHeader=nil

	local function CreateCheck(parent, xAnchorRef, yOffset, varKey, coloredLabel, tooltip, alignRight)
		local cb=CreateFrame("CheckButton", nil, parent)
		cb:SetSize(18,18)
		if alignRight then
			cb:SetPoint("TOPRIGHT", xAnchorRef, "BOTTOMRIGHT", 0, yOffset)
		else
			cb:SetPoint("TOPLEFT",  xAnchorRef, "BOTTOMLEFT", 0, yOffset)
		end
		local nt=cb:CreateTexture(nil,"ARTWORK") nt:SetTexture("Interface\\Buttons\\UI-CheckBox-Up") nt:SetAllPoints() cb:SetNormalTexture(nt)
		local pt=cb:CreateTexture(nil,"ARTWORK") pt:SetTexture("Interface\\Buttons\\UI-CheckBox-Down") pt:SetAllPoints() cb:SetPushedTexture(pt)
		local ht=cb:CreateTexture(nil,"HIGHLIGHT") ht:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight") ht:SetAllPoints() ht:SetBlendMode("ADD") cb:SetHighlightTexture(ht)
		local ct=cb:CreateTexture(nil,"ARTWORK") ct:SetTexture("Interface\\Buttons\\UI-CheckBox-Check") ct:SetAllPoints() cb:SetCheckedTexture(ct)
		local labelFS=cb:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		if alignRight then
			labelFS:SetPoint("RIGHT", cb, "LEFT", -4, 0)
		else
			labelFS:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		end
		labelFS:SetText(coloredLabel)
		cb.labelFS=labelFS
		cb.varKey=varKey
		cb.tooltipText=tooltip
		cb:Hide()
		cb:SetScript("OnEnter", function(self)
			if not self.tooltipText then return end
			GameTooltip:SetOwner(self, alignRight and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipText,1,1,1,true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return cb
	end

	local summaryScroll=CreateFrame("ScrollFrame","PeddlerSetupSummaryScroll",choiceContainer,"UIPanelScrollFrameTemplate")
	summaryScroll:SetPoint("TOPLEFT", choiceContainer, "TOPLEFT", 0, 0)
	summaryScroll:SetPoint("BOTTOMRIGHT", choiceContainer, "BOTTOMRIGHT", -24, 0)
	local summaryContent=CreateFrame("Frame", nil, summaryScroll)
	summaryContent:SetSize(choiceContainer:GetWidth()-24, 200)
	summaryScroll:SetScrollChild(summaryContent)
	local summaryText=summaryContent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	summaryText:SetPoint("TOPLEFT", summaryContent, "TOPLEFT", 0, 0)
	summaryText:SetWidth(choiceContainer:GetWidth()-30)
	summaryText:SetJustifyH("LEFT")
	summaryScroll:Hide()
	summaryScroll:EnableMouse(true)
	summaryScroll:EnableMouseWheel(true)
	summaryScroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange()
		if range <= 0 then return end
		local step = 24
		local new = self:GetVerticalScroll() - (delta * step)
		if new < 0 then new = 0 elseif new > range then new = range end
		self:SetVerticalScroll(new)
	end)

	local backBtn=CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	backBtn:SetSize(70,22)
	backBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
	backBtn:SetText("Back")

	local progressFS=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
	progressFS:SetPoint("BOTTOM", f, "BOTTOM", 0, PROGRESS_Y)
	progressFS:SetText("")

	local applyBtn=CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	applyBtn:SetSize(90,22)
	applyBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
	applyBtn:SetText("Apply")
	applyBtn:Hide()

	if closeBtn then
		closeBtn:SetScript("OnClick", function()
			PeddlerSetupDoneGlobal=true
			print(PREFIX.."Setup canceled. Run again with /peddler setup or configure via /peddler config.")
			f:Hide()
		end)
	end

	Wizard.frame=f
	f.headerFS=headerFS; f.bodyFS=bodyFS; f.reco=reco
	f.choiceContainer=choiceContainer
	f.yesBtn=yesBtn; f.noBtn=noBtn
	f.modifierLabel=modifierLabel; f.modifierDropdown=modifierDropdown
	f.qualityHeader=qualityHeader
	f.leftCol=leftCol; f.rightCol=rightCol
	f.qualityChecks=qualityChecks; f.flagChecks=flagChecks
	f.continueBtn=continueBtn
	f.summaryScroll=summaryScroll; f.summaryText=summaryText; f.summaryContent=summaryContent
	f.applyBtn=applyBtn; f.backBtn=backBtn; f.progressFS=progressFS

	--------------------------------------------------
	-- Helpers
	--------------------------------------------------
	local function BuildSummaryText()
		local a=Wizard.answers
		local function mark(k)local v=a[k]; if v==nil then return"UNCHANGED" end return v and"YES" or "NO" end
		local lines={
			COLOR_HEADER.."Summary of Choices|r",
			"Sell Limit: "..mark("SellLimit"),
			"Silent Mode: "..mark("Silent"),
			"Modifier Key: "..(a.ModifierKey or _G.ModifierKey or "ALT"),
			"|cff9d9d9dPoor|r: "..mark("AutoSellGreyItems"),
			"|cffffffffCommon|r: "..mark("AutoSellWhiteItems"),
			"|cff1eff00Uncommon|r: "..mark("AutoSellGreenItems"),
			"|cff0070ddRare|r: "..mark("AutoSellBlueItems"),
			"|cffa335eeEpic|r: "..mark("AutoSellPurpleItems"),
			"Only Soulbound: "..mark("SoulboundOnly"),
			"Unwanted Items: "..mark("AutoSellUnwantedItems"),
			"Delete Unsellables: "..mark("DeleteUnsellablesEnabled"),
			"",
			COLOR_RECO.."Click Apply to save or Back to adjust.|r"
		}
		return table.concat(lines,"\n")
	end

	local function UpdateProgress()
		progressFS:SetText(COLOR_DIM.."Step "..Wizard.stepIndex.." / "..#Wizard.steps.."|r")
	end

	local function HideDynamic()
		yesBtn:Hide(); noBtn:Hide()
		modifierLabel:Hide(); modifierDropdown:Hide()
		qualityHeader:Hide()
		leftCol:Hide(); rightCol:Hide()
		for _,cb in ipairs(qualityChecks) do cb:Hide() end
		for _,cb in ipairs(flagChecks) do cb:Hide() end
		if f.qualityLeftHeader then f.qualityLeftHeader:Hide() end
		if f.qualityRightHeader then f.qualityRightHeader:Hide() end
		continueBtn:Hide()
		summaryScroll:Hide()
		applyBtn:Hide()
	end

	local function CenterBooleanButtons()
		yesBtn:ClearAllPoints(); noBtn:ClearAllPoints()
		yesBtn:SetPoint("TOP", choiceContainer, "TOP", -60, 0)
		noBtn:SetPoint("TOP",  choiceContainer, "TOP",  60, 0)
	end

	local ROW_OFFSET = -4
	local function BuildQualityColumns(step)
		wipe(qualityChecks); wipe(flagChecks)
		if f.qualityLeftHeader then f.qualityLeftHeader:Hide() end
		if f.qualityRightHeader then f.qualityRightHeader:Hide() end
		leftCol:Show(); rightCol:Show()

		local lhdr = f.qualityLeftHeader or leftCol:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		lhdr:ClearAllPoints(); lhdr:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, 0)
		lhdr:SetText(COLOR_HEADER.."Qualities:|r"); lhdr:Show(); f.qualityLeftHeader=lhdr

		local rhdr = f.qualityRightHeader or rightCol:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		rhdr:ClearAllPoints(); rhdr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
		rhdr:SetText(COLOR_HEADER.."Flags:|r"); rhdr:Show(); f.qualityRightHeader=rhdr

		local extras = step.extras or {}
		local extra1, extra2 = extras[1], extras[2]
		local prevLeft, prevRight = lhdr, rhdr

		for idx, q in ipairs(step.list) do
			if Wizard.answers[q.var]==nil then
				if _G[q.var] ~= nil then Wizard.answers[q.var]=_G[q.var] else Wizard.answers[q.var]=q.default and true or false end
			end
			local lab=(q.color or "|cffffffff")..q.label.."|r"
			local leftCB = CreateCheck(leftCol, prevLeft, ROW_OFFSET, q.var, lab, q.tooltip, false)
			leftCB:SetChecked(Wizard.answers[q.var])
			leftCB:SetScript("OnClick", function(self)
				Wizard.answers[self.varKey]=self:GetChecked() and true or false
			end)
			leftCB:Show()
			qualityChecks[#qualityChecks+1]=leftCB
			prevLeft = leftCB

			if idx==1 and extra1 then
				if Wizard.answers[extra1.var]==nil then
					if _G[extra1.var] ~= nil then Wizard.answers[extra1.var]=_G[extra1.var] else Wizard.answers[extra1.var]=extra1.default and true or false end
				end
				local lab1=(extra1.color or "|cffffffff")..extra1.label.."|r"
				local rightCB = CreateCheck(rightCol, prevRight, ROW_OFFSET, extra1.var, lab1, extra1.tooltip, true)
				rightCB:SetChecked(Wizard.answers[extra1.var])
				rightCB:SetScript("OnClick", function(self)
					Wizard.answers[self.varKey]=self:GetChecked() and true or false
				end)
				rightCB:Show()
				flagChecks[#flagChecks+1]=rightCB
				prevRight=rightCB
			elseif idx==2 and extra2 then
				if Wizard.answers[extra2.var]==nil then
					if _G[extra2.var] ~= nil then Wizard.answers[extra2.var]=_G[extra2.var] else Wizard.answers[extra2.var]=extra2.default and true or false end
				end
				local lab2=(extra2.color or "|cffffffff")..extra2.label.."|r"
				local rightCB = CreateCheck(rightCol, prevRight, ROW_OFFSET, extra2.var, lab2, extra2.tooltip, true)
				rightCB:SetChecked(Wizard.answers[extra2.var])
				rightCB:SetScript("OnClick", function(self)
					Wizard.answers[self.varKey]=self:GetChecked() and true or false
				end)
				rightCB:Show()
				flagChecks[#flagChecks+1]=rightCB
				prevRight=rightCB
			else
				local spacer=CreateFrame("Frame", nil, rightCol)
				spacer:SetSize(1,1)
				spacer:SetPoint("TOPRIGHT", prevRight, "BOTTOMRIGHT", 0, ROW_OFFSET)
				prevRight=spacer
			end
		end
	end

	local function Advance()
		Wizard.stepIndex=Wizard.stepIndex+1
		if Wizard.stepIndex > #Wizard.steps then Wizard.stepIndex=#Wizard.steps end
		f.ShowStep()
	end
	f.Advance=Advance

	function f.ShowStep()
		local step=Wizard.steps[Wizard.stepIndex]; if not step then return end
		local targetHeight=step.frameHeight or MIN_FRAME_HEIGHT
		if targetHeight < MIN_FRAME_HEIGHT then targetHeight=MIN_FRAME_HEIGHT end
		f:SetHeight(targetHeight)
		choiceContainer:SetHeight(step.containerHeight or 80)

		UpdateProgress()
		HideDynamic()

		headerFS:SetText(COLOR_HEADER..(step.header or "Step").."|r")
		bodyFS:SetText("|cffffffff"..(step.body or "").."|r")
		reco:SetText(COLOR_RECO..(step.recommended or "").."|r")

		if Wizard.stepIndex==1 then
			if f.backBtn.Disable then f.backBtn:Disable() end
		else
			if f.backBtn.Enable then f.backBtn:Enable() end
		end

		if step.type=="boolean" then
			if Wizard.answers[step.key]==nil and _G[step.key] ~= nil then
				Wizard.answers[step.key] = _G[step.key] and true or false
			end
			yesBtn:SetText(step.yesLabel or "Yes")
			noBtn:SetText(step.noLabel or "No")
			CenterBooleanButtons()
			yesBtn:Show(); noBtn:Show()

		elseif step.type=="modifier" then
			if not Wizard.answers.ModifierKey then
				Wizard.answers.ModifierKey = _G.ModifierKey or "ALT"
			end
			modifierLabel:SetText("|cffffffffSelect a modifier:|r")
			modifierLabel:Show()
			modifierDropdown:Show()
			modifierDropdown:ClearAllPoints()
			modifierDropdown:SetPoint("TOP", choiceContainer, "TOP", DROPDOWN_X_OFFSET, -26)
			UIDropDownMenu_Initialize(modifierDropdown, ModifierDropdown_Init)
			-- Show Continue button on this step
			continueBtn:SetText("Continue")
			continueBtn:Show()

		elseif step.type=="quality" then
			local fp,sz,fl=GameFontNormal:GetFont()
			qualityHeader:SetFont(fp, sz, fl)
			qualityHeader:SetText(COLOR_HEADER.."Select automatic flags:|r")
			qualityHeader:Show()
			leftCol:Show(); rightCol:Show()
			BuildQualityColumns(step)
			continueBtn:SetText("Continue")
			continueBtn:Show()

		elseif step.type=="summary" then
			summaryScroll:Show()
			summaryText:SetText(BuildSummaryText())
			local sb=_G[summaryScroll:GetName().."ScrollBar"]
			local needsScroll = summaryText:GetStringHeight() > f.summaryContent:GetHeight()
			if not needsScroll then
				if sb then sb:Hide() end
				summaryScroll:SetVerticalScroll(0)
			else
				if sb then sb:Show() end
			end
			applyBtn:Show()
		end
	end

	-- Button scripts
	yesBtn:SetScript("OnClick", function()
		local s=Wizard.steps[Wizard.stepIndex]; if s and s.type=="boolean" then Wizard.answers[s.key]=true; f.Advance() end
	end)
	noBtn:SetScript("OnClick", function()
		local s=Wizard.steps[Wizard.stepIndex]; if s and s.type=="boolean" then Wizard.answers[s.key]=false; f.Advance() end
	end)
	continueBtn:SetScript("OnClick", function() f.Advance() end)

	backBtn:SetScript("OnClick", function()
		if Wizard.stepIndex>1 then
			Wizard.stepIndex=Wizard.stepIndex-1
			f.ShowStep()
		end
	end)

	applyBtn:SetScript("OnClick", function()
		if not Wizard.applied then
			ApplyAnswers()
			PrintCompletion()
			f:Hide()
		end
	end)

	if closeBtn then
		closeBtn:SetScript("OnClick", function()
			PeddlerSetupDoneGlobal=true
			print(PREFIX.."Setup canceled. Run again with /peddler setup or configure via /peddler config.")
			f:Hide()
		end)
	end

	f:SetScript("OnShow", function() f.ShowStep() end)
end

--------------------------------------------------
-- Public Entry
--------------------------------------------------
function Peddler.StartSetupWizard(force)
	EnsureFrame()
	if PeddlerSetupDoneGlobal and not force then
		print(PREFIX.."Setup already completed. Use /peddler setup to rerun.")
		return
	end
	BuildSteps()
	Wizard.frame:Show()
end

--------------------------------------------------
-- Auto-run
--------------------------------------------------
local loader=CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_,_,name)
	if name~="Peddler" then return end
	loader:UnregisterEvent("ADDON_LOADED")
	if _G.PeddlerSetupDone and not PeddlerSetupDoneGlobal then
		PeddlerSetupDoneGlobal=true
	end
	if not PeddlerSetupDoneGlobal then
		local fr,t=CreateFrame("Frame"),0
		fr:SetScript("OnUpdate", function(_,dt)
			t=t+dt
			if t>=1 then fr:SetScript("OnUpdate", nil); Peddler.StartSetupWizard(false) end
		end)
	end

end)
