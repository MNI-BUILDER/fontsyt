-- Variables for player and services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- API endpoint configuration
local API_ENDPOINT = "https://gamersbergbotapi.vercel.app/api/statics/testingbot"

-- Configuration
local CHECK_INTERVAL = 1 -- Check every 1 second
local RUNNING = true -- Control variable to stop the loop if needed

-- Function to compare two tables for equality
local function areTablesEqual(t1, t2)
    -- Check if both are tables
    if type(t1) ~= "table" or type(t2) ~= "table" then
        return t1 == t2
    end
    
    -- Check if all keys in t1 exist in t2 with the same values
    for k, v in pairs(t1) do
        if type(v) == "table" then
            if not areTablesEqual(v, t2[k]) then
                return false
            end
        elseif t2[k] ~= v then
            return false
        end
    end
    
    -- Check if all keys in t2 exist in t1
    for k, _ in pairs(t2) do
        if t1[k] == nil then
            return false
        end
    end
    
    return true
end

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
    local shopName = shopType == "seed" and "Seed_Shop" or "Gear_Shop"
    local shopUI = LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild(shopName)
    
    if not shopUI then 
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
    local shopName = shopType == "seed" and "Seed_Shop" or "Gear_Shop"
    local shopUI = LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild(shopName)
    
    if not shopUI then
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

    return 0
end

-- Function to collect all stock data
local function collectAllStockData()
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
    local HttpService = game:GetService("HttpService")
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
    
    local previousStockData = nil
    local updateCount = 0
    local lastUpdateTime = 0
    
    -- Main monitoring loop
    while RUNNING do
        local success, currentStockData = pcall(collectAllStockData)
        
        if success then
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

-- Start the monitoring
startStockMonitoring()

-- To stop monitoring, call:
-- stopMonitoring()
