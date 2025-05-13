-- Shop Stock, Weather, and Egg Monitor with Data Persistence
print("🛒 Shop Stock, Weather, and Egg Monitor Starting...")

-- Configuration
local API_ENDPOINT = "https://gagdata.vercel.app/api/data"  -- API endpoint
local API_KEY = "GAMERSBERGGAG"  -- Authorization key
local CHECK_INTERVAL = 2  -- Check every 2 seconds
local HEARTBEAT_INTERVAL = 45  -- Send heartbeat every 45 seconds
local MAX_RETRIES = 3
local RECONNECT_DELAY = 10  -- Seconds to wait before reconnecting

-- Cache to track changes
local Cache = {
    seedStock = {},
    gearStock = {},
    eggs = {},
    currentWeather = "None",
    weatherDuration = 0,
    lastUpdate = 0,
    lastHeartbeat = 0,
    errorCount = 0,
    isConnected = false,
    lastData = nil  -- Store last successful data for recovery
}

-- Function to collect egg data
local function collectEggData()
    print("🥚 Collecting egg data...")
    local Eggs = {}
    
    -- Try to get the egg data module
    local success, result = pcall(function()
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local EggShop = require(ReplicatedStorage.Data.PetEggData)
        
        for _, Egg in next, EggShop do
            if Egg.StockChance > 0 then
                table.insert(Eggs, Egg.EggName)
                print("🥚 Found egg with stock chance > 0: " .. Egg.EggName)
            end
        end
        
        return Eggs
    end)
    
    if success then
        print("✅ Successfully collected egg data: " .. #result .. " eggs found")
        return result
    else
        warn("❌ Failed to collect egg data: " .. tostring(result))
        return {}
    end
end

-- Function to check stock for a specific item
local function checkStock(fruit, shopType)
    for _, des in pairs(game.Players.LocalPlayer.PlayerGui[shopType].Frame.ScrollingFrame:GetDescendants()) do
        if des.Name == "Stock_Text" and des.Parent.Parent.Name == fruit then
            return string.match(des.Text, "%d+")
        end
    end
    return "0"
end

-- Function to get all available seed names
local function getAvailableSeedNames()
    local shopUI = game.Players.LocalPlayer.PlayerGui:FindFirstChild("Seed_Shop")
    if not shopUI then return {} end

    local names = {}
    local scroll = shopUI.Frame.ScrollingFrame
    for _, item in pairs(scroll:GetChildren()) do
        if item:IsA("Frame") and not item.Name:match("_Padding$") then
            table.insert(names, item.Name)
        end
    end
    return names
end

-- Function to get all available gear names
local function getAvailableGearNames()
    local shopUI = game.Players.LocalPlayer.PlayerGui:FindFirstChild("Gear_Shop")
    if not shopUI then return {} end

    local names = {}
    local scroll = shopUI.Frame.ScrollingFrame
    for _, item in pairs(scroll:GetChildren()) do
        if item:IsA("Frame") and not item.Name:match("_Padding$") then
            table.insert(names, item.Name)
        end
    end
    return names
end

-- Function to collect all stock data
local function collectStockData()
    -- Create a completely new data object (old data gets garbage collected)
    local data = {
        seeds = {},
        gear = {},
        eggs = Cache.eggs,  -- Include egg data
        weather = {
            type = Cache.currentWeather,
            duration = Cache.weatherDuration
        },
        timestamp = os.time(),
        playerName = game.Players.LocalPlayer.Name,
        userId = game.Players.LocalPlayer.UserId,
        heartbeat = true  -- Flag to indicate this is a regular update
    }
    
    -- Collect seed data (fresh collection, not using old data)
    local seedNames = getAvailableSeedNames()
    for _, seedName in ipairs(seedNames) do
        local stock = checkStock(seedName, "Seed_Shop")
        data.seeds[seedName] = stock
    end
    
    -- Collect gear data (fresh collection, not using old data)
    local gearNames = getAvailableGearNames()
    for _, gearName in ipairs(gearNames) do
        local stock = checkStock(gearName, "Gear_Shop")
        data.gear[gearName] = stock
    end
    
    return data
end

-- Function to detect changes in stock data
local function hasChanges(oldData, newData)
    -- Check weather changes
    if oldData.weather.type ~= newData.weather.type or 
       oldData.weather.duration ~= newData.weather.duration then
        return true
    end
    
    -- Check eggs (compare length first for quick check)
    if #oldData.eggs ~= #newData.eggs then
        return true
    end
    
    -- Check each egg
    for i, eggName in ipairs(newData.eggs) do
        if oldData.eggs[i] ~= eggName then
            return true
        end
    end
    
    -- Check seeds
    for seedName, newStock in pairs(newData.seeds) do
        if oldData.seeds[seedName] ~= newStock then
            return true
        end
    end
    
    -- Check for new or removed seeds
    local oldSeedCount, newSeedCount = 0, 0
    for _ in pairs(oldData.seeds) do oldSeedCount = oldSeedCount + 1 end
    for _ in pairs(newData.seeds) do newSeedCount = newSeedCount + 1 end
    if oldSeedCount ~= newSeedCount then
        return true
    end
    
    -- Check gear
    for gearName, newStock in pairs(newData.gear) do
        if oldData.gear[gearName] ~= newStock then
            return true
        end
    end
    
    -- Check for new or removed gear
    local oldGearCount, newGearCount = 0, 0
    for _ in pairs(oldData.gear) do oldGearCount = oldGearCount + 1 end
    for _ in pairs(newData.gear) do newGearCount = newGearCount + 1 end
    if oldGearCount ~= newGearCount then
        return true
    end
    
    return false
end

-- Function to check if API has data
local function checkAPIData()
    print("🔍 Checking if API has data...")
    
    local success, response = pcall(function()
        return request({
            Url = API_ENDPOINT,
            Method = "GET",
            Headers = {
                ["Authorization"] = API_KEY
            }
        })
    end)
    
    if not success then
        warn("❌ Failed to check API data:", response)
        return false, nil
    end
    
    -- Try to parse the response
    local hasData = false
    local dataResponse = nil
    
    pcall(function()
        -- Check if response has a Body property (some executors return different formats)
        local body = response.Body or response
        
        -- Try to parse as JSON
        if type(body) == "string" then
            -- Simple JSON parsing check (look for data array)
            if body:match('"data"%s*:%s*%[') then
                local dataStart = body:find('"data"%s*:%s*%[')
                local dataContent = body:sub(dataStart)
                
                -- Check if the data array is empty
                if not dataContent:match('"data"%s*:%s*%[%s*%]') then
                    hasData = true
                    dataResponse = body
                end
            end
        end
    end)
    
    return hasData, dataResponse
end

-- Function to send data to API with persistence logic
local function sendToAPI(data, isHeartbeat)
    -- Add heartbeat flag if this is a heartbeat update
    if isHeartbeat then
        data.heartbeat = true
    end
    
    local success, response = pcall(function()
        -- Convert data to JSON string (simple version)
        local jsonStr = "{"
        
        -- Add timestamp
        jsonStr = jsonStr .. '"timestamp":' .. data.timestamp .. ','
        
        -- Add player info
        jsonStr = jsonStr .. '"playerName":"' .. data.playerName .. '",'
        jsonStr = jsonStr .. '"userId":' .. data.userId .. ','
        
        -- Add heartbeat flag
        jsonStr = jsonStr .. '"heartbeat":' .. (data.heartbeat and "true" or "false") .. ','
        
        -- Add weather info
        jsonStr = jsonStr .. '"weather":{'
        jsonStr = jsonStr .. '"type":"' .. data.weather.type .. '",'
        jsonStr = jsonStr .. '"duration":' .. data.weather.duration
        jsonStr = jsonStr .. '},'
        
        -- Add eggs array
        jsonStr = jsonStr .. '"eggs":['
        for i, eggName in ipairs(data.eggs) do
            if i > 1 then jsonStr = jsonStr .. ',' end
            jsonStr = jsonStr .. '"' .. eggName .. '"'
        end
        jsonStr = jsonStr .. '],'
        
        -- Add seeds
        jsonStr = jsonStr .. '"seeds":{'
        local first = true
        for name, stock in pairs(data.seeds) do
            if not first then jsonStr = jsonStr .. ',' end
            first = false
            jsonStr = jsonStr .. '"' .. name .. '":"' .. stock .. '"'
        end
        jsonStr = jsonStr .. '},'
        
        -- Add gear
        jsonStr = jsonStr .. '"gear":{'
        first = true
        for name, stock in pairs(data.gear) do
            if not first then jsonStr = jsonStr .. ',' end
            first = false
            jsonStr = jsonStr .. '"' .. name .. '":"' .. stock .. '"'
        end
        jsonStr = jsonStr .. '}'
        
        jsonStr = jsonStr .. "}"
        
        -- Check if API has data before deciding whether to use PUT or POST
        local hasData, _ = checkAPIData()
        
        local method = "POST"  -- Default to POST
        
        -- If API already has data, use PUT to update it
        if hasData then
            method = "PUT"
            print("🔄 API already has data, using PUT to update")
        else
            print("➕ API has no data, using POST to create")
        end
        
        -- Send request using the supported REQUEST function with authorization header
        return request({
            Url = API_ENDPOINT,
            Method = method,
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Heartbeat"] = isHeartbeat and "true" or "false"  -- Indicate if this is a heartbeat
            },
            Body = jsonStr
        })
    end)
    
    if not success then
        warn("❌ Failed to send data:", response)
        Cache.errorCount = Cache.errorCount + 1
        Cache.isConnected = false
        
        if Cache.errorCount >= MAX_RETRIES then
            warn("⚠️ Max retry attempts reached, will try again later")
            Cache.errorCount = 0
            return false
        end
        
        print("🔄 Retrying in 5 seconds...")
        wait(5)
        return sendToAPI(data, isHeartbeat)
    end
    
    -- Reset error count and mark as connected
    Cache.errorCount = 0
    Cache.isConnected = true
    
    -- Store last successful data for recovery
    Cache.lastData = data
    
    -- Update last heartbeat time if this was a heartbeat
    if isHeartbeat then
        Cache.lastHeartbeat = os.time()
        print("💓 Heartbeat sent successfully")
    else
        print("✅ Data sent successfully")
    end
    
    return true
end

-- Function to send a heartbeat to keep the connection alive
local function sendHeartbeat()
    print("💓 Sending heartbeat to prevent data deletion...")
    
    -- If we have last data, use it for the heartbeat
    if Cache.lastData then
        -- Update the timestamp
        Cache.lastData.timestamp = os.time()
        Cache.lastData.heartbeat = true
        
        -- Send the heartbeat
        sendToAPI(Cache.lastData, true)
    else
        -- Collect new data for the heartbeat
        local success, heartbeatData = pcall(collectStockData)
        
        if success then
            sendToAPI(heartbeatData, true)
        else
            warn("❌ Failed to collect data for heartbeat:", heartbeatData)
        end
    end
end

-- Function to recover data if it was deleted
local function recoverData()
    print("🔄 Checking if data recovery is needed...")
    
    -- Check if API has data
    local hasData, _ = checkAPIData()
    
    if not hasData and Cache.lastData then
        print("🔄 Data not found in API, recovering...")
        
        -- Update timestamp on last data
        Cache.lastData.timestamp = os.time()
        Cache.lastData.recovered = true  -- Mark as recovered data
        
        -- Send the recovered data
        sendToAPI(Cache.lastData, false)
        
        return true
    end
    
    return false
}

-- Anti-AFK function
local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    game.Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        print("🔄 Anti-AFK triggered")
    end)
end

-- Setup weather event listener
local function setupWeatherListener()
    print("🌦️ Setting up weather event listener...")
    
    -- Fix the syntax for connecting to the weather event
    local success, conn = pcall(function()
        return game.ReplicatedStorage.GameEvents.WeatherEventStarted.OnClientEvent:Connect(function(weatherType, duration)
            print("🌦️ Weather event detected:", weatherType, duration)
            
            -- Update weather cache
            Cache.currentWeather = weatherType or "None"
            Cache.weatherDuration = duration or 0
            
            -- Force an immediate update to the API
            local currentData = collectStockData()
            sendToAPI(currentData, false)
            
            -- Update cache with new data
            Cache.seedStock = {}  -- Clear old data
            Cache.gearStock = {}  -- Clear old data
            
            -- Copy new data (not references)
            for k, v in pairs(currentData.seeds) do
                Cache.seedStock[k] = v
            end
            
            for k, v in pairs(currentData.gear) do
                Cache.gearStock[k] = v
            end
            
            Cache.lastUpdate = os.time()
        end)
    end)
    
    if not success then
        warn("⚠️ Failed to set up weather listener:", conn)
    else
        print("✅ Weather listener set up successfully")
    end
end

-- Main monitoring function
local function startMonitoring()
    print("🛒 Shop Stock, Weather, and Egg Monitor Started")
    print("📡 Using API endpoint: " .. API_ENDPOINT)
    
    -- Setup anti-AFK
    pcall(setupAntiAFK)
    
    -- Setup weather listener
    pcall(setupWeatherListener)
    
    -- Collect egg data
    Cache.eggs = collectEggData()
    
    -- Initial data collection
    local success, initialData = pcall(collectStockData)
    if success then
        -- Clear old data and store new data (not references)
        Cache.seedStock = {}
        Cache.gearStock = {}
        
        for k, v in pairs(initialData.seeds) do
            Cache.seedStock[k] = v
        end
        
        for k, v in pairs(initialData.gear) do
            Cache.gearStock[k] = v
        end
        
        Cache.lastUpdate = os.time()
        Cache.lastHeartbeat = os.time()
        
        -- Send initial data
        sendToAPI(initialData, false)
    else
        warn("❌ Failed to collect initial data:", initialData)
    end
    
    -- Main monitoring loop
    while true do
        -- Check if we need to recover data
        if not Cache.isConnected then
            print("📡 Attempting to reconnect...")
            recoverData()
            wait(RECONNECT_DELAY)
        end
        
        -- Check if we need to send a heartbeat
        local currentTime = os.time()
        if (currentTime - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
            sendHeartbeat()
        end
        
        -- Regular data collection and update
        local success, currentData = pcall(collectStockData)
        
        if success then
            -- Periodically refresh egg data (every 5 minutes)
            if (currentTime - Cache.lastUpdate) >= 300 then
                Cache.eggs = collectEggData()
                currentData.eggs = Cache.eggs
            end
            
            -- Create a comparison object with the same structure as currentData
            local oldData = {
                seeds = Cache.seedStock,
                gear = Cache.gearStock,
                eggs = Cache.eggs,
                weather = {
                    type = Cache.currentWeather,
                    duration = Cache.weatherDuration
                }
            }
            
            local hasStockChanges = hasChanges(oldData, currentData)
            local timeForceUpdate = (currentTime - Cache.lastUpdate) >= 300  -- Force update every 5 minutes
            
            if hasStockChanges or timeForceUpdate then
                print("📊 Changes detected or force update triggered")
                
                if sendToAPI(currentData, false) then
                    -- Clear old data and store new data (not references)
                    Cache.seedStock = {}
                    Cache.gearStock = {}
                    
                    for k, v in pairs(currentData.seeds) do
                        Cache.seedStock[k] = v
                    end
                    
                    for k, v in pairs(currentData.gear) do
                        Cache.gearStock[k] = v
                    end
                    
                    Cache.lastUpdate = currentTime
                    print("📊 Data updated successfully")
                end
            else
                print("📊 No changes detected")
            end
        else
            warn("❌ Error collecting data:", currentData)
        end
        
        wait(CHECK_INTERVAL)
    end
end

-- Start the monitoring
startMonitoring()
