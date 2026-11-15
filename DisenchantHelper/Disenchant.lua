-- DisenchantHelper / Disenchant.lua
-- 마력 추출 가능 여부 판별 엔진 (경매장 / 인벤토리 / 일괄 추출 공통)
--
-- 판별 결과는 세 가지 상태: YES(가능) / NO(불가능) / UNKNOWN(미확인)
-- 원칙
--   * 실제 마력 추출 주문을 실행해 검사하지 않는다. 아이템을 소비하지 않는다.
--   * API로 확인되는 정보(품질, 아이템 분류, 장착 부위, 아이템 레벨, 귀속 유형)를 우선한다.
--   * 툴팁에 마력 추출 관련 문구가 있으면 보조 근거로 사용한다 (있으면 규칙보다 우선).
--   * 확인할 수 없는 정보는 추측하지 않고 UNKNOWN 으로 둔다. UNKNOWN 은 "가능"으로 표시하지 않는다.

local _, DH = ...
local API = DH.API

local Engine = {}
DH.Engine = Engine

local YES, NO, UNKNOWN = "YES", "NO", "UNKNOWN"
Engine.YES, Engine.NO, Engine.UNKNOWN = YES, NO, UNKNOWN

local LABEL = { YES = "추출 가능", NO = "추출 불가", UNKNOWN = "미확인" }
local COLOR = { YES = { 0.2, 1, 0.2 }, NO = { 1, 0.35, 0.35 }, UNKNOWN = { 0.7, 0.7, 0.7 } }
function Engine.Label(state) return LABEL[state] or LABEL.UNKNOWN end
function Engine.Color(state) local c = COLOR[state] or COLOR.UNKNOWN; return c[1], c[2], c[3] end

---------------------------------------------------------------------------
-- 아이템 분류 상수 (Enum 이 있으면 Enum 사용)
---------------------------------------------------------------------------
local E = Enum or {}
local IC  = E.ItemClass or {}
local IWS = E.ItemWeaponSubclass or {}
local IAS = E.ItemArmorSubclass or {}

local CLASS_WEAPON = IC.Weapon or 2
local CLASS_ARMOR  = IC.Armor or 4
local WEAPON_FISHINGPOLE = IWS.Fishingpole or 20
local WEAPON_GENERIC     = IWS.Generic or 14     -- 기타 무기(도구 등): 툴팁 근거가 없으면 미확인
local ARMOR_COSMETIC     = IAS.Cosmetic or 5

-- 마력 추출 대상이 아닌 장착 부위
local EXCLUDED_EQUIPLOC = {
    INVTYPE_BODY = true,      -- 속옷
    INVTYPE_TABARD = true,    -- 휘장
    INVTYPE_BAG = true,
    INVTYPE_QUIVER = true,
    INVTYPE_AMMO = true,
    INVTYPE_NON_EQUIP = true,
    INVTYPE_NON_EQUIP_IGNORE = true,
}

-- 마력 추출 가능한 품질: 고급(2), 희귀(3), 영웅(4)
local DE_QUALITY = { [2] = true, [3] = true, [4] = true }

local BIND_QUEST = (E.ItemBind and E.ItemBind.Quest) or 4

---------------------------------------------------------------------------
-- 툴팁 문구 패턴 (클라이언트의 한국어 GlobalStrings 그대로 사용, 문자열 하드코딩 안 함)
---------------------------------------------------------------------------
local function FormatToPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%d?%$?s", "(.+)")
    p = p:gsub("%%%d?%$?d", "(%%d+)")
    return "^" .. p .. "$"
end

local TIP_NOT_DE = _G.ITEM_DISENCHANT_NOT_DISENCHANTABLE
local TIP_ANY    = _G.ITEM_DISENCHANT_ANY_SKILL
local TIP_MIN_PATTERN = FormatToPattern(_G.ITEM_DISENCHANT_MIN_SKILL)

