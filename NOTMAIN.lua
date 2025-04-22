queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")


-- CONFIG
local Target_Rift1 = "man-egg"
local Target_Rift2 = "event-2"
local MAX_PAGES = 5
local MAX_PLAYERS = 10
local REFRESH_INTERVAL = 600
local WD_TIME = 30

-- WEBHOOK
local WH_PART1 = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local WH_PART2 = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/" .. WH_PART1 .. WH_PART2

-- SERVICES
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local RiftFolder = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local PLACE_ID = game.PlaceId

-- FILE CACHE
local CACHE_DIR = "riftHopCache"
local SERVERS_FILE = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

local ActiveRift, LoadingServers = false, false
local Payload

-- Ensure cache exists
pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

local function TimeLeftUnix(rift)
    local gui = rift:FindFirstChild("Display")
    local label = gui and gui:FindFirstChild("SurfaceGui") and gui.SurfaceGui:FindFirstChild("Timer")
    local text = label and label.Text:lower() or "10 minutes"
    local num, unit = text:match("(%d+)%s*(%a+)")
    num = tonumber(num)
    local mult = ({second=1,seconds=1,minute=60,minutes=60})[unit] or 60
    return os.time() + ((num or 10) * mult)
end

local function showRiftGui(rift, unixTime)
    local pivot = rift:GetPivot()
    local y = pivot.Position.Y
    local luck = rift:FindFirstChild("Display")
        and rift.Display:FindFirstChild("SurfaceGui")
        and rift.Display.SurfaceGui:FindFirstChild("Icon")
        and rift.Display.SurfaceGui.Icon:FindFirstChild("Luck")
    local screenGui = Instance.new("ScreenGui", game:GetService("CoreGui"))
    screenGui.Name = "RiftAlert"

    local frame = Instance.new("Frame", screenGui)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0, 300, 0, 140)
    frame.BackgroundColor3 = Color3.new(0, 0, 0)
    frame.BackgroundTransparency = 0.3

    local layout = Instance.new("UIListLayout", frame)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 4)

    local function makeLabel(txt)
        local label = Instance.new("TextLabel", frame)
        label.Size = UDim2.new(1, -16, 0, 20)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextScaled = true
        label.Text = txt
    end

    makeLabel("Rift: "..rift.Name)
    makeLabel("Player: "..LocalPlayer.Name)
    makeLabel(("Y Height: %.1f"):format(y))
    makeLabel("Despawn: <t:"..unixTime..":R>")
    makeLabel("Luck: "..(luck and luck.Text or "N/A"))
end

local function PostWebhook()
    local req = (http and http.request) or request or (syn and syn.request)
    if not req then return warn("["..LocalPlayer.Name.."] no HTTP library") end
    req({
        Url = WEBHOOK_URL,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(Payload)
    })
end

local function ScanForRift()
    print("["..LocalPlayer.Name.."] → scanning for Rift…")
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == Target_Rift1 or rift.Name == Target_Rift2 then
            local unix = TimeLeftUnix(rift)
            Payload = {
                embeds = {{
                    title = rift.Name.." Rift Found!",
                    description = ("[Server](https://www.roblox.com/games/%d/#!/server?id=%s)\nALT: [Profile](https://www.roblox.com/users/%d/profile)\nDespawn: <t:%d:R>")
                        :format(PLACE_ID, game.JobId, LocalPlayer.UserId, unix),
                    color = 0x00FF00
                }}
            }
            showRiftGui(rift, unix)
            print("["..LocalPlayer.Name.."] → FOUND Rift!")
            ActiveRift = true
            task.spawn(function()
                repeat task.wait(1) until not rift:IsDescendantOf(workspace)
                ActiveRift = false
            end)
            return true
        end
    end
    print("["..LocalPlayer.Name.."] → no Rift found")
    return false
end

local function FetchServers()
    LoadingServers = true
    print("["..LocalPlayer.Name.."] → fetching server list…")
    local servers, cursor = {}, ""
    for page = 1, MAX_PAGES do
        print(("["..LocalPlayer.Name.."] [DEBUG] page %d, cursor=%s"):format(page, cursor))
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?limit=100&excludeFullGames=true%s")
            :format(PLACE_ID, cursor ~= "" and "&cursor="..cursor or "")
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        if not ok or not resp or not resp.Body then
            warn("["..LocalPlayer.Name.."] failed to fetch page", page)
            task.wait(2)
            continue
        end
        local data = HttpService:JSONDecode(resp.Body)
        for _, s in ipairs(data.data or {}) do
            if tonumber(s.playing) <= MAX_PLAYERS then
                table.insert(servers, s.id)
            end
        end
        cursor = data.nextPageCursor or ""
        if cursor == "" then break end
        task.wait(1)
    end
    writefile(SERVERS_FILE, HttpService:JSONEncode(servers))
    writefile(TIMESTAMP_FILE, tostring(os.time()))
    print("["..LocalPlayer.Name.."] → fetched", #servers, "servers.")
    LoadingServers = false
    return servers
end

local function GetServerList()
    print("["..LocalPlayer.Name.."] [DEBUG] loading server list (cache check)…")
    local last = tonumber(readfile(TIMESTAMP_FILE)) or 0
    if os.time() - last > REFRESH_INTERVAL then
        print("["..LocalPlayer.Name.."] → cache expired")
        return FetchServers()
    else
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(SERVERS_FILE))
        end)
        if ok and type(data) == "table" then
            print("["..LocalPlayer.Name.."] → loaded", #data, "servers from cache")
            return data
        else
            print("["..LocalPlayer.Name.."] → cache invalid")
            return FetchServers()
        end
    end
end

local function AutoHop()
    print("["..LocalPlayer.Name.."] → autoHop()")
    local list = GetServerList()
    if #list == 0 then
        warn("["..LocalPlayer.Name.."] → no servers found, retrying in 5s")
        task.wait(5)
        return AutoHop()
    end
    local choice = table.remove(list, math.random(1, #list))
    writefile(SERVERS_FILE, HttpService:JSONEncode(list))
    print("["..LocalPlayer.Name.."] → hopping to", choice)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, choice)
    end)
    if not ok then
        warn("["..LocalPlayer.Name.."] → teleport failed:", err)
        TeleportService:Teleport(PLACE_ID)
    end
end

-- Watchdog
task.spawn(function()
    task.wait(WD_TIME)
    while true do
        if not ActiveRift and not LoadingServers then
            print("["..LocalPlayer.Name.."] → Watchdog triggered, no Rift → autoHop()")
            AutoHop()
        end
        task.wait(1)
    end
end)

-- INIT
repeat task.wait() until game:IsLoaded()
print("["..LocalPlayer.Name.."] → RiftHunter script started.")
if ScanForRift() then
    PostWebhook()
else
    AutoHop()
end
