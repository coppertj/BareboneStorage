local barrelName = "minecraft:barrel_4"

-- Wrap the barrel once
local barrel = peripheral.wrap(barrelName)
if not barrel then error("Export barrel not found!") end

-- Function to log errors
local function logError(msg)
    local f = fs.open("transfer_log.txt", "a")
    f.writeLine(msg)
    f.close()
end

-- Load defrag_log.txt
if not fs.exists("defrag_log.txt") then
    error("defrag_log.txt not found.")
end

local entries = {}
local f = fs.open("defrag_log.txt", "r")
while true do
    local line = f.readLine()
    if not line then break end

    -- Match the log line for item info
    local item, chest, slot, count = line:match("Item: ([%w_:]+).*From chest: ([%w_:%.%-]+) slot: (%d+) count: (%d+)")
    if item and chest and slot and count then
        table.insert(entries, {
            item = item,
            chest = chest,
            slot = tonumber(slot),
            count = tonumber(count)
        })
    end
end
f.close()

-- Begin transfers
for _, entry in ipairs(entries) do
    local chest = peripheral.wrap(entry.chest)
    if chest and chest.pushItems then
        local moved = chest.pushItems(peripheral.getName(barrel), entry.slot, entry.count)
        logError("Moved " .. moved .. " of " .. entry.item .. " from " .. entry.chest .. " slot " .. entry.slot)
    else
        logError("Error wrapping chest: " .. tostring(entry.chest))
    end
end
