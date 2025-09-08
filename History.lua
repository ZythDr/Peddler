-- (Patched) History view: fixes "frozen rows when no scrollbar" issue
-- Key changes:
--   * Force offset = 0 when total <= visibleRows
--   * Re-anchor rows on each UpdateHistoryUI even if no scrollbar
--   * Ensure filler background always stretches
--   * Avoid atBottomStick logic interfering when no scroll range

local addonName, Peddler = ...
_G.Peddler = _G.Peddler or Peddler

local DEFAULT_FRAME_WIDTH, DEFAULT_FRAME_HEIGHT = 730, 480
local COL_TIME_WIDTH, COL_QTY_WIDTH = 100, 50
local COL_PRICE_WIDTH, COL_REASON_WIDTH = 140, 90
local HEADER_HEIGHT, ROW_HEIGHT = 20, 28
local ROW_SPACING, INNER_PAD = 2, 4
local PRICE_CELL_PADDING = 5
local LEFT_SCROLL_X, RIGHT_SCROLL_X = 16, 30
local TOP_SCROLL_Y, BOTTOM_SCROLL_Y = -60, 92
local MIN_ITEM_COL_WIDTH = 150
local MIN_FRAME_WIDTH, MIN_FRAME_HEIGHT = 610, 360
local EXTRA_VISIBLE_ROWS = 1
local SEARCH_BOX_WIDTH = 240

local MANUAL_REASON_COLOR      = "cffdddddd"
local MANUAL_SELL_STAR_COLOR   = "cffff0202"
local MANUAL_SELL_STAR_SYMBOL  = "*"
local DELETED_REASON_COLOR     = "cffff3030"
local ROW_TINT_DELETED         = {0.65,0.10,0.10}

function Peddler.EnsureHistoryState()
	if type(PeddlerHistoryFrameState) ~= "table" then
		PeddlerHistoryFrameState = { width=DEFAULT_FRAME_WIDTH, height=DEFAULT_FRAME_HEIGHT, scrollOffset=0 }
	end
	if PeddlerHistoryFrameState.scrollOffset == nil then
		PeddlerHistoryFrameState.scrollOffset = 0
	end
end
Peddler.EnsureHistoryState()

if not PeddlerHistorySessionSalesNet then PeddlerHistorySessionSalesNet = 0 end
if not PeddlerSessionGoldBaseline and GetMoney then PeddlerSessionGoldBaseline = GetMoney() end

local reasonMeta = {
	manual     = { label="manual", color=MANUAL_REASON_COLOR, desc="Manually flagged" },
	manualsell = { label="manual", color=MANUAL_REASON_COLOR, desc="Sold manually", specialManualStar=true },
	grey       = { label="grey",   color="cff9d9d9d", desc="Poor (grey)" },
	common     = { label="common", color="cffffffff", desc="Common (white)" },
	uncommon   = { label="uncommon", color="cff1eff00", desc="Uncommon (green)" },
	rare       = { label="rare",   color="cff0070dd", desc="Rare (blue)" },
	epic       = { label="epic",   color="cffa335ee", desc="Epic (purple)" },
	class      = { label="class",  color="cffff7f00", desc="Unwanted for class" },
	auto       = { label="auto",   color="cffaaaaaa", desc="Auto flagged" },
	buyback    = { label="buyback", color="cffffcc00", desc="Bought back" },
	deleted    = { label="deleted", color=DELETED_REASON_COLOR, desc="Deleted" },
}
local RARITY_COLOR = {
	grey="|cff9d9d9d", common="|cffffffff", uncommon="|cff1eff00",
	rare="|cff0070dd", epic="|cffa335ee"
}
local function rq(word,key) return "Quality: "..(RARITY_COLOR[key] or "|cffffffff")..word.."|r" end
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
local QUALITY_TOKEN  = { [0]="grey",[1]="common",[2]="uncommon",[3]="rare",[4]="epic" }

local ROW_TINTS = {
	manual={0.70,0.70,0.70}, manualsell={0.70,0.60,0.60},
	grey={0.40,0.40,0.40}, common={0.55,0.55,0.55},
	uncommon={0.25,0.50,0.20}, rare={0.15,0.35,0.60},
	epic={0.45,0.20,0.60}, class={0.60,0.35,0.10},
	auto={0.30,0.30,0.30}, buyback={0.70,0.55,0.15},
	deleted=ROW_TINT_DELETED
}

