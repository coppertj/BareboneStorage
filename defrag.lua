-- Function to log errors to a file
function logError(message)
    local logFile = fs.open("defrag_log.txt", "a")
    logFile.writeLine(message)
    logFile.close()
end

-- Function to scan all chests for raw ores, ingots, and nuggets
function scanChests()
    local chestMap = {}
    local chests = peripheral.getNames()

    for _, chestName in ipairs(chests) do
        if peripheral.getType(chestName):match("chest") or peripheral.getType(chestName):match("barrel") then
            local chest = peripheral.wrap(chestName)
            if chest.list then
                for slot, item in pairs(chest.list()) do
                    if item.name:match("^alltheores:raw_")
                    or item.name:match("_ingot$")
                    or item.name:match("_nugget$") then

                        if not chestMap[item.name] then
                            chestMap[item.name] = {}
                        end

                        table.insert(chestMap[item.name], {
                            chest = chestName,
                            slot = slot,
                            count = item.count
                        })
                    end
                end
            end
        end
    end

    logError("Finished scanning chests.")
    return chestMap
end

-- Main logic
local consolidationPlan = scanChests()

-- Debug: Print the consolidation plan
for itemName, entries in pairs(consolidationPlan) do
    logError("Item: " .. itemName)
    for _, entry in ipairs(entries) do
        logError(" - From chest: " .. entry.chest .. " slot: " .. entry.slot .. " count: " .. entry.count)
    end
end

-- Turtle Crafting Coordinator Script
local exportBarrel = 'minecraft:barrel_4'  -- Temporary hardcoded barrel

local modem = peripheral.find('modem') or error('No modem found')
rednet.open(peripheral.getName(modem))

-- Function to log activity
local function log(message)
    local file = fs.open('crafting_log.txt', 'a')
    file.writeLine(os.date('%T') .. ' ' .. message)
    file.close()
end

-- Wait until the expected crafted block appears in the barrel
local function waitForCraftedBlock(expectedName, expectedCount)
    log('Waiting for crafted result: ' .. expectedName)
    while true do
        local items = peripheral.wrap(exportBarrel).list()
        for _, item in pairs(items) do
            if item.name == expectedName and item.count >= expectedCount then
                log('Crafted block detected: ' .. expectedName)
                return true
            end
        end
        sleep(1)
    end
end

-- Export items from the system to the crafting barrel
local function exportToCraftingBarrel(itemName, totalCount)
    log('Preparing to export for crafting: ' .. itemName .. ' x' .. totalCount)
    local exportCount = math.floor(totalCount / 9) * 9
    if exportCount == 0 then return false end

    if not fs.exists('database.txt') then error('No item database found!') end
    local db = fs.open('database.txt', 'r')
    local itemLocations = textutils.unserialize(db.readAll())
    db.close()

    local itemSlots = itemLocations[itemName]
    local transferred = 0

    for chestIndex, slots in pairs(itemSlots or {}) do
        local chestName = peripheral.getNames()[chestIndex]
        local chest = peripheral.wrap(chestName)
        for slot, count in pairs(slots) do
            local sendCount = math.min(9 - (transferred % 9), count, exportCount - transferred)
            if sendCount > 0 then
                chest.pushItems(exportBarrel, slot, sendCount)
                transferred = transferred + sendCount
                if transferred >= exportCount then
                    log('Export complete: ' .. transferred .. ' of ' .. itemName)
                    return true
                end
            end
        end
    end
    return false
end

-- Process a list of items from craft_queue.txt and convert them via the turtle
local function runCraftingQueue()
    if not fs.exists('craft_queue.txt') then
        log('No craft queue found.')
        return
    end
    local f = fs.open('craft_queue.txt', 'r')
    local queue = textutils.unserialize(f.readAll())
    f.close()

    for _, item in ipairs(queue) do
        local itemName = item.name
        local count = item.count
        local resultName = itemName:gsub('_nugget', '_block'):gsub('_ingot', '_block'):gsub('raw_', 'raw_block_')
        if exportToCraftingBarrel(itemName, count) then
            waitForCraftedBlock(resultName, 1)
            log('Importing crafted blocks into the system...')
            peripheral.call(exportBarrel, 'pushItems', 'mainChest') -- Adjust target as needed
        else
            log('Export failed for ' .. itemName)
        end
    end
end

runCraftingQueue()

