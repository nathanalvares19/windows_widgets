-- Fixture.lua (UnitedMatch skin)
-- Reads the downloaded Man Utd men's ICS feed, keeps a last-known-good copy,
-- and works out the next match.  Step 3: parsing + selection + logging only.

local MATCH_WINDOW = 3 * 3600   -- seconds after kickoff that a match still counts as "current"

NextMatch  = nil      -- table describing the next match, or nil if none / no data
FeedSource = 'none'   -- 'download', 'cache' or 'none'

local FRESH, CACHE
local crestIds = {}

local function log(msg, level)
    msg = tostring(msg):gsub('"', "'")
    SKIN:Bang('!Log "UnitedMatch: ' .. msg .. '" ' .. (level or 'Notice'))
end

local function setPaths()
    local base = SKIN:GetVariable('CURRENTPATH')
    FRESH = base .. 'DownloadFile\\fixtures.ics'
    CACHE = base .. 'DownloadFile\\fixtures_lastgood.ics'
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
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- A real, complete calendar: has a start, at least one event, and an end.
local function looksValid(text)
    return text ~= nil
        and text:find('BEGIN:VCALENDAR', 1, true) ~= nil
        and text:find('BEGIN:VEVENT', 1, true) ~= nil
        and text:find('END:VCALENDAR', 1, true) ~= nil
end

-- Remove CRs and unfold long lines (continuation lines start with space/tab).
local function normalise(text)
    text = text:gsub('\r', '')
    text = text:gsub('\n[ \t]', '')
    return text
end

local function unescape(s)
    s = s:gsub('\\,', ',')
    s = s:gsub('\\;', ';')
    s = s:gsub('\\[nN]', ' ')
    s = s:gsub('\\\\', '\\')
    return s
end

-- Days since 1970-01-01 for a civil date (no timezone involved).
local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp  = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function utcEpoch(y, m, d, h, mi, s)
    return daysFromCivil(y, m, d) * 86400 + h * 3600 + mi * 60 + s
end

-- Returns { epoch, hasTime, dateKey } or nil.
-- Only a full UTC time (ending in Z) counts as a known kickoff.
-- A bare date, or a time with no Z, gives us the day but not a trustworthy kickoff.
local function parseStart(value)
    value = trim(value)
    local y, mo, d, h, mi, s, z = value:match('^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)(Z?)$')
    if y and z == 'Z' then
        return {
            epoch   = utcEpoch(tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)),
            hasTime = true,
            dateKey = y .. mo .. d,
        }
    end
    local y2, mo2, d2 = value:match('^(%d%d%d%d)(%d%d)(%d%d)')
    if y2 then
        return {
            epoch   = utcEpoch(tonumber(y2), tonumber(mo2), tonumber(d2), 12, 0, 0),
            hasTime = false,
            dateKey = y2 .. mo2 .. d2,
        }
    end
    return nil
end

local function isUnited(name)
    local n = name:lower()
    return n:find('man utd', 1, true) or n:find('man united', 1, true)
        or n:find('manchester united', 1, true) or n:find('manchester utd', 1, true)
end

-- "Man Utd vs Everton - Premier League" -> opponent, competition, venue ('H'/'A'/nil)
local function parseSummary(summary)
    local matchup, competition = summary:match('^(.-)%s+%-%s+(.+)$')
    if not matchup then matchup = summary end
    matchup = trim(matchup)
    if competition then competition = trim(competition) end

    local home, away = matchup:match('^(.-)%s+[vV][sS]?%.?%s+(.+)$')
    local opponent, venue
    if home and away then
        home, away = trim(home), trim(away)
        if isUnited(home) then
            opponent, venue = away, 'H'
        elseif isUnited(away) then
            opponent, venue = home, 'A'
        else
            opponent = matchup
        end
    else
        opponent = matchup
    end
    return opponent, competition, venue
end

-- Value of a property line such as "SUMMARY:..." or "DTSTART;VALUE=DATE:...".
local function field(block, name)
    local params, value = block:match('\n' .. name .. '([^:\n]*):([^\n]*)')
    return params, value
end

