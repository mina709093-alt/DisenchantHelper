-- DisenchantHelper / AuctionHouse.lua
-- 기존 경매장 검색 필터 영역에 "마력 추출 가능" 체크박스 추가, 검색 결과 필터링
--
-- 방식
--   * 서버 검색 조건(C_AuctionHouse.SendBrowseQuery)에는 마력 추출 필터가 없다.
--   * 그래서 서버가 돌려준 검색 결과 목록(BrowseResultsFrame.browseResults)을
--     화면에 그리기 직전에 걸러서 보여 준다. 검색창/검색 버튼/구매 과정은 건드리지 않는다.
--   * 원본 결과는 따로 보관해 두었다가 체크를 해제하면 그대로 복원한다.
--   * 판별할 수 없는(미확인) 아이템은 결과에서 제외하고, 정보가 도착하면 다시 거른다.

local _, DH = ...

local AH = {}
DH.AH = AH

AH.enabled = false
AH.full = nil         -- 서버가 돌려준 원본 결과 (필터 전)
AH.total = 0
AH.shown = 0
AH.hooked = false
AH.problem = nil

local function GetBrowseFrame()
    local f = _G.AuctionHouseFrame
    return f and f.BrowseResultsFrame
end

local function IsDE(result)
    if type(result) ~= "table" then return false end
    local res = DH.Engine:EvaluateItemKey(result.itemKey)
    return res.state == DH.Engine.YES
end

local function RefreshList(frame)
    local list = frame and frame.ItemList
    if not list then return end
    if list.DirtyScrollFrame then
        pcall(list.DirtyScrollFrame, list)
    elseif list.RefreshScrollFrame then
        pcall(list.RefreshScrollFrame, list)
    end
end

-- frame.browseResults 를 AH.full 기준으로 다시 채움
local function Rebuild(frame)
    local target = frame.browseResults
    if type(target) ~= "table" or not AH.full then return end
    wipe(target)
    if AH.enabled then
        for _, r in ipairs(AH.full) do
            if IsDE(r) then target[#target + 1] = r end
        end
    else
        for i, r in ipairs(AH.full) do target[i] = r end
    end
    AH.total, AH.shown = #AH.full, #target
    RefreshList(frame)
    if AH.checkbox and AH.checkbox:IsMouseOver() then AH:ShowTooltip(AH.checkbox) end
end

-- Blizzard 결과 갱신 직후 실행 (hooksecurefunc: 원래 함수는 그대로 실행됨)
local function OnBrowseResultsUpdated(frame, addedBrowseResults)
    if type(frame.browseResults) ~= "table" then return end
    if type(addedBrowseResults) == "table" and AH.full and AH.lastFiltered == frame.browseResults then
        -- 추가로 도착한 결과만 원본에 이어 붙임
        for _, r in ipairs(addedBrowseResults) do AH.full[#AH.full + 1] = r end
    else
        -- 새 검색 결과: 원본 복사
        AH.full = {}
        for i, r in ipairs(frame.browseResults) do AH.full[i] = r end
    end
    AH.lastFiltered = frame.browseResults
    if AH.enabled then
        Rebuild(frame)
    else
        AH.total, AH.shown = #AH.full, #frame.browseResults
    end
end

function AH:Hook()
    if self.hooked then return true end
    local frame = GetBrowseFrame()
    if not frame then
        self.problem = "경매장 결과 프레임을 찾지 못함"
        return false
    end
    if type(frame.UpdateBrowseResults) ~= "function" then
        self.problem = "결과 갱신 함수(UpdateBrowseResults)를 찾지 못함"
        return false
    end
    hooksecurefunc(frame, "UpdateBrowseResults", function(f, added)
        DH:SafeCall(OnBrowseResultsUpdated, f, added)
    end)
    self.hooked = true
    self.problem = nil
    return true
end

function AH:SetEnabled(on)
    self.enabled = on and true or false
    local frame = GetBrowseFrame()
    if not frame then return end
    if not self.full and type(frame.browseResults) == "table" then
        self.full = {}
        for i, r in ipairs(frame.browseResults) do self.full[i] = r end
        self.lastFiltered = frame.browseResults
    end
    Rebuild(frame)
end

function AH:GetStatusText()
    if not _G.AuctionHouseFrame then return "경매장 UI 미로딩 (경매장을 한 번 열어 주세요)" end
    if not self.hooked then return "사용 불가: " .. (self.problem or "알 수 없음") end
    return string.format("연결됨, 체크: %s, 결과 %d/%d", self.enabled and "예" or "아니오", self.shown or 0, self.total or 0)
end

function AH:ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine("마력 추출 가능", 1, 0.82, 0)
    GameTooltip:AddLine("검색 결과에서 마력 추출이 가능한 장비만 표시합니다.", 1, 1, 1, true)
    GameTooltip:AddLine("판별할 수 없는 아이템은 제외됩니다.", 0.7, 0.7, 0.7, true)
    if not self.hooked then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("이 클라이언트의 경매장 구조를 인식하지 못해 필터를 적용할 수 없습니다.", 1, 0.3, 0.3, true)
        GameTooltip:AddLine(self.problem or "", 1, 0.3, 0.3, true)
    elseif self.enabled then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("현재 결과: 추출 가능 %d개 / 전체 %d개", self.shown or 0, self.total or 0), 0.2, 1, 0.2)
    end
    local p = DH.Engine:GetPlayerStatus()
    if p.knowsDE == false then
        GameTooltip:AddLine("마법부여를 배우지 않아 모든 결과가 '추출 불가'로 판별됩니다.", 1, 0.5, 0.2, true)
    elseif p.skill then
        GameTooltip:AddLine("현재 마법부여 숙련도: " .. p.skill .. " (숙련도에 맞는 아이템만 표시)", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- 체크박스 (기존 검색 필터 버튼 옆, 기존 체크박스 템플릿 사용)
---------------------------------------------------------------------------
local function Overlaps(a, b)
    if not a or not b or not a:IsVisible() or not b:IsVisible() then return false end
    local al, ar, at, ab = a:GetLeft(), a:GetRight(), a:GetTop(), a:GetBottom()
    local bl, br, bt, bb = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
    if not (al and bl) then return false end
    return al < br and ar > bl and ab < bt and at > bb
end

local function PlaceCheckbox(cb)
    local ahf = _G.AuctionHouseFrame
    local bar = ahf and ahf.SearchBar
    if not bar then return end
    local filter = bar.FilterButton
    local search = bar.SearchButton
    local box = bar.SearchBox
    cb:ClearAllPoints()
    -- 1순위: 필터 버튼 왼쪽 (체크박스 + 글자)
    if filter then
        cb:SetPoint("RIGHT", filter, "LEFT", -(cb.label:GetStringWidth() + 10), 0)
        if not Overlaps(cb.hit, box) and not Overlaps(cb.hit, search) then return end
    end
    -- 2순위: 검색 줄의 가장 오른쪽 버튼 오른쪽
    local rightmost = filter
    if search and filter and (search:GetRight() or 0) > (filter:GetRight() or 0) then rightmost = search end
    if rightmost then
        cb:ClearAllPoints()
        cb:SetPoint("LEFT", rightmost, "RIGHT", 8, 0)
        local fr = ahf:GetRight()
        if fr and cb.hit:GetRight() and cb.hit:GetRight() < fr - 4 then return end
    end
    -- 3순위: 필터 버튼 바로 위
    cb:ClearAllPoints()
    cb:SetPoint("BOTTOMRIGHT", filter or bar, "TOPRIGHT", -(cb.label:GetStringWidth() + 6), 0)
end

function AH:CreateCheckbox()
    if self.checkbox then return end
    local ahf = _G.AuctionHouseFrame
    local bar = ahf and ahf.SearchBar
    if not bar then return end

    local cb = CreateFrame("CheckButton", "DisenchantHelperAHFilterCheck", bar, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local label = cb.Text or cb.text or _G[cb:GetName() .. "Text"]
    if not label then
        label = cb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 0, 1)
    end
    label:SetFontObject("GameFontNormalSmall")
    label:SetText("마력 추출 가능")
    cb.label = label
    cb:SetHitRectInsets(0, -(label:GetStringWidth() + 4), 0, 0)

    -- 겹침 확인용 영역 (체크박스 + 글자)
    local hit = CreateFrame("Frame", nil, cb)
    hit:SetPoint("TOPLEFT", cb, "TOPLEFT")
    hit:SetPoint("BOTTOMLEFT", cb, "BOTTOMLEFT")
    hit:SetWidth(24 + label:GetStringWidth() + 4)
    cb.hit = hit

    cb:SetChecked(self.enabled)
    cb:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and 856 or 857) -- 체크/해제 소리
        AH:SetEnabled(self:GetChecked())
    end)
    cb:SetScript("OnEnter", function(self) AH:ShowTooltip(self) end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.checkbox = cb
    C_Timer.After(0, function() DH:SafeCall(PlaceCheckbox, cb) end)
    ahf:HookScript("OnShow", function()
        C_Timer.After(0, function() DH:SafeCall(PlaceCheckbox, cb) end)
    end)
end

-- 마법부여 미습득 캐릭터는 체크박스를 숨기고 필터도 끔
function AH:UpdateActive()
    local cb = self.checkbox
    if not cb then return end
    if DH:IsActive() then
        cb:Show()
    else
        if self.enabled then
            cb:SetChecked(false)
            self:SetEnabled(false)
        end
        cb:Hide()
    end
end

local function Setup()
    if not _G.AuctionHouseFrame then return end
    AH:Hook()
    AH:CreateCheckbox()
    AH:UpdateActive()
end

DH:On("ACTIVE_CHANGED", function() DH:SafeCall(AH.UpdateActive, AH) end)

---------------------------------------------------------------------------
-- 이벤트
---------------------------------------------------------------------------
DH:RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_AuctionHouseUI" then DH:SafeCall(Setup) end
end)

DH:On("INIT", function()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
        DH:SafeCall(Setup)
    end
end)

DH:RegisterEvent("AUCTION_HOUSE_SHOW", function()
    DH:SafeCall(Setup)
    if not AH.hooked and not AH.warned then
        AH.warned = true
        DH:Print("|cffff8800경매장 필터를 연결하지 못했습니다:|r " .. (AH.problem or "") .. "  (/dh 진단 으로 정보 복사)")
    end
end)

DH:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
    AH.full = nil
    AH.lastFiltered = nil
    AH.total, AH.shown = 0, 0
end)

-- 아이템 정보가 늦게 도착하면 원본 결과를 기준으로 다시 거름
DH:On("ITEM_DATA_READY", function()
    if not AH.enabled or not AH.full then return end
    local frame = GetBrowseFrame()
    if frame and frame:IsVisible() then Rebuild(frame) end
end)
DH:On("DATA_CHANGED", function()
    if not AH.enabled or not AH.full then return end
    local frame = GetBrowseFrame()
    if frame and frame:IsVisible() then Rebuild(frame) end
end)