-- 색상 코드(|cffxxxxxx ... |r)와 앞뒤 공백 제거
local function CleanText(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|n", " "):gsub("[\r\n\t]", " ")
    text = text:gsub("\194\160", " ")              -- 줄바꿈 없는 공백(NBSP)
    text = text:gsub("\226\128[\139-\141]", "")    -- 폭 없는 공백(U+200B~200D)
    text = text:gsub("\239\187\191", "")           -- BOM
    text = text:gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local TIP_NOT_DE_CLEAN = TIP_NOT_DE and CleanText(TIP_NOT_DE)
local TIP_ANY_CLEAN = TIP_ANY and CleanText(TIP_ANY)

-- 한 줄 분류: NO / YES, 요구 숙련도 / nil
local function ClassifyLine(text)
    if type(text) ~= "string" or text == "" or API.IsSecret(text) then return nil end
    text = CleanText(text)
    if TIP_NOT_DE_CLEAN and TIP_NOT_DE_CLEAN ~= "" then
        if text == TIP_NOT_DE_CLEAN then return NO end
        -- 앞뒤에 다른 글자가 붙은 경우도 인정 (이 애드온의 "마력 추출: ..." 줄은 제외)
        if not text:find("^마력 추출:") and text:find(TIP_NOT_DE_CLEAN, 1, true) then return NO end
    end
    if TIP_ANY_CLEAN and text == TIP_ANY_CLEAN then return YES, nil end
    if TIP_ANY and text == TIP_ANY then return YES, nil end
    if TIP_MIN_PATTERN then
        local a, b = text:match(TIP_MIN_PATTERN)
        local lvl = tonumber(b) or tonumber(a)
        if lvl then return YES, lvl end
    end
    return nil
end
Engine.ClassifyLine = ClassifyLine

-- 툴팁 데이터(C_TooltipInfo) 검사. 반환: nil(근거 없음) / NO / YES, 요구 숙련도
local function ScanTooltipData(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        if line.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then
            pcall(TooltipUtil.SurfaceArgs, line)
        end
        local s, lvl = ClassifyLine(line.leftText)
        if s then return s, lvl end
    end
    return nil
end
Engine.ScanTooltipData = ScanTooltipData

-- 화면에 그려지는 툴팁 글줄 검사 (GameTooltip 계열)
local function ScanTooltipFrame(tooltip)
    if not tooltip or not tooltip.NumLines then return nil end
    local name = tooltip:GetName()
    if not name then return nil end
    for i = 1, tooltip:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        if fs then
            local ok, text = pcall(fs.GetText, fs)
            if ok then
                local s, lvl = ClassifyLine(text)
                if s then return s, lvl end
            end
        end
    end
    return nil
end
Engine.ScanTooltipFrame = ScanTooltipFrame

-- 숨겨진 검사용 툴팁: 실제 게임 툴팁과 똑같이 만들어서 글줄을 읽음
-- (C_TooltipInfo 데이터에 없는 줄도 화면 툴팁에는 들어가는 경우를 대비)
local scanTip
local function ScanWithHiddenTooltip(setter)
    if not setter then return nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "DisenchantHelperScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    local ok = pcall(setter, scanTip)
    local s, lvl, n
    if ok then
        n = scanTip:NumLines()
        s, lvl = ScanTooltipFrame(scanTip)
    end
    scanTip:Hide()
    return s, lvl, n
end
Engine.ScanWithHiddenTooltip = ScanWithHiddenTooltip

---------------------------------------------------------------------------
-- 학습 기록: 게임 툴팁에 실제로 표시된 마력 추출 문구를 itemID 단위로 기억
-- (마력 추출 가능 여부는 아이템 종류(itemID)마다 고정이므로 경매장 판별에도 그대로 사용)
---------------------------------------------------------------------------
local function GetLearned(itemID)
    local db = DH.db and DH.db.learned
    return db and db[itemID]
end

---------------------------------------------------------------------------
-- 클래식 규칙 기반 요구 숙련도 (툴팁에 요구 숙련도가 없을 때만 사용)
-- 아이템 레벨 20 이하: 1 / 21~25: 25 / 이후 5레벨마다 +25 / 56~60: 200 / 61 이상: 225
---------------------------------------------------------------------------
local function RuleRequiredSkill(ilvl)
    if type(ilvl) ~= "number" or ilvl <= 0 then return nil end
    if ilvl <= 20 then return 1 end
    if ilvl <= 60 then return math.floor((ilvl - 21) / 5) * 25 + 25 end
    return 225
end
Engine.RuleRequiredSkill = RuleRequiredSkill

---------------------------------------------------------------------------
-- 캐시
---------------------------------------------------------------------------
local itemCache = {}      -- 아이템 단위 판별 결과 (플레이어 조건 제외)  key -> result
local finalCache = {}     -- 최종 판별 결과  key -> result
local pendingItems = {}   -- 정보 로딩 대기 중인 itemID
local lowSkillFail = {}   -- 실제 시도에서 숙련도 부족 오류가 난 itemID -> 그때의 숙련도
local playerStatus        -- 플레이어 상태 캐시

function Engine:ClearCache()
    wipe(itemCache)
    wipe(finalCache)
end

local function Result(state, reason, reqSkill, source)
    return { state = state, reason = reason, reqSkill = reqSkill, source = source }
end

local function MarkPending(itemID)
    if itemID and not pendingItems[itemID] then
        pendingItems[itemID] = true
        API.RequestItem(itemID)
    end
end

---------------------------------------------------------------------------
-- 플레이어 상태: 마력 추출 습득 여부 / 마법부여 숙련도
---------------------------------------------------------------------------
local function FindEnchantingSkill()
    local enchName = API.GetSpellName(DH.ENCHANTING_SPELL_ID) or "마법부여"
    -- 1) 리테일 방식 전문기술 API
    if GetProfessions and GetProfessionInfo then
        local ok, p1, p2 = pcall(GetProfessions)
        if ok then
            for _, idx in ipairs({ p1, p2 }) do
                if idx then
                    local ok2, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, idx)
                    if ok2 and (skillLine == DH.ENCHANTING_SKILL_LINE or name == enchName or name == "마법부여") then
                        if type(rank) == "number" and not API.IsSecret(rank) then
                            return rank, maxRank, "GetProfessionInfo"
                        end
                    end
                end
            end
        end
    end
    -- 2) 클래식 방식 기술 목록 API
    if GetNumSkillLines and GetSkillLineInfo then
        local ok, n = pcall(GetNumSkillLines)
        if ok and n then
            for i = 1, n do
                local ok2, name, isHeader, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
                if ok2 and not isHeader and (name == enchName or name == "마법부여") then
                    return rank, maxRank, "GetSkillLineInfo"
                end
            end
        end
    end
    return nil, nil, nil
