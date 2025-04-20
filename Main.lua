local TargetRift = "man-egg"


local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local RiftFolder = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local placeId = game.PlaceId
local jobId = game.JobId


local whh1 = "1363337687406346391/wYzR7TTmB1coshGGzcOjQUQ"
local whh2 =  "-WBHy7jS-R29TyglyA7Inj6UpUhYMY3w2VmHtcXBkbY94"
local WEBHOOK_URL = "https://discord.com/api/webhooks/"..whh1..whh2 -- your webhook here
local serverLink = string.format("https://www.roblox.com/games/%d/My-Game?jobId=%s", placeId, jobId)


queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/Main.lua'))()")


local function sendRiftFoundWebhook(time)
	local logData = {
		["embeds"] = { {
			["title"] = ""..TargetRift.." Rift Found! " .. time .. " Left!",
			["description"] = "Rift detected in [Server](https://www.roblox.com/users/".. LocalPlayer.UserId .."/profile)",
			["color"] = tonumber(0xff4444)
		} }
	}
	local encoded = HttpService:JSONEncode(logData)
	local http_request = http and http.request or request or syn and syn.request
	if http_request then
		http_request({
			Url = WEBHOOK_URL,
			Method = "POST",
			Headers = {["Content-Type"] = "application/json"},
			Body = encoded
		})
	end
end

local function checkForRift()
	for _, rift in ipairs(RiftFolder:GetChildren()) do
		if rift:FindFirstChild("EggPlatformSpawn") and rift.Name == TargetRift then
			local display = rift:FindFirstChild("Display")
			local surfaceGui = display and display:FindFirstChild("SurfaceGui")
			local timer = surfaceGui and surfaceGui:FindFirstChild("Timer")
			local timeLeft = timer and timer.Text or "???"
			print("[!] Rift Found")
			sendRiftFoundWebhook(timeLeft)

			repeat task.wait(1) until not rift.Parent or not rift:IsDescendantOf(workspace)
            print("Rift Despawned, re-hopping...")
			return true
		end
	end
	return false
end

local function autohop()
    local success = false
    while not success do
        if httprequest then
            local servers = {}
            local req = httprequest({
                Url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true", PlaceId)
            })

            local body = HttpService:JSONDecode(req.Body)

            if body and body.data then
                for i, v in next, body.data do
                    if type(v) == "table" and tonumber(v.playing) and tonumber(v.maxPlayers) and v.playing < v.maxPlayers and v.id ~= JobId then
                        table.insert(servers, v.id)
                    end
                end
            end

            if #servers > 0 then
                for i = #servers, 2, -1 do
                    local j = math.random(1, i)
                    servers[i], servers[j] = servers[j], servers[i]
                end

                local target = servers[math.random(1, #servers)]
                local worked, err = pcall(function()
                    TeleportService:TeleportToPlaceInstance(PlaceId, target, Players.LocalPlayer)
                end)

                if worked then
                    success = true
                else
                    warn("Teleport failed:", err)
                    wait(1)
                end
            else
                warn("Couldn't find a valid server. Retrying...")
                wait(2)
            end
        else
            warn("Exploit does not support 'httprequest'.")
            break
        end
    end
end


local function start()
    print("Started, Actively Searching For ".. TargetRift)
	repeat task.wait() until game:IsLoaded()
	task.wait(5)
	local found = checkForRift()
	if not found then
		autoHop()
	end
end

start()
