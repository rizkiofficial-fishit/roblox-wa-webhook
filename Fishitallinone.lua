--[[
    FISH IT ALL-IN-ONE  =  Player Scanner + PS Monitor (1x execute)

    Isi:
      1. Player Scanner  : GUI + laporan berkala + alert real-time (join/leave, pindah pulau, dll)
      2. PS Monitor      : 1 pesan status server yang di-edit terus (daftar pemain, boost, dll)

    TANPA CONFIG: execute aja, nanti muncul FORM buat isi webhook -> tekan Start.
    (Kalau webhook udah diisi di config di bawah, form dilewati & langsung jalan.
     Mau form tetap muncul: FishItConfig = { SHOW_FORM = true })

    CARA PAKAI (pakai config):
    getgenv().PSMON = {
        webhook  = "https://discord.com/api/webhooks/xxx/yyy",  -- dipakai PS Monitor (& Scanner kalau WEBHOOK_URL kosong)
        name     = "sesi7",
        -- boost    = { mult = 8, dur = "1d 6h 34m" },
        -- reporter = "UsernameAkun",   -- kalau banyak akun 1 sesi
        -- interval = 15,               -- detik, minimal 10
    }
    getgenv().FishItConfig = {          -- OPSIONAL (setting Scanner)
        -- WEBHOOK_URL = "https://discord.com/api/webhooks/aaa/bbb", -- webhook beda khusus Scanner
        -- PSMON_ENABLED = false,       -- matiin PS Monitor, Scanner aja
        -- SCANNER_ENABLED = false,     -- matiin Scanner, PS Monitor aja
        -- START_MINIMIZED = true,
    }
    loadstring(game:HttpGet("https://raw.githubusercontent.com/USERNAME/REPO/main/fishit_all.lua"))()

    Fitur Scanner:
    - Simpan pulau: berdiri di pulau, ketik nama pulau di kolom bawah, tekan "Simpan lokasi".
    - AJARIN ROD: pegang rod, ketik nama rod, tekan "Rod" (disimpan ke FishItRods.json).
    - Tombol "?" = dump debug ke clipboard & console.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

------------------------------------------------------------
-- KONFIGURASI
------------------------------------------------------------
local UPDATE_INTERVAL = 2

local WEBHOOK_URL    = "ISI_URL_DISCORD_WEBHOOK_DI_SINI"
local NOTIFY_INTERVAL = 30 * 60
local SEND_ON_START   = true
local BOT_NAME        = "Fish It Scanner"
local RODS_FILE       = "FishItRods.json"

local ISLANDS = {
    { "kohana",                Vector3.new(-644, 16, 627),     250 },
    { "kohana vulcano",        Vector3.new(-512, 18, 155),     250 },
    { "fisherman island",      Vector3.new(33, 9, 2816),       250 },
    { "coral reefs",           Vector3.new(-2795, 9, 2094),    250 },
    { "esoteric grove",        Vector3.new(2329, -1151, 1408), 250 },
    { "esoteric depths",       Vector3.new(3195, -1303, 1457), 250 },
    { "tropical grove",        Vector3.new(-2040, 6, 3666),    250 },
    { "crater island",         Vector3.new(974, 7, 4892),      250 },
    { "sisyphus statue",       Vector3.new(-3694, -136, -1040),250 },
    { "treasure room",         Vector3.new(-3601, -267, -1558),250 },
    { "planetary observatory", Vector3.new(385, 3, 2147),      250 },
    { "lava basin",            Vector3.new(1022, 85, -10244),  250 },
    { "ancient jungle",        Vector3.new(1313, 7, -178),     250 },
    { "sacred temple",         Vector3.new(1485, 7, -546),     250 },
    { "stingray shores",       Vector3.new(-2132, 5, -586),    250 },
    { "copper canyon",         Vector3.new(-4098, 4, 644),     250 },
    { "copper canyon mines",   Vector3.new(-4167, -555, 534),  250 },
    { "underwater city",       Vector3.new(-3184, -637, -10233),400 },
    { "sewers",                Vector3.new(-1417, -1042, -10412),250 },
    { "ancient ruin",          Vector3.new(6050, -554, 4444),  250 },
    { "pirate cove",           Vector3.new(3330, 4, 3540),     250 },
    { "crystal depths",        Vector3.new(5670, -903, 15418), 250 },
    { "gloomcamp depths",      Vector3.new(5856, -880, 12246), 250 },
    { "elemental island",      Vector3.new(-665, 4, 5155),     250 },
    { "thorne room",           Vector3.new(-1236, -854, 5502), 250 },
}

-- Model rod yang dipakai SEMUA player non-skin (ga bisa bedain rod aslinya dari client).
local GENERIC_RODS = {} -- kosong = semua nama rod tampil apa adanya
local GENERIC_LABEL = "Rod biasa (non-skin)"

local ROD_ATTRIBUTE_NAMES = { "EquippedRod", "Rod", "FishingRod", "CurrentRod" }

local cfg = (getgenv and getgenv().FishItConfig) or {}
local pcfg = (getgenv and getgenv().PSMON) or {}

if cfg.WEBHOOK_URL then WEBHOOK_URL = cfg.WEBHOOK_URL end
-- kalau webhook Scanner ga diisi, pakai webhook dari PSMON (1 webhook buat dua-duanya)
if (WEBHOOK_URL == "" or string.find(WEBHOOK_URL, "ISI_URL")) and type(pcfg.webhook) == "string" then
    WEBHOOK_URL = pcfg.webhook
end
if cfg.NOTIFY_INTERVAL then NOTIFY_INTERVAL = cfg.NOTIFY_INTERVAL end
if cfg.UPDATE_INTERVAL then UPDATE_INTERVAL = cfg.UPDATE_INTERVAL end
if cfg.SEND_ON_START ~= nil then SEND_ON_START = cfg.SEND_ON_START end
if cfg.BOT_NAME then BOT_NAME = cfg.BOT_NAME end
if type(cfg.ISLANDS) == "table" then ISLANDS = cfg.ISLANDS end
if type(cfg.GENERIC_RODS) == "table" then
    GENERIC_RODS = {}
    for _, n in ipairs(cfg.GENERIC_RODS) do GENERIC_RODS[n] = true end
end
if cfg.GENERIC_LABEL then GENERIC_LABEL = cfg.GENERIC_LABEL end

local SCANNER_ENABLED = cfg.SCANNER_ENABLED ~= false
local PSMON_ENABLED   = cfg.PSMON_ENABLED ~= false

-- Alert real-time & fitur tambahan
local ALERT_COOLDOWN     = 10
local EVENT_POLL         = 5
local ALERTS = { join = true, leave = true, island = true, fishing = true, spot = true, idle = true }
local IDLE_MARK_MINUTES  = 5
local IDLE_ALERT_MINUTES = 30
local SPOT_RADIUS        = 40
local SPOT_MIN           = 3
local SPOT_COOLDOWN      = 15 * 60
local SHOW_PET           = true
if cfg.ALERT_COOLDOWN then ALERT_COOLDOWN = cfg.ALERT_COOLDOWN end
if cfg.EVENT_POLL then EVENT_POLL = cfg.EVENT_POLL end
if type(cfg.ALERTS) == "table" then
    for k, v in pairs(cfg.ALERTS) do ALERTS[k] = v end
end
if cfg.IDLE_MARK_MINUTES then IDLE_MARK_MINUTES = cfg.IDLE_MARK_MINUTES end
if cfg.IDLE_ALERT_MINUTES then IDLE_ALERT_MINUTES = cfg.IDLE_ALERT_MINUTES end
if cfg.SPOT_RADIUS then SPOT_RADIUS = cfg.SPOT_RADIUS end
if cfg.SPOT_MIN then SPOT_MIN = cfg.SPOT_MIN end
if cfg.SPOT_COOLDOWN then SPOT_COOLDOWN = cfg.SPOT_COOLDOWN end
if cfg.SHOW_PET ~= nil then SHOW_PET = cfg.SHOW_PET end

-- HTTP request (dipakai Scanner & PS Monitor)
local httpRequest = (syn and syn.request)
    or (http and http.request)
    or http_request
    or request
    or (fluxus and fluxus.request)

------------------------------------------------------------
-- PS MONITOR (jalan duluan, independen dari Scanner)
------------------------------------------------------------
local startPSMon
do
    function startPSMon()
        local StarterGui = game:GetService("StarterGui")

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

        local pwebhook = pcfg.webhook
        if type(pwebhook) ~= "string" or not pwebhook:find("^https://") then
            -- fallback ke webhook Scanner kalau valid
            if type(WEBHOOK_URL) == "string" and WEBHOOK_URL:find("^https://") then
                pwebhook = WEBHOOK_URL
            else
                notify("GAGAL: webhook belum diisi / bukan https")
                return
            end
        end

        if getgenv().PSMON_RUNNING then
            notify("sudah berjalan (rejoin atau set PSMON_RUNNING=false)")
            return
        end

        if not httpRequest then
            notify("GAGAL: executor tidak support request()")
            return
        end

        -- kalau banyak akun di 1 sesi, hanya akun reporter yang kirim
        if pcfg.reporter and LocalPlayer.Name ~= pcfg.reporter then
            print("[PSMON] bukan akun reporter, dilewati")
            return
        end

        getgenv().PSMON_RUNNING = true

        local INTERVAL = math.max(tonumber(pcfg.interval) or 15, 10)
        local WEBHOOK = (pwebhook:gsub("%?.*$", ""):gsub("/+$", ""))
        local NAME = string.upper(tostring(pcfg.name or "SESI"))
        local PS_ID = (game.PrivateServerId ~= "" and game.PrivateServerId) or game.JobId

        -- BOOST
        local function parseDur(s)
            s = string.lower(tostring(s or ""))
            local d = tonumber(s:match("(%d+)%s*d")) or 0
            local h = tonumber(s:match("(%d+)%s*h")) or 0
            local m = tonumber(s:match("(%d+)%s*m")) or 0
            return ((d * 24 + h) * 60 + m) * 60
        end

        local boostEnds, boostMult = nil, 0
        if type(pcfg.boost) == "table" then
            local sec = parseDur(pcfg.boost.dur)
            if sec > 0 then
                boostEnds = os.time() + sec
                boostMult = tonumber(pcfg.boost.mult) or 0
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

        -- ISI PESAN
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

        -- HTTP
        local HEADERS = { ["Content-Type"] = "application/json" }

        local function call(url, method, body)
            local ok, res = pcall(function()
                return httpRequest({ Url = url, Method = method, Headers = HEADERS, Body = body })
            end)
            if not ok then return nil, "request error: " .. tostring(res) end
            if type(res) ~= "table" then return nil, "response kosong" end
            return res
        end

        local function statusOf(res)
            return tonumber(res.StatusCode or res.Status or res.status_code) or 0
        end

        local function decode(body)
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
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

        local myGen = (getgenv().PSMON_GEN or 0) + 1
        getgenv().PSMON_GEN = myGen

        notify("aktif | sesi " .. NAME .. " | mengirim...")

        task.spawn(function()
            while getgenv().PSMON_RUNNING and getgenv().PSMON_GEN == myGen do
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
    end

end

------------------------------------------------------------
-- FORM SETUP (isi webhook lewat UI, lalu Start)
------------------------------------------------------------
local onSetupStart = nil -- diisi Scanner di bawah (kirim laporan pertama)
local SETUP_FILE = "FishItSetup.json"

do
    local genv = (getgenv and getgenv()) or _G

    local function validWebhook(s)
        return type(s) == "string" and s:find("^https://") ~= nil
            and s:find("/api/webhooks/", 1, true) ~= nil
    end

    local function trim(s)
        return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function launchPS()
        if not PSMON_ENABLED then return end
        genv.PSMON_RUNNING = false
        local okPS, errPS = pcall(startPSMon)
        if not okPS then warn("[PSMON] gagal start: " .. tostring(errPS)) end
    end

    local function mk(class, props, par)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        o.Parent = par
        return o
    end

    local function buildForm()
        local saved = {}
        pcall(function()
            if isfile and readfile and isfile(SETUP_FILE) then
                saved = HttpService:JSONDecode(readfile(SETUP_FILE)) or {}
            end
        end)

        local host
        pcall(function() host = (gethui and gethui()) or game:GetService("CoreGui") end)
        if not host then host = LocalPlayer:WaitForChild("PlayerGui") end
        local oldForm = host:FindFirstChild("FishItSetup")
        if oldForm then oldForm:Destroy() end

        local sg = mk("ScreenGui", { Name = "FishItSetup", ResetOnSpawn = false }, host)
        local box = mk("Frame", {
            Size = UDim2.new(0, 320, 0, 252),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.45, 0),
            BackgroundColor3 = Color3.fromRGB(20, 20, 28),
            BackgroundTransparency = 0.05,
            BorderSizePixel = 0,
            Active = true,
            Draggable = true,
        }, sg)
        mk("UICorner", { CornerRadius = UDim.new(0, 10) }, box)

        mk("TextLabel", {
            Size = UDim2.new(1, -50, 0, 26), Position = UDim2.new(0, 12, 0, 6),
            BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 14,
            TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
            Text = "Fish It Monitor - Setup",
        }, box)

        local closeF = mk("TextButton", {
            Size = UDim2.new(0, 24, 0, 24), Position = UDim2.new(1, -32, 0, 7),
            BackgroundColor3 = Color3.fromRGB(180, 50, 50), Text = "X",
            TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 12,
        }, box)
        mk("UICorner", { CornerRadius = UDim.new(0, 6) }, closeF)
        closeF.MouseButton1Click:Connect(function() sg:Destroy() end)

        -- side: nil = full lebar, 0 = kiri, 1 = kanan
        local function field(label, y, placeholder, text, side)
            local pos, size
            if side == nil then
                pos, size = UDim2.new(0, 12, 0, y), UDim2.new(1, -24, 0, 26)
            elseif side == 0 then
                pos, size = UDim2.new(0, 12, 0, y), UDim2.new(0.5, -18, 0, 26)
            else
                pos, size = UDim2.new(0.5, 6, 0, y), UDim2.new(0.5, -18, 0, 26)
            end
            mk("TextLabel", {
                Size = UDim2.new(size.X.Scale, size.X.Offset, 0, 16),
                Position = pos, BackgroundTransparency = 1, Font = Enum.Font.Gotham,
                TextSize = 11, TextColor3 = Color3.fromRGB(170, 175, 190),
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd, Text = label,
            }, box)
            local tb = mk("TextBox", {
                Size = size, Position = UDim2.new(pos.X.Scale, pos.X.Offset, 0, y + 17),
                BackgroundColor3 = Color3.fromRGB(35, 35, 48), TextColor3 = Color3.new(1, 1, 1),
                PlaceholderText = placeholder, PlaceholderColor3 = Color3.fromRGB(120, 120, 135),
                Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false,
                TextXAlignment = Enum.TextXAlignment.Left, Text = text or "",
            }, box)
            mk("UICorner", { CornerRadius = UDim.new(0, 6) }, tb)
            return tb
        end

        local whBox   = field("Webhook Discord (wajib)", 34, "https://discord.com/api/webhooks/...", saved.webhook or pcfg.webhook)
        local nameBox = field("Nama sesi", 84, "sesi7", saved.name or pcfg.name)
        local multBox = field("Boost x (opsional)", 134, "8", nil, 0)
        local durBox  = field("Sisa boost (opsional)", 134, "1d 6h 34m", nil, 1)

        local status = mk("TextLabel", {
            Size = UDim2.new(1, -24, 0, 22), Position = UDim2.new(0, 12, 0, 180),
            BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
            TextColor3 = Color3.fromRGB(170, 175, 190), TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top, Text = "Isi webhook lalu tekan Start",
        }, box)

        local startBtn = mk("TextButton", {
            Size = UDim2.new(1, -24, 0, 32), Position = UDim2.new(0, 12, 0, 208),
            BackgroundColor3 = Color3.fromRGB(50, 140, 80), Text = "Start",
            TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 14,
        }, box)
        mk("UICorner", { CornerRadius = UDim.new(0, 6) }, startBtn)

        local busy = false
        startBtn.MouseButton1Click:Connect(function()
            if busy then return end
            local wh = trim(whBox.Text)
            if not validWebhook(wh) then
                status.Text = "Webhook ga valid (harus https://.../api/webhooks/...)"
                status.TextColor3 = Color3.fromRGB(255, 110, 110)
                return
            end
            busy = true

            local nm = trim(nameBox.Text)
            pcfg.webhook = wh
            pcfg.name = (nm ~= "") and nm or "SESI"
            local mult, dur = tonumber(multBox.Text), trim(durBox.Text)
            if mult and dur ~= "" then pcfg.boost = { mult = mult, dur = dur } else pcfg.boost = nil end
            if not validWebhook(WEBHOOK_URL) then WEBHOOK_URL = wh end

            pcall(function()
                if writefile then
                    writefile(SETUP_FILE, HttpService:JSONEncode({ webhook = wh, name = nm }))
                end
            end)

            launchPS()
            if onSetupStart then task.spawn(onSetupStart) end

            status.Text = "Berjalan, cek channel Discord kamu"
            status.TextColor3 = Color3.fromRGB(120, 230, 150)
            startBtn.Text = "OK"
            task.delay(1.5, function() pcall(function() sg:Destroy() end) end)
        end)
    end

    if (validWebhook(pcfg.webhook) or validWebhook(WEBHOOK_URL)) and not cfg.SHOW_FORM then
        launchPS()
    else
        buildForm()
    end
end

if not SCANNER_ENABLED then return end

------------------------------------------------------------
-- LOGIKA SCANNER
------------------------------------------------------------
local function titleCase(s)
    return (string.gsub(s, "(%a)([%w']*)", function(a, b) return string.upper(a) .. b end))
end

local function getIsland(pos)
    if #ISLANDS == 0 then
        return string.format("(%d, %d, %d)", math.floor(pos.X), math.floor(pos.Y), math.floor(pos.Z))
    end
    local bestName, bestDist = nil, math.huge
    for _, island in ipairs(ISLANDS) do
        local d = (pos - island[2]).Magnitude
        if d <= island[3] and d < bestDist then
            bestName, bestDist = island[1], d
        end
    end
    if bestName then return bestName end

    local nearName, nearDist = "?", math.huge
    for _, island in ipairs(ISLANDS) do
        local d = (pos - island[2]).Magnitude
        if d < nearDist then
            nearName, nearDist = island[1], d
        end
    end
    return string.format("Dekat %s (%d stud)", nearName, math.floor(nearDist))
end

------------------------------------------------------------
-- DETEKSI ROD (lewat MeshId)
------------------------------------------------------------
local templates = nil
local learned = {}
local rodCache = {}

local function meshSet(root)
    local set, n = {}, 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("MeshPart") and d.MeshId ~= "" and not set[d.MeshId] then
            set[d.MeshId] = true
            n = n + 1
        end
    end
    return set, n
end

local function signature(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, "|")
end

local function templateRoot(mp, stopAt)
    local best
    local cur = mp
    while cur and cur ~= stopAt do
        if cur:IsA("Model") or cur:IsA("Tool") then best = cur end
        cur = cur.Parent
    end
    return best or mp.Parent
end

local function buildTemplates()
    local groups, order = {}, {}
    local scanned = 0
    local roots = { ReplicatedStorage }
    pcall(function() table.insert(roots, game:GetService("ReplicatedFirst")) end)
    pcall(function() table.insert(roots, game:GetService("StarterPack")) end)

    for _, root in ipairs(roots) do
        for _, d in ipairs(root:GetDescendants()) do
            scanned = scanned + 1
            if scanned % 1500 == 0 then task.wait() end
            if d:IsA("MeshPart") and d.MeshId ~= "" then
                local r = templateRoot(d, root)
                if r then
                    local g = groups[r]
                    if not g then
                        g = { set = {}, n = 0 }
                        groups[r] = g
                        order[#order + 1] = r
                    end
                    if not g.set[d.MeshId] then
                        g.set[d.MeshId] = true
                        g.n = g.n + 1
                    end
                end
            end
        end
    end

    local out = {}
    for _, r in ipairs(order) do
        local g = groups[r]
        local nm = r.Name
        if #nm > 2 and not tonumber(nm) then
        out[#out + 1] = {
            name = r.Name,
            path = r:GetFullName(),
            set = g.set,
            n = g.n,
            rodish = (string.find(string.lower(r:GetFullName()), "rod") ~= nil),
            fr = (string.find(r:GetFullName(), "Fishing Rods", 1, true) ~= nil),
            bad = (string.find(r:GetFullName(), ".NPC.", 1, true) ~= nil
                or string.find(r:GetFullName(), "Cutscene", 1, true) ~= nil),
        }
        end
    end
    templates = out
end

task.spawn(function() pcall(buildTemplates) end)

-- load rod yang pernah diajarin
pcall(function()
    if isfile and readfile and isfile(RODS_FILE) then
        local data = HttpService:JSONDecode(readfile(RODS_FILE))
        for _, e in ipairs(data) do
            local set, n = {}, 0
            for _, id in ipairs(e.ids) do set[id] = true; n = n + 1 end
            learned[#learned + 1] = { name = e.name, set = set, n = n, ids = e.ids }
        end
    end
end)

local function saveLearned()
    pcall(function()
        if writefile then
            local data = {}
            for _, e in ipairs(learned) do data[#data + 1] = { name = e.name, ids = e.ids } end
            writefile(RODS_FILE, HttpService:JSONEncode(data))
        end
    end)
end

local function scoreOf(set, n, t)
    local common = 0
    for id in pairs(set) do
        if t.set[id] then common = common + 1 end
    end
    if common == 0 then return 0, 0, 0 end
    local coverage = common / n
    local jac = common / (n + t.n - common)
    return coverage, jac, common
end

local function candidates(model, k)
    local set, n = meshSet(model)
    local res = {}
    if n == 0 then return res, n end
    local function consider(list, isLearned)
        for _, t in ipairs(list) do
            local cov, jac, common = scoreOf(set, n, t)
            if cov >= 0.5 then
                local s = jac + (t.rodish and 0.05 or 0) + (t.fr and 0.1 or 0)
                    - (t.bad and 0.3 or 0) + (isLearned and 1 or 0)
                res[#res + 1] = { name = t.name, path = t.path, cov = cov, jac = jac, score = s, common = common }
            end
        end
    end
    consider(learned, true)
    if templates then consider(templates, false) end
    table.sort(res, function(a, b) return a.score > b.score end)
    local top = {}
    for i = 1, math.min(k or 5, #res) do top[i] = res[i] end
    return top, n
end

local function matchRod(model)
    if not model then return nil end
    local set, n = meshSet(model)
    if n == 0 then return nil end

    local sig = signature(set)
    if rodCache[sig] then return rodCache[sig] end

    local top = candidates(model, 1)
    local best = top[1]
    if best and best.cov >= 0.7 and (best.jac >= 0.4 or best.score >= 1) then
        rodCache[sig] = best.name
        return best.name
    end
    return nil
end

local function rodFromEquippedModel(char)
    local m = char and char:FindFirstChild("!!!EQUIPPED_TOOL!!!")
    if not m then return nil end

    if not templates and #learned == 0 then return "memuat..." end

    local matched = matchRod(m)
    if matched then return matched end

    for k, v in pairs(m:GetAttributes()) do
        local key = string.lower(k)
        if type(v) == "string" and v ~= "" and key ~= "owner"
            and (string.find(key, "name") or string.find(key, "rod")
                or string.find(key, "item") or string.find(key, "tool")) then
            return v
        end
    end

    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("StringValue") and d.Value ~= "" then
            return d.Value
        end
    end

    local generic = { handle = true, tool = true, model = true, rod = true, mesh = true }
    for _, c in ipairs(m:GetChildren()) do
        if (c:IsA("Model") or c:IsA("Folder") or c:IsA("Tool") or c:IsA("Accessory"))
            and #c.Name > 2 and not generic[string.lower(c.Name)] then
            return c.Name
        end
    end

    return "tidak dikenal"
end

local function getRod(player)
    local char = player.Character

    local skin = player:GetAttribute("FishingRodSkin")
    if type(skin) == "string" and skin ~= "" then
        return skin .. " (skin)"
    end

    local fromModel = rodFromEquippedModel(char)
    if fromModel then
        if GENERIC_RODS[fromModel] then return GENERIC_LABEL end
        return fromModel
    end

    if char then
        local fallbackTool
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                if string.find(string.lower(child.Name), "rod") then
                    return child.Name
                end
                fallbackTool = fallbackTool or child.Name
            end
        end
        if fallbackTool then return fallbackTool end
    end

    if char then
        for _, d in ipairs(char:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("Accessory") or d:IsA("Folder") or d:IsA("Tool"))
                and string.find(string.lower(d.Name), "rod") then
                return d.Name
            end
        end
    end

    for _, holder in ipairs({ player, char }) do
        if holder then
            for k, v in pairs(holder:GetAttributes()) do
                if string.find(string.lower(k), "rod") and type(v) == "string" and v ~= "" then
                    return v
                end
            end
        end
    end

    for _, attr in ipairs(ROD_ATTRIBUTE_NAMES) do
        local v = player:GetAttribute(attr) or (char and char:GetAttribute(attr))
        if type(v) == "string" and v ~= "" then return v end
    end

    for _, attr in ipairs(ROD_ATTRIBUTE_NAMES) do
        local obj = player:FindFirstChild(attr, true)
        if obj and obj:IsA("ValueBase") and type(obj.Value) ~= "boolean" then
            return tostring(obj.Value)
        end
    end

    return "-"
end

local FISHING_HOLD = 45
local lastFishing = {}
local idleSince = {}

local function isFishing(plr)
    local now = os.clock()
    local sig = plr:GetAttribute("FLAG_Fishing") == true
        or plr:GetAttribute("PetFishingActive") == true
        or plr:GetAttribute("EquippedPetState") == "Fishing"
    if sig then lastFishing[plr] = now end
    local t = lastFishing[plr]
    local f = t ~= nil and (now - t) <= FISHING_HOLD
    if f then
        idleSince[plr] = nil
    elseif not idleSince[plr] then
        idleSince[plr] = now
    end
    return f
end

local function statusMark(r)
    if r.fishing then
        return (r.phase == "Waiting") and "🟡" or "🟢"
    end
    if r.idleMin >= IDLE_MARK_MINUTES then return "💤" end
    return "⚪"
end

local function scan()
    local rows = {}
    local now = os.clock()
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local loc = plr:GetAttribute("LocationName")
        local island
        if type(loc) == "string" and loc ~= "" then
            island = titleCase(loc)
        elseif hrp then
            island = titleCase(getIsland(hrp.Position))
        else
            island = "(belum spawn)"
        end

        local fishing = isFishing(plr)
        local phase = plr:GetAttribute("PetFishingPhase")
        local cast = plr:GetAttribute("PetFishingCastPosition")
        local castPos = nil
        if plr:GetAttribute("PetFishingActive") == true and typeof(cast) == "Vector3" and cast.Magnitude > 1 then
            castPos = cast
        end
        local pet = plr:GetAttribute("EquippedPetModelName")
        local skin = plr:GetAttribute("FishingRodSkin")

        table.insert(rows, {
            plr = plr,
            uid = plr.UserId,
            fishing = fishing,
            phase = (type(phase) == "string") and phase or "None",
            idleMin = (not fishing and idleSince[plr]) and ((now - idleSince[plr]) / 60) or 0,
            castPos = castPos,
            vip = plr:GetAttribute("VIP") == true,
            pet = (type(pet) == "string" and pet ~= "") and pet or nil,
            skin = (type(skin) == "string" and skin ~= "") and skin or nil,
            display = plr.DisplayName,
            username = plr.Name,
            name = plr.DisplayName .. " (@" .. plr.Name .. ")",
            island = island,
            rod = getRod(plr),
        })
    end
    table.sort(rows, function(a, b) return a.island < b.island end)
    return rows
end

------------------------------------------------------------
-- GUI
------------------------------------------------------------
local parent
pcall(function() parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not parent then parent = LocalPlayer:WaitForChild("PlayerGui") end

do
    local g = (getgenv and getgenv()) or _G
    if g.FishItScannerStop then pcall(g.FishItScannerStop) end
end

local old = parent:FindFirstChild("FishItScanner")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "FishItScanner"
gui.ResetOnSpawn = false
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Size = IS_MOBILE and UDim2.new(0, 300, 0, 240) or UDim2.new(0, 380, 0, 350)
frame.Position = UDim2.new(0, 10, 0, 10)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -100, 0, 26)
title.TextTruncate = Enum.TextTruncate.AtEnd
title.Position = UDim2.new(0, 10, 0, 4)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Fish It Scanner"
title.Parent = frame

local close = Instance.new("TextButton")
close.Size = UDim2.new(0, 24, 0, 24)
close.Position = UDim2.new(1, -30, 0, 5)
close.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.GothamBold
close.TextSize = 12
close.Parent = frame
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)

local posLabel = Instance.new("TextLabel")
posLabel.Size = UDim2.new(1, -20, 0, 18)
posLabel.Position = UDim2.new(0, 10, 0, 30)
posLabel.BackgroundTransparency = 1
posLabel.Font = Enum.Font.Code
posLabel.TextSize = 11
posLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
posLabel.TextXAlignment = Enum.TextXAlignment.Left
posLabel.Text = "Posisi kamu: -"
posLabel.Parent = frame

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 1, -92)
list.Position = UDim2.new(0, 10, 0, 52)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.Parent = list

local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -190, 0, 26)
nameBox.Position = UDim2.new(0, 10, 1, -32)
nameBox.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
nameBox.TextColor3 = Color3.new(1, 1, 1)
nameBox.PlaceholderText = "Nama pulau / rod"
nameBox.PlaceholderColor3 = Color3.fromRGB(140, 140, 150)
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 12
nameBox.ClearTextOnFocus = false
nameBox.Parent = frame
Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 6)

local learnBtn = Instance.new("TextButton")
learnBtn.Size = UDim2.new(0, 50, 0, 26)
learnBtn.Position = UDim2.new(1, -170, 1, -32)
learnBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 40)
learnBtn.Text = "Rod"
learnBtn.TextColor3 = Color3.new(1, 1, 1)
learnBtn.Font = Enum.Font.GothamBold
learnBtn.TextSize = 12
learnBtn.Parent = frame
Instance.new("UICorner", learnBtn).CornerRadius = UDim.new(0, 6)

local saveBtn = Instance.new("TextButton")
saveBtn.Size = UDim2.new(0, 105, 0, 26)
saveBtn.Position = UDim2.new(1, -115, 1, -32)
saveBtn.BackgroundColor3 = Color3.fromRGB(50, 140, 80)
saveBtn.Text = "Simpan lokasi"
saveBtn.TextColor3 = Color3.new(1, 1, 1)
saveBtn.Font = Enum.Font.GothamBold
saveBtn.TextSize = 12
saveBtn.Parent = frame
Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 6)

saveBtn.MouseButton1Click:Connect(function()
    local nm = nameBox.Text
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if nm == "" or not hrp then return end

    local p = hrp.Position
    table.insert(ISLANDS, { nm, p, 250 })

    local line = string.format('    { "%s", Vector3.new(%d, %d, %d), 250 },',
        nm, math.floor(p.X), math.floor(p.Y), math.floor(p.Z))
    print("[FishItScanner] " .. line)
    pcall(function() if setclipboard then setclipboard(line) end end)

    nameBox.Text = ""
    saveBtn.Text = "Tersimpan!"
    task.delay(1.5, function() saveBtn.Text = "Simpan lokasi" end)
end)

learnBtn.MouseButton1Click:Connect(function()
    local nm = nameBox.Text
    local char = LocalPlayer.Character
    local m = char and char:FindFirstChild("!!!EQUIPPED_TOOL!!!")
    if nm == "" or not m then
        learnBtn.Text = "Err"
        task.delay(1.5, function() learnBtn.Text = "Rod" end)
        return
    end

    local set, n = meshSet(m)
    if n == 0 then return end
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end

    for i = #learned, 1, -1 do
        if learned[i].name == nm then table.remove(learned, i) end
    end
    learned[#learned + 1] = { name = nm, set = set, n = n, ids = ids }
    rodCache = {}
    saveLearned()

    nameBox.Text = ""
    learnBtn.Text = "OK!"
    task.delay(1.5, function() learnBtn.Text = "Rod" end)
end)

-- Tombol debug "?"
local dbgBtn = Instance.new("TextButton")
dbgBtn.Size = UDim2.new(0, 24, 0, 24)
dbgBtn.Position = UDim2.new(1, -60, 0, 5)
dbgBtn.BackgroundColor3 = Color3.fromRGB(70, 90, 160)
dbgBtn.Text = "?"
dbgBtn.TextColor3 = Color3.new(1, 1, 1)
dbgBtn.Font = Enum.Font.GothamBold
dbgBtn.TextSize = 12
dbgBtn.Parent = frame
Instance.new("UICorner", dbgBtn).CornerRadius = UDim.new(0, 6)

dbgBtn.MouseButton1Click:Connect(function()
    local out = {}
    local function add(s) out[#out + 1] = s end
    local char = LocalPlayer.Character
    local eq = char and char:FindFirstChild("!!!EQUIPPED_TOOL!!!")

    add("===== FISHITSCANNER DEBUG ROD v2 =====")
    add("-- Template model ketemu: " .. tostring(templates and #templates or "belum jadi"))
    add("-- Rod yang diajarin: " .. #learned)

    if eq then
        local set, n = meshSet(eq)
        add("-- Equipped: " .. n .. " mesh unik")
        local i = 0
        for id in pairs(set) do
            i = i + 1
            if i > 12 then add("  ...") break end
            add("  " .. id)
        end
        local top = candidates(eq, 8)
        add("-- Kandidat terbaik (nama | coverage | jaccard | path):")
        if #top == 0 then add("  (TIDAK ADA yang cocok - template rod ga ada di client)") end
        for _, c in ipairs(top) do
            add(string.format("  %s | %.2f | %.2f | %s", c.name, c.cov, c.jac, c.path))
        end
        add("-- Hasil akhir: " .. tostring(matchRod(eq)))
    else
        add("-- Kamu lagi ga pegang rod (!!!EQUIPPED_TOOL!!! ga ada)")
    end

    add("-- Sinyal mancing tiap player (FLAG_*, *Fish*, EquippedPetState, part FISHING):")
    for _, plr in ipairs(Players:GetPlayers()) do
        local bits = {}
        for k, v in pairs(plr:GetAttributes()) do
            local lk = string.lower(k)
            if string.find(lk, "flag") or string.find(lk, "fish") or k == "EquippedPetState" then
                bits[#bits + 1] = k .. "=" .. tostring(v)
            end
        end
        local c = plr.Character
        local extra = ""
        if c then
            if c:FindFirstChild("!!!FISHING_BAIT_MODEL!!!") then extra = extra .. " BAIT" end
            if c:FindFirstChild("!!!FISHING_LANTERN!!!") then extra = extra .. " LANTERN" end
            if c:FindFirstChild("!!!EQUIPPED_TOOL!!!") then extra = extra .. " TOOL" end
        end
        add("  " .. plr.Name .. " | " .. table.concat(bits, ", ") .. " |" .. extra)
    end

    add("-- Rod tiap player (skin attr | hasil | mesh | kandidat teratas):")
    for _, plr in ipairs(Players:GetPlayers()) do
        local m = plr.Character and plr.Character:FindFirstChild("!!!EQUIPPED_TOOL!!!")
        local skin = tostring(plr:GetAttribute("FishingRodSkin"))
        if m then
            local top, n = candidates(m, 2)
            local c1 = top[1]
            add(string.format("  %s | skin=%s | hasil=%s | %d mesh | %s",
                plr.Name, skin, tostring(getRod(plr)), n,
                c1 and string.format("%s cov%.2f jac%.2f", c1.name, c1.cov, c1.jac) or "tanpa kandidat"))
        else
            add("  " .. plr.Name .. " | skin=" .. skin .. " | ga ada EQUIPPED_TOOL")
        end
    end

    add("-- ReplicatedStorage children:")
    for _, c in ipairs(ReplicatedStorage:GetChildren()) do add("  " .. c.ClassName .. " | " .. c.Name) end

    if templates then
        add("-- Sample template yang path-nya mengandung 'rod' (maks 40):")
        local shown = 0
        for _, t in ipairs(templates) do
            if t.rodish then
                shown = shown + 1
                if shown > 40 then add("  ...") break end
                add(string.format("  %s (%d mesh) | %s", t.name, t.n, t.path))
            end
        end
    end
    add("===== END =====")

    local text = table.concat(out, "\n")
    print(text)
    pcall(function() if setclipboard then setclipboard(text) end end)
    dbgBtn.Text = "OK"
    task.delay(1.5, function() dbgBtn.Text = "?" end)
end)

-- Minimize
local fullSize = frame.Size
local minimized = false

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 24, 0, 24)
minBtn.Position = UDim2.new(1, -90, 0, 5)
minBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 105)
minBtn.Text = "-"
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.Parent = frame
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local function setMinimized(state)
    minimized = state
    posLabel.Visible = not state
    list.Visible = not state
    nameBox.Visible = not state
    saveBtn.Visible = not state
    learnBtn.Visible = not state

    if state then
        frame.Size = UDim2.new(0, 230, 0, 34)
        minBtn.Text = "+"
    else
        frame.Size = fullSize
        minBtn.Text = "-"
    end
end

minBtn.MouseButton1Click:Connect(function()
    setMinimized(not minimized)
end)

if cfg.START_MINIMIZED then
    setMinimized(true)
end

local running = true
close.MouseButton1Click:Connect(function()
    running = false
    gui:Destroy()
end)
do
    local g = (getgenv and getgenv()) or _G
    g.FishItScannerStop = function()
        running = false
        pcall(function() gui:Destroy() end)
    end
end

local function render()
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end

    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if myHrp then
        local p = myHrp.Position
        posLabel.Text = string.format("Posisi kamu: Vector3.new(%d, %d, %d)",
            math.floor(p.X), math.floor(p.Y), math.floor(p.Z))
    end

    local rows = scan()
    title.Text = (minimized and "Scanner · " or "Fish It Scanner - ") .. #rows .. " player"

    for _, r in ipairs(rows) do
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -6, 0, 44)
        l.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
        l.BorderSizePixel = 0
        l.Font = Enum.Font.Gotham
        l.TextSize = 12
        l.TextColor3 = Color3.new(1, 1, 1)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Center
        l.Text = "  " .. (statusMark(r) .. " ") .. r.name .. "\n  Pulau: " .. r.island .. "  |  Rod: " .. r.rod
        l.Parent = list
        Instance.new("UICorner", l).CornerRadius = UDim.new(0, 6)
    end
end

task.spawn(function()
    while running do
        pcall(render)
        task.wait(UPDATE_INTERVAL)
    end
end)

------------------------------------------------------------
-- NOTIF WEBHOOK (Scanner)
------------------------------------------------------------
local function webhookReady()
    if not httpRequest then
        warn("[FishItScanner] executor kamu ga support http request")
        return false
    end
    if WEBHOOK_URL == "" or string.find(WEBHOOK_URL, "ISI_URL") then
        warn("[FishItScanner] WEBHOOK_URL belum diisi")
        return false
    end
    return true
end

local function postWebhook(payload)
    if not webhookReady() then return end
    payload.username = BOT_NAME
    local ok, err = pcall(function()
        httpRequest({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload),
        })
    end)
    if not ok then warn("[FishItScanner] gagal kirim webhook: " .. tostring(err)) end
end

local function nameOf(r) return r.display .. (r.vip and " 👑" or "") end
local function rodLabel(r) return (r.rod ~= "-") and r.rod or "–" end

local function phaseText(r)
    if r.fishing then
        if r.phase == "Reeling" then return "🟢 Reeling" end
        if r.phase == "Waiting" then return "🟡 Waiting" end
        return "🟢 mancing"
    end
    if r.idleMin >= IDLE_MARK_MINUTES then
        return string.format("💤 idle %d menit", math.floor(r.idleMin))
    end
    return "⚪ tidak mancing"
end

local function buildReport()
    local rows = scan()

    local groups, order = {}, {}
    for _, r in ipairs(rows) do
        if not groups[r.island] then
            groups[r.island] = {}
            order[#order + 1] = r.island
        end
        table.insert(groups[r.island], r)
    end

    table.sort(order, function(a, b)
        if #groups[a] ~= #groups[b] then return #groups[a] > #groups[b] end
        return a < b
    end)

    local blocks = {}
    local fishingCount, idleCount = 0, 0
    local skinCounts = {}
    for _, island in ipairs(order) do
        local members = groups[island]
        local lines = { string.format("🏝️ **%s** · %d player", island, #members) }
        for _, m in ipairs(members) do
            local line = string.format("> %s %s  ·  🎣 %s", statusMark(m), nameOf(m), rodLabel(m))
            if SHOW_PET and m.pet then line = line .. "  ·  🐾 " .. m.pet end
            if not m.fishing and m.idleMin >= IDLE_MARK_MINUTES then
                line = line .. string.format("  ·  idle %d menit", math.floor(m.idleMin))
                idleCount = idleCount + 1
            end
            lines[#lines + 1] = line
            if m.fishing then fishingCount = fishingCount + 1 end
            if m.skin then skinCounts[m.skin] = (skinCounts[m.skin] or 0) + 1 end
        end
        blocks[#blocks + 1] = table.concat(lines, "\n")
    end

    local summary = {}
    local skinList = {}
    for nm, c in pairs(skinCounts) do skinList[#skinList + 1] = { nm, c } end
    table.sort(skinList, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    if #skinList > 0 then
        local parts = {}
        for _, s in ipairs(skinList) do parts[#parts + 1] = s[1] .. " ×" .. s[2] end
        summary[#summary + 1] = "📊 Skin: " .. table.concat(parts, " · ")
    end
    if order[1] then
        summary[#summary + 1] = string.format("📈 Pulau terpadat: %s (%d)", order[1], #groups[order[1]])
    end
    local summaryText = table.concat(summary, "\n")

    local text = table.concat(blocks, "\n\n")
    local limit = 3800 - #summaryText
    if #text > limit then text = string.sub(text, 1, limit) .. "\n..." end
    if summaryText ~= "" then text = text .. "\n\n" .. summaryText end
    return #rows, #order, text, fishingCount, idleCount
end

local function sendWebhook()
    if not webhookReady() then return end

    local count, islandCount, text, fishingCount, idleCount = buildReport()
    local head = string.format("👥 **%d** player  ·  🎣 **%d** mancing", count, fishingCount)
    if idleCount > 0 then head = head .. string.format("  ·  💤 **%d** idle", idleCount) end
    head = head .. string.format("  ·  🏝️ **%d** lokasi", islandCount)

    postWebhook({
        content = "📍 **Update posisi pemancing** (" .. count .. " player di server)",
        embeds = {{
            title = "🎣 Fish It — Peta Pemancing",
            description = head .. "\n🟢 Reeling   🟡 Waiting   ⚪ tidak   💤 idle\n\n" .. text,
            color = 3447003,
            footer = { text = "Server " .. string.sub(game.JobId, 1, 8)
                .. "  •  update tiap " .. math.floor(NOTIFY_INTERVAL / 60) .. " menit" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }},
    })
end

task.spawn(function()
    if SEND_ON_START then
        task.wait(5)
        local waited = 0
        while not templates and waited < 90 and running do
            task.wait(1)
            waited = waited + 1
        end
        task.wait(1)
        if running then sendWebhook() end
    end
    while running do
        task.wait(NOTIFY_INTERVAL)
        if running then sendWebhook() end
    end
end)

------------------------------------------------------------
-- ALERT REAL-TIME
------------------------------------------------------------
local ALERT_COLORS = {
    join = 3066993, leave = 15158332, island = 3447003,
    fishing = 10181046, spot = 15105570, idle = 9807270,
}
local alertQueue = {}

local function pushAlert(kind, title, lines)
    if not ALERTS[kind] then return end
    if #alertQueue >= 50 then table.remove(alertQueue, 1) end
    alertQueue[#alertQueue + 1] = { kind = kind, title = title, lines = lines }
end

task.spawn(function()
    while running do
        task.wait(ALERT_COOLDOWN)
        if running and #alertQueue > 0 then
            local batch = {}
            for _ = 1, math.min(#alertQueue, 8) do
                batch[#batch + 1] = table.remove(alertQueue, 1)
            end
            local title, desc
            if #batch == 1 then
                title, desc = batch[1].title, batch[1].lines
            else
                local parts = {}
                for _, e in ipairs(batch) do
                    parts[#parts + 1] = "**" .. e.title .. "**\n" .. e.lines
                end
                title = "🔔 Update server (" .. #batch .. ")"
                desc = table.concat(parts, "\n\n")
            end
            postWebhook({
                embeds = {{
                    title = title,
                    description = desc,
                    color = ALERT_COLORS[batch[1].kind] or 3447003,
                    footer = { text = "Server " .. string.sub(game.JobId, 1, 8) },
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                }},
            })
        end
    end
end)

local function validIsland(isl)
    return type(isl) == "string" and not string.find(isl, "^Dekat") and not string.find(isl, "^%(")
end

local function detailLine(r)
    return "🎣 " .. rodLabel(r) .. " · " .. phaseText(r)
end

local prev = {}
local pendingIsland = {}
local idleAlerted = {}
local spotAlerted = {}
local baseline = false

local function monitorTick()
    local rows = scan()
    local now = os.clock()

    for _, r in ipairs(rows) do
        local snap = prev[r.uid]
        if not snap then
            snap = { island = r.island, fishing = r.fishing }
            prev[r.uid] = snap
        end
        snap.display, snap.rod = r.display, rodLabel(r)

        if baseline then
            if validIsland(r.island) and validIsland(snap.island) and r.island ~= snap.island then
                if pendingIsland[r.uid] == r.island then
                    pendingIsland[r.uid] = nil
                    local oldIsl = snap.island
                    snap.island = r.island
                    pushAlert("island", "🏝️ PINDAH PULAU",
                        string.format("%s: %s → %s\n%s", nameOf(r), oldIsl, r.island, detailLine(r)))
                else
                    pendingIsland[r.uid] = r.island
                end
            else
                pendingIsland[r.uid] = nil
                if validIsland(r.island) and not validIsland(snap.island) then snap.island = r.island end
            end

            if r.fishing ~= snap.fishing then
                if r.fishing then
                    pushAlert("fishing", "🎣 MULAI MANCING",
                        string.format("%s di %s\n%s", nameOf(r), r.island, detailLine(r)))
                else
                    pushAlert("fishing", "🛑 BERHENTI MANCING",
                        string.format("%s di %s", nameOf(r), r.island))
                end
            end

            if r.fishing then
                idleAlerted[r.uid] = nil
            elseif r.idleMin >= IDLE_ALERT_MINUTES and not idleAlerted[r.uid] then
                idleAlerted[r.uid] = true
                pushAlert("idle", "💤 IDLE LAMA",
                    string.format("%s · %s · 🎣 %s\nudah %d menit ga mancing",
                        nameOf(r), r.island, rodLabel(r), math.floor(r.idleMin)))
            end
        else
            if validIsland(r.island) then snap.island = r.island end
        end
        snap.fishing = r.fishing
    end

    if baseline then
        local used = {}
        local fishers = {}
        for _, r in ipairs(rows) do
            if r.fishing and r.castPos then fishers[#fishers + 1] = r end
        end
        for i, a in ipairs(fishers) do
            if not used[i] then
                local cluster = { a }
                used[i] = true
                for j, b in ipairs(fishers) do
                    if not used[j] and (a.castPos - b.castPos).Magnitude <= SPOT_RADIUS then
                        used[j] = true
                        cluster[#cluster + 1] = b
                    end
                end
                if #cluster >= SPOT_MIN then
                    local key = math.floor(a.castPos.X / SPOT_RADIUS) .. ":" .. math.floor(a.castPos.Z / SPOT_RADIUS)
                    if now - (spotAlerted[key] or -math.huge) > SPOT_COOLDOWN then
                        spotAlerted[key] = now
                        local names = {}
                        for _, c in ipairs(cluster) do names[#names + 1] = c.display end
                        pushAlert("spot", "🔥 SPOT RAME",
                            string.format("%d player nembak spot yang sama di %s\n%s",
                                #cluster, a.island, table.concat(names, " · ")))
                    end
                end
            end
        end
    end

    baseline = true
end

task.spawn(function()
    while running do
        pcall(monitorTick)
        task.wait(EVENT_POLL)
    end
end)

Players.PlayerAdded:Connect(function(plr)
    task.delay(6, function()
        if not running or not plr.Parent then return end
        local row
        for _, r in ipairs(scan()) do
            if r.plr == plr then row = r break end
        end
        if not row then return end
        pushAlert("join", "➕ JOIN",
            string.format("%s · 🎣 %s\n📍 %s\n👥 sekarang %d player",
                nameOf(row), rodLabel(row), row.island, #Players:GetPlayers()))
    end)
end)

Players.PlayerRemoving:Connect(function(plr)
    local snap = prev[plr.UserId]
    local isl = (snap and validIsland(snap.island)) and snap.island or "?"
    local remaining = math.max(#Players:GetPlayers() - 1, 0)
    pushAlert("leave", "➖ LEAVE",
        string.format("%s · terakhir di %s\n👥 sekarang %d player", plr.DisplayName, isl, remaining))
    prev[plr.UserId] = nil
    idleAlerted[plr.UserId] = nil
    pendingIsland[plr.UserId] = nil
    lastFishing[plr] = nil
    idleSince[plr] = nil
end)

-- dipanggil form setelah tombol Start: kirim laporan pertama Scanner
onSetupStart = function()
    local waited = 0
    while not templates and waited < 60 and running do
        task.wait(1)
        waited = waited + 1
    end
    if running then sendWebhook() end
end
