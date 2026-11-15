-- DisenchantHelper / Bags.lua
-- 인벤토리 자동 검사, 테두리 표시, 아이템 변경 처리, 단축키+좌클릭 마력 추출 오버레이

local _, DH = ...
local API = DH.API

local Bags = {}
DH.Bags = Bags

local COLOR_DE    = { 0.72, 0.30, 1.0, 1 }   -- 마력 추출 가능 (보라색: 고급 등급 초록 테두리와 구분)
local COLOR_BLUE  = { 0.2, 0.55, 1.0, 1 }    -- 일괄 추출 선택됨
local COLOR_NEXT  = { 0.45, 0.85, 1.0, 1 }   -- 일괄 추출 다음 대상 (밝은 파랑 + 깜빡임)
local EDGE = 2                                -- 테두리 두께 (아이콘 바깥쪽에만 그림)

local decos = {}         -- itemButton -> deco frame
local hookedButtons = {} -- itemButton -> true
local hookedFrames = {}
local hookedCount = 0

Bags.batchMode = false
Bags.hoverButton = nil

---------------------------------------------------------------------------
-- 테두리 프레임 (아이콘 바깥 2px, 아이콘/수량/귀속 표시를 가리지 않음)
---------------------------------------------------------------------------
local function CreateDeco(button)
    local d = CreateFrame("Button", nil, button)
    d:SetPoint("TOPLEFT", button, "TOPLEFT", -EDGE, EDGE)
    d:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", EDGE, -EDGE)
    d:SetFrameLevel(button:GetFrameLevel() + 4)
    d:EnableMouse(false)
    d:RegisterForClicks("LeftButtonUp")

    local function edge()
        local t = d:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        return t
    end
    d.top, d.bottom, d.left, d.right = edge(), edge(), edge(), edge()
    d.top:SetPoint("TOPLEFT"); d.top:SetPoint("TOPRIGHT"); d.top:SetHeight(EDGE)
    d.bottom:SetPoint("BOTTOMLEFT"); d.bottom:SetPoint("BOTTOMRIGHT"); d.bottom:SetHeight(EDGE)
    d.left:SetPoint("TOPLEFT", 0, -EDGE); d.left:SetPoint("BOTTOMLEFT", 0, EDGE); d.left:SetWidth(EDGE)
    d.right:SetPoint("TOPRIGHT", 0, -EDGE); d.right:SetPoint("BOTTOMRIGHT", 0, EDGE); d.right:SetWidth(EDGE)

    -- 다음 추출 대상 깜빡임 (애니메이션 그룹 사용, OnUpdate 없음)
    local ag = d:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.6)
    d.pulse = ag

    -- 일괄 추출 모드: 보라 테두리 아이템 클릭 = 선택/해제
    d:SetScript("OnClick", function(self)
        if self.bag and self.slot and DH.Batch then DH.Batch:Toggle(self.bag, self.slot) end
    end)
    d:SetScript("OnEnter", function(self)
        if not self.bag then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetBagItem, GameTooltip, self.bag, self.slot)
        GameTooltip:AddLine(" ")
        if DH.Batch and DH.Batch:IsSelectedSlot(self.bag, self.slot) then
            GameTooltip:AddLine("좌클릭: 선택 해제 (일괄 추출)", 0.4, 0.7, 1)
        else
            GameTooltip:AddLine("좌클릭: 선택 (일괄 추출)", 0.4, 0.7, 1)
        end
        GameTooltip:Show()
    end)
    d:SetScript("OnLeave", function() GameTooltip:Hide() end)

    decos[button] = d
    return d
end

local function SetDecoColor(d, c)
    for _, t in ipairs({ d.top, d.bottom, d.left, d.right }) do t:SetVertexColor(c[1], c[2], c[3], c[4]) end
end