-- UI state
local rows, visibleRows = {}, 0
local fauxScrollFrame, contentFrame, headerBG, fillerBG
local headers, separators = {}, {}
local itemColumnWidth = 0
local currentSortKey = "time"
local currentSortAsc = true
local currentReasonFilter = "ALL"
local searchTerm = ""
local filteredIndex = {}
local atBottomStick = true
local userScrollOverride = false
local unresolvedItemIDs = {}
local historyJustOpened = false
local updateInProgress, rerunRequested = false, false

local function SafeSetTexColor(tex,r,g,b,a)
	if not tex then return end
	if tex.SetColorTexture then tex:SetColorTexture(r,g,b,a) else tex:SetTexture(r,g,b,a) end
end
local function ApplyRowTint(row, reason, i)
	local t=ROW_TINTS[reason] or ROW_TINTS.auto
	SafeSetTexColor(row.bg, t[1], t[2], t[3], (i%2==0) and 0.20 or 0.12)
end
local function EnsureHistory() if not PeddlerSalesHistory then PeddlerSalesHistory = {} end end
local function EnsureGoldBaseline() if not PeddlerSessionGoldBaseline and GetMoney then PeddlerSessionGoldBaseline = GetMoney() end end

-- Currency
local ICON_SCALE=1.15
local BASE_ICON_SIZE=12
local ICON_SIZE=math.floor(BASE_ICON_SIZE*ICON_SCALE+0.5)
local function CoinTex(path) return "|TInterface\\MoneyFrame\\"..path..":"..ICON_SIZE..":"..ICON_SIZE..":0:0:64:64:5:59:5:59|t" end
local GOLD_ICON,SILVER_ICON,COPPER_ICON = CoinTex("UI-GoldIcon"),CoinTex("UI-SilverIcon"),CoinTex("UI-CopperIcon")
local function CoinsTex(amount)
	amount=amount or 0
	local g=math.floor(amount/10000)
	local s=math.floor((amount%10000)/100)
	local c=amount%100
	local t={}
	if g>0 then t[#t+1]="|cffffffff"..g.."|r "..GOLD_ICON end
	if s>0 or g>0 then t[#t+1]="|cffffffff"..s.."|r "..SILVER_ICON end
	t[#t+1]="|cffffffff"..c.."|r "..COPPER_ICON
	return table.concat(t," ")
end

-- Footer
local function UpdateSessionDisplay()
	if not (PeddlerHistoryFooterNetFrame and GetMoney) then return end
	EnsureGoldBaseline()
	local base = PeddlerSessionGoldBaseline or GetMoney()
	local now  = GetMoney()
	local diff = now - base
	local salesNet = PeddlerHistorySessionSalesNet or 0
	local function sign(v) return v>=0 and "|cff2aff2a+|r" or "|cffff2a2a-|r" end
	PeddlerHistoryFooterNetFrame.salesFS:SetText("|cffffd100Sales:|r "..sign(salesNet).." "..CoinsTex(math.abs(salesNet)))
	PeddlerHistoryFooterNetFrame.goldFS:SetText ("|cffffd100Gold:|r  "..sign(diff).." "..CoinsTex(math.abs(diff)))
end
Peddler.UpdateSessionDisplay = UpdateSessionDisplay

local function ShortTime(epoch)
	if date("%Y-%m-%d", epoch) == date("%Y-%m-%d") then return date("%H:%M", epoch) end
	return date("%Y-%m-%d", epoch)
end
local function FullTime(epoch) return date("%Y-%m-%d %H:%M:%S", epoch) end
local function BuildReasonDisplay(meta)
	if not meta then return "|cffffffff?|" end
	if meta.specialManualStar then
		return "|"..meta.color..meta.label.."|r|"..MANUAL_SELL_STAR_COLOR..MANUAL_SELL_STAR_SYMBOL.."|r"
	end
	return "|"..meta.color..meta.label.."|r"
end

-- Factories
local function CreateCell(parent,width,justifyH)
	local f=CreateFrame("Frame",nil,parent)
	f:SetSize(width,ROW_HEIGHT)
	local fs=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT",f,"TOPLEFT",INNER_PAD,0)
	fs:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-INNER_PAD,0)
	fs:SetJustifyV("MIDDLE")
	fs:SetJustifyH(justifyH or "LEFT")
	f.text=fs
	return f
end
local function CreateHeader(parent,width,justifyH,label,sortKey)
	local b=CreateFrame("Button",nil,parent)
	b:SetSize(width,HEADER_HEIGHT)
	b.sortKey=sortKey
	local fs=b:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
	fs:SetPoint("TOPLEFT",b,"TOPLEFT",INNER_PAD,-2)
	fs:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-INNER_PAD,2)
	fs:SetJustifyV("MIDDLE"); fs:SetJustifyH(justifyH or "CENTER")
	fs:SetText(label or ""); fs:SetTextColor(1,0.82,0)
	b.text=fs
	b:SetScript("OnClick", function(self)
		if currentSortKey == self.sortKey then
			currentSortAsc = not currentSortAsc
		else
			currentSortKey = self.sortKey
			currentSortAsc = true
		end
		atBottomStick = true
		userScrollOverride = false
		Peddler.UpdateHistoryUI()
	end)
	return b
end

-- Layout
local function ComputeItemColumnWidth(frame)
	local innerWidth = frame:GetWidth() - LEFT_SCROLL_X - RIGHT_SCROLL_X
	local fixed = COL_TIME_WIDTH + COL_QTY_WIDTH + COL_PRICE_WIDTH + COL_REASON_WIDTH
	itemColumnWidth = math.max(MIN_ITEM_COL_WIDTH, innerWidth - fixed)
end
local function ComputeVisibleRows(frame)
	local innerHeight = frame:GetHeight() - (math.abs(TOP_SCROLL_Y)+BOTTOM_SCROLL_Y)
	local rowsArea = innerHeight - HEADER_HEIGHT - 8 - 24
	local per = ROW_HEIGHT + ROW_SPACING
	local base = math.max(4, math.floor(rowsArea / per))
	return base + EXTRA_VISIBLE_ROWS
end
local function EnsureRowCount(count)
	if count == visibleRows then return end
	for i=visibleRows+1,count do
		local row=CreateFrame("Button",nil,contentFrame)
		row:SetHeight(ROW_HEIGHT)
		row.bg=row:CreateTexture(nil,"BACKGROUND")
		row.bg:SetAllPoints()
		SafeSetTexColor(row.bg,0,0,0,0.06)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		local hl=row:GetHighlightTexture(); if hl then hl:SetAllPoints(); hl:SetAlpha(0.18) end
		row.timeCell   = CreateCell(row,COL_TIME_WIDTH,"CENTER")
		row.itemCell   = CreateCell(row,itemColumnWidth,"LEFT")
		row.qtyCell    = CreateCell(row,COL_QTY_WIDTH,"CENTER")
		row.priceCell  = CreateCell(row,COL_PRICE_WIDTH-PRICE_CELL_PADDING*2,"RIGHT")
		row.reasonCell = CreateCell(row,COL_REASON_WIDTH,"LEFT")
		row.timeCell:SetPoint("LEFT",row,"LEFT",0,0)
		row.itemCell:SetPoint("LEFT",row.timeCell,"RIGHT",0,0)
		row.qtyCell:SetPoint("LEFT",row.itemCell,"RIGHT",0,0)
		row.priceCell:SetPoint("LEFT",row.qtyCell,"RIGHT",PRICE_CELL_PADDING,0)
		row.reasonCell:SetPoint("LEFT",row.priceCell,"RIGHT",PRICE_CELL_PADDING,0)
		row:SetScript("OnEnter", function(self)
			if not self.link or not self.link:find("|Hitem:") then return end
			GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.link)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cffbbbbbbTime:|r "..FullTime(self._fullTime or time()))
			if self.reasonCode then
				local meta=reasonMeta[self.reasonCode]; if meta then
					GameTooltip:AddLine("|"..meta.color.."Reason:|r "..(meta.desc or meta.label))
				end
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnMouseDown", function(self)
			if self.link and self.link:find("|Hitem:") and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
				ChatEdit_InsertLink(self.link)
			end
		end)
		rows[i]=row
	end
	if count < visibleRows then
		for i=count+1,visibleRows do
			if rows[i] then
				rows[i]:Hide()
				SafeSetTexColor(rows[i].bg,0,0,0,0)
			end
		end
	end
	visibleRows = count