local function parseEvents(text)
    local events = {}
    for body in text:gmatch('BEGIN:VEVENT\n(.-)\nEND:VEVENT') do
        local block = '\n' .. body .. '\n'
        local _, status   = field(block, 'STATUS')
        local _, startVal = field(block, 'DTSTART')
        local _, summary  = field(block, 'SUMMARY')

        local cancelled = status and status:upper():find('CANCEL', 1, true)
        if startVal and summary and not cancelled then
            summary = trim(unescape(summary))
            local upper = summary:upper()
            local dead = upper:find('POSTPONED', 1, true)
                      or upper:find('CANCEL', 1, true)
                      or upper:find('ABANDONED', 1, true)
            local start = parseStart(startVal)
            if start and not dead then
                if upper:find('TBC', 1, true) or upper:find('TBA', 1, true) then
                    start.hasTime = false
                end
                local opponent, competition, venue = parseSummary(summary)
                events[#events + 1] = {
                    epoch       = start.epoch,
                    hasTime     = start.hasTime,
                    dateKey     = start.dateKey,
                    opponent    = opponent,
                    competition = competition,
                    venue       = venue,
                    summary     = summary,
                }
            end
        end
    end
    return events
end

local function pickNext(events, now)
    local today = os.date('%Y%m%d', now)
    local best
    for _, ev in ipairs(events) do
        local upcoming
        if ev.hasTime then
            upcoming = (ev.epoch + MATCH_WINDOW) > now
        else
            upcoming = ev.dateKey >= today
        end
        if upcoming and (not best or ev.epoch < best.epoch) then
            best = ev
        end
    end
    return best
end

local function describe(ev)
    local when
    if ev.hasTime then
        when = os.date('!%Y-%m-%d %H:%M', ev.epoch) .. ' UTC / '
            .. os.date('%Y-%m-%d %H:%M', ev.epoch) .. ' local'
    else
        local k = ev.dateKey
        when = k:sub(1, 4) .. '-' .. k:sub(5, 6) .. '-' .. k:sub(7, 8) .. ' (kickoff time TBC)'
    end
    local where = (ev.venue == 'H' and 'home') or (ev.venue == 'A' and 'away') or 'venue unknown'
    return ev.opponent .. ' | ' .. (ev.competition or 'no competition') .. ' | ' .. where .. ' | ' .. when
end

