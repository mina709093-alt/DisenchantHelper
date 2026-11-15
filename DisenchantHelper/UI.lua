-- DisenchantHelper / UI.lua
-- [일괄 추출] 버튼, 선택 목록 창, [선택 아이템 추출] 보안 버튼, 상태 표시, 복사 창

local _, DH = ...
local API = DH.API

local UI = {}
DH.UI = UI

local ROWS = 8
local ROW_H = 26
local WIN_W, WIN_H = 270, 420

-- 가방 프레임이 하나라도 열려 있는지
local function AnyBagShown()
    for _, f in ipairs(DH.Bags.GetContainerFrames()) do
        if f:IsShown() then return true end
    end
    return false
end


---------------------------------------------------------------------------
-- 보안 추출 버튼 (선택 목록의 다음 아이템 1개를 추출)
-- 이름이 Bindings.xml 의 CLICK 바인딩과 같아야 함
---------------------------------------------------------------------------
local function CreateCastButton(parent)
    local b = CreateFrame("Button", "DisenchantHelperBatchCastButton", parent,
        "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetSize(WIN_W - 24, 28)
    b:SetText("선택 아이템 추출")
    b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    b:SetScript("PreClick", function(self) DH.Batch:PrepareSecureButton(self) end)
    b:SetScript("PostClick", function(self) DH.Batch:OnSecureButtonPostClick(self) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("선택 아이템 추출", 1, 0.82, 0)
        GameTooltip:AddLine("누를 때마다 선택된 아이템을 1개씩 순서대로 마력 추출합니다.", 1, 1, 1, true)
        GameTooltip:AddLine("게임 보안 정책상 클릭(또는 키 입력) 1번에 1개만 추출할 수 있습니다.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("단축키 지정: 게임 메뉴 > 설정 > 단축키 > 애드온 > 마력 추출 도우미", 0.4, 0.8, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

---------------------------------------------------------------------------
-- 선택 목록 창
---------------------------------------------------------------------------
local function SetItemTooltip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if e.bag and e.slot then
        pcall(GameTooltip.SetBagItem, GameTooltip, e.bag, e.slot)
    elseif e.link then
        pcall(GameTooltip.SetHyperlink, GameTooltip, e.link)
    end
    GameTooltip:Show()
end

local function CreateRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIN_W - 30, ROW_H - 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.icon:SetPoint("LEFT", 2, 0)

    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(16, 16)
    row.remove:SetPoint("RIGHT", -2, 0)
    row.remove:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    row.remove:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    row.remove:SetScript("OnClick", function() if row.entry then DH.Batch:RemoveEntry(row.entry) end end)
    row.remove:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("선택 해제")
        GameTooltip:Show()
    end)
    row.remove:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.mark:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", 1, 1)
    row.mark:SetText("|cff66ccff다음|r")

    row:SetScript("OnEnter", function(self) if self.entry then SetItemTooltip(self, self.entry) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function UI:CreateBatchWindow()
    if self.window then return end
    local f = CreateFrame("Frame", "DisenchantHelperBatchFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIN_W, WIN_H)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        DH.db.batchPos = { point, relPoint, x, y }
    end)
    f:Hide()

    local title = f.TitleText or f.title
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("일괄 추출")

    local help = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 14, -30)
    help:SetPoint("TOPRIGHT", -14, -30)
    help:SetJustifyH("LEFT")
    help:SetText("가방의 보라 테두리 아이템을 클릭하면 선택됩니다.\n선택된 아이템은 파란 테두리로 표시됩니다.")

    -- 목록 영역
    local listBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 10, -62)
    listBg:SetSize(WIN_W - 20, ROWS * ROW_H + 8)
    if listBg.SetBackdrop then
        listBg:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        listBg:SetBackdropColor(0, 0, 0, 0.5)
        listBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    end

    local content = CreateFrame("Frame", nil, listBg)
    content:SetPoint("TOPLEFT", 5, -4)
    content:SetSize(WIN_W - 30, ROWS * ROW_H)
    f.rows = {}
    for i = 1, ROWS do f.rows[i] = CreateRow(content, i) end
    f.offset = 0

    local empty = listBg:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetText("선택된 아이템이 없습니다")
    f.empty = empty

    listBg:EnableMouseWheel(true)
    listBg:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, DH.Batch:Count() - ROWS)
        f.offset = math.min(maxOff, math.max(0, f.offset - delta))
        UI:RefreshBatchWindow()
    end)

    f.pageText = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    f.pageText:SetPoint("TOPRIGHT", listBg, "BOTTOMRIGHT", -4, -2)

    -- 수량 / 상태
    f.countText = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.countText:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 4, -16)

    f.remainText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.remainText:SetPoint("TOPLEFT", f.countText, "BOTTOMLEFT", 0, -4)

    f.statusText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.statusText:SetPoint("TOPLEFT", f.remainText, "BOTTOMLEFT", 0, -4)
    f.statusText:SetWidth(WIN_W - 28)
    f.statusText:SetJustifyH("LEFT")
    f.statusText:SetWordWrap(true)

    -- 버튼
    local selAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    selAll:SetSize((WIN_W - 30) / 2, 22)
    selAll:SetPoint("BOTTOMLEFT", 12, 48)
    selAll:SetText("추출 가능 전체 선택")
    selAll:SetScript("OnClick", function() DH.Batch:SelectAll() end)

    local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clear:SetSize((WIN_W - 30) / 2, 22)
    clear:SetPoint("LEFT", selAll, "RIGHT", 6, 0)
    clear:SetText("전체 선택 해제")
    clear:SetScript("OnClick", function() DH.Batch:ClearAll() end)

    local cast = CreateCastButton(f)
    cast:SetPoint("BOTTOM", 0, 14)
    f.cast = cast

    f:SetScript("OnShow", function()
        DH.Bags:SetBatchMode(true)
        UI:RefreshBatchWindow()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
    end)
    f:SetScript("OnHide", function()
        DH.Bags:SetBatchMode(false)
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
    end)

    self.window = f
    self:PositionBatchWindow()
end

function UI:PositionBatchWindow()
    local f = self.window
    if not f or InCombatLockdown() then return end
    f:ClearAllPoints()
    local pos = DH.db and DH.db.batchPos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        return
    end
    local bagFrame = UI:GetMainBagFrame()
    if bagFrame and bagFrame:IsShown() then
        f:SetPoint("BOTTOMRIGHT", bagFrame, "BOTTOMLEFT", -90, 0)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -260, 0)
    end
end

function UI:RefreshBatchWindow()
    local f = self.window
    if not f or not f:IsShown() then return end
    local list = DH.Batch.list
    local n = #list
    f.offset = math.min(f.offset, math.max(0, n - ROWS))
    local nextE = DH.Batch:GetNext()
    for i = 1, ROWS do
        local row = f.rows[i]
        local e = list[f.offset + i]
        if e then
            row.entry = e
            row.icon:SetTexture(e.icon)
            local r, g, b = 1, 1, 1
            if e.quality and C_Item and C_Item.GetItemQualityColor then
                local ok, cr, cg, cb = pcall(C_Item.GetItemQualityColor, e.quality)
                if ok and cr then r, g, b = cr, cg, cb end
            elseif e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality] then
                local c = ITEM_QUALITY_COLORS[e.quality]
                r, g, b = c.r, c.g, c.b
            end
            row.name:SetText(e.name)
            row.name:SetTextColor(r, g, b)
            row.count:SetText((e.count or 1) .. "개")
            row.mark:SetShown(e == nextE)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    f.empty:SetShown(n == 0)
    if n > ROWS then
        f.pageText:SetText(string.format("%d-%d / %d  (마우스 휠로 이동)", f.offset + 1, math.min(n, f.offset + ROWS), n))
    else
        f.pageText:SetText("")
    end
    f.countText:SetText("선택된 아이템: |cffffffff" .. n .. "개|r")
    f.remainText:SetText(string.format("남은 아이템: |cffffffff%d개|r    추출 완료: |cff33ff33%d개|r", n, DH.Batch.completed))
    f.statusText:SetText(DH.Batch:GetStatusText())
    f.cast:SetEnabled(n > 0)
end

function UI:ToggleBatchWindow()
    self:CreateBatchWindow()
    if InCombatLockdown() then
        DH:Print("전투 중에는 일괄 추출 창을 열거나 닫을 수 없습니다.")
        return
    end
    if self.window:IsShown() then
        self.window:Hide()
    else
        -- 일괄 추출 창은 가방과 함께 쓰는 창: 가방이 닫혀 있으면 가방도 함께 엶
        if not AnyBagShown() and OpenAllBags then pcall(OpenAllBags) end
        self.window:Show()
    end
end

---------------------------------------------------------------------------
-- 가방에 [일괄 추출] 버튼 (표시 ON/OFF 버튼이 아니라 선택 목록 창을 여는 기능 버튼)
---------------------------------------------------------------------------
function UI:GetMainBagFrame()
    local combined = _G.ContainerFrameCombinedBags
    if combined and combined:IsShown() then return combined end
    -- 기본 가방(가방 ID 0)을 보여 주는 프레임
    for _, f in ipairs(DH.Bags.GetContainerFrames()) do
        if f:IsShown() and f ~= combined then
            local id = f.GetBagID and select(2, pcall(f.GetBagID, f))
            if id == nil and f.GetID then id = f:GetID() end
            if id == 0 then return f end
        end
    end
end

-- 가방이 모두 닫히면 일괄 추출 창도 함께 닫음 (가방을 다시 열어도 자동으로 열리지 않음)
function UI:CloseWithBags()
    local f = self.window
    if not f or not f:IsShown() or AnyBagShown() then return end
    if InCombatLockdown() then return end   -- 전투 중에는 전투 시작 시 이미 닫혀 있음
    f:Hide()
end

function UI:UpdateBagButton()
    local b = self.bagButton
    if not b then return end
    local frame = DH:IsActive() and self:GetMainBagFrame() or nil
    if frame then
        b:SetParent(frame)
        b:SetFrameLevel(frame:GetFrameLevel() + 10)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -2, 6)
        b:Show()
    else
        b:Hide()
    end
end

function UI:CreateBagButton()
    if self.bagButton then return end
    local b = CreateFrame("Button", "DisenchantHelperBagButton", UIParent, "UIPanelButtonTemplate")
    b:SetSize(84, 22)
    b:SetText("일괄 추출")
    b:Hide()
    b:SetScript("OnClick", function() UI:ToggleBatchWindow() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("일괄 추출", 1, 0.82, 0)
        GameTooltip:AddLine("여러 아이템을 선택해 순서대로 마력 추출합니다.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffb84dff보라 테두리|r 추출 가능   |cff3388ff파란 테두리|r 선택된 아이템", 1, 1, 1)
        GameTooltip:AddLine((DH.MODIFIER_LABEL[DH.db.modifier] or "Alt") ..
            " + 좌클릭: 창을 열지 않고 바로 마력 추출", 0.8, 0.5, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.bagButton = b

    for _, f in ipairs(DH.Bags.GetContainerFrames()) do
        f:HookScript("OnShow", function() UI:UpdateBagButton() end)
        f:HookScript("OnHide", function()
            -- B 키 등으로 여러 가방이 차례로 닫히므로 한 프레임 뒤에 확인
            C_Timer.After(0, function()
                UI:UpdateBagButton()
                UI:CloseWithBags()
            end)
        end)
    end
end

---------------------------------------------------------------------------
-- 복사 창 (진단 / 오류 내용을 Ctrl+C 로 복사해 제보)
---------------------------------------------------------------------------
function UI:ShowCopyBox(titleText, text)
    if not self.copy then
        local f = CreateFrame("Frame", "DisenchantHelperCopyFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(460, 320)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -32)
        sf:SetPoint("BOTTOMRIGHT", -30, 40)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject("ChatFontNormal")
        eb:SetWidth(410)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hint:SetPoint("BOTTOMLEFT", 14, 16)
        hint:SetText("Ctrl+A 로 전체 선택, Ctrl+C 로 복사해서 전달해 주세요.")
        f.eb = eb
        self.copy = f
        tinsert(UISpecialFrames, "DisenchantHelperCopyFrame")
    end
    local f = self.copy
    local title = f.TitleText or f.title
    if title then title:SetText(titleText) end
    f.eb:SetText(text or "")
    f:Show()
    f.eb:SetFocus()
    f.eb:HighlightText()
end

---------------------------------------------------------------------------
-- 이벤트
---------------------------------------------------------------------------
DH:On("INIT", function()
    UI:CreateBagButton()
    UI:CreateBatchWindow()
    UI:UpdateBagButton()
end)

DH:On("SELECTION_CHANGED", function() UI:RefreshBatchWindow() end)
DH:On("ACTIVE_CHANGED", function()
    UI:UpdateBagButton()
    if not DH:IsActive() and UI.window and UI.window:IsShown() and not InCombatLockdown() then UI.window:Hide() end
end)
DH:On("BATCH_STATUS", function() UI:RefreshBatchWindow() end)
DH:On("ITEM_DATA_READY", function() UI:RefreshBatchWindow() end)

DH:RegisterEvent("BAG_OPEN", function() C_Timer.After(0, function() UI:UpdateBagButton() end) end)

-- 전투 시작 직전(잠금 전)에 창을 닫음: 보안 버튼이 포함된 창은 전투 중 숨길 수 없기 때문
-- 선택 목록은 유지되므로 전투 후 다시 열면 이어서 진행할 수 있음
DH:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if UI.window and UI.window:IsShown() then
        UI.window:Hide()
        UI.closedByCombat = true
    end
end)
DH:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if UI.closedByCombat then
        UI.closedByCombat = nil
        if DH.Batch:Count() > 0 then
            DH:Print("전투가 끝났습니다. 가방의 [일괄 추출] 버튼으로 이어서 진행할 수 있습니다.")
        end
    end
end)
