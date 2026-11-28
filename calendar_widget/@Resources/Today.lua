-- Today.lua: reads the Google .ics feed and renders today's events as a departure board.

local FEEDS = { 'google' }  -- add a name here + a WebParser measure in Today.ini for another calendar
local MAX_ROWS = 8
local Y0, RH, W = 74, 28, 360       -- first row top, row pitch, board width

local ALL = {}          -- parsed events from every feed
local loaded = 0        -- feeds with usable data
local todayKey, todayTimed, todayAllDay

local function log(msg, level)
    SKIN:Bang('!Log', 'Today: ' .. tostring(msg), level or 'Notice')
end

local function readFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

local function writeFile(path, data)
    local f = io.open(path, 'wb')
    if not f then return end
    f:write(data)
    f:close()
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

local function looksValid(text)
    return text ~= nil
        and text:find('BEGIN:VCALENDAR', 1, true) ~= nil
        and text:find('END:VCALENDAR', 1, true) ~= nil
end

-- Remove CRs and unfold continuation lines.
local function normalise(text)
    return (text:gsub('\r', ''):gsub('\n[ \t]', ''))
end

local function unescape(s)
    return (s:gsub('\\,', ','):gsub('\\;', ';'):gsub('\\[nN]', ' '):gsub('\\\\', '\\'))
end

local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp  = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function dateKey(y, m, d) return string.format('%04d%02d%02d', y, m, d) end

local function field(block, name)
    return block:match('\n' .. name .. '([^:\n]*):([^\n]*)')
end

-- "20261128" -> all day; "...Z" -> UTC shifted to local; otherwise wall time.
-- shortcut: TZID times are taken as PC-local wall time; upgrade if you add events from other timezones.
local function parseDT(value)
    value = trim(value)
    local y, mo, d, h, mi, s, z = value:match('^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)(Z?)$')
    if y then
        y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
        if z == 'Z' then
            local t = os.date('*t', daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60)
            y, mo, d, h, mi = t.year, t.month, t.day, t.hour, t.min
        end
        return { y = y, m = mo, d = d, min = h * 60 + mi, allDay = false }
    end
    y, mo, d = value:match('^(%d%d%d%d)(%d%d)(%d%d)')
    if y then return { y = tonumber(y), m = tonumber(mo), d = tonumber(d), min = 0, allDay = true } end
    return nil
end

local function keyOf(dt) return dateKey(dt.y, dt.m, dt.d) end

local function parseRule(text)
    local r = {}
    for k, v in text:gmatch('([%u]+)=([^;]+)') do r[k] = v end
    if r.UNTIL then
        local u = parseDT(r.UNTIL)
        r.UNTIL = u and keyOf(u)
    end
    r.INTERVAL = tonumber(r.INTERVAL) or 1
    r.COUNT = tonumber(r.COUNT)
    return r
end

local overrides = {}    -- uid..dateKey -> true when a moved/edited instance replaces the master's

local function parseEvents(text, out)
    for body in text:gmatch('BEGIN:VEVENT\n(.-)\nEND:VEVENT') do
        local block = '\n' .. body .. '\n'
        local _, startVal = field(block, 'DTSTART')
        local _, summary  = field(block, 'SUMMARY')
        local _, status   = field(block, 'STATUS')
        local start = startVal and parseDT(startVal)
        local cancelled = status and status:upper():find('CANCEL', 1, true)
        local _, uid = field(block, 'UID')
        uid = uid and trim(uid) or ''

        local _, recId = field(block, 'RECURRENCE%-ID')
        if recId and parseDT(recId) then overrides[uid .. keyOf(parseDT(recId))] = true end

        if start and not cancelled then
            local ev = start
            ev.title = summary and trim(unescape(summary)) or '(no title)'
            ev.uid = uid
            ev.day = daysFromCivil(ev.y, ev.m, ev.d)
            ev.isOverride = recId ~= nil

            local _, endVal = field(block, 'DTEND')
            local fin = endVal and parseDT(endVal)
            if ev.allDay then
                ev.span = fin and math.max(1, daysFromCivil(fin.y, fin.m, fin.d) - ev.day) or 1
                ev.dur = 0
            else
                -- shortcut: timed events spanning midnight only show on their start day.
                ev.dur = fin and ((daysFromCivil(fin.y, fin.m, fin.d) - ev.day) * 1440 + fin.min - ev.min) or 0
            end

            local _, rule = field(block, 'RRULE')
            if rule then ev.rule = parseRule(rule) end
            ev.ex = {}
            for _, list in block:gmatch('\nEXDATE([^:\n]*):([^\n]*)') do
                for v in list:gmatch('[^,]+') do
                    local x = parseDT(v)
                    if x then ev.ex[keyOf(x)] = true end
                end
            end
            out[#out + 1] = ev
        end
    end
end

local CODES = { SU = 0, MO = 1, TU = 2, WE = 3, TH = 4, FR = 5, SA = 6 }
local function weekday(day) return (day + 4) % 7 end          -- 0 = Sunday (1970-01-01 was a Thursday)
local function weekStart(day) return day - (day + 3) % 7 end  -- the Monday of that week

-- Does the rule's pattern land on `day`? Ignores UNTIL/COUNT/EXDATE.
-- shortcut: no BYSETPOS or "2nd Tuesday" monthly rules; those events won't show. Upgrade if you rely on them.
local function patternHits(ev, day, y, m, d)
    local r, diff = ev.rule, day - ev.day
    if diff < 0 then return false end
    if r.FREQ == 'DAILY' then
        return diff % r.INTERVAL == 0
    elseif r.FREQ == 'WEEKLY' then
        local weeks = (weekStart(day) - weekStart(ev.day)) / 7
        if weeks % r.INTERVAL ~= 0 then return false end
        if not r.BYDAY then return weekday(day) == weekday(ev.day) end
        for code in r.BYDAY:gmatch('%u%u') do
            if CODES[code] == weekday(day) then return true end
        end
        return false
    elseif r.FREQ == 'MONTHLY' then
        if r.BYDAY then return false end
        local months = (y - ev.y) * 12 + (m - ev.m)
        return months % r.INTERVAL == 0 and d == (tonumber(r.BYMONTHDAY) or ev.d)
    elseif r.FREQ == 'YEARLY' then
        return (y - ev.y) % r.INTERVAL == 0 and m == ev.m and d == ev.d
    end
    return false
end

local function occursOn(ev, y, m, d)
    local day, key = daysFromCivil(y, m, d), dateKey(y, m, d)
    if not ev.rule then
        local diff = day - ev.day
        return diff >= 0 and diff < (ev.span or 1)
    end
    if ev.ex[key] or overrides[ev.uid .. key] then return false end
    if ev.rule.UNTIL and key > ev.rule.UNTIL then return false end
    if not patternHits(ev, day, y, m, d) then return false end
    if ev.rule.COUNT then
        local n = 0
        for dd = ev.day, day - 1 do
            local t = os.date('!*t', dd * 86400)
            if patternHits(ev, dd, t.year, t.month, t.day) then n = n + 1 end
        end
        if n >= ev.rule.COUNT then return false end
    end
    return true
end

-- ===== loading =====

function Load()
    local base = SKIN:GetVariable('CURRENTPATH') .. 'DownloadFile\\'
    ALL, overrides, loaded = {}, {}, 0
    local counts = {}
    for _, name in ipairs(FEEDS) do
        local fresh, cache = base .. name .. '.ics', base .. name .. '_lastgood.ics'
        local raw = readFile(fresh)
        if looksValid(raw) then
            writeFile(cache, raw)
        else
            raw = readFile(cache)
        end
        local before = #ALL
        if looksValid(raw) then
            parseEvents(normalise(raw), ALL)
            loaded = loaded + 1
        end
        counts[#counts + 1] = name .. ': ' .. (#ALL - before)
    end
    log('loaded ' .. #ALL .. ' events (' .. table.concat(counts, ', ') .. ')')
    todayKey = nil
    Update()
end

local function buildToday(t)
    todayTimed, todayAllDay = {}, {}
    local seen = {}
    for _, ev in ipairs(ALL) do
        if occursOn(ev, t.year, t.month, t.day) then
            local id = ev.title:lower() .. '|' .. (ev.allDay and 'all' or ev.min)
            if not seen[id] then           -- same event can live in both calendars
                seen[id] = true
                local list = ev.allDay and todayAllDay or todayTimed
                list[#list + 1] = ev
            end
        end
    end
    table.sort(todayTimed, function(a, b) return a.min < b.min end)
end

-- ===== rendering =====

local function set(meter, option, value) SKIN:Bang('!SetOption', meter, option, value) end
local function show(meter, on) SKIN:Bang(on and '!ShowMeter' or '!HideMeter', meter) end

local AMBER, AMBER_DIM = '255,176,32', '255,176,32,80'
local TEXT, TEXT_DIM, INK = '238,232,216', '238,232,216,70', '18,16,12'
local CLEAR = '0,0,0,0'

local function rect(x, y, w, h, r, fill)
    return string.format('Rectangle %d,%d,%d,%d,%d | Fill Color %s | StrokeWidth 0', x, y, w, h, r, fill)
end
local function rule(y) return string.format('Line 12,%d,%d,%d | StrokeWidth 1 | Stroke Color 255,176,32,55', y, W - 12, y) end

function Update()
    local t = os.date('*t')
    local key = dateKey(t.year, t.month, t.day)
    if key ~= todayKey then buildToday(t); todayKey = key end
    local now = t.hour * 60 + t.min

    set('Date', 'Text', os.date('%a ') .. t.day .. os.date(' %b'))

    local rows = math.min(#todayTimed, MAX_ROWS)
    local nextShown
    for i = 1, MAX_ROWS do
        local ev, on = todayTimed[i], i <= rows
        local y = Y0 + (i - 1) * RH + RH / 2
        show('T' .. i, on); show('E' .. i, on); show('S' .. i, on)
        -- each row sits on its own flap module
        set('Board', 'Shape' .. (i + 2), on and rect(10, Y0 + (i - 1) * RH + 2, W - 20, RH - 4, 3, '28,26,22') or rect(0, 0, 0, 0, 0, CLEAR))
        if on then
            local done = ev.min + ev.dur <= now and not (ev.dur == 0 and ev.min >= now)
            local live = not done and ev.min <= now
            local status = ''
            if done then status = 'DONE'
            elseif live then status = 'NOW'
            elseif not nextShown then status, nextShown = 'NEXT', true end

            set('T' .. i, 'Text', string.format('%02d:%02d', math.floor(ev.min / 60), ev.min % 60))
            set('E' .. i, 'Text', ev.title:upper())
            set('E' .. i, 'ToolTipText', ev.title)
            set('S' .. i, 'Text', status)
            set('T' .. i, 'FontColor', done and AMBER_DIM or AMBER)
            set('E' .. i, 'FontColor', done and TEXT_DIM or TEXT)
            set('S' .. i, 'FontColor', live and INK or (done and TEXT_DIM or AMBER))
            set('S' .. i, 'SolidColor', live and AMBER or CLEAR)
            for _, m in ipairs({ 'T', 'E', 'S' }) do set(m .. i, 'Y', y) end
        end
    end

    local extra = #todayTimed - rows
    local bottom = Y0 + rows * RH
    show('More', extra > 0)
    set('More', 'Text', '+' .. extra .. ' MORE')
    set('More', 'Y', bottom + 4)
    if extra > 0 then bottom = bottom + 22 end

    -- empty and not-set-up states use the first title slot, widened since there's no status
    set('E1', 'W', rows == 0 and 262 or 200)
    if rows == 0 then
        show('E1', true)
        set('E1', 'FontColor', TEXT_DIM)
        set('E1', 'Y', Y0 + RH / 2)
        set('E1', 'Text', loaded == 0 and 'ADD GOOGLEURL TO FEEDS.INC' or 'NOTHING SCHEDULED TODAY')
        set('E1', 'ToolTipText', '')
        bottom = Y0 + RH
    end

    local titles = {}
    for _, ev in ipairs(todayAllDay) do titles[#titles + 1] = ev.title:upper() end
    local hasAllDay = #titles > 0
    show('AllDayLabel', hasAllDay); show('AllDay', hasAllDay)
    set('Board', 'Shape11', hasAllDay and rule(bottom + 8) or rect(0, 0, 0, 0, 0, CLEAR))
    if hasAllDay then
        set('AllDayLabel', 'Y', bottom + 26)
        set('AllDay', 'Y', bottom + 26)
        set('AllDay', 'Text', table.concat(titles, '  /  '))
        set('AllDay', 'ToolTipText', table.concat(titles, '\n'))
        bottom = bottom + 38
    end

    set('Board', 'Shape', string.format('Rectangle 0.5,0.5,%d,%d,8 | Fill Color 14,13,11 | StrokeWidth 1 | Stroke Color 58,54,46', W - 1, bottom + 10))

    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end

-- ===== self-check: logs PASS/FAIL to the Rainmeter log on load =====

local function SelfTest()
    local function ev(y, m, d, rule, extra)
        local e = { y = y, m = m, d = d, day = daysFromCivil(y, m, d), uid = 't', ex = {}, rule = rule and parseRule(rule) }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end
    local cases = {
        { ev(2026, 11, 1, 'FREQ=DAILY;INTERVAL=2'), 2026, 11, 3, true },
        { ev(2026, 11, 1, 'FREQ=DAILY;INTERVAL=2'), 2026, 11, 4, false },
        { ev(2026, 11, 2, 'FREQ=WEEKLY;BYDAY=MO,WE'), 2026, 11, 4, true },
        { ev(2026, 11, 2, 'FREQ=WEEKLY;BYDAY=MO,WE'), 2026, 11, 5, false },
        { ev(2026, 11, 2, 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO'), 2026, 11, 9, false },
        { ev(2026, 11, 2, 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO'), 2026, 11, 16, true },
        { ev(2026, 11, 1, 'FREQ=DAILY;UNTIL=20261110T235959Z'), 2026, 11, 12, false },
        { ev(2026, 11, 1, 'FREQ=DAILY', { ex = { ['20261104'] = true } }), 2026, 11, 4, false },
        { ev(2026, 11, 1, 'FREQ=DAILY;COUNT=3'), 2026, 11, 3, true },
        { ev(2026, 11, 1, 'FREQ=DAILY;COUNT=3'), 2026, 11, 4, false },
        { ev(2026, 1, 15, 'FREQ=MONTHLY'), 2026, 11, 15, true },
        { ev(2026, 1, 15, 'FREQ=MONTHLY'), 2026, 11, 16, false },
        { ev(2000, 11, 28, 'FREQ=YEARLY'), 2026, 11, 28, true },
        { ev(2026, 11, 27, nil, { span = 3 }), 2026, 11, 29, true },
        { ev(2026, 11, 27, nil, { span = 3 }), 2026, 11, 30, false },
    }
    local failed = 0
    for i, c in ipairs(cases) do
        if occursOn(c[1], c[2], c[3], c[4]) ~= c[5] then
            failed = failed + 1
            log('selftest case ' .. i .. ' failed', 'Error')
        end
    end
    log(failed == 0 and 'selftest PASS' or ('selftest FAIL (' .. failed .. ')'), failed == 0 and 'Notice' or 'Error')
end

function Initialize()
    SelfTest()
    Load()
end
