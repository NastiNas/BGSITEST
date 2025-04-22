queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/YOURUSERNAME/YOURREPO/main/RiftHop.lua'))()")

local TARGET_RIFTS = { "man-egg", "event-2" }
local MAX_PAGES = 5
local MAX_PLAYERS = 10
local REFRESH_INTERVAL = 600
local WD_TIME = 30

local WH_PART1 = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local WH_PART2 = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/" .. WH_PART1 .. WH_PART2

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local RiftFolder  = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local PLACE_ID = game.PlaceId

local CACHE_DIR = "riftHopCache"
local SERVERS_FILE = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

local ActiveRift, LoadingServers = false, false
local Payload

-- Initialize cache
pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

local function showGui(rift, despawnUnix)
    local pivot = rift:GetPivot()
    local y = pivot.Position.Y

    local luckLabel = rift:FindFirstChild("Display")
        and rift.Display:FindFirstChild("SurfaceGui")
        and rift.Display.SurfaceGui:FindFirstChild("Icon")
        and rift.Display.SurfaceGui.Icon:FindFirstChild("Luck")

    local screenGui = Instance.new("ScreenGui", game:GetService("CoreGui"))
    screenGui.Name = "RiftAlert"
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local frame = Instance.new("Frame", screenGui)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0, 300, 0, 150)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.3

    local layout = Instance.new("UIListLayout", frame)
    layout.Padding = UDim.new(0, 4)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center

    local function label(text)
        local l = Instance.new("TextLabel", frame)
        l.Size = UDim2.new(1, -16, 0, 20)
        l.BackgroundTransparency = 1
        l.TextColor3 = Color3.new(1, 1, 1)
        l.TextScaled = true
        l.Text = text
    end

    label("Rift: "..rift.Name)
    label("Player: "..LocalPlayer.Name)
    label(("Y Height: %.1f"):format(y))
    label("Despawn: <t:"..despawnUnix..":R>")
    label("Luck: "..(luckLabel and luckLabel.Text or "N/A"))
end

local function TimeLeftUnix(rift)
    local timeLbl = rift:FindFirstChild("Display")
        and rift.Display:FindFirstChild("SurfaceGui")
        and rift.Display.SurfaceGui:FindFirstChild("Timer")

    if not timeLbl then return os.time() + 600 end

    local txt = timeLbl.Text:lower()
    local num, unit = txt:match("(%d+)%s*(%a+)")
    num = tonumber(num)

    local multipliers = { second = 1, seconds = 1, minute = 60, minutes = 60 }
    local mult = multipliers[unit] or 60

    return os.time() + (num * mult)
end

local function SendWebhook()
    local req = (http and http.request) or request or (syn and syn.request)
    if not req then return warn("No HTTP lib found") end

    req({
        Url = WEBHOOK_URL,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(Payload)
    })
end

local function ScanForRift()
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if table.find(TARGET_RIFTS, rift.Name) then
            local unix = TimeLeftUnix(rift)

            Payload = {
                embeds = { {
                    title = rift.Name.." Rift Found!",
                    description = ("[Jump to Server](https://www.roblox.com/games/%d/#!/server?id=%s)\n**Despawn:** <t:%d:R>\nPlayer: %s")
                        :format(PLACE_ID, game.JobId, unix, LocalPlayer.Name),
                    color = 0x00FF00
                } }
            }

            showGui(rift, unix)
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

local function FetchServers()
    LoadingServers = true
    local servers, cursor = {}, ""
    for _ = 1, MAX_PAGES do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s"):format(
            PLACE_ID, cursor ~= "" and "&cursor="..cursor or "")
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({ Url = url })
        end)
        if ok and resp and resp.Body then
            local data = HttpService:JSONDecode(resp.Body)
            for _, s in ipairs(data.data or {}) do
                if tonumber(s.playing) <= MAX_PLAYERS then
                    table.insert(servers, s.id)
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

local function GetServerList()
    local last = tonumber(readfile(TIMESTAMP_FILE)) or 0
    if os.time() - last > REFRESH_INTERVAL then return FetchServers() end
    local ok, list = pcall(function()
        return HttpService:JSONDecode(readfile(SERVERS_FILE))
    end)
    return ok and list or FetchServers()
end

local function AutoHop()
    local servers = GetServerList()
    if #servers == 0 then task.wait(3) return AutoHop() end
    local pick = table.remove(servers, math.random(1, #servers))
    writefile(SERVERS_FILE, HttpService:JSONEncode(servers))

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, pick)
    end)
    if not ok then
        warn("Teleport failed: ", err)
        TeleportService:Teleport(PLACE_ID)
    end
end

-- Watchdog
task.spawn(function()
    task.wait(WD_TIME)
    while true do
        if not ActiveRift and not LoadingServers then
            AutoHop()
        end
        task.wait(1)
    end
end)

-- Run
print("Started " ..LocalPlayer.Name)
repeat task.wait() until game:IsLoaded()
if ScanForRift() then
    print("RIFT FOUND - "..LocalPlayer.Name)
    SendWebhook()
end
