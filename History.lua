local addonName, Peddler = ...
_G.Peddler = _G.Peddler or Peddler -- keep global for debugging

--------------------------------------------------
-- User-configurable
--------------------------------------------------
local NEWEST_AT_TOP = false   -- Set false for chronological ascending (auto-scroll bottom)

--------------------------------------------------
-- Layout (frame +50 width, price +50 from earlier)
--------------------------------------------------
local DEFAULT_FRAME_WIDTH   = 730
local DEFAULT_FRAME_HEIGHT  = 480

local COL_TIME_WIDTH   = 100
local COL_QTY_WIDTH    = 50
local COL_PRICE_WIDTH  = 140
local COL_REASON_WIDTH = 90

local HEADER_HEIGHT         = 20
local ROW_HEIGHT            = 28
local ROW_SPACING           = 2
local INNER_PAD             = 4
local PRICE_CELL_PADDING    = 5

local LEFT_SCROLL_X         = 16
local RIGHT_SCROLL_X        = 30
local TOP_SCROLL_Y          = -60
local BOTTOM_SCROLL_Y       = 92
local MIN_ITEM_COL_WIDTH    = 150
local MIN_FRAME_WIDTH       = 610
local MIN_FRAME_HEIGHT      = 360
local EXTRA_VISIBLE_ROWS    = 1
local SEARCH_BOX_WIDTH      = 240

local MANUAL_REASON_COLOR      = "cffdddddd"
local MANUAL_SELL_STAR_COLOR   = "cffff0202"
local MANUAL_SELL_STAR_SYMBOL  = "*"
local DELETED_REASON_COLOR     = "cffff3030"
local ROW_TINT_DELETED         = {0.65, 0.10, 0.10}

--------------------------------------------------
-- State
--------------------------------------------------
local rows = {}
local visibleRows = 0
local fauxScrollFrame
local contentFrame
local headerBG
local headers = {}
local separators = {}
local itemColumnWidth = 0

local currentSortKey  = "time"
local currentSortAsc  = not NEWEST_AT_TOP
local currentReasonFilter = "ALL"
local searchTerm = ""
local filteredIndex = {}
local pendingAutoScroll = false

-- Ensure history frame state always exists (added for robustness after reset-all)
function Peddler.EnsureHistoryState()
	if not PeddlerHistoryFrameState or type(PeddlerHistoryFrameState) ~= "table" then
		PeddlerHistoryFrameState = {
			width  = DEFAULT_FRAME_WIDTH,
			height = DEFAULT_FRAME_HEIGHT,
		}
	end
end
Peddler.EnsureHistoryState()

if not PeddlerHistorySessionNet then PeddlerHistorySessionNet = 0 end

--------------------------------------------------
-- Reason metadata (updated descriptions)
--------------------------------------------------
local reasonMeta = {
	manual     = { label="manual",     color=MANUAL_REASON_COLOR, desc="Manually flagged" },
	manualsell = { label="manual",     color=MANUAL_REASON_COLOR, desc="Sold by player (not Peddler)", specialManualStar=true },
	grey       = { label="grey",       color="cff9d9d9d", desc="Poor quality (grey)" },
	common     = { label="common",     color="cffffffff", desc="Common quality (white)" },
	uncommon   = { label="uncommon",   color="cff1eff00", desc="Uncommon quality (green)" },
	rare       = { label="rare",       color="cff0070dd", desc="Rare quality (blue)" },
	epic       = { label="epic",       color="cffa335ee", desc="Epic quality (purple)" },
	class      = { label="class",      color="cffff7f00", desc="Unwanted for your class" },
	auto       = { label="auto",       color="cffaaaaaa", desc="Automatically flagged" },
	buyback    = { label="buyback",    color="cffffcc00", desc="Bought back by player" },
	deleted    = { label="deleted",    color=DELETED_REASON_COLOR, desc="Deleted permanently" },
}

local RARITY_COLOR = {
	grey="|cff9d9d9d", common="|cffffffff", uncommon="|cff1eff00",
	rare="|cff0070dd", epic="|cffa335ee"
}
local function rq(word,key) return "Quality: "..(RARITY_COLOR[key] or "|cffffffff")..word.."|r" end

-- 4 groups layout
local FILTER_OPTIONS = {
	{ text="All", value="ALL", group=1 },

	{ text="Manual (flagged)", value="manual", group=2 },
	{ text="Class Unwanted", value="class", group=2 },
	{ text="Auto (other)", value="auto", group=2 },

	{ text=rq("Grey","grey"), value="grey", group=3 },
	{ text=rq("Common","common"), value="common", group=3 },
	{ text=rq("Uncommon","uncommon"), value="uncommon", group=3 },
	{ text=rq("Rare","rare"), value="rare", group=3 },
	{ text=rq("Epic","epic"), value="epic", group=3 },

	{ text="Manual* (sold by user)", value="manualsell", group=4 },
	{ text="Buyback", value="buyback", group=4 },
	{ text="Deleted", value="deleted", group=4 },
}

