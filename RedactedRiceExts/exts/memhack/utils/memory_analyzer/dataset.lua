-- Dataset for memory analysis
-- Stores and compares memory captures

local Dataset = {}
Dataset.__index = Dataset

function Dataset.new(analyzer, name)
	local self = setmetatable({}, Dataset)
	self._analyzer = analyzer
	self.name = name
	self.captures = {}

	-- Initialize with analyzer defaults
	self._lastBaseAddress = analyzer.baseAddress

	return self
end

-- Capture memory state now ignoring any enabled/rate limit checks
function Dataset:_capture(baseAddress)
	-- Use provided baseAddress or fall back to last one
	local baseAddr = baseAddress or self._lastBaseAddress
	if not baseAddr then
		error("No base address available for capture")
	end

	-- Follow pointer chain if configured
	local addr = baseAddr
	local chain = self._analyzer.pointerChain or {}
	for i, offset in ipairs(chain) do
		local ptr = self._analyzer._dll.memory.readPointer(addr)
		if not ptr or ptr == 0 then
			error(string.format("Failed to resolve pointer at 0x%X (offset index %d)", addr, i))
		end
		addr = ptr + offset
	end

	local data = self._analyzer._dll.memory.readByteArray(addr, self._analyzer.size)
	if not data then
		error(string.format("Failed to read memory at 0x%X", addr))
	end

	local captureData = {
		timestamp = os.time(),
		address = addr,
		data = data,
		baseAddress = baseAddr
	}

	-- Remember this base address for next capture
	self._lastBaseAddress = baseAddr

	table.insert(self.captures, captureData)
	local result = #self.captures
	return result
end

-- Compare up to the last N captures within this dataset
-- n: number of recent captures to compare (default: all)
-- includeData: if true, automatically adds detailed value data to the result
function Dataset:getChanges(n, includeData)
	local count = #self.captures

	if n == nil or n <= 0 then
		n = count
	end

	if count < 2 then
		error("Need at least 2 captures to compare")
	end

	-- Handle case where n > count - use all captures with warning
	if n > count then
		LOG(string.format("Warning: Requested %d captures but only %d available. Using all captures.", n, count))
		n = count
	end

	local startIdx = math.max(1, count - n + 1)
	local captures = {}
	for i = startIdx, count do
		table.insert(captures, self.captures[i])
	end

	-- Build changed and unchanged ranges
	local changedRanges, unchangedRanges = self._analyzer.buildChangeRanges(self._analyzer.size,
			function(byteIdx)
				local firstValue = string.byte(captures[1].data, byteIdx)
				for i = 2, #captures do
					if string.byte(captures[i].data, byteIdx) ~= firstValue then
						return true  -- Changed
					end
				end
				return false  -- Unchanged
			end, self._analyzer.alignment
	)

	-- Formulate into results structure
	local result = {
		datasets = {{name = self.name, captureIndices = {startIdx, count}}},
		changedRanges = changedRanges,
		unchangedRanges = unchangedRanges,
		_captures = captures,
		_startIdx = startIdx,
		_dataset = self,
		_alignment = self._analyzer.alignment
	}

	-- Automatically add data if requested
	if includeData then
		result = self._analyzer.getChangedData(result)
	end
	return result
end

-- Reads the value from data at offset with specified type
-- Supports byte, int, and pointer types for value comparison
function Dataset:_getValueAtOffset(data, offset, valueType, typeLength)
	local byteIdx = offset + 1

	if valueType == "byte" then
		return string.byte(data, byteIdx)
	elseif valueType == "int" or valueType == "pointer" then
		if byteIdx + 3 > #data then return nil end
		local b1, b2, b3, b4 = string.byte(data, byteIdx, byteIdx + 3)
		-- Interpret as little-endian
		local value = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
		-- For int, treat as signed; for pointer, treat as unsigned
		if valueType == "int" and value >= 0x80000000 then
			value = value - 0x100000000
		end
		return value
	else
		error(string.format("_getValueAtOffset only supports 'byte', 'int', and 'pointer' types, got '%s'", valueType))
	end
end

-- Compare values based on passed operator string
function Dataset:_compareValues(value, operator, target)
	if operator == "==" then
		return value == target
	elseif operator == "~=" then
		return value ~= target
	elseif operator == "<" then
		return value < target
	elseif operator == "<=" then
		return value <= target
	elseif operator == ">" then
		return value > target
	elseif operator == ">=" then
		return value >= target
	else
		error(string.format("Unsupported operator: %s (use Lua syntax: ==, ~=, <, <=, >, >=)", operator))
	end
end

-- Get type size in bytes
function Dataset:_getTypeSize(valueType, targetValue)
	if valueType == "byte" then
		return 1
	elseif valueType == "int" or valueType == "pointer" then
		return 4
	elseif valueType == "bytearray" then
		-- For byte arrays, size is the length of the target value
		if type(targetValue) == "string" then
			return #targetValue
		else
			error("bytearray type requires target value to be a string")
		end
	elseif valueType == "string" then
		-- For strings, size is the length of the target value + 1 (for null terminator)
		if type(targetValue) == "string" then
			return #targetValue + 1
		else
			error("string type requires target value to be a string")
		end
	else
		error(string.format("Unsupported type '%s'. Supported types: byte, int, pointer, string, bytearray", valueType))
	end
end

-- Find offsets where values match a condition
-- Uses analyzer's alignment setting to determine which offsets to check
-- Supported operators by type:
--   byte/int/pointer: ==, ~=, <, <=, >, >=  (full comparison support)
--   string/bytearray: ==, ~=  (equality only, raw byte comparison)
-- Returns an array of offsets (0-based) that match across all captures
function Dataset:findOffsets(operator, targetValue, valueType)
	if #self.captures == 0 then
		error("No captures available in dataset")
	end

	-- Validate operator for type
	local comparisonOps = {"<", "<=", ">", ">="}
	local isComparisonOp = false
	for _, op in ipairs(comparisonOps) do
		if operator == op then
			isComparisonOp = true
			break
		end
	end

	if isComparisonOp and valueType ~= "int" and valueType ~= "byte" and valueType ~= "pointer" then
		error(string.format("Operator '%s' only supported for 'int', 'byte', and 'pointer' types. Type '%s' only supports '==' and '~='", operator, valueType))
	end

	local size = self._analyzer.size
	local alignment = self._analyzer.alignment

	-- Handle hex string conversion for bytearray
	if valueType == "bytearray" and type(targetValue) == "string" then
		targetValue = memhack.debug.hexToBytes(targetValue)
	end

	local typeSize = self:_getTypeSize(valueType, targetValue)
	local matchingOffsets = {}

	-- For byte/int/pointer types, use typed value comparison
	if valueType == "byte" or valueType == "int" or valueType == "pointer" then
		for offset = 0, size - typeSize, alignment do
			local allMatch = true
			for _, capture in ipairs(self.captures) do
				local value = self:_getValueAtOffset(capture.data, offset, valueType, nil)
				if not value or not self:_compareValues(value, operator, targetValue) then
					allMatch = false
					break
				end
			end
			if allMatch then
				table.insert(matchingOffsets, offset)
			end
		end
	elseif valueType == "string" or valueType == "bytearray" then
		-- For string/bytearray, compare raw bytes (only == and ~= supported)
		if operator ~= "==" and operator ~= "~=" then
			error(string.format("Type '%s' only supports '==' and '~=' operators", valueType))
		end

		local targetBytes
		if valueType == "string" then
			targetBytes = targetValue .. "\0"
		elseif valueType == "bytearray" then
			targetBytes = targetValue
		end

		-- Compare byte sequences
		for offset = 0, size - typeSize, alignment do
			local allMatch = true
			for _, capture in ipairs(self.captures) do
				local dataBytes = string.sub(capture.data, offset + 1, offset + typeSize)
				local matches = (dataBytes == targetBytes)
				if operator == "~=" then
					matches = not matches
				end
				if not matches then
					allMatch = false
					break
				end
			end
			if allMatch then
				table.insert(matchingOffsets, offset)
			end
		end
	else
		error(string.format("Unsupported type '%s' for findOffsets. Supported types: byte, int, pointer, string, bytearray", valueType))
	end

	return matchingOffsets
end

return Dataset
