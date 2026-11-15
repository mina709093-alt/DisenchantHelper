-- DisenchantHelper / Core.lua
-- 애드온 초기화, 이벤트 관리, 공통 기능, API 호환 계층

local ADDON_NAME, DH = ...
_G.DisenchantHelper = DH

DH.version = "1.0.8"
DH.DISENCHANT_SPELL_ID = 13262   -- 마력 추출
DH.ENCHANTING_SPELL_ID = 7411    -- 마법부여 (전문기술 이름 확인용)
DH.ENCHANTING_SKILL_LINE = 333   -- 마법부여 skillLine

DH.PREFIX = "|cff33ff99[마력 추출 도우미]|r "

-- 단축키 설정 화면 표시 이름
BINDING_HEADER_DISENCHANTHELPER = "마력 추출 도우미"
_G["BINDING_NAME_CLICK DisenchantHelperBatchCastButton:LeftButton"] = "선택 아이템 추출 (다음 아이템)"

local DEFAULTS = {
    modifier = "ALT",      -- 단축키+좌클릭 추출 조합키 (ALT / SHIFT / CTRL)
    excluded = {},         -- 사용자가 지정한 마력 추출 제외 아이템 (itemID = true)
    learned = {},          -- 툴팁에서 확인한 마력 추출 문구 (itemID = { s = YES/NO, req = 숙련도 })
    batchPos = nil,        -- 일괄 추출 창 위치
}

---------------------------------------------------------------------------
-- 출력 / 오류 기록
---------------------------------------------------------------------------
function DH:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(DH.PREFIX .. tostring(msg))
end

DH.errors = {}
local errorSeen = {}
function DH:ReportError(err)
    err = tostring(err)
    if errorSeen[err] then return end
    errorSeen[err] = true
    table.insert(DH.errors, err)
    if #DH.errors <= 3 then
        DH:Print("|cffff5555오류가 발생했습니다.|r /dh 오류 를 입력하면 내용을 복사할 수 있습니다.")
    end
end

function DH:SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then DH:ReportError(err) end
    return ok
end

---------------------------------------------------------------------------
-- 게임 이벤트 관리 (이벤트 기반 동작, OnUpdate 사용 안 함)
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function DH:RegisterEvent(event, fn)
    if not handlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return false end   -- 이 클라이언트에 없는 이벤트
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then DH:ReportError(event .. ": " .. tostring(err)) end
    end
end)

---------------------------------------------------------------------------
-- 내부 메시지 (모듈 간 통신)
---------------------------------------------------------------------------
local callbacks = {}
function DH:On(msg, fn)
    callbacks[msg] = callbacks[msg] or {}
    table.insert(callbacks[msg], fn)
end

function DH:Fire(msg, ...)
    local list = callbacks[msg]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then DH:ReportError(msg .. ": " .. tostring(err)) end
    end
end

-- 짧은 시간에 여러 번 요청돼도 한 번만 실행 (C_Timer 1회성 타이머)
local throttled = {}
function DH:FireThrottled(msg, delay)
    if throttled[msg] then return end
    throttled[msg] = true
    C_Timer.After(delay or 0.1, function()
        throttled[msg] = nil
        DH:Fire(msg)
    end)
end

---------------------------------------------------------------------------
-- API 호환 계층: Interface 16001(Midnight 계열 엔진) 우선, 없으면 구 API
---------------------------------------------------------------------------
local API = {}
DH.API = API

function API.IsSecret(v)
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        if ok and res then return true end
    end
    return false
end

function API.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    if GetItemInfo then return GetItemInfo(item) end
end

function API.GetItemInfoInstant(item)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(item) end
    if GetItemInfoInstant then return GetItemInfoInstant(item) end
end

function API.GetItemQualityByID(itemID)
    if C_Item and C_Item.GetItemQualityByID then
        local q = C_Item.GetItemQualityByID(itemID)
        if q then return q end
    end
    local _, _, q = API.GetItemInfo(itemID)
    return q
end