local QUALITY_REASON = { grey=true, common=true, uncommon=true, rare=true, epic=true }
local QUALITY_TOKEN = { [0]="grey",[1]="common",[2]="uncommon",[3]="rare",[4]="epic" }

--------------------------------------------------
-- Row tints
--------------------------------------------------
local ROW_TINTS = {
	manual     = {0.70, 0.70, 0.70},
	manualsell = {0.70, 0.60, 0.60},
	grey       = {0.40, 0.40, 0.40},
	common     = {0.55, 0.55, 0.55},
	uncommon   = {0.25, 0.50, 0.20},
	rare       = {0.15, 0.35, 0.60},
	epic       = {0.45, 0.20, 0.60},
	class      = {0.60, 0.35, 0.10},
	auto       = {0.30, 0.30, 0.30},
	buyback    = {0.70, 0.55, 0.15},
	deleted    = ROW_TINT_DELETED,
}

--------------------------------------------------
-- Helpers
--------------------------------------------------
local function SafeSetTexColor(tex,r,g,b,a)
	if not tex then return end
	if tex.SetColorTexture then tex:SetColorTexture(r,g,b,a) else tex:SetTexture(r,g,b,a) end
end
local function ApplyRowTint(row, reason, idx)
	local tint = ROW_TINTS[reason] or ROW_TINTS.auto
	local alpha = (idx % 2 == 0) and 0.20 or 0.12
	SafeSetTexColor(row.bg, tint[1], tint[2], tint[3], alpha)
end
local function EnsureHistory()
	if not PeddlerSalesHistory then PeddlerSalesHistory = {} end
end
local function EnsureGoldBaseline()
	if not PeddlerSessionGoldBaseline and GetMoney then
		PeddlerSessionGoldBaseline = GetMoney()
	end
end

--------------------------------------------------
-- Currency formatting (larger coin icons)
--------------------------------------------------
local ICON_SCALE = 1.15
local BASE_ICON_SIZE = 12
local ICON_SIZE = math.floor(BASE_ICON_SIZE * ICON_SCALE + 0.5)
local function CoinTex(path)
	return "|TInterface\\MoneyFrame\\"..path..":"..ICON_SIZE..":"..ICON_SIZE..":0:0:64:64:5:59:5:59|t"
end
local GOLD_ICON   = CoinTex("UI-GoldIcon")
local SILVER_ICON = CoinTex("UI-SilverIcon")
local COPPER_ICON = CoinTex("UI-CopperIcon")

local function CoinsTex(amount)
	amount = amount or 0
	local g = math.floor(amount / 10000)
	local s = math.floor((amount % 10000) / 100)
	local c = amount % 100
	local str=""
	if g>0 then str = str .. ("|cffffffff"..g.."|r "..GOLD_ICON.." ") end
	if s>0 or g>0 then str = str .. ("|cffffffff"..s.."|r "..SILVER_ICON.." ") end
	str = str .. ("|cffffffff"..c.."|r "..COPPER_ICON)
	return str
end

--------------------------------------------------
-- Export (session display updater to use outside)
--------------------------------------------------
local function UpdateSessionDisplay()
	if not (PeddlerHistoryFooterNetFrame and GetMoney and PeddlerSessionGoldBaseline) then return end
	local diff = GetMoney() - PeddlerSessionGoldBaseline
	local abs = math.abs(diff)
	local sign = diff >=0 and "|cff2aff2a+|r" or "|cffff2a2a-|r"
	PeddlerHistoryFooterNetFrame.text:SetText("|cffffd100Session:|r "..sign.." "..CoinsTex(abs))
end
Peddler.UpdateSessionDisplay = UpdateSessionDisplay

--------------------------------------------------
-- Logging
--------------------------------------------------
function Peddler.LogSale(itemID, link, amount, priceCopper, reason)
	EnsureHistory()
	table.insert(PeddlerSalesHistory, {
		time   = time(),
		itemID = itemID,
		link   = link,
		amount = amount or 1,
		price  = priceCopper or 0,
		reason = reason or "auto",
	})
	if #PeddlerSalesHistory > 500 then
		table.remove(PeddlerSalesHistory,1)
	end
	if PeddlerHistoryFrame and PeddlerHistoryFrame:IsShown() then
		Peddler.UpdateHistoryUI()
	end
	UpdateSessionDisplay()
end

--------------------------------------------------
-- Formatting
--------------------------------------------------
local function ShortTime(epoch)
	if date("%Y-%m-%d", epoch) == date("%Y-%m-%d") then
		return date("%H:%M", epoch)
	else
		return date("%Y-%m-%d", epoch)
	end
