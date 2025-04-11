-- Function to log errors to a file
function logError(message)
    local logFile = fs.open("error_log.txt", "a")
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

checkAndDownloadBasalt()

local basalt = require("basalt")
local modem = peripheral.find("modem") or error("No modem attached", 0)
rednet.open(peripheral.getName(modem))
logError("Rednet opened on modem: " .. peripheral.getName(modem))

local itemLocations = {}
local itemList, searchInput

function requestItemList()
    rednet.broadcast("request_item_list")
    logError("Sent item list request")
    local senderId, message = rednet.receive()
    logError("Received message from sender: " .. tostring(senderId))

    if type(message) == "table" and next(message) ~= nil then
        itemLocations = message
        logError("Item list updated")
        if searchInput and itemList then
            populateItemList(searchInput:getValue())
        else
            logError("Skipped update in requestItemList: GUI not ready")
        end
    else
        logError("Failed to receive valid item list: " .. textutils.serialize(message))
    end
end

function handleIncomingMessages()
    while true do
        local senderId, message, protocol = rednet.receive()
        logError("Received broadcast message from sender: " .. tostring(senderId) .. " with protocol: " .. tostring(protocol))
        if protocol == "item_list_update" and type(message) == "table" then
            logError("Updating item list from broadcast")
            itemLocations = message
            if searchInput and itemList then
                populateItemList(searchInput:getValue())
            else
                logError("Skipped broadcast update: GUI not initialized yet")
            end
        else
            logError("Received message with incorrect protocol or no message: " .. textutils.serialize(message))
        end
    end
end

function importItems(amount)
    rednet.broadcast({command = "import_items", amount = amount})
    logError("Sent import items request with amount: " .. tostring(amount))
end

function exportItems(itemName, amount)
    rednet.broadcast({command = "export_items", itemName = itemName, amount = amount})
    logError("Sent export items request with itemName: " .. itemName .. " and amount: " .. tostring(amount))
end

function populateItemList(query)
    logError("Populating item list with query: " .. query)
    itemList:clear()

    if not itemLocations or type(itemLocations) ~= "table" then
        logError("itemLocations invalid or nil")
        return
    end

    query = (query or ""):lower()
    for itemName, locations in pairs(itemLocations) do
        local totalCount = 0
        for _, slots in pairs(locations or {}) do
            for _, itemCount in pairs(slots or {}) do
                totalCount = totalCount + (itemCount or 0)
            end
        end

        local displayName = itemName:match("^.+:(.+)$") or itemName
        local visibleText = displayName .. " - " .. totalCount

        if visibleText and type(visibleText) == "string" and itemName then
            itemList:addItem(visibleText)
        else
            logError("Skipping invalid item entry: " .. tostring(itemName))
        end
    end
end

function createMainFrame()
    local mainFrame = basalt.createFrame()
    itemList = mainFrame:addList():setScrollable(true):setPosition(2, 3):setSize(49, 10)
    searchInput = mainFrame:addInput():setPosition(2, 1):setSize(49, 1):setDefaultText("Search...")
    local amountInput = mainFrame:addInput():setPosition(2, 14):setSize(10, 1):setDefaultText("Amount")

    mainFrame:addButton():setPosition(2, 15):setSize(8, 1):setText("Import")
        :onClick(function()
            local amount = tonumber(amountInput:getValue())
            if amount then
                importItems(amount)
            else
                importItems(0)
                logError("Invalid amount for import")
            end
            requestItemList()
        end)

mainFrame:addButton():setPosition(12, 15):setSize(8, 1):setText("Export")
    :onClick(function()
        local selectedItemIndex = itemList:getItemIndex()
        if selectedItemIndex then
            local selectedItem = itemList:getItem(selectedItemIndex)
            if selectedItem and selectedItem.text then
                local displayName = selectedItem.text:match("^(.-) %- ")
                local fullName = nil
                for id, _ in pairs(itemLocations) do
                    if id:match("^.+:(.+)$") == displayName then
                        fullName = id
                        break
                    end
                end

                if fullName then
                    local amount = tonumber(amountInput:getValue()) or 0
                    exportItems(fullName, amount)
                    requestItemList()
                else
                    logError("Could not resolve full item ID from display name: " .. tostring(displayName))
                end
            else
                logError("Invalid selected item or missing text field")
            end
        end
    end)


    mainFrame:addButton():setPosition(22, 15):setSize(12, 1):setText("Refresh List")
        :onClick(function()
            requestItemList()
        end)

    searchInput:onChange(function()
        local value = searchInput:getValue()
        populateItemList(value)
    end)

    populateItemList("")
    mainFrame:show()
    basalt.autoUpdate()
end

logError("Starting pocket computer program")
parallel.waitForAll(
    function()
        handleIncomingMessages()
    end,
    function()
        createMainFrame()
        requestItemList()
    end
)
