local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local BOT_WEBHOOK_URL = "https://private.gervhosting.my.id/roblox/fish-caught"

local function showRobloxNotification(title, text)
    task.spawn(function()
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = title,
                Text = text,
                Duration = 5
            })
        end)
    end)
end

local function sendToWA(playerName, fishName, rarity, weight, mutation, chance, imgUrl)
    print("🔍 [WA-DEBUG] Mencoba Mengirim Notif untuk Player:", playerName, "| Ikan:", fishName)

    local payload = {
        player = playerName or "Unknown",
        fishName = fishName or "Unknown Fish",
        mutation = mutation or "None",
        weight = tostring(weight or "0"),
        rarity = rarity or "Mythic/Secret",
        chance = chance or "1 in 1M",
        imageUrl = imgUrl or "",
        serverLuck = "x8",
        luckEnds = "Active"
    }

    local reqFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if reqFunc then
        local response = reqFunc({
            Url = BOT_WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
        print("📥 [WA-DEBUG] Respon VPS Server:", response.Body or response.StatusCode)
    else
        print("❌ [WA-DEBUG] Executor kamu tidak mendukung HTTP Request!")
    end
end

-- 1. DETEKSI VIA REMOTE EVENT
task.spawn(function()
    local packages = ReplicatedStorage:WaitForChild("Packages", 10) or ReplicatedStorage:WaitForChild("Events", 10)
    if packages then
        for _, child in pairs(packages:GetDescendants()) do
            if child:IsA("RemoteEvent") and (child.Name:find("Catch") or child.Name:find("Obtain") or child.Name:find("Global")) then
                child.OnClientEvent:Connect(function(...)
                    local args = {...}
                    if args[1] and type(args[1]) == "table" then
                        local d = args[1]
                        -- Cari username asli (bukan display name)
                        local pName = d.Player or d.Username or (d.PlayerObj and d.PlayerObj.Name)
                        if pName then
                            sendToWA(pName, d.Name, d.Rarity, d.Weight, d.Mutation, d.Chance, d.Image or d.Icon)
                        end
                    end
                end)
            end
        end
    end
end)

-- 2. DETEKSI VIA CHAT SYSTEM (BROADCAST ALL FORMAT)
task.spawn(function()
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        TextChatService.MessageReceived:Connect(function(msg)
            local text = msg.Text or ""
            if text:find("Obtained") or text:find("caught") or text:find("Has Obtained") or text:find("Mythic") or text:find("Secret") then
                print("💬 [WA-DEBUG] Chat Terdeteksi:", text)
                
                -- Format 1: [Username] obtained [FishName]
                local pName, fishName = text:match("%[(.-)%].-%[(.-)%]")
                
                -- Format 2 (Fallback): Username obtained FishName
                if not pName then
                    pName, fishName = text:match("(%w+)%s+has%s+obtained%s+(.+)")
                end

                if pName and fishName then
                    sendToWA(pName, fishName, "Server Broadcast", "100+", "None", "Global", "")
                end
            end
        end)
    end
end)

showRobloxNotification("Fish It Notifier", "Notifier Debug Mode Active! 🎣")
print("✅ [WA-Notifier] Webhook FishIt Debug Active!")
