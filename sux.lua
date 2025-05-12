-- Ultra-simplified script using only supported functions
print("Script starting...")

-- Function to make HTTP requests (using the supported REQUEST function)
local function makeRequest(url, method, data)
    method = method or "GET"
    
    local options = {
        Url = url,
        Method = method
    }
    
    if data then
        options.Body = data
        options.Headers = {
            ["Content-Type"] = "application/json"
        }
    end
    
    local success, response = pcall(function()
        return request(options)
    end)
    
    if success then
        return response
    else
        print("Request failed: " .. tostring(response))
        return nil
    end
end

-- API endpoint
local API_ENDPOINT = "https://gamersbergbotapi.vercel.app/api/statics/testingbot"

-- Simple data collection function
local function collectData()
    local data = {
        timestamp = os.time(),
        executor = "Limited Functionality Executor",
        data = {}
    }
    
    -- Try to get player info if available
    pcall(function()
        if game and game:GetService("Players") and game:GetService("Players").LocalPlayer then
            data.playerName = game:GetService("Players").LocalPlayer.Name
            data.userId = game:GetService("Players").LocalPlayer.UserId
        end
    end)
    
    -- Try to find shop UIs
    pcall(function()
        if game and game:GetService("Players") and game:GetService("Players").LocalPlayer and 
           game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui") then
            
            local playerGui = game:GetService("Players").LocalPlayer.PlayerGui
            local shopData = {}
            
            -- Look for any GUI that might be a shop
            for _, gui in pairs(playerGui:GetChildren()) do
                if gui:IsA("ScreenGui") then
                    local guiInfo = {
                        name = gui.Name,
                        children = {}
                    }
                    
                    -- Try to find any stock information
                    pcall(function()
                        for _, desc in pairs(gui:GetDescendants()) do
                            if desc:IsA("TextLabel") and desc.Name:match("Stock") then
                                table.insert(guiInfo.children, {
                                    name = desc.Name,
                                    text = desc.Text,
                                    parent = desc.Parent and desc.Parent.Name or "Unknown"
                                })
                            end
                        end
                    end)
                    
                    if #guiInfo.children > 0 then
                        shopData[gui.Name] = guiInfo
                    end
                end
            end
            
            data.shops = shopData
        end
    end)
    
    return data
end

-- Function to convert table to JSON (since JSONEncode might not be available)
local function tableToJSON(tbl)
    local json = "{"
    local first = true
    
    for k, v in pairs(tbl) do
        if not first then
            json = json .. ","
        end
        first = false
        
        -- Key
        json = json .. '"' .. tostring(k) .. '":'
        
        -- Value
        if type(v) == "table" then
            json = json .. tableToJSON(v)
        elseif type(v) == "string" then
            json = json .. '"' .. v:gsub('"', '\\"') .. '"'
        elseif type(v) == "number" or type(v) == "boolean" then
            json = json .. tostring(v)
        else
            json = json .. '""'
        end
    end
    
    json = json .. "}"
    return json
end

-- Main monitoring function
local function startMonitoring()
    print("Starting monitoring...")
    
    -- Initial data collection
    local lastData = collectData()
    print("Initial data collected")
    
    -- Send initial data
    local response = makeRequest(API_ENDPOINT, "POST", tableToJSON(lastData))
    if response then
        print("Initial data sent successfully")
        if response.Body then
            print("Response: " .. response.Body)
        end
    else
        print("Failed to send initial data")
    end
    
    -- Monitoring loop
    while true do
        wait(5) -- Check every 5 seconds
        
        local currentData = collectData()
        print("Data collected, sending to API...")
        
        -- Send current data
        local response = makeRequest(API_ENDPOINT, "POST", tableToJSON(currentData))
        if response then
            print("Data sent successfully")
            if response.Body then
                print("Response: " .. response.Body)
            end
        else
            print("Failed to send data")
        end
    end
end

-- Start monitoring
startMonitoring()
