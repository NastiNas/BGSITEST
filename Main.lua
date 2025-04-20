    if not game:IsLoaded() then
        print("Waiting for game to load...")
        game.Loaded:Wait()
    end

    local Players         = game:GetService("Players")
    local HttpService     = game:GetService("HttpService")
    local TeleportService = game:GetService("TeleportService")
    local LocalPlayer     = Players.LocalPlayer
    local placeId, jobId  = game.PlaceId, game.JobId

    local hookHalf1 = "1363337687406346391/wYzR7TTmB1c"
    local hookHalf2 = "oshGGzcOjQUQ-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"

    local WEBHOOK_URL     = "https://discord.com/api/webhooks/"..hookHalf1..hookHalf2
    local RIFT_NAME       = "man-egg"

    local function warnNotify(tag, msg)
        warn(("[%s] %s"):format(tag, msg))
    end

    local function sendRiftFoundWebhook(timeLeft)
        local profileUrl = ("https://www.roblox.com/users/%d/profile"):format(LocalPlayer.UserId)
        local payload = {
            embeds = {{
                title       = (RIFT_Name.. "Rift Found! %s Left"):format(timeLeft),
                description = ("Detected: [%s](%s)")
                              :format(LocalPlayer.Name, profileUrl)
            }}
        }
        local body       = HttpService:JSONEncode(payload)
        local req        = http and http.request or request or syn and syn.request
        if not req then
            return warnNotify("Webhook", "HTTP request unsupported; cannot send webhook.")
        end
        pcall(function()
            req({
                Url     = WEBHOOK_URL,
                Method  = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body    = body,
            })
        end)
    end

    local function serverHop()
        print("Attempting to hop to a new server...")
        local req = http and http.request or request or syn and syn.request
        if not req then
            return warnNotify("ServerHop", "Exploit missing HTTP support.")
        end

        while true do
            -- fetch up to 100 servers, exclude full ones
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?"
                       .. "sortOrder=Desc&limit=100&excludeFullGames=true")
                       :format(placeId)
            local ok, res = pcall(req, { Url = url })
            if ok and res and res.Body then
                local decOK, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if decOK and data and data.data then
                    for _, v in ipairs(data.data) do
                        if type(v)=="table"
                        and tonumber(v.playing)
                        and tonumber(v.maxPlayers)
                        and v.playing < v.maxPlayers
                        and v.id ~= jobId then

                            -- attempt teleport
                            local hopOK = pcall(function()
                                print("Teleporting to server")
                                TeleportService:TeleportToPlaceInstance(placeId, v.id, LocalPlayer)
                            end)

                            if hopOK then
                                return  -- teleport succeeded; script restarts via queue
                            else
                                print("Teleport failed; retrying")
                                warnNotify("Teleport", "Failed to join server "..v.id.."; retrying")
                            end
                        end
                    end
                end
            end

            -- nothing worked: wait then retry
            wait(1)
        end
    end

    -- Main scan + hop routine
    local function startScanning()
        -- 1) Wait for Rifts folder to exist
        print("Looking for Rifts folder...")

        local rendered = workspace:WaitForChild("Rendered", 30)
        if not rendered then
            warnNotify("Init", "Rendered missing; hopping")
            return serverHop()
        end
        local RiftFolder = rendered:WaitForChild("Rifts", 30)
        if not RiftFolder then
            warnNotify("Init", "Rifts missing; hopping")
            return serverHop()
        end

        -- small pause for everything to load
        wait(2)

        -- 2) Initial scan
        local found = false
        for _, r in ipairs(RiftFolder:GetChildren()) do
            if r.Name == RIFT_NAME then
                print("Found Rift")
                found = true
                local timerGui = r:FindFirstChild("Display")
                              and r.Display:FindFirstChild("SurfaceGui")
                              and r.Display.SurfaceGui:FindFirstChild("Timer")
                local timeLeft = timerGui and timerGui.Text or "??:??"
                sendRiftFoundWebhook(timeLeft)
                break
            end
        end

        -- 3a) If not found, hop immediately
        if not found then
            print("No Rift found; hopping")
            return serverHop()
        end

        -- 3b) If found, wait for despawn then hop
        RiftFolder.ChildRemoved:Connect(function(rem)
            if rem.Name == RIFT_NAME then
                print("Rift despawned; hopping")
                serverHop()
            end
        end)
    end

    -- run it
    print("yippee")
    startScanning()