end

function Engine:GetPlayerStatus(force)
    if playerStatus and not force then return playerStatus end
    local knows = API.IsSpellKnown(DH.DISENCHANT_SPELL_ID)
    local skill, maxSkill, source = FindEnchantingSkill()
    if knows == nil and skill then knows = true end
    if knows == false and skill and skill > 0 then knows = true end  -- 주문 확인 API 오동작 대비
    playerStatus = { knowsDE = knows, skill = skill, maxSkill = maxSkill, skillSource = source }
    return playerStatus
end

local function InvalidatePlayer()
    local old = playerStatus
    playerStatus = nil
    local new = Engine:GetPlayerStatus()
    if old and old.knowsDE ~= new.knowsDE then
        DH:FireThrottled("ACTIVE_CHANGED", 0.2)
    end
    if not old or old.knowsDE ~= new.knowsDE or old.skill ~= new.skill then
        wipe(finalCache)
        if old and old.skill ~= new.skill then wipe(lowSkillFail) end
        DH:FireThrottled("DATA_CHANGED", 0.2)
    end
end

-- 툴팁에서 확인한 마력 추출 문구를 itemID 단위로 기록
-- silent = true: 판별 도중 기록 (캐시/갱신 건드리지 않음)
-- silent = false: 화면 툴팁에서 새로 알게 된 경우 → 캐시 비우고 가방/경매장 다시 표시
function Engine:Learn(itemID, state, reqSkill, silent)
    if not itemID or (state ~= YES and state ~= NO) or not DH.db then return false end
    DH.db.learned = DH.db.learned or {}
    local old = DH.db.learned[itemID]
    if old and old.s == state and old.req == reqSkill then return false end
    DH.db.learned[itemID] = { s = state, req = reqSkill }
    if not silent then
        self:ClearCache()
        DH:FireThrottled("DATA_CHANGED", 0.1)
    end
    return true
end

function Engine:GetLearned(itemID) return GetLearned(itemID) end

function Engine:MarkLowSkill(itemID)
    if not itemID then return end
    local p = self:GetPlayerStatus()
    lowSkillFail[itemID] = p.skill or 0
    wipe(finalCache)
    DH:FireThrottled("DATA_CHANGED", 0.1)
end

---------------------------------------------------------------------------
-- 아이템 단위 판별 (플레이어 조건 제외)
-- info = { itemID, link, quality, ilvl, getTooltip = function() return tooltipData end }
---------------------------------------------------------------------------
function Engine:EvaluateItem(key, info)
    if key and itemCache[key] then return itemCache[key] end

    local itemID = info.itemID
    if not itemID and info.link then
        itemID = tonumber(info.link:match("item:(%d+)"))
    end
    if not itemID then return Result(UNKNOWN, "아이템 정보 없음") end

    if DH.db and DH.db.excluded and DH.db.excluded[itemID] then
        local r = Result(NO, "사용자 제외 목록")
        if key then itemCache[key] = r end
        return r
    end

    -- 1) 분류 / 장착 부위 (즉시 확인 가능한 정보)
    local _, _, _, equipLoc, _, classID, subClassID = API.GetItemInfoInstant(info.link or itemID)
    if not classID then
        MarkPending(itemID)
        return Result(UNKNOWN, "아이템 정보 로딩 중")
    end
    if classID ~= CLASS_WEAPON and classID ~= CLASS_ARMOR then
        local r = Result(NO, "장비 아님", nil, "API")
        r.notGear = true
        if key then itemCache[key] = r end
        return r
    end
    if equipLoc == nil or equipLoc == "" or EXCLUDED_EQUIPLOC[equipLoc] then
        local r = Result(NO, "마력 추출 대상 부위 아님", nil, "API")
        if key then itemCache[key] = r end
        return r
    end
    if classID == CLASS_ARMOR and subClassID == ARMOR_COSMETIC then
        local r = Result(NO, "외형 아이템", nil, "API")
        if key then itemCache[key] = r end
        return r
    end
    if classID == CLASS_WEAPON and subClassID == WEAPON_FISHINGPOLE then
        local r = Result(NO, "낚싯대", nil, "API")
        if key then itemCache[key] = r end
        return r
    end

    -- 2) 품질
    local quality = info.quality
    if quality == nil or API.IsSecret(quality) then quality = API.GetItemQualityByID(itemID) end
    if quality == nil then
        MarkPending(itemID)
        return Result(UNKNOWN, "품질 정보 로딩 중")
    end
    if not DE_QUALITY[quality] then
        local r = Result(NO, quality < 2 and "일반 등급 이하" or "추출 불가 등급", nil, "API")
        if key then itemCache[key] = r end
        return r
    end

    -- 3) 전체 아이템 정보 (귀속 유형 확인)
    local name, _, _, baseLevel, _, _, _, _, _, _, _, _, _, bindType = API.GetItemInfo(info.link or itemID)
    if not name then
        MarkPending(itemID)
        return Result(UNKNOWN, "아이템 정보 로딩 중")
    end
    if bindType == BIND_QUEST then
        local r = Result(NO, "퀘스트 아이템", nil, "API")
        if key then itemCache[key] = r end
        return r
    end

    -- 4) 아이템 레벨
    local ilvl = info.ilvl
    if (not ilvl or ilvl <= 0) and info.link then ilvl = API.GetDetailedItemLevel(info.link) end
    if not ilvl or ilvl <= 0 then ilvl = baseLevel end

    -- 5) 툴팁 근거 (있으면 규칙보다 우선)
    --    우선순위: 학습 기록(실제 표시된 툴팁) > 숨겨진 검사용 툴팁 > 툴팁 데이터
    local tipState, tipSkill
    local learned = GetLearned(itemID)
    if learned then
        tipState, tipSkill = learned.s, learned.req
    end
    if not tipState and info.setTooltip then
        tipState, tipSkill = ScanWithHiddenTooltip(info.setTooltip)
    end
    if not tipState and info.getTooltip then
        tipState, tipSkill = ScanTooltipData(info.getTooltip())
    end
    if tipState then Engine:Learn(itemID, tipState, tipSkill, true) end
    if tipState == NO then
        local r = Result(NO, "툴팁: 마력 추출 불가", nil, "툴팁")
        if key then itemCache[key] = r end
        return r
    end
    if tipState == YES then
        local r = Result(YES, "툴팁 확인", tipSkill or RuleRequiredSkill(ilvl), "툴팁")
        r.ilvl = ilvl
        if key then itemCache[key] = r end
        return r
    end

    -- 6) 툴팁 근거가 없을 때: 기타 무기는 판단 근거 부족 → 미확인
    if classID == CLASS_WEAPON and subClassID == WEAPON_GENERIC then
        local r = Result(UNKNOWN, "기타 무기 (판별 근거 부족)", nil, "API")
        if key then itemCache[key] = r end
        return r
    end

    -- 7) 규칙 기반 판정
    if not ilvl or ilvl <= 0 then
        return Result(UNKNOWN, "아이템 레벨 확인 불가")
    end
    local r = Result(YES, "규칙 기반 판정", RuleRequiredSkill(ilvl), "규칙")
    r.ilvl = ilvl
    if key then itemCache[key] = r end
    return r
end

