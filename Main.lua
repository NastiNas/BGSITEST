-- ✅ Rift Finder Script (Self-Repeating)
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local RiftFolder = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")
local placeId = game.PlaceId
local jobId = game.JobId

local WEBHOOK_URL = "https://discord.com/api/webhooks/..." -- your webhook here
local serverLink = string.format("https://www.roblox.com/games/%d/My-Game?jobId=%s", placeId, jobId)

-- 🔁 REQUEUE SELF
queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/NastiNas/BGSITEST/refs/heads/main/Main.lua'))()")

-- 📨 Send webhook alert
local function sendRiftFoundWebhook(time)
	local logData = {
		["embeds"] = { {
			["title"] = "Rift Found! " .. time .. "s Left!",
			["description"] = "Rift detected in server.\n[View Profile](https://www.roblox.com/users/".. LocalPlayer.UserId .."/profile)",
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

-- 🧠 Check for Rift
local function checkForRift()
	for _, rift in ipairs(RiftFolder:GetChildren()) do
		if rift:FindFirstChild("EggPlatformSpawn") and rift.Name == "man-egg" then
			local display = rift:FindFirstChild("Display")
			local surfaceGui = display and display:FindFirstChild("SurfaceGui")
			local timer = surfaceGui and surfaceGui:FindFirstChild("Timer")
			local timeLeft = timer and timer.Text or "???"
			print("[!] Rift Found")
			sendRiftFoundWebhook(timeLeft)

			-- ⏳ Wait for despawn
			repeat task.wait(1) until not rift.Parent or not rift:IsDescendantOf(workspace)
			return true
		end
	end
	return false
end

-- 🔄 Auto Server Hop Logic
local function autoHop()
	local servers = {}
	local req = http_request({
		Url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true", placeId)
	})
	local body = HttpService:JSONDecode(req.Body)

	if body and body.data then
		for _, v in ipairs(body.data) do
			if tonumber(v.playing) < tonumber(v.maxPlayers) and v.id ~= jobId then
				table.insert(servers, v.id)
			end
		end
	end

	if #servers > 0 then
		local chosen = servers[math.random(1, #servers)]
		TeleportService:TeleportToPlaceInstance(placeId, chosen, LocalPlayer)
	else
		task.wait(1)
		autoHop()
	end
end

-- 🚀 MAIN LOOP
local function start()
	repeat task.wait() until game:IsLoaded()
	task.wait(5)
	local found = checkForRift()
	if not found then
		autoHop()
	end
end

start()
