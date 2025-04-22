queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")

-- CONFIG
local TARGET_RIFTS = {["man-egg"] = true, ["event-2"] = true}
local MAX_PAGES = 5
local MAX_PLAYERS = 10
local REFRESH_INTERVAL = 600
local WATCHDOG_TIME = 40

-- WEBHOOK
local WH_PART1 = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local WH_PART2 = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/"..WH_PART1..WH_PART2

-- SERVICES
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local RiftFolder = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local PLACE_ID = game.PlaceId
local ActiveRift = false

-- CACHE
local CACHE_DIR = "riftHopCache"
local SERVERS_FILE = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"
local loadingServers = false

-- make sure folder/files exist
pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

-- Rift detection GUI
local function showRiftGui(rift: Model, despawnTime: number, luckValue: string)
    local y = math.floor(rift:GetPivot().Position.Y)

    local gui = Instance.new("ScreenGui")
    gui.Name = "RiftAlert"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = game:GetService("CoreGui")

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0, 300, 0, 140)
    frame.BackgroundColor3 = Color3.new(0,0,0)
    frame.BackgroundTransparency = 0.3
    frame.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 4)
    layout.Parent = frame

    local function makeLabel(txt: string)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -16, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.Text = txt
        lbl.TextColor3 = Color3.new(1,1,1)
        lbl.TextScaled = true
        lbl.Parent = frame
    end

    makeLabel("Rift: "..rift.Name)
    makeLabel("Player: "..LocalPlayer.Name)
    makeLabel("Y Height: "..y)
    makeLabel("Luck: "..luckValue)
    makeLabel("Despawn: <t:"..despawnTime..":R>")
end

-- Time parser
local function parseDespawnTime(rift)
    local timerLbl = rift:FindFirstChild("Display")
                     and rift.Display:FindFirstChild("SurfaceGui")
                     and rift.Display.SurfaceGui:FindFirstChild("Timer")
    local raw = (timerLbl and timerLbl.Text or ""):lower()
    local amt, unit = raw:match("(%d+)%s*(%a+)")
    local num = tonumber(amt or "")
    if not num then return os.time() + 600 end
    local mult = ({second=1, seconds=1, minute=60, minutes=60})[unit] or 1
    return os.time() + (num * mult)
end

-- Webhook
local function sendWebhook(rift, despawnUnix, luckValue, height)
    local payload = {
        embeds = {{
            title = rift.Name.." Rift Found!",
            description = "Rift detected by **"..LocalPlayer.Name.."**\n"
                .."Height: "..math.floor(height).."m\n"
                .."Luck: "..luckValue.."\n"
                .."Despawn: <t:"..despawnUnix..":R>\n"
                .."[Join](https://www.roblox.com/games/"..game.PlaceId.."#!/server?id="..game.JobId..")\n"
                .."[Alt Link](https://www.roblox.com/users/"..LocalPlayer.UserId.."/profile)",
            color = 0x00FF00
        }}
    }

    local json = HttpService:JSONEncode(payload)
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = json
        })
    else
        warn("["..LocalPlayer.Name.."] → no HTTP method available")
    end
end

-- Scan for Rift
local function scanForRift(): boolean
    print("["..LocalPlayer.Name.."] → scanning for Rift…")
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if TARGET_RIFTS[rift.Name] and rift:FindFirstChild("EggPlatformSpawn") then
            print("["..LocalPlayer.Name.."] → FOUND Rift: "..rift.Name)
            local luckLbl = rift:FindFirstChild("Display")
                            and rift.Display:FindFirstChild("SurfaceGui")
                            and rift.Display.SurfaceGui:FindFirstChild("Icon")
                            and rift.Display.SurfaceGui.Icon:FindFirstChild("Luck")
            local luckVal = (luckLbl and luckLbl.Text) or "???"
            local despawn = parseDespawnTime(rift)
            local height = rift:GetPivot().Position.Y

            sendWebhook(rift, despawn, luckVal, height)
            showRiftGui(rift, despawn, luckVal)

            ActiveRift = true
            task.spawn(function()
                repeat task.wait(1) until not rift.Parent or not rift:IsDescendantOf(workspace)
                ActiveRift = false
            end)
            
            return true
        end
    end
    print("["..LocalPlayer.Name.."] → no Rift found.")
    return false
end

-- Safe teleport
local function safeTeleport(serverId)
    print("["..LocalPlayer.Name.."] → teleporting to", serverId)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, serverId)
    end)
    if not ok then
        warn("Teleport failed:", err)
        pcall(function() TeleportService:Teleport(PLACE_ID) end)
    end
end

-- Fetch fresh servers
local function fetchServers(): {string}
    loadingServers = true
    print("["..LocalPlayer.Name.."] → fetching server list")
    local servers, cursor = {}, ""
    for page = 1, MAX_PAGES do
        print(("→ fetching page %d..."):format(page))
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s"):format(
            PLACE_ID,
            cursor ~= "" and "&cursor="..cursor or ""
        )
        local success, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url = url})
        end)
        if success and resp and resp.Body then
            local data = HttpService:JSONDecode(resp.Body)
            for _, server in ipairs(data.data or {}) do
                if tonumber(server.playing) <= MAX_PLAYERS then
                    table.insert(servers, server.id)
                end
            end
            cursor = data.nextPageCursor or ""
            if cursor == "" then break end
        else
            warn("→ failed page", page)
        end
        task.wait(1)
    end
    writefile(SERVERS_FILE, HttpService:JSONEncode(servers))
    writefile(TIMESTAMP_FILE, tostring(os.time()))
    loadingServers = false
    return servers
end

-- Load cached servers
local function getServerList()
    print("→ loading cached server list")
    local lastTime = tonumber(readfile(TIMESTAMP_FILE)) or 0
    if os.time() - lastTime >= REFRESH_INTERVAL then
        return fetchServers()
    end

    local raw = readfile(SERVERS_FILE)
    local ok, tbl = pcall(HttpService.JSONDecode, HttpService, raw)
    if ok and type(tbl) == "table" and #tbl > 0 then
        return tbl
    end
    return fetchServers()
end

-- AutoHop
local function autoHop()
    print("→ autoHop()")
    local servers = getServerList()
    if #servers == 0 then
        warn("→ no servers found, retrying...")
        task.wait(5)
        return autoHop()
    end
    local choice = table.remove(servers, math.random(1, #servers))
    writefile(SERVERS_FILE, HttpService:JSONEncode(servers))
    print("→ hopping to", choice, "(remaining:", #servers, ")")
    safeTeleport(choice)
end

-- Watchdog
task.spawn(function()
    task.wait(WD_TIME)

    while true do
        if not ActiveRift or not loadingServers then
            autoHop()
            task.wait(5)
        end
        task.wait(1)
    end
end)

-- MAIN
print("["..LocalPlayer.Name.."] script started!")
repeat task.wait() until game:IsLoaded()
task.wait(5)

if not scanForRift() then
    autoHop()
end
