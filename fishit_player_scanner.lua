--[[
    Fish It - Player Scanner (read-only)
    Nampilin semua player di server: lagi di pulau mana + pake rod apa.
    Cuma baca data yang udah ke-replicate ke client, ga ngubah apa-apa di game.

    CARA PAKAI:
    1. Isi WEBHOOK_URL di bawah (wajib kalau mau notif ke WA).
    2. Jalankan script. Panel muncul di kiri atas.
    3. Simpan pulau: berdiri di pulau, ketik nama pulau di kolom bawah, tekan "Simpan lokasi".
    4. AJARIN ROD (kalau rod kamu tampil "tidak dikenal"): pegang rod kamu,
       ketik nama rodnya di kolom bawah, tekan tombol "Rod". Disimpan ke file
       FishItRods.json (kalau executor support writefile), jadi permanen.
    5. Tombol "?" = dump debug (kandidat rod + skor) ke clipboard & console.
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
-- Hasil match ke nama-nama ini ditampilin sebagai GENERIC_LABEL.
local GENERIC_RODS = {} -- kosong = semua nama rod tampil apa adanya
local GENERIC_LABEL = "Rod biasa (non-skin)"

local ROD_ATTRIBUTE_NAMES = { "EquippedRod", "Rod", "FishingRod", "CurrentRod" }

local cfg = (getgenv and getgenv().FishItConfig) or {}
if cfg.WEBHOOK_URL then WEBHOOK_URL = cfg.WEBHOOK_URL end
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

------------------------------------------------------------
-- LOGIKA
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
-- templates: rod/item model dari game (ReplicatedStorage dll), { name=, path=, set=, n= }
-- learned:   rod yang kamu ajarin manual lewat tombol "Rod"
local templates = nil
local learned = {}
local rodCache = {} -- signature -> nama

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

-- cari "model item" teratas dari sebuah MeshPart
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

-- hitung skor model terhadap satu entry
local function scoreOf(set, n, t)
    local common = 0
    for id in pairs(set) do
        if t.set[id] then common = common + 1 end
    end
    if common == 0 then return 0, 0, 0 end
    local coverage = common / n                    -- berapa % mesh model yang ada di template
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

    -- skin rod disimpan game di attribute player
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

-- FLAG_Fishing cuma true sesaat (pas lempar/nunggu), jadi dibuat "nempel":
-- dianggap mancing kalau sinyalnya pernah aktif dalam FISHING_HOLD detik terakhir.
local FISHING_HOLD = 45
local lastFishing = {}

local function isFishing(plr)
    local now = os.clock()
    local sig = plr:GetAttribute("FLAG_Fishing") == true
        or plr:GetAttribute("PetFishingActive") == true
        or plr:GetAttribute("EquippedPetState") == "Fishing"
    if sig then lastFishing[plr] = now end
    local t = lastFishing[plr]
    return t ~= nil and (now - t) <= FISHING_HOLD
end

local function scan()
    local rows = {}
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

        table.insert(rows, {
            fishing = isFishing(plr),
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

-- Ajarin rod: pegang rod, ketik namanya, klik "Rod"
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

    -- timpa entry lama dengan nama yang sama
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
        l.Text = "  " .. (r.fishing and "🟢 " or "⚪ ") .. r.name .. "\n  Pulau: " .. r.island .. "  |  Rod: " .. r.rod
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
-- NOTIF WEBHOOK
------------------------------------------------------------
local httpRequest = (syn and syn.request)
    or (http and http.request)
    or http_request
    or request
    or (fluxus and fluxus.request)

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
    local fishingCount = 0
    for _, island in ipairs(order) do
        local members = groups[island]
        local lines = { string.format("🏝️ **%s** · %d player", island, #members) }
        for _, m in ipairs(members) do
            local rod = (m.rod ~= "-") and m.rod or "–"
            local mark = m.fishing and "🟢" or "⚪"
            lines[#lines + 1] = string.format("> %s %s  ·  🎣 %s", mark, m.display, rod)
            if m.fishing then fishingCount = fishingCount + 1 end
        end
        blocks[#blocks + 1] = table.concat(lines, "\n")
    end

    local text = table.concat(blocks, "\n\n")
    if #text > 3800 then text = string.sub(text, 1, 3800) .. "\n..." end
    return #rows, #order, text, fishingCount
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

    local count, islandCount, text, fishingCount = buildReport()
    local payload = {
        username = BOT_NAME,
        content = "📍 **Update posisi pemancing** (" .. count .. " player di server)",
        embeds = {{
            title = "🎣 Fish It — Peta Pemancing",
            description = string.format(
                "👥 **%d** player  ·  🎣 **%d** mancing  ·  🏝️ **%d** lokasi\n🟢 lagi mancing   ⚪ tidak\n\n%s",
                count, fishingCount, islandCount, text),
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
