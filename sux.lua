-- Variables for player and services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- API endpoint configuration
local API_ENDPOINT = "https://gamersbergbotapi.vercel.app/api/statics/testingbot"

-- Configuration
local CHECK_INTERVAL = 1 -- Check every 1 second
local RUNNING = true -- Control variable to stop the loop if needed

-- Function to deep copy a table
local function deepCopy(original)
    local copy
    if type(original) == "table" then
        copy = {}
        for key, value in pairs(original) do
            copy[key] = deepCopy(value)
        end
    else
        copy = original
    end
    return copy
end

-- Improved function to get available items from a shop
local function getAvailableItems(shopType)
    -- Make sure LocalPlayer is valid
    if not LocalPlayer then
        warn("LocalPlayer is nil")
        return {}
    end
    
    -- Make sure PlayerGui exists
    if not LocalPlayer:FindFirstChild("PlayerGui") then
        warn("PlayerGui not found")
        return {}
    end
    
    local shopName = shopType == "seed" and "Seed_Shop" or "Gear_Shop"
    local shopUI = LocalPlayer.PlayerGui:FindFirstChild(shopName)
    
    if not shopUI then 
        warn("Shop UI not found: " .. shopName)
        return {} 
    end
    
    -- Make sure the UI structure is as expected
    if not shopUI:FindFirstChild("Frame") or not shopUI.Frame:FindFirstChild("ScrollingFrame") then
        warn("Expected UI structure not found in " .. shopName)
        return {}
    end

    local names = {}
    local scroll = shopUI.Frame.ScrollingFrame
    for _, item in pairs(scroll:GetChildren()) do
        if item:IsA("Frame") and not item.Name:match("_Padding$") then
            table.insert(names, item.Name)
        end
    end
    return names
end

-- Unified function to check stock for any item
local function getItemStock(itemName, shopType)
    -- Make sure LocalPlayer is valid
    if not LocalPlayer then
        warn("LocalPlayer is nil")
        return 0
    end
    
    -- Make sure PlayerGui exists
    if not LocalPlayer:FindFirstChild("PlayerGui") then
        warn("PlayerGui not found")
        return 0
    end
    
    local shopName = shopType == "seed" and "Seed_Shop" or "Gear_Shop"
    local shopUI = LocalPlayer.PlayerGui:FindFirstChild(shopName)
    
    if not shopUI then
        warn("Shop UI not found: " .. shopName)
        return 0
    end
    
    -- Make sure the UI structure is as expected
    if not shopUI:FindFirstChild("Frame") or not shopUI.Frame:FindFirstChild("ScrollingFrame") then
        warn("Expected UI structure not found in " .. shopName)
        return 0
    end

    -- Find the item frame
    local itemFrame
    for _, frame in pairs(shopUI.Frame.ScrollingFrame:GetChildren()) do
        if frame:IsA("Frame") and frame.Name == itemName then
            itemFrame = frame
            break
        end
    end

    if not itemFrame then
        warn("Item not found in shop: " .. itemName)
        return 0
    end

    -- Find the stock text
    for _, desc in pairs(itemFrame:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Name == "Stock_Text" then
            local stockText = desc.Text or "0"
            local stock = tonumber(string.match(stockText, "%d+"))
            return stock or 0
        end
    end

    warn("Stock text not found for item: " .. itemName)
    return 0
end

-- Function to collect all stock data
local function collectAllStockData()
    -- Make sure LocalPlayer is valid
    if not LocalPlayer then
        error("LocalPlayer is nil")
        return nil
    end
    
    local stockData = {
        seeds = {},
        gear = {},
        timestamp = os.time(),
        playerName = LocalPlayer.Name,
        userId = LocalPlayer.UserId
    }

    -- Collect seed data
    local seedNames = getAvailableItems("seed")
    for _, seedName in ipairs(seedNames) do
        local stock = getItemStock(seedName, "seed")
        stockData.seeds[seedName] = stock
    end

    -- Collect gear data
    local gearNames = getAvailableItems("gear")
    for _, gearName in ipairs(gearNames) do
        local stock = getItemStock(gearName, "gear")
        stockData.gear[gearName] = stock
    end

    return stockData
end

-- Function to send data to API using executor's request function or Roblox's HttpService
local function sendDataToAPI(data)
    -- Convert data to JSON
    local jsonData
    local success, result
    
    -- Try to use HttpService for JSON encoding
    local HttpService
    success, HttpService = pcall(function()
        return game:GetService("HttpService")
    end)
    
    if not success or not HttpService then
        warn("Failed to get HttpService")
        return false
    end
    
    success, jsonData = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    
    if not success then
        warn("Failed to encode data to JSON")
        return false
    end
    
    -- Try different HTTP request methods based on what's available
    if syn and syn.request then
        -- Synapse X
        success, result = pcall(function()
            return syn.request({
                Url = API_ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        end)
    elseif http and http.request then
        -- Other executors
        success, result = pcall(function()
            return http.request({
                Url = API_ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        end)
    elseif request then
        -- Generic request function
        success, result = pcall(function()
            return request({
                Url = API_ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        end)
    elseif httpservice then
        -- Custom httpservice
        success, result = pcall(function()
            return httpservice.request({
                Url = API_ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        end)
    else
        -- Try Roblox's HttpService as a last resort
        success, result = pcall(function()
            return HttpService:PostAsync(API_ENDPOINT, jsonData, Enum.HttpContentType.ApplicationJson)
        end)
    end
    
    if not success then
        warn("Failed to send data to API: " .. tostring(result))
        return false
    end
    
    print("API Response: ", type(result) == "table" and result.Body or tostring(result))
    return true
end

-- Function to detect changes in stock data
local function detectChanges(previousData, currentData)
    if not previousData then return true end
    
    -- Check seeds
    for seedName, currentStock in pairs(currentData.seeds) do
        if previousData.seeds[seedName] ~= currentStock then
            print("Change detected in seed: " .. seedName .. " (Old: " .. (previousData.seeds[seedName] or "nil") .. ", New: " .. currentStock .. ")")
            return true
        end
    end
    
    -- Check for new seeds
    for seedName, _ in pairs(previousData.seeds) do
        if currentData.seeds[seedName] == nil then
            print("Seed removed: " .. seedName)
            return true
        end
    end
    
    -- Check gear
    for gearName, currentStock in pairs(currentData.gear) do
        if previousData.gear[gearName] ~= currentStock then
            print("Change detected in gear: " .. gearName .. " (Old: " .. (previousData.gear[gearName] or "nil") .. ", New: " .. currentStock .. ")")
            return true
        end
    end
    
    -- Check for new gear
    for gearName, _ in pairs(previousData.gear) do
        if currentData.gear[gearName] == nil then
            print("Gear removed: " .. gearName)
            return true
        end
    end
    
    return false
end

-- Main monitoring function
local function startStockMonitoring()
    print("Starting continuous stock monitoring...")
    
    -- Make sure LocalPlayer is valid before starting
    if not LocalPlayer then
        warn("LocalPlayer is nil. Waiting for player to load...")
        
        -- Wait for player to load
        while not LocalPlayer and wait(1) do
            LocalPlayer = Players.LocalPlayer
        end
        
        if not LocalPlayer then
            error("Failed to get LocalPlayer after waiting")
            return
        end
    end
    
    print("Player loaded: " .. LocalPlayer.Name)
    
    local previousStockData = nil
    local updateCount = 0
    local lastUpdateTime = 0
    
    -- Main monitoring loop
    while RUNNING do
        local success, currentStockData = pcall(collectAllStockData)
        
        if success and currentStockData then
            local changesDetected = detectChanges(previousStockData, currentStockData)
            
            if changesDetected then
                updateCount = updateCount + 1
                print("Changes detected! Update #" .. updateCount)
                
                -- Send data to API
                local apiSuccess = sendDataToAPI(currentStockData)
                
                if apiSuccess then
                    print("Successfully sent updated stock data to API")
                    lastUpdateTime = os.time()
                    -- Update previous data after successful API update
                    previousStockData = deepCopy(currentStockData)
                else
                    print("Failed to send data to API, will retry on next change")
                end
            else
                -- No changes detected
                local timeSinceLastUpdate = os.time() - lastUpdateTime
                if timeSinceLastUpdate >= 60 then  -- Send heartbeat update every minute even if no changes
                    print("No changes for 60 seconds, sending heartbeat update")
                    sendDataToAPI(currentStockData)
                    lastUpdateTime = os.time()
                else
                    print("No changes detected. Checking again in " .. CHECK_INTERVAL .. " second(s)")
                end
            end
        else
            warn("Error collecting stock data: " .. tostring(currentStockData))
        end
        
        wait(CHECK_INTERVAL)
    end
    
    print("Stock monitoring stopped")
end

-- Function to stop monitoring
local function stopMonitoring()
    RUNNING = false
    print("Stopping monitoring...")
end

-- Wrap the entire execution in pcall to catch any errors
local success, errorMsg = pcall(function()
    -- Make sure Players service is available
    if not Players then
        error("Players service is nil")
        return
    end
    
    -- Get LocalPlayer, wait if necessary
    if not LocalPlayer then
        print("Waiting for LocalPlayer...")
        LocalPlayer = Players.LocalPlayer
        
        -- If still nil, wait for it
        if not LocalPlayer then
            local waitCount = 0
            while not LocalPlayer and waitCount < 10 do
                wait(1)
                LocalPlayer = Players.LocalPlayer
                waitCount = waitCount + 1
            end
        end
    end
    
    if not LocalPlayer then
        error("Failed to get LocalPlayer")
        return
    end
    
    -- Start monitoring
    startStockMonitoring()
end)

if not success then
    warn("Script error: " .. tostring(errorMsg))
end