function API.GetDetailedItemLevel(link)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, lvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok and lvl then return lvl end
    end
    if GetDetailedItemLevelInfo then
        local ok, lvl = pcall(GetDetailedItemLevelInfo, link)
        if ok and lvl then return lvl end
    end
    local _, _, _, lvl = API.GetItemInfo(link)
    return lvl
end

function API.RequestItem(itemID)
    if not itemID then return end
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

function API.GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and name then return name end
    end
end

-- true / false / nil(확인 불가)
function API.IsSpellKnown(spellID)
    local result
    local function try(fn, ...)
        if result ~= nil or type(fn) ~= "function" then return end
        local ok, res = pcall(fn, ...)
        if ok and type(res) == "boolean" then result = res end
    end
    try(IsPlayerSpell, spellID)
    if result == false then
        -- IsPlayerSpell 이 false 여도 다른 API로 한 번 더 확인
        result = nil
        try(C_SpellBook and C_SpellBook.IsSpellKnown, spellID)
        try(IsSpellKnown, spellID)
        if result == nil then result = false end
    else
        try(C_SpellBook and C_SpellBook.IsSpellKnown, spellID)
        try(IsSpellKnown, spellID)
    end
    return result
end

-- 가방 목록 (기본 가방 0 + 장착 가방 슬롯)
function API.GetBagList()
    local list = {}
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do list[#list + 1] = bag end
    return list
end

function API.GetNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
    return 0
end

-- 가방 칸 정보: { link, itemID, count, icon, locked, quality, bound } 또는 nil
function API.GetSlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return {
            link = info.hyperlink, itemID = info.itemID, count = info.stackCount or 1,
            icon = info.iconFileID, locked = info.isLocked, quality = info.quality, bound = info.isBound,
        }
    end
    if GetContainerItemInfo then
        local icon, count, locked, quality, _, _, link, _, _, itemID, bound = GetContainerItemInfo(bag, slot)
        if not icon then return nil end
        return { link = link, itemID = itemID, count = count or 1, icon = icon, locked = locked, quality = quality, bound = bound }
    end
end

function API.GetItemGUID(bag, slot)
    if ItemLocation and C_Item and C_Item.GetItemGUID and C_Item.DoesItemExist then
        local ok, guid = pcall(function()
            local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
            if C_Item.DoesItemExist(loc) then return C_Item.GetItemGUID(loc) end
        end)
        if ok and type(guid) == "string" and not API.IsSecret(guid) then return guid end
    end
end

function API.GetBagItemTooltipData(bag, slot)
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        if ok then return data end
    end
end

function API.GetLinkTooltipData(link)
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok then return data end
    end
end

function API.GetItemKeyTooltipData(itemID, itemLevel, itemSuffix)
    if C_TooltipInfo and C_TooltipInfo.GetItemKey then
        local ok, data = pcall(C_TooltipInfo.GetItemKey, itemID, itemLevel or 0, itemSuffix or 0)
        if ok and data then return data end
    end
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok then return data end
    end
end

-- 마법부여(마력 추출)를 배운 캐릭터에서만 애드온 기능이 켜짐
-- 배우지 않은 캐릭터: 테두리, 툴팁 줄, 가방 버튼, 경매장 체크박스, 단축키 추출 모두 꺼짐
-- 나중에 마법부여를 배우면 자동으로 켜짐 (켜고 끄는 버튼 없음)
function DH:IsActive()
    if not DH.Engine then return false end
    local p = DH.Engine:GetPlayerStatus()
    return p and p.knowsDE == true
end

function API.ModifierDown(mod)
    if mod == "SHIFT" then return IsShiftKeyDown() end
    if mod == "CTRL" then return IsControlKeyDown() end
    return IsAltKeyDown()
end

DH.MODIFIER_LABEL = { ALT = "Alt", SHIFT = "Shift", CTRL = "Ctrl" }

-- 보안 버튼에 "마력 추출 → 가방 bag 칸 slot" 지정
-- 보안 버튼은 조합키(Alt/Shift/Ctrl)를 누르고 있으면 "type1" 대신 "alt-type1" / "*type1" 을 찾는다.
-- 그래서 어떤 조합키에도 적용되는 "*" 접두어 속성과 접두어 없는 속성을 함께 지정한다.
local CAST_ATTRS = { "type", "spell", "target-bag", "target-slot", "target-item" }
function DH:SetCastAttributes(button, bag, slot)
    if InCombatLockdown() then return false end
    if bag and slot then
        local values = {
            ["type"] = "spell",
            ["spell"] = DH.DISENCHANT_SPELL_ID,
            ["target-bag"] = bag,
            ["target-slot"] = slot,
            ["target-item"] = nil,
        }
        for _, name in ipairs(CAST_ATTRS) do
            local v = values[name]
            button:SetAttribute(name, v)
            button:SetAttribute(name .. "1", v)
            button:SetAttribute("*" .. name .. "1", v)
        end
    else
        for _, name in ipairs(CAST_ATTRS) do
            button:SetAttribute(name, nil)
            button:SetAttribute(name .. "1", nil)
            button:SetAttribute("*" .. name .. "1", nil)
        end
    end
    return true
end

---------------------------------------------------------------------------
-- 초기화
---------------------------------------------------------------------------
DH:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    DisenchantHelperDB = DisenchantHelperDB or {}
    for k, v in pairs(DEFAULTS) do
        if DisenchantHelperDB[k] == nil then
            DisenchantHelperDB[k] = type(v) == "table" and {} or v
        end
    end
    DH.db = DisenchantHelperDB
end)

