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
