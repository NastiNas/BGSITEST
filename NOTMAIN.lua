--[[
  Rift Scanner / Auto‑Hop Script
  - Stores up to 5 pages of ≤10‑player servers in a local file.
  - Background thread refreshes the file every 2min.
  - On each hop, reads the file and teleports to a random server from it.
  - If a Rift named `TargetRift` is found, fires your Discord webhook.
  - Persists across teleports via queue_on_teleport.
--]]

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local TargetRift = "man-egg"

-- Discord webhook IDs
local whh1 = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local whh2 = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/"..whh1..whh2 

-- File to store your server list
local SERVER_LIST_FILE = "riftServerList.json"

----------------------------------------------------------------
-- SERVICES & UTIL
----------------------------------------------------------------
local Players        = game:GetService("Players")
local HttpService    = game:GetService("HttpService")
local TeleportService= game:GetService("TeleportService")
local LocalPlayer    = Players.LocalPlayer
local RiftFolder     = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local placeId        = game.PlaceId
local jobId          = game.JobId

-- detect executor HTTP & file‑IO
local http_request = http and http.request or request or (syn and syn.request)
local write_file   = writefile   or writeFile   or (syn and syn.write_file)
local read_file    = readfile    or readFile    or (syn and syn.read_file)
local is_file      = isfile      or isFile      or (syn and syn.is_file)

-- ensure randomness
math.randomseed(tick())

-- queue script on teleport so it auto‑reloads on each server hop
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")

----------------------------------------------------------------
-- WEBHOOK
----------------------------------------------------------------
local function sendRiftFoundWebhook(timeLeft)
    local payload = {
        embeds = {{
            title       = TargetRift.." Rift Found! "..timeLeft.." Left!",
            description = "Rift detected in [Server]("..string.format(
                                "https://www.roblox.com/games/%d/My-Game?jobId=%s",
                                placeId, jobId
                            )..")",
            color       = 0xff4444,
        }}
    }
    if http_request then
        http_request({
            Url     = WEBHOOK_URL,
            Method  = "POST",
            Headers = {["Content-Type"]="application/json"},
            Body    = HttpService:JSONEncode(payload),
        })
    else
        warn("No HTTP request function available for webhook.")
    end
end

----------------------------------------------------------------
-- RIFT CHECK
----------------------------------------------------------------
local function checkForRift()
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TargetRift and rift:FindFirstChild("EggPlatformSpawn") then
            local timerGui = rift:FindFirstChild("Display")
                             and rift.Display:FindFirstChild("SurfaceGui")
                             and rift.Display.SurfaceGui:FindFirstChild("Timer")
            local timeLeft = timerGui and timerGui.Text or "???"
            print("[!] Rift Found!")
            sendRiftFoundWebhook(timeLeft)

            -- wait for it to despawn before hopping again
            repeat task.wait(1) until not rift:IsDescendantOf(workspace)
            print("Rift Despawned, re-hopping...")
            return true
        end
    end
    return false
end

----------------------------------------------------------------
-- SERVER LIST COLLECTION
----------------------------------------------------------------
local function collectServers()
    local collected, pagesChecked, cursor = {}, 0, ""
    local maxPages = 5

    while pagesChecked < maxPages do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true%s",
            placeId,
            cursor ~= "" and "&cursor="..cursor or ""
        )

        local success, response = pcall(function()
            return http_request and http_request({Url=url})
        end)

        if success and response and response.Body then
            local body = HttpService:JSONDecode(response.Body)
            if body.data and #body.data > 0 then
                for _, srv in ipairs(body.data) do
                    if tonumber(srv.playing) <= 10 and srv.id ~= jobId then
                        collected[srv.id] = true
                    end
                end
                pagesChecked += 1
                cursor = body.nextPageCursor or ""
                task.wait(1)  -- avoid rate‑limit
                if cursor == "" then break end
            elseif body.errors then
                for _, e in ipairs(body.errors) do
                    if e.message:match("Too many requests") then
                        warn("Rate‑limited, waiting 5s...")
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

    -- flatten & write to file
    local list = {}
    for id in pairs(collected) do
        table.insert(list, id)
    end

    if write_file then
        write_file(SERVER_LIST_FILE, HttpService:JSONEncode(list))
    else
        warn("File IO unavailable; cannot write server list.")
    end
end

-- initial collection (or reload existing)
if is_file and is_file(SERVER_LIST_FILE) then
    local ok, content = pcall(read_file, SERVER_LIST_FILE)
    if not (ok and content and #content > 2) then
        collectServers()
    end
else
    collectServers()
end

-- background refresher
spawn(function()
    while true do
        task.wait(120)
        collectServers()
    end
end)

----------------------------------------------------------------
-- AUTO‑HOP
----------------------------------------------------------------
local function autoHop()
    local servers = {}
    if is_file and read_file and is_file(SERVER_LIST_FILE) then
        local raw = read_file(SERVER_LIST_FILE)
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok and type(decoded)=="table" and #decoded>0 then
            servers = decoded
        else
            warn("Server list invalid/empty; recollecting...")
            collectServers()
            -- try again once
            local raw2 = read_file(SERVER_LIST_FILE)
            local ok2, dec2 = pcall(HttpService.JSONDecode, HttpService, raw2)
            servers = (ok2 and type(dec2)=="table" and dec2) or {}
        end
    end

    if #servers > 0 then
        local choice = servers[math.random(#servers)]
        TeleportService:TeleportToPlaceInstance(placeId, choice, LocalPlayer)
    else
        warn("No servers in list; recollecting & retrying in 5s...")
        collectServers()
        task.wait(5)
        autoHop()
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
        autoHop()
    end
end

start()