-- Called when the skin loads and each time a download finishes.
function Refresh()
    setPaths()

    local raw = readFile(FRESH)
    local source = 'download'
    if looksValid(raw) then
        writeFile(CACHE, raw)                 -- remember the last good copy
    else
        log('downloaded feed missing or invalid, trying cached copy', 'Warning')
        raw = readFile(CACHE)
        source = 'cache'
        if not looksValid(raw) then
            NextMatch, FeedSource = nil, 'none'
            log('no usable feed data (no valid download and no cached copy)', 'Warning')
            return
        end
    end

    local events = parseEvents(normalise(raw))
    NextMatch  = pickNext(events, os.time())
    FeedSource = source

    if NextMatch then
        log('next match [' .. source .. ', ' .. #events .. ' events]: ' .. describe(NextMatch))
    else
        log('feed OK [' .. source .. ', ' .. #events .. ' events] but no upcoming match found', 'Warning')
    end
end

function Initialize()
    local ok, result = pcall(dofile, SKIN:GetVariable('CURRENTPATH') .. '@Resources\\Teams.lua')
    if ok and type(result) == 'table' then
        crestIds = result
    else
        crestIds = {}
        log('could not load team crest list; using initials', 'Warning')
    end
    Refresh()
end

-- ===== Step 4: text for the card =====

local function isStale(ev, now)
    if ev.hasTime then
        return (ev.epoch + MATCH_WINDOW) <= now
    end
    return ev.dateKey < os.date('%Y%m%d', now)
end

-- The match to display; moves on by itself once the current one is over.
local function current()
    if NextMatch and isStale(NextMatch, os.time()) then
        Refresh()
    end
    return NextMatch
end

-- Local offset from UTC at time t, e.g. "UTC+5:30", "UTC+1", "UTC-5"
local function utcOffsetLabel(t)
    local l = os.date('*t', t)
    local u = os.date('!*t', t)
    u.isdst = l.isdst
    local off = os.time(l) - os.time(u)
    local sign = (off < 0) and '-' or '+'
    off = math.abs(off)
    local h = math.floor(off / 3600)
    local m = math.floor((off % 3600) / 60)
    if m == 0 then
        return 'UTC' .. sign .. h
    end
    return string.format('UTC%s%d:%02d', sign, h, m)
end

-- "Sun 22 Nov" (no leading zero on the day)
local function dayLabel(t, utc)
    local bang = utc and '!' or ''
    return os.date(bang .. '%a ', t) .. tonumber(os.date(bang .. '%d', t)) .. os.date(bang .. ' %b', t)
end

function GetLabel()
    local ev = current()
    if ev then
        return (ev.competition or 'NEXT MATCH'):upper()
    end
    if FeedSource == 'none' then return 'FIXTURES UNAVAILABLE' end
    return 'NEXT MATCH'
end

function GetOpponent()
    local ev = current()
    if ev then
        if ev.venue == 'A' then return 'at ' .. ev.opponent end
        return 'vs. ' .. ev.opponent
    end
    if FeedSource == 'none' then return 'Feed unavailable' end
    return 'No upcoming match'
end

function GetKickoff()
    local ev = current()
    if not ev then
        if FeedSource == 'none' then return 'Will retry shortly' end
        return 'Check back soon'
    end
    if not ev.hasTime then
        -- Date only: show the date exactly as published, no timezone shifting.
        return dayLabel(ev.epoch, true) .. ' | Kickoff TBC'
    end
    local clock = os.date('%I:%M %p', ev.epoch):gsub('^0', '')
    return dayLabel(ev.epoch, false) .. ' | ' .. clock .. ' ' .. utcOffsetLabel(ev.epoch)
end

-- Portfolio-style board. The original text getters remain available.

local function boardTeam(side)
    local ev = current()
    if not ev then return nil end
    local unitedSide = ev.venue == 'A' and 'away' or 'home'
    if side == unitedSide then return 'Manchester United' end
    return ev.opponent
end

local function crestId(name)
    if not name then return nil end
    local key = name:lower():gsub('&amp;', 'and'):gsub('&', 'and'):gsub('[^a-z0-9]', '')
    return crestIds[key]
end

function GetTeamName(side)
    return boardTeam(side) or '---'
end

function GetTeamLogo(side)
    local id = crestId(boardTeam(side)) or 'blank'
    return SKIN:GetVariable('CURRENTPATH') .. '@Resources\\Logos\\' .. id .. '.png'
end

function GetTeamInitials(side)
    local name = boardTeam(side)
    if not name or crestId(name) then return '' end
    local initials = ''
    for word in name:gmatch('%S+') do initials = initials .. word:sub(1, 1) end
    return initials:sub(1, 3):upper()
end

function GetVenueLabel(side)
    local ev = current()
    if not ev or not ev.venue then return '' end
    return side == 'home' and 'Home' or 'Away'
end

function GetBoardLabel()
    local ev = current()
    if not ev then return GetOpponent() end
    return ev.competition or 'Competition unavailable'
end

function GetBoardTime()
    local ev = current()
    if not ev then return '--:--' end
    if not ev.hasTime then return 'TBC' end
    local clock = os.date('%I:%M %p', ev.epoch):gsub('^0', '')
    return clock
end

function GetBoardDate()
    local ev = current()
    if not ev then return GetKickoff() end
    if not ev.hasTime then return dayLabel(ev.epoch, true) end
    return dayLabel(ev.epoch, false) .. ' / ' .. utcOffsetLabel(ev.epoch)
end

function GetBoardDateTime()
    local ev = current()
    if not ev then return GetKickoff() end
    local date = dayLabel(ev.epoch, not ev.hasTime)
    return date .. '  -  ' .. GetBoardTime()
end

function GetDisplayTeamName(side)
    local name = GetTeamName(side)
    return name:gsub("%s+", "\n")
end