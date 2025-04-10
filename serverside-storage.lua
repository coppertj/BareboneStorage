-- Function to log errors to a file
function logError(message)
    local logFile = fs.open("error_log.txt", "a")  -- 'a' to append to the existing log
    logFile.writeLine(message)
    logFile.close()
end

-- Function to check and download Basalt if not already installed
function checkAndDownloadBasalt()
    if not fs.exists("basalt.lua") then
        logError("Basalt not found, downloading...")
        shell.run("wget run https://raw.githubusercontent.com/Pyroxenium/Basalt/refs/heads/master/docs/install.lua release latest.lua basalt.lua")
        logError("Basalt installed successfully, starting the program...")
        os.sleep(3)
    end
end

-- Call the function to check and download Basalt
checkAndDownloadBasalt()

local basalt = require("basalt")

-- Ensure Rednet is available and open a channel for communication
local modem = peripheral.find("modem") or error("No modem attached", 0)
rednet.open(peripheral.getName(modem))
logError("Rednet opened on modem: " .. peripheral.getName(modem))

local fileName = "database.txt"
local itemLocations = {}
local chests = {}
local mainChest = nil
local fullItemList = {} -- Table to store all items

local pocketToEnderChestMapFileName = "pocket_to_ender_chest_map.txt"
local pocketToEnderChestMap = {}

-- Discover all connected chests and designate the main chest
function discoverChests()
    local peripheralList = peripheral.getNames()
    
    local chestIndex = 1
    logError("Discovering peripherals...")
    for _, peripheralName in ipairs(peripheralList) do
        local peripheralType = peripheral.getType(peripheralName)
        logError("Found peripheral: " .. peripheralName .. " of type " .. peripheralType)
        if peripheralType == "minecraft:barrel" then
            mainChest = peripheral.wrap(peripheralName)
            logError("Designated main chest: " .. peripheralName)
        elseif peripheralType == "minecraft:chest"
            or peripheralType:match("^ironchests:")
            or peripheralType:match("^quark:")
            or peripheralType:match("^sophisticatedstorage:") then
            chests[chestIndex] = peripheral.wrap(peripheralName)
            chestIndex = chestIndex + 1
        end
    end

    if mainChest == nil then
        logError("Warning: No barrel found. Please add a barrel to the network to designate as the main chest.")
    end
end

-- Initialize the database with the current inventory
function initDatabase()
    itemLocations = {} -- Reset the database
    logError("Initializing database...")
    for chestIndex, chest in pairs(chests) do
        for slot, item in pairs(chest.list()) do
            if not itemLocations[item.name] then
                itemLocations[item.name] = {}
            end
            itemLocations[item.name][chestIndex] = itemLocations[item.name][chestIndex] or {}
            itemLocations[item.name][chestIndex][slot] = item.count
        end
    end
    logError("Database initialized")
end

-- Save the database to a file
function saveDatabase()
    local file = fs.open(fileName, "w")
    file.write(textutils.serialize(itemLocations))
    file.close()
    logError("Database saved to " .. fileName)
end

-- Load the database from a file
function loadDatabase()
    if fs.exists(fileName) then
        local file = fs.open(fileName, "r")
        itemLocations = textutils.unserialize(file.readAll())
        file.close()
        logError("Database loaded from " .. fileName)
    else
        saveDatabase() -- Create the file if it doesn't exist
    end
end

function getTotalItemCount(locations)
    local count = 0
    for _, slots in pairs(locations) do
        for _, itemCount in pairs(slots) do
            count = count + itemCount
        end
    end
    return count
end

-- Populate fullItemList with all items, sorted by total count in descending order
function populateFullItemList()
    fullItemList = {}
    for itemName, locations in pairs(itemLocations) do
        local totalCount = getTotalItemCount(locations)
        table.insert(fullItemList, {name = itemName, count = totalCount})
    end
    table.sort(fullItemList, function(a, b) return a.count > b.count end)
end

-- Function to update the item list based on the search query
function updateItemList(itemList, query)
    itemList:clear()
    query = query or "" -- Ensure query is not nil
    query = query:lower()
    for _, item in ipairs(fullItemList) do
        local displayText = item.name .. " - " .. item.count
        if displayText:lower():find(query) then
            itemList:addItem(displayText)
        end
    end
end

-- Create the main frame for the GUI
function createMainFrame()
    local mainFrame = basalt.createFrame()

    -- Initialize the list without items
    local itemList = mainFrame:addList():setScrollable(true)
        :setPosition(2, 3)
        :setSize(49, 10)

    -- Add search input field
    local searchInput = mainFrame:addInput()
        :setPosition(2, 1)
        :setSize(49, 1)
        :setDefaultText("Search...")

    -- Add amount input field for export
    local amountInput = mainFrame:addInput()
        :setPosition(2, 14)
        :setSize(10, 1)
        :setDefaultText("Amount")

    -- Add import button
    local importButton = mainFrame:addButton()
        :setPosition(2, 16)
        :setSize(10, 1)
        :setText("Import")
        :onClick(function()
            importItems()
            populateFullItemList()
            updateItemList(itemList, searchInput:getValue())
            broadcastItemList()
        end)

    -- Add export button
    local exportButton = mainFrame:addButton()
        :setPosition(14, 16)
        :setSize(10, 1)
        :setText("Export")
        :onClick(function()
            local selectedItemIndex = itemList:getItemIndex()
            if selectedItemIndex then
                local selectedItemTable = itemList:getItem(selectedItemIndex)
                if selectedItemTable and type(selectedItemTable) == "table" then
                    local selectedItem = selectedItemTable.text
                    if selectedItem and type(selectedItem) == "string" then
                        local itemName = selectedItem:match("^(.-) %- %d+$") -- Extract item name
                        local amount = tonumber(amountInput:getValue())
                        if itemName and amount then
                            local result = {removeItem(itemName, amount)}
                            populateFullItemList()
                            updateItemList(itemList, searchInput:getValue())
                            -- Re-select the previously selected item
                            itemList:selectItem(selectedItemIndex)
                            broadcastItemList()
                        end
                    end
                end
            end
        end)

    -- Add refresh button
    local refreshButton = mainFrame:addButton()
        :setPosition(26, 16)
        :setSize(10, 1)
        :setText("Refresh")
        :onClick(function()
            initDatabase()
            populateFullItemList()
            updateItemList(itemList, searchInput:getValue())
            broadcastItemList()
        end)

    -- Add button to add wireless inventory
    local wirelessButton = mainFrame:addButton()
        :setPosition(38, 16)
        :setSize(10, 1)
        :setText("Add Wireless")
        :onClick(function()
            addWirelessInventory()
        end)

    -- Populate fullItemList with all items
    populateFullItemList()

    -- Dynamically add items to the list based on the itemLocations database
    updateItemList(itemList, "")

    -- Add event to update the item list based on the search input
    searchInput:onChange(function()
        local value = searchInput:getValue() -- Ensure value is not nil
        updateItemList(itemList, value)
    end)

    mainFrame:show()
    basalt.autoUpdate()
end

function addWirelessInventory()
    local peripheralList = peripheral.getNames()
    local enderChests = {}

    for _, peripheralName in ipairs(peripheralList) do
        if peripheralName:match("enderchests:ender_chest.tile_%d+") then
            table.insert(enderChests, peripheralName)
        end
    end

    if #enderChests == 0 then
        logError("No ender chests found on the network.")
        return
    end

    logError("Ender chests found: " .. table.concat(enderChests, ", "))
    for _, enderChestName in ipairs(enderChests) do
        logError("Ender chest detected: " .. enderChestName)
        -- Command prompt to enter pocket computer ID
        term.clear()
        term.setCursorPos(1, 1)
        print("Enter pocket computer ID for ender chest " .. enderChestName .. ":")
        local pocketID = read()
        -- Link pocket computer ID to ender chest
        pocketToEnderChestMap[pocketID] = enderChestName
        savePocketToEnderChestMap()
        logError("Linked pocket computer ID " .. pocketID .. " with ender chest " .. enderChestName)
    end
end

function savePocketToEnderChestMap()
    local file = fs.open(pocketToEnderChestMapFileName, "w")
    file.write(textutils.serialize(pocketToEnderChestMap))
    file.close()
    logError("Pocket to Ender Chest map saved to " .. pocketToEnderChestMapFileName)
end

function loadPocketToEnderChestMap()
    if fs.exists(pocketToEnderChestMapFileName) then
        local file = fs.open(pocketToEnderChestMapFileName, "r")
        pocketToEnderChestMap = textutils.unserialize(file.readAll())
        file.close()
        logError("Pocket to Ender Chest map loaded from " .. pocketToEnderChestMapFileName)
    else
        savePocketToEnderChestMap() -- Create the file if it doesn't exist
    end
end

-- Check if there is enough room in the main chest
function hasEnoughRoomInMainChest(count)
    local totalFreeSlots = 0
    for slot = 1, mainChest.size() do
        local item = mainChest.getItemDetail(slot)
        if item == nil then
            totalFreeSlots = totalFreeSlots + 64
        else
            totalFreeSlots = totalFreeSlots + (64 - item.count)
        end
        if totalFreeSlots >= count then
            return true
        end
    end
    return totalFreeSlots >= count
end

-- Import items from the main chest to the network
function importItems()
    if not mainChest or #chests == 0 then
        logError("Importing failed: Required components missing.")
        return
    end
    -- Iterate over all slots in the main chest
    for slot, item in pairs(mainChest.list()) do
        if item ~= nil then -- Ensure there's an item in this slot
            -- Iterate over all chests in the network, excluding the main chest
            for _, chest in pairs(chests) do
                if chest ~= mainChest then -- Skip the main chest
                    -- Try to push the items to the current chest, ignoring how many items remain
                    mainChest.pushItems(peripheral.getName(chest), slot)
                    -- No check on remaining items, it just tries to push whatever it can
                end
            end
        end
    end
    initDatabase()
    broadcastItemList()
end

-- Remove items from the database and from the chests
function removeItem(itemName, count)
    if not mainChest then
        logError("Cannot remove items: No main chest available.")
        return 0
    end
    local totalRemoved = 0
    local slotsToRemove = {}

    -- Check if there is enough room in the main chest
    if not hasEnoughRoomInMainChest(count) then
        return 0 -- Exit early if there's not enough room in the main chest
    end

    -- Iterate over all items in the database
    for name, locations in pairs(itemLocations) do
        if name == itemName then
            -- Iterate over all slots of the current item in the current location
            for location, slots in pairs(locations) do
                for slot, itemCount in pairs(slots) do
                    if itemCount > 0 then
                        local removeCount = math.min(itemCount, count - totalRemoved)
                        local pulledCount = mainChest.pullItems(peripheral.getName(chests[location]), slot, removeCount)
                        if pulledCount > 0 then
                            totalRemoved = totalRemoved + pulledCount
                            slotsToRemove[{location, slot}] = pulledCount

                            -- Subtract the count from the database based on the pulled count
                            itemLocations[name][location][slot] = itemLocations[name][location][slot] - pulledCount
                            -- If the count becomes 0, remove the slot from the database
                            if itemLocations[name][location][slot] <= 0 then
                                itemLocations[name][location][slot] = nil
                            end
                        end

                        if totalRemoved >= count then
                            break
                        end
                    end
                end
                if totalRemoved >= count then
                    break
                end
            end
        end
        -- Remove the item from itemLocations if total count is zero
        if getTotalItemCount(locations) == 0 then
            itemLocations[name] = nil
        end
    end

    -- If we get here, the item was not found in any chest
    if totalRemoved == 0 then
        return 0
    end

    broadcastItemList()
    return totalRemoved
end

-- Function to broadcast the updated item list to all pocket computers
function broadcastItemList()
    rednet.broadcast(itemLocations, "item_list_update")
    logError("Broadcasted item list update to all pocket computers")
end

-- Function to handle requests from pocket computers
function handleRequests()
    while true do
        local senderId, message = rednet.receive()
        logError("Received message: " .. textutils.serialize(message) .. " from sender: " .. tostring(senderId))
        if message == "request_item_list" then
            rednet.send(senderId, itemLocations)
            logError("Sent item list to pocket computer with ID: " .. tostring(senderId))
        elseif type(message) == "table" and message.command == "import_items" then
            local enderChestName = pocketToEnderChestMap[tostring(senderId)]
            if not enderChestName then
                logError("Importing failed: Ender chest not found or not linked.")
            else
                local enderChest = peripheral.wrap(enderChestName)
                if not enderChest then
                    logError("Importing failed: Ender chest peripheral not found.")
                else
                    -- Iterate over all slots in the ender chest
                    for slot, item in pairs(enderChest.list()) do
                        if item ~= nil then -- Ensure there's an item in this slot
                            -- Iterate over all chests in the network, excluding the ender chest
                            for _, chest in pairs(chests) do
                                if chest ~= enderChest then -- Skip the ender chest
                                    -- Try to push the items to the current chest, ignoring how many items remain
                                    enderChest.pushItems(peripheral.getName(chest), slot)
                                    -- No check on remaining items, it just tries to push whatever it can
                                end
                            end
                        end
                    end
                    initDatabase()
                    logError("Import items command received and processed for ender chest: " .. enderChestName)
                    rednet.send(senderId, itemLocations)
                    broadcastItemList()
                end
            end
        elseif type(message) == "table" and message.command == "export_items" then
            local itemName = message.itemName
            local amount = message.amount
            local enderChestName = pocketToEnderChestMap[tostring(senderId)]
            if not enderChestName then
                logError("Exporting failed: Ender chest not found or not linked.")
            else
                local enderChest = peripheral.wrap(enderChestName)
                if not enderChest then
                    logError("Exporting failed: Ender chest peripheral not found.")
                else
                    local totalRemoved = 0
                    -- Iterate over all items in the database
                    for name, locations in pairs(itemLocations) do
                        if name == itemName then
                            -- Iterate over all slots of the current item in the current location
                            for location, slots in pairs(locations) do
                                for slot, itemCount in pairs(slots) do
                                    if itemCount > 0 then
                                        local removeCount = math.min(itemCount, amount - totalRemoved)
local sourceChestName = peripheral.getName(chests[location])
logError("Trying to move " .. removeCount .. " of " .. name .. " from " .. sourceChestName .. " slot " .. slot .. " to ender chest " .. enderChestName)

local pulledCount = enderChest.pullItems(sourceChestName, slot, removeCount)

if pulledCount and pulledCount > 0 then
    logError("Successfully pulled " .. pulledCount .. " items.")
    totalRemoved = totalRemoved + pulledCount
    itemLocations[name][location][slot] = itemLocations[name][location][slot] - pulledCount
    if itemLocations[name][location][slot] <= 0 then
        itemLocations[name][location][slot] = nil
    end
else
    logError("No items pulled. Chest may be empty, slot mismatch, or ender chest is full.")

                                            if totalRemoved >= amount then
                                                break
                                            end
                                        end
                                    end
                                end
                                if totalRemoved >= amount then
                                    break
                                end
                            end
                        end
                        if getTotalItemCount(locations) == 0 then
                            itemLocations[name] = nil
                        end
                        if totalRemoved >= amount then
                            break
                        end
                    end
                    initDatabase()
                    logError("Export items command received and processed for ender chest: " .. enderChestName)
                    rednet.send(senderId, itemLocations)
                    broadcastItemList()
                end
            end
        end
    end
end

-- Run the request handler in parallel with the main program
parallel.waitForAll(function()
    handleRequests()
end, function()
    discoverChests()
    loadDatabase()
    loadPocketToEnderChestMap()
    initDatabase()
    createMainFrame()
end)
