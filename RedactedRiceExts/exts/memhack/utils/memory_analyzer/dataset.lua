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
		local ptr = MemoryAnalyzer._dll.memory.readPointer(addr)
		if not ptr or ptr == 0 then
			error(string.format("Failed to resolve pointer at 0x%X (offset index %d)", addr, i))
		end
		addr = ptr + offset
	end

	local data = MemoryAnalyzer._dll.memory.readByteArray(addr, self._analyzer.size)
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

return Dataset