end
local function FullTime(epoch) return date("%Y-%m-%d %H:%M:%S", epoch) end
local function BuildReasonDisplay(meta)
	if not meta then return "|cffffffff?|" end
	if meta.specialManualStar then
		return "|"..meta.color..meta.label.."|r|"..MANUAL_SELL_STAR_COLOR..MANUAL_SELL_STAR_SYMBOL.."|r"
	end
	return "|"..meta.color..meta.label.."|r"
end

--------------------------------------------------
-- UI Factories
--------------------------------------------------
local function CreateCell(parent, width, justifyH)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetHeight(ROW_HEIGHT); holder:SetWidth(width)
	local fs = holder:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", holder, "TOPLEFT", INNER_PAD, 0)
	fs:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -INNER_PAD, 0)
	fs:SetJustifyV("MIDDLE")
	fs:SetJustifyH(justifyH or "LEFT")
	holder.text = fs
	return holder
end

local function CreateHeader(parent, width, justifyH, label, sortKey)
	local holder = CreateFrame("Button", nil, parent)
	holder:SetHeight(HEADER_HEIGHT); holder:SetWidth(width); holder.sortKey = sortKey
	local fs = holder:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
	fs:SetPoint("TOPLEFT", holder, "TOPLEFT", INNER_PAD, -2)
	fs:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -INNER_PAD, 2)
	fs:SetJustifyV("MIDDLE"); fs:SetJustifyH(justifyH or "CENTER")
	fs:SetText(label or ""); fs:SetTextColor(1,0.82,0)
	holder.text = fs
	holder:SetScript("OnClick", function(self)
		if currentSortKey == self.sortKey then
			currentSortAsc = not currentSortAsc
		else
			currentSortKey = self.sortKey
			if self.sortKey == "time" then
				currentSortAsc = not NEWEST_AT_TOP
			else
				currentSortAsc = true
			end
		end
		if currentSortKey == "time" and not NEWEST_AT_TOP and currentSortAsc then
			pendingAutoScroll = true
		end
		Peddler.UpdateHistoryUI()
	end)
	return holder
end

--------------------------------------------------
-- Layout
--------------------------------------------------
local function ComputeItemColumnWidth(frame)
	local innerWidth = frame:GetWidth() - LEFT_SCROLL_X - RIGHT_SCROLL_X
	local fixed = COL_TIME_WIDTH + COL_QTY_WIDTH + COL_PRICE_WIDTH + COL_REASON_WIDTH
	local available = innerWidth - fixed
	itemColumnWidth = math.max(MIN_ITEM_COL_WIDTH, available)
end

local function ComputeVisibleRows(frame)
	local innerHeight = frame:GetHeight() - (math.abs(TOP_SCROLL_Y) + BOTTOM_SCROLL_Y)
	local rowsArea = innerHeight - HEADER_HEIGHT - 8 - 24
	local per = ROW_HEIGHT + ROW_SPACING
	local count = math.max(4, math.floor(rowsArea / per))
	return count + EXTRA_VISIBLE_ROWS
end

local function EnsureRowCount(count)
	if count == visibleRows then return end
	for i=visibleRows+1,count do
		local row = CreateFrame("Button", nil, contentFrame)
		row:SetHeight(ROW_HEIGHT)
		row.bg = row:CreateTexture(nil,"BACKGROUND")
		row.bg:SetAllPoints()
		SafeSetTexColor(row.bg,0,0,0,0.06)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		local hl=row:GetHighlightTexture()
		if hl then hl:SetAllPoints(); hl:SetAlpha(0.18) end

		row.timeCell   = CreateCell(row, COL_TIME_WIDTH, "CENTER")
		row.itemCell   = CreateCell(row, itemColumnWidth, "LEFT")
		row.qtyCell    = CreateCell(row, COL_QTY_WIDTH, "CENTER")
		row.priceCell  = CreateCell(row, COL_PRICE_WIDTH - PRICE_CELL_PADDING*2, "RIGHT")
		row.reasonCell = CreateCell(row, COL_REASON_WIDTH, "LEFT")

		row.timeCell:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.itemCell:SetPoint("LEFT", row.timeCell, "RIGHT", 0, 0)
		row.qtyCell:SetPoint("LEFT", row.itemCell, "RIGHT", 0, 0)
		row.priceCell:SetPoint("LEFT", row.qtyCell, "RIGHT", PRICE_CELL_PADDING, 0)
		row.reasonCell:SetPoint("LEFT", row.priceCell, "RIGHT", PRICE_CELL_PADDING, 0)

		row:SetScript("OnEnter", function(self)
			if not self.link then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.link)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cffbbbbbbSold:|r "..FullTime(self._fullTime or time()))
			if self.reasonCode then
				local meta = reasonMeta[self.reasonCode]
				if meta then
					GameTooltip:AddLine("|"..meta.color.."Reason:|r "..(meta.desc or meta.label))
				end
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnMouseDown", function(self)
			if self.link and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
				ChatEdit_InsertLink(self.link)
			end
		end)

		rows[i]=row
	end
	if count < visibleRows then
		for i=count+1,visibleRows do if rows[i] then rows[i]:Hide() end end
	end
	visibleRows = count

	local yStart = -HEADER_HEIGHT - 6
	for i=1,visibleRows do
		local row=rows[i]
		row:ClearAllPoints()
		if i==1 then
			row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, yStart)
		else
			row:SetPoint("TOPLEFT", rows[i-1], "BOTTOMLEFT", 0, -ROW_SPACING)
		end
		row:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
		row:Show()
	end
