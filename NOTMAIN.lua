----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local TargetRift       = "man-egg"
local SERVER_LIST_FILE = "riftServerList.json"
local SERVER_LIST_TTL  = 20 * 60        -- 20 minutes (seconds)
local MAX_PAGES        = 5
local MAX_PLAYERS      = 10

-- Discord webhook IDs
local whh1 = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local whh2 = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/"..whh1..whh2 

----------------------------------------------------------------
-- SERVICES & UTIL
----------------------------------------------------------------
local Players         = game:GetService("Players")
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer     = Players.LocalPlayer
local RiftFolder      = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local placeId         = game.PlaceId
local jobId           = game.JobId

-- executor HTTP & file‑IO
local http_request = http and http.request
                  or request
                  or (syn and syn.request)
local write_file   = writefile or writeFile or (syn and syn.write_file)
local read_file    = readfile  or readFile  or (syn and syn.read_file)
local is_file      = isfile    or isFile    or (syn and syn.is_file)

math.randomseed(tick())


queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")

----------------------------------------------------------------
-- WEBHOOK
----------------------------------------------------------------
local function sendRiftFoundWebhook(timeLeft)
    local logData = {
        ["embeds"] = {{
            ["title"]       = ""..TargetRift.." Rift Found! " .. timeLeft .. " Left!",
            ["description"] = "Rift detected in [Server](https://www.roblox.com/users/".. LocalPlayer.UserId .."/profile)",
            ["color"]       = tonumber(0xff4444)
        }}
    }
    local encoded = HttpService:JSONEncode(logData)
    local http_req = http and http.request or request or (syn and syn.request)
    if http_req then
        http_req({
            Url     = WEBHOOK_URL,
            Method  = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body    = encoded
        })
    else
        warn("No HTTP request function available for webhook.")
    end
end

----------------------------------------------------------------
-- RIFT CHECK
----------------------------------------------------------------
local function checkForRift()
    print("Scanning for Rift: ", TargetRift)
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TargetRift and rift:FindFirstChild("EggPlatformSpawn") then
            local timerGui = rift:FindFirstChild("Display")
                             and rift.Display:FindFirstChild("SurfaceGui")
                             and rift.Display.SurfaceGui:FindFirstChild("Timer")
            local timeLeft = (timerGui and timerGui.Text) or "???"
            print("Rift found! Time left: ", timeLeft)
            sendRiftFoundWebhook(timeLeft)

            -- wait for it to despawn before hopping again
            repeat task.wait(1) until not rift:IsDescendantOf(workspace)
            print("Rift despawned; re-hopping...")
            return true
        end
    end
    print("No Rift found this scan.")
    return false
end

----------------------------------------------------------------
-- SERVER LIST COLLECTION
----------------------------------------------------------------
local function collectServers()
    print("Collecting server list...")
    local collected = {}
    local pagesChecked, cursor = 0, ""

    while pagesChecked < MAX_PAGES do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true%s",
            placeId,
            cursor ~= "" and "&cursor="..cursor or ""
        )

        local ok, res = pcall(function()
            return http_request({Url = url})
        end)

        if ok and res and res.Body then
            local body = HttpService:JSONDecode(res.Body)
            if type(body.data)=="table" and #body.data > 0 then
                for _, srv in ipairs(body.data) do
                    if tonumber(srv.playing) <= MAX_PLAYERS and srv.id ~= jobId then
                        collected[srv.id] = true
                    end
                end
                pagesChecked += 1
                cursor = body.nextPageCursor or ""
                task.wait(1)
                if cursor == "" then break end
            elseif body.errors then
                for _, e in ipairs(body.errors) do
                    if e.message:match("Too many requests") then
                        warn("Rate‑limited fetching servers; waiting 5s...")
                        task.wait(5)
                    end
                end
            else
                warn("Unexpected server list format; retrying...")
                task.wait(2.5)
            end
        else
            warn("Failed to fetch servers; retrying...")
            task.wait(3)
        end
    end

    local list = {}
    for id in pairs(collected) do
        table.insert(list, id)
    end

    local payload = {
        ts      = os.time(),
        servers = list,
    }

    if write_file then
        write_file(SERVER_LIST_FILE, HttpService:JSONEncode(payload))
        print("Server list saved (" .. #list .. " entries).")
    else
        warn("File IO unavailable; cannot write server list.")
    end
end

-- initial load or create
if not (is_file and is_file(SERVER_LIST_FILE)) then
    collectServers()
else
    local ok, raw = pcall(read_file, SERVER_LIST_FILE)
    if not (ok and raw and #raw > 2) then
        collectServers()
    else
        print("Loaded existing server list.")
    end
end

-- background refresher every TTL
task.spawn(function()
    while true do
        task.wait(SERVER_LIST_TTL)
        collectServers()
    end
end)

----------------------------------------------------------------
-- AUTO‑HOP (with TTL & full‑server handling)
----------------------------------------------------------------
local function autoHop()
    -- read & decode file
    local payload
    if is_file and read_file and is_file(SERVER_LIST_FILE) then
        local raw = read_file(SERVER_LIST_FILE)
        local ok, dec = pcall(HttpService.JSONDecode, HttpService, raw)
        payload = (ok and type(dec)=="table") and dec or { ts = 0, servers = {} }
    else
        payload = { ts = 0, servers = {} }
    end

    -- TTL check
    if os.time() - (payload.ts or 0) >= SERVER_LIST_TTL then
        print("Server list expired; recollecting...")
        collectServers()
        return autoHop()
    end

    local servers = payload.servers or {}
    if #servers == 0 then
        warn("No servers available; recollecting & retrying in 5s...")
        collectServers()
        task.wait(5)
        return autoHop()
    end

    -- pick & teleport
    local choice = servers[math.random(#servers)]
    print("Teleporting to server:", choice)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, choice, LocalPlayer)
    end)

    if not ok then
        if type(err)=="string" and err:match("TeleportGameFull") then
            warn("Server full: "..choice.."; removing and retrying...")
            -- remove from list
            for i,id in ipairs(servers) do
                if id == choice then
                    table.remove(servers, i)
                    break
                end
            end
            -- update file
            payload.servers = servers
            payload.ts = os.time()
            if write_file then
                write_file(SERVER_LIST_FILE, HttpService:JSONEncode(payload))
            end
            return autoHop()
        else
            error("Teleport error: "..tostring(err))
        end
    end
end

----------------------------------------------------------------
-- STARTUP
----------------------------------------------------------------
local function start()
    print("Started, actively searching for Rift:", TargetRift)
    repeat task.wait() until game:IsLoaded()
    task.wait(5)

    if not checkForRift() then
        print("No Rift found; hopping servers...")
        autoHop()
    end
end

start()
