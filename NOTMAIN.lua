--!strict
-- CONFIG
local TARGET_RIFT      = "man-egg"
local MAX_PAGES        = 5
local MAX_PLAYERS      = 10
local REFRESH_INTERVAL = 20 * 60      -- 20 minutes

-- WEBHOOK
local WH_PART1     = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local WH_PART2     = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL  = "https://discord.com/api/webhooks/"..WH_PART1..WH_PART2

-- SERVICES
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportSvc = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local PLACE_ID    = game.PlaceId

-- waitForChild with timeout
local function safeWait(parent, name, timeout)
    local found = parent:FindFirstChild(name)
    if found then return found end
    return parent:WaitForChild(name, timeout or 5)
end

-- RIFT FOLDER
local RiftFolder = safeWait(workspace, "Rendered", 10)
RiftFolder = RiftFolder and safeWait(RiftFolder, "Rifts", 10)
if not RiftFolder then error("Couldn't find workspace.Rendered.Rifts") end

-- CACHE
local CACHE_DIR      = "riftHopCache"
local SERVERS_FILE   = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"
pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

-- WEBHOOK SENDER
local function sendRiftFoundWebhook(timeLeft: string)
    local payload = HttpService:JSONEncode({ embeds = {{
        title       = TARGET_RIFT.." Rift Found! "..timeLeft.." Left!",
        description = "Detected by "..LocalPlayer.Name,
        color       = 0xFF4444,
    }}})
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({ Url=WEBHOOK_URL, Method="POST",
              Headers={["Content-Type"]="application/json"},
              Body=payload })
    else
        warn("No HTTP function for webhook")
    end
end

-- RIFT CHECK
local function checkForRift(): boolean
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TARGET_RIFT and rift:FindFirstChild("EggPlatformSpawn") then
            local lbl = rift:FindFirstChild("Display")
                      and rift.Display:FindFirstChild("SurfaceGui")
                      and rift.Display.SurfaceGui:FindFirstChild("Timer")
            local timeLeft = (lbl and lbl.Text) or "???"
            print("[!] Rift Found!")
            sendRiftFoundWebhook(timeLeft)
            repeat task.wait(1) until not rift:IsDescendantOf(workspace)
            print("Rift despawned; hopping…")
            return true
        end
    end
    return false
end

-- SAFE TELEPORT (1s throttle)
local lastTP = 0
local function safeTeleport(serverId: string)
    if os.clock() - lastTP < 1 then task.wait(1) end
    lastTP = os.clock()
    local ok, err = pcall(function()
        TeleportSvc:TeleportToPlaceInstance(PLACE_ID, serverId)
    end)
    print("Teleport→", serverId)
    if not ok then
        warn("TeleportToPlaceInstance failed:", err)
        pcall(function() TeleportSvc:Teleport(PLACE_ID) end)
    end
end

-- FETCH SERVERS (never include full ones)
local function fetchServerList(): {string}
    local out, cursor = {}, ""
    for page = 1, MAX_PAGES do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?"
                   .."sortOrder=Asc&limit=100&excludeFullGames=true%s")
                   :format(PLACE_ID, cursor=="" and "" or "&cursor="..cursor)
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        if not ok or not (resp and resp.Body) then
            warn("Page "..page.." fetch failed; retrying…")
            task.wait(2)
            continue
        end
        local okJ, body = pcall(HttpService.JSONDecode, HttpService, resp.Body)
        if okJ and type(body)=="table" and type(body.data)=="table" then
            for _, s in ipairs(body.data) do
                local playing   = tonumber(s.playing)
                local maxPlayer = tonumber(s.maxPlayers)
                if playing and maxPlayer and
                   playing < maxPlayer and          -- never full
                   playing <= MAX_PLAYERS then      -- within your MAX_PLAYERS
                    table.insert(out, s.id)
                end
            end
            cursor = body.nextPageCursor or ""
        else
            warn("Bad JSON on page "..page.."; skipping")
        end
        if cursor=="" then break end
        task.wait(1)
    end
    pcall(writefile, SERVERS_FILE,   HttpService:JSONEncode(out))
    pcall(writefile, TIMESTAMP_FILE, tostring(os.time()))
    print("Cached "..#out.." servers")
    return out
end

-- GET OR REFRESH CACHE
local function getServerList(): {string}
    local lastTs = tonumber((pcall(readfile, TIMESTAMP_FILE) and readfile(TIMESTAMP_FILE)) or "0") or 0
    if os.time() - lastTs >= REFRESH_INTERVAL then
        print("Cache expired; fetching…")
        return fetchServerList()
    else
        local ok, data = pcall(readfile, SERVERS_FILE)
        if ok then
            local okD, tbl = pcall(HttpService.JSONDecode, HttpService, data)
            if okD and type(tbl)=="table" and #tbl>0 then
                local mins = math.floor((REFRESH_INTERVAL - (os.time()-lastTs))/60)
                print("Loaded "..#tbl.." servers; refresh in "..mins.."m")
                return tbl
            end
        end
        warn("Cache invalid; refetching…")
        return fetchServerList()
    end
end

-- AUTO‑HOP
local function autoHop()
    print("No Rift; hopping…")
    local list = getServerList()
    if #list == 0 then
        warn("Empty list; retrying in 5s…")
        task.wait(5)
        return autoHop()
    end
    safeTeleport(list[math.random(#list)])
end

-- MAIN
pcall(function()
    queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")
    print("Started; looking for Rift:", TARGET_RIFT)
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(5)
    if not checkForRift() then autoHop() end
end)