end

local function LayoutHeaders()
	if not headers.order then return end
	local x=0
	for _,h in ipairs(headers.order) do
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, -2)
		x = x + h:GetWidth()
	end
	headerBG:ClearAllPoints()
	headerBG:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0,0)
	headerBG:SetPoint("TOPRIGHT", contentFrame, "TOPLEFT", x,0)

	local colPositions = {
		COL_TIME_WIDTH,
		COL_TIME_WIDTH + itemColumnWidth,
		COL_TIME_WIDTH + itemColumnWidth + COL_QTY_WIDTH,
		COL_TIME_WIDTH + itemColumnWidth + COL_QTY_WIDTH + COL_PRICE_WIDTH,
	}
	for i,sep in ipairs(separators) do
		sep:ClearAllPoints()
		sep:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", colPositions[i], -2)
		sep:SetPoint("BOTTOMLEFT", contentFrame, "TOPLEFT", colPositions[i], -HEADER_HEIGHT+2)
		sep:Show()
	end
end

local function UpdateColumnWidths()
	headers.item:SetWidth(itemColumnWidth)
	for i=1,visibleRows do
		local row=rows[i]
		if row and row.itemCell then row.itemCell:SetWidth(itemColumnWidth) end
	end
	LayoutHeaders()
end

--------------------------------------------------
-- Filtering / search
--------------------------------------------------
local function LinkMatchesSearch(entry)
	if searchTerm == "" then return true end
	local link = entry.link or ""
	local inside = link:match("%[(.-)%]") or link
	inside = inside:lower()
	return inside:find(searchTerm,1,true) ~= nil
end

local function ItemQualityMatches(entry, desiredReason)
	if not QUALITY_REASON[desiredReason] then return false end
	local itemID = entry.itemID
	if not itemID and entry.link then
		local id = tonumber(entry.link:match("|Hitem:(%d+):"))
		if id then itemID = id end
	end
	if not itemID then return false end
	local _,_,q = GetItemInfo(itemID)
	if not q then return false end
	return QUALITY_TOKEN[q] == desiredReason
end

local function PassesFilter(entry)
	if not LinkMatchesSearch(entry) then return false end
	if currentReasonFilter == "ALL" then return true end

	if QUALITY_REASON[currentReasonFilter] then
		if entry.reason == currentReasonFilter then return true end
		if ItemQualityMatches(entry, currentReasonFilter) then return true end
		return false
	end

	return entry.reason == currentReasonFilter
end

local function BuildFilteredIndex()
	EnsureHistory()
	for i=#filteredIndex,1,-1 do filteredIndex[i]=nil end
	for i=1,#PeddlerSalesHistory do
		local e = PeddlerSalesHistory[i]
		if PassesFilter(e) then
			filteredIndex[#filteredIndex+1]=i
		end
	end
end

--------------------------------------------------
-- Sorting
--------------------------------------------------
local function SortFiltered()
	table.sort(filteredIndex, function(a,b)
		local ea = PeddlerSalesHistory[a]
		local eb = PeddlerSalesHistory[b]
		if not ea then return false end
		if not eb then return true end
		local va,vb
		if currentSortKey=="time" then
			va,vb = ea.time or 0, eb.time or 0
		elseif currentSortKey=="item" then
			local na=(ea.link or ""):match("%[(.+)%]") or (ea.link or "")
			local nb=(eb.link or ""):match("%[(.+)%]") or (eb.link or "")
			va,vb=na,nb
		elseif currentSortKey=="qty" then
			va,vb = ea.amount or 0, eb.amount or 0
		elseif currentSortKey=="price" then
			va,vb = ea.price or 0, eb.price or 0
		elseif currentSortKey=="reason" then
			va,vb = ea.reason or "", eb.reason or ""
		else
			va,vb = 0,0
		end
		if va==vb then return a<b end
		if currentSortAsc then return va<vb else return va>vb end
	end)
end

--------------------------------------------------
-- Update rows
--------------------------------------------------
local function UpdateRows()
	BuildFilteredIndex()
	SortFiltered()

	local total = #filteredIndex
	FauxScrollFrame_Update(fauxScrollFrame, total, visibleRows, ROW_HEIGHT + ROW_SPACING)
	local offset = FauxScrollFrame_GetOffset(fauxScrollFrame)

	for i=1,visibleRows do
		local row = rows[i]; if not row then break end
		local entryIndex = filteredIndex[offset + i]
		if entryIndex then
			local e = PeddlerSalesHistory[entryIndex]
			local t = e.time or time()
			row.link = e.link
			row._fullTime = t
			row.reasonCode = e.reason
			row.timeCell.text:SetText(ShortTime(t))
			row.itemCell.text:SetText(e.link or ("item:"..(e.itemID or "?")))
			row.qtyCell.text:SetText(tostring(e.amount or 1))
			local meta = reasonMeta[e.reason] or reasonMeta.auto
			row.reasonCell.text:SetText(BuildReasonDisplay(meta))
			local priceStr = CoinsTex(e.price or 0)
			if e.reason=="buyback" then
				row.priceCell.text:SetText("|cffff5555-"..priceStr.."|r")
			else
				row.priceCell.text:SetText(priceStr)
			end
			ApplyRowTint(row, e.reason, i)
			row:Show()
		else
			row:Hide()
			row.link=nil
			row.reasonCode=nil
		end
	end

	UpdateSessionDisplay()

	if pendingAutoScroll then
		pendingAutoScroll=false
		local maxOffset = math.max(0, total - visibleRows)
		FauxScrollFrame_SetOffset(fauxScrollFrame, maxOffset)
		FauxScrollFrame_Update(fauxScrollFrame, total, visibleRows, ROW_HEIGHT + ROW_SPACING)
		offset = FauxScrollFrame_GetOffset(fauxScrollFrame)
		for i=1,visibleRows do
			local row=rows[i]; if not row then break end
			local idx=filteredIndex[offset + i]
			if idx then
				local e=PeddlerSalesHistory[idx]
				local t=e.time or time()
				row.link=e.link
				row._fullTime=t
				row.reasonCode=e.reason
				row.timeCell.text:SetText(ShortTime(t))
				row.itemCell.text:SetText(e.link or ("item:"..(e.itemID or "?")))
				row.qtyCell.text:SetText(tostring(e.amount or 1))
				local meta=reasonMeta[e.reason] or reasonMeta.auto
				row.reasonCell.text:SetText(BuildReasonDisplay(meta))
				local priceStr = CoinsTex(e.price or 0)
				if e.reason=="buyback" then
					row.priceCell.text:SetText("|cffff5555-"..priceStr.."|r")
				else
					row.priceCell.text:SetText(priceStr)
				end
				ApplyRowTint(row, e.reason, i)
				row:Show()
			else
				row:Hide()
			end
		end
		UpdateSessionDisplay()
	end
end

function Peddler.UpdateHistoryUI()
	if not PeddlerHistoryFrame then return end
	UpdateRows()
end

--------------------------------------------------
-- Dropdown
--------------------------------------------------
local function InitializeFilterDropdown(self, level)
	if not level then return end
	for group=1,4 do
		for _,opt in ipairs(FILTER_OPTIONS) do
			if opt.group == group then
				local info = UIDropDownMenu_CreateInfo()
				info.text=opt.text
				info.value=opt.value
				info.func=function(btn)
					currentReasonFilter=btn.value
					UIDropDownMenu_SetSelectedValue(self, btn.value)
					if currentSortKey=="time" and not NEWEST_AT_TOP and currentSortAsc then
						pendingAutoScroll=true
					end
					Peddler.UpdateHistoryUI()
				end
				info.checked=(currentReasonFilter==opt.value)
				UIDropDownMenu_AddButton(info, level)
			end
		end
		if group < 4 then
			local sep=UIDropDownMenu_CreateInfo()
			sep.text=" "
			sep.disabled=true
			UIDropDownMenu_AddButton(sep, level)
		end
	end
end

--------------------------------------------------
-- Reset
--------------------------------------------------
function Peddler.ResetHistoryWindow()
	Peddler.EnsureHistoryState()
	currentSortKey = "time"
	currentSortAsc = not NEWEST_AT_TOP
	currentReasonFilter = "ALL"
	searchTerm = ""
	PeddlerHistoryFrameState.width  = DEFAULT_FRAME_WIDTH
	PeddlerHistoryFrameState.height = DEFAULT_FRAME_HEIGHT
	if PeddlerHistoryFrame then
		PeddlerHistoryFrame:ClearAllPoints()
		PeddlerHistoryFrame:SetSize(DEFAULT_FRAME_WIDTH, DEFAULT_FRAME_HEIGHT)
		PeddlerHistoryFrame:SetPoint("CENTER")
		Peddler.UpdateHistoryUI()
	else
		print("|cff33ff99Peddler:|r History reset (will apply on open).")
	end
end

--------------------------------------------------
-- Geometry
--------------------------------------------------
local function EnsureHistoryFrameGeometry()
	if not PeddlerHistoryFrame then return end
	local f=PeddlerHistoryFrame
	if f:GetNumPoints()==0 then
		f:ClearAllPoints()
		f:SetPoint("CENTER")
	end
	if f:GetWidth()<50 or f:GetHeight()<50 then
		f:SetSize(DEFAULT_FRAME_WIDTH, DEFAULT_FRAME_HEIGHT)
	end
	f:SetAlpha(1); f:SetScale(1)
end

--------------------------------------------------
-- Unfocus catcher
--------------------------------------------------
local function AttachUnfocusCatcher(searchBox)
	local catcher = _G.PeddlerHistorySearchUnfocusFrame
	if not catcher then
		catcher = CreateFrame("Button","PeddlerHistorySearchUnfocusFrame",UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:EnableMouse(true)
		catcher:SetFrameStrata("FULLSCREEN_DIALOG")
		catcher:SetFrameLevel(1)
		catcher:Hide()
	end
	catcher:SetScript("OnMouseDown", function()
		if searchBox:HasFocus() then searchBox:ClearFocus() end
		catcher:Hide()
	end)
	searchBox:HookScript("OnEditFocusGained", function() catcher:Show() end)
	searchBox:HookScript("OnEditFocusLost",  function() catcher:Hide() end)
end

--------------------------------------------------
-- Create frame
--------------------------------------------------
local function CreateHistoryFrame()
	Peddler.EnsureHistoryState()
	if PeddlerHistoryFrame then return end

	local frame = CreateFrame("Frame","PeddlerHistoryFrame",UIParent,"UIPanelDialogTemplate")
	frame:SetResizable(true)
	frame:SetMinResize(MIN_FRAME_WIDTH, MIN_FRAME_HEIGHT)
	frame:SetSize(
		math.max(MIN_FRAME_WIDTH,  PeddlerHistoryFrameState.width  or DEFAULT_FRAME_WIDTH),
		math.max(MIN_FRAME_HEIGHT, PeddlerHistoryFrameState.height or DEFAULT_FRAME_HEIGHT)
	)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetClampedToScreen(true)

	-- Resizer
	local resizer = CreateFrame("Button", nil, frame)
	resizer:SetSize(16,16)
	resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
	resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizer:SetScript("OnMouseDown", function(self,btn)
		if btn=="LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
	end)
	resizer:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		PeddlerHistoryFrameState.width  = frame:GetWidth()
		PeddlerHistoryFrameState.height = frame:GetHeight()
		ComputeItemColumnWidth(frame)
		local needed=ComputeVisibleRows(frame)
		EnsureRowCount(needed)
		UpdateColumnWidths()
		Peddler.UpdateHistoryUI()
	end)

	frame:SetScript("OnSizeChanged", function()
		if not frame:IsShown() then return end
		PeddlerHistoryFrameState.width  = frame:GetWidth()
		PeddlerHistoryFrameState.height = frame:GetHeight()
		ComputeItemColumnWidth(frame)
		local needed=ComputeVisibleRows(frame)
		EnsureRowCount(needed)
		UpdateColumnWidths()
		Peddler.UpdateHistoryUI()
	end)
	frame:SetScript("OnShow", function(self)
		self:ClearAllPoints()
		self:SetPoint("CENTER")
		EnsureHistoryFrameGeometry()
		if currentSortKey=="time" and not NEWEST_AT_TOP and currentSortAsc then
			pendingAutoScroll = true
		end
		UpdateSessionDisplay()
	end)

	local title = frame.TitleText or frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
	title:SetPoint("TOP", frame, "TOP", 0, -8)
	title:SetText("Peddler Sales History")
	frame.TitleText = title
	tinsert(UISpecialFrames,"PeddlerHistoryFrame")

	-- Scroll
	fauxScrollFrame = CreateFrame("ScrollFrame","PeddlerHistoryFauxScrollFrame",frame,"FauxScrollFrameTemplate")
	fauxScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_SCROLL_X, TOP_SCROLL_Y)
	fauxScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -RIGHT_SCROLL_X, BOTTOM_SCROLL_Y)
	fauxScrollFrame:SetScript("OnVerticalScroll", function(self, delta)
		FauxScrollFrame_OnVerticalScroll(self, delta, ROW_HEIGHT + ROW_SPACING, Peddler.UpdateHistoryUI)
	end)

	contentFrame = CreateFrame("Frame", nil, frame)
	contentFrame:SetAllPoints(fauxScrollFrame)

	headerBG = contentFrame:CreateTexture(nil,"BACKGROUND")
	headerBG:SetTexture(0,0,0,0.45)
	headerBG:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
	headerBG:SetHeight(HEADER_HEIGHT)

	headers.time   = CreateHeader(contentFrame, COL_TIME_WIDTH,   "CENTER", "Time", "time")
	headers.item   = CreateHeader(contentFrame, 10,               "LEFT",   "Item", "item")
	headers.qty    = CreateHeader(contentFrame, COL_QTY_WIDTH,    "CENTER", "Qty",  "qty")
	headers.price  = CreateHeader(contentFrame, COL_PRICE_WIDTH,  "CENTER", "Price","price")
	headers.reason = CreateHeader(contentFrame, COL_REASON_WIDTH, "LEFT",   "Reason","reason")
	headers.order  = { headers.time, headers.item, headers.qty, headers.price, headers.reason }

	for i=1,4 do
		local tex = contentFrame:CreateTexture(nil,"BACKGROUND")
		tex:SetTexture(1,1,1,0.05)
		separators[i]=tex
	end

	-- Filter dropdown
	local filterDrop = CreateFrame("Frame","PeddlerHistoryFilterDropdown",frame,"UIDropDownMenuTemplate")
	filterDrop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -34)
	UIDropDownMenu_Initialize(filterDrop, InitializeFilterDropdown)
	UIDropDownMenu_SetWidth(filterDrop,180)
	UIDropDownMenu_SetSelectedValue(filterDrop,currentReasonFilter)

	-- Search (center)
	local searchBox = CreateFrame("EditBox","PeddlerHistorySearchBox",frame,"InputBoxTemplate")
	searchBox:SetSize(SEARCH_BOX_WIDTH,20)
	searchBox:SetAutoFocus(false)
	searchBox:SetPoint("BOTTOM", frame, "BOTTOM", 0, 56)
	local placeholder = searchBox:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
	placeholder:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
	placeholder:SetText("Search...")
	local function UpdatePlaceholder()
		if (searchBox:GetText() or "")=="" and not searchBox:HasFocus() then placeholder:Show() else placeholder:Hide() end
	end
	searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); UpdatePlaceholder() end)
	searchBox:SetScript("OnEditFocusGained", function() UpdatePlaceholder() end)
	searchBox:SetScript("OnEditFocusLost", function() UpdatePlaceholder() end)
	searchBox:SetScript("OnTextChanged", function(self)
		searchTerm = (self:GetText() or ""):lower()
		if currentSortKey=="time" and not NEWEST_AT_TOP and currentSortAsc then pendingAutoScroll=true end
		UpdatePlaceholder()
		Peddler.UpdateHistoryUI()
	end)
	UpdatePlaceholder()
	AttachUnfocusCatcher(searchBox)

	-- Reset Window (bottom-left)
	local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetBtn:SetSize(120,22)
	resetBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 20)
	resetBtn:SetText("Reset Window")
	resetBtn:SetScript("OnClick", function() Peddler.ResetHistoryWindow() end)

	-- Clear History (center bottom)
	local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clearBtn:SetSize(140,22)
	clearBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 20)
	clearBtn:SetText("Clear History")
	clearBtn:SetScript("OnClick", function()
		EnsureHistory()
		for i=#PeddlerSalesHistory,1,-1 do PeddlerSalesHistory[i]=nil end
		if currentSortKey=="time" and not NEWEST_AT_TOP then pendingAutoScroll=true end
		Peddler.UpdateHistoryUI()
	end)

	-- Session display (bottom-right)
	local netFrame = CreateFrame("Frame","PeddlerHistoryFooterNetFrame",frame)
	netFrame:SetSize(320,22)
	netFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 22)
	local netFS = netFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
	netFS:SetAllPoints()
	netFS:SetJustifyH("RIGHT")
	netFS:SetText("|cffffd100Session:|r |cff2aff2a+|r "..CoinsTex(0))
	netFrame.text = netFS
	netFrame:EnableMouse(true)
	netFrame:SetScript("OnEnter", function(self)
		EnsureGoldBaseline()
		if not GetMoney then return end
		local baseline = PeddlerSessionGoldBaseline or GetMoney()
		local now = GetMoney()
		local diff = now - baseline
		local abs = math.abs(diff)
		GameTooltip:SetOwner(self,"ANCHOR_TOP")
		GameTooltip:AddLine("Session",1,1,1)
		GameTooltip:AddLine("Baseline: "..CoinsTex(baseline),0.8,0.8,0.8)
		if diff >= 0 then
			GameTooltip:AddLine("|cff2aff2aProfit:|r "..CoinsTex(abs))
		else
			GameTooltip:AddLine("|cffff2a2aLoss:|r "..CoinsTex(abs))
		end
		GameTooltip:Show()
	end)
	netFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

	PeddlerHistoryFrame = frame
	EnsureGoldBaseline()
	EnsureHistory()
	ComputeItemColumnWidth(frame)
	local needed=ComputeVisibleRows(frame)
	EnsureRowCount(needed)
	UpdateColumnWidths()
	if currentSortKey=="time" and not NEWEST_AT_TOP and currentSortAsc then
		pendingAutoScroll = true
	end
	Peddler.UpdateHistoryUI()
