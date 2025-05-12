-- Ultra-simplified version with maximum error checking
print("Script starting...")

-- Wait for game to load
if not game then
    print("Game not available, waiting...")
    repeat wait(1) until game
    print("Game loaded")
end

-- Basic variables
local success, errorMsg

-- Wait for Players service
local Players
success, Players = pcall(function() return game:GetService("Players") end)
if not success or not Players then
    print("Failed to get Players service: " .. tostring(Players))
    Players = game:FindService("Players")
    if not Players then
        print("Still can't find Players service. Trying alternative...")
        Players = game.Players
    end
end

if not Players then
    print("CRITICAL ERROR: Players service is completely unavailable")
    return
end
print("Players service loaded successfully")

-- Wait for LocalPlayer
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    print("LocalPlayer not available, waiting...")
    local waitTime = 0
    while not LocalPlayer and waitTime < 30 do
        wait(1)
        waitTime = waitTime + 1
        LocalPlayer = Players.LocalPlayer
        print("Waiting for player... " .. waitTime .. " seconds")
    end
end

if not LocalPlayer then
    print("CRITICAL ERROR: LocalPlayer could not be loaded after 30 seconds")
    return
end
print("LocalPlayer loaded: " .. LocalPlayer.Name)

-- Wait for PlayerGui
if not LocalPlayer:FindFirstChild("PlayerGui") then
    print("PlayerGui not available, waiting...")
    local waitTime = 0
    while not LocalPlayer:FindFirstChild("PlayerGui") and waitTime < 30 do
        wait(1)
        waitTime = waitTime + 1
        print("Waiting for PlayerGui... " .. waitTime .. " seconds")
    end
end

if not LocalPlayer:FindFirstChild("PlayerGui") then
    print("CRITICAL ERROR: PlayerGui could not be loaded after 30 seconds")
    return
end
print("PlayerGui loaded successfully")

-- Debug function to print UI structure
local function printUIStructure(parent, level)
    level = level or 0
    local indent = string.rep("  ", level)
    
    print(indent .. parent.Name .. " [" .. parent.ClassName .. "]")
    
    for _, child in pairs(parent:GetChildren()) do
        printUIStructure(child, level + 1)
    end
end

-- Print all GUIs to help identify the correct ones
print("Listing all GUIs in PlayerGui:")
for _, gui in pairs(LocalPlayer.PlayerGui:GetChildren()) do
    print("- " .. gui.Name .. " [" .. gui.ClassName .. "]")
end

-- Try to find shop GUIs with flexible naming
local seedShopUI, gearShopUI

-- Look for anything with "Seed" in the name
for _, gui in pairs(LocalPlayer.PlayerGui:GetChildren()) do
    if gui.Name:match("[Ss]eed") then
        seedShopUI = gui
        print("Found potential Seed Shop UI: " .. gui.Name)
    end
    if gui.Name:match("[Gg]ear") then
        gearShopUI = gui
        print("Found potential Gear Shop UI: " .. gui.Name)
    end
end

-- If found, print their structure
if seedShopUI then
    print("Seed Shop UI Structure:")
    printUIStructure(seedShopUI, 1)
else
    print("No Seed Shop UI found")
end

if gearShopUI then
    print("Gear Shop UI Structure:")
    printUIStructure(gearShopUI, 1)
else
    print("No Gear Shop UI found")
end

print("Script completed successfully")

-- This is just a diagnostic script to help identify the correct UI structure
-- Once you see the output, you can modify the main script to match your game's UI structure
