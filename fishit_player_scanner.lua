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

------------------------------------------------------------
-- KONFIGURASI
------------------------------------------------------------
local UPDATE_INTERVAL = 2

-- Notif ke WA (lewat Discord webhook -> discordToWa)
local WEBHOOK_URL    = "ISI_URL_DISCORD_WEBHOOK_DI_SINI"
local NOTIFY_INTERVAL = 30 * 60   -- 30 menit (dalam detik)
local SEND_ON_START   = true      -- kirim 1x langsung pas script jalan
local BOT_NAME        = "Fish It Scanner"

-- {nama pulau, titik tengah, radius}
-- GANTI sesuai koordinat asli di game
-- Kosongin aja, pulau bisa ditambah langsung dari panel (tombol "Simpan lokasi")
local ISLANDS = {
    -- { "Kohana", Vector3.new(120, 15, -340), 150 },
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

    -- 2) Attribute di player / character
    for _, attr in ipairs(ROD_ATTRIBUTE_NAMES) do
        local v = player:GetAttribute(attr) or (char and char:GetAttribute(attr))
        if v then return tostring(v) end
    end

    -- 3) Value object di dalam player (mis. Data/Equipped)
    for _, attr in ipairs(ROD_ATTRIBUTE_NAMES) do
        local obj = player:FindFirstChild(attr, true)
        if obj and obj:IsA("ValueBase") then
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
        local island = hrp and getIsland(hrp.Position) or "(belum spawn)"
        table.insert(rows, {
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
frame.Size = UDim2.new(0, 380, 0, 350)
frame.Position = UDim2.new(0, 10, 0, 10)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 26)
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
    table.insert(ISLANDS, { nm, p, 150 })

    local line = string.format('    { "%s", Vector3.new(%d, %d, %d), 150 },',
        nm, math.floor(p.X), math.floor(p.Y), math.floor(p.Z))
    print("[FishItScanner] " .. line)
    pcall(function() if setclipboard then setclipboard(line) end end)

    nameBox.Text = ""
    saveBtn.Text = "Tersimpan!"
    task.delay(1.5, function() saveBtn.Text = "Simpan lokasi" end)
end)

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
    title.Text = "Fish It Scanner - " .. #rows .. " player"

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
    local lines = {}
    for i, r in ipairs(rows) do
        lines[#lines + 1] = string.format("%d. **%s**\n   Pulau: %s\n   Rod: %s",
            i, r.name, r.island, r.rod)
    end
    local text = table.concat(lines, "\n\n")
    if #text > 3800 then text = string.sub(text, 1, 3800) .. "\n..." end
    return #rows, text
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

    local count, text = buildReport()
    local payload = {
        username = BOT_NAME,
        content = "📍 **Update posisi player** (" .. count .. " player di server)",
        embeds = {{
            title = "Fish It - Lokasi & Rod Player",
            description = text,
            color = 3447003,
            footer = { text = "Server: " .. string.sub(game.JobId, 1, 8) .. " | " .. os.date("%H:%M:%S") },
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
