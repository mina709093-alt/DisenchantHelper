-- DisenchantHelper / BatchDisenchant.lua
-- 다수 아이템 선택, 선택 목록 관리, 추출 진행 관리
--
-- 보안 정책상 "버튼 한 번으로 여러 아이템 자동 연속 추출"은 불가능하다.
-- 마력 추출은 보호된 주문이므로 하드웨어 입력(클릭/키 입력) 1회당 시전 1회만 허용된다.
-- 따라서: [선택 아이템 추출] 보안 버튼(또는 단축키)을 누를 때마다 다음 선택 아이템 1개를 추출한다.

local _, DH = ...
local API = DH.API

local Batch = {}
DH.Batch = Batch

Batch.list = {}        -- { key, guid, itemID, link, name, icon, quality, count, bag, slot }
Batch.byKey = {}
Batch.slotIndex = {}   -- "bag:slot" -> entry
Batch.status = "IDLE"  -- IDLE / CASTING / DONE / FAILED
Batch.statusText = nil
Batch.completed = 0
Batch.pending = nil    -- 추출 시도 중인 항목

local function SlotKey(bag, slot) return bag .. ":" .. slot end

local function RebuildSlotIndex()
    wipe(Batch.slotIndex)
    for _, e in ipairs(Batch.list) do
        if e.bag and e.slot then Batch.slotIndex[SlotKey(e.bag, e.slot)] = e end
    end
end

local function Changed()
    RebuildSlotIndex()
    DH:Fire("SELECTION_CHANGED")
end

function Batch:IsSelectedSlot(bag, slot)
    return self.slotIndex[SlotKey(bag, slot)] ~= nil
end

function Batch:Count() return #self.list end

---------------------------------------------------------------------------
-- 선택 / 해제
---------------------------------------------------------------------------
local function MakeEntry(bag, slot, info)
    local guid = API.GetItemGUID(bag, slot)
    local key = guid or ("S:" .. bag .. ":" .. slot .. ":" .. (info.link or info.itemID))
    local name, _, quality, _, _, _, _, _, _, icon = API.GetItemInfo(info.link or info.itemID)
    return {
        key = key, guid = guid, itemID = info.itemID, link = info.link,
        name = name or (info.link and info.link:match("%[(.-)%]")) or ("아이템 " .. info.itemID),
        icon = info.icon or icon, quality = info.quality or quality, count = info.count or 1,
        bag = bag, slot = slot,
    }
end

function Batch:Add(bag, slot, silent)
    if self:IsSelectedSlot(bag, slot) then return false end
    local res, info = DH.Engine:EvaluateBagSlot(bag, slot)
    if res.state ~= DH.Engine.YES or not info then
        if not silent then DH:Print("마력 추출 가능으로 확인된 아이템만 선택할 수 있습니다.") end
        return false
    end
    local e = MakeEntry(bag, slot, info)
    if self.byKey[e.key] then return false end
    table.insert(self.list, e)
    self.byKey[e.key] = e
    if not silent then Changed() end
    return true
end

function Batch:RemoveEntry(e, silent)
    if not e then return end
    for i, v in ipairs(self.list) do
        if v == e then table.remove(self.list, i); break end
    end
    self.byKey[e.key] = nil
    if self.pending and self.pending.entry == e then self.pending = nil end
    if not silent then Changed() end
end

function Batch:Toggle(bag, slot)
    local e = self.slotIndex[SlotKey(bag, slot)]
    if e then self:RemoveEntry(e) else self:Add(bag, slot) end
end

function Batch:ClearAll()
    wipe(self.list); wipe(self.byKey)
    self.pending = nil
    self.completed = 0
    self:SetStatus("IDLE")
    Changed()
end

function Batch:SelectAll()
    local added = 0
    for _, bag in ipairs(API.GetBagList()) do
        for slot = 1, API.GetNumSlots(bag) do
            if self:Add(bag, slot, true) then added = added + 1 end
        end
    end
    Changed()
    if added == 0 then DH:Print("새로 선택할 마력 추출 가능 아이템이 없습니다.") end
    return added
end

