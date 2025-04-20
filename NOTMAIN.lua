-- Rift Scanner Script (Roblox Executor)
-- Caches server list with 20 min TTL, handles missing data, avoids nil‑length errors.

local TargetRift     = "man-egg"
local SERVER_FILE    = "rift_servers.json"
local SERVER_TTL     = 20 * 60  -- seconds

-- Services
local Players        = game:GetService("Players")
local HttpService    = game:GetService("HttpService")
local TeleportService= game:GetService("TeleportService")
local LocalPlayer    = Players.LocalPlayer
local placeId, jobId = game.PlaceId, game.JobId

-- Discord Webhook
local whh1 = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local whh2 = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/"..whh1..whh2

-- Auto‑reload the NOTMAIN script on teleport
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")

-- Simple prefixed logger
local function log(...)
    print("[RiftScanner]", ...)
end

-- Send embed to Discord
local function sendRiftFoundWebhook(timeLeft)
    local payload = {
        embeds = {{
            title       = TargetRift.." Rift Found! "..timeLeft.." Left!",
            description = "Rift detected in [Server]("..
                          string.format("https://www.roblox.com/games/%d/My-Game?jobId=%s", placeId, jobId)
                          ..")",
            color       = tonumber("0xff4444"),
        }}
    }
    local body = HttpService:JSONEncode(payload)
    local request = http and http.request or request or (syn and syn.request)
    if request then
        local ok, err = pcall(function()
            request({ Url=WEBHOOK_URL, Method="POST",
                      Headers={["Content-Type"]="application/json"},
                      Body=body })
        end)
        if not ok then
            warn("[RiftScanner] Webhook error:", err)
        end
    end
end

-- Safe WaitForChild with timeout
local function safeWait(parent, name, timeout)
    local found = parent:FindFirstChild(name)
    if found then return found end
    local ok, obj = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if ok then return obj end
    warn("[RiftScanner] Timeout waiting for "..name)
    return nil
end

-- Get the Rifts folder safely
local rendered   = safeWait(workspace, "Rendered", 10)
local RiftFolder = rendered and safeWait(rendered, "Rifts", 10)

-- Load cached servers if still valid
local function loadSavedServers()
    if not isfile(SERVER_FILE) then return nil end
    local ok, content = pcall(readfile, SERVER_FILE)
    if not ok then warn("[RiftScanner] readfile:", content); return nil end
    local data = HttpService:JSONDecode(content)
    if type(data)~="table" or type(data.timestamp)~="number" or type(data.servers)~="table" then
        return nil
    end
    if os.time() - data.timestamp < SERVER_TTL then
        log("Using cached server list ("..#data.servers.." entries, "..(os.time()-data.timestamp).."s old)")
        return data.servers
    end
    return nil
end

-- Save servers + timestamp
local function saveServers(list)
    local data = { timestamp=os.time(), servers=list }
    local ok, err = pcall(function()
        writefile(SERVER_FILE, HttpService:JSONEncode(data))
    end)
    if not ok then warn("[RiftScanner] writefile:", err) end
end

-- Fetch up to 5 pages of servers with ≤10 players, safely handles missing data
local function fetchServerList(maxPages, pageSize)
    local servers, cursor = {}, ""
    local http_request = http and http.request or request or (syn and syn.request)
    for page = 1, maxPages do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=%d%s",
            placeId, pageSize,
            cursor~="" and "&cursor="..cursor or ""
        )
        local ok, resp = pcall(function()
            return http_request({Url=url, Method="GET"})
        end)
        if not ok or not resp or not resp.Body then
            warn("[RiftScanner] Fetch page "..page.." failed")
            break
        end

        local body = HttpService:JSONDecode(resp.Body)
        if type(body)~="table" then
            warn("[RiftScanner] Invalid response structure on page "..page)
            break
        end

        local data = body.data
        if type(data)~="table" or #data == 0 then
            warn("[RiftScanner] No server data on page "..page)
            break
        end

        for _, s in ipairs(data) do
            if tonumber(s.playing) <= 10 and s.id ~= jobId then
                table.insert(servers, s.id)
            end
        end

        if type(body.nextPageCursor) ~= "string" then
            break
        end

        cursor = body.nextPageCursor
        task.wait(0.5)
    end

    return servers
end

-- Get current server list (cache or fetch+cache)
local function getServerList()
    local saved = loadSavedServers()
    if saved then return saved end

    log("Cache expired or missing; fetching new server list…")
    local fresh = fetchServerList(5, 100)
    if #fresh > 0 then
        saveServers(fresh)
    else
        warn("[RiftScanner] No servers fetched!")
    end
    return fresh
end

-- Scan workspace for the target rift
local function checkForRift()
    if not RiftFolder then
        warn("[RiftScanner] RiftFolder not found")
        return false
    end
    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TargetRift and rift:FindFirstChild("EggPlatformSpawn") then
            local display    = rift:FindFirstChild("Display")
            local surfaceGui = display and display:FindFirstChild("SurfaceGui")
            local timer      = surfaceGui and surfaceGui:FindFirstChild("Timer")
            local timeLeft   = timer and timer.Text or "???"
            log("Rift FOUND! Time left:", timeLeft)
            sendRiftFoundWebhook(timeLeft)
            repeat task.wait(1) until not rift:IsDescendantOf(workspace)
            log("Rift despawned; restarting search")
            return true
        end
    end
    return false
end

-- Auto‑hop through the server list, handling full‑server errors
local function autoHop()
    local list = getServerList()
    if #list == 0 then
        warn("[RiftScanner] Empty server list; retrying in 5s")
        task.wait(5)
        return autoHop()
    end

    for i, id in ipairs(list) do
        log("Teleporting to server", id, "("..i.."/"..#list..")")
        local success, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, id, LocalPlayer)
        end)
        if success then
            log("Teleport initiated to", id)
            return  -- quit script after teleport
        elseif tostring(err):find("TeleportGameFull") then
            warn("[RiftScanner] Server full:", id)
        else
            warn("[RiftScanner] Teleport error:", err)
        end
    end

    -- All servers failed → clear cache and retry
    warn("[RiftScanner] All servers failed; clearing cache and retrying")
    pcall(delfile, SERVER_FILE)
    task.wait(5)
    return autoHop()
end

-- Main entrypoint
local function start()
    log("Started; looking for Rift:", TargetRift)
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    task.wait(5)

    if not checkForRift() then
        log("No Rift found; hopping servers")
        autoHop()
    end
end

start()
