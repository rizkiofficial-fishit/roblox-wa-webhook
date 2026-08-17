local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")

-- ============================================================
-- ⚙️ CONFIG WEBHOOK
-- ============================================================
local BOT_WEBHOOK_URL = "https://private.gervhosting.my.id/roblox/fish-caught"
-- ============================================================

local function sendToWA(playerName, fishName, rarity, weight, mutation, chance, imgUrl)
    local payload = {
        player = playerName or "Unknown",
        fishName = fishName or "Unknown Fish",
        mutation = mutation or "None",
        weight = tostring(weight or "0"),
        rarity = rarity or "Secret",
        chance = chance or "1 in 1M",
        imageUrl = imgUrl or "",
        serverLuck = "x8",
        luckEnds = "Active"
    }

    local reqFunc = (syn and syn.request) or (http and http.request) or http_request or fluxus.request or request
    if reqFunc then
        reqFunc({
            Url = BOT_WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end
end

-- 1. DETEKSI VIA REMOTE EVENT (1 SERVER)
task.spawn(function()
    local packages = ReplicatedStorage:WaitForChild("Packages", 10) or ReplicatedStorage:WaitForChild("Events", 10)
    if packages then
        for _, child in pairs(packages:GetDescendants()) do
            if child:IsA("RemoteEvent") and (child.Name:find("Catch") or child.Name:find("Obtain") or child.Name:find("Global")) then
                child.OnClientEvent:Connect(function(...)
                    local args = {...}
                    if args[1] and type(args[1]) == "table" then
                        local d = args[1]
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

-- 2. DETEKSI VIA CHAT SYSTEM (BROADCAST SERVER)
task.spawn(function()
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        TextChatService.MessageReceived:Connect(function(msg)
            local text = msg.Text or ""
            if text:find("Obtained") or text:find("caught") or text:find("Has Obtained") then
                local pName, fishName = text:match("%[(.-)%].-%[(.-)%]")
                if pName and fishName then
                    sendToWA(pName, fishName, "Server Broadcast", "100+", "None", "Global", "")
                end
            end
        end)
    end
end)

print("✅ [WA-Notifier] Webhook FishIt 1 Server Berhasil Aktif!")