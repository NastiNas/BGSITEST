-- Rift Scanner (all‑in‑one) with cache‑file auto‑creation
local TargetRift  = "man-egg"
local SERVER_FILE = "rift_servers.json"
local SERVER_TTL  = 20 * 60   -- 20 minutes

-- Services
local Players         = game:GetService("Players")
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer     = Players.LocalPlayer
local placeId, jobId  = game.PlaceId, game.JobId

-- Webhook
local whh1 = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local whh2 = "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/"..whh1..whh2

-- reload on teleport
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/NOTMAIN.lua'))()")

-- simple logger
local function log(...) print("[RiftScanner]", ...) end

-- ensure cache file exists
if type(isfile)=="function" and not isfile(SERVER_FILE) then
    local init = { timestamp = 0, servers = {} }
    pcall(function()
        writefile(SERVER_FILE, HttpService:JSONEncode(init))
    end)
    log("Cache file created:", SERVER_FILE)
end

-- Discord embed
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
    local req  = http and http.request or request or (syn and syn.request)
    if req then
        pcall(function()
            req{ Url=WEBHOOK_URL, Method="POST",
                 Headers={["Content-Type"]="application/json"},
                 Body=body }
        end)
    end
end

-- safe WaitForChild
local function safeWait(parent, name, t)
    return parent:FindFirstChild(name)
        or (pcall(function() return parent:WaitForChild(name, t) end) and parent[name])
end

-- cache helpers
local function loadSaved()
    if type(isfile)~="function" or not isfile(SERVER_FILE) then return nil end
    local ok, txt = pcall(readfile, SERVER_FILE)
    if not ok or type(txt)~="string" then return nil end
    local data = HttpService:JSONDecode(txt)
    if type(data)~="table"
    or type(data.timestamp)~="number"
    or type(data.servers)~="table"
    then return nil end
    if os.time() - data.timestamp < SERVER_TTL then
        log("Using cached servers:", #data.servers, "entries; age", os.time()-data.timestamp, "s")
        return data.servers
    end
    return nil
end

local function saveServers(list)
    if type(list)~="table" then return end
    local data = { timestamp=os.time(), servers=list }
    pcall(function()
        writefile(SERVER_FILE, HttpService:JSONEncode(data))
    end)
end

-- fetch up to 5 pages, ≤10 players, skip current
local function fetchServerList(pages, limit)
    local out, cursor = {}, ""
    local req = http and http.request or request or (syn and syn.request)
    for page=1, pages do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=%d%s",
            placeId, limit,
            (cursor~="" and "&cursor="..cursor or "")
        )
        local ok, resp = pcall(function()
            return req{ Url=url, Method="GET" }
        end)
        if not ok or not resp or type(resp.Body)~="string" then
            warn("[RiftScanner] page",page,"fetch failed"); break
        end

        local body = HttpService:JSONDecode(resp.Body)
        if type(body)~="table" then
            warn("[RiftScanner] invalid JSON on page",page); break
        end

        local data = body.data
        if type(data)~="table" or #data == 0 then
            warn("[RiftScanner] no data on page",page); break
        end

        for _, srv in ipairs(data) do
            if tonumber(srv.playing) <= 10 and srv.id ~= jobId then
                table.insert(out, srv.id)
            end
        end

        if type(body.nextPageCursor) ~= "string" or body.nextPageCursor == "" then
            break
        end
        cursor = body.nextPageCursor
        task.wait(0.5)
    end
    return out
end

-- wrap cache or fresh
local function getServerList()
    local cached = loadSaved()
    if cached then return cached end
    log("Cache miss/expired → fetching servers…")
    local fresh = fetchServerList(5, 100)
    if #fresh > 0 then
        saveServers(fresh)
    else
        warn("[RiftScanner] fetched zero servers")
    end
    return fresh
end

-- find and notify
local function checkForRift()
    local rendered = safeWait(workspace, "Rendered", 10)
    local RiftFolder = rendered and safeWait(rendered, "Rifts", 10)
    if not RiftFolder then
        warn("[RiftScanner] no RiftFolder"); return false
    end

    for _, rift in ipairs(RiftFolder:GetChildren()) do
        if rift.Name == TargetRift
        and rift:FindFirstChild("EggPlatformSpawn")
        then
            local disp = rift:FindFirstChild("Display")
            local gui  = disp and disp:FindFirstChild("SurfaceGui")
            local tm   = gui and gui:FindFirstChild("Timer")
            local timeLeft = (tm and tm.Text) or "???"
            log("Rift FOUND! Time:", timeLeft)
            sendRiftFoundWebhook(timeLeft)
            repeat task.wait(1) until not rift:IsDescendantOf(workspace)
            log("Rift despawned; restarting")
            return true
        end
    end
    return false
end

-- hop through list
local function autoHop()
    local list = getServerList()
    if type(list)~="table" or #list == 0 then
        warn("[RiftScanner] no servers to hop; retry in 5s")
        task.wait(5)
        return autoHop()
    end

    for i,id in ipairs(list) do
        log("Teleporting to", id, "("..i.."/"..#list..")")
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, id, LocalPlayer)
        end)
        if ok then
            log("→ teleport started:", id)
            return
        elseif tostring(err):match("TeleportGameFull") then
            warn("[RiftScanner] full:", id)
        else
            warn("[RiftScanner] teleport error:", err)
        end
    end

    warn("[RiftScanner] all attempts failed; clearing cache")
    pcall(delfile, SERVER_FILE)
    task.wait(5)
    return autoHop()
end

-- entrypoint
local function start()
    log("Started; looking for Rift:", TargetRift)
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(5)
    if not checkForRift() then
        log("No Rift; hopping servers")
        autoHop()
    end
end

start()
