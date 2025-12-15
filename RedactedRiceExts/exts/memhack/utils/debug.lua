-- Debug utilities for memhack
-- Provides formatting and memory inspection functions

local Debug = {}

-- Initialize the debug utilities with a DLL instance
function Debug.init(dll)
	Debug._dll = dll
	return Debug

-- Convert a hex string to an integer
-- Supports both "0x1A" and "1A" format
function Debug.hexToInt(hexstr)
    if type(hexstr) ~= "string" then
        error("hexToInt expects a string, got " .. type(hexstr))
    end

    if string.sub(hexstr, 1, 2) == "0x" or string.sub(hexstr, 1, 2) == "0X" then
        return tonumber(hexstr)  -- Lua understands "0x.." prefix
    else
        return tonumber(hexstr, 16)
    end
end

-- Convert an integer to a hex string (like 26 -> "0x1A")
function Debug.intToHex(num)
    return string.format("0x%X", num)
end

-- Convert a byte array to a hex string representation
-- bytes array (table) of bytes
-- bytesPerGroup optional, number of bytes before space separator (default: 0, no grouping)
function Debug.bytesToHex(bytes, bytesPerGroup)
    local groups = {}
	if not bytesPerGroup or bytesPerGroup == 0 then
		-- No grouping, space between each byte
		local hexStr = {}
		for i, byte in ipairs(bytes) do
			table.insert(groups, string.format("%02X", byte))
		end
	else
		-- Group bytes with spaces between groups
		local currentGroup = {}
		for i, byte in ipairs(bytes) do
			table.insert(currentGroup, string.format("%02X", byte))

			-- If we've reached the group size, add to groups and start new group
			if #currentGroup == bytesPerGroup then
				table.insert(groups, table.concat(currentGroup, ""))
				currentGroup = {}
			end
		end

		-- Add any remaining bytes in the last group
		if #currentGroup > 0 then
			table.insert(groups, table.concat(currentGroup, ""))
		end
	end
    return table.concat(hexStr, " ")
end

-- Convert hex string to bytes
-- hexStr Handles spaces "01020304", "01 0203 04", etc.
-- Returns array(table) of byte values
function Debug.hexToBytes(hexStr)
	-- Remove spaces and 0x prefix if present
	hexStr = hexStr:gsub("%s+", ""):gsub("^0[xX]", "")

	if #hexStr % 2 ~= 0 then
		error("Hex string must have even number of characters")
	end

	local bytes = {}
	for i = 1, #hexStr, 2 do
		local byteStr = hexStr:sub(i, i + 1)
		bytes[#bytes + 1] = tonumber(byteStr, 16)
	end
	return bytes
end

-- Log memory contents from a given address for a specified number of bytes
-- address integer memory address to start reading from
-- numBytes number of bytes to read
-- bytesPerLine optional, number of bytes to display per line (default 64)
-- bytesPerGroup optional, number of bytes before space separator (default 4)
function Debug.logFromMemory(address, numBytes, bytesPerLine, bytesPerGroup)
	if not Debug._dll then
		error("Debug utilities not initialized. Call Debug.init() first")
	end

	bytesPerLine = bytesPerLine or 64
	bytesPerGroup = bytesPerGroup or 4

	if numBytes <= 0 then
		LOG("No bytes to read")
		return
	end

	-- Read the memory
	local bytes = Debug._dll.memory.readBytes(address, numBytes)
	if not bytes then
		LOG(string.format("Failed to read memory at address 0x%X", address))
		return
	end

	-- Log header
	LOG(string.format("Memory dump from 0x%X (%d bytes):", address, numBytes))

	-- Log each line individually. LOG does not seem to like newline
	for i = 1, numBytes, bytesPerLine do
		-- Extract bytes for this line
		local lineBytes = {}
		for j = 0, bytesPerLine - 1 do
			local byteIndex = i + j
			if byteIndex <= numBytes then
				table.insert(lineBytes, bytes[byteIndex])
			end
		end

		-- Log address and the bytes for that line
		local hexPart = Debug.bytesToHex(lineBytes, bytesPerGroup)
		local offsetAddr = address + (i - 1)
		local line = string.format("0x%08X: %s", offsetAddr, hexPart)

		LOG(line)
	end
end

return Debug