local function GetButtonBagSlot(button)
    local bag
    if button.GetBagID then
        local ok, b = pcall(button.GetBagID, button)
        if ok then bag = b end
    end
    if bag == nil then
        local parent = button:GetParent()
        if parent and parent.GetID then bag = parent:GetID() end
    end
    local slot = button:GetID()
    if type(bag) ~= "number" or type(slot) ~= "number" or slot <= 0 then return nil end
    return bag, slot
end
Bags.GetButtonBagSlot = GetButtonBagSlot

---------------------------------------------------------------------------
-- 마우스 오버 추적 (단축키+좌클릭 추출용)
---------------------------------------------------------------------------
local function HookButton(button)
    if hookedButtons[button] then return end
    hookedButtons[button] = true
    button:HookScript("OnEnter", function(self)
        Bags.hoverButton = self
        if DH.ClickCast then DH.ClickCast:Update() end
    end)
    button:HookScript("OnLeave", function(self)
        local cc = DH.ClickCast
        if cc and cc.overlay and cc.overlay:IsShown() and cc.overlay:IsMouseOver() then return end
        if Bags.hoverButton == self then Bags.hoverButton = nil end
        if cc then cc:Update() end
    end)
end

---------------------------------------------------------------------------
-- 버튼 갱신
---------------------------------------------------------------------------
function Bags:UpdateButton(button)
    if not button then return end
    HookButton(button)
    local d = decos[button]
    local bag, slot = GetButtonBagSlot(button)
    if not bag or not button:IsShown() or not DH:IsActive() then
        if d then d.bag = nil; d:Hide(); d.pulse:Stop() end
        return
    end
    local res, info = DH.Engine:EvaluateBagSlot(bag, slot)
    if res.state ~= DH.Engine.YES then
        if d then d.bag = nil; d:Hide(); d.pulse:Stop() end
        return
    end
    -- 툴팁 근거 없이 규칙으로만 "가능" 판정된 아이템은 사전 확인 대기열에 넣음
    if res.source == "규칙" and info and DH.Prefetch then
        DH.Prefetch:Queue(bag, slot, info.itemID)
    end
    d = d or CreateDeco(button)
    d.bag, d.slot = bag, slot

    local selected = DH.Batch and DH.Batch:IsSelectedSlot(bag, slot)
    local isNext = selected and DH.Batch:IsNextSlot(bag, slot)
    if isNext then
        SetDecoColor(d, COLOR_NEXT)
        if not d.pulse:IsPlaying() then d.pulse:Play() end
    else
        d.pulse:Stop(); d:SetAlpha(1)
        SetDecoColor(d, selected and COLOR_BLUE or COLOR_DE)
    end
    d:EnableMouse(Bags.batchMode and true or false)
    d:Show()
end

local function ForEachButton(frame, fn)
    if frame.EnumerateValidItems then
        local ok = pcall(function()
            for _, btn in frame:EnumerateValidItems() do fn(btn) end
        end)
        if ok then return end
    end
    -- 구형 이름 규칙 (ContainerFrameNItemM)
    local name = frame:GetName()
    if name then
        for i = 1, 40 do
            local btn = _G[name .. "Item" .. i]
            if not btn then break end
            if btn:IsShown() then fn(btn) end
        end
    end
end

function Bags:UpdateFrame(frame)
    if not frame or not frame:IsShown() then return end
    ForEachButton(frame, function(btn) Bags:UpdateButton(btn) end)
end

