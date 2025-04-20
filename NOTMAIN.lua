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

-- waitForChild with timeout helper
local function safeWait(parent, name, timeout)
    local obj = parent:FindFirstChild(name)
    if obj then return obj end
    return parent:WaitForChild(name, timeout or 5)
end

-- RIFT FOLDER (with timeout)
local RiftFolder = safeWait(workspace, "Rendered", 10)
if RiftFolder then
    RiftFolder = safeWait(RiftFolder, "Rifts", 10)
end
if not RiftFolder then
    error("Could not locate workspace.Rendered.Rifts")
end

-- CACHE FILES
local CACHE_DIR      = "riftHopCache"
local SERVERS_FILE   = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

-- ensure cache folder & files exist
pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

-- UTIL: send webhook
local function sendRiftFoundWebhook(timeLeft: string)
    local payload = HttpService:JSONEncode({
        embeds = {{
            title       = TARGET_RIFT.." Rift Found! "..timeLeft.." Left!",
            description = "Rift detected for "..LocalPlayer.Name,
            color       = 0xff4444
        }}
    })
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({Url=WEBHOOK_URL, Method="POST",
             Headers={["Content-Type"]="application/json"},
             Body=payload})
    else
        warn("No HTTP request available for webhook")
    end
end

-- SCAN FOR RIFT
local function checkForRift(): boolean
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TARGET_RIFT and rift:FindFirstChild("EggPlatformSpawn") then
            local disp = rift:FindFirstChild("Display")
            local timerLbl
            if disp then
                local sg = disp:FindFirstChild("SurfaceGui")
                if sg then
                    timerLbl = sg:FindFirstChild("Timer")
                end
            end
            local timeLeft = (timerLbl and timerLbl.Text) or "???"
            print("[!] Rift Found!")
            sendRiftFoundWebhook(timeLeft)
            -- wait until Rift despawns
            repeat task.wait(1) until not rift:IsDescendantOf(workspace)
            print("Rift despawned, will re‑hop…")
            return true
        end
    end
    return false
end

-- SAFE TELEPORT (with 1s throttle)
local lastTeleport = 0
local function safeTeleport(serverId: string)
    if os.clock() - lastTeleport < 1 then
        task.wait(1)
    end
    lastTeleport = os.clock()
    local ok, err = pcall(function()
        TeleportSvc:TeleportToPlaceInstance(PLACE_ID, serverId)
    end)
    print("Teleport→", serverId)
    if not ok then
        warn("TeleportToPlaceInstance failed:", err, "; falling back")
        pcall(function() TeleportSvc:Teleport(PLACE_ID) end)
    end
end

-- FETCH & CACHE
local function fetchServerList(): {string}
    local servers, cursor = {}, ""
    for page = 1, MAX_PAGES do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?"
                  .."sortOrder=Asc&limit=100&excludeFullGames=true%s")
                  :format(PLACE_ID, cursor=="" and "" or "&cursor="..cursor)
        local okReq, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        if not okReq or not (resp and resp.Body) then
            warn("Page "..page.." fetch failed; retrying…")
            task.wait(2)
            continue
        end

        local okJson, body = pcall(HttpService.JSONDecode, HttpService, resp.Body)
        if okJson and type(body)=="table" and type(body.data)=="table" then
            for _, s in ipairs(body.data) do
                local playing = tonumber(s.playing)
                if playing and playing <= MAX_PLAYERS then
                    table.insert(servers, s.id)
                end
            end
            cursor = body.nextPageCursor or ""
        else
            warn("Bad JSON on page "..page.."; skipping")
        end

        if cursor=="" then break end
        task.wait(1)
    end

    pcall(writefile, SERVERS_FILE, HttpService:JSONEncode(servers))
    pcall(writefile, TIMESTAMP_FILE, tostring(os.time()))
    print("Cached "..#servers.." servers")
    return servers
end

-- GET FROM CACHE OR REFRESH
local function getServerList(): {string}
    local lastTs = 0
    local okTs, tsStr = pcall(readfile, TIMESTAMP_FILE)
    if okTs then lastTs = tonumber(tsStr) or 0 end

    if os.time() - lastTs >= REFRESH_INTERVAL then
        print("Cache expired; fetching fresh…")
        return fetchServerList()
    else
        local okFile, data = pcall(readfile, SERVERS_FILE)
        if okFile then
            local okDec, tbl = pcall(HttpService.JSONDecode, HttpService, data)
            if okDec and type(tbl)=="table" and #tbl>0 then
                print("Loaded "..#tbl.." servers from cache; refresh in "
                      ..math.floor((REFRESH_INTERVAL-(os.time()-lastTs))/60)
                      .."m")
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
    local ok, list = pcall(getServerList)
    if not ok or type(list)~="table" or #list==0 then
        warn("getServerList failed; retrying fetch")
        list = fetchServerList()
    end
    if #list==0 then
        warn("Still empty; wait 5s")
        task.wait(5)
        return autoHop()
    end
    safeTeleport(list[math.random(#list)])
end

-- MAIN
pcall(function()
    queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")
    print("Started, searching for Rift:", TARGET_RIFT)
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    task.wait(5)
    if not checkForRift() then
        autoHop()
    end
end)
