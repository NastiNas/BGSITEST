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

local function autoHop()
	local servers = {}
	local pagesChecked = 0
	local cursor = ""
	local maxPages = 1

	while pagesChecked < maxPages do
		local url = string.format(
			"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true%s",
			placeId,
			cursor ~= "" and ("&cursor=" .. cursor) or ""
		)

		local success, response = pcall(function()
			return http_request({ Url = url })
		end)

		if success and response and response.Body then
			local body = HttpService:JSONDecode(response.Body)

			if body and body.data and typeof(body.data) == "table" and #body.data > 0 then
				for _, server in ipairs(body.data) do
                print(server.playing)
					if tonumber(server.playing) <= 10 and server.id ~= jobId then
                        print(server.id)
						table.insert(servers, server.id)
					end
				end

				pagesChecked += 1
				if body.nextPageCursor then
					cursor = body.nextPageCursor
					task.wait(2.5) -- 🕓 Slow down between pages
				else
					break
				end
			elseif body.errors then
				-- ⛔ Handle rate limit
				for _, err in ipairs(body.errors) do
					if err.message == "Too many requests" then
						warn("Rate limited. Waiting 5 seconds before retrying...")
						task.wait(5)
					end
				end
			else
				warn("Body data invalid or empty. Retrying...")
				task.wait(2.5)
			end
		else
			warn("Failed to get server list. Retrying...")
			task.wait(3)
		end
	end

	if #servers > 0 then
		local chosen = servers[math.random(1, #servers)]
		TeleportService:TeleportToPlaceInstance(placeId, chosen, LocalPlayer)
	else
        for i,v in servers do
            print(i,v)
        end
		warn("No suitable servers found. Retrying in 5s...")
		task.wait(5)
		autoHop()
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
