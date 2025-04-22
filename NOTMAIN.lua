--!strict

-- queue loader on teleport
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/YOURUSERNAME/YOURREPO/main/RiftHop.lua'))()")

-- CONFIG
local Target_Rift1 = "man-egg"
local Target_Rift2 = "event-2"
local MAX_PAGES = 5
local MAX_PLAYERS = 10
local REFRESH_INTERVAL = 10 * 60 -- 10 minutes
local WD_TIME = 30 -- seconds

-- WEBHOOK
local WH_PART1 = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local WH_PART2 = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/" .. WH_PART1 .. WH_PART2

-- SERVICES
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local RiftFolder = workspace:WaitForChild("Worlds"):WaitForChild("The Overworld"):WaitForChild("Rift")
local PLACE_ID = game.PlaceId

-- FILE CACHE
local CACHE_DIR = "riftHopCache"
local SERVERS_FILE = CACHE_DIR .. "/servers.json"
local TIMESTAMP_FILE = CACHE_DIR .. "/timestamp.txt"

-- STATE
local ActiveRift = false
local LoadingServers = false
local Payload

-- Ensure cache exists
pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

-- GUI when Rift is found
local function showRiftGui(rift: Model, timeLeft: string)
    local pivot = rift:GetPivot()
    local yValue = pivot.Position.Y

    local luckLbl = rift:FindFirstChild("Display")
        and rift.Display:FindFirstChild("SurfaceGui")
        and rift.Display.SurfaceGui:FindFirstChild("Icon")
        and rift.Display.SurfaceGui.Icon:FindFirstChild("Luck")
    local luckValue = luckLbl and luckLbl.Text or "N/A"

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RiftAlert"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = game:GetService("CoreGui")

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0, 300, 0, 140)
    frame.BackgroundColor3 = Color3.new(0, 0, 0)
    frame.BackgroundTransparency = 0.3
    frame.Parent = screenGui

    local uiList = Instance.new("UIListLayout")
    uiList.FillDirection = Enum.FillDirection.Vertical
    uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    uiList.VerticalAlignment = Enum.VerticalAlignment.Center
    uiList.Padding = UDim.new(0, 4)
    uiList.Parent = frame

    local function makeLabel(txt: string)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -16, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.Text = txt
        lbl.TextColor3 = Color3.new(1, 1, 1)
        lbl.TextScaled = true
        lbl.Parent = frame
    end

    makeLabel("Rift: " .. rift.Name)
    makeLabel("Player: " .. LocalPlayer.Name)
    makeLabel(("Y Pivot: %.2f"):format(yValue))
    makeLabel("Time Left: " .. timeLeft)
    makeLabel("Luck: " .. luckValue)
end

-- TimeLeft helper
local function TimeLeft(timedRift)
    local display = timedRift:FindFirstChild("Display")
    local timeLeft = display:FindFirstChild("SurfaceGui"):FindFirstChild("Timer").Text
    local amount, unit = string.match(timeLeft:lower(), "(%d+)%s*(%a+)")
    local multipliers = { second = 1, seconds = 1, minute = 60, minutes = 60 }
    return os.time() + ((tonumber(amount) or 0) * (multipliers[unit] or 0))
end

-- Webhook
local function PostWebhook()
    local body = HttpService:JSONEncode(Payload)
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body
        })
    end
end

-- Scan for Rift
local function ScanForRift()
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == Target_Rift1 or rift.Name == Target_Rift2 then
            local display = rift:FindFirstChild("Display")
            local RiftPivot = rift:GetPivot()
            local Height = RiftPivot.Position.Y
            local EggLuck = display and display:FindFirstChild("SurfaceGui") and display.SurfaceGui:FindFirstChild("Icon") and display.SurfaceGui.Icon:FindFirstChild("Luck") and display.SurfaceGui.Icon.Luck.Text or "N/A"

            Payload = {
                ["embeds"] = { {
                    ["title"] = rift.Name .. " Rift Found!",
                    ["description"] = "Rift detected in [Server](https://www.roblox.com/games/" .. game.PlaceId .. "/?#!/server?id=" .. game.JobId .. ")\nALT LINK: [Profile](https://www.roblox.com/users/" .. LocalPlayer.UserId .. "/profile)\nDespawn Time: " .. TimeLeft(rift) .. "\nLuck: " .. EggLuck .. "\nHeight: " .. Height .. "~ meters",
                    ["color"] = 0x00FF00
                } }
            }

            showRiftGui(rift, tostring(TimeLeft(rift)))
            ActiveRift = true
            task.spawn(function()
                repeat task.wait(1) until not rift.Parent or not rift:IsDescendantOf(workspace)
                ActiveRift = false
            end)

            return true
        end
    end
    return false
end

-- AutoHop
local function fetchServerList(): { string }
    LoadingServers = true
    local servers, cursor = {}, ""
    for page = 1, MAX_PAGES do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true%s")
            :format(PLACE_ID, cursor ~= "" and "&cursor=" .. cursor or "")
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({ Url = url })
        end)
        if ok and resp and resp.Body then
            local data = HttpService:JSONDecode(resp.Body)
            for _, server in ipairs(data.data or {}) do
                if tonumber(server.playing) <= MAX_PLAYERS and not server.vipServerId then
                    table.insert(servers, server.id)
                end
            end
            cursor = data.nextPageCursor or ""
            if cursor == "" then break end
        end
        task.wait(1)
    end
    writefile(SERVERS_FILE, HttpService:JSONEncode(servers))
    writefile(TIMESTAMP_FILE, tostring(os.time()))
    LoadingServers = false
    return servers
end

local function getServerList(): { string }
    local lastTs = tonumber(readfile(TIMESTAMP_FILE)) or 0
    if os.time() - lastTs > REFRESH_INTERVAL then
        return fetchServerList()
    else
        local data = readfile(SERVERS_FILE)
        local ok, decoded = pcall(function() return HttpService:JSONDecode(data) end)
        return (ok and decoded) or fetchServerList()
    end
end

local function AutoHop()
    local list = getServerList()
    if #list == 0 then
        task.wait(5)
        return AutoHop()
    end

    local chosen = list[math.random(1, #list)]
    local remaining = {}
    for _, sid in ipairs(list) do
        if sid ~= chosen then table.insert(remaining, sid) end
    end
    writefile(SERVERS_FILE, HttpService:JSONEncode(remaining))

    pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, chosen)
    end)
end

-- Watchdog logic
repeat task.wait() until game:IsLoaded()
task.spawn(function()
    task.wait(WD_TIME)
    while true do
        if not ActiveRift and not LoadingServers then
            AutoHop()
        end
        task.wait(5)
    end
end)

-- Initial run
if ScanForRift() then
    PostWebhook()
else
    AutoHop()
end