end

--------------------------------------------------
-- Public show/hide/toggle
--------------------------------------------------
function Peddler.ShowHistory()
	Peddler.EnsureHistoryState()
	CreateHistoryFrame()
	if PeddlerHistoryFrame then
		PeddlerHistoryFrame:ClearAllPoints()
		PeddlerHistoryFrame:SetPoint("CENTER")
		PeddlerHistoryFrame:Show()
		if currentSortKey=="time" and not NEWEST_AT_TOP and currentSortAsc then
			pendingAutoScroll=true
		end
		Peddler.UpdateHistoryUI()
	end
end

function Peddler.HideHistory()
	if PeddlerHistoryFrame then PeddlerHistoryFrame:Hide() end
end

function Peddler.ToggleHistory()
	if PeddlerHistoryFrame and PeddlerHistoryFrame:IsShown() then
		Peddler.HideHistory()
	else
		Peddler.ShowHistory()
	end
end

--------------------------------------------------
-- Live session updates (money event)
--------------------------------------------------
local moneyWatcher = CreateFrame("Frame")
moneyWatcher:RegisterEvent("PLAYER_MONEY")
moneyWatcher:RegisterEvent("PLAYER_TRADE_MONEY")
moneyWatcher:RegisterEvent("SEND_MAIL_MONEY_CHANGED")
moneyWatcher:RegisterEvent("SEND_MAIL_COD_CHANGED")
moneyWatcher:SetScript("OnEvent", function()
	if PeddlerHistoryFooterNetFrame then
		UpdateSessionDisplay()
	end
end)

