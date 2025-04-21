--!strict

-- queue our loader so it runs on each hop
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")

-- CONFIG
local TARGET_RIFT      = "event-2"
local MAX_PAGES        = 5
local MAX_PLAYERS      = 10
local REFRESH_INTERVAL = 10 * 60   -- 10 minutes
local WATCHDOG_TIME    = 40         -- seconds

-- WEBHOOK
local WH_PART1    = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local WH_PART2    = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/"..WH_PART1..WH_PART2

-- SERVICES
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportSvc = game:GetService("TeleportService")

-- wait for LocalPlayer
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local RiftFolder  = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local PLACE_ID    = game.PlaceId

-- CACHE
local CACHE_DIR      = "riftHopCache"
local SERVERS_FILE   = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

-- state
local loadingServers = false

-- ensure cache folder & files exist
pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

-- lightweight check if a Rift is in the world right now
local function isRiftPresent(): boolean
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TARGET_RIFT and rift:FindFirstChild("EggPlatformSpawn") then
            return true
        end
    end
    return false
end

-- UTIL: display an on‐screen alert
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
    frame.BackgroundColor3 = Color3.new(0,0,0)
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
        lbl.TextColor3 = Color3.new(1,1,1)
        lbl.TextScaled = true
        lbl.Parent = frame
    end

    makeLabel("Rift: "..TARGET_RIFT)
    makeLabel("Player: "..LocalPlayer.Name)
    makeLabel(("Y Pivot: %.2f"):format(yValue))
    makeLabel("Time Left: "..timeLeft)
    makeLabel("Luck: "..luckValue)
end

-- UTIL: send Discord webhook
local function sendRiftFoundWebhook(timeLeft: string)
    local payload = {
        embeds = { {
            title       = TARGET_RIFT.." Rift Found! "..timeLeft.." left!",
            description = "Rift detected by **"..LocalPlayer.Name.."**",
            color       = 0xFF4444
        } }
    }
    local body = HttpService:JSONEncode(payload)
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({
            Url     = WEBHOOK_URL,
            Method  = "POST",
            Headers = {["Content-Type"]="application/json"},
            Body    = body
        })
    else
        warn("["..LocalPlayer.Name.."] no HTTP function for webhook")
    end
end

-- 1) SCAN FOR RIFT
local function checkForRift(): boolean
    print("["..LocalPlayer.Name.."] → scanning for Rift…")
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TARGET_RIFT and rift:FindFirstChild("EggPlatformSpawn") then
            local timerLbl = rift:FindFirstChild("Display")
                             and rift.Display:FindFirstChild("SurfaceGui")
                             and rift.Display.SurfaceGui:FindFirstChild("Timer")
            local timeLeft = (timerLbl and timerLbl.Text) or "???"

            print("["..LocalPlayer.Name.."] → FOUND Rift!")
            showRiftGui(rift, timeLeft)
            sendRiftFoundWebhook(timeLeft)
            return true
        end
    end
    print("["..LocalPlayer.Name.."] → no Rift here.")
    return false
end

-- 2) SAFE TELEPORT
local function safeTeleport(serverId: string)
    print("["..LocalPlayer.Name.."] → teleporting to", serverId)
    local ok, err = pcall(function()
        TeleportSvc:TeleportToPlaceInstance(PLACE_ID, serverId)
    end)
    if not ok then
        warn("["..LocalPlayer.Name.."] → Teleport failed:", err)
        print("["..LocalPlayer.Name.."] → fallback to Teleport()")
        pcall(function() TeleportSvc:Teleport(PLACE_ID) end)
    else
        print("["..LocalPlayer.Name.."] → Teleport call succeeded.")
    end
end

-- 3) FETCH FRESH SERVER LIST
local function fetchServerList(): {string}
    loadingServers = true
    print("["..LocalPlayer.Name.."] → fetching server list…")
    local servers, cursor = {}, ""
    for page = 1, MAX_PAGES do
        print(("["..LocalPlayer.Name.."] [DEBUG] page %d, cursor=%s"):format(page, cursor))
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public"
            .. "?sortOrder=Asc&limit=100&excludeFullGames=true%s")
            :format(PLACE_ID, (cursor~="" and "&cursor="..cursor) or "")
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        if not ok or not resp or not resp.Body then
            warn("["..LocalPlayer.Name.."] failed to fetch page", page)
            task.wait(2)
            continue
        end
        local body = HttpService:JSONDecode(resp.Body)
        for _, s in ipairs(body.data or {}) do
            if tonumber(s.playing) <= MAX_PLAYERS then
                table.insert(servers, s.id)
            end
        end
        cursor = body.nextPageCursor or ""
        if cursor == "" then break end
        task.wait(1)
    end
    writefile(SERVERS_FILE, HttpService:JSONEncode(servers))
    writefile(TIMESTAMP_FILE, tostring(os.time()))
    loadingServers = false
    print(("["..LocalPlayer.Name.."] → fetched %d servers"):format(#servers))
    return servers
end

-- 4) LOAD FROM CACHE OR REFETCH
local function getServerList(): {string}
    print("["..LocalPlayer.Name.."] [DEBUG] loading server list (cache check)…")
    local lastTs = tonumber(readfile(TIMESTAMP_FILE)) or 0
    if os.time() - lastTs >= REFRESH_INTERVAL then
        print("["..LocalPlayer.Name.."] → cache expired")
        return fetchServerList()
    else
        local data = readfile(SERVERS_FILE)
        local ok, tbl = pcall(HttpService.JSONDecode, HttpService, data)
        if ok and type(tbl)=="table" and #tbl>0 then
            print(("["..LocalPlayer.Name.."] → loaded %d servers from cache"):format(#tbl))
            return tbl
        else
            warn("["..LocalPlayer.Name.."] → cache invalid")
            return fetchServerList()
        end
    end
end

-- 5) PICK + REMOVE + HOP
local function autoHop()
    print("["..LocalPlayer.Name.."] → autoHop()")
    local list = getServerList()
    if #list == 0 then
        warn("["..LocalPlayer.Name.."] → no servers found, retrying in 5s")
        task.wait(5)
        return autoHop()
    end
    local choice = list[math.random(1,#list)]
    print("["..LocalPlayer.Name.."] → chosen server:", choice)

    local remaining = {}
    for _, sid in ipairs(list) do
        if sid ~= choice then table.insert(remaining, sid) end
    end
    writefile(SERVERS_FILE, HttpService:JSONEncode(remaining))
    print("["..LocalPlayer.Name.."] → removed", choice, "from cache; remaining:", #remaining)

    safeTeleport(choice)
end

-- WATCHDOG: if neither Rift nor server‐fetching for WATCHDOG_TIME, force a hop
spawn(function()
    task.wait(WATCHDOG_TIME)
    if not isRiftPresent() and not loadingServers then
        print("["..LocalPlayer.Name.."] → Watchdog triggered: no Rift & idle → autoHop()")
        autoHop()
    end
end)

-- MAIN
print("["..LocalPlayer.Name.."] script started, target Rift:", TARGET_RIFT)
repeat task.wait() until game:IsLoaded()
task.wait(5)

if checkForRift() then
    print("["..LocalPlayer.Name.."] → Rift present at launch, stopping.")
else
    print("["..LocalPlayer.Name.."] → no Rift → autoHop()")
    autoHop()
end