DH:RegisterEvent("PLAYER_LOGIN", function()
    if not DH.db then
        DisenchantHelperDB = DisenchantHelperDB or {}
        DH.db = DisenchantHelperDB
        for k, v in pairs(DEFAULTS) do
            if DH.db[k] == nil then DH.db[k] = type(v) == "table" and {} or v end
        end
    end
    DH:Fire("INIT")
end)

---------------------------------------------------------------------------
-- 슬래시 명령
---------------------------------------------------------------------------
local function ShowHelp()
    DH:Print("명령어 안내")
    DH:Print("  /dh  - 일괄 추출 창 열기/닫기")
    DH:Print("  /dh 키 alt | shift | ctrl  - 단축키+좌클릭 추출 조합키 변경 (현재: " ..
        (DH.MODIFIER_LABEL[DH.db.modifier] or "Alt") .. ")")
    DH:Print("  /dh 제외 [아이템 링크]  - 마력 추출 제외 목록에 추가/삭제")
    DH:Print("  /dh 진단  - 기술 진단 정보 (버그 제보용, 복사 가능)")
    DH:Print("  /dh 툴팁  - 가방 아이템에 마우스를 올린 채 입력: 판별 근거 확인")
    DH:Print("  /dh 오류  - 발생한 오류 내용 복사")
end

