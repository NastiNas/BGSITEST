--!strict

-- queue our loader so it runs on each hop
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")

-- CONFIG
local TARGET_RIFT      = "man-egg"
local MAX_PAGES        = 5
local MAX_PLAYERS      = 10
local REFRESH_INTERVAL = 20 * 60   -- 20 minutes

-- SERVICES
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportSvc = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
local RiftFolder  = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local PLACE_ID    = game.PlaceId

-- CACHE
local CACHE_DIR      = "riftHopCache"
local SERVERS_FILE   = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

-- make sure our cache exists
pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

-- 1) scan for the Rift
local function checkForRift(): boolean
    print("[DEBUG] → scanning for Rift…")
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TARGET_RIFT and rift:FindFirstChild("EggPlatformSpawn") then
            print("[DEBUG] → FOUND Rift!")
            return true
        end
    end
    print("[DEBUG] → no Rift here.")
    return false
end

-- 2) safe teleport
local function safeTeleport(serverId: string)
    print("[DEBUG] → teleporting to", serverId)
    local ok, err = pcall(function()
        TeleportSvc:TeleportToPlaceInstance(PLACE_ID, serverId)
    end)
    if not ok then
        warn("[DEBUG] → Teleport failed:", err)
        print("[DEBUG] → fallback to simple Teleport()")
        pcall(function() TeleportSvc:Teleport(PLACE_ID) end)
    else
        print("[DEBUG] → Teleport call succeeded.")
    end
end

-- 3) fetch fresh server list
local function fetchServerList(): {string}
    print("[DEBUG] → fetching server list…")
    local servers, cursor = {}, ""
    for page = 1, MAX_PAGES do
        print(("[DEBUG]   page %d, cursor=%s"):format(page, cursor))
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public"
            .. "?sortOrder=Asc&limit=100&excludeFullGames=true%s")
            :format(PLACE_ID, (cursor ~= "" and "&cursor="..cursor) or "")
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        if not ok or not resp or not resp.Body then
            warn("[DEBUG]   failed to fetch page", page)
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
    print(("[DEBUG] → fetched %d servers"):format(#servers))
    return servers
end

-- 4) load from cache or refetch
local function getServerList(): {string}
    print("[DEBUG] → loading server list (cache check)…")
    local lastTs = tonumber(readfile(TIMESTAMP_FILE)) or 0
    if os.time() - lastTs >= REFRESH_INTERVAL then
        print("[DEBUG] → cache expired")
        return fetchServerList()
    else
        local data = readfile(SERVERS_FILE)
        local ok, tbl = pcall(HttpService.JSONDecode, HttpService, data)
        if ok and type(tbl) == "table" and #tbl > 0 then
            print(("[DEBUG] → loaded %d servers from cache"):format(#tbl))
            return tbl
        else
            warn("[DEBUG] → cache invalid")
            return fetchServerList()
        end
    end
end

-- 5) pick a server & hop
local function autoHop()
    print("[DEBUG] → autoHop()")
    local list = getServerList()
    if #list == 0 then
        warn("[DEBUG] → no servers found, retrying in 5s")
        task.wait(5)
        return autoHop()
    end
    local choice = list[math.random(1,#list)]
    print("[DEBUG] → chosen server:", choice)
    safeTeleport(choice)
end

-- MAIN
print("[DEBUG] script started, target Rift:", TARGET_RIFT)
repeat task.wait() until game:IsLoaded()
task.wait(5)

if checkForRift() then
    print("[DEBUG] → Rift present at launch, stopping.")
else
    print("[DEBUG] → no Rift → autoHop()")
    autoHop()
end