end

local function LayoutRows()
	local startY=-HEADER_HEIGHT-6
	for i=1,visibleRows do
		local r=rows[i]; if not r then break end
		r:ClearAllPoints()
		if i==1 then r:SetPoint("TOPLEFT",contentFrame,"TOPLEFT",0,startY)
		else r:SetPoint("TOPLEFT",rows[i-1],"BOTTOMLEFT",0,-ROW_SPACING) end
		r:SetPoint("RIGHT",contentFrame,"RIGHT",0,0)
	end
end

local function LayoutHeaders()
	if not headers.order then return end
	local x=0
	for _,h in ipairs(headers.order) do
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT",contentFrame,"TOPLEFT",x,-2)
		x=x+h:GetWidth()
	end
	headerBG:ClearAllPoints()
	headerBG:SetPoint("TOPLEFT",contentFrame,"TOPLEFT",0,0)
	headerBG:SetPoint("TOPRIGHT",contentFrame,"TOPLEFT",x,0)
	local colPositions={
		COL_TIME_WIDTH,
		COL_TIME_WIDTH+itemColumnWidth,
		COL_TIME_WIDTH+itemColumnWidth+COL_QTY_WIDTH,
		COL_TIME_WIDTH+itemColumnWidth+COL_QTY_WIDTH+COL_PRICE_WIDTH
	}
	for i,sep in ipairs(separators) do
		sep:ClearAllPoints()
		sep:SetPoint("TOPLEFT",contentFrame,"TOPLEFT",colPositions[i],-2)
		sep:SetPoint("BOTTOMLEFT",contentFrame,"TOPLEFT",colPositions[i],-HEADER_HEIGHT+2)
		sep:Show()
	end
