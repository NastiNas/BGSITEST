--!strict
-- CONFIG
local TARGET_RIFT      = "man-egg"
local MAX_PAGES        = 5
local MAX_PLAYERS      = 10
local REFRESH_INTERVAL = 20 * 60   -- 20 minutes
local RATE_LIMIT_DELAY = 60        -- 1 minute when rate limited
local NORMAL_DELAY     = 30        -- 30s otherwise

-- WEBHOOK
local WH_PART1      = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local WH_PART2      = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL   = "https://discord.com/api/webhooks/"..WH_PART1..WH_PART2

-- SERVICES
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportSvc = game:GetService("TeleportService")
local LogService  = game:GetService("LogService")

local LocalPlayer = Players.LocalPlayer
local RiftFolder  = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local PLACE_ID    = game.PlaceId

-- CACHE FILES (Synapse-style API)
local CACHE_DIR      = "riftHopCache"
local SERVERS_FILE   = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

-- ensure cache folder & files exist
pcall(function()
    if not isfolder(CACHE_DIR) then
        makefolder(CACHE_DIR)
    end
    if not isfile(SERVERS_FILE) then
        writefile(SERVERS_FILE, "[]")
    end
    if not isfile(TIMESTAMP_FILE) then
        writefile(TIMESTAMP_FILE, "0")
    end
end)

-- UTIL: send webhook
local function sendRiftFoundWebhook(timeLeft: string)
    local payload = HttpService:JSONEncode({
        embeds = {{
            title       = TARGET_RIFT.." Rift Found! "..timeLeft.." Left!",
            description = "Rift detected in [Server](https://www.roblox.com/users/"..LocalPlayer.UserId.."/profile)",
            color       = 0xff4444
        }}
    })
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({ Url = WEBHOOK_URL,
              Method = "POST",
              Headers = {["Content-Type"]="application/json"},
              Body = payload })
    else
        warn("No HTTP request available for webhook.")
    end
end

-- SCAN FOR RIFT
local function checkForRift(): boolean
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TARGET_RIFT and rift:FindFirstChild("EggPlatformSpawn") then
            local timerLbl = rift:FindFirstChild("Display")
                              and rift.Display:FindFirstChild("SurfaceGui")
                              and rift.Display.SurfaceGui:FindFirstChild("Timer")
            local timeLeft = (timerLbl and timerLbl.Text) or "???"
            print("[!] Rift Found! sending webhook…")
            sendRiftFoundWebhook(timeLeft)
            -- wait until Rift despawns
            repeat task.wait(1) until not rift:IsDescendantOf(workspace)
            print("Rift despawned, re-hopping soon…")
            return true
        end
    end
    return false
end

-- SAFE TELEPORT
local function safeTeleport(serverId: string)
    local ok, err = pcall(function()
        TeleportSvc:TeleportToPlaceInstance(PLACE_ID, serverId)
    end)
    print("Teleport attempt to", serverId)
    if not ok then
        warn("TeleportToPlaceInstance failed:", err, "; falling back to Teleport()")
        pcall(function() TeleportSvc:Teleport(PLACE_ID) end)
    end
end

-- FETCH & CACHE SERVERS
local function fetchServerList(): {string}
    local servers = {}
    local cursor  = ""
    for page = 1, MAX_PAGES do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true%s")
                    :format(PLACE_ID, (cursor~="" and "&cursor="..cursor or ""))
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        if not ok or not resp or not resp.Body then
            warn("Failed to fetch servers page", page, "; retrying…")
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
    print("Server list cached ("..#servers.." entries)")
    return servers
end

-- GET FROM CACHE OR REFRESH
local function getServerList(): {string}
    local lastTs = tonumber(readfile(TIMESTAMP_FILE)) or 0
    if os.time() - lastTs >= REFRESH_INTERVAL then
        print("Cache expired; fetching fresh list…")
        return fetchServerList()
    else
        local data = readfile(SERVERS_FILE)
        local ok, tbl = pcall(HttpService.JSONDecode, HttpService, data)
        if ok and type(tbl)=="table" and #tbl>0 then
            local mins = math.floor((REFRESH_INTERVAL - (os.time()-lastTs))/60)
            print("Loaded cache; next refresh in", mins, "minutes")
            return tbl
        else
            warn("Cache invalid; refetching…")
            return fetchServerList()
        end
    end
end

-- AUTO-HOP
local lastHop = 0
local rateLimited = false

function autoHop()
    local now = os.time()
    -- if rate-limited, ensure at least RATE_LIMIT_DELAY since last hop
    local delay = rateLimited and RATE_LIMIT_DELAY or NORMAL_DELAY
    if now - lastHop < delay then
        task.wait(delay - (now - lastHop))
    end

    print("No Rift found; auto-hopping…")
    local list = getServerList()
    if #list == 0 then
        warn("Empty list; retry in 5s…")
        task.wait(5)
        return autoHop()
    end
    local choice = list[math.random(1,#list)]
    lastHop = os.time()
    safeTeleport(choice)
end

-- WATCHDOG: detect “server full” teleport failures
LogService.MessageOut:Connect(function(message, messageType)
    if messageType == Enum.MessageType.MessageError then
        if message:find("ingame%.connectionerror%.teleportgamefull") then
            warn("Detected full-server error; re-hopping…")
            rateLimited = true
            task.wait(1)
            autoHop()
        end
    end
end)

-- MAIN
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")
print("Started, searching for Rift:", TARGET_RIFT)
repeat task.wait() until game:IsLoaded()
task.wait(5)

if not checkForRift() then
    autoHop()
end
