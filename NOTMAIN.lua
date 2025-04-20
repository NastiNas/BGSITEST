--!strict
-- ensure this runs again after each hop
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")

-- CONFIG
local TARGET_RIFT      = "man-egg"
local MAX_PAGES        = 5
local MAX_PLAYERS      = 10
local REFRESH_INTERVAL = 20 * 60   -- 20 minutes

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

-- CACHE FILES
local CACHE_DIR      = "riftHopCache"
local SERVERS_FILE   = CACHE_DIR.."/servers.json"
local TIMESTAMP_FILE = CACHE_DIR.."/timestamp.txt"

pcall(function()
    if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
    if not isfile(SERVERS_FILE) then writefile(SERVERS_FILE, "[]") end
    if not isfile(TIMESTAMP_FILE) then writefile(TIMESTAMP_FILE, "0") end
end)

-- send webhook
local function sendRiftFoundWebhook(timeLeft: string)
    local payload = HttpService:JSONEncode({
        embeds = {{
            title       = TARGET_RIFT.." Rift Found! "..timeLeft.." Left!",
            description = "Rift detected for user "..LocalPlayer.UserId,
            color       = 0xff4444
        }}
    })
    local req = (http and http.request) or request or (syn and syn.request)
    if req then
        req({
            Url     = WEBHOOK_URL,
            Method  = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body    = payload
        })
    else
        warn("No HTTP request function available for webhook.")
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
            print("[!] Rift Found!")
            sendRiftFoundWebhook(timeLeft)
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
    local servers, cursor = {}, ""
    for page = 1, MAX_PAGES do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true%s",
            PLACE_ID,
            (cursor ~= "" and "&cursor="..cursor) or ""
        )
        local ok, resp = pcall(function()
            return ((http and http.request) or request or (syn and syn.request))({Url=url})
        end)
        if not ok or not resp or not resp.Body then
            warn("Failed to fetch servers page", page, "; retrying...")
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
        print("Server cache expired; fetching fresh list...")
        return fetchServerList()
    else
        local ok, tbl = pcall(HttpService.JSONDecode, HttpService, readfile(SERVERS_FILE))
        if ok and type(tbl) == "table" and #tbl > 0 then
            print("Loaded server list from cache; next refresh in",
                  math.floor((REFRESH_INTERVAL - (os.time()-lastTs))/60), "minutes")
            return tbl
        else
            warn("Cache invalid or empty; refetching...")
            return fetchServerList()
        end
    end
end

-- AUTO-HOP
local function autoHop()
    print("No Rift found; preparing to hop...")
    local list = getServerList()
    if #list == 0 then
        warn("Server list empty; retrying in 5s...")
        task.wait(5)
        return autoHop()
    end
    safeTeleport(list[math.random(1,#list)])
end

-- HANDLE FULL / UNAUTHORIZED ERRORS
local function handleError(msg: string)
    if msg:find("teleportgamefull") then
        print("[DEBUG] Server is full, hopping again…")
        return true
    elseif msg:find("teleportunauthorized") then
        print("[DEBUG] Unauthorized server, hopping again…")
        return true
    end
    return false
end

-- LISTEN FOR CRASH ERRORS
LogService.MessageOut:Connect(function(message, level)
    if level == Enum.MessageOutputType.MessageError then
        if handleError(message:lower()) then
            task.wait(1)
            autoHop()
        end
    end
end)

-- MAIN
print("Started, actively searching for Rift:", TARGET_RIFT)
repeat task.wait() until game:IsLoaded()
task.wait(5)
if not checkForRift() then
    autoHop()
end