---------------------------------------------------------------------------
-- 인벤토리 변화 반영: 이동한 아이템은 새 위치로, 사라진 아이템은 목록에서 제거
---------------------------------------------------------------------------
function Batch:Resolve()
    if #self.list == 0 then return end
    local guidLoc = {}
    for _, bag in ipairs(API.GetBagList()) do
        for slot = 1, API.GetNumSlots(bag) do
            local guid = API.GetItemGUID(bag, slot)
            if guid then guidLoc[guid] = { bag, slot } end
        end
    end
    local changed = false
    for i = #self.list, 1, -1 do
        local e = self.list[i]
        local present = false
        if e.guid then
            local loc = guidLoc[e.guid]
            if loc then
                if e.bag ~= loc[1] or e.slot ~= loc[2] then changed = true end
                e.bag, e.slot = loc[1], loc[2]
                present = true
            end
        else
            local info = API.GetSlotInfo(e.bag, e.slot)
            present = info and info.link == e.link
        end
        if present then
            local res = DH.Engine:EvaluateBagSlot(e.bag, e.slot)
            if res.state ~= DH.Engine.YES then present = false end
        end
        if not present then
            if self.pending and self.pending.entry == e then
                -- 추출 시도 중이던 아이템이 사라짐 = 추출 완료
                self.completed = self.completed + 1
                self.pending = nil
                self:SetStatus("DONE", e.name)
            end
            self.byKey[e.key] = nil
            table.remove(self.list, i)
            changed = true
        end
    end
    if changed then Changed() end
end

---------------------------------------------------------------------------
-- 다음 추출 대상
---------------------------------------------------------------------------
function Batch:GetNext()
    for _, e in ipairs(self.list) do
        local info = API.GetSlotInfo(e.bag, e.slot)
        if info and not info.locked then
            local res = DH.Engine:EvaluateBagSlot(e.bag, e.slot, info)
            if res.state == DH.Engine.YES then return e end
        end
    end
end

function Batch:IsNextSlot(bag, slot)
    local e = self.list[1] and self:GetNext()
    return e and e.bag == bag and e.slot == slot
end

---------------------------------------------------------------------------
-- 진행 상태
---------------------------------------------------------------------------
function Batch:SetStatus(status, name)
    self.status = status
    self.statusName = name
    DH:Fire("BATCH_STATUS")
end

function Batch:GetStatusText()
    local s, n = self.status, self.statusName
    if s == "CASTING" then return "|cffffd200추출 진행 중|r: " .. (n or "") end
    if s == "DONE" then
        if #self.list == 0 then return "|cff33ff33추출 완료|r - 모든 선택 아이템을 추출했습니다." end
        return "|cff33ff33추출 완료|r: " .. (n or "")
    end
    if s == "FAILED" then return "|cffff5555추출 실패|r: " .. (n or "") end
    if #self.list == 0 then return "보라 테두리 아이템을 클릭해 선택하세요." end
    local nxt = self:GetNext()
    if nxt then return "다음 추출 대상: " .. nxt.name end
    return "추출할 수 있는 아이템이 없습니다. (이동 중이거나 잠김)"
end

-- 보안 버튼 PreClick: 다음 대상을 속성에 지정 (전투 중이 아닐 때만)
function Batch:PrepareSecureButton(button)
    if InCombatLockdown() then return end
    local e = DH:IsActive() and self:GetNext() or nil
    if e then
        DH:SetCastAttributes(button, e.bag, e.slot)
        button.candidate = e
    else
        DH:SetCastAttributes(button, nil, nil)
        button.candidate = nil
    end
end

function Batch:OnSecureButtonPostClick(button)
    local e = button.candidate
    if e then
        self:BeginPending(e)
    elseif not self.warnedEmpty then
        self.warnedEmpty = true
        C_Timer.After(1, function() Batch.warnedEmpty = nil end)
        if #self.list == 0 then
            DH:Print("선택된 아이템이 없습니다. 가방에서 보라 테두리 아이템을 선택하세요.")
        else
            DH:Print("지금 추출할 수 있는 선택 아이템이 없습니다.")
        end
    end
end

function Batch:BeginPending(e)
    if self.pending and self.pending.entry == e then return end
    self.pending = { entry = e, itemID = e.itemID, time = GetTime() }
    local token = self.pending
    -- 2초 안에 시전이 시작되지 않으면 대기 상태 해제 (클릭했지만 시전 실패 등)
    C_Timer.After(2, function()
        if Batch.pending == token and Batch.status ~= "CASTING" then
            Batch.pending = nil
            DH:Fire("BATCH_STATUS")
        end
    end)
end

-- 단축키+좌클릭 오버레이에서 추출을 시도했을 때 (선택 목록에 있는 아이템이면 진행 상태 반영)
function Batch:NotifyCastAttempt(bag, slot)
    local e = self.slotIndex[SlotKey(bag, slot)]
    if e then
        self:BeginPending(e)
    else
        local info = API.GetSlotInfo(bag, slot)
        if info then
            self.pending = { entry = nil, itemID = info.itemID, time = GetTime() }
        end
    end
end

---------------------------------------------------------------------------
-- 이벤트
---------------------------------------------------------------------------
local function IsPlayerDECast(unit, spellID)
    if unit ~= "player" or not Batch.pending then return false end
    if spellID ~= nil and not API.IsSecret(spellID) and spellID ~= DH.DISENCHANT_SPELL_ID then return false end
    return true
end

DH:RegisterEvent("UNIT_SPELLCAST_START", function(_, unit, _, spellID)
    if unit == "player" then DH.lastCastStart = GetTime() end
    if IsPlayerDECast(unit, spellID) then
        Batch:SetStatus("CASTING", Batch.pending.entry and Batch.pending.entry.name or "")
    end
end)

local function OnCastStop(_, unit, _, spellID)
    if IsPlayerDECast(unit, spellID) and Batch.status == "CASTING" then
        local name = Batch.pending.entry and Batch.pending.entry.name
        Batch.pending = nil
        Batch:SetStatus("FAILED", name or "")
    end
end
DH:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", OnCastStop)
DH:RegisterEvent("UNIT_SPELLCAST_FAILED", OnCastStop)

DH:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if IsPlayerDECast(unit, spellID) then
        if not Batch.pending.entry then
            -- 선택 목록에 없는 아이템을 단축키+좌클릭으로 추출한 경우
            Batch.pending = nil
            Batch:SetStatus("IDLE")
            return
        end
        -- 아이템이 실제로 사라지는 것은 가방 갱신 이벤트에서 확인
        C_Timer.After(0.5, function() DH:SafeCall(Batch.Resolve, Batch) end)
    end
end)

-- 숙련도 부족 오류를 받으면 해당 아이템을 '숙련도 부족'으로 기록 (다음 판별부터 반영)
local LOW_SKILL_ERRORS = {}
for _, k in ipairs({ "SPELL_FAILED_LOW_CASTLEVEL", "SPELL_FAILED_MIN_SKILL", "ERR_ITEM_DISENCHANT_SKILL_TOO_LOW" }) do
    if type(_G[k]) == "string" then LOW_SKILL_ERRORS[_G[k]] = true end
end
DH:RegisterEvent("UI_ERROR_MESSAGE", function(_, _, message)
    DH.lastCastError = GetTime()   -- 게임이 오류를 띄웠다면 시전 시도는 된 것
    if not Batch.pending or type(message) ~= "string" or API.IsSecret(message) then return end
    if LOW_SKILL_ERRORS[message] then
        DH.Engine:MarkLowSkill(Batch.pending.itemID)
        local name = Batch.pending.entry and Batch.pending.entry.name
        Batch.pending = nil
        Batch:SetStatus("FAILED", (name or "") .. " (숙련도 부족)")
    end
end)

DH:RegisterEvent("BAG_UPDATE_DELAYED", function()
    Batch:Resolve()
    DH:Fire("BATCH_STATUS")
end)

DH:On("ITEM_DATA_READY", function() DH:Fire("BATCH_STATUS") end)
DH:On("DATA_CHANGED", function() Batch:Resolve(); DH:Fire("BATCH_STATUS") end)
