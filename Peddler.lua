local _, Peddler = ...

-- ============================================================================
-- Peddler Core (Auto-sell + Post-baseline Buyback Growth Manual Detection)
-- ============================================================================

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

local SELL_MODE       = "sequential"
local SELL_INTERVAL   = 0.05
local WAVE_SIZE       = 12
local WAVE_PAUSE      = 0.20
local MAX_SELL_QUEUE  = 200
local BUYBACK_CAP     = 12

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
local Hook                 = hooksecurefunc

local floor, print = math.floor, print

local coreFrame = CreateFrame("Frame")
local markCounter, countLimit = 1, 1

Peddler._autoSellingActive      = Peddler._autoSellingActive or false
Peddler._autoScheduledCount     = Peddler._autoScheduledCount or 0
Peddler._autoLoggedCount        = Peddler._autoLoggedCount or 0
Peddler._sellQueue              = Peddler._sellQueue or {}
Peddler._sellingIndex           = Peddler._sellingIndex or 0
Peddler._sellingTimerFrame      = Peddler._sellingTimerFrame or CreateFrame("Frame")
Peddler._wavePausePending       = Peddler._wavePausePending or false
Peddler._currentBatchTotal      = Peddler._currentBatchTotal or 0
Peddler._SaleLedger             = Peddler._SaleLedger or {}
Peddler._BuybackBaseline        = Peddler._BuybackBaseline or nil
Peddler._BuybackWatcherEnabled  = Peddler._BuybackWatcherEnabled or false
Peddler._ManualSaleDedupe       = Peddler._ManualSaleDedupe or {}
Peddler._LastMoney              = Peddler._LastMoney or (GetMoney and GetMoney() or 0)

if not PeddlerHistorySessionSalesNet then
    PeddlerHistorySessionSalesNet = 0
end

