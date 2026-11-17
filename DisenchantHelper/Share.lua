-- 파티/길드 공유: 툴팁에서 확인한 "마력 추출 가능/불가" 기록을 상수팩 사용자끼리 나눕니다.
-- (아이템 종류마다 결과가 고정이라 다른 사람이 확인한 결과를 그대로 써도 됩니다)
-- 상수팩 공용 공유(SangsuData.lua)를 사용합니다. 키: l:아이템번호, 내용: 결과~요구숙련도
local DH = _G.DisenchantHelper
local SD = _G.SangsuData
if not (DH and DH.Engine and SD and SD.Register) then return end
local E = DH.Engine

local receiving = false
local origLearn = E.Learn
function E:Learn(itemID, state, reqSkill, silent)
    local changed = origLearn(self, itemID, state, reqSkill, silent)
    if changed and not receiving then SD:Changed("DH") end
    return changed
end

SD:Register("DH", {
    keys = function()
        local t = {}
        for id, v in pairs(DH.db and DH.db.learned or {}) do
            if v.s == "YES" or v.s == "NO" then t[#t + 1] = "l:" .. id end
        end
        return t
    end,
    has = function(key)
        local id = tonumber(key:match("^l:(%d+)$"))
        if not id then return true end
        return (DH.db and DH.db.learned and DH.db.learned[id]) and true or false
    end,
    encode = function(key)
        local id = tonumber(key:match("^l:(%d+)$"))
        local v = id and DH.db and DH.db.learned and DH.db.learned[id]
        if not v then return nil end
        return v.s .. "~" .. (v.req or "")
    end,
    apply = function(key, payload, who)
        local id = tonumber(key:match("^l:(%d+)$"))
        local s, req = payload:match("^(%u+)~(%d*)$")
        if not id or (s ~= "YES" and s ~= "NO") or not DH.db then return false end
        receiving = true
        local ok = pcall(E.Learn, E, id, s, tonumber(req), false)
        receiving = false
        return ok
    end,
    onReceived = function(total, from)
        DH:Print(string.format("파티/길드원에게서 마력 추출 확인 결과 %d건을 받았습니다. (%s)", total, from))
    end,
})
