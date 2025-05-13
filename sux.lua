-- Shop Stock, Weather, and Egg Monitor
print("🛒 Shop Stock, Weather, and Egg Monitor Starting...")

-- Configuration
local API_ENDPOINT = "https://gagdata.vercel.app/api/data"
local API_KEY = "GAMERSBERGGAG"
local CHECK_INTERVAL = 5  -- Check every 5 seconds
local HEARTBEAT_INTERVAL = 60  -- Send heartbeat every 60 seconds
local MAX_RETRIES = 3

-- Cache to track changes
local Cache = {
    seedStock = {}, gearStock = {}, eggs = {},
    currentWeather = "None", weatherDuration = 0,
    lastUpdate = 0, lastHeartbeat = 0, errorCount = 0
}

-- Function to collect egg data
local function collectEggData()
    print("🥚 Collecting egg data...")
    local Eggs = {}
    
    local success, result = pcall(function()
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local EggShop = require(ReplicatedStorage.Data.PetEggData)
        
        for _, Egg in next, EggShop do
            if Egg.StockChance > 0 then
                table.insert(Eggs, Egg.EggName)
            end
        end
        return Eggs
    end)
    
    if success then
        print("✅ Egg data: " .. #result .. " eggs found")
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

-- Function to get available items from a shop
local function getAvailableItems(shopType)
    local shopUI = game.Players.LocalPlayer.PlayerGui:FindFirstChild(shopType)
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
    local data = {
        seeds = {}, gear = {}, eggs = Cache.eggs,
        weather = {
            type = Cache.currentWeather,
            duration = Cache.weatherDuration
        },
        timestamp = os.time(),
        playerName = game.Players.LocalPlayer.Name,
        userId = game.Players.LocalPlayer.UserId,
        heartbeat = (os.time() - Cache.lastUpdate) >= HEARTBEAT_INTERVAL
    }
    
    -- Collect seed data
    local seedNames = getAvailableItems("Seed_Shop")
    for _, seedName in ipairs(seedNames) do
        data.seeds[seedName] = checkStock(seedName, "Seed_Shop")
    end
    
    -- Collect gear data
    local gearNames = getAvailableItems("Gear_Shop")
    for _, gearName in ipairs(gearNames) do
        data.gear[gearName] = checkStock(gearName, "Gear_Shop")
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

-- Function to send data to API
local function sendToAPI(data)
    local success, response = pcall(function()
        -- Convert data to JSON string (simple version)
        local jsonStr = "{"
        
        -- Add timestamp and heartbeat flag
        jsonStr = jsonStr .. '"timestamp":' .. data.timestamp .. ','
        jsonStr = jsonStr .. '"heartbeat":' .. (data.heartbeat and "true" or "false") .. ','
        
        -- Add player info
        jsonStr = jsonStr .. '"playerName":"' .. data.playerName .. '",'
        jsonStr = jsonStr .. '"userId":' .. data.userId .. ','
        
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
        
        -- Send request using the supported REQUEST function with authorization header
        return request({
            Url = API_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY
            },
            Body = jsonStr
        })
    end)
    
    if not success then
        warn("❌ Failed to send data:", response)
        Cache.errorCount = Cache.errorCount + 1
        
        if Cache.errorCount >= MAX_RETRIES then
            warn("⚠️ Max retry attempts reached")
            Cache.errorCount = 0
            return false
        end
        
        print("🔄 Retrying in 5 seconds...")
        wait(5)
        return sendToAPI(data)
    end
    
    Cache.errorCount = 0
    print("✅ Data sent successfully")
    return true
end

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
    
    local success, conn = pcall(function()
        return game.ReplicatedStorage.GameEvents.WeatherEventStarted.OnClientEvent:Connect(function(weatherType, duration)
            print("🌦️ Weather event detected:", weatherType, duration)
            
            -- Update weather cache
            Cache.currentWeather = weatherType or "None"
            Cache.weatherDuration = duration or 0
            
            -- Force an immediate update to the API
            local currentData = collectStockData()
            sendToAPI(currentData)
            
            -- Update cache with new data
            Cache.seedStock = {}
            Cache.gearStock = {}
            
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
        -- Store new data
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
        sendToAPI(initialData)
    else
        warn("❌ Failed to collect initial data:", initialData)
    end
    
    -- Main monitoring loop
    while true do
        local success, currentData = pcall(collectStockData)
        
        if success then
            local currentTime = os.time()
            
            -- Periodically refresh egg data (every 5 minutes)
            if (currentTime - Cache.lastUpdate) >= 300 then
                Cache.eggs = collectEggData()
                currentData.eggs = Cache.eggs
            end
            
            -- Create comparison object
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
            local needsHeartbeat = (currentTime - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL
            
            -- Send update if changes detected or heartbeat needed
            if hasStockChanges or needsHeartbeat then
                local reason = hasStockChanges and "changes detected" or "heartbeat"
                print("📊 Sending update: " .. reason)
                
                -- Set heartbeat flag if this is a heartbeat update
                currentData.heartbeat = needsHeartbeat
                
                if sendToAPI(currentData) then
                    -- Update cache
                    Cache.seedStock = {}
                    Cache.gearStock = {}
                    
                    for k, v in pairs(currentData.seeds) do
                        Cache.seedStock[k] = v
                    end
                    
                    for k, v in pairs(currentData.gear) do
                        Cache.gearStock[k] = v
                    end
                    
                    Cache.lastUpdate = currentTime
                    if needsHeartbeat then
                        Cache.lastHeartbeat = currentTime
                    end
                    
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
