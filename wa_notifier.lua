local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local BOT_WEBHOOK_URL = "https://private.gervhosting.my.id/roblox/fish-caught"
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- NOTIFICATION
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

notify(
    "FishIt WA Notifier",
    "Script aktif, menunggu hasil tangkapan... 🎣",
    5
)

-- ==========================================
-- REQUEST FUNCTION
-- ==========================================

local function getRequestFunction()
    return (syn and syn.request)
        or (http and http.request)
        or http_request
        or (fluxus and fluxus.request)
        or request
end

-- ==========================================
-- SEND WEBHOOK
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
    print("[FishIt WA] Weight :", data.weight)
    print("[FishIt WA] Mutation:", data.mutation)
    print("[FishIt WA] Payload:", payload)

    local reqFunc = getRequestFunction()

    if not reqFunc then
        warn("[FishIt WA] Request function tidak ditemukan.")

        notify(
            "FishIt WA ❌",
            "Executor tidak mendukung HTTP request",
            5
        )

        return false
    end

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

    if not ok then

        warn("[FishIt WA] Request ERROR:")
        warn(response)

        notify(
            "FishIt WA ❌",
            "Webhook gagal dikirim",
            5
        )

        return false
    end

    print("[FishIt WA] Response:", response)

    local statusCode = nil
    local responseBody = nil

    if type(response) == "table" then
        statusCode = response.StatusCode or response.Status
        responseBody = response.Body or response.body
    elseif type(response) == "string" then
        responseBody = response
    end

    print("[FishIt WA] Status:", statusCode or "unknown")
    print("[FishIt WA] Body:", responseBody or "empty")

    -- ==========================================
    -- CEK STATUS
    -- ==========================================

    if statusCode then

        if statusCode >= 200 and statusCode < 300 then

            print("[FishIt WA] ✅ WEBHOOK BERHASIL")

            notify(
                "FishIt WA ✅",
                "Data berhasil dikirim ke webhook!",
                4
            )

            return true

        else

            warn("[FishIt WA] ❌ HTTP ERROR:", statusCode)

            notify(
                "FishIt WA ❌",
                "Webhook error HTTP " .. tostring(statusCode),
                6
            )

            return false
        end

    end

    -- Beberapa executor tidak memberikan StatusCode.
    -- Jadi jangan langsung menganggap gagal.

    print("[FishIt WA] ⚠️ Response tidak memiliki StatusCode.")

    notify(
        "FishIt WA ⚠️",
        "Request terkirim, tetapi status server tidak diketahui",
        5
    )

    return true
end

-- ==========================================
-- TEST WEBHOOK
-- ==========================================

task.delay(3, function()

    print("[FishIt WA] Mengirim TEST webhook...")

    sendToWA(
        LocalPlayer.Name,
        "TEST FISH",
        "Legendary",
        "10",
        "None",
        "1 in 100",
        ""
    )

end)

-- ==========================================
-- REMOTE EVENT DETECTION
-- ==========================================

for _, v in pairs(game:GetDescendants()) do

    if v:IsA("RemoteEvent") then

        v.OnClientEvent:Connect(function(...)

            local args = {...}

            for _, arg in pairs(args) do

                if type(arg) == "table" then

                    local fish =
                        arg.Fish
                        or arg.Name
                        or arg.Item
                        or arg.FishName

                    local pName =
                        arg.Player
                        or arg.Username
                        or (arg.PlayerObj and arg.PlayerObj.Name)
                        or LocalPlayer.Name

                    if fish and (
                        arg.Rarity
                        or arg.Weight
                        or arg.Mutation
                        or arg.Price
                    ) then

                        print(
                            "[FishIt WA] 🎣 Fish ditemukan:",
                            fish
                        )

                        sendToWA(
                            pName,
                            fish,
                            arg.Rarity,
                            arg.Weight,
                            arg.Mutation,
                            arg.Chance,
                            arg.Image
                        )

                    end
                end
            end
        end)
    end
end

-- ==========================================
-- CHAT BROADCAST DETECTION
-- ==========================================

local chatEvents =
    ReplicatedStorage:FindFirstChild(
        "DefaultChatSystemChatEvents"
    )

if chatEvents then

    local onMessage =
        chatEvents:FindFirstChild(
            "OnMessageDoneFiltering"
        )

    if onMessage then

        onMessage.OnClientEvent:Connect(function(data)

            if type(data) ~= "table" then
                return
            end

            local text =
                data.Message
                or ""

            local sender =
                data.FromSpeaker
                or ""

            local lowerText =
                string.lower(text)

            if
                string.find(lowerText, "obtained")
                or string.find(lowerText, "caught")
                or string.find(lowerText, "found")
                or string.find(lowerText, "mythic")
                or string.find(lowerText, "secret")
                or string.find(lowerText, "legendary")
            then

                local fishName =
                    text:match("%[(.-)%]")
                    or text:match(
                        "[Oo]btained%s+(.+)"
                    )
                    or text:match(
                        "[Cc]aught%s+(.+)"
                    )
                    or "Fish"

                print(
                    "[FishIt WA] 📢 Broadcast fish:",
                    fishName
                )

                sendToWA(
                    sender ~= "" and sender
                        or LocalPlayer.Name,

                    fishName,

                    "Broadcast",

                    "10",

                    "None",

                    "-",

                    ""
                )
            end
        end)
    end
end

print("====================================")
print("✅ [FishIt WA] SYSTEM READY")
print("🎣 Menunggu fish...")
print("====================================")