local function GetContainerFrames()
    local list = {}
    local n = NUM_CONTAINER_FRAMES or 13
    for i = 1, math.max(n, 13) do
        local f = _G["ContainerFrame" .. i]
        if f then list[#list + 1] = f end
    end
    if _G.ContainerFrameCombinedBags then list[#list + 1] = _G.ContainerFrameCombinedBags end
    return list
end
Bags.GetContainerFrames = GetContainerFrames

function Bags:RefreshAll()
    for _, f in ipairs(GetContainerFrames()) do
        if f:IsShown() then self:UpdateFrame(f) end
    end
end

local function HookFrame(frame)
    if hookedFrames[frame] then return end
    hookedFrames[frame] = true
    hookedCount = hookedCount + 1
    if type(frame.UpdateItems) == "function" then
        hooksecurefunc(frame, "UpdateItems", function(self) DH:SafeCall(Bags.UpdateFrame, Bags, self) end)
    end
    frame:HookScript("OnShow", function(self)
        C_Timer.After(0, function() DH:SafeCall(Bags.UpdateFrame, Bags, self) end)
    end)
end

function Bags:HookAll()
    for _, f in ipairs(GetContainerFrames()) do HookFrame(f) end
    -- 구형 클라이언트 함수가 있으면 함께 연결
    if type(_G.ContainerFrame_Update) == "function" and not Bags.legacyHooked then
        Bags.legacyHooked = true
        hooksecurefunc("ContainerFrame_Update", function(frame) DH:SafeCall(Bags.UpdateFrame, Bags, frame) end)
    end
end

function Bags:GetHookSummary()
    return string.format("%d개 프레임 (통합 가방: %s)", hookedCount, _G.ContainerFrameCombinedBags and "있음" or "없음")
end

function Bags:SetBatchMode(on)
    self.batchMode = on and true or false
    if DH.ClickCast then DH.ClickCast:Update() end
    self:RefreshAll()
end

---------------------------------------------------------------------------
-- 단축키 + 좌클릭 마력 추출 (SecureActionButtonTemplate 오버레이)
-- * 애드온 코드가 주문을 직접 시전하지 않는다.
-- * 플레이어의 실제 마우스 클릭이 보안 버튼에 전달될 때만 게임이 주문을 시전한다.
-- * 전투 중에는 보안 프레임을 이동/표시할 수 없으므로 동작하지 않는다.
---------------------------------------------------------------------------
local ClickCast = {}
DH.ClickCast = ClickCast

function ClickCast:Create()
    if self.overlay then return end
    local b = CreateFrame("Button", "DisenchantHelperClickCastButton", UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    b:Hide()

    local hl = b:CreateTexture(nil, "OVERLAY")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.85, 0.3, 0.25)

    b:SetScript("OnEnter", function(self)
        if not self.bag then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetBagItem, GameTooltip, self.bag, self.slot)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((DH.MODIFIER_LABEL[DH.db.modifier] or "Alt") .. " + 좌클릭: 마력 추출", 0.8, 0.5, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        local hb = Bags.hoverButton
        if hb and not hb:IsMouseOver() then Bags.hoverButton = nil end
        ClickCast:Update()
    end)
    b:SetScript("PostClick", function(self)
        if not self.bag then return end
        if DH.Batch then DH.Batch:NotifyCastAttempt(self.bag, self.slot) end
        -- 클릭은 들어왔는데 1초 안에 시전이 시작되지 않으면 한 번 안내
        if not ClickCast.checking then
            ClickCast.checking = true
            local clickTime = GetTime()
            C_Timer.After(1, function()
                ClickCast.checking = nil
                if (DH.lastCastStart or 0) < clickTime and (DH.lastCastError or 0) < clickTime and not ClickCast.warned then
                    ClickCast.warned = true
                    DH:Print("|cffff8800클릭은 들어왔지만 마력 추출이 시작되지 않았습니다.|r /dh 진단 내용을 보내 주세요.")
                end
            end)
        end
    end)
    self.overlay = b
end

function ClickCast:Hide()
    local b = self.overlay
    if not b or InCombatLockdown() then return end
    b.bag, b.slot = nil, nil
    b:ClearAllPoints()
    b:Hide()
end

function ClickCast:Update()
    local b = self.overlay
    if not b or InCombatLockdown() then return end
    local btn = Bags.hoverButton
    if not btn or Bags.batchMode or not DH:IsActive() or not DH.db or not API.ModifierDown(DH.db.modifier)
        or not btn:IsVisible() then
        self:Hide()
        return
    end
    local bag, slot = GetButtonBagSlot(btn)
    if not bag then self:Hide(); return end
    local res, info = DH.Engine:EvaluateBagSlot(bag, slot)
    if res.state ~= DH.Engine.YES or (info and info.locked) then self:Hide(); return end

    b:ClearAllPoints()
    b:SetAllPoints(btn)
    DH:SetCastAttributes(b, bag, slot)
    b.bag, b.slot = bag, slot
    b:Show()
end

---------------------------------------------------------------------------
-- 사전 확인 (마우스를 올리지 않아도 게임 툴팁의 마력 추출 문구를 미리 읽음)
-- 게임은 "마력 추출 불가" 줄을 툴팁이 실제로 화면에 표시될 때 붙인다.
-- 그래서 보이지 않게(투명) 툴팁을 실제로 띄운 뒤 잠시 기다렸다가 읽는다.
--   1단계: 애드온 전용 툴팁을 투명하게 표시
--   2단계: 1단계에서 문구가 없으면, 기본 툴팁(GameTooltip)이 쉬고 있을 때만 잠깐 투명하게 빌려서 확인
-- 아이템 종류(itemID)당 한 번만 확인하고, 한 번에 하나씩 처리해서 게임에 부담을 주지 않는다.
---------------------------------------------------------------------------
local Prefetch = { queue = {}, queued = {}, checked = {}, busy = false,
                   stats = { own = 0, game = 0, none = 0 } }
DH.Prefetch = Prefetch

local WAIT = 0.25          -- 툴팁 표시 후 기다리는 시간 (초)
local ownTip, dummyOwner

function Prefetch:Queue(bag, slot, itemID)
    if not itemID or self.checked[itemID] or self.queued[itemID] then return end
    if DH.Engine:GetLearned(itemID) then return end
    self.queued[itemID] = true
    table.insert(self.queue, { bag = bag, slot = slot, itemID = itemID })
    C_Timer.After(0.1, function() DH:SafeCall(Prefetch.Run, Prefetch) end)
end

local function GetItemName(itemID)
    local name = API.GetItemInfo(itemID)
    return name or ("아이템 " .. itemID)
end

function Prefetch:Finish(job, s, lvl, stage)
    self.checked[job.itemID] = true
    self.queued[job.itemID] = nil
    self.busy = false
    if s then
        self.stats[stage] = self.stats[stage] + 1
        local changed = DH.Engine:Learn(job.itemID, s, lvl, false)
        if changed and s == DH.Engine.NO then
            DH:Print(GetItemName(job.itemID) .. ": 게임 툴팁에서 '마력 추출 불가'를 확인해 표시를 해제했습니다. (자동 확인)")
        end
    else
        self.stats.none = self.stats.none + 1
    end
    C_Timer.After(0.05, function() DH:SafeCall(Prefetch.Run, Prefetch) end)
end

-- 처리하지 못한 작업을 나중에 다시 시도
function Prefetch:Retry(job, delay)
    self.busy = false
    table.insert(self.queue, job)
    C_Timer.After(delay or 1, function() DH:SafeCall(Prefetch.Run, Prefetch) end)
end

-- 2단계: 기본 툴팁을 잠깐 빌려서 확인
function Prefetch:TryGameTooltip(job)
    if InCombatLockdown() then return self:Retry(job, 2) end
    if GameTooltip:IsShown() then return self:Retry(job, 1) end
    dummyOwner = dummyOwner or CreateFrame("Frame", nil, UIParent)
    self.borrowing = true
    local ok = pcall(function()
        GameTooltip:SetOwner(dummyOwner, "ANCHOR_NONE")
        GameTooltip:SetAlpha(0)
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -100, -100)
        GameTooltip:SetBagItem(job.bag, job.slot)
        GameTooltip:Show()
    end)
    if not ok then
        self.borrowing = false
        GameTooltip:SetAlpha(1)
        return self:Finish(job, nil, nil, "none")
    end
    C_Timer.After(WAIT, function()
        local mine = GameTooltip:GetOwner() == dummyOwner
        local s, lvl
        if mine then
            s, lvl = DH.Engine.ScanTooltipFrame(GameTooltip)
            GameTooltip:Hide()
        end
        GameTooltip:SetAlpha(1)
        self.borrowing = false
        if mine then
            self:Finish(job, s, lvl, "game")
        else
            -- 그 사이 플레이어가 다른 곳에 마우스를 올려 툴팁을 사용함 → 나중에 다시
            self:Retry(job, 1)
        end
    end)
end

function Prefetch:Run()
    if self.busy or #self.queue == 0 then return end
    if InCombatLockdown() then return end   -- 전투가 끝나면 PLAYER_REGEN_ENABLED 에서 재개
    local job = table.remove(self.queue, 1)
    -- 그 사이 아이템이 이동/삭제되었거나 이미 확인된 경우 건너뜀
    local info = API.GetSlotInfo(job.bag, job.slot)
    if not info or info.itemID ~= job.itemID or DH.Engine:GetLearned(job.itemID) then
        self.queued[job.itemID] = nil
        return self:Run()
    end
    self.busy = true

    -- 1단계: 애드온 전용 툴팁을 투명하게 표시
    if not ownTip then
        ownTip = CreateFrame("GameTooltip", "DisenchantHelperPrefetchTooltip", UIParent, "GameTooltipTemplate")
    end
    local ok = pcall(function()
        ownTip:SetOwner(UIParent, "ANCHOR_NONE")
        ownTip:ClearAllPoints()
        ownTip:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -100, -100)
        ownTip:SetAlpha(0)
        ownTip:SetBagItem(job.bag, job.slot)
        ownTip:Show()
    end)
    if not ok then return self:TryGameTooltip(job) end
    C_Timer.After(WAIT, function()
        local s, lvl = DH.Engine.ScanTooltipFrame(ownTip)
        ownTip:Hide()
        if s then
            self:Finish(job, s, lvl, "own")
        else
            self:TryGameTooltip(job)
        end
    end)