--------------------------------------------------
-- Merchant button
--------------------------------------------------
function Peddler.InitHistoryButton()
	if not MerchantFrame or PeddlerHistoryToggleButton then return end
	local btn = CreateFrame("Button","PeddlerHistoryToggleButton",MerchantFrame)
	btn:SetSize(20,20)
	if MerchantFrameCloseButton then
		btn:SetPoint("RIGHT", MerchantFrameCloseButton, "LEFT", -6, 0)
	else
		btn:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -42, -16)
	end
	local normal=btn:CreateTexture(nil,"ARTWORK")
	normal:SetAllPoints()
	normal:SetTexture("Interface\\AddOns\\Peddler\\coins")
	btn:SetNormalTexture(normal)
	local pushed=btn:CreateTexture(nil,"ARTWORK")
	pushed:SetAllPoints()
	pushed:SetTexture("Interface\\AddOns\\Peddler\\coins")
	pushed:SetVertexColor(0.8,0.8,0.8,1)
	btn:SetPushedTexture(pushed)
	local hl=btn:CreateTexture(nil,"HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")
	btn:SetHighlightTexture(hl)
	btn:SetScript("OnClick", function() Peddler.ToggleHistory() end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self,"ANCHOR_LEFT")
		GameTooltip:AddLine("Peddler Sales History",1,1,1)
		GameTooltip:AddLine("Click to toggle",0.9,0.9,0.9)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--------------------------------------------------
-- Events
--------------------------------------------------
local baselineFrame = CreateFrame("Frame")
baselineFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
baselineFrame:SetScript("OnEvent", function()
	EnsureGoldBaseline()
	UpdateSessionDisplay()
end)

--------------------------------------------------
-- Reset helper
--------------------------------------------------
function Peddler.ResetHistoryWindowPosition()
	if not PeddlerHistoryFrame then return end
	PeddlerHistoryFrame:ClearAllPoints()
	PeddlerHistoryFrame:SetPoint("CENTER")
end

--------------------------------------------------
-- Diagnostic
--------------------------------------------------
function Peddler.HistoryDiag()
	print("|cff33ff99Peddler History Diag:|r frame =", PeddlerHistoryFrame)
	if PeddlerHistoryFrame then
		print("Size:", PeddlerHistoryFrame:GetWidth(), PeddlerHistoryFrame:GetHeight(),
		      "Sort:", currentSortKey, currentSortAsc and "ASC" or "DESC",
		      "Filter:", currentReasonFilter,
		      "Search:", searchTerm,
		      "#Filtered:", #filteredIndex)
	end
end