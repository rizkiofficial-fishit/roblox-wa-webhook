--[[
    Fish It - Player Scanner (read-only)
    Nampilin semua player di server: lagi di pulau mana + pake rod apa.
    Cuma baca data yang udah ke-replicate ke client, ga ngubah apa-apa di game.

    CARA PAKAI:
    1. Isi WEBHOOK_URL di bawah (wajib kalau mau notif ke WA).
    2. Jalankan script, lalu keliling ke tiap pulau. Berdiri di pulau itu,
       ketik nama pulaunya di kolom bawah panel, tekan "Simpan lokasi".
       Pulau langsung terdaftar, ga perlu edit file.
       (Baris Lua-nya juga di-copy ke clipboard kalau executor support, biar
       bisa ditempel ke tabel ISLANDS supaya permanen.)
    Panel muncul di kiri atas, update tiap UPDATE_INTERVAL detik.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

------------------------------------------------------------
-- KONFIGURASI
------------------------------------------------------------
local UPDATE_INTERVAL = 2

-- Notif ke WA (lewat Discord webhook -> discordToWa)
local WEBHOOK_URL    = "https://discord.com/api/webhooks/1549381299142262825/skfFFSZY-TeYvlf-xfWYJ9PgUY4f7ENWGtq4CEcmgM673HRuwvnii8f8x8oaVPwXkUOx"
local NOTIFY_INTERVAL = 30 * 60   -- 30 menit (dalam detik)
local SEND_ON_START   = true      -- kirim 1x langsung pas script jalan
local BOT_NAME        = "Fish It Scanner"

-- {nama pulau, titik tengah, radius}
-- GANTI sesuai koordinat asli di game
-- Kosongin aja, pulau bisa ditambah langsung dari panel (tombol "Simpan lokasi")
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

-- Tempat lain yang mungkin nyimpen nama rod (dicek berurutan)
local ROD_ATTRIBUTE_NAMES = { "EquippedRod", "Rod", "FishingRod", "CurrentRod" }

-- Override config dari luar (dipakai kalau script dijalankan via loadstring).
-- Jadi URL webhook & daftar pulau cukup ditulis di executor, ga perlu masuk file GitHub.
local cfg = (getgenv and getgenv().FishItConfig) or {}
if cfg.WEBHOOK_URL then WEBHOOK_URL = cfg.WEBHOOK_URL end
if cfg.NOTIFY_INTERVAL then NOTIFY_INTERVAL = cfg.NOTIFY_INTERVAL end
if cfg.UPDATE_INTERVAL then UPDATE_INTERVAL = cfg.UPDATE_INTERVAL end
if cfg.SEND_ON_START ~= nil then SEND_ON_START = cfg.SEND_ON_START end
if cfg.BOT_NAME then BOT_NAME = cfg.BOT_NAME end
if type(cfg.ISLANDS) == "table" then ISLANDS = cfg.ISLANDS end

------------------------------------------------------------
-- LOGIKA
------------------------------------------------------------
-- "kohana vulcano" -> "Kohana Vulcano"
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

    -- kalau di luar semua radius, tampilin pulau terdekat
    local nearName, nearDist = "?", math.huge
    for _, island in ipairs(ISLANDS) do
        local d = (pos - island[2]).Magnitude
        if d < nearDist then
            nearName, nearDist = island[1], d
        end
    end
    return string.format("Dekat %s (%d stud)", nearName, math.floor(nearDist))
end

local function getRod(player)
    local char = player.Character

    -- 1) Tool yang lagi dipegang (paling umum)
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

    -- 1b) Model/aksesori rod yang nempel di character (nama mengandung "rod")
    if char then
        for _, d in ipairs(char:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("Accessory") or d:IsA("Folder") or d:IsA("Tool"))
                and string.find(string.lower(d.Name), "rod") then
                return d.Name
            end
        end
    end

    -- 1c) Attribute apa pun yang namanya mengandung "rod"
    for _, holder in ipairs({ player, char }) do
        if holder then
            for k, v in pairs(holder:GetAttributes()) do
                if string.find(string.lower(k), "rod") and type(v) == "string" and v ~= "" then
                    return v
                end
            end
        end
    end

    -- 2) Attribute di player / character
    for _, attr in ipairs(ROD_ATTRIBUTE_NAMES) do
        local v = player:GetAttribute(attr) or (char and char:GetAttribute(attr))
        if type(v) == "string" and v ~= "" then return v end
    end

    -- 3) Value object di dalam player (mis. Data/Equipped)
    for _, attr in ipairs(ROD_ATTRIBUTE_NAMES) do
        local obj = player:FindFirstChild(attr, true)
        if obj and obj:IsA("ValueBase") and type(obj.Value) ~= "boolean" then
            return tostring(obj.Value)
        end
    end

    return "-"
end

local function scan()
    local rows = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local island = hrp and titleCase(getIsland(hrp.Position)) or "(belum spawn)"
        table.insert(rows, {
            display = plr.DisplayName,
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

-- Input nama pulau + tombol simpan lokasi
local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -125, 0, 26)
nameBox.Position = UDim2.new(0, 10, 1, -32)
nameBox.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
nameBox.TextColor3 = Color3.new(1, 1, 1)
nameBox.PlaceholderText = "Nama pulau tempat kamu berdiri"
nameBox.PlaceholderColor3 = Color3.fromRGB(140, 140, 150)
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 12
nameBox.ClearTextOnFocus = false
nameBox.Parent = frame
Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 6)

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

-- Tombol debug "?" : dump info buat nyari tempat game nyimpen data rod
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
    local plr = LocalPlayer
    local char = plr.Character

    add("===== FISHITSCANNER DEBUG ROD =====")
    add("-- Player children:")
    for _, c in ipairs(plr:GetChildren()) do add("  " .. c.ClassName .. " | " .. c.Name) end
    add("-- Player attributes:")
    for k, v in pairs(plr:GetAttributes()) do add("  " .. tostring(k) .. " = " .. tostring(v)) end

    if char then
        add("-- Character children:")
        for _, c in ipairs(char:GetChildren()) do add("  " .. c.ClassName .. " | " .. c.Name) end
        add("-- Character attributes:")
        for k, v in pairs(char:GetAttributes()) do add("  " .. tostring(k) .. " = " .. tostring(v)) end
        add("-- Descendants character yang namanya mengandung 'rod':")
        for _, d in ipairs(char:GetDescendants()) do
            if string.find(string.lower(d.Name), "rod") then
                add("  " .. d.ClassName .. " | " .. d:GetFullName())
            end
        end
    end

    local bp = plr:FindFirstChildOfClass("Backpack")
    if bp then
        add("-- Backpack:")
        for _, c in ipairs(bp:GetChildren()) do add("  " .. c.ClassName .. " | " .. c.Name) end
    end
    add("===== END =====")

    local text = table.concat(out, "\n")
    print(text)
    pcall(function() if setclipboard then setclipboard(text) end end)
    dbgBtn.Text = "OK"
    task.delay(1.5, function() dbgBtn.Text = "?" end)
end)

-- Tombol minimize "-" : ciutin panel jadi bar kecil (script tetap jalan & notif tetap kekirim)
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

-- Mulai dalam keadaan ke-minimize kalau diatur dari config
if cfg.START_MINIMIZED then
    setMinimized(true)
end

local running = true
close.MouseButton1Click:Connect(function()
    running = false
    gui:Destroy()
end)

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
        l.Text = "  " .. r.name .. "\n  Pulau: " .. r.island .. "  |  Rod: " .. r.rod
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
-- NOTIF WEBHOOK (tiap NOTIFY_INTERVAL detik)
------------------------------------------------------------
local HttpService = game:GetService("HttpService")

local httpRequest = (syn and syn.request)
    or (http and http.request)
    or http_request
    or request
    or (fluxus and fluxus.request)

local function buildReport()
    local rows = scan()

    -- kelompokkan player per pulau
    local groups, order = {}, {}
    for _, r in ipairs(rows) do
        if not groups[r.island] then
            groups[r.island] = {}
            order[#order + 1] = r.island
        end
        table.insert(groups[r.island], r)
    end

    -- pulau paling rame di atas
    table.sort(order, function(a, b)
        if #groups[a] ~= #groups[b] then return #groups[a] > #groups[b] end
        return a < b
    end)

    local blocks = {}
    for _, island in ipairs(order) do
        local members = groups[island]
        local lines = { string.format("🏝️ **%s** · %d player", island, #members) }
        for _, m in ipairs(members) do
            local rod = (m.rod ~= "-") and m.rod or "–"
            lines[#lines + 1] = string.format("> 👤 %s  ·  🎣 %s", m.display, rod)
        end
        blocks[#blocks + 1] = table.concat(lines, "\n")
    end

    local text = table.concat(blocks, "\n\n")
    if #text > 3800 then text = string.sub(text, 1, 3800) .. "\n..." end
    return #rows, #order, text
end

local function sendWebhook()
    if not httpRequest then
        warn("[FishItScanner] executor kamu ga support http request")
        return
    end
    if WEBHOOK_URL == "" or string.find(WEBHOOK_URL, "ISI_URL") then
        warn("[FishItScanner] WEBHOOK_URL belum diisi")
        return
    end

    local count, islandCount, text = buildReport()
    local payload = {
        username = BOT_NAME,
        content = "📍 **Update posisi pemancing** (" .. count .. " player di server)",
        embeds = {{
            title = "🎣 Fish It — Peta Pemancing",
            description = string.format("👥 **%d** player  ·  🏝️ **%d** lokasi aktif\n\n%s",
                count, islandCount, text),
            color = 3447003,
            footer = { text = "Server " .. string.sub(game.JobId, 1, 8)
                .. "  •  update tiap " .. math.floor(NOTIFY_INTERVAL / 60) .. " menit" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }},
    }

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

task.spawn(function()
    if SEND_ON_START then
        task.wait(5)
        if running then sendWebhook() end
    end
    while running do
        task.wait(NOTIFY_INTERVAL)
        if running then sendWebhook() end
    end
end)
