--!strict
-- CONFIG
local TARGET_RIFT      = "man-egg"
local MAX_PAGES        = 5
local MAX_PLAYERS      = 10
local REFRESH_INTERVAL = 20 * 60       -- 20m

-- RATE‑LIMIT (max MAX_HOPS teleports per WINDOW seconds)
local WINDOW       = 5 * 60            -- 5m
local MAX_HOPS     = 20
local HISTORY_FILE = "riftHopCache/teleport_history.json"

-- WEBHOOK
local WH_PART1     = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local WH_PART2     = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL  = "https://discord.com/api/webhooks/"..WH_PART1..WH_PART2

-- SERVICES
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportSvc = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local RiftFolder  = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local PLACE_ID    = game.PlaceId

-- CACHE & HISTORY FILES (Synapse-style)
local CACHE_DIR      = "riftHopCache"
local SERVERS_FILE   = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

-- ensure cache folder & files exist
pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE)   then writefile(SERVERS_FILE,  "[]") end
    if not isfile(TIMESTAMP_FILE)  then writefile(TIMESTAMP_FILE, "0") end
    if not isfile(HISTORY_FILE)    then writefile(HISTORY_FILE,   "[]") end
end)

-- UTIL: send webhook
local function sendRiftFoundWebhook(timeLeft: string)
    local payload = HttpService:JSONEncode({
        embeds = {{ title = TARGET_RIFT.." Rift Found! "..timeLeft.." Left!",
                    description = "Rift detected in [Server](https://www.roblox.com/users/"..LocalPlayer.UserId.."/profile)",
                    color = 0xff4444 }}
    })
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({ Url=WEBHOOK_URL, Method="POST",
              Headers={["Content-Type"]="application/json"},
              Body=payload })
    else
        warn("No HTTP request function available for webhook.")
    end
end

-- SCAN FOR RIFT
local function checkForRift(): boolean
    for _, r in ipairs(RiftFolder:GetChildren()) do
        if r.Name==TARGET_RIFT and r:FindFirstChild("EggPlatformSpawn") then
            local lbl = r:FindFirstChild("Display")
                     and r.Display:FindFirstChild("SurfaceGui")
                     and r.Display.SurfaceGui:FindFirstChild("Timer")
            local timeLeft = (lbl and lbl.Text) or "???"
            print("[!] Rift Found!")
            sendRiftFoundWebhook(timeLeft)
            repeat task.wait(1) until not r:IsDescendantOf(workspace)
            print("Rift despawned, will re-hop…")
            return true
        end
    end
    return false
end

-- SAFE TELEPORT
local function safeTeleport(id: string)
    local ok, err = pcall(function()
        TeleportSvc:TeleportToPlaceInstance(PLACE_ID, id)
    end)
    print("Teleport attempt to", id)
    if not ok then
        warn("TeleportToPlaceInstance failed:", err, "; falling back to Teleport()")
        pcall(function() TeleportSvc:Teleport(PLACE_ID) end)
    end
end

-- FETCH & CACHE SERVERS
local function fetchServerList(): {string}
    local out, cursor = {}, ""
    for page=1, MAX_PAGES do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?"
            .."sortOrder=Asc&limit=100&excludeFullGames=true%s")
            :format(PLACE_ID, (cursor~="" and "&cursor="..cursor) or "")
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        if not(ok and resp and resp.Body) then
            warn("Failed to fetch page", page, "; retrying…")
            task.wait(2)
            continue
        end
        local body = HttpService:JSONDecode(resp.Body)
        for _, s in ipairs(body.data or {}) do
            if tonumber(s.playing) <= MAX_PLAYERS then
                table.insert(out, s.id)
            end
        end
        cursor = body.nextPageCursor or ""
        if cursor=="" then break end
        task.wait(1)
    end
    writefile(SERVERS_FILE,   HttpService:JSONEncode(out))
    writefile(TIMESTAMP_FILE, tostring(os.time()))
    print("Server list cached ("..#out.." entries)")
    return out
end

-- CACHE / REFRESH
local function getServerList(): {string}
    local last = tonumber(readfile(TIMESTAMP_FILE)) or 0
    if os.time() - last >= REFRESH_INTERVAL then
        print("Cache expired; fetching fresh list…")
        return fetchServerList()
    else
        local ok, tbl = pcall(HttpService.JSONDecode, HttpService, readfile(SERVERS_FILE))
        if ok and type(tbl)=="table" and #tbl>0 then
            print("Loaded server list; next refresh in",
                  math.floor((REFRESH_INTERVAL - (os.time()-last))/60), "m")
            return tbl
        else
            warn("Cache invalid; refetching…")
            return fetchServerList()
        end
    end
end

-- TELEPORT RATE‑LIMITER (returns waitSeconds)
local function throttleIfNeeded(): number
    local now = os.time()
    local hist = {}
    local ok, old = pcall(HttpService.JSONDecode, HttpService, readfile(HISTORY_FILE))
    if ok and type(old)=="table" then hist = old end

    -- purge old
    for i=#hist,1,-1 do
        if now - hist[i] >= WINDOW then
            table.remove(hist, i)
        end
    end

    if #hist >= MAX_HOPS then
        table.sort(hist)
        local waitSec = WINDOW - (now - hist[1])
        print(("Rate‑limit hit (%d hops/%.0f s); waiting %d s…")
              :format(#hist, WINDOW, waitSec))
        task.wait(waitSec)
        now = os.time()
        for i=#hist,1,-1 do
            if now - hist[i] >= WINDOW then
                table.remove(hist, i)
            end
        end
        table.insert(hist, now)
        writefile(HISTORY_FILE, HttpService:JSONEncode(hist))
        return waitSec
    else
        table.insert(hist, now)
        writefile(HISTORY_FILE, HttpService:JSONEncode(hist))
        return 0
    end
end

-- AUTO‑HOP WITH DYNAMIC WATCHDOG
local function autoHop()
    print("No Rift found; preparing to hop…")
    local list = getServerList()
    if #list == 0 then
        warn("Server list empty; retrying in 5s…")
        task.wait(5)
        return autoHop()
    end

    local waited = throttleIfNeeded()
    local didHop = false

    -- choose watchdog timeout based on rate‑limit
    local timeout = (waited == 0) and 30 or 60
    task.spawn(function()
        task.wait(timeout)
        if not didHop then
            warn(("Watchdog: teleport didn’t start in %ds, retrying autoHop"):format(timeout))
            autoHop()
        end
    end)

    local choice = list[ math.random(1, #list) ]
    didHop = true
    safeTeleport(choice)
end

-- MAIN
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")
print("Started, searching for Rift:", TARGET_RIFT)
repeat task.wait() until game:IsLoaded()
task.wait(5)
if not checkForRift() then
    autoHop()
end