---------------------------------------------------------------------------
-- 최종 판별 (아이템 조건 + 플레이어 조건)
---------------------------------------------------------------------------
function Engine:Evaluate(key, info)
    if key and finalCache[key] then return finalCache[key] end
    local item = self:EvaluateItem(key, info)
    if item.state ~= YES then
        if key and item.state ~= UNKNOWN then finalCache[key] = item end
        return item
    end

    local p = self:GetPlayerStatus()
    local r
    local itemID = info.itemID or (info.link and tonumber(info.link:match("item:(%d+)")))
    if p.knowsDE == false then
        r = Result(NO, "마법부여 미습득", item.reqSkill, item.source)
        r.itemOK = true
    elseif itemID and lowSkillFail[itemID] and (p.skill or 0) <= lowSkillFail[itemID] then
        r = Result(NO, "숙련도 부족 (실제 시도 결과)", item.reqSkill, item.source)
        r.itemOK = true
    elseif p.skill and item.reqSkill and p.skill < item.reqSkill then
        r = Result(NO, string.format("숙련도 부족 (필요 %d / 현재 %d)", item.reqSkill, p.skill), item.reqSkill, item.source)
        r.itemOK = true
    else
        local reason = item.reason
        if not p.skill then reason = reason .. ", 숙련도 확인 불가" end
        r = Result(YES, reason, item.reqSkill, item.source)
    end
    r.ilvl = item.ilvl
    if key then finalCache[key] = r end
    return r
end

-- 가방 칸 판별 (인벤토리 / 일괄 추출 공통)
function Engine:EvaluateBagSlot(bag, slot, slotInfo)
    slotInfo = slotInfo or API.GetSlotInfo(bag, slot)
    if not slotInfo or not slotInfo.itemID then
        return Result(NO, "빈 칸"), nil
    end
    local key = slotInfo.link or ("id:" .. slotInfo.itemID)
    local res = self:Evaluate(key, {
        itemID = slotInfo.itemID,
        link = slotInfo.link,
        quality = slotInfo.quality,
        getTooltip = function() return API.GetBagItemTooltipData(bag, slot) end,
        setTooltip = function(tt) tt:SetBagItem(bag, slot) end,
    })
    return res, slotInfo
end

-- 링크 판별 (툴팁 표시용)
function Engine:EvaluateLink(link)
    if type(link) ~= "string" or API.IsSecret(link) then return nil end
    return self:Evaluate(link, {
        link = link,
        getTooltip = function() return API.GetLinkTooltipData(link) end,
        setTooltip = function(tt) tt:SetHyperlink(link) end,
    })
end

-- 경매장 itemKey 판별
-- 경매장 결과는 소지 아이템이 아니므로 가방 아이템과 달리 itemID, itemLevel, itemSuffix 만 확인 가능
function Engine:EvaluateItemKey(itemKey)
    if type(itemKey) ~= "table" or not itemKey.itemID then return Result(UNKNOWN, "아이템 키 없음") end
    if itemKey.battlePetSpeciesID and itemKey.battlePetSpeciesID ~= 0 then
        return Result(NO, "애완동물")
    end
    local key = "K:" .. itemKey.itemID .. ":" .. (itemKey.itemLevel or 0) .. ":" .. (itemKey.itemSuffix or 0)
    return self:Evaluate(key, {
        itemID = itemKey.itemID,
        ilvl = itemKey.itemLevel,
        getTooltip = function()
            return API.GetItemKeyTooltipData(itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix)
        end,
        setTooltip = function(tt)
            if tt.SetItemKey then
                tt:SetItemKey(itemKey.itemID, itemKey.itemLevel or 0, itemKey.itemSuffix or 0)
            else
                tt:SetItemByID(itemKey.itemID)
            end
        end,
    })
end

---------------------------------------------------------------------------
-- 이벤트
---------------------------------------------------------------------------
DH:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, itemID)
    if itemID and pendingItems[itemID] then
        pendingItems[itemID] = nil
        DH:FireThrottled("ITEM_DATA_READY", 0.2)
    end
end)

DH:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, itemID)
    if itemID and pendingItems[itemID] then
        pendingItems[itemID] = nil
        DH:FireThrottled("ITEM_DATA_READY", 0.2)
    end
end)

for _, ev in ipairs({ "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "TRADE_SKILL_LIST_UPDATE" }) do
    DH:RegisterEvent(ev, function() InvalidatePlayer() end)
end

DH:On("INIT", function()
    Engine:GetPlayerStatus(true)
end)