local DEBUG = false
local function Dbg(...)
    if not DEBUG then return end
    local t={"|cff33ff99PeddlerDBG|r"}
    for i=1,select("#", ...) do t[#t+1]=tostring(select(i,...)) end
    DEFAULT_CHAT_FRAME:AddMessage(table.concat(t," "))
end

local function RunAfter(d,f) Peddler.RunAfter(d,f) end

local GOLD_ICON   = "Interface\\MoneyFrame\\UI-GoldIcon"
local SILVER_ICON = "Interface\\MoneyFrame\\UI-SilverIcon"
local COPPER_ICON = "Interface\\MoneyFrame\\UI-CopperIcon"
local COIN_SIZE   = 12
local function CoinTex(path) return "|T"..path..":"..COIN_SIZE..":"..COIN_SIZE..":0:0:64:64:5:59:5:59|t" end
local GOLD_TEX, SILVER_TEX, COPPER_TEX = CoinTex(GOLD_ICON), CoinTex(SILVER_ICON), CoinTex(COPPER_ICON)
local function CoinsString(amount)
    amount = amount or 0
    local g = floor(amount / 10000)
    local s = floor((amount % 10000) / 100)
    local c = amount % 100
    local t={}
    if g>0 then t[#t+1]=g.." "..GOLD_TEX end
    if s>0 or g>0 then t[#t+1]=s.." "..SILVER_TEX end
    t[#t+1]=c.." "..COPPER_TEX
    return table.concat(t, " ")
end

local function ApplyDefaultsIfNil()
    for k,v in pairs(DEFAULTS) do if _G[k]==nil then _G[k]=v end end
end
local function SetupDefaults()
    if not ItemsToSell   then ItemsToSell   = {} end
    if not UnmarkedItems then UnmarkedItems = {} end
    if not ItemsToDelete then ItemsToDelete = {} end
    ApplyDefaultsIfNil()
end

local function ModifierActive()
    local ctrl, shift, alt = IsControlKeyDown(), IsShiftKeyDown(), IsAltKeyDown()
    if ModifierKey=="CTRL" then return ctrl end
    if ModifierKey=="ALT" then return alt end
    if ModifierKey=="SHIFT" then return shift end
    if ModifierKey=="CTRL-SHIFT" then return ctrl and shift end
    if ModifierKey=="CTRL-ALT" then return ctrl and alt end
    if ModifierKey=="ALT-SHIFT" then return alt and shift end
    return false
end

function Peddler.itemIsToBeSold(itemID, unique)
    local auto = select(1, Peddler.ShouldAutoSell(itemID, unique))
    if not auto then return ItemsToSell[unique] end
    return ItemsToSell[unique] or auto
end
local function GetSaleReasonCode(itemID, unique)
    local _, link, quality = GetItemInfo(itemID)
    local manual = ItemsToSell and ItemsToSell[unique]
    local _, classUnwanted = Peddler.ShouldAutoSell(itemID, unique)
    return Peddler.ClassifyAutoReason(quality, manual, classUnwanted)
end

local function ItemLedgerKey(itemID, link)
    if link and link:find("|Hitem:") then
        local itemString = link:match("(|Hitem:%d+:[^|]*|h)")
        return itemString or ("id:"..(itemID or 0))
    end
    return "id:"..(itemID or 0)
end

-- Reprice
local function AttemptReprice(itemID)
    local list = Peddler._PendingPriceFix and Peddler._PendingPriceFix[itemID]
    if not list or not PeddlerSalesHistory or #list==0 then return end
    local _,_,_,_,_,_,_,_,_,_,unitPrice = GetItemInfo(itemID)
    if not unitPrice or unitPrice<=0 then return end
    for i=#list,1,-1 do
        local idx=list[i]
        local e=PeddlerSalesHistory[idx]
        if e and e.reason=="manualsell" and e.price==0 and e.itemID==itemID then
            local addValue=unitPrice*(e.amount or 1)
            local key=ItemLedgerKey(e.itemID, e.link)
            if Peddler._SaleLedger[key] and Peddler._SaleLedger[key]>0 then
                e.price=addValue
                PeddlerHistorySessionSalesNet=(PeddlerHistorySessionSalesNet or 0)+addValue
            else
                e.price=addValue
            end
        end
        table.remove(list,i)
    end
    if #list==0 then Peddler._PendingPriceFix[itemID]=nil end
    if PeddlerHistoryFrame and PeddlerHistoryFrame:IsShown() and Peddler.UpdateHistoryUI then Peddler.UpdateHistoryUI() end
    if Peddler.UpdateSessionDisplay then Peddler.UpdateSessionDisplay() end
end

function Peddler.LogSale(itemID, link, amount, priceCopper, reason)
    if not PeddlerSalesHistory then PeddlerSalesHistory={} end
    local price=priceCopper or 0
    local qty=amount or 1
    local idx=#PeddlerSalesHistory+1
    PeddlerSalesHistory[idx]={ time=time(), itemID=itemID or 0, link=link, amount=qty, price=price, reason=reason or "auto" }
    if #PeddlerSalesHistory>500 then table.remove(PeddlerSalesHistory,1) end

    if reason=="buyback" then
        local key=ItemLedgerKey(itemID, link)
        if Peddler._SaleLedger[key] and Peddler._SaleLedger[key]>0 then
            Peddler._SaleLedger[key]=Peddler._SaleLedger[key]-1
            PeddlerHistorySessionSalesNet=(PeddlerHistorySessionSalesNet or 0)-price
        end
    elseif reason~="deleted" then
        local key=ItemLedgerKey(itemID, link)
        Peddler._SaleLedger[key]=(Peddler._SaleLedger[key] or 0)+1
        PeddlerHistorySessionSalesNet=(PeddlerHistorySessionSalesNet or 0)+price
    end

    if reason=="manualsell" and price==0 and itemID and itemID>0 then
        Peddler._PendingPriceFix=Peddler._PendingPriceFix or {}
        Peddler._PendingPriceFix[itemID]=Peddler._PendingPriceFix[itemID] or {}
        table.insert(Peddler._PendingPriceFix[itemID], idx)
        GetItemInfo(itemID)
        RunAfter(0.5,function() AttemptReprice(itemID) end)
    end
    if itemID and itemID>0 and (not link or not link:find("|Hitem:")) then GetItemInfo(itemID) end
    if PeddlerHistoryFrame and PeddlerHistoryFrame:IsShown() and Peddler.UpdateHistoryUI then Peddler.UpdateHistoryUI() end
    if Peddler.UpdateSessionDisplay then Peddler.UpdateSessionDisplay() end
end

-- Buyback baseline
local function BuildBuybackSnapshot()
    local snap={}
    for i=1,(GetNumBuybackItems() or 0) do
        local link=GetBuybackItemLink(i)
        local name, _, price, qty = GetBuybackItemInfo(i)
        local key
        if link then
            key = link.."@"..(price or 0).."@"..(qty or 1)
        else
            key = "NOLINK:"..(name or "?").."@"..(price or 0).."@"..(qty or 1)
        end
        snap[key]=(snap[key] or 0)+1
    end
    return snap
end

-- FIXED: simplified pattern so full colored link is captured cleanly
local function ParseBuybackKey(key)
    local head, p, q = key:match("^(.-)@(%d+)@(%d+)$")
    if head then
        return head, tonumber(p) or 0, tonumber(q) or 1
    end
    return key, 0, 1
end

local function CaptureBuybackBaseline()
    Peddler._BuybackBaseline = BuildBuybackSnapshot()
    Peddler._BuybackWatcherEnabled = true
    Dbg("Baseline captured; watcher enabled.")
end

-- FIXED: correct amount, link, and price handling (no price*qty multiplication; qty preserved)
local function DetectNewManualBuys()
    if not Peddler._BuybackWatcherEnabled then return end
    if Peddler._autoSellingActive then return end
    local old = Peddler._BuybackBaseline or {}
    local current = BuildBuybackSnapshot()
    for key,count in pairs(current) do
        local prev = old[key] or 0
        if count > prev then
            local delta = count - prev
            local head, stackPrice, stackQty = ParseBuybackKey(key)
            local link = head:find("|Hitem:") and head or nil
            local itemID = link and tonumber(link:match("|Hitem:(%d+):"))
            local totalPrice = stackPrice -- already total stack price per GetBuybackItemInfo
            local saleKey = key
            if not Peddler._ManualSaleDedupe[saleKey] then
                -- Log once per new stack instance (delta times)
                for _=1,delta do
                    Peddler.LogSale(itemID or 0, link or head, stackQty, totalPrice, "manualsell")
                end
                Peddler._ManualSaleDedupe[saleKey]=true
            end
        end
    end
    Peddler._BuybackBaseline = current
end

-- Auto-sell Engine (unchanged except finalize baseline scheduling)
local function PrintSaleLine(i,total,link,count,value)
    if Silent or SilenceSaleSummary then return end
    local msg=" "..i.."/"..total..": "..(link or "?")
    if count>1 then msg=msg.."x"..count end
    msg=msg.." for "..CoinsString(value)
    print(msg)
end

local function FinalizeAutoSelling()
    Peddler._autoSellingActive=false
    Peddler._wavePausePending=false
    RunAfter(0.08, CaptureBuybackBaseline)
end

local function LogCompletionCheck()
    if not Peddler._autoSellingActive then return end
    if Peddler._autoLoggedCount>=Peddler._autoScheduledCount then
        RunAfter(0.02, FinalizeAutoSelling)
    end
end

local function SellNextSequential()
    if not Peddler._autoSellingActive then return end
    Peddler._sellingIndex=Peddler._sellingIndex+1
    local i=Peddler._sellingIndex
    local entry=Peddler._sellQueue[i]
    if not entry then LogCompletionCheck(); return end
    local bag,slot,itemID=entry.bag,entry.slot,entry.itemID
    local link=entry.link or GetContainerItemLink(bag,slot)
    local count=entry.count
    local price=entry.price
    local reason=entry.reason
    local value=(price or 0)*count
    UseContainerItem(bag,slot)
    if not Silent and i==1 and not SilenceSaleSummary then
        print("Peddler is selling "..#Peddler._sellQueue.." item(s):")
    end
    Peddler._currentBatchTotal=Peddler._currentBatchTotal+value
    if price and price>0 then PrintSaleLine(i,#Peddler._sellQueue,link,count,value) end
    Peddler.LogSale(itemID, link or ("item:"..itemID), count, value, reason)
    Peddler._autoLoggedCount=Peddler._autoLoggedCount+1
    if i < #Peddler._sellQueue then
        Peddler._sellingTimerFrame.elapsed=0
        Peddler._sellingTimerFrame:SetScript("OnUpdate",function(_,dt)
            Peddler._sellingTimerFrame.elapsed=Peddler._sellingTimerFrame.elapsed+dt
            if Peddler._sellingTimerFrame.elapsed>=SELL_INTERVAL then
                Peddler._sellingTimerFrame:SetScript("OnUpdate",nil)
                SellNextSequential()
            end
        end)
    else
        if not Silent and not SilenceSaleSummary then
            print("Total: "..CoinsString(Peddler._currentBatchTotal))
        end
        LogCompletionCheck()
    end
end

local function SellWave()
    if not Peddler._autoSellingActive then return end
    if Peddler._wavePausePending then return end
    local startIdx=Peddler._sellingIndex+1
    local q=Peddler._sellQueue
    if startIdx>#q then LogCompletionCheck(); return end
    local endIdx=math.min(startIdx+WAVE_SIZE-1,#q)
    if not Silent and startIdx==1 and not SilenceSaleSummary then
        print("Peddler is selling "..#q.." item(s) in waves of "..WAVE_SIZE..":")
    end
    for i=startIdx,endIdx do
        Peddler._sellingIndex=i
        local e=q[i]
        if e then
            local bag,slot,itemID=e.bag,e.slot,e.itemID
            local link=e.link or GetContainerItemLink(bag,slot)
            local count=e.count
            local price=e.price
            local reason=e.reason
            local val=(price or 0)*count
            Peddler._currentBatchTotal=Peddler._currentBatchTotal+val
            UseContainerItem(bag,slot)
            if price and price>0 then PrintSaleLine(i,#q,link,count,val) end
            Peddler.LogSale(itemID, link or ("item:"..itemID), count, val, reason)
            Peddler._autoLoggedCount=Peddler._autoLoggedCount+1
        end
    end
    if Peddler._sellingIndex < #q then
        Peddler._wavePausePending=true
        RunAfter(WAVE_PAUSE,function()
            Peddler._wavePausePending=false
            SellWave()
        end)
    else
        if not Silent and not SilenceSaleSummary then
            print("Total: "..CoinsString(Peddler._currentBatchTotal))
        end
        LogCompletionCheck()
    end
end

local function StartSelling()
    if SELL_MODE=="waves" then SellWave() else SellNextSequential() end
end

local function QueueSell(list)
    Peddler._sellQueue=list
    Peddler._autoScheduledCount=#list
    Peddler._autoLoggedCount=0
    Peddler._sellingIndex=0
    Peddler._autoSellingActive=(#list>0)
    Peddler._currentBatchTotal=0
end

local function PrewarmItemInfo(ids) for id in pairs(ids) do GetItemInfo(id) end end

local function PeddleGoods()
    Peddler._BuybackWatcherEnabled=false
    Peddler._BuybackBaseline=nil
    local planned={}
    local maxQueue=SellLimit and BUYBACK_CAP or MAX_SELL_QUEUE
    local prewarm={}
    for bag=0,4 do
        local slots=GetContainerNumSlots(bag)
        for slot=1,slots do
            local link=GetContainerItemLink(bag,slot)
            if link then
                local itemID,unique=Peddler.ParseItemLink(link)
                if unique and Peddler.itemIsToBeSold(itemID, unique) then
                    local _,stack=GetContainerItemInfo(bag,slot)
                    stack=stack or 1
                    local _,_,_,_,_,_,_,_,_,_,price=GetItemInfo(itemID)
                    local reason=GetSaleReasonCode(itemID, unique)
                    planned[#planned+1]={
                        bag=bag,slot=slot,itemID=itemID,unique=unique,
                        count=stack,price=price or 0,reason=reason,link=link
                    }
                    prewarm[itemID]=true
                    if #planned>=maxQueue then break end
                end
            end
        end
        if #planned>=maxQueue then break end
    end
    if #planned==0 then
        RunAfter(0.05, function()
            Peddler._BuybackBaseline=BuildBuybackSnapshot()
            Peddler._BuybackWatcherEnabled=true
            Dbg("Baseline (no autosell) captured; watcher enabled.")
        end)
        return
    end
    PrewarmItemInfo(prewarm)
    QueueSell(planned)
    StartSelling()
end

Hook("BuybackItem", function(index)
    local link=GetBuybackItemLink(index)
    local name,_,price,qty=GetBuybackItemInfo(index)
    if not (link or name) then return end
    local itemID=link and tonumber(link:match("|Hitem:(%d+):"))
    Peddler.LogSale(itemID or 0, link or name, qty or 1, price or 0, "buyback")
    RunAfter(0.05,function()
        if Peddler._BuybackWatcherEnabled then
            Peddler._BuybackBaseline=BuildBuybackSnapshot()
        end
    end)
end)

-- Resets
function Peddler.ResetManualFlags()
    if not ItemsToSell then ItemsToSell={} end
    local c=0 for _ in pairs(ItemsToSell) do c=c+1 end
    for k in pairs(ItemsToSell) do ItemsToSell[k]=nil end
    print("|cff33ff99Peddler:|r Reset "..c.." manually flagged sell item"..(c==1 and "" or "s")..".")
    if Peddler.MarkWares then Peddler.MarkWares() end
end
function Peddler.ResetAll()
    for k,v in pairs(DEFAULTS) do _G[k]=v end
    ItemsToSell,UnmarkedItems,ItemsToDelete={}, {}, {}
    PeddlerSalesHistory={}
    PeddlerHistoryFrameState={ width=730,height=480,scrollOffset=0 }
    PeddlerHistorySessionSalesNet=0
    PeddlerSessionGoldBaseline=nil
    wipe(Peddler._SaleLedger)
    Peddler._BuybackBaseline=nil
    Peddler._BuybackWatcherEnabled=false
    Peddler._ManualSaleDedupe={}
    Peddler._PendingPriceFix={}
    if Peddler.ResetHistoryWindow then Peddler.ResetHistoryWindow() end
    if Peddler.MarkWares then Peddler.MarkWares() end
    print("|cff33ff99Peddler:|r All settings reset.")
end

-- Modifier toggle
local function ToggleSellFlag(itemID, unique)
    local _,_,_,_,_,_,_,_,_,_,price=GetItemInfo(itemID)
    if price==0 then return false end
    local auto=Peddler.ShouldAutoSell(itemID, unique)
    if auto then
        if UnmarkedItems[unique] then
            UnmarkedItems[unique]=nil
        else
            UnmarkedItems[unique]=1
            ItemsToSell[unique]=nil
        end
    elseif ItemsToSell[unique] then
        ItemsToSell[unique]=nil
    else
        ItemsToSell[unique]=1
    end
    return true
end
local function HandleItemClick(btn, button)
    local ctrl,shift,alt=IsControlKeyDown(),IsShiftKeyDown(),IsAltKeyDown()
    local mod =
        (ModifierKey=="CTRL" and ctrl) or
        (ModifierKey=="SHIFT" and shift) or
        (ModifierKey=="ALT" and alt) or
        (ModifierKey=="CTRL-SHIFT" and ctrl and shift) or
        (ModifierKey=="CTRL-ALT" and ctrl and alt) or
        (ModifierKey=="ALT-SHIFT" and alt and shift)
    if not (mod and button=="RightButton") then return end
    local parent=btn:GetParent(); if not parent then return end
    local bag,slot=parent:GetID(),btn:GetID()
    local link=GetContainerItemLink(bag,slot); if not link then return end
    local itemID, unique=Peddler.ParseItemLink(link); if not itemID then return end
    local _,_,_,_,_,_,_,_,_,_,price=GetItemInfo(itemID)
    if not price or price==0 then
        Peddler.ItemDelete.ToggleDeleteFlag(itemID, unique)
    else
        ToggleSellFlag(itemID, unique)
    end
    if Peddler.MarkWares then Peddler.MarkWares() end
end
Hook("ContainerFrameItemButton_OnModifiedClick", HandleItemClick)

-- Quest rewards
local listeningToRewards={}
local function CheckQuestReward(btn)
    local idx=btn:GetID()
    local function test(link)
        if not link then return end
        local itemID,unique=Peddler.ParseItemLink(link)
        if itemID and unique then
            local _,_,_,_,_,_,_,_,_,_,price=GetItemInfo(itemID)
            if price and price>0 then ToggleSellFlag(itemID, unique) else Peddler.ItemDelete.ToggleDeleteFlag(itemID, unique) end
        end
    end
    test(GetQuestLogItemLink("reward", idx))
    test(GetQuestLogItemLink("choice", idx))
end
local function QuestRewardClick(self) if not IsAltKeyDown() then return end CheckQuestReward(self); if Peddler.MarkWares then Peddler.MarkWares() end end
local function SetupQuestFrame(base)
    for i=1,6 do
        local name=base..i
        local btn=_G[name]
        if btn and not listeningToRewards[name] then
            listeningToRewards[name]=true
            btn:HookScript("OnClick", QuestRewardClick)
        end
    end
end
if QuestInfoRewardsFrame then QuestInfoRewardsFrame:HookScript("OnShow", function() SetupQuestFrame("QuestInfoRewardsFrameQuestInfoItem") end) end
if MapQuestInfoRewardsFrame then MapQuestInfoRewardsFrame:HookScript("OnShow", function() SetupQuestFrame("MapQuestInfoRewardsFrameQuestInfoItem") end) end

-- Events
coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("MERCHANT_SHOW")
coreFrame:RegisterEvent("MERCHANT_CLOSED")
coreFrame:RegisterEvent("MERCHANT_UPDATE")
coreFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local function OnUpdateDriver()
    markCounter=markCounter+1
    if markCounter>countLimit then
        markCounter=0
        if Peddler.MarkWares then Peddler.MarkWares() end
    end
end

local function HandleEvent(self, event, ...)
    local arg1,arg2=...
    if event=="ADDON_LOADED" and arg1=="Peddler" then
        self:UnregisterEvent("ADDON_LOADED")
        SetupDefaults()
        if Peddler.CompatRegister then Peddler.CompatRegister() end
        countLimit=400
        self:SetScript("OnUpdate", OnUpdateDriver)

    elseif event=="PLAYER_ENTERING_WORLD" then
        if GetMoney then
            PeddlerSessionGoldBaseline=GetMoney()
            PeddlerHistorySessionSalesNet=0
            wipe(Peddler._SaleLedger)
        end
        Peddler._BuybackWatcherEnabled=false
        Peddler._BuybackBaseline=nil

    elseif event=="MERCHANT_SHOW" then
        Peddler._BuybackWatcherEnabled=false
        Peddler._BuybackBaseline=nil
        if Peddler.InitHistoryButton then Peddler.InitHistoryButton() end
        PeddleGoods()

    elseif event=="MERCHANT_UPDATE" then
        DetectNewManualBuys()

    elseif event=="MERCHANT_CLOSED" then
        Peddler._BuybackWatcherEnabled=false
        Peddler._BuybackBaseline=nil

    elseif event=="GET_ITEM_INFO_RECEIVED" then
        local itemID, success = arg1, arg2
        if success then AttemptReprice(itemID) end
    end
end
coreFrame:SetScript("OnEvent", HandleEvent)

-- Slash
SLASH_PEDDLER_COMMAND1="/peddler"
SlashCmdList["PEDDLER_COMMAND"]=function(cmd)
    cmd = Peddler.Trim(string.lower(cmd or ""))

    local function ShowHelp()
        print("|cff33ff99Peddler Commands:|r")
        print(" /peddler config")
        print(" /peddler history")
        print(" /peddler setup")
        print(" /peddler reset flags/delete/history/all")
    end

    if cmd=="" then
        ShowHelp()
    elseif cmd=="config" or cmd=="options" then
        if InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory("Peddler")
            InterfaceOptionsFrame_OpenToCategory("Peddler")
        end
    elseif cmd=="setup" then
        if Peddler.StartSetupWizard then Peddler.StartSetupWizard(true) end
    elseif cmd=="history" or cmd=="hist" then
        if Peddler.ToggleHistory then Peddler.ToggleHistory() end
    elseif cmd=="reset flags" or cmd=="reset manual" then
        Peddler.ResetManualFlags()
    elseif cmd=="reset delete" then
        Peddler.ItemDelete.Reset()
    elseif cmd=="reset history" then
        if Peddler.ResetHistoryWindow then Peddler.ResetHistoryWindow() end
    elseif cmd=="reset all" then
        Peddler.ResetAll()
    else
        ShowHelp()
    end
end

if not Peddler.ShowHistory then
    function Peddler.ShowHistory() print("|cff33ff99Peddler:|r History not loaded.") end
end
if not Peddler.ToggleHistory then
    function Peddler.ToggleHistory() Peddler.ShowHistory() end
end

PeddlerAPI = Peddler