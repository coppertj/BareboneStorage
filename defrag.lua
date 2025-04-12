
-- Auto-generated defrag + crafting coordinator

-- Logging
function logError(message)
    local file = fs.open("defrag_log.txt", "a")
    file.writeLine("[" .. os.date("%T") .. "] " .. message)
    file.close()
end

-- Turtle Crafting Logger
function logCraft(message)
    local file = fs.open("crafting_log.txt", "a")
    file.writeLine("[" .. os.date("%T") .. "] " .. message)
    file.close()
end

-- Globals
local exportBarrel = "minecraft:barrel_4"
local fileName = "database.txt"
local itemLocations = {}
local chests = {}
local mainChest = nil

-- Discover chests
function discoverChests()
    local peripherals = peripheral.getNames()
    local index = 1
    logError("Discovering peripherals...")
    for _, name in ipairs(peripherals) do
        local pType = peripheral.getType(name)
        logError("Found peripheral: " .. name .. " of type " .. pType)
        if pType == "minecraft:barrel" then
            mainChest = peripheral.wrap(name)
            logError("Designated main chest: " .. name)
        elseif pType == "minecraft:chest"
            or pType:match("^ironchests:")
            or pType:match("^quark:")
            or pType:match("^sophisticatedstorage:") then
            chests[index] = peripheral.wrap(name)
            index = index + 1
        end
    end
    if not mainChest then
        logError("Warning: No barrel found for main chest.")
    end
end

-- Build the database
function initDatabase()
    itemLocations = {}
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

function saveDatabase()
    local file = fs.open(fileName, "w")
    file.write(textutils.serialize(itemLocations))
    file.close()
end

function loadDatabase()
    if fs.exists(fileName) then
        local file = fs.open(fileName, "r")
        itemLocations = textutils.unserialize(file.readAll())
        file.close()
        logError("Database loaded from " .. fileName)
    else
        saveDatabase()
    end
end

-- Scan for craftable ores/ingots/nuggets
function scanChests()
    local chestMap = {}
    for _, chest in pairs(chests) do
        if chest.list then
            for slot, item in pairs(chest.list()) do
                if item.name:match("^alltheores:raw_")
                    or item.name:match("_ingot$")
                    or item.name:match("_nugget$") then

                    chestMap[item.name] = chestMap[item.name] or {}
                    table.insert(chestMap[item.name], {slot = slot, count = item.count})
                end
            end
        end
    end
    return chestMap
end

-- Export for crafting
function exportToCraftingBarrel(itemName, totalCount)
    local exportCount = math.floor(totalCount / 9) * 9
    if exportCount == 0 then return false end
    logCraft("Exporting " .. itemName .. " x" .. exportCount)
    local transferred = 0
    for chestIndex, slots in pairs(itemLocations[itemName] or {}) do
        local chestName = peripheral.getNames()[chestIndex]
        local chest = peripheral.wrap(chestName)
        for slot, count in pairs(slots) do
            local send = math.min(9 - (transferred % 9), count, exportCount - transferred)
            if send > 0 then
                chest.pushItems(exportBarrel, slot, send)
                transferred = transferred + send
                if transferred >= exportCount then return true end
            end
        end
    end
    return false
end

function waitForCraftedBlock(expectedName, expectedCount)
    logCraft("Waiting for result: " .. expectedName)
    while true do
        for _, item in pairs(peripheral.wrap(exportBarrel).list()) do
            if item.name == expectedName and item.count >= expectedCount then
                logCraft("Detected crafted: " .. expectedName)
                return true
            end
        end
        sleep(1)
    end
end

function runCraftingQueue()
    if not fs.exists("craft_queue.txt") then
        logCraft("No craft queue found.")
        return
    end
    local f = fs.open("craft_queue.txt", "r")
    local queue = textutils.unserialize(f.readAll())
    f.close()

    for _, item in ipairs(queue) do
        local name, count = item.name, item.count
        local result = name:gsub("_nugget", "_block"):gsub("_ingot", "_block"):gsub("raw_", "raw_block_")
        if exportToCraftingBarrel(name, count) then
            waitForCraftedBlock(result, 1)
            logCraft("Attempting reimport into system...")
            peripheral.call(exportBarrel, "pushItems", peripheral.getName(mainChest))
        else
            logCraft("Export failed for " .. name)
        end
    end
end

-- Start
discoverChests()
initDatabase()
saveDatabase()

local scan = scanChests()
for item, list in pairs(scan) do
    logError("Detected " .. item)
end

runCraftingQueue()