end

function Prefetch:GetStatusText()
    return string.format("전용 툴팁 %d / 기본 툴팁 %d / 문구 없음 %d / 대기 %d",
        self.stats.own, self.stats.game, self.stats.none, #self.queue)
end

-- 안전장치: 플레이어가 툴팁을 쓰는데 투명 상태가 남아 있으면 즉시 복구
GameTooltip:HookScript("OnShow", function(tt)
    if not Prefetch.borrowing and tt:GetAlpha() < 1 then tt:SetAlpha(1) end
end)

DH:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    C_Timer.After(1, function() DH:SafeCall(Prefetch.Run, Prefetch) end)
end)

---------------------------------------------------------------------------
-- 아이템 툴팁에 판별 결과 표시
---------------------------------------------------------------------------
local function AddTooltipLine(tooltip)
    if not tooltip or not tooltip.GetItem or not DH:IsActive() then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if not ok or not link or API.IsSecret(link) then return end
    -- 안전장치: 실제로 화면에 그려진 게임 툴팁의 마력 추출 문구를 우선 기록
    -- (판별이 틀렸다면 여기서 바로 바로잡히고 가방/경매장 표시도 다시 갱신됨)
    local itemID = tonumber(link:match("item:(%d+)"))
    local tipState, tipSkill = DH.Engine.ScanTooltipFrame(tooltip)
    if itemID and tipState then DH.Engine:Learn(itemID, tipState, tipSkill, false) end
    local res = DH.Engine:EvaluateLink(link)
    if not res or res.notGear then return end
    -- 장비가 아닌 아이템(재료 등)은 표시하지 않음
    if res.state == DH.Engine.NO and (res.reason == "장비 아님") then return end
    local function lineText(rs)
        local t = "마력 추출: " .. DH.Engine.Label(rs.state)
        if rs.state ~= DH.Engine.YES and rs.reason then t = t .. " (" .. rs.reason .. ")" end
        return t
    end
    local r, g, b = DH.Engine.Color(res.state)
    tooltip:AddLine(lineText(res), r, g, b)
    local myIndex = tooltip:NumLines()

    -- 게임 툴팁의 마력 추출 문구가 이 시점보다 늦게 붙는 경우 대비:
    -- 툴팁이 다 그려진 뒤 한 번 더 읽고, 결과가 바뀌면 기록 + 이 툴팁의 우리 줄도 고침
    local name = tooltip:GetName()
    local function recheck()
        if not tooltip:IsShown() then return end
        local ok2, _, curLink = pcall(tooltip.GetItem, tooltip)
        if not ok2 or curLink ~= link then return end
        local s, lvl = DH.Engine.ScanTooltipFrame(tooltip)
        if not (itemID and s) then return end
        if DH.Engine:Learn(itemID, s, lvl, false) then
            local newRes = DH.Engine:EvaluateLink(link)
            local fs = name and _G[name .. "TextLeft" .. myIndex]
            if newRes and fs then
                fs:SetText(lineText(newRes))
                fs:SetTextColor(DH.Engine.Color(newRes.state))
                tooltip:Show()
            end
        end
    end
    C_Timer.After(0, function() DH:SafeCall(recheck) end)
    C_Timer.After(0.3, function() DH:SafeCall(recheck) end)
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then
                DH:SafeCall(AddTooltipLine, tooltip)
            end
        end)
        -- 다른 애드온/기본 UI가 툴팁을 다 만든 뒤(표시 시점)에도 한 번 더 확인
        GameTooltip:HookScript("OnShow", function(tt)
            C_Timer.After(0, function()
                DH:SafeCall(function()
                    if not tt:IsShown() or not DH:IsActive() then return end
                    local ok, _, link = pcall(tt.GetItem, tt)
                    if not ok or not link or API.IsSecret(link) then return end
                    local itemID = tonumber(link:match("item:(%d+)"))
                    local s, lvl = DH.Engine.ScanTooltipFrame(tt)
                    if itemID and s then DH.Engine:Learn(itemID, s, lvl, false) end
                end)
            end)
        end)
    elseif GameTooltip:HasScript("OnTooltipSetItem") then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt) DH:SafeCall(AddTooltipLine, tt) end)
        if ItemRefTooltip then
            ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt) DH:SafeCall(AddTooltipLine, tt) end)
        end
    end