SLASH_DISENCHANTHELPER1 = "/dh"
SLASH_DISENCHANTHELPER2 = "/마추"
SLASH_DISENCHANTHELPER3 = "/disenchanthelper"
SlashCmdList["DISENCHANTHELPER"] = function(input)
    input = strtrim(input or "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if not DH:IsActive() and cmd ~= "진단" and cmd ~= "diag" and cmd ~= "오류" and cmd ~= "error" then
        DH:Print("마법부여를 배우지 않은 캐릭터라 꺼져 있습니다. 마법부여를 배우면 자동으로 켜집니다.")
        return
    end
    if cmd == "" then
        if DH.UI and DH.UI.ToggleBatchWindow then DH.UI:ToggleBatchWindow() end
        ShowHelp()
    elseif cmd == "키" or cmd == "key" then
        local m = (rest or ""):upper()
        if m == "ALT" or m == "SHIFT" or m == "CTRL" then
            DH.db.modifier = m
            DH:Print("단축키+좌클릭 추출 조합키: " .. DH.MODIFIER_LABEL[m] .. " + 좌클릭")
            DH:Fire("MODIFIER_CHANGED")
        else
            DH:Print("사용법: /dh 키 alt  또는  /dh 키 shift  또는  /dh 키 ctrl")
        end
    elseif cmd == "제외" or cmd == "exclude" then
        local itemID = rest and tonumber(rest:match("item:(%d+)") or rest:match("^(%d+)$"))
        if not itemID then
            DH:Print("사용법: /dh 제외 [아이템 링크]  (채팅창에 Shift+클릭으로 링크 입력)")
            return
        end
        if DH.db.excluded[itemID] then
            DH.db.excluded[itemID] = nil
            DH:Print("제외 목록에서 삭제했습니다: " .. rest)
        else
            DH.db.excluded[itemID] = true
            DH:Print("마력 추출 제외 목록에 추가했습니다: " .. rest)
        end
        DH.Engine:ClearCache()
        DH:Fire("DATA_CHANGED")
    elseif cmd == "진단" or cmd == "diag" then
        if DH.UI then DH.UI:ShowCopyBox("진단 정보", DH:BuildDiagnostics()) end
    elseif cmd == "툴팁" or cmd == "tip" then
        if DH.UI then DH.UI:ShowCopyBox("툴팁 진단", DH:BuildTooltipDiagnostics()) end
    elseif cmd == "오류" or cmd == "error" then
        local text = #DH.errors > 0 and table.concat(DH.errors, "\n\n") or "기록된 오류가 없습니다."
        if DH.UI then DH.UI:ShowCopyBox("오류 기록", "DisenchantHelper " .. DH.version .. "\n\n" .. text) end
    else
        ShowHelp()
    end
end

---------------------------------------------------------------------------
-- 툴팁 진단: 마우스를 올린 가방 아이템의 판별 근거를 경로별로 보여 줌
---------------------------------------------------------------------------
function DH:BuildTooltipDiagnostics()
    local E = DH.Engine
    local btn = DH.Bags and DH.Bags.hoverButton
    local bag, slot
    if btn then bag, slot = DH.Bags.GetButtonBagSlot(btn) end
    if not bag then
        return "가방 아이템에 마우스를 올린 상태에서 채팅창에 /dh 툴팁 을 입력해 주세요.\n(단축키로 채팅창을 열면 마우스를 올린 채 입력할 수 있습니다)"
    end
    local info = API.GetSlotInfo(bag, slot)
    if not info then return "빈 칸입니다." end
    local L = {}
    local function add(s) L[#L + 1] = tostring(s) end
    add("아이템: " .. tostring(info.link) .. "  (itemID " .. tostring(info.itemID) .. ", 가방 " .. bag .. " 칸 " .. slot .. ")")
    add("품질: " .. tostring(info.quality))
    local _, _, _, equipLoc, _, classID, subClassID = API.GetItemInfoInstant(info.link or info.itemID)
    add("분류: " .. tostring(classID) .. "/" .. tostring(subClassID) .. "  부위: " .. tostring(equipLoc))
    local learned = E:GetLearned(info.itemID)
    add("학습 기록: " .. (learned and (learned.s .. " " .. tostring(learned.req)) or "없음"))

    add("")
    add("[1] 툴팁 데이터(C_TooltipInfo) 줄:")
    local data = API.GetBagItemTooltipData(bag, slot)
    if data and data.lines then
        for i, line in ipairs(data.lines) do
            if line.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
            local t = line.leftText
            if API.IsSecret(t) then t = "(보호 값)" end
            add(string.format("  %d [type %s] %s", i, tostring(line.type), tostring(t)))
        end
        add("  → 판정: " .. tostring((E.ScanTooltipData(data))))
    else
        add("  데이터 없음")
    end

    add("")
    add("[2] 숨겨진 검사용 툴팁:")
    local s, lvl, n = E.ScanWithHiddenTooltip(function(tt) tt:SetBagItem(bag, slot) end)
    add("  줄 수: " .. tostring(n) .. "  → 판정: " .. tostring(s) .. " " .. tostring(lvl))
    local tip = _G.DisenchantHelperScanTooltip
    if tip then
        tip:SetOwner(WorldFrame, "ANCHOR_NONE"); tip:ClearLines()
        pcall(tip.SetBagItem, tip, bag, slot)
        for i = 1, tip:NumLines() do
            local fs = _G["DisenchantHelperScanTooltipTextLeft" .. i]
            local ok, t = pcall(fs.GetText, fs)
            if ok and not API.IsSecret(t) then add(string.format("  %d %s", i, tostring(t))) end
        end
        tip:Hide()
    end

    add("")
    add("[3] 지금 화면에 떠 있는 툴팁(GameTooltip):")
    if GameTooltip:IsShown() then
        for i = 1, GameTooltip:NumLines() do
            local fs = _G["GameTooltipTextLeft" .. i]
            local ok, t = pcall(fs.GetText, fs)
            if ok and type(t) == "string" and not API.IsSecret(t) then
                local line = string.format("  %d %s", i, t)
                if t:find("추출", 1, true) then
                    local hex = {}
                    for b = 1, #t do hex[#hex + 1] = string.format("%02X", t:byte(b)) end
                    line = line .. "\n     → 판정: " .. tostring((E.ClassifyLine(t))) .. "  코드: " .. table.concat(hex, " ")
                end
                add(line)
            end
        end
    else
        add("  표시된 툴팁 없음")
    end
    local tnd = _G.ITEM_DISENCHANT_NOT_DISENCHANTABLE
    if type(tnd) == "string" then
        local hex = {}
        for b = 1, #tnd do hex[#hex + 1] = string.format("%02X", tnd:byte(b)) end
        add("  기준 문자열(추출 불가) 코드: " .. table.concat(hex, " "))
    end

    add("")
    E:ClearCache()
    local res = E:EvaluateBagSlot(bag, slot)
    add("최종 판별: " .. tostring(res.state) .. " / " .. tostring(res.reason) .. " / 근거: " .. tostring(res.source))
    return table.concat(L, "\n")
end

---------------------------------------------------------------------------
-- 진단 정보 (기술 검증 결과를 실제 클라이언트에서 확인하기 위한 용도)
---------------------------------------------------------------------------
function DH:BuildDiagnostics()
    local lines = {}
    local function add(k, v) lines[#lines + 1] = k .. ": " .. tostring(v) end
    local _, build, _, iface = GetBuildInfo()
    add("DisenchantHelper", DH.version)
    add("Interface", iface)
    add("Build", build)
    add("C_Container", C_Container ~= nil)
    add("C_TooltipInfo", C_TooltipInfo ~= nil)
    add("TooltipDataProcessor", TooltipDataProcessor ~= nil)
    add("C_AuctionHouse", C_AuctionHouse ~= nil)
    add("ItemLocation GUID", (C_Item and C_Item.GetItemGUID) ~= nil)
    add("툴팁 문자열(추출 불가)", _G.ITEM_DISENCHANT_NOT_DISENCHANTABLE or "없음")
    add("툴팁 문자열(추출 가능)", _G.ITEM_DISENCHANT_ANY_SKILL or "없음")
    add("툴팁 문자열(요구 숙련도)", _G.ITEM_DISENCHANT_MIN_SKILL or "없음")
    add("마력 추출 주문 이름", API.GetSpellName(DH.DISENCHANT_SPELL_ID) or "확인 불가")
    if DH.Engine then
        local p = DH.Engine:GetPlayerStatus(true)
        add("마력 추출 습득", p.knowsDE == nil and "확인 불가" or p.knowsDE)
        add("마법부여 숙련도", p.skill or "확인 불가")
        add("숙련도 확인 방식", p.skillSource or "없음")
    end
    if DH.Bags then add("가방 프레임 연결", DH.Bags:GetHookSummary()) end
    if DH.AH then add("경매장 필터", DH.AH:GetStatusText()) end
    if DH.Prefetch then add("사전 확인", DH.Prefetch:GetStatusText()) end
    add("동작 상태", DH:IsActive() and "켜짐" or "꺼짐 (마법부여 미습득)")
    add("조합키", DH.db and DH.db.modifier)
    add("오류 수", #DH.errors)
    return table.concat(lines, "\n")
end