end

local function UpdateColumnWidths()
	headers.item:SetWidth(itemColumnWidth)
	for i=1,visibleRows do
		local r=rows[i]; if r and r.itemCell then r.itemCell:SetWidth(itemColumnWidth) end
	end
	LayoutHeaders()
end

-- Filtering
local function LinkMatchesSearch(entry)
	if searchTerm=="" then return true end
	local link=entry.link or ""
	local inside=link:match("%[(.-)%]") or link
	inside=inside:lower()
	return inside:find(searchTerm,1,true) ~= nil
end
local function ItemQualityMatches(entry, desired)
	if not QUALITY_REASON[desired] then return false end
	local itemID=entry.itemID
	if not itemID and entry.link then
		local id=tonumber(entry.link:match("|Hitem:(%d+):"))
		if id then itemID=id end
	end
	if not itemID then return false end
	local _,_,q=GetItemInfo(itemID)
	if not q then return false end
	return QUALITY_TOKEN[q]==desired
end
local function PassesFilter(entry)
	if not LinkMatchesSearch(entry) then return false end
	if currentReasonFilter=="ALL" then return true end
	if QUALITY_REASON[currentReasonFilter] then
		if entry.reason==currentReasonFilter then return true end
		return ItemQualityMatches(entry,currentReasonFilter)
	end
	return entry.reason==currentReasonFilter
end
local function BuildFilteredIndex()
	EnsureHistory()
	for i=#filteredIndex,1,-1 do filteredIndex[i]=nil end
	for i=1,#PeddlerSalesHistory do
		local e=PeddlerSalesHistory[i]
		if e and PassesFilter(e) then
			filteredIndex[#filteredIndex+1]=i
		end
	end
end

-- Sorting
local function SortFiltered()
	if currentSortKey ~= "time" and #filteredIndex > 1 then
		local key=currentSortKey
		local asc=currentSortAsc
		local list={}
		for _,idx in ipairs(filteredIndex) do
			local e=PeddlerSalesHistory[idx]
			if e then
				local name
				if e.link and e.link:find("%[") then
					name=e.link:match("%[(.+)%]") or e.link
				else
					name=e.link or ("item:"..(e.itemID or "?"))
				end
				list[#list+1]={ index=idx, item=(name or ""):lower(), qty=e.amount or 0,
					price=e.price or 0, reason=e.reason or "", time=e.time or 0 }
			end
		end
		table.sort(list,function(a,b)
			local va,vb
			if key=="item" then va,vb=a.item,b.item
			elseif key=="qty" then va,vb=a.qty,b.qty
			elseif key=="price" then va,vb=a.price,b.price
			elseif key=="reason" then va,vb=a.reason,b.reason
			else va,vb=a.time,b.time end
			if va==vb then return a.index < b.index end
			return asc and va<vb or va>vb
		end)
		for i=1,#list do filteredIndex[i]=list[i].index end
	end
end

-- Scroll helpers
local function ScrollToBottom(total)
	local maxOff = math.max(0, total - visibleRows)
	FauxScrollFrame_SetOffset(fauxScrollFrame, maxOff)
	local sb=_G[fauxScrollFrame:GetName().."ScrollBar"]
	if sb then sb:SetValue(maxOff*(ROW_HEIGHT+ROW_SPACING)) end
end

-- Core update
local function UpdateRowsInternal()
	BuildFilteredIndex()
	SortFiltered()

	local total = #filteredIndex
	local sbVisible = total > visibleRows

	if not sbVisible then
		FauxScrollFrame_SetOffset(fauxScrollFrame, 0)
	end

	local currentOffset = FauxScrollFrame_GetOffset(fauxScrollFrame) or 0
	local wasAtBottom = (currentOffset + visibleRows) >= (total - 1)

	if historyJustOpened or (atBottomStick and wasAtBottom) or not sbVisible then
		ScrollToBottom(total)
	else
		if wasAtBottom then atBottomStick = true else atBottomStick = false end
	end

	FauxScrollFrame_Update(fauxScrollFrame, total, visibleRows, ROW_HEIGHT + ROW_SPACING)

	local offset = sbVisible and (FauxScrollFrame_GetOffset(fauxScrollFrame) or 0) or 0

	for i=1,visibleRows do
		local row=rows[i]; if not row then break end
		local entryIndex=filteredIndex[offset + i]
		if entryIndex then
			local e=PeddlerSalesHistory[entryIndex]
			local t=e.time or time()
			if e.itemID and (not e.link or not e.link:find("|Hitem:")) then
				local _, lnk = GetItemInfo(e.itemID)
				if lnk then
					e.link=lnk
					unresolvedItemIDs[e.itemID]=nil
				else
					unresolvedItemIDs[e.itemID]=true
					GetItemInfo(e.itemID)
				end
			end
			row.link=e.link
			row._fullTime=t
			row.reasonCode=e.reason
			row.timeCell.text:SetText(ShortTime(t))
			if e.link and e.link:find("|Hitem:") then
				row.itemCell.text:SetText(e.link)
			elseif unresolvedItemIDs[e.itemID] then
				row.itemCell.text:SetText("|cffff5555[Retrieving Item Information]|r")
			elseif e.itemID then
				row.itemCell.text:SetText("item:"..e.itemID)
			else
				row.itemCell.text:SetText("?")
			end
			row.qtyCell.text:SetText(e.amount or 1)
			local meta=reasonMeta[e.reason] or reasonMeta.auto
			row.reasonCell.text:SetText(BuildReasonDisplay(meta))
			local priceStr=CoinsTex(e.price or 0)
			if e.reason=="buyback" then
				row.priceCell.text:SetText("|cffff5555-"..priceStr.."|r")
			else
				row.priceCell.text:SetText(priceStr)
			end
			ApplyRowTint(row,e.reason,i)
			row.bg:ClearAllPoints()
			row.bg:SetAllPoints(row)
			row:Show()
		else
			row:Hide()
			row.link=nil
			row.reasonCode=nil
		end
	end

	-- Stretch filler background
	fillerBG:ClearAllPoints()
	fillerBG:SetPoint("TOPLEFT",contentFrame,"TOPLEFT",0,-HEADER_HEIGHT)
	fillerBG:SetPoint("BOTTOMRIGHT",contentFrame,"BOTTOMRIGHT",0,0)

	LayoutRows()
	UpdateSessionDisplay()
	historyJustOpened = false
end

function Peddler.UpdateHistoryUI()
	if not PeddlerHistoryFrame then return end
	if updateInProgress then rerunRequested=true return end
	updateInProgress=true
	UpdateRowsInternal()
	updateInProgress=false
	if rerunRequested then rerunRequested=false Peddler.UpdateHistoryUI() end
end

-- Dropdown
local function InitializeFilterDropdown(self, level)
	if not level then return end
	for group=1,4 do
		for _,opt in ipairs(FILTER_OPTIONS) do
			if opt.group==group then
				local info=UIDropDownMenu_CreateInfo()
				info.text=opt.text
				info.value=opt.value
				info.func=function(btn)
					currentReasonFilter=btn.value
					UIDropDownMenu_SetSelectedValue(self, btn.value)
					atBottomStick = true
					userScrollOverride = false
					Peddler.UpdateHistoryUI()
				end
				info.checked=(currentReasonFilter==opt.value)
				UIDropDownMenu_AddButton(info, level)
			end
		end
		if group<4 then
			local sep=UIDropDownMenu_CreateInfo()
			sep.text=" "
			sep.disabled=true
			UIDropDownMenu_AddButton(sep, level)
		end
	end
end

-- Reset
function Peddler.ResetHistoryWindow()
	Peddler.EnsureHistoryState()
	currentSortKey="time"
	currentSortAsc=true
	currentReasonFilter="ALL"
	searchTerm=""
	PeddlerHistoryFrameState.width=DEFAULT_FRAME_WIDTH
	PeddlerHistoryFrameState.height=DEFAULT_FRAME_HEIGHT
	PeddlerHistoryFrameState.scrollOffset=0
	userScrollOverride=false
	atBottomStick=true
	if PeddlerHistoryFrame then
		PeddlerHistoryFrame:SetSize(DEFAULT_FRAME_WIDTH,DEFAULT_FRAME_HEIGHT)
		Peddler.ResetHistoryWindowPosition()
		Peddler.UpdateHistoryUI()
	else
		print("|cff33ff99Peddler:|r History reset.")
	end
end
function Peddler.ResetHistoryWindowPosition()
	if not PeddlerHistoryFrame then return end
	PeddlerHistoryFrame:ClearAllPoints()
	PeddlerHistoryFrame:SetPoint("CENTER")
end

-- Frame
local function CreateHistoryFrame()
	Peddler.EnsureHistoryState()
	if PeddlerHistoryFrame then return end

	local f=CreateFrame("Frame","PeddlerHistoryFrame",UIParent,"UIPanelDialogTemplate")
	f:SetResizable(true)
	f:SetMinResize(MIN_FRAME_WIDTH,MIN_FRAME_HEIGHT)
	f:SetSize(
		math.max(MIN_FRAME_WIDTH,PeddlerHistoryFrameState.width or DEFAULT_FRAME_WIDTH),
		math.max(MIN_FRAME_HEIGHT,PeddlerHistoryFrameState.height or DEFAULT_FRAME_HEIGHT)
	)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)

	local resizer=CreateFrame("Button",nil,f)
	resizer:SetSize(16,16)
	resizer:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-4,4)
	resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizer:SetScript("OnMouseDown", function(self,btn) if btn=="LeftButton" then f:StartSizing("BOTTOMRIGHT") end end)
	resizer:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		PeddlerHistoryFrameState.width=f:GetWidth()
		PeddlerHistoryFrameState.height=f:GetHeight()
		ComputeItemColumnWidth(f)
		EnsureRowCount(ComputeVisibleRows(f))
		UpdateColumnWidths()
		Peddler.UpdateHistoryUI()
	end)
	f:SetScript("OnSizeChanged", function()
		if not f:IsShown() then return end
		PeddlerHistoryFrameState.width=f:GetWidth()
		PeddlerHistoryFrameState.height=f:GetHeight()
		ComputeItemColumnWidth(f)
		EnsureRowCount(ComputeVisibleRows(f))
		UpdateColumnWidths()
		Peddler.UpdateHistoryUI()
	end)

	f:SetScript("OnShow", function()
		EnsureGoldBaseline()
		historyJustOpened = true
		atBottomStick = true
		for _,e in ipairs(PeddlerSalesHistory or {}) do
			if e.itemID and (not e.link or not e.link:find("|Hitem:")) then
				local _, lnk=GetItemInfo(e.itemID)
				if lnk then
					e.link=lnk
					unresolvedItemIDs[e.itemID]=nil
				else
					unresolvedItemIDs[e.itemID]=true
					GetItemInfo(e.itemID)
				end
			end
		end
		Peddler.UpdateHistoryUI()
	end)

	local title=f:CreateFontString(nil,"OVERLAY","GameFontHighlight")
	title:SetPoint("TOP",f,"TOP",0,-8)
	title:SetText("Peddler Sales History")
	f.TitleText=title
	tinsert(UISpecialFrames,"PeddlerHistoryFrame")

	fauxScrollFrame=CreateFrame("ScrollFrame","PeddlerHistoryFauxScrollFrame",f,"FauxScrollFrameTemplate")
	fauxScrollFrame:SetPoint("TOPLEFT",f,"TOPLEFT",LEFT_SCROLL_X,TOP_SCROLL_Y)
	fauxScrollFrame:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-RIGHT_SCROLL_X,BOTTOM_SCROLL_Y)
	fauxScrollFrame:SetScript("OnVerticalScroll", function(self,delta)
		FauxScrollFrame_OnVerticalScroll(self,delta,ROW_HEIGHT+ROW_SPACING,Peddler.UpdateHistoryUI)
		local off=FauxScrollFrame_GetOffset(self) or 0
		local total=#filteredIndex
		local atBottom = (off + visibleRows) >= total
		if atBottom then
			atBottomStick = true
			userScrollOverride = false
		else
			userScrollOverride = true
			atBottomStick = false
		end
	end)

	contentFrame=CreateFrame("Frame",nil,f)
	contentFrame:SetAllPoints(fauxScrollFrame)

	fillerBG=contentFrame:CreateTexture(nil,"BACKGROUND")
	fillerBG:SetColorTexture(0,0,0,0.04)
	fillerBG:SetPoint("TOPLEFT",contentFrame,"TOPLEFT",0,-HEADER_HEIGHT)
	fillerBG:SetPoint("BOTTOMRIGHT",contentFrame,"BOTTOMRIGHT",0,0)

	headerBG=contentFrame:CreateTexture(nil,"ARTWORK")
	headerBG:SetColorTexture(0,0,0,0.45)
	headerBG:SetPoint("TOPLEFT",contentFrame,"TOPLEFT",0,0)
	headerBG:SetHeight(HEADER_HEIGHT)

	headers.time   = CreateHeader(contentFrame,COL_TIME_WIDTH,"CENTER","Time","time")
	headers.item   = CreateHeader(contentFrame,10,"LEFT","Item","item")
	headers.qty    = CreateHeader(contentFrame,COL_QTY_WIDTH,"CENTER","Qty","qty")
	headers.price  = CreateHeader(contentFrame,COL_PRICE_WIDTH,"CENTER","Price","price")
	headers.reason = CreateHeader(contentFrame,COL_REASON_WIDTH,"LEFT","Reason","reason")
	headers.order  = { headers.time, headers.item, headers.qty, headers.price, headers.reason }

	for i=1,4 do
		local tex=contentFrame:CreateTexture(nil,"ARTWORK")
		tex:SetColorTexture(1,1,1,0.05)
		separators[i]=tex
	end

	local filterDrop=CreateFrame("Frame","PeddlerHistoryFilterDropdown",f,"UIDropDownMenuTemplate")
	filterDrop:SetPoint("TOPRIGHT",f,"TOPRIGHT",-10,-34)
	UIDropDownMenu_Initialize(filterDrop,InitializeFilterDropdown)
	UIDropDownMenu_SetWidth(filterDrop,180)
	UIDropDownMenu_SetSelectedValue(filterDrop,currentReasonFilter)

	local searchBox=CreateFrame("EditBox","PeddlerHistorySearchBox",f,"InputBoxTemplate")
	searchBox:SetSize(SEARCH_BOX_WIDTH,20)
	searchBox:SetAutoFocus(false)
	searchBox:SetPoint("BOTTOM",f,"BOTTOM",0,56)
	local placeholder=searchBox:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
	placeholder:SetPoint("LEFT",searchBox,"LEFT",4,0)
	placeholder:SetText("Search...")
	local function UpdatePH()
		if (searchBox:GetText() or "")=="" and not searchBox:HasFocus() then placeholder:Show() else placeholder:Hide() end
	end
	searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); UpdatePH() end)
	searchBox:SetScript("OnEditFocusGained", UpdatePH)
	searchBox:SetScript("OnEditFocusLost", UpdatePH)
	searchBox:SetScript("OnTextChanged", function(self)
		searchTerm=(self:GetText() or ""):lower()
		atBottomStick=true
		userScrollOverride=false
		UpdatePH()
		Peddler.UpdateHistoryUI()
	end)
	UpdatePH()

	local catcher=CreateFrame("Button",nil,UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:EnableMouse(true)
	catcher:Hide()
	catcher:SetScript("OnMouseDown", function()
		if searchBox:HasFocus() then searchBox:ClearFocus() end
		catcher:Hide()
	end)
	searchBox:HookScript("OnEditFocusGained", function() catcher:Show() end)
	searchBox:HookScript("OnEditFocusLost", function() catcher:Hide() end)

	local resetBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
	resetBtn:SetSize(120,22)
	resetBtn:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",16,20)
	resetBtn:SetText("Reset Window")
	resetBtn:SetScript("OnClick", function() Peddler.ResetHistoryWindow() end)

	local clearBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
	clearBtn:SetSize(140,22)
	clearBtn:SetPoint("BOTTOM",f,"BOTTOM",0,20)
	clearBtn:SetText("Clear History")
	clearBtn:SetScript("OnClick", function()
		EnsureHistory()
		for i=#PeddlerSalesHistory,1,-1 do PeddlerSalesHistory[i]=nil end
		PeddlerHistorySessionSalesNet = 0
		if Peddler and Peddler._SaleLedger then wipe(Peddler._SaleLedger) end
		atBottomStick = true
		userScrollOverride = false
		if Peddler.UpdateSessionDisplay then Peddler.UpdateSessionDisplay() end
		Peddler.UpdateHistoryUI()
	end)

	local netFrame=CreateFrame("Frame","PeddlerHistoryFooterNetFrame",f)
	netFrame:SetSize(260,36)
	netFrame:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-20,18)
	netFrame.salesFS=netFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
	netFrame.salesFS:SetPoint("TOPRIGHT",netFrame,"TOPRIGHT",0,0)
	netFrame.salesFS:SetJustifyH("RIGHT")
	netFrame.goldFS=netFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
	netFrame.goldFS:SetPoint("TOPRIGHT",netFrame.salesFS,"BOTTOMRIGHT",0,-2)
	netFrame.goldFS:SetJustifyH("RIGHT")
	netFrame:EnableMouse(true)
	netFrame:SetScript("OnEnter", function(self)
		EnsureGoldBaseline()
		local base=PeddlerSessionGoldBaseline or (GetMoney and GetMoney() or 0)
		local now=GetMoney and GetMoney() or base
		local diff=now-base
		local salesNet=PeddlerHistorySessionSalesNet or 0
		GameTooltip:SetOwner(self,"ANCHOR_TOP")
		GameTooltip:AddLine("Session Detail",1,1,1)
		GameTooltip:AddLine("Gold at login: "..CoinsTex(base),0.8,0.8,0.8)
		GameTooltip:AddLine("Gold now:      "..CoinsTex(now),0.8,0.8,0.8)
		if diff>=0 then
			GameTooltip:AddLine("Profit: "..CoinsTex(math.abs(diff)),0.4,1,0.4)
		else
			GameTooltip:AddLine("Loss: "..CoinsTex(math.abs(diff)),1,0.3,0.3)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Logged Sales Net: "..CoinsTex(math.abs(salesNet)),0.9,0.9,0.9)
		GameTooltip:AddLine("(Repairs/trades/mail change gold delta.)",0.65,0.65,0.65)
		GameTooltip:Show()
	end)
	netFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

	PeddlerHistoryFrame=f
	EnsureGoldBaseline()
	EnsureHistory()
	ComputeItemColumnWidth(f)
	EnsureRowCount(ComputeVisibleRows(f))
	UpdateColumnWidths()
	LayoutRows()
	atBottomStick=true
	userScrollOverride=false
	UpdateSessionDisplay()
	Peddler.UpdateHistoryUI()
end

-- Public
function Peddler.ShowHistory()
	Peddler.EnsureHistoryState()
	CreateHistoryFrame()
	if PeddlerHistoryFrame then
		PeddlerHistoryFrame:Show()
		historyJustOpened=true
		atBottomStick=true
		Peddler.UpdateHistoryUI()
	end
end
function Peddler.HideHistory()
	if PeddlerHistoryFrame then
		PeddlerHistoryFrame:Hide()
	end
end
function Peddler.ToggleHistory()
	if PeddlerHistoryFrame and PeddlerHistoryFrame:IsShown() then
		Peddler.HideHistory()
	else
		Peddler.ShowHistory()
	end
end

-- Item info resolver
local resolver=CreateFrame("Frame")
resolver:RegisterEvent("GET_ITEM_INFO_RECEIVED")
resolver:SetScript("OnEvent", function(_, itemID, success)
	if not success or not unresolvedItemIDs[itemID] then return end
	local _, link=GetItemInfo(itemID)
	if link then
		for _,e in ipairs(PeddlerSalesHistory or {}) do
			if e.itemID==itemID and (not e.link or not e.link:find("|Hitem:")) then
				e.link=link
			end
		end
		unresolvedItemIDs[itemID]=nil
		if PeddlerHistoryFrame and PeddlerHistoryFrame:IsShown() then
			Peddler.UpdateHistoryUI()
		end
	end
end)

