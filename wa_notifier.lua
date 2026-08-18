local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")

local BOT_WEBHOOK_URL = "https://private.gervhosting.my.id/roblox/fish-caught"
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- NOTIFICATION SYSTEM
-- ==========================================
local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5
        })
    end)
end

notify("FishIt WA Notifier", "Script aktif, menunggu hasil tangkapan... 🎣", 5)

-- ==========================================
-- REQUEST FUNCTION CHECKER
-- ==========================================
local function getRequestFunction()
    return (syn and syn.request) 
        or (http and http.request) 
        or http_request 
        or (fluxus and fluxus.request) 
        or request
end

-- ==========================================
-- SEND WEBHOOK FUNCTION
-- ==========================================
local function sendToWA(playerName, fishName, rarity, weight, mutation, chance, imgUrl)
    local data = {
        player = playerName or LocalPlayer.Name,
        fishName = fishName or "Unknown Fish",
        mutation = mutation or "None",
        weight = tostring(weight or "1"),
        rarity = rarity or "Special",
        chance = chance or "1 in 100",
        imageUrl = imgUrl or "",
        serverLuck = "x8",
        luckEnds = "Active"
    }

    local payload = HttpService:JSONEncode(data)

    print("====================================")
    print("[FishIt WA] Mengirim webhook...")
    print("[FishIt WA] Player :", data.player)
    print("[FishIt WA] Fish   :", data.fishName)
    print("[FishIt WA] Rarity :", data.rarity)

    local reqFunc = getRequestFunction()

    -- Metoda 1: Memakai Executor Request Function
    if reqFunc then
        local ok, response = pcall(function()
            return reqFunc({
                Url = BOT_WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json"
                },
                Body = payload
            })
        end)

        if ok and response then
            local statusCode = (type(response) == "table" and (response.StatusCode or response.Status)) or 200
            print("[FishIt WA] ✅ Status:", statusCode)
            notify("FishIt WA ✅", "Data berhasil dikirim!", 4)
            return true
        end
    end

    -- Metoda 2 (Fallback): Memakai Game HttpPostAsync jika Executor Request gagal
    local okAsync = pcall(function()
        game:HttpPostAsync(BOT_WEBHOOK_URL, payload, "application/json")
    end)

    if okAsync then
        print("[FishIt WA] ✅ Webhook terkirim via HttpPostAsync!")
        notify("FishIt WA ✅", "Data terkirim via HttpPost!", 4)
        return true
    else
        warn("[FishIt WA] ❌ Webhook Gagal Dikirim!")
        notify("FishIt WA ❌", "Gagal mengirim webhook", 5)
        return false
    end
end

-- ==========================================
-- TEST WEBHOOK (AUTO TEST 3 DETIK)
-- ==========================================
task.delay(3, function()
    print("[FishIt WA] Mengirim TEST webhook...")
    sendToWA(LocalPlayer.Name, "TEST FISH", "Legendary", "10", "None", "1 in 100", "")
end)

-- ==========================================
-- REMOTE EVENT DETECTION (UNIVERSAL)
-- ==========================================
for _, v in pairs(game:GetDescendants()) do
    if v:IsA("RemoteEvent") then
        v.OnClientEvent:Connect(function(...)
            local args = {...}
            for _, arg in pairs(args) do
                if type(arg) == "table" then
                    local fish = arg.Fish or arg.Name or arg.Item or arg.FishName
                    local pName = arg.Player or arg.Username or (arg.PlayerObj and arg.PlayerObj.Name) or LocalPlayer.Name

                    if fish and (arg.Rarity or arg.Weight or arg.Mutation or arg.Price) then
                        print("[FishIt WA] 🎣 Remote Fish Ditemukan:", fish)
                        sendToWA(pName, fish, arg.Rarity, arg.Weight, arg.Mutation, arg.Chance, arg.Image or arg.Icon)
                    end
                end
            end
        end)
    end
end

-- ==========================================
-- CHAT BROADCAST DETECTION (OLD & NEW CHAT)
-- ==========================================
local function processChatMessage(text, sender)
    local lowerText = string.lower(text or "")
    if string.find(lowerText, "obtained") or string.find(lowerText, "caught") or string.find(lowerText, "found") or string.find(lowerText, "mythic") or string.find(lowerText, "secret") or string.find(lowerText, "legendary") then
        local fishName = text:match("%[(.-)%]") or text:match("[Oo]btained%s+(.+)") or text:match("[Cc]aught%s+(.+)") or "Fish"
        print("[FishIt WA] 📢 Broadcast Chat Ditemukan:", fishName)
        sendToWA(sender ~= "" and sender or LocalPlayer.Name, fishName, "Broadcast", "100", "None", "-", "")
    end
end

-- Chat System Lama
local chatEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
if chatEvents then
    local onMessage = chatEvents:FindFirstChild("OnMessageDoneFiltering")
    if onMessage then
        onMessage.OnClientEvent:Connect(function(data)
            if type(data) == "table" then
                processChatMessage(data.Message, data.FromSpeaker)
            end
        end)
    end
end

-- Chat System Baru (TextChatService)
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    TextChatService.MessageReceived:Connect(function(msg)
        local senderName = msg.TextSource and msg.TextSource.Name or LocalPlayer.Name
        processChatMessage(msg.Text, senderName)
    end)
end

print("====================================")
print("✅ [FishIt WA] SYSTEM READY")
print("🎣 Menunggu fish...")
print("====================================")
