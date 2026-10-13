-- ============================================================
-- PS MONITOR v2 (webhook langsung)
--
-- getgenv().PSMON = {
--     webhook  = "https://discord.com/api/webhooks/xxx/yyy",
--     name     = "sesi7",
--     -- opsional:
--     -- boost    = { mult = 8, dur = "1d 6h 34m" },  -- sisa waktu di game
--     -- reporter = "UsernameAkun",                   -- kalau banyak akun 1 sesi
--     -- interval = 15,                               -- detik, minimal 10
-- }
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/USERNAME/REPO/main/psmon.lua"))()
--
-- Tanda script jalan:
--   1. Notifikasi "PS Monitor aktif" muncul di layar game
--   2. Console: [PSMON] ... (status tiap kirim)
-- ============================================================

local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local function notify(text)
    print("[PSMON] " .. text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "PS Monitor",
            Text = text,
            Duration = 6,
        })
    end)
end

local cfg = (getgenv and getgenv().PSMON) or {}

if type(cfg.webhook) ~= "string" or not cfg.webhook:find("^https://") then
    notify("GAGAL: webhook belum diisi / bukan https")
    return
end

if getgenv().PSMON_RUNNING then
    notify("sudah berjalan (rejoin atau set PSMON_RUNNING=false)")
    return
end

local httpRequest = (syn and syn.request)
    or (http and http.request)
    or http_request
    or request
    or (fluxus and fluxus.request)

if not httpRequest then
    notify("GAGAL: executor tidak support request()")
    return
end

-- kalau banyak akun di 1 sesi, hanya akun reporter yang kirim
if cfg.reporter and LP.Name ~= cfg.reporter then
    print("[PSMON] bukan akun reporter, dilewati")
    return
end

getgenv().PSMON_RUNNING = true

local INTERVAL = math.max(tonumber(cfg.interval) or 15, 10)
local WEBHOOK = (cfg.webhook:gsub("%?.*$", ""):gsub("/+$", ""))
local NAME = string.upper(tostring(cfg.name or "SESI"))
local PS_ID = (game.PrivateServerId ~= "" and game.PrivateServerId) or game.JobId

-- ============================================================
-- BOOST (hitung mundur dari sisa waktu yang diisi)
-- ============================================================

local function parseDur(s)
    s = string.lower(tostring(s or ""))
    local d = tonumber(s:match("(%d+)%s*d")) or 0
    local h = tonumber(s:match("(%d+)%s*h")) or 0
    local m = tonumber(s:match("(%d+)%s*m")) or 0
    return ((d * 24 + h) * 60 + m) * 60
end

local boostEnds, boostMult = nil, 0

if type(cfg.boost) == "table" then
    local sec = parseDur(cfg.boost.dur)
    if sec > 0 then
        boostEnds = os.time() + sec
        boostMult = tonumber(cfg.boost.mult) or 0
    end
end

local function fmt(sec)
    local m = math.floor(sec / 60)
    local d = math.floor(m / 1440)
    local h = math.floor((m % 1440) / 60)
    local mm = m % 60

    local out = {}
    if d > 0 then table.insert(out, d .. "d") end
    if d > 0 or h > 0 then table.insert(out, h .. "h") end
    table.insert(out, mm .. "m")

    return table.concat(out, " ")
end

-- ============================================================
-- ISI PESAN
-- ============================================================

local function build()
    local players = Players:GetPlayers()
    local list = {}

    for i, p in ipairs(players) do
        table.insert(list, "┃ " .. i .. ". " .. p.Name)
    end

    local lines = {
        "╭━━〔 🤖 PS MONITOR 〕━━⬣",
        "┃ 🏷️ Server : " .. NAME,
        "┃ 🟢 Status : ONLINE",
        "┃ 👥 Player : " .. #players .. " / " .. Players.MaxPlayers,
        "┃ 🎮 Game   : Fish It",
        "┃ 🆔 PS ID  : " .. tostring(PS_ID),
    }

    if boostEnds and boostEnds > os.time() then
        table.insert(lines, "┃ 🍀 Boost  : x" .. boostMult .. " | " .. fmt(boostEnds - os.time()))
    end

    table.insert(lines, "┃ 🔄 Update : " .. os.date("%H:%M:%S"))
    table.insert(lines, "┃")
    table.insert(lines, "┃ 👤 Pemain:")
    table.insert(lines, #list > 0 and table.concat(list, "\n") or "┃ -")
    table.insert(lines, "╰━━━━━━━━━━━━━━━━━━━━━━⬣")

    return "```\n" .. table.concat(lines, "\n") .. "\n```"
end

-- ============================================================
-- HTTP
-- ============================================================

local HEADERS = { ["Content-Type"] = "application/json" }

local function call(url, method, body)
    local ok, res = pcall(function()
        return httpRequest({
            Url = url,
            Method = method,
            Headers = HEADERS,
            Body = body,
        })
    end)

    if not ok then
        return nil, "request error: " .. tostring(res)
    end

    if type(res) ~= "table" then
        return nil, "response kosong"
    end

    return res
end

local function statusOf(res)
    return tonumber(res.StatusCode or res.Status or res.status_code) or 0
end

local function decode(body)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    return ok and data or nil
end

local msgId = nil
local editFails = 0
local noEdit = false
local lastState = nil

local function setState(state, text)
    if lastState ~= state then
        lastState = state
        notify(text)
    end
end

-- return false kalau script harus berhenti
local function send()
    local body = HttpService:JSONEncode({ content = build() })

    -- 1) edit pesan yang sudah ada
    if msgId and not noEdit then
        local res, err = call(WEBHOOK .. "/messages/" .. msgId, "PATCH", body)

        if res then
            local st = statusOf(res)

            if st == 200 or st == 204 then
                editFails = 0
                setState("ok", "terkirim ke Discord (edit tiap " .. INTERVAL .. "s)")
                return true
            end

            if st == 429 then
                local d = decode(res.Body or "")
                task.wait((d and tonumber(d.retry_after) or 2) + 0.5)
                return true
            end

            print("[PSMON] edit gagal, status " .. st)
        else
            print("[PSMON] edit error: " .. tostring(err))
        end

        editFails = editFails + 1
        msgId = nil

        if editFails >= 3 then
            noEdit = true
            INTERVAL = math.max(INTERVAL, 60)
            print("[PSMON] edit tidak didukung, mode kirim baru tiap " .. INTERVAL .. "s")
        end
    end

    -- 2) kirim pesan baru
    local res, err = call(WEBHOOK .. "?wait=true", "POST", body)

    if not res then
        setState("fail", "GAGAL kirim: " .. tostring(err))
        return true
    end

    local st = statusOf(res)

    if st == 200 or st == 204 then
        local d = decode(res.Body or "")
        if d and d.id then
            msgId = d.id
        elseif not noEdit then
            noEdit = true
            INTERVAL = math.max(INTERVAL, 60)
            print("[PSMON] id pesan tidak terbaca, mode kirim baru tiap " .. INTERVAL .. "s")
        end
        setState("ok", "terkirim ke Discord")
        return true
    end

    if st == 429 then
        local d = decode(res.Body or "")
        task.wait((d and tonumber(d.retry_after) or 2) + 0.5)
        return true
    end

    if st == 401 or st == 404 then
        notify("GAGAL: webhook tidak valid / dihapus (" .. st .. ")")
        return false
    end

    setState("fail", "GAGAL kirim, status " .. st)
    print("[PSMON] body: " .. tostring(res.Body))
    return true
end

notify("aktif | sesi " .. NAME .. " | mengirim...")

task.spawn(function()
    while getgenv().PSMON_RUNNING do
        local ok, alive = pcall(send)

        if not ok then
            warn("[PSMON] error internal: " .. tostring(alive))
        elseif alive == false then
            getgenv().PSMON_RUNNING = false
            break
        end

        task.wait(INTERVAL)
    end
end)
