--!strict
-- CONFIG
local TARGET_RIFT      = "man-egg"
local MAX_PAGES        = 5
local MAX_PLAYERS      = 10
local REFRESH_INTERVAL = 20 * 60          -- 20 minutes

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

-- CACHE FILES (Synapse-style)
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
    local logData = {
        embeds = {{
            title       = TARGET_RIFT.." Rift Found! "..timeLeft.." Left!",
            description = "Rift detected in [Server](https://www.roblox.com/users/"..LocalPlayer.UserId.."/profile)",
            color       = 0xff4444
        }}
    }
    local encoded = HttpService:JSONEncode(logData)
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({
            Url     = WEBHOOK_URL,
            Method  = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body    = encoded
        })
    else
        warn("No HTTP request function available for webhook.")
    end
end

-- SCAN FOR RIFT
local function checkForRift(): boolean
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TARGET_RIFT and rift:FindFirstChild("EggPlatformSpawn") then
            local timerLbl = rift
                :FindFirstChild("Display")
                and rift.Display:FindFirstChild("SurfaceGui")
                and rift.Display.SurfaceGui:FindFirstChild("Timer")
            local timeLeft = (timerLbl and timerLbl.Text) or "???"
            print("[!] Rift Found!")
            sendRiftFoundWebhook(timeLeft)
            -- wait until Rift despawns
            repeat task.wait(1) until not rift:IsDescendantOf(workspace)
            print("Rift despawned, will re-hop...")
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
    local cursor = ""
    for page = 1, MAX_PAGES do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true%s",
            PLACE_ID,
            (cursor ~= "" and "&cursor="..cursor) or ""
        )
        local okReq, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url = url})
        end)
        if not okReq or not resp or not resp.Body then
            warn("Failed to fetch servers page", page, "; retrying...")
            task.wait(2)
            continue
        end

        local okBody, body = pcall(HttpService.JSONDecode, HttpService, resp.Body)
        if not okBody or type(body) ~= "table" then
            warn("Invalid JSON on page", page, "; skipping...")
        else
            for _, s in ipairs(body.data or {}) do
                if tonumber(s.playing) and tonumber(s.playing) <= MAX_PLAYERS then
                    table.insert(servers, s.id)
                end
            end
            cursor = body.nextPageCursor or ""
        end

        if cursor == "" then
            break
        else
            task.wait(1)  -- avoid rate limit
        end
    end

    -- write to disk
    pcall(writefile, SERVERS_FILE, HttpService:JSONEncode(servers))
    pcall(writefile, TIMESTAMP_FILE, tostring(os.time()))
    print("Server list cached ("..#servers.." entries)")
    return servers
end

-- GET FROM CACHE OR REFRESH
local function getServerList(): {string}
    -- safe read timestamp
    local lastTs = 0
    local okTs, tsStr = pcall(readfile, TIMESTAMP_FILE)
    if okTs then
        lastTs = tonumber(tsStr) or 0
    end

    if os.time() - lastTs >= REFRESH_INTERVAL then
        print("Server cache expired; fetching fresh list...")
        return fetchServerList()
    else
        local okFile, data = pcall(readfile, SERVERS_FILE)
        if okFile then
            local okDec, tbl = pcall(HttpService.JSONDecode, HttpService, data)
            if okDec and type(tbl) == "table" and #tbl > 0 then
                print("Loaded server list from cache; next refresh in",
                      math.floor((REFRESH_INTERVAL - (os.time() - lastTs)) / 60),
                      "minutes")
                return tbl
            end
        end
        warn("Cache invalid or read error; refetching...")
        return fetchServerList()
    end
end

-- AUTO-HOP
local function autoHop()
    print("No Rift found; preparing to hop...")
    local ok, list = pcall(getServerList)
    if not ok or type(list) ~= "table" then
        warn("getServerList failed; forcing fresh fetch")
        list = fetchServerList() or {}
    end

    if #list == 0 then
        warn("Server list empty; retrying in 5s...")
        task.wait(5)
        return autoHop()
    end

    local choice = list[math.random(1, #list)]
    safeTeleport(choice)
end

-- MAIN
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")
print("Started, actively searching for Rift:", TARGET_RIFT)
repeat task.wait() until game:IsLoaded()
task.wait(5)
if not checkForRift() then
    autoHop()
end
