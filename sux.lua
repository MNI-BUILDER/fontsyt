-- Simple Shop Stock Monitor (based on reference)
print("🛒 Shop Stock Monitor Starting...")

-- Configuration
local API_ENDPOINT = "https://gamersbergbotapi.vercel.app/api/statics/testingbot"
local CHECK_INTERVAL = 5  -- Check every 5 seconds
local MAX_RETRIES = 3

-- Cache to track changes
local Cache = {
    seedStock = {},
    gearStock = {},
    lastUpdate = 0,
    errorCount = 0
}

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
    local data = {
        seeds = {},
        gear = {},
        timestamp = os.time(),
        playerName = game.Players.LocalPlayer.Name,
        userId = game.Players.LocalPlayer.UserId
    }
    
    -- Collect seed data
    local seedNames = getAvailableSeedNames()
    for _, seedName in ipairs(seedNames) do
        local stock = checkStock(seedName, "Seed_Shop")
        data.seeds[seedName] = stock
    end
    
    -- Collect gear data
    local gearNames = getAvailableGearNames()
    for _, gearName in ipairs(gearNames) do
        local stock = checkStock(gearName, "Gear_Shop")
        data.gear[gearName] = stock
    end
    
    return data
end

-- Function to detect changes in stock data
local function hasChanges(oldData, newData)
    -- Check seeds
    for seedName, newStock in pairs(newData.seeds) do
        if oldData.seeds[seedName] ~= newStock then
            return true
        end
    end
    
    -- Check for new seeds
    for seedName, _ in pairs(oldData.seeds) do
        if newData.seeds[seedName] == nil then
            return true
        end
    end
    
    -- Check gear
    for gearName, newStock in pairs(newData.gear) do
        if oldData.gear[gearName] ~= newStock then
            return true
        end
    end
    
    -- Check for new gear
    for gearName, _ in pairs(oldData.gear) do
        if newData.gear[gearName] == nil then
            return true
        end
    end
    
    return false
end

-- Function to send data to API
local function sendToAPI(data)
    local success, response = pcall(function()
        -- Convert data to JSON string (simple version)
        local jsonStr = "{"
        
        -- Add timestamp
        jsonStr = jsonStr .. '"timestamp":' .. data.timestamp .. ','
        
        -- Add player info
        jsonStr = jsonStr .. '"playerName":"' .. data.playerName .. '",'
        jsonStr = jsonStr .. '"userId":' .. data.userId .. ','
        
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
        
        -- Send request using the supported REQUEST function
        return request({
            Url = API_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
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

-- Main monitoring function
local function startMonitoring()
    print("🛒 Shop Stock Monitor Started")
    
    -- Setup anti-AFK
    pcall(setupAntiAFK)
    
    -- Initial data collection
    local success, initialData = pcall(collectStockData)
    if success then
        Cache.seedStock = initialData.seeds
        Cache.gearStock = initialData.gear
        Cache.lastUpdate = os.time()
        
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
            local hasStockChanges = hasChanges({seeds = Cache.seedStock, gear = Cache.gearStock}, currentData)
            local timeForceUpdate = (currentTime - Cache.lastUpdate) >= 300  -- Force update every 5 minutes
            
            if hasStockChanges or timeForceUpdate then
                print("📊 Stock changes detected or force update triggered")
                
                if sendToAPI(currentData) then
                    Cache.seedStock = currentData.seeds
                    Cache.gearStock = currentData.gear
                    Cache.lastUpdate = currentTime
                    print("📊 Stock data updated successfully")
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