end

---------------------------------------------------------------------------
-- 이벤트
---------------------------------------------------------------------------
DH:On("INIT", function()
    Bags:HookAll()
    ClickCast:Create()
    HookTooltips()
end)

-- 가방 프레임이 나중에 생성되는 경우 대비
DH:RegisterEvent("BAG_OPEN", function() Bags:HookAll() end)

-- 아이템 정보 로딩 완료, 숙련도 변화, 선택 변경 → 보이는 가방만 다시 표시 (캐시 사용)
DH:On("ITEM_DATA_READY", function() Bags:RefreshAll() end)
DH:On("DATA_CHANGED", function() Bags:RefreshAll() end)
DH:On("SELECTION_CHANGED", function() Bags:RefreshAll() end)
DH:On("ACTIVE_CHANGED", function() Bags:RefreshAll(); ClickCast:Update() end)

DH:RegisterEvent("MODIFIER_STATE_CHANGED", function() ClickCast:Update() end)
DH:On("MODIFIER_CHANGED", function() ClickCast:Update() end)

-- 전투 시작 직전(잠금 전)에 보안 오버레이 숨김
DH:RegisterEvent("PLAYER_REGEN_DISABLED", function() ClickCast:Hide() end)

-- 아이템 잠금 상태 변화(이동 중 등) 시 오버레이 재확인
DH:RegisterEvent("ITEM_LOCK_CHANGED", function() ClickCast:Update() end)
DH:RegisterEvent("BAG_UPDATE_DELAYED", function()
    ClickCast:Update()
end)
