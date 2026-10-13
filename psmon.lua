-- ============================================================
-- PS MONITOR (webhook langsung)
-- Dijalankan buyer lewat:
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
-- ============================================================

local cfg = getgenv().PSMON or {}

if type(cfg.webhook) ~= "string" or not cfg.webhook:find("^https://") then
    warn("[PSMON] webhook belum diisi / tidak valid")
    return
end

if getgenv().PSMON_RUNNING then
    warn("[PSMON] sudah berjalan")
    return
end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local req = (syn and syn.request) or (http and http.request) or http_request or request
if not req then
    warn("[PSMON] executor tidak support request()")
    return
end

-- kalau banyak akun di 1 sesi, hanya akun reporter yang kirim
if cfg.reporter and LP.Name ~= cfg.reporter then
    return
end

getgenv().PSMON_RUNNING = true

local INTERVAL = math.max(tonumber(cfg.interval) or 15, 10)
local WEBHOOK = cfg.webhook:gsub("%?.*$", ""):gsub("/+$", "")
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

local boostEnds = nil
local boostMult = 0

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
-- KIRIM / EDIT KE WEBHOOK
-- ============================================================

local msgId = nil
local HEADERS = { ["Content-Type"] = "application/json" }

local function decode(body)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    return ok and data or nil
end

-- return true kalau berhasil, false kalau webhook tidak valid lagi
local function send()
    local body = HttpService:JSONEncode({ content = build() })

    -- edit pesan yang sudah ada
    if msgId then
        local r = req({
            Url = WEBHOOK .. "/messages/" .. msgId,
            Method = "PATCH",
            Headers = HEADERS,
            Body = body,
        })

        if r and r.StatusCode == 200 then
            return true
        end

        if r and r.StatusCode == 429 then
            local d = decode(r.Body)
            task.wait((d and tonumber(d.retry_after) or 2) + 0.5)
            return true
        end

        -- pesan hilang / tidak bisa diedit -> kirim baru
        msgId = nil
    end

    -- kirim pesan baru
    local r = req({
        Url = WEBHOOK .. "?wait=true",
        Method = "POST",
        Headers = HEADERS,
        Body = body,
    })

    if not r then
        return true
    end

    if r.StatusCode == 200 then
        local d = decode(r.Body)
        if d and d.id then
            msgId = d.id
        end
        return true
    end

    if r.StatusCode == 429 then
        local d = decode(r.Body)
        task.wait((d and tonumber(d.retry_after) or 2) + 0.5)
        return true
    end

    if r.StatusCode == 401 or r.StatusCode == 404 then
        warn("[PSMON] webhook tidak valid / sudah dihapus (" .. r.StatusCode .. ")")
        return false
    end

    return true
end

task.spawn(function()
    while getgenv().PSMON_RUNNING do
        local ok, alive = pcall(send)

        if ok and alive == false then
            getgenv().PSMON_RUNNING = false
            break
        end

        task.wait(INTERVAL)
    end
end)

print("[PSMON] aktif | sesi: " .. NAME .. " | interval: " .. INTERVAL .. "s")
print("[PSMON] aktif | sesi: " .. NAME .. " | interval: " .. INTERVAL .. "s")
print("[PSMON] aktif | sesi: " .. NAME .. " | interval: " .. INTERVAL .. "s")