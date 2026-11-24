script_name("Leader Helper")
script_author("Pascal Jeans")

local imgui = require 'mimgui'
local ffi = require 'ffi'
local ini = require 'inicfg'
local encoding = require 'encoding'
local lfs = require 'lfs'
local sampev = require 'samp.events'

-- =========================================
-- АВТООБНОВЛЕНИЕ
-- =========================================
local SCRIPT_VERSION = "0.3.4"
local UPDATE_URL_SCRIPT = "https://raw.githubusercontent.com/pascaljeans/Leader-Helper/refs/heads/main/Leader%20Helper.lua"

local SCRIPT_PATH = thisScript().path
local TEMP_SCRIPT = os.getenv("TEMP") .. "\\lh_update.tmp"

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function fileExists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function versionNewer(remote, local_)
    local function parse(v)
        local t = {}
        for n in tostring(v):gmatch("%d+") do t[#t+1] = tonumber(n) end
        return t
    end
    local r, l = parse(remote), parse(local_)
    for i = 1, math.max(#r, #l) do
        local a, b = r[i] or 0, l[i] or 0
        if a > b then return true end
        if a < b then return false end
    end
    return false
end

local function checkUpdate()
    if fileExists(TEMP_SCRIPT) then os.remove(TEMP_SCRIPT) end

    downloadUrlToFile(UPDATE_URL_SCRIPT, TEMP_SCRIPT)
    wait(3000)

    if not fileExists(TEMP_SCRIPT) then
        return false, "Не удалось скачать скрипт"
    end

    local content = readFile(TEMP_SCRIPT)
    if not content or #content < 100 then
        os.remove(TEMP_SCRIPT)
        return false, "Скачанный файл повреждён"
    end

    local remoteVer = content:match('local%s+SCRIPT_VERSION%s*=%s*"([%d%.]+)"')
    if not remoteVer then
        os.remove(TEMP_SCRIPT)
        return false, "В скачанном файле нет SCRIPT_VERSION"
    end

    if not versionNewer(remoteVer, SCRIPT_VERSION) then
        os.remove(TEMP_SCRIPT)
        return false, nil
    end

    updateRemoteVer = remoteVer
    updateContent = content
    updateAvailable[0] = true

    return true, remoteVer
end

local function applyUpdate()
    if not updateContent or #updateContent < 100 then
        sampAddChatMessage(u8:decode("{FF4444}[Leader Helper] Нет данных для обновления"), -1)
        return
    end

    os.remove(SCRIPT_PATH)
    local ok = os.rename(TEMP_SCRIPT, SCRIPT_PATH)
    if not ok then
        local f = io.open(SCRIPT_PATH, "w")
        if f then f:write(updateContent); f:close(); ok = true end
        if ok then os.remove(TEMP_SCRIPT) end
    end

    if ok then
        updateAvailable[0] = false
        sampAddChatMessage(
            u8:decode("{6495ED}[Leader Helper] {00FF7F}Обновлено до " .. updateRemoteVer .. ". Напиши /mlreload"),
            -1
        )
    else
        sampAddChatMessage(u8:decode("{FF4444}[Leader Helper] Не удалось заменить файл"), -1)
    end
end

ffi.cdef[[
    typedef struct _SYSTEMTIME {
        unsigned short wYear;
        unsigned short wMonth;
        unsigned short wDayOfWeek;
        unsigned short wDay;
        unsigned short wHour;
        unsigned short wMinute;
        unsigned short wSecond;
        unsigned short wMilliseconds;
    } SYSTEMTIME;

    void GetLocalTime(SYSTEMTIME* lpSystemTime);
    int CreateDirectoryW(const wchar_t* lpPathName, void* lpSecurityAttributes);
    int MoveFileW(const wchar_t* lpExistingFileName, const wchar_t* lpNewFileName);
    int MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char* lpMultiByteStr, int cbMultiByte, wchar_t* lpWideCharStr, int cchWideChar);
    int WideCharToMultiByte(unsigned int CodePage, unsigned long dwFlags, const wchar_t* lpWideCharStr, int cchWideChar, char* lpMultiByteStr, int cbMultiByte, const char* lpDefaultChar, int* lpUsedDefaultChar);
    unsigned int GetLastError(void);
]]

local function getWinTime()
    local st = ffi.new("SYSTEMTIME")
    ffi.C.GetLocalTime(st)
    return {
        year = tonumber(st.wYear),
        month = tonumber(st.wMonth),
        day = tonumber(st.wDay),
        wday = tonumber(st.wDayOfWeek) + 1,
        hour = tonumber(st.wHour),
        min = tonumber(st.wMinute),
        sec = tonumber(st.wSecond)
    }
end

local function getFormattedDate()
    local t = getWinTime()
    return string.format("%04d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.min)
end

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local function utf8ToAnsi(s)
    local str = tostring(s or "")
    if #str == 0 then return "" end
    local wlen = ffi.C.MultiByteToWideChar(65001, 0, str, #str, nil, 0)
    if wlen <= 0 then return str end
    local wbuf = ffi.new("wchar_t[?]", wlen + 1)
    ffi.C.MultiByteToWideChar(65001, 0, str, #str, wbuf, wlen)
    local alen = ffi.C.WideCharToMultiByte(1251, 0, wbuf, wlen, nil, 0, nil, nil)
    if alen <= 0 then return str end
    local abuf = ffi.new("char[?]", alen + 1)
    ffi.C.WideCharToMultiByte(1251, 0, wbuf, wlen, abuf, alen, nil, nil)
    local out = ffi.string(abuf, alen)
    wbuf = nil; abuf = nil
    return out
end

local function ansiToUtf8(s)
    local str = tostring(s or "")
    if #str == 0 then return "" end
    local wlen = ffi.C.MultiByteToWideChar(1251, 0, str, #str, nil, 0)
    if wlen <= 0 then return str end
    local wbuf = ffi.new("wchar_t[?]", wlen + 1)
    ffi.C.MultiByteToWideChar(1251, 0, str, #str, wbuf, wlen)
    local ulen = ffi.C.WideCharToMultiByte(65001, 0, wbuf, wlen, nil, 0, nil, nil)
    if ulen <= 0 then return str end
    local ubuf = ffi.new("char[?]", ulen + 1)
    ffi.C.WideCharToMultiByte(65001, 0, wbuf, wlen, ubuf, ulen, nil, nil)
    local out = ffi.string(ubuf, ulen)
    wbuf = nil; ubuf = nil
    return out
end

local function toWide(ansiStr)
    local s = tostring(ansiStr or "")
    local len = #s
    if len == 0 then return nil end
    local wlen = ffi.C.MultiByteToWideChar(1251, 0, s, len, nil, 0)
    if wlen <= 0 then return nil end
    local wbuf = ffi.new("wchar_t[?]", wlen + 1)
    local r = ffi.C.MultiByteToWideChar(1251, 0, s, len, wbuf, wlen)
    if r <= 0 then return nil end
    return wbuf
end

-- =========================================
-- КОНФИГУРАЦИЯ
-- =========================================

local CONFIG_FILE = "LeaderHelper.ini"
local EXPORT_SEP  = "~|~"

local function encodeForIni(text)
    if text == nil then return "" end
    local s = tostring(text)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\r\n", "\\n")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "")
    return s
end

local function decodeFromIni(text)
    if text == nil then return "" end
    local s = tostring(text)
    local out, i, len = {}, 1, #s
    while i <= len do
        local c = s:sub(i, i)
        if c == "\\" and i < len then
            local nc = s:sub(i + 1, i + 1)
            if nc == "n" then out[#out + 1] = "\n"; i = i + 2
            elseif nc == "\\" then out[#out + 1] = "\\"; i = i + 2
            else out[#out + 1] = c; i = i + 1 end
        else out[#out + 1] = c; i = i + 1 end
    end
    return table.concat(out)
end

local function trim(s)
    s = tostring(s or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function getCommands(text)
    local r = {}
    local s = tostring(text or ""):gsub("\r", "") .. "\n"
    local pos = 1
    while true do
        local nl = s:find("\n", pos, true)
        if not nl then break end
        local line = trim(s:sub(pos, nl - 1))
        if line ~= "" then r[#r + 1] = line end
        pos = nl + 1
    end
    return r
end

local function validTime(h, m, s)
    return h and m and s and h >= 0 and h <= 23 and m >= 0 and m <= 59
        and s >= 0 and s <= 59 and h == math.floor(h)
        and m == math.floor(m) and s == math.floor(s)
end

local function validNumber(v, mn, mx)
    local n = tonumber(v)
    return n and n >= mn and n <= mx
end

local function isEnabled(v)
    return v == true or v == "true" or v == "1"
end

local function settingsValid(p)
    if type(p) ~= "table" then return false end
    local rawCmds = p.commands
    if type(rawCmds) ~= "string" then return false end
    local ct = decodeFromIni(rawCmds)
    return #getCommands(ct) > 0
        and validTime(tonumber(p.hour), tonumber(p.min), tonumber(p.sec))
        and validNumber(p.delay, 0, 3600) and validNumber(p.timeAfter, 1, 10000)
        and validNumber(p.screenshotAfter, 1, 10000) and validNumber(p.screenshotDelay, 100, 3600)
end

local function notify(kind, msg)
    local p = "{6495ED}[Leader Helper] "
    if kind == "success" then p = p .. "{00FF7F}:true: {FFFFFF}"
    elseif kind == "error" then p = p .. "{FF4444}:no_entry: {FFFFFF}"
    elseif kind == "info" then p = p .. "{FFD700}:u1f4a0: {FFFFFF}" end
    sampAddChatMessage(u8:decode(p .. msg), -1)
end

-- =========================================
-- ПРОФИЛИ
-- =========================================

-- СТАТИЧНЫЙ ШАБЛОН (без вызова FFI каждый кадр)
local DEFAULT_PROFILE_TEMPLATE = {
    name            = "Новый профиль",
    commands        = "",
    hour            = "12",
    min             = "00",
    sec             = "00",
    delay           = "3",
    useTime         = "true",
    timeAfter       = "3",
    useScreenshot   = "true",
    screenshotAfter = "3",
    screenshotDelay = "100",
    screenshotFolder = "Собеседование",
    enabled         = "false",
    use_count       = "0",
    last_used       = "",
    created         = ""
}

local function defaultProfile(name)
    local p = {}
    -- Копируем поля из шаблона
    for k, v in pairs(DEFAULT_PROFILE_TEMPLATE) do
        p[k] = v
    end
    p.name = name or "Новый профиль"
    p.created = "" -- НЕ вызываем FFI здесь (краш: cannot resume non-suspended coroutine)
    return p
end

local cfg = ini.load({
    profiles = { count = "1", selected = "1" },
    profile1 = defaultProfile("Основной")
}, CONFIG_FILE)

if not cfg.profiles then cfg.profiles = { count = "1", selected = "1" } end
cfg.profiles.count    = tonumber(cfg.profiles.count) or 1
cfg.profiles.selected = tonumber(cfg.profiles.selected) or 1

if cfg.timer and cfg.timer.commands ~= nil then
    local old = cfg.timer
    local first = cfg.profile1 or defaultProfile("Основной")
    local def = defaultProfile("Основной")
    for k, v in pairs(def) do
        if old[k] ~= nil then first[k] = tostring(old[k])
        elseif first[k] == nil then first[k] = v end
    end
    first.name = first.name or "Основной"
    cfg.profile1 = first; cfg.timer = nil
    ini.save(cfg, CONFIG_FILE)
end

local function getProfile(index)
    local key = "profile" .. tostring(index)
    if not cfg[key] then 
        cfg[key] = defaultProfile("Профиль " .. tostring(index)) 
    end
    local p = cfg[key]
    -- Заполняем только отсутствующие поля
    for f, dv in pairs(DEFAULT_PROFILE_TEMPLATE) do
        if p[f] == nil then 
            p[f] = dv 
        else 
            p[f] = tostring(p[f]) 
        end
    end
    return p
end

local selectedProfile = cfg.profiles.selected
local activeCfg = getProfile(selectedProfile)

-- =========================================
-- РАДИАЛЬНОЕ МЕНЮ LEADER HELPER
-- =========================================

cfg.customActions = cfg.customActions or { count = "0" }
cfg.customActions.count = tonumber(cfg.customActions.count) or 0

local function getCustomAction(index)
    local key = "customAction" .. tostring(index)
    if not cfg[key] then
        cfg[key] = {
            name = "Моё действие",
            rp = "/me выполнил действие",
            command = "/example {id}"
        }
    end
    return cfg[key]
end

for i = 1, cfg.customActions.count do
    getCustomAction(i)
end

local pendingInviteEvidence = false
local takeScreenshot
local radialOpen = ffi.new("bool[1]", false)
local radialPlayerId = 0
local radialMode = "menu"
local radialAction = nil
local radialBusy = false
local radialCustomIndex = 0

local radialReason = ffi.new("char[256]")
local radialRank = ffi.new("char[16]")
local radialDuration = ffi.new("char[32]")

local customName = ffi.new("char[128]")
local customRp = ffi.new("char[1024]")
local customCommand = ffi.new("char[512]")

local function radialNotify(message)
    sampAddChatMessage(
        u8:decode("{6495ED}[Leader Helper] {FFFFFF}" .. message),
        -1
    )
end

local function sendRadialChat(text)
    sampSendChat(u8:decode(text))
end

local function replaceActionValues(text, values)
    text = tostring(text or "")
    for key, value in pairs(values) do
        text = text:gsub("{" .. key .. "}", function()
            return tostring(value or "")
        end)
    end
    return text
end

local function getRadialValues()
    return {
        id = tostring(radialPlayerId),
        reason = trim(ffi.string(radialReason)),
        rank = trim(ffi.string(radialRank)),
        time = trim(ffi.string(radialDuration))
    }
end

local function closeRadial()
    radialOpen[0] = false
    radialMode = "menu"
    radialAction = nil
    radialCustomIndex = 0
end


local function runRadialAction(rpLines, command, values, evidenceMode)
    if radialBusy then
        radialNotify("Дождись завершения предыдущего действия!")
        return
    end

    if not command or trim(command) == "" then
        radialNotify("Команда не указана!")
        return
    end

    local finalCommand = replaceActionValues(command, values)
    local lines = getCommands(rpLines)

    if #lines == 0 then
        radialNotify("Добавь RP-отыгровку!")
        return
    end

    radialBusy = true
    closeRadial()

    lua_thread.create(function()
        local ok, err = pcall(function()
            -- ВАЖНО: здесь НЕТ wait(), pcall только для защиты от ошибок
            -- но wait нужен... поэтому pcall убираем, а ошибку ловим иначе
        end)
        -- Выполняем без pcall, но с защитой флага через отдельную функцию
        local success, err = true, nil

        -- Отправка RP-строк
        for _, line in ipairs(lines) do
            local okSend, e = pcall(function()
                sendRadialChat(replaceActionValues(line, values))
            end)
            if not okSend then success = false; err = e; break end
            wait(1000)
        end

        if success then
            if evidenceMode == "invite" then
                pendingInviteEvidence = true
            end

            local okSend, e = pcall(function()
                sendRadialChat(finalCommand)
            end)
            if not okSend then success = false; err = e end
            wait(1000)

            if success and evidenceMode == "after" then
                local okTime, e2 = pcall(function() sampSendChat("/time") end)
                if not okTime then success = false; err = e2 end
                wait(500)
                takeScreenshot("Инвайты")
            end
        end

        radialBusy = false
        if not success then
            radialNotify("Ошибка действия: " .. tostring(err))
        end
    end)
end


local function openRadialAction(action)
    if radialBusy then
        radialNotify("Подожди завершения предыдущего действия!")
        return
    end

    radialAction = action
    radialMode = "form"

    ffi.fill(radialReason, ffi.sizeof(radialReason))
    ffi.fill(radialRank, ffi.sizeof(radialRank))
    ffi.fill(radialDuration, ffi.sizeof(radialDuration))
end

local function saveCustomRadialAction()
    local name = trim(ffi.string(customName))
    local rp = trim(ffi.string(customRp))
    local command = trim(ffi.string(customCommand))

    if name == "" or rp == "" or command == "" then
        radialNotify("Заполни название, RP-отыгровку и команду!")
        return
    end

    local count = cfg.customActions.count + 1
    cfg.customActions.count = count

    cfg["customAction" .. count] = {
        name = name,
        rp = encodeForIni(rp),
        command = encodeForIni(command)
    }

    ini.save(cfg, CONFIG_FILE)

    ffi.fill(customName, ffi.sizeof(customName))
    ffi.fill(customRp, ffi.sizeof(customRp))
    ffi.fill(customCommand, ffi.sizeof(customCommand))

    radialMode = "menu"
    radialNotify("Добавлено действие: " .. name)
end


-- =========================================
-- СТАНДАРТНЫЕ ДЕЙСТВИЯ
-- =========================================

local function confirmRadialAction()
    local values = getRadialValues()
    local id = values.id
    local reason = values.reason
    local rank = values.rank
    local duration = values.time

    if radialAction == "invite" then
        runRadialAction(
            "/me достал документы и подготовил заявление о вступлении в организацию.\n" ..
            "/do Документы готовы к оформлению.",
            "/invite " .. id,
            values,
            "invite"
        )

    elseif radialAction == "rank" then
        if not validNumber(rank, 1, 100) then
            radialNotify("Укажи корректный номер ранга!")
            return
        end

        runRadialAction(
            "/me открыл личное дело сотрудника и внёс изменения в документы\n" ..
            "/do Изменения в личном деле сотрудника внесены.",
            "/giverank " .. id .. " " .. rank,
            values,
            "after"
        )

    elseif radialAction == "fwarn" then
        if reason == "" then
            radialNotify("Укажи причину выговора!")
            return
        end

        runRadialAction(
            "/me открыл дисциплинарное дело сотрудника\n" ..
            "/do Дисциплинарное дело открыто.\n" ..
            "/me внёс информацию о нарушении в документы.",
            "/fwarn " .. id .. " " .. reason,
            values,
            "after"
        )

    elseif radialAction == "uninvite" then
        if reason == "" then
            radialNotify("Укажи причину увольнения!")
            return
        end

        runRadialAction(
            "/me открыл личное дело сотрудника.\n" ..
            "/do Личное дело сотрудника открыто.\n" ..
            "/me подготовил документы об увольнении.",
            "/uninvite " .. id .. " " .. reason,
            values,
            "after"
        )

    elseif radialAction == "fmute" then
        if duration == "" or not validNumber(duration, 1, 100000) then
            radialNotify("Укажи корректный срок мута!")
            return
        end

        if reason == "" then
            radialNotify("Укажи причину мута!")
            return
        end

        runRadialAction(
            "/me открыл журнал дисциплины организации.\n" ..
            "/do Журнал дисциплины открыт.\n" ..
            "/me внёс запись о нарушении правил радиосвязи.",
            "/fmute " .. id .. " " .. duration .. " " .. reason,
            values,
            "after"
        )

    elseif radialAction == "custom" then
        local action = radialCustomIndex > 0
            and getCustomAction(radialCustomIndex)

        if not action then
            radialNotify("Пользовательское действие не найдено!")
            return
        end

        runRadialAction(
            decodeFromIni(action.rp),
            decodeFromIni(action.command),
            values
        )
    end
end

-- =========================================
-- АНИМАЦИИ
-- =========================================

local function lerp(a, b, t) return a + (b - a) * math.min(math.max(t, 0), 1) end

local function rgba(r, g, b, a)
    return bit.bor(bit.lshift(math.floor((a or 1) * 255 + 0.5), 24),
        bit.lshift(math.floor(b * 255 + 0.5), 16),
        bit.lshift(math.floor(g * 255 + 0.5), 8),
        math.floor(r * 255 + 0.5))
end

local function hsvRgb(h, s, v)
    local i = math.floor(h * 6); local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v else return v, p, q end
end

math.randomseed(os.time())
local particles = {}
for i = 1, 25 do
    particles[i] = {
        x = math.random() * 620, y = math.random() * 800,
        vx = (math.random() - 0.5) * 0.3, vy = -0.15 - math.random() * 0.3,
        size = 1.0 + math.random() * 1.5, alpha = 0.04 + math.random() * 0.10,
        phase = math.random() * 6.28
    }
end
local tabIndicatorX = -1

-- =========================================
-- UI ПЕРЕМЕННЫЕ
-- =========================================

local showMenu           = ffi.new('bool[1]', false)
local updateAvailable    = ffi.new('bool[1]', false)
local updateRemoteVer    = ""
local updateContent      = ""
local updateDownloading  = false
local currentTab         = 1
local sequenceRunning    = false
local lastSentKey        = nil
local profileToDelete    = 0

local bufCommands        = ffi.new('char[4096]')
local bufHour            = ffi.new('char[8]')
local bufMin             = ffi.new('char[8]')
local bufSec             = ffi.new('char[8]')
local bufDelay           = ffi.new('char[16]')
local bufTimeAfter       = ffi.new('char[16]')
local bufScreenshotAfter = ffi.new('char[16]')
local bufScreenshotDelay = ffi.new('char[16]')
local bufScreenshotFolder = ffi.new('char[128]')
local bufProfileName     = ffi.new('char[128]')
local bufCurrentProfile  = ffi.new('char[128]')
local bufRenameName      = ffi.new('char[128]')
local bufExportStr       = ffi.new('char[8192]')
local bufImportStr       = ffi.new('char[8192]')
local checkTime          = ffi.new('bool[1]', false)
local checkScreenshot    = ffi.new('bool[1]', false)

local myFont = nil

-- =========================================
-- БУФЕРЫ
-- =========================================

local function setBuffer(buf, val)
    ffi.fill(buf, ffi.sizeof(buf))
    local s = tostring(val or ""); local mx = ffi.sizeof(buf) - 1
    if #s > mx then s = s:sub(1, mx) end; ffi.copy(buf, s, #s)
end

local function loadBuffers()
    setBuffer(bufCommands, decodeFromIni(activeCfg.commands))
    setBuffer(bufHour, activeCfg.hour); setBuffer(bufMin, activeCfg.min)
    setBuffer(bufSec, activeCfg.sec);   setBuffer(bufDelay, activeCfg.delay)
    setBuffer(bufTimeAfter, activeCfg.timeAfter)
    setBuffer(bufScreenshotAfter, activeCfg.screenshotAfter)
    setBuffer(bufScreenshotDelay, activeCfg.screenshotDelay)
    setBuffer(bufScreenshotFolder, activeCfg.screenshotFolder or "Собеседование")
    checkTime[0] = isEnabled(activeCfg.useTime)
    checkScreenshot[0] = isEnabled(activeCfg.useScreenshot)
    setBuffer(bufCurrentProfile, activeCfg.name or "")
    setBuffer(bufProfileName, "")
end

loadBuffers()

local function storeCurrentProfile()
    activeCfg.commands        = encodeForIni(ffi.string(bufCommands))
    activeCfg.hour            = ffi.string(bufHour)
    activeCfg.min             = ffi.string(bufMin)
    activeCfg.sec             = ffi.string(bufSec)
    activeCfg.delay           = ffi.string(bufDelay)
    activeCfg.useTime         = tostring(checkTime[0])
    activeCfg.timeAfter       = ffi.string(bufTimeAfter)
    activeCfg.useScreenshot   = tostring(checkScreenshot[0])
    activeCfg.screenshotAfter = ffi.string(bufScreenshotAfter)
    activeCfg.screenshotDelay = ffi.string(bufScreenshotDelay)
    local sF = trim(ffi.string(bufScreenshotFolder))
    if sF == "" then sF = "Скриншоты" end
    activeCfg.screenshotFolder = sF
    cfg.profiles.selected     = selectedProfile
    ini.save(cfg, CONFIG_FILE)
end

-- =========================================
-- ОПЕРАЦИИ С ПРОФИЛЯМИ
-- =========================================

local function selectProfile(index)
    if index < 1 or index > cfg.profiles.count or index == selectedProfile then return end
    storeCurrentProfile()
    selectedProfile = index; cfg.profiles.selected = index
    activeCfg = getProfile(index); loadBuffers()
    lastSentKey = nil; ini.save(cfg, CONFIG_FILE)
    notify("success", "Выбран: " .. tostring(activeCfg.name))
end

local function createProfile()
    local name = trim(ffi.string(bufProfileName))
    if name == "" then name = "Профиль " .. tostring(cfg.profiles.count + 1) end
    storeCurrentProfile()
    local idx = cfg.profiles.count + 1; cfg.profiles.count = idx
    cfg["profile" .. tostring(idx)] = defaultProfile(name)
    cfg["profile" .. tostring(idx)].created = getFormattedDate()
    selectedProfile = idx; cfg.profiles.selected = idx
    activeCfg = getProfile(idx); loadBuffers()
    lastSentKey = nil; ini.save(cfg, CONFIG_FILE)
    notify("success", "Создан: " .. name)
end

local function deleteProfile(index)
    if cfg.profiles.count <= 1 then
        notify("error", "Нельзя удалить последний профиль!"); return
    end
    local name = getProfile(index).name
    for i = index, cfg.profiles.count - 1 do
        cfg["profile" .. tostring(i)] = cfg["profile" .. tostring(i + 1)]
    end
    cfg["profile" .. tostring(cfg.profiles.count)] = nil
    cfg.profiles.count = cfg.profiles.count - 1
    if selectedProfile >= index and selectedProfile > 1 then
        selectedProfile = selectedProfile - 1
    end
    if selectedProfile > cfg.profiles.count then
        selectedProfile = cfg.profiles.count
    end
    cfg.profiles.selected = selectedProfile
    activeCfg = getProfile(selectedProfile); loadBuffers()
    lastSentKey = nil; ini.save(cfg, CONFIG_FILE)
    notify("success", "Удалён: " .. name)
end

local function renameProfile(index, newName)
    getProfile(index).name = newName
    if index == selectedProfile then setBuffer(bufCurrentProfile, newName) end
    ini.save(cfg, CONFIG_FILE)
    notify("success", "Переименован: " .. newName)
end

local function duplicateProfile(index)
    local src = getProfile(index)
    local idx = cfg.profiles.count + 1; cfg.profiles.count = idx
    local np = {}; for k, v in pairs(src) do np[k] = v end
    np.name = src.name .. " (копия)"
    np.use_count = "0"; np.last_used = ""
    np.created = getFormattedDate()
    cfg["profile" .. tostring(idx)] = np
    storeCurrentProfile()
    selectedProfile = idx; cfg.profiles.selected = idx
    activeCfg = getProfile(idx); loadBuffers()
    lastSentKey = nil; ini.save(cfg, CONFIG_FILE)
    notify("success", "Клонирован: " .. np.name)
end

local function swapProfiles(a, b)
    if a < 1 or a > cfg.profiles.count or b < 1 or b > cfg.profiles.count then return end
    storeCurrentProfile()
    local kA, kB = "profile" .. tostring(a), "profile" .. tostring(b)
    cfg[kA], cfg[kB] = cfg[kB], cfg[kA]
    if selectedProfile == a then selectedProfile = b
    elseif selectedProfile == b then selectedProfile = a end
    cfg.profiles.selected = selectedProfile
    activeCfg = getProfile(selectedProfile); loadBuffers()
    ini.save(cfg, CONFIG_FILE)
    notify("success", "Профили переставлены!")
end

local function toggleProfile(index)
    local p = getProfile(index)
    local was = isEnabled(p.enabled)
    p.enabled = was and "false" or "true"
    ini.save(cfg, CONFIG_FILE)
    notify(was and "info" or "success",
        (was and "Деактивирован: " or "Активирован: ") .. p.name)
end

-- Экспорт/Импорт
local function exportProfileStr(index)
    local p = getProfile(index)
    return table.concat({
        "LSP", p.name or "", p.commands or "",
        p.hour or "12", p.min or "00", p.sec or "00",
        p.delay or "3", p.useTime or "true", p.timeAfter or "3",
        p.useScreenshot or "true", p.screenshotAfter or "3",
        p.screenshotDelay or "100", p.screenshotFolder or "Собеседование"
    }, EXPORT_SEP)
end

local function importProfileStr(str)
    local parts = {}; local pos = 1
    while true do
        local s, e = str:find(EXPORT_SEP, pos, true)
        if not s then parts[#parts + 1] = str:sub(pos); break end
        parts[#parts + 1] = str:sub(pos, s - 1); pos = e + 1
    end
    if parts[1] ~= "LSP" or #parts < 12 then
        notify("error", "Неверный формат! Строка должна начинаться с LSP")
        return false
    end
    storeCurrentProfile()
    local np = defaultProfile(parts[2])
    np.commands = parts[3];  np.hour = parts[4]
    np.min = parts[5];      np.sec = parts[6]
    np.delay = parts[7];    np.useTime = parts[8]
    np.timeAfter = parts[9]; np.useScreenshot = parts[10]
    np.screenshotAfter = parts[11]; np.screenshotDelay = parts[12]
    if parts[13] and parts[13] ~= "" then np.screenshotFolder = parts[13] end
    np.created = getFormattedDate()
    local idx = cfg.profiles.count + 1; cfg.profiles.count = idx
    cfg["profile" .. tostring(idx)] = np
    selectedProfile = idx; cfg.profiles.selected = idx
    activeCfg = getProfile(idx); loadBuffers()
    lastSentKey = nil; ini.save(cfg, CONFIG_FILE)
    notify("success", "Импортирован: " .. np.name)
    return true
end

-- =========================================
-- СТИЛИЗАЦИЯ
-- =========================================

imgui.OnInitialize(function()
    local fontPath = getFolderPath(0x14) .. '\\tahoma.ttf'
    local io = imgui.GetIO()
    myFont = io.Fonts:AddFontFromFileTTF(fontPath, 16.0, nil, io.Fonts:GetGlyphRangesCyrillic())

    local s = imgui.GetStyle()
    s.WindowRounding = 14.0;  s.FrameRounding = 8.0
    s.ChildRounding = 10.0;   s.PopupRounding = 10.0
    s.ScrollbarRounding = 8.0; s.GrabRounding = 8.0
    s.WindowBorderSize = 0.0;  s.FrameBorderSize = 0.0; s.PopupBorderSize = 0.0
    s.WindowPadding = imgui.ImVec2(18, 16)
    s.FramePadding  = imgui.ImVec2(10, 8)
    s.ItemSpacing   = imgui.ImVec2(9, 8)
    s.ItemInnerSpacing = imgui.ImVec2(6, 6)

    s.Colors[imgui.Col.WindowBg]      = imgui.ImVec4(0.055, 0.065, 0.095, 0.94)
    s.Colors[imgui.Col.TitleBg]       = imgui.ImVec4(0.045, 0.055, 0.085, 0.98)
    s.Colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.065, 0.080, 0.120, 0.98)
    s.Colors[imgui.Col.FrameBg]        = imgui.ImVec4(0.075, 0.095, 0.145, 0.70)
    s.Colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.115, 0.155, 0.235, 0.80)
    s.Colors[imgui.Col.FrameBgActive]  = imgui.ImVec4(0.145, 0.195, 0.295, 0.90)
    s.Colors[imgui.Col.Button]        = imgui.ImVec4(0.13, 0.26, 0.46, 0.85)
    s.Colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.19, 0.37, 0.60, 0.95)
    s.Colors[imgui.Col.ButtonActive]  = imgui.ImVec4(0.10, 0.22, 0.38, 1.00)
    s.Colors[imgui.Col.Separator]     = imgui.ImVec4(0.18, 0.24, 0.34, 0.35)
    s.Colors[imgui.Col.CheckMark]     = imgui.ImVec4(0.35, 0.72, 1.0, 1.0)
    s.Colors[imgui.Col.PopupBg]       = imgui.ImVec4(0.055, 0.070, 0.105, 0.96)
    s.Colors[imgui.Col.Header]        = imgui.ImVec4(0.11, 0.21, 0.36, 0.55)
    s.Colors[imgui.Col.HeaderHovered] = imgui.ImVec4(0.17, 0.31, 0.51, 0.70)
    s.Colors[imgui.Col.HeaderActive]  = imgui.ImVec4(0.14, 0.27, 0.45, 0.80)
    s.Colors[imgui.Col.ScrollbarBg]          = imgui.ImVec4(0.035, 0.045, 0.070, 0.50)
    s.Colors[imgui.Col.ScrollbarGrab]        = imgui.ImVec4(0.17, 0.27, 0.40, 0.55)
    s.Colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(0.23, 0.37, 0.55, 0.70)
    s.Colors[imgui.Col.ScrollbarGrabActive]  = imgui.ImVec4(0.30, 0.45, 0.65, 0.85)
    s.Colors[imgui.Col.Text]         = imgui.ImVec4(0.90, 0.92, 0.95, 1.0)
    s.Colors[imgui.Col.TextDisabled] = imgui.ImVec4(0.42, 0.48, 0.56, 1.0)
    s.Colors[imgui.Col.ResizeGrip]        = imgui.ImVec4(0.18, 0.33, 0.52, 0.25)
    s.Colors[imgui.Col.ResizeGripHovered] = imgui.ImVec4(0.28, 0.48, 0.72, 0.50)
    s.Colors[imgui.Col.ResizeGripActive]  = imgui.ImVec4(0.33, 0.55, 0.78, 0.70)
end)

-- =========================================
-- СОХРАНЕНИЕ / СКРИНШОТ / ЗАПУСК
-- =========================================

local function saveSettings()
    local commands = ffi.string(bufCommands)
    local h, m, s = tonumber(ffi.string(bufHour)), tonumber(ffi.string(bufMin)), tonumber(ffi.string(bufSec))
    local delay = tonumber(ffi.string(bufDelay))
    local tA = tonumber(ffi.string(bufTimeAfter))
    local sA = tonumber(ffi.string(bufScreenshotAfter))
    local sD = tonumber(ffi.string(bufScreenshotDelay))
    local cl = getCommands(commands)
    if #cl == 0 then notify("error", "Добавь хотя бы одну команду!"); return false end
    if not validTime(h, m, s) then notify("error", "Неверное время!"); return false end
    if not validNumber(delay, 0, 3600) then notify("error", "Задержка: 0-3600!"); return false end
    if not validNumber(tA, 1, 10000) then notify("error", "Неверное кол-во для /time!"); return false end
    if not validNumber(sA, 1, 10000) then notify("error", "Неверное кол-во для скриншота!"); return false end
    if not validNumber(sD, 100, 3600) then notify("error", "Задержка скриншота: мин 100!"); return false end
    activeCfg.commands = encodeForIni(commands)
    activeCfg.hour = tostring(h); activeCfg.min = tostring(m); activeCfg.sec = tostring(s)
    activeCfg.delay = tostring(delay)
    activeCfg.useTime = tostring(checkTime[0]); activeCfg.timeAfter = tostring(tA)
    activeCfg.useScreenshot = tostring(checkScreenshot[0])
    activeCfg.screenshotAfter = tostring(sA); activeCfg.screenshotDelay = tostring(sD)
    activeCfg.enabled = "true"; cfg.profiles.selected = selectedProfile
    lastSentKey = nil; ini.save(cfg, CONFIG_FILE)
    notify("success", "Сохранено! Команд: " .. #cl); return true
end

local function getDocumentsPath()
    local userProfile = os.getenv("USERPROFILE")
    if userProfile then return userProfile .. "\\Documents" end
    local homeDrive = os.getenv("HOMEDRIVE")
    local homePath = os.getenv("HOMEPATH")
    if homeDrive and homePath then return homeDrive .. homePath .. "\\Documents" end
    return nil
end

local function ensureDirectory(pathAnsi)
    pathAnsi = pathAnsi:gsub("/", "\\")
    local drive, rest = pathAnsi:match("^([A-Za-z]:\\)(.*)")
    if not drive then return false end
    local cur = drive
    local pos = 1
    while true do
        local slash = rest:find("\\", pos, true)
        local part = slash and rest:sub(pos, slash - 1) or rest:sub(pos)
        if part ~= "" then
            cur = cur .. part
            local w = toWide(cur)
            if w then ffi.C.CreateDirectoryW(w, nil) end
            cur = cur .. "\\"
        end
        if not slash then break end
        pos = slash + 1
    end
    return true
end

local function sanitizeFolderName(name)
    local s = tostring(name or ""):gsub('[%\\%/%:%*%?%"%<%>%|]', "_")
    s = trim(s)
    if s == "" then s = "Скриншоты" end
    return s
end

local function getDateFolderNameUtf8()
    local t = getWinTime()

    local days = {
        "Воскресенье", "Понедельник", "Вторник",
        "Среда", "Четверг", "Пятница", "Суббота"
    }

    local months = {
        "Января", "Февраля", "Марта", "Апреля",
        "Мая", "Июня", "Июля", "Августа",
        "Сентября", "Октября", "Ноября", "Декабря"
    }

    local dayName = days[t.wday] or "День"
    local monthName = months[t.month] or tostring(t.month)

    return string.format(
        "%s - %02d %s",
        dayName,
        t.day,
        monthName
    )
end

local screensBusy = false

local function getGameIncomingScreenshots()
    if screensBusy then return {} end
    screensBusy = true
    local ok, result = pcall(function()
        local docs = getDocumentsPath()
        if not docs then return {} end
        local searchBases = {
            docs .. "\\GTA San Andreas User Files\\SAMP\\arizona\\screens",
            docs .. "\\GTA San Andreas User Files\\SAMP\\screens"
        }
        local incoming = {}
        for _, baseDir in ipairs(searchBases) do
            if lfs.attributes(baseDir) then
                for entry in lfs.dir(baseDir) do
                    if entry ~= "." and entry ~= ".." then
                        local fullPath = baseDir .. "\\" .. entry
                        local attr = lfs.attributes(fullPath)
                        if attr then
                            local firstChar = entry:sub(1, 1)
                            local isDateDir = (firstChar >= "0" and firstChar <= "9")
                            if attr.mode == "directory" and isDateDir then
                                for f in lfs.dir(fullPath) do
                                    if f ~= "." and f ~= ".." then
                                        local fLower = f:lower()
                                        if fLower:sub(-4) == ".jpg" or fLower:sub(-4) == ".png" then
                                            local fp = fullPath .. "\\" .. f
                                            local fattr = lfs.attributes(fp)
                                            if fattr then
                                                incoming[#incoming + 1] = { path = fp, name = f, time = fattr.modification, size = fattr.size }
                                            end
                                        end
                                    end
                                end
                            elseif attr.mode == "file" then
                                local lower = entry:lower()
                                if lower:sub(-4) == ".jpg" or lower:sub(-4) == ".png" then
                                    incoming[#incoming + 1] = { path = fullPath, name = entry, time = attr.modification, size = attr.size }
                                end
                            end
                        end
                    end
                end
            end
        end
        table.sort(incoming, function(a, b) return a.time > b.time end)
        return incoming
    end)
    screensBusy = false
    if ok then return result else return {} end
end

local function organizeScreenshot(customFolderUtf8)
    local docs = getDocumentsPath()
    if not docs then notify("error", "Не найден путь к Документам"); return end
    local baseScreens = docs .. "\\GTA San Andreas User Files\\SAMP\\arizona\\screens"
    if not lfs.attributes(baseScreens) then
        baseScreens = docs .. "\\GTA San Andreas User Files\\SAMP\\screens"
    end
    if not lfs.attributes(baseScreens) then
        notify("error", "Не найдена папка screens игры")
        return
    end

    local fNameUtf8 = sanitizeFolderName(customFolderUtf8 or "Собеседование")
    local dNameUtf8 = getDateFolderNameUtf8()
    local fNameAnsi = utf8ToAnsi(fNameUtf8)
    local dNameAnsi = utf8ToAnsi(dNameUtf8)
    local targetDirAnsi = baseScreens .. "\\" .. fNameAnsi .. "\\" .. dNameAnsi
    ensureDirectory(targetDirAnsi)

    local initialScreens = getGameIncomingScreenshots()
    local initialPath = initialScreens[1] and initialScreens[1].path or nil

    local foundPath, foundName = nil, nil
    for attempt = 1, 25 do
        wait(400)
        local top = getGameIncomingScreenshots()[1]
        if top and top.path ~= initialPath and (top.size or 0) > 0 then
            local prevSize = top.size
            wait(400)
            local again = getGameIncomingScreenshots()[1]
            if again and again.path == top.path and (again.size or 0) == prevSize and prevSize > 0 then
                foundPath, foundName = again.path, again.name
                break
            end
        end
    end

    if not foundPath then
        notify("error", "Скриншот не найден или не сохранился")
        return
    end

    local newPathAnsi = targetDirAnsi .. "\\" .. foundName
    if foundPath == newPathAnsi then return end

    wait(300)

    local srcW = toWide(foundPath)
    local dstW = toWide(newPathAnsi)
    if not srcW or not dstW then
        notify("error", "Не удалось конвертировать путь (CP1251)")
        return
    end
    if ffi.C.MoveFileW(srcW, dstW) ~= 0 then
        notify("info", "Скрин сохранен: " .. fNameUtf8 .. " -> " .. dNameUtf8)
    else
        local err = tonumber(ffi.C.GetLastError()) or 0
        notify("error", string.format("Не удалось перенести скриншот (WinAPI error %d)", err))
    end
end

local screenshotInProgress = false

takeScreenshot = function(customFolderUtf8)
    if not setVirtualKeyDown then notify("error", "Нет setVirtualKeyDown!"); return end
    if screenshotInProgress then
        notify("info", "Скриншот уже выполняется, подождите...")
        return
    end
    screenshotInProgress = true
    setVirtualKeyDown(0x77, true); wait(100); setVirtualKeyDown(0x77, false)
    organizeScreenshot(customFolderUtf8)
    screenshotInProgress = false
end

-- =========================================
-- ОТСЛЕЖИВАНИЕ ПРИНЯТИЯ ИНВАЙТА
-- =========================================

function sampev.onServerMessage(color, text)
    if not pendingInviteEvidence then
        return
    end

    local message = tostring(text or "")
    local acceptedText = u8:decode("Приветствуем нового члена нашей организации")

    if message:find(acceptedText, 1, true) then
        pendingInviteEvidence = false

        lua_thread.create(function()
            wait(100)
            sampSendChat("/time")
            wait(500)
            takeScreenshot("Инвайты")
            radialNotify("Игрок принял приглашение! /time и скриншот выполнены.")
        end)
    end
end

local function runSequence(profile)
    if sequenceRunning then return end
    sequenceRunning = true
    profile = profile or activeCfg
    local cmds = getCommands(decodeFromIni(tostring(profile.commands or "")))
    local delay = tonumber(profile.delay) or 3
    local uT, tA = isEnabled(profile.useTime), tonumber(profile.timeAfter) or 1
    local uS = isEnabled(profile.useScreenshot)
    local sA = tonumber(profile.screenshotAfter) or 1
    local sD = math.max(100, tonumber(profile.screenshotDelay) or 100)
    local sF = profile.screenshotFolder or "Собеседование"
    local mc, ts, sd = 0, false, false

    for i, cmd in ipairs(cmds) do
        sampSendChat(u8:decode(cmd)); mc = mc + 1
        if uT and not ts and mc >= tA then
            wait(100); sampSendChat("/time"); ts = true
        end
        if uS and not sd and mc >= sA and (not uT or ts) then
            wait(sD); takeScreenshot(sF); sd = true
        end
        if i < #cmds then wait(math.floor(delay * 1000)) end
    end

    if uT and not ts then wait(100); sampSendChat("/time") end
    if uS and not sd then wait(sD); takeScreenshot(sF) end

    profile.use_count = tostring((tonumber(profile.use_count) or 0) + 1)
    profile.last_used = getFormattedDate()
    ini.save(cfg, CONFIG_FILE)
    sequenceRunning = false
end

-- =========================================
-- CUSTOM DRAWING
-- =========================================

local function drawAnimBg()
    local dl, wp, ws, t = imgui.GetWindowDrawList(), imgui.GetWindowPos(), imgui.GetWindowSize(), os.clock()
    local h1 = 0.65 + 0.10 * math.sin(t * 0.4)
    local h2 = 0.65 + 0.10 * math.sin(t * 0.4 + 0.8)
    local r1, g1, b1 = hsvRgb(h1, 0.75, 0.90)
    local r2, g2, b2 = hsvRgb(h2, 0.75, 0.90)
    dl:AddRectFilledMultiColor(imgui.ImVec2(wp.x, wp.y), imgui.ImVec2(wp.x + ws.x, wp.y + 3),
        rgba(r1,g1,b1,0.90), rgba(r2,g2,b2,0.90), rgba(r2,g2,b2,0.35), rgba(r1,g1,b1,0.35))
    dl:AddRectFilledMultiColor(imgui.ImVec2(wp.x, wp.y+3), imgui.ImVec2(wp.x+ws.x, wp.y+6),
        rgba(1,1,1,0.055), rgba(1,1,1,0.02), rgba(1,1,1,0), rgba(1,1,1,0))
    dl:AddRectFilledMultiColor(wp, imgui.ImVec2(wp.x+ws.x*0.4, wp.y+ws.y*0.25),
        rgba(0.3,0.5,0.9,0.035), rgba(0.3,0.5,0.9,0), rgba(0.3,0.5,0.9,0), rgba(0.3,0.5,0.9,0))
    dl:AddRectFilledMultiColor(imgui.ImVec2(wp.x+ws.x*0.6, wp.y+ws.y*0.75), imgui.ImVec2(wp.x+ws.x, wp.y+ws.y),
        rgba(0.25,0.1,0.45,0), rgba(0.25,0.1,0.45,0), rgba(0.25,0.1,0.45,0.04), rgba(0.25,0.1,0.45,0))
    for _, p in ipairs(particles) do
        p.x = p.x + p.vx; p.y = p.y + p.vy
        if p.y < -10 then p.y = ws.y + 10; p.x = math.random() * ws.x end
        if p.x < -10 then p.x = ws.x + 10 end
        if p.x > ws.x + 10 then p.x = -10 end
        local pa = p.alpha * (0.6 + 0.4 * math.sin(t * 1.5 + p.phase))
        local ph = 0.65 + 0.08 * math.sin(t * 0.3 + p.phase)
        local pr, pg, pb = hsvRgb(ph, 0.4, 0.9)
        dl:AddCircleFilled(imgui.ImVec2(wp.x + p.x, wp.y + p.y), p.size, rgba(pr, pg, pb, pa), 8)
    end
    local bp = 0.10 + 0.05 * math.sin(t * 0.8)
    local bh = 0.65 + 0.08 * math.sin(t * 0.5)
    local br, bg, bb = hsvRgb(bh, 0.4, 0.7)
    dl:AddRect(imgui.ImVec2(wp.x+1,wp.y+1), imgui.ImVec2(wp.x+ws.x-1,wp.y+ws.y-1),
        rgba(br,bg,bb,bp), 14.0)
end

local function gradSep()
    imgui.Spacing()
    local dl, pos = imgui.GetWindowDrawList(), imgui.GetCursorScreenPos()
    local w, t = imgui.GetContentRegionAvail().x, os.clock()
    local hue = 0.65 + 0.08 * math.sin(t * 0.6)
    local r, g, b = hsvRgb(hue, 0.5, 0.8)
    local mid = pos.x + w / 2
    dl:AddRectFilledMultiColor(imgui.ImVec2(pos.x,pos.y), imgui.ImVec2(mid,pos.y+1),
        rgba(r,g,b,0), rgba(r,g,b,0.5), rgba(r,g,b,0.5), rgba(r,g,b,0))
    dl:AddRectFilledMultiColor(imgui.ImVec2(mid,pos.y), imgui.ImVec2(pos.x+w,pos.y+1),
        rgba(r,g,b,0.5), rgba(r,g,b,0), rgba(r,g,b,0), rgba(r,g,b,0.5))
    imgui.Dummy(imgui.ImVec2(0, 1)); imgui.Spacing()
end

local function secTitle(text)
    local t = os.clock()
    local hue = 0.65 + 0.08 * math.sin(t * 0.5)
    local r, g, b = hsvRgb(hue, 0.5, 0.95)
    imgui.TextColored(imgui.ImVec4(r, g, b, 0.85 + 0.15 * math.sin(t * 1.2)), text)
end

local function accBtn(text, size, variant)
    local t = os.clock(); variant = variant or 0
    local hue = 0.645 + 0.075 * math.sin(t * 0.5 + variant * 0.5)
    local cr, cg, cb = hsvRgb(hue, 0.55, 0.50)
    local hr, hg, hb = hsvRgb(hue, 0.45, 0.65)
    local ar, ag, ab = hsvRgb(hue, 0.65, 0.35)
    local pos, dl = imgui.GetCursorScreenPos(), imgui.GetWindowDrawList()
    dl:AddRectFilled(imgui.ImVec2(pos.x-2,pos.y-2), imgui.ImVec2(pos.x+size.x+2,pos.y+size.y+2),
        rgba(cr,cg,cb,0.06), 10.0)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(cr,cg,cb,0.85))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(hr,hg,hb,0.95))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(ar,ag,ab,1))
    local r = imgui.Button(text, size); imgui.PopStyleColor(3); return r
end

local function redBtn(text, size)
    local pos, dl = imgui.GetCursorScreenPos(), imgui.GetWindowDrawList()
    dl:AddRectFilled(imgui.ImVec2(pos.x-2,pos.y-2), imgui.ImVec2(pos.x+size.x+2,pos.y+size.y+2),
        rgba(0.6,0.1,0.1,0.06), 10.0)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.55,0.12,0.12,0.85))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.70,0.18,0.18,0.95))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.45,0.08,0.08,1))
    local r = imgui.Button(text, size); imgui.PopStyleColor(3); return r
end

local function greenBtn(text, size)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12,0.45,0.20,0.85))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18,0.55,0.28,0.95))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.08,0.38,0.15,1))
    local r = imgui.Button(text, size); imgui.PopStyleColor(3); return r
end

local function grayBtn(text, size)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.30,0.30,0.30,0.65))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.40,0.40,0.40,0.80))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.25,0.25,0.25,1))
    local r = imgui.Button(text, size); imgui.PopStyleColor(3); return r
end

local function drawTabBar()
    local dl, t = imgui.GetWindowDrawList(), os.clock()
    local tw, th = 174, 38
    local hue = 0.645 + 0.075 * math.sin(t * 0.5)
    local cr, cg, cb = hsvRgb(hue, 0.55, 0.60)
    local names = {"Редактор", "Профили", "Настройки"}
    local positions = {}
    for idx, name in ipairs(names) do
        if idx > 1 then imgui.SameLine() end
        positions[idx] = imgui.GetCursorScreenPos()
        local a  = currentTab == idx and 0.60 or 0.12
        local ah = currentTab == idx and 0.72 or 0.28
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(cr,cg,cb,a))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(cr,cg,cb,ah))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(cr,cg,cb,0.78))
        if imgui.Button(name, imgui.ImVec2(tw, th)) then currentTab = idx end
        imgui.PopStyleColor(3)
    end
    local iy = positions[1].y + th + 2
    local tx = positions[currentTab] and positions[currentTab].x or 0
    if tabIndicatorX < 0 then tabIndicatorX = tx
    else tabIndicatorX = lerp(tabIndicatorX, tx, 0.12) end
    local ir, ig, ib = hsvRgb(0.65 + 0.08 * math.sin(t * 0.7), 0.7, 1.0)
    dl:AddRectFilled(imgui.ImVec2(tabIndicatorX, iy), imgui.ImVec2(tabIndicatorX + tw, iy + 2),
        rgba(ir,ig,ib,0.90), 2.0)
    dl:AddRectFilledMultiColor(imgui.ImVec2(tabIndicatorX, iy+2), imgui.ImVec2(tabIndicatorX+tw, iy+14),
        rgba(ir,ig,ib,0.22), rgba(ir,ig,ib,0.22), rgba(ir,ig,ib,0), rgba(ir,ig,ib,0))
    imgui.Dummy(imgui.ImVec2(0, 14))
end

local function drawStatusDot(running)
    local dl, pos, t = imgui.GetWindowDrawList(), imgui.GetCursorScreenPos(), os.clock()
    local cx, cy = pos.x + 7, pos.y + 7
    if running then
        local p = 0.5 + 0.5 * math.sin(t * 4); local sz = 4 + p * 2
        dl:AddCircleFilled(imgui.ImVec2(cx,cy), sz+4, rgba(0.2,1,0.4,0.08+0.1*p), 16)
        dl:AddCircleFilled(imgui.ImVec2(cx,cy), sz, rgba(0.2,1,0.4,0.75+0.25*p), 12)
    else
        local p = 0.5 + 0.5 * math.sin(t * 1.5)
        dl:AddCircleFilled(imgui.ImVec2(cx,cy), 4, rgba(0.4,0.55,0.85,0.35+0.3*p), 10)
    end
    imgui.Dummy(imgui.ImVec2(14, 14))
end

-- =========================================
-- ВКЛ 1: РЕДАКТОР
-- =========================================

local function drawEditorTab()
    secTitle("РЕДАКТОР ПРОФИЛЯ")
    imgui.Text("Текущий профиль:")
    imgui.PushItemWidth(540)
    imgui.InputText("##curprof", bufCurrentProfile, ffi.sizeof(bufCurrentProfile),
        imgui.InputTextFlags.ReadOnly)
    imgui.PopItemWidth()

    gradSep()

    imgui.Text("Команды (каждая с новой строки):")
    imgui.PushItemWidth(540)
    imgui.InputTextMultiline("##cmds", bufCommands, 4096, imgui.ImVec2(540, 165))
    imgui.PopItemWidth()

    gradSep()

    imgui.Text("Время запуска (часы ПК):")
    imgui.PushItemWidth(85)
    imgui.InputText("##h", bufHour, 8); imgui.SameLine(); imgui.Text(":")
    imgui.SameLine(); imgui.InputText("##m", bufMin, 8); imgui.SameLine(); imgui.Text(":")
    imgui.SameLine(); imgui.InputText("##s", bufSec, 8)
    imgui.PopItemWidth()
    imgui.Spacing()
    imgui.Text("Задержка между командами (сек):")
    imgui.PushItemWidth(140)
    imgui.InputText("##del", bufDelay, 16)
    imgui.PopItemWidth()
    imgui.Spacing()

    if accBtn("СОХРАНИТЬ И АКТИВИРОВАТЬ", imgui.ImVec2(540, 40), 0) then saveSettings() end
    imgui.Spacing()
    if accBtn("ЗАПУСТИТЬ СЕЙЧАС", imgui.ImVec2(540, 38), 1) then
        if not sequenceRunning then
            storeCurrentProfile()
            if settingsValid(activeCfg) then lua_thread.create(runSequence, activeCfg)
            else notify("error", "Сначала сохрани корректные настройки!") end
        else notify("error", "Последовательность уже выполняется!") end
    end
    imgui.Spacing()

    local now = os.date("*t"); local tc = os.clock()
    imgui.Text("Время:"); imgui.SameLine()
    local th = 0.65 + 0.08 * math.sin(tc * 0.5)
    local tr, tg, tb = hsvRgb(th, 0.55, 1.0)
    imgui.TextColored(imgui.ImVec4(tr,tg,tb,1), string.format("%02d:%02d:%02d", now.hour, now.min, now.sec))
    imgui.SameLine(0, 25)
    drawStatusDot(sequenceRunning); imgui.SameLine()
    if sequenceRunning then
        imgui.TextColored(imgui.ImVec4(0.25,1,0.5, 0.7+0.3*math.sin(tc*3)), "Выполняется...")
    else
        imgui.TextColored(imgui.ImVec4(0.5,0.55,0.65,0.8), "Ожидание")
    end
end

-- =========================================
-- ВКЛ 2: ПРОФИЛИ
-- =========================================

local function drawProfileInfo()
    local p = getProfile(selectedProfile)
    local ct = decodeFromIni(tostring(p.commands or ""))
    local cc = #getCommands(ct)
    local uses = tonumber(p.use_count) or 0

    secTitle("ИНФОРМАЦИЯ")
    imgui.Text(string.format("Команд: %d  |  Время: %s:%s:%s  |  Задержка: %sс",
        cc, p.hour, p.min, p.sec, p.delay))
    imgui.Text(string.format("/time: %s  |  Скриншот: %s%s",
        isEnabled(p.useTime) and ("ON (после " .. p.timeAfter .. ")") or "OFF",
        isEnabled(p.useScreenshot) and ("ON (после " .. p.screenshotAfter .. ")") or "OFF",
        isEnabled(p.useScreenshot) and (" [" .. (p.screenshotFolder or "Собеседование") .. "]") or ""))
    imgui.Text(string.format("Автозапуск: %s  |  Использований: %d",
        isEnabled(p.enabled) and "ON" or "OFF", uses))
    if p.created and p.created ~= "" then
        imgui.TextColored(imgui.ImVec4(0.5,0.55,0.65,0.8), "Создан: " .. p.created) end
    if p.last_used and p.last_used ~= "" then
        imgui.TextColored(imgui.ImVec4(0.5,0.55,0.65,0.8), "Последний запуск: " .. p.last_used) end
end

local function drawProfilesTab()
    secTitle("МЕНЕДЖЕР ПРОФИЛЕЙ")

    imgui.BeginChild("##plist", imgui.ImVec2(540, 155), true)
    for i = 1, cfg.profiles.count do
        local prof = getProfile(i)
        local isSel = (selectedProfile == i)
        local isOn = isEnabled(prof.enabled)
        local uses = tonumber(prof.use_count) or 0
        if not isOn then
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.45,0.48,0.55,0.75))
        end
        local label = string.format("%s %d. %s  (%dx)%s##p%d",
            isOn and "[ON] " or "[OFF]", i, prof.name, uses, isSel and "  <<" or "", i)
        if imgui.Selectable(label, isSel) then selectProfile(i) end
        if not isOn then imgui.PopStyleColor() end
    end
    imgui.EndChild()

    if accBtn("ПЕРЕИМЕНОВАТЬ", imgui.ImVec2(170, 34), 0) then
        setBuffer(bufRenameName, activeCfg.name or ""); imgui.OpenPopup("rename_pop")
    end
    imgui.SameLine()
    if accBtn("КЛОНИРОВАТЬ", imgui.ImVec2(170, 34), 1) then
        duplicateProfile(selectedProfile)
    end
    imgui.SameLine()
    if redBtn("УДАЛИТЬ", imgui.ImVec2(170, 34)) then
        profileToDelete = selectedProfile; imgui.OpenPopup("delete_pop")
    end

    if accBtn("ВВЕРХ", imgui.ImVec2(126, 34), 0) then
        swapProfiles(selectedProfile, selectedProfile - 1)
    end
    imgui.SameLine()
    if accBtn("ВНИЗ", imgui.ImVec2(126, 34), 1) then
        swapProfiles(selectedProfile, selectedProfile + 1)
    end
    imgui.SameLine()
    local isAct = isEnabled(activeCfg.enabled)
    if isAct then
        if greenBtn(isAct and "АКТИВЕН" or "", imgui.ImVec2(260, 34)) then
            toggleProfile(selectedProfile)
        end
    else
        if grayBtn("ДЕАКТИВИРОВАН", imgui.ImVec2(260, 34)) then
            toggleProfile(selectedProfile)
        end
    end

    gradSep()

    drawProfileInfo()

    gradSep()

    imgui.Text("Новый профиль:")
    imgui.PushItemWidth(330)
    imgui.InputText("##newname", bufProfileName, 128)
    imgui.PopItemWidth()
    imgui.SameLine()
    if accBtn("СОЗДАТЬ", imgui.ImVec2(195, 32), 2) then createProfile() end

    imgui.Spacing()

    if accBtn("ЭКСПОРТ", imgui.ImVec2(260, 34), 0) then
        setBuffer(bufExportStr, exportProfileStr(selectedProfile))
        imgui.OpenPopup("export_pop")
    end
    imgui.SameLine()
    if accBtn("ИМПОРТ", imgui.ImVec2(260, 34), 1) then
        setBuffer(bufImportStr, ""); imgui.OpenPopup("import_pop")
    end

    if imgui.BeginPopup("rename_pop") then
        imgui.Text("Новое имя профиля:")
        imgui.PushItemWidth(300)
        imgui.InputText("##rnm", bufRenameName, 128)
        imgui.PopItemWidth()
        if imgui.Button("ПРИМЕНИТЬ", imgui.ImVec2(300, 33)) then
            local nn = trim(ffi.string(bufRenameName))
            if nn ~= "" then renameProfile(selectedProfile, nn); imgui.CloseCurrentPopup() end
        end
        imgui.EndPopup()
    end

    if imgui.BeginPopup("delete_pop") then
        imgui.Text("Удалить профиль?")
        imgui.TextColored(imgui.ImVec4(1,0.7,0.3,1), tostring(getProfile(profileToDelete).name))
        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.65,0.12,0.12,0.85))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.80,0.18,0.18,0.95))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.55,0.08,0.08,1))
        if imgui.Button("ДА, УДАЛИТЬ", imgui.ImVec2(140, 30)) then
            deleteProfile(profileToDelete); imgui.CloseCurrentPopup()
        end
        imgui.PopStyleColor(3)
        imgui.SameLine()
        if imgui.Button("ОТМЕНА", imgui.ImVec2(140, 30)) then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end

    if imgui.BeginPopup("export_pop") then
        imgui.Text("Скопируй строку (Ctrl+A, Ctrl+C):")
        imgui.PushItemWidth(500)
        imgui.InputText("##expstr", bufExportStr, ffi.sizeof(bufExportStr),
            imgui.InputTextFlags.ReadOnly + imgui.InputTextFlags.AutoSelectAll)
        imgui.PopItemWidth()
        imgui.EndPopup()
    end

    if imgui.BeginPopup("import_pop") then
        imgui.Text("Вставь строку профиля (Ctrl+V):")
        imgui.PushItemWidth(500)
        imgui.InputText("##impstr", bufImportStr, ffi.sizeof(bufImportStr))
        imgui.PopItemWidth()
        if imgui.Button("ИМПОРТИРОВАТЬ", imgui.ImVec2(300, 33)) then
            if importProfileStr(ffi.string(bufImportStr)) then imgui.CloseCurrentPopup() end
        end
        imgui.EndPopup()
    end
end

-- =========================================
-- ВКЛ 3: НАСТРОЙКИ
-- =========================================

local function drawSettingsTab()
    secTitle("НАСТРОЙКИ АВТОМАТИЗАЦИИ")
    gradSep()

    imgui.Text("КОМАНДА /time")
    imgui.Checkbox("Автоматически отправлять /time", checkTime)
    if checkTime[0] then
        imgui.Text("После какого сообщения:")
        imgui.PushItemWidth(140); imgui.InputText("##ta", bufTimeAfter, 16); imgui.PopItemWidth()
    end
    gradSep()

    imgui.Text("СКРИНШОТ")
    imgui.Checkbox("Автоматически делать скриншот", checkScreenshot)
    if checkScreenshot[0] then
        imgui.Text("После какого сообщения:")
        imgui.PushItemWidth(140); imgui.InputText("##sa", bufScreenshotAfter, 16); imgui.PopItemWidth()
        imgui.Spacing()
        imgui.Text("Задержка перед скриншотом (мс):")
        imgui.PushItemWidth(140); imgui.InputText("##sd", bufScreenshotDelay, 16); imgui.PopItemWidth()
        local tc = os.clock(); local ih = 0.65 + 0.08 * math.sin(tc * 0.5)
        local ir,ig,ib = hsvRgb(ih,0.4,0.95)
        imgui.TextColored(imgui.ImVec4(ir,ig,ib,0.9), "Минимальная задержка: 100 мс")
        imgui.Spacing()
        imgui.Text("Папка для скриншотов профиля (например: Собеседования, Инвайты):")
        imgui.PushItemWidth(360); imgui.InputText("##sf", bufScreenshotFolder, ffi.sizeof(bufScreenshotFolder)); imgui.PopItemWidth()
        imgui.TextColored(imgui.ImVec4(0.45,0.7,0.95,0.85), "Скриншоты сохранятся в: screens\\Папка\\День недели - Дата")
    end
    gradSep()

    if accBtn("СОХРАНИТЬ НАСТРОЙКИ", imgui.ImVec2(540, 40), 0) then
        storeCurrentProfile()
        notify("success", "Настройки сохранены!")
    end
end

-- =========================================
-- ГЛАВНОЕ ОКНО
-- =========================================

local function drawMenu()
    if myFont then imgui.PushFont(myFont) end
    imgui.SetNextWindowSize(imgui.ImVec2(600, 780), imgui.Cond.Always)
    imgui.Begin("Leader Helper", showMenu, imgui.WindowFlags.NoResize)

    drawAnimBg()
    drawTabBar()

    if currentTab == 1 then drawEditorTab()
    elseif currentTab == 2 then drawProfilesTab()
    else drawSettingsTab() end

    imgui.End()
    if myFont then imgui.PopFont() end
end

local function drawUpdateWindow()
    if not updateAvailable[0] then return end

    if myFont then imgui.PushFont(myFont) end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(460, 260), imgui.Cond.Always)
    imgui.SetNextWindowPos(
        imgui.ImVec2(sw / 2, sh / 2),
        imgui.Cond.Always,
        imgui.ImVec2(0.5, 0.5)
    )

    local flags =
        imgui.WindowFlags.NoTitleBar +
        imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoCollapse

    imgui.Begin("##UpdateWindow", updateAvailable, flags)

    -- Фон
    local dl = imgui.GetWindowDrawList()
    local wp = imgui.GetWindowPos()
    local ws = imgui.GetWindowSize()
    dl:AddRectFilledMultiColor(
        imgui.ImVec2(wp.x, wp.y),
        imgui.ImVec2(wp.x + ws.x, wp.y + 4),
        rgba(0.25, 0.55, 0.95, 0.95),
        rgba(0.45, 0.75, 1.0, 0.95),
        rgba(0.45, 0.75, 1.0, 0.35),
        rgba(0.25, 0.55, 0.95, 0.35)
    )
    dl:AddRect(
        imgui.ImVec2(wp.x + 1, wp.y + 1),
        imgui.ImVec2(wp.x + ws.x - 1, wp.y + ws.y - 1),
        rgba(0.25, 0.55, 0.95, 0.85), 12.0
    )

    -- Заголовок
    imgui.SetCursorPos(imgui.ImVec2(20, 18))
    imgui.TextColored(imgui.ImVec4(0.55, 0.85, 1.0, 1.0), "ДОСТУПНО ОБНОВЛЕНИЕ")

    -- Версии
    imgui.SetCursorPos(imgui.ImVec2(20, 55))
    imgui.Text("Текущая версия: " .. SCRIPT_VERSION)
    imgui.SetCursorPos(imgui.ImVec2(20, 80))
    imgui.TextColored(
        imgui.ImVec4(0.3, 1.0, 0.5, 1.0),
        "Новая версия: " .. updateRemoteVer
    )

    -- Описание
    imgui.SetCursorPos(imgui.ImVec2(20, 115))
    imgui.TextWrapped("Обновить скрипт сейчас? После обновления нужно написать /mlreload.")

    -- Кнопки
    imgui.SetCursorPos(imgui.ImVec2(20, 200))
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.45, 0.20, 0.90))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.55, 0.28, 0.95))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.08, 0.38, 0.15, 1.0))
    if imgui.Button("ОБНОВИТЬ", imgui.ImVec2(200, 38)) then
        applyUpdate()
    end
    imgui.PopStyleColor(3)

    imgui.SameLine()

    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.30, 0.30, 0.30, 0.75))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.40, 0.40, 0.40, 0.85))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.25, 0.25, 0.25, 1.0))
    if imgui.Button("ПОЗЖЕ", imgui.ImVec2(200, 38)) then
        updateAvailable[0] = false
        if fileExists(TEMP_SCRIPT) then os.remove(TEMP_SCRIPT) end
    end
    imgui.PopStyleColor(3)

    imgui.End()
    if myFont then imgui.PopFont() end
end

-- =========================================
-- РАДИАЛЬНЫЙ ИНТЕРФЕЙС
-- =========================================

local function radialButton(label, x, y, width, height)
    imgui.SetCursorPos(imgui.ImVec2(x, y))
    return imgui.Button(label, imgui.ImVec2(width, height))
end

local function drawRadialMenu()
    local sw, sh = getScreenResolution()

    local isMenu = radialMode == "menu"
    local isCustom = radialMode == "custom"

    -- Увеличенное окно для кольца, чтобы X и кнопки не пересекались
    local windowW = isMenu and 520 or (isCustom and 480 or 390)
    local windowH = isMenu and 520 or (isCustom and 430 or 280)

    imgui.SetNextWindowSize(imgui.ImVec2(windowW, windowH), imgui.Cond.Always)
    imgui.SetNextWindowPos(
        imgui.ImVec2(sw / 2, sh / 2),
        imgui.Cond.Always,
        imgui.ImVec2(0.5, 0.5)
    )

    local flags =
        imgui.WindowFlags.NoTitleBar +
        imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoCollapse

    if isMenu then
        if imgui.WindowFlags.NoBackground then
            flags = flags + imgui.WindowFlags.NoBackground
        end
        if imgui.SetNextWindowBgAlpha then
            imgui.SetNextWindowBgAlpha(0.0)
        end
    end

    imgui.Begin("##LeaderHelperRadial", radialOpen, flags)

    if isMenu then
        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos()

        local cx = wp.x + 260
        local cy = wp.y + 260
        local ringRadius = 185
        local centerRadius = 75

        -- Внешнее кольцо
        dl:AddCircle(imgui.ImVec2(cx, cy), ringRadius, rgba(0.25, 0.55, 0.95, 0.55), 90, 2)

        -- Центральный круг
        dl:AddCircleFilled(imgui.ImVec2(cx, cy), centerRadius, rgba(0.055, 0.085, 0.14, 0.98), 90)
        dl:AddCircle(imgui.ImVec2(cx, cy), centerRadius, rgba(0.25, 0.55, 0.95, 0.9), 90, 2)

        -- Текст в центре
        imgui.SetCursorPos(imgui.ImVec2(215, 240))
        imgui.Text("LEADER")

        imgui.SetCursorPos(imgui.ImVec2(221, 265))
        imgui.Text("ID: " .. tostring(radialPlayerId))

        -- Список стандартных действий
        local actions = {
            { name = "ИНВАЙТ", key = "invite" },
            { name = "РАНГ", key = "rank" },
            { name = "ВЫГОВОР", key = "fwarn" },
            { name = "УВОЛИТЬ", key = "uninvite" },
            { name = "МУТ РАЦИИ", key = "fmute" }
        }

        for i = 1, cfg.customActions.count do
            local custom = getCustomAction(i)
            actions[#actions + 1] = {
                name = custom.name,
                key = "custom",
                index = i
            }
        end

        local count = #actions
        local buttonW = 110
        local buttonH = 42

        for i, action in ipairs(actions) do
            local angle = -math.pi / 2 + ((i - 1) * 2 * math.pi / count)
            local x = 260 + math.cos(angle) * ringRadius - buttonW / 2
            local y = 260 + math.sin(angle) * ringRadius - buttonH / 2

            if radialButton(action.name, x, y, buttonW, buttonH) then
                radialCustomIndex = action.index or 0
                openRadialAction(action.key)
            end
        end

        -- Кнопка "добавить действие" внизу
        if radialButton("+ ДЕЙСТВИЕ", 195, 445, 130, 35) then
            radialMode = "custom"
        end

        -- Кнопка X в правом верхнем углу, далеко от кольца
        if radialButton("X", 470, 10, 40, 30) then
            closeRadial()
        end

    elseif radialMode == "form" then
        imgui.SetCursorPos(imgui.ImVec2(20, 20))
        imgui.Text("ДЕЙСТВИЕ С ИГРОКОМ")

        imgui.SetCursorPos(imgui.ImVec2(20, 48))
        imgui.Text("ID игрока: " .. tostring(radialPlayerId))

        if radialAction == "rank" then
            imgui.SetCursorPos(imgui.ImVec2(20, 85))
            imgui.Text("Введите номер нового ранга:")
            imgui.SetCursorPos(imgui.ImVec2(20, 112))
            imgui.SetNextItemWidth(340)
            imgui.InputText("##radialrank", radialRank, 16)

        elseif radialAction == "fwarn" or radialAction == "uninvite" then
            imgui.SetCursorPos(imgui.ImVec2(20, 85))
            imgui.Text("Укажите причину:")
            imgui.SetCursorPos(imgui.ImVec2(20, 112))
            imgui.SetNextItemWidth(340)
            imgui.InputText("##radialreason", radialReason, 256)

        elseif radialAction == "fmute" then
            imgui.SetCursorPos(imgui.ImVec2(20, 80))
            imgui.Text("Срок мута:")
            imgui.SetCursorPos(imgui.ImVec2(20, 105))
            imgui.SetNextItemWidth(340)
            imgui.InputText("##radialduration", radialDuration, 32)

            imgui.SetCursorPos(imgui.ImVec2(20, 145))
            imgui.Text("Причина:")
            imgui.SetCursorPos(imgui.ImVec2(20, 170))
            imgui.SetNextItemWidth(340)
            imgui.InputText("##radialreason", radialReason, 256)

        elseif radialAction == "custom" then
            imgui.SetCursorPos(imgui.ImVec2(20, 85))
            imgui.Text("Пользовательское действие")
            imgui.SetCursorPos(imgui.ImVec2(20, 112))
            imgui.Text("ID игрока: " .. tostring(radialPlayerId))
        end

        if radialButton("ВЫПОЛНИТЬ", 20, 225, 155, 35) then
            confirmRadialAction()
        end

        if radialButton("НАЗАД", 210, 225, 155, 35) then
            radialMode = "menu"
        end

    elseif isCustom then
        imgui.SetCursorPos(imgui.ImVec2(20, 15))
        imgui.Text("СОЗДАНИЕ СВОЕГО ДЕЙСТВИЯ")

        imgui.SetCursorPos(imgui.ImVec2(20, 48))
        imgui.Text("Название кнопки:")

        imgui.SetCursorPos(imgui.ImVec2(20, 70))
        imgui.SetNextItemWidth(430)
        imgui.InputText("##customname", customName, 128)

        imgui.SetCursorPos(imgui.ImVec2(20, 105))
        imgui.Text("RP-отыгровка (каждая строка отдельно):")

        imgui.SetCursorPos(imgui.ImVec2(20, 130))
        imgui.InputTextMultiline(
            "##customrp",
            customRp,
            ffi.sizeof(customRp),
            imgui.ImVec2(430, 110)
        )

        imgui.SetCursorPos(imgui.ImVec2(20, 250))
        imgui.Text("Игровая команда:")

        imgui.SetCursorPos(imgui.ImVec2(20, 275))
        imgui.SetNextItemWidth(430)
        imgui.InputText("##customcommand", customCommand, 512)

        imgui.SetCursorPos(imgui.ImVec2(20, 315))
        imgui.Text("{id} {reason} {rank} {time}")

        if radialButton("СОХРАНИТЬ", 20, 365, 200, 35) then
            saveCustomRadialAction()
        end

        if radialButton("НАЗАД", 250, 365, 200, 35) then
            radialMode = "menu"
        end
    end

    imgui.End()
end

-- =========================================
-- ОТРИСОВКА РАДИАЛЬНОГО МЕНЮ (ФИКС)
-- =========================================

imgui.OnFrame(
    function()
        return showMenu[0] or radialOpen[0] or updateAvailable[0]
    end,
    function()
        if updateAvailable[0] then
            drawUpdateWindow()
        end
        if radialOpen[0] then
            drawRadialMenu()
        elseif showMenu[0] then
            drawMenu()
        end
    end
)

-- =========================================
-- ОСНОВНОЙ ПОТОК
-- =========================================

function main()
    repeat wait(0) until isSampAvailable()

    lua_thread.create(function()
        wait(2000)
        local updated, ver = checkUpdate()
        if updated then
            sampAddChatMessage(
                u8:decode("{6495ED}[Leader Helper] {FFD700}Доступно обновление " .. tostring(ver)),
                -1
            )
        end
    end)

    sampRegisterChatCommand("ltools", function()
        if radialOpen[0] then
            closeRadial()
        end

        showMenu[0] = not showMenu[0]
    end)

    notify("success", "Скрипт запущен! /ltools — меню")

        sampRegisterChatCommand("lh", function(param)
        local id = tonumber(trim(param or ""))

        if not id or id < 0 or id > 1000 or id ~= math.floor(id) then
            radialNotify("Использование: /lh [ID игрока]")
            return
        end

        if radialBusy then
            radialNotify("Сейчас выполняется другое действие!")
            return
        end

        -- Закрываем основное меню, если оно открыто
        showMenu[0] = false

        radialPlayerId = id
        radialMode = "menu"
        radialOpen[0] = true
    end)

        local lastErrorAt = 0

    while true do
        wait(100)

        if not sequenceRunning then
            local ok, err = pcall(function()
                local count = tonumber(cfg.profiles.count) or 0
                if count < 1 then count = 1; cfg.profiles.count = 1 end
                local now = os.date("*t")
                for i = 1, count do
                    local profile = getProfile(i)
                    if isEnabled(profile.enabled) then
                        local h, m, s = tonumber(profile.hour), tonumber(profile.min), tonumber(profile.sec)
                        if validTime(h, m, s) and now.hour == h and now.min == m and now.sec == s then
                            local cKey = string.format("%d|%s|%02d:%02d:%02d", i, os.date("%Y%m%d"), h, m, s)
                            if lastSentKey ~= cKey then
                                if settingsValid(profile) then
                                    lastSentKey = cKey
                                    selectedProfile = i; activeCfg = profile; loadBuffers()
                                    lua_thread.create(runSequence, profile)
                                    break
                                end
                            end
                        end
                    end
                end
            end)

            if not ok then
                local now = os.clock()
                if now - lastErrorAt > 5 then
                    lastErrorAt = now
                    sampAddChatMessage("[Leader Helper] Ошибка в цикле: "..tostring(err), -1)
                end
            end
        end
    end
end
