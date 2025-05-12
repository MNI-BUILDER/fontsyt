-- Variables for player and services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- API endpoint configuration
local API_ENDPOINT = "https://gamersbergbotapi.vercel.app/api/statics/testingbot"

-- Improved function to get available items from a shop
local function getAvailableItems(shopType)
    local shopName = shopType == "seed" and "Seed_Shop" or "Gear_Shop"
    local shopUI = LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild(shopName)
    
    if not shopUI then 
        warn("Shop UI not found: " .. shopName)
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
        warn("Shop UI not found: " .. shopName)
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
    
    -- Try to use HttpService if available
    if syn and syn.request then
        -- Synapse X
        success, result = pcall(function()
            local response = syn.request({
                Url = API_ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = game:GetService("HttpService"):JSONEncode(data)
            })
            return response
        end)
    elseif http and http.request then
        -- Other executors
        success, result = pcall(function()
            local response = http.request({
                Url = API_ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = game:GetService("HttpService"):JSONEncode(data)
            })
            return response
        end)
    elseif request then
        -- Generic request function
        success, result = pcall(function()
            local response = request({
                Url = API_ENDPOINT,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = game:GetService("HttpService"):JSONEncode(data)
            })
            return response
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
                Body = game:GetService("HttpService"):JSONEncode(data)
            })
        end)
    else
        -- Try Roblox's HttpService as a last resort
        local HttpService = game:GetService("HttpService")
        success, result = pcall(function()
            return HttpService:PostAsync(API_ENDPOINT, HttpService:JSONEncode(data), Enum.HttpContentType.ApplicationJson)
        end)
    end
    
    if not success then
        warn("Failed to send data to API: " .. tostring(result))
        return false, "API request failed: " .. tostring(result)
    end
    
    print("API Response: ", result.Body or result)
    return true, "Data sent successfully"
end

-- Main function to execute the data collection and API submission
local function trackAndSubmitStockData()
    local success, errorMsg
    
    -- Collect data with error handling
    local stockData
    success, stockData = pcall(collectAllStockData)
    
    if not success then
        warn("Failed to collect stock data: " .. tostring(stockData))
        return false, "Data collection failed"
    end
    
    print("Collected stock data: ")
    for category, items in pairs(stockData) do
        if type(items) == "table" then
            print("  " .. category .. ":")
            for name, stock in pairs(items) do
                print("    " .. name .. ": " .. stock)
            end
        else
            print("  " .. category .. ": " .. tostring(items))
        end
    end
    
    -- Send data to API
    success, errorMsg = sendDataToAPI(stockData)
    
    if not success then
        return false, errorMsg
    end
    
    print("Successfully sent stock data to API")
    return true, "Data sent successfully"
end

-- Execute the tracking function
print("Starting stock tracking...")
local success, result = trackAndSubmitStockData()
if not success then
    warn("Stock tracking failed: " .. tostring(result))
else
    print("Stock tracking result: " .. tostring(result))
end
