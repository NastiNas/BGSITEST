--!strict
-- reload after each hop
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

-- CACHE FILES
local CACHE_DIR      = "riftHopCache"
local SERVERS_FILE   = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

-- 1) scan for rift
local function checkForRift(): boolean
    print("[DEBUG] checkForRift: scanning RiftFolder...")
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TARGET_RIFT and rift:FindFirstChild("EggPlatformSpawn") then
            print("[DEBUG] checkForRift: found target rift!")
            return true
        end
    end
    print("[DEBUG] checkForRift: no rift found")
    return false
end

-- 2) safe teleport wrapper
local function safeTeleport(serverId: string)
    print("[DEBUG] safeTeleport: attempting teleport to", serverId)
    local ok, err = pcall(function()
        TeleportSvc:TeleportToPlaceInstance(PLACE_ID, serverId)
    end)
    if ok then
        print("[DEBUG] safeTeleport: TeleportToPlaceInstance pcall returned OK")
    else
        warn("[DEBUG] safeTeleport: error:", err)
        print("[DEBUG] safeTeleport: falling back to Teleport()")
        pcall(function() TeleportSvc:Teleport(PLACE_ID) end)
    end
end

-- 3) fetch server list from Roblox
local function fetchServerList(): {string}
    print("[DEBUG] fetchServerList: start")
    local servers, cursor = {}, ""
    for page = 1, MAX_PAGES do
        print("[DEBUG] fetchServerList: fetching page", page, "cursor=", cursor)
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true%s",
            PLACE_ID,
            (cursor ~= "" and "&cursor="..cursor) or ""
        )
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        if not ok or not resp or not resp.Body then
            warn("[DEBUG] fetchServerList: failed to fetch page", page)
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
    print("[DEBUG] fetchServerList: done, got", #servers, "servers")
    return servers
end

-- 4) choose between cache or refetch
local function getServerList(): {string}
    print("[DEBUG] getServerList: checking timestamp")
    local lastTs = tonumber(readfile(TIMESTAMP_FILE)) or 0
    if os.time() - lastTs >= REFRESH_INTERVAL then
        print("[DEBUG] getServerList: cache expired; refetching")
        return fetchServerList()
    else
        local data = readfile(SERVERS_FILE)
        local ok, tbl = pcall(HttpService.JSONDecode, HttpService, data)
        if ok and type(tbl) == "table" and #tbl > 0 then
            print("[DEBUG] getServerList: loaded", #tbl, "from cache")
            return tbl
        else
            warn("[DEBUG] getServerList: cache invalid; refetching")
            return fetchServerList()
        end
    end
end

-- 5) pick one and teleport
local function autoHop()
    print("[DEBUG] autoHop: starting")
    local list = getServerList()
    if #list == 0 then
        warn("[DEBUG] autoHop: empty list; retrying in 5s")
        task.wait(5)
        return autoHop()
    end
    local choice = list[math.random(1, #list)]
    print("[DEBUG] autoHop: chosen server", choice)
    safeTeleport(choice)
end

-- MAIN
print("[DEBUG] Script started, looking for Rift:", TARGET_RIFT)
repeat task.wait() until game:IsLoaded()
task.wait(5)

if checkForRift() then
    print("[DEBUG] main: Rift was present on load; stopping.")
else
    print("[DEBUG] main: no Rift on load; calling autoHop()")
    autoHop()
end
