local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local BOT_WEBHOOK_URL = "https://private.gervhosting.my.id/roblox/fish-caught"

local function showRobloxNotification(title, text)
    task.spawn(function()
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = title,
                Text = text,
                Duration = 4
            })
        end)
    end)
end

local function sendToWA(playerName, fishName, rarity, weight, mutation, chance, imgUrl)
    print("🚀 [WA-NOTIF] MENGIRIM KE WA:", playerName, "|", fishName)
    
    local payload = {
        player = playerName or Players.LocalPlayer.Name,
        fishName = fishName or "Caught Fish",
        mutation = mutation or "None",
        weight = tostring(weight or "1"),
        rarity = rarity or "Special",
        chance = chance or "1 in 100",
        imageUrl = imgUrl or "",
        serverLuck = "x8",
        luckEnds = "Active"
    }

    local reqFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if reqFunc then
        reqFunc({
            Url = BOT_WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end
end

-- 1. HOOK SEMUA REMOTE EVENT DI GAME (Universal Catch)
for _, v in pairs(game:GetDescendants()) do
    if v:IsA("RemoteEvent") then
        v.OnClientEvent:Connect(function(...)
            local args = {...}
            for _, arg in pairs(args) do
                if type(arg) == "table" then
                    -- Cek struktur data pancingan umum
                    local fish = arg.Fish or arg.Name or arg.Item or arg.FishName
                    local pName = arg.Player or arg.Username or (arg.PlayerObj and arg.PlayerObj.Name) or Players.LocalPlayer.Name
                    
                    if fish and (arg.Rarity or arg.Weight or arg.Mutation or arg.Price) then
                        print("🎯 [REMOTE DETECTED]:", pName, fish)
                        sendToWA(pName, fish, arg.Rarity, arg.Weight, arg.Mutation, arg.Chance, arg.Image)
                    end
                end
            end
        end)
    end
end

-- 2. HOOK SEMUA PESAN MASUK DI HUD CHAT
local chatEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
if chatEvents then
    local onMessage = chatEvents:FindFirstChild("OnMessageDoneFiltering")
    if onMessage then
        onMessage.OnClientEvent:Connect(function(data)
            local text = data and data.Message or ""
            local sender = data and data.FromSpeaker or ""
            
            if text:find("obtained") or text:find("caught") or text:find("Obtained") or text:find("Found") then
                print("💬 [CHAT DETECTED]:", text)
                local fishName = text:match("%[(.-)%]") or text:match("obtained%s+(.+)") or "Fish"
                sendToWA(sender ~= "" and sender or Players.LocalPlayer.Name, fishName, "Broadcast", "10", "None", "-", "")
            end
        end)
    end
end

showRobloxNotification("FishIt Notifier", "Sistem Universal Hook Aktif! 🎣")
print("✅ [WA-Notifier] Universal Hook Ready!")
