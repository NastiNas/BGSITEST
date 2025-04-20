--!strict
print("DEBUG: Rift‑hop script initializing…")

-- CONFIG
local TARGET_RIFT      = "man-egg"
local MAX_PAGES        = 5
local MAX_PLAYERS      = 10
local REFRESH_INTERVAL = 20 * 60   -- 20m
local RATE_LIMIT_DELAY = 60        -- 1m when rate‑limited
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

-- CACHE
local CACHE_DIR      = "riftHopCache"
local SERVERS_FILE   = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

pcall(function()
    if not isfolder(CACHE_DIR) then 
        print("DEBUG: creating cache folder")
        makefolder(CACHE_DIR) 
    end
    if not isfile(SERVERS_FILE) then 
        print("DEBUG: creating servers.json")
        writefile(SERVERS_FILE, "[]") 
    end
    if not isfile(TIMESTAMP_FILE) then 
        print("DEBUG: creating timestamp.txt")
        writefile(TIMESTAMP_FILE, "0") 
    end
end)

-- send webhook
local function sendRiftFoundWebhook(timeLeft: string)
    print("DEBUG: sendRiftFoundWebhook", timeLeft)
    local payload = HttpService:JSONEncode({
        embeds = {{
            title       = TARGET_RIFT.." Rift Found! "..timeLeft.." Left!",
            description = "Rift detected for user "..LocalPlayer.UserId,
            color       = 0xff4444
        }}
    })
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({Url=WEBHOOK_URL, Method="POST",
             Headers={["Content-Type"]="application/json"},
             Body=payload})
        print("DEBUG: webhook sent")
    else
        warn("No HTTP request available for webhook.")
    end
end

-- scan for rift
local function checkForRift(): boolean
    print("DEBUG: checkForRift()")
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        print("DEBUG: scanning rift:", rift.Name)
        if rift.Name == TARGET_RIFT and rift:FindFirstChild("EggPlatformSpawn") then
            print("DEBUG: Rift matched target!")
            local timerLbl = rift:FindFirstChild("Display")
                           and rift.Display:FindFirstChild("SurfaceGui")
                           and rift.Display.SurfaceGui:FindFirstChild("Timer")
            local timeLeft = (timerLbl and timerLbl.Text) or "???"
            sendRiftFoundWebhook(timeLeft)
            repeat 
                task.wait(1) 
            until not rift:IsDescendantOf(workspace)
            print("DEBUG: Rift despawned, returning true")
            return true
        end
    end
    print("DEBUG: checkForRift() → false")
    return false
end

-- safe teleport
local function safeTeleport(serverId: string)
    print("DEBUG: safeTeleport to", serverId)
    local ok, err = pcall(function()
        TeleportSvc:TeleportToPlaceInstance(PLACE_ID, serverId)
    end)
    print("DEBUG: TeleportToPlaceInstance pcall ok=", ok)
    if not ok then
        warn("TeleportToPlaceInstance failed:", err, "; falling back.")
        pcall(function() TeleportSvc:Teleport(PLACE_ID) end)
    end
end

-- fetch server list
local function fetchServerList(): {string}
    print("DEBUG: fetchServerList()")
    local servers, cursor = {}, ""
    for page = 1, MAX_PAGES do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?"..
                     "sortOrder=Asc&limit=100&excludeFullGames=true%s")
                    :format(PLACE_ID,
                            cursor~="" and "&cursor="..cursor or "")
        print("DEBUG: requesting page", page, url)
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        print("DEBUG: http.request ok=", ok, "resp?", resp and resp.Body ~= nil)
        if not ok or not resp or not resp.Body then
            warn("Failed page", page, "; retrying…")
            task.wait(2)
            continue
        end
        local body = HttpService:JSONDecode(resp.Body)
        print("DEBUG: page", page, "#data=", #body.data)
        for _, s in ipairs(body.data or {}) do
            if tonumber(s.playing) <= MAX_PLAYERS then
                table.insert(servers, s.id)
            end
        end
        cursor = body.nextPageCursor or ""
        print("DEBUG: nextPageCursor →", cursor)
        if cursor == "" then break end
        task.wait(1)
    end
    writefile(SERVERS_FILE, HttpService:JSONEncode(servers))
    writefile(TIMESTAMP_FILE, tostring(os.time()))
    print("DEBUG: cached "..#servers.." servers")
    return servers
end

-- get from cache or fetch
local function getServerList(): {string}
    local now, lastTs = os.time(), tonumber(readfile(TIMESTAMP_FILE)) or 0
    print("DEBUG: getServerList: now=", now, "lastTs=", lastTs)
    if now - lastTs >= REFRESH_INTERVAL then
        print("DEBUG: cache expired → fetch")
        return fetchServerList()
    else
        print("DEBUG: cache valid for", REFRESH_INTERVAL - (now-lastTs), "s more")
        local data = readfile(SERVERS_FILE)
        local ok, tbl = pcall(HttpService.JSONDecode, HttpService, data)
        if ok and type(tbl)=="table" and #tbl>0 then
            print("DEBUG: loaded "..#tbl.." from cache")
            return tbl
        else
            warn("Cache invalid → refetch")
            return fetchServerList()
        end
    end
end

-- auto‑hop
local lastHop = 0
local rateLimited = false

local function autoHop()
    local now = os.time()
    local delay = rateLimited and RATE_LIMIT_DELAY or NORMAL_DELAY
    print(("DEBUG: autoHop() rateLimited=%s, lastHop=%d, now=%d, delay=%d")
          :format(tostring(rateLimited), lastHop, now, delay))
    if now - lastHop < delay then
        local waitTime = delay - (now - lastHop)
        print("DEBUG: waiting", waitTime, "s before hop")
        task.wait(waitTime)
    end
    print("DEBUG: performing hop")
    local list = getServerList()
    if #list == 0 then
        warn("No servers → retry in 5s")
        task.wait(5)
        return autoHop()
    end
    local choice = list[math.random(1,#list)]
    print("DEBUG: chosen server", choice)
    lastHop = os.time()
    safeTeleport(choice)
end

-- watchdog: catch errors
LogService.MessageOut:Connect(function(msg, typ)
    print("DEBUG: MessageOut:", typ.Name, msg)
    if typ == Enum.MessageType.MessageError then
        if msg:find("teleportgamefull",1,true)
        or msg:find("teleporunathorized",1,true) then
            warn("Detected teleport‑full/unauthorized error → re‑hop")
            rateLimited = true
            task.spawn(autoHop)
        end
    end
end)

-- MAIN
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")
print("DEBUG: queued on teleport; waiting for game to load…")
repeat task.wait() until game:IsLoaded()
print("DEBUG: game loaded; waiting 5s…")
task.wait(5)

print("DEBUG: initial Rift check")
if not checkForRift() then
    print("DEBUG: no Rift → first autoHop")
    autoHop()
end
