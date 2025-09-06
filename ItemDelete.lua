local addonName, Peddler = ...

if not Peddler then Peddler = {} end
Peddler.ItemDelete = Peddler.ItemDelete or {}
local F = Peddler.ItemDelete

--------------------------------------------------
-- Configuration
--------------------------------------------------
local POPUP_KEY              = "PEDDLER_DELETE_UNSELLABLES"
local MIN_WIDTH              = 400
local MAX_WIDTH_CAP          = 520
local SIDE_PADDING           = 80
local BASE_TEXT_PADDING      = 40
local EXTRA_TEXT_PADDING     = 80
local MAX_TEXT_CHARS         = 900
local MAX_OVERLAYS           = 60
local LINE_HEIGHT_FALLBACK   = 14
local BUTTON_Y_OFFSET        = 21
local OVERLAY_Y_ADJUST       = 3       -- fine-tuned earlier
local TOOLTIP_CURSOR_YOFF    = 5       -- bottom-left anchor vertical offset

--------------------------------------------------
-- Unsellable check
--------------------------------------------------
local function IsUnsellable(itemID)
	local _,_,_,_,_,_,_,_,_,_,price = GetItemInfo(itemID)
	return (price == 0 or price == nil)
end
F.IsUnsellable = IsUnsellable

--------------------------------------------------
-- Flag utilities
--------------------------------------------------
function F.ToggleDeleteFlag(itemID, unique)
	if not ItemsToDelete then ItemsToDelete = {} end
	if ItemsToDelete[unique] then
		ItemsToDelete[unique] = nil
	else
		ItemsToDelete[unique] = 1
	end
end

function F.Reset()
	if not ItemsToDelete then ItemsToDelete = {} end
	local c=0 for _ in pairs(ItemsToDelete) do c=c+1 end
	for k in pairs(ItemsToDelete) do ItemsToDelete[k]=nil end
	print("|cff33ff99Peddler:|r Reset "..c.." unsellable deletion flag"..(c==1 and "" or "s")..".")
	if Peddler.MarkWares then Peddler.MarkWares() end
end

--------------------------------------------------
-- Collect flagged
--------------------------------------------------
local function ListFlagged()
	if not ItemsToDelete then ItemsToDelete = {} end
	local list = {}
	for bag=0,4 do
		local slots = GetContainerNumSlots(bag)
		for slot=1,slots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local itemID, unique = Peddler.ParseItemLink(link)
				if itemID and unique and ItemsToDelete[unique] and IsUnsellable(itemID) then
					local _, count = GetContainerItemInfo(bag, slot)
					list[#list+1] = { link=link, itemID=itemID, count=count or 1 }
				end
			end
		end
	end
	return list
end
F.ListFlagged = ListFlagged

--------------------------------------------------
-- Delete flagged (add logging with reason = "deleted")
--------------------------------------------------
local function DeleteFlagged(flagged)
	if #flagged == 0 then
		print("|cff33ff99Peddler:|r No flagged unsellable items.")
		return
	end
	for _, entry in ipairs(flagged) do
		local remain = entry.count
		for bag=0,4 do
			if remain <= 0 then break end
			local slots=GetContainerNumSlots(bag)
			for slot=1,slots do
				local link = GetContainerItemLink(bag, slot)
				if link == entry.link then
					PickupContainerItem(bag, slot)
					DeleteCursorItem()
					remain = remain - 1
				end
				if remain <= 0 then break end
			end
		end
		-- Log one entry for the stack (price zero)
		if Peddler.LogSale then
			Peddler.LogSale(entry.itemID, entry.link, entry.count or 1, 0, "deleted")
		end
	end
	print("|cff33ff99Peddler:|r Deleted "..#flagged.." unsellable flagged item(s).")
	if Peddler.MarkWares then Peddler.MarkWares() end
end

--------------------------------------------------
-- Build popup text & overlay meta
--------------------------------------------------
local function BuildPopupText(flagged)
	local overlay = {}
	local lines = {
		"The following flagged items will be |cffff5555PERMANENTLY DELETED|r:",
		""
	}
	local overflow = {}
	if #flagged == 0 then
		lines[#lines+1] = "(None)"
	else
		local used = 0
		for i, entry in ipairs(flagged) do
			local line = entry.link
			if entry.count and entry.count > 1 then
				line = line .. " x" .. entry.count
			end
			local future = used + line:len() + 1
			if future > MAX_TEXT_CHARS then
				for j=i,#flagged do
					local e=flagged[j]
					local show=e.link
					if e.count and e.count>1 then show=show.." x"..e.count end
					overflow[#overflow+1] = show
				end
				lines[#lines+1] = "... (+"..(#flagged - i + 1).." more)"
				break
			end
			lines[#lines+1] = line
			overlay[#overlay+1] = { text=line, link=entry.link, ellipsis=false }
			used = future
		end
	end
	lines[#lines+1] = ""
	lines[#lines+1] = "This cannot be undone. Proceed?"

	if #overflow > 0 then
		overlay[#overlay+1] = {
			text = "... (+"..#overflow.." more)",
			ellipsis = true,
			overflow = overflow,
		}
	end

	return table.concat(lines, "\n"), overlay
end

--------------------------------------------------
-- Tooltip anchor helper
--------------------------------------------------
local function ShowAnchoredTooltip(owner, buildFunc)
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale() or 1
	x = x / scale
	y = y / scale
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y + TOOLTIP_CURSOR_YOFF)
	buildFunc()
	GameTooltip:Show()
end

--------------------------------------------------
-- Overlay pool
--------------------------------------------------
local function EnsureOverlayPool(popup)
	if popup.PeddlerOverlayButtons then return end
	popup.PeddlerOverlayButtons = {}
	for i=1,MAX_OVERLAYS do
		local b = CreateFrame("Button", nil, popup)
		b:Hide()
		b:SetFrameLevel(popup:GetFrameLevel()+5)
		b:SetScript("OnEnter", function(btn)
			if not btn.meta then return end
			if btn.meta.ellipsis then
				ShowAnchoredTooltip(btn, function()
					GameTooltip:AddLine("Additional Items",1,1,1)
					GameTooltip:AddLine(" ")
					for _, line in ipairs(btn.meta.overflow or {}) do
						GameTooltip:AddLine(line)
					end
				end)
			elseif btn.meta.link then
				ShowAnchoredTooltip(btn, function()
					GameTooltip:SetHyperlink(btn.meta.link)
				end)
			end
		end)
		b:SetScript("OnLeave", function()
			if GameTooltip:IsShown() then GameTooltip:Hide() end
		end)
		b:SetScript("OnClick", function(btn)
			if btn.meta and btn.meta.link and not btn.meta.ellipsis then
				if IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
					ChatEdit_InsertLink(btn.meta.link)
				end
			end
		end)
		popup.PeddlerOverlayButtons[i] = b
	end
end

--------------------------------------------------
-- Layout overlays
--------------------------------------------------
local measureFS
local function LayoutOverlays(popup, overlayLines)
	if not overlayLines then return end
	EnsureOverlayPool(popup)
	if not measureFS then
		measureFS = popup:CreateFontString(nil,"OVERLAY","GameFontHighlight")
		measureFS:Hide()
	end
	local textFS = popup.text
	measureFS:SetFontObject(textFS:GetFontObject())

	local full = textFS:GetText() or ""
	local rawLines = {}
	for line in full:gmatch("([^\n]+)") do rawLines[#rawLines+1] = line end

	local textWidth = textFS:GetWidth()
	local heights, widths, yOffsets = {}, {}, {}
	local cumulative = 0
	for i,line in ipairs(rawLines) do
		measureFS:SetWidth(textWidth)
		measureFS:SetText(line)
		local h = measureFS:GetStringHeight()
		if h == 0 then h = LINE_HEIGHT_FALLBACK end
		local w = measureFS:GetStringWidth()
		heights[i] = h
		widths[i]  = w
		yOffsets[i] = cumulative
		cumulative = cumulative + h
	end

	local _,_,_,_, baseY = textFS:GetPoint(1)
	baseY = baseY or -16

	local matched = {}
	local startIdx = 1
	for _, meta in ipairs(overlayLines) do
		for idx=startIdx,#rawLines do
			if rawLines[idx] == meta.text then
				matched[#matched+1] = { lineIndex=idx, meta=meta }
				startIdx = idx + 1
				break
			end
		end
	end

	local used=0
	for _, m in ipairs(matched) do
		used = used + 1
		local btn = popup.PeddlerOverlayButtons[used]
		if not btn then break end
		local i = m.lineIndex
		local lineH = heights[i] or LINE_HEIGHT_FALLBACK
		local lineW = widths[i] or 40
		if lineW < 16 then lineW = 16 end
		local trimmedH = math.max(8, lineH)
		local leftOffset = (textWidth - lineW)/2
		local topOffset  = baseY - yOffsets[i] + OVERLAY_Y_ADJUST

		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", textFS, "TOPLEFT", leftOffset, topOffset)
		btn:SetSize(lineW, trimmedH)
		btn.meta = m.meta
		btn:Show()
	end
	for i=used+1,#popup.PeddlerOverlayButtons do
		local b = popup.PeddlerOverlayButtons[i]
		b:Hide()
		b.meta=nil
	end
end

--------------------------------------------------
-- Popup definition
--------------------------------------------------
StaticPopupDialogs[POPUP_KEY] = {
	text = "",
	button1 = YES,
	button2 = NO,
	timeout = 0,
	hideOnEscape = true,
	whileDead = true,

	OnAccept = function(self, data)
		DeleteFlagged(data.flagged or {})
	end,

	OnHide = function(self)
		if self._peddlerOrig then
			self.text:ClearAllPoints()
			for _, pt in ipairs(self._peddlerOrig.points or {}) do
				self.text:SetPoint(unpack(pt))
			end
			self.text:SetJustifyH(self._peddlerOrig.justify or "CENTER")
			self.text:SetWidth(self._peddlerOrig.textWidth)
			self:SetWidth(self._peddlerOrig.width)
			self.maxWidth = self._peddlerOrig.maxWidth
			self._peddlerOrig = nil
		end
		if self.PeddlerOverlayButtons then
			for _, b in ipairs(self.PeddlerOverlayButtons) do b:Hide(); b.meta=nil end
		end
		if GameTooltip:IsShown() then GameTooltip:Hide() end
	end,

	OnShow = function(self, data)
		local flagged = data.flagged or {}
		local text, overlayLines = BuildPopupText(flagged)

		local orig = {
			width     = self:GetWidth(),
			maxWidth  = self.maxWidth,
			textWidth = self.text:GetWidth(),
			justify   = self.text:GetJustifyH(),
			points    = {}
		}
		for i=1,self.text:GetNumPoints() do
			orig.points[#orig.points+1] = { self.text:GetPoint(i) }
		end
		self._peddlerOrig = orig

		self.text:ClearAllPoints()
		self.text:SetPoint("TOP", self, "TOP", 0, -16)
		self.text:SetJustifyH("CENTER")
		self.text:SetText(text)

		local longest = 0
		local meas = measureFS or self:CreateFontString(nil,"OVERLAY","GameFontHighlight")
		measureFS = meas
		meas:SetFontObject(self.text:GetFontObject())
		for _, meta in ipairs(overlayLines) do
			if not meta.ellipsis then
				meas:SetText(meta.text)
				local w = meas:GetStringWidth()
				if w > longest then longest = w end
			end
		end
		local desired = math.max(MIN_WIDTH, math.min(MAX_WIDTH_CAP, longest + SIDE_PADDING))
		self:SetWidth(desired)
		self.maxWidth = desired
		local innerPad = BASE_TEXT_PADDING + EXTRA_TEXT_PADDING
		self.text:SetWidth(desired - innerPad)

		if StaticPopup_Resize then
			StaticPopup_Resize(self, self.which)
		end

		self.button1:ClearAllPoints()
		self.button2:ClearAllPoints()
		self.button1:SetPoint("BOTTOMRIGHT", self, "BOTTOM", -6, BUTTON_Y_OFFSET)
		self.button2:SetPoint("BOTTOMLEFT",  self, "BOTTOM",  6, BUTTON_Y_OFFSET)

		Peddler.RunAfter(0.05, function()
			LayoutOverlays(self, overlayLines)
		end)
	end,
}

--------------------------------------------------
-- Public trigger
--------------------------------------------------
function F.MaybeShowPopup()
	if not DeleteUnsellablesEnabled then return end
	local flagged = ListFlagged()
	if #flagged == 0 then return end
	StaticPopup_Show(POPUP_KEY, nil, nil, { flagged = flagged })
end