print("Loaded Script")
wait(1)
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local RiftFolder = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local PlaceId = game.PlaceId
local JobId = game.JobId

-- Webhook Setup
local WEBHOOK_URL = "https://discord.com/api/webhooks/your_webhook_here"
local serverLink = string.format("https://www.roblox.com/games/%d/My-Game?jobId=%s", PlaceId, JobId)

local function sendRiftFoundWebhook(timerText)
	local logData = {
		["embeds"] = {{
			["title"] = "Rift Found! " .. timerText .. " left!",
			["description"] = "Rift detected in this server.\n[Join Profile](https://www.roblox.com/users/".. LocalPlayer.UserId .."/profile)",
			["color"] = 16711680
		}}
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
		if rift:FindFirstChild("EggPlatformSpawn") then
			local display = rift:FindFirstChild("Display")
			local surfaceGui = display and display:FindFirstChild("SurfaceGui")
			local timer = surfaceGui and surfaceGui:FindFirstChild("Timer")
			local eggName = rift.Name:lower()
			if eggName == "man-egg" then
				print("Egg Found")
				sendRiftFoundWebhook(timer and timer.Text or "???")
				repeat task.wait(1) until not rift.Parent -- Wait for rift to despawn
				return false
			else
				print("Not Found")
		end
	end
	return true -- Not found
end

local function serverHop()
	print("Attempting to Hop Servers")
	local success = false
	while not success do
		local servers = {}
		local req = (http and http.request or request or syn and syn.request)({
			Url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true", PlaceId)
		})
		local body = HttpService:JSONDecode(req.Body)
		if body and body.data then
			for _, server in ipairs(body.data) do
				if server.playing < server.maxPlayers and server.id ~= JobId then
					table.insert(servers, 1, server.id)
				end
			end
		end
		if #servers > 0 then
			queue_on_teleport("loadstring(game:HttpGet('https://pastebin.com/raw/YOUR_PASTEBIN_CODE'))()")
			TeleportService:TeleportToPlaceInstance(PlaceId, servers[math.random(1, #servers)], LocalPlayer)
			success = true
		else
			task.wait(1)
		end
	end
end

-- Wait until game is fully loaded
if not game:IsLoaded() then
	print("Waiting for game to load...")
	game.Loaded:Wait()
end

-- Start scanning logic
local notFound = checkForRift()
if notFound then
	serverHop()
end
