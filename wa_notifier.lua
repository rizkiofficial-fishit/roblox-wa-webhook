local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local BOT_WEBHOOK_URL = "https://private.gervhosting.my.id/roblox/fish-caught"
local LocalPlayer = Players.LocalPlayer

-- Pop-up Notif di Layar
pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "FishIt WA Notifier",
        Text = "Sistem Notifikasi Berhasil Aktif! 🎣",
        Duration = 5
    })
end)

local function sendToWA(playerName, fishName, rarity, weight, mutation, chance, imgUrl)
    local payload = HttpService:JSONEncode({
        player = playerName or LocalPlayer.Name,
        fishName = fishName or "Unknown Fish",
        mutation = mutation or "None",
        weight = tostring(weight or "1"),
        rarity = rarity or "Special",
        chance = chance or "1 in 100",
        imageUrl = imgUrl or "",
        serverLuck = "x8",
        luckEnds = "Active"
    })

    -- Pengiriman data metode ganda (Executor Request & Game HttpPost)
    task.spawn(function()
        local reqFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
        if reqFunc then
            reqFunc({
                Url = BOT_WEBHOOK_URL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = payload
            })
        else
            pcall(function()
                game:HttpPostAsync(BOT_WEBHOOK_URL, payload, "application/json")
            end)
        end
    end)
end

-- 1. DETEKSI REMOTE EVENT
for _, v in pairs(game:GetDescendants()) do
    if v:IsA("RemoteEvent") then
        v.OnClientEvent:Connect(function(...)
            local args = {...}
            for _, arg in pairs(args) do
                if type(arg) == "table" then
                    local fish = arg.Fish or arg.Name or arg.Item or arg.FishName
                    local pName = arg.Player or arg.Username or (arg.PlayerObj and arg.PlayerObj.Name) or LocalPlayer.Name
                    
                    if fish and (arg.Rarity or arg.Weight or arg.Mutation or arg.Price) then
                        sendToWA(pName, fish, arg.Rarity, arg.Weight, arg.Mutation, arg.Chance, arg.Image)
                    end
                end
            end
        end)
    end
end

-- 2. DETEKSI CHAT BROADCAST
local chatEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
if chatEvents then
    local onMessage = chatEvents:FindFirstChild("OnMessageDoneFiltering")
    if onMessage then
        onMessage.OnClientEvent:Connect(function(data)
            local text = data and data.Message or ""
            local sender = data and data.FromSpeaker or ""
            
            if text:find("obtained") or text:find("caught") or text:find("Obtained") or text:find("Found") or text:find("Mythic") or text:find("Secret") or text:find("Legendary") then
                local fishName = text:match("%[(.-)%]") or text:match("obtained%s+(.+)") or "Fish"
                sendToWA(sender ~= "" and sender or LocalPlayer.Name, fishName, "Broadcast", "10", "None", "-", "")
            end
        end)
    end
end

print("✅ [WA-Notifier] System Ready!")
