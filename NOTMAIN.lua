--==== SELF‑QUEUE ON TELEPORT ====--
local function main()
    local Players         = game:GetService("Players")
    local TeleportService = game:GetService("TeleportService")
    local HttpService     = game:GetService("HttpService")
    local placeId         = game.PlaceId
    local cacheFile       = "server_list_cache.txt"
    local servers         = {}

    -- ensure cache file exists
    if not (isfile and isfile(cacheFile)) then
        writefile(cacheFile, "") 
    end

    local function now() return os.time() end

    local function fetchServerList()
        local cursor
        repeat
            local url = 
                ("https://games.roblox.com/v1/games/%d/servers/Public?limit=100%s")
                :format(placeId, cursor and "&cursor="..cursor or "")
            local raw = HttpService:GetAsync(url)
            local data = HttpService:JSONDecode(raw)
            for _,srv in ipairs(data.data) do
                if srv.playing < srv.maxPlayers then
                    table.insert(servers, srv.id)
                end
            end
            cursor = data.nextPageCursor
        until not cursor

        -- update timestamp
        writefile(cacheFile, tostring(now()))
    end

    local function getServerList()
        local stored = tonumber(readfile(cacheFile)) or 0
        if now() - stored < 1200 and #servers > 0 then
            return servers
        end
        table.clear(servers)
        fetchServerList()
        return servers
    end

    local function hop()
        local list = getServerList()
        if #list == 0 then
            warn("✨ No servers available to hop.")
            return
        end
        local choice = list[math.random(1, #list)]
        pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, choice, Players.LocalPlayer)
        end)
    end

    -- loop every minute
    while true do
        hop()
        wait(60)
    end
end

-- queue for next server
if syn and syn.queue_on_teleport then
    syn.queue_on_teleport(string.dump(main))
elseif queue_on_teleport then
    queue_on_teleport(string.dump(main))
end

-- start first run
main()