-- Money watcher
local moneyWatcher=CreateFrame("Frame")
moneyWatcher:RegisterEvent("PLAYER_MONEY")
moneyWatcher:SetScript("OnEvent", function() UpdateSessionDisplay() end)

-- Merchant button
function Peddler.InitHistoryButton()
	if not MerchantFrame or PeddlerHistoryToggleButton then return end
	local btn=CreateFrame("Button","PeddlerHistoryToggleButton",MerchantFrame)
	btn:SetSize(20,20)
	if MerchantFrameCloseButton then
		btn:SetPoint("RIGHT",MerchantFrameCloseButton,"LEFT",-6,0)
	else
		btn:SetPoint("TOPRIGHT",MerchantFrame,"TOPRIGHT",-42,-16)
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

-- Baseline safety
local baseFrame=CreateFrame("Frame")
baseFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
baseFrame:SetScript("OnEvent", function()
	if GetMoney and not PeddlerSessionGoldBaseline then
		PeddlerSessionGoldBaseline=GetMoney()
	end
	UpdateSessionDisplay()
end)

-- Diagnostics
function Peddler.HistoryDiag()
	print("|cff33ff99Peddler History Diag|r rows=",#filteredIndex,"visibleRows=",visibleRows,"totalEntries=",#(PeddlerSalesHistory or {}))
end