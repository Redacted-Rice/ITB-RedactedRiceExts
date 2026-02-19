--[[
	Memory Analyzer - Useful tool for analyzing memory changes and patterns to
	reverse engineer structures and data for memhack (or maybe memedit)
--]]

local path = GetParentPath(...)

local MemoryAnalyzer = {}
MemoryAnalyzer.__index = MemoryAnalyzer

MemoryAnalyzer.analysis = require(path .. "analysis")

local analysis = MemoryAnalyzer.analysis

-- Module level storage (following StructManager pattern)
MemoryAnalyzer._memoryAnalyzers = {}
MemoryAnalyzer._dll = nil

function MemoryAnalyzer.init(dll)
	MemoryAnalyzer._dll = dll
end

-- constructor
-- id: used to retrieve the analyzer later
-- size: number of bytes to track (i.e. the size/estimated size of the structure)
-- options: enabled, rateLimit, baseAddress, pointerChain, alignment
--    baseAddress can be overriden in capture()
--    alignment: byte alignment for change detection (1=byte, 4=4-byte groups, default 4)
function MemoryAnalyzer.new(id, size, options)
	if MemoryAnalyzer._memoryAnalyzers[id] then
		error(string.format("Memory analyzer with ID '%s' already exists", id))
	end

	options = options or {}

	local instance = setmetatable({}, MemoryAnalyzer)
	instance.id = id
	instance.size = size

	instance.baseAddress = options.baseAddress or nil
	instance.pointerChain = options.pointerChain or {}
	instance.alignment = options.alignment or 4  -- Default 4-byte alignment

	if instance.size % instance.alignment ~= 0 then
		error(string.format("Size (%d) must be divisible by alignment (%d)", instance.size, instance.alignment))
	end

	-- Enable/disable and rate limiting
	instance.enabled = options.enabled ~= false  -- Default true
	instance.rateLimit = options.rateLimit or 0  -- 0 = unlimited
	instance._lastCaptureTime = 0

	-- Capture and result storage
	instance._captures = {}
	instance._results = {}
	instance._lastBaseAddress = options.baseAddress

	MemoryAnalyzer._memoryAnalyzers[id] = instance
	return instance
end

-- Get existing analyzer by ID
function MemoryAnalyzer.get(id)
	return MemoryAnalyzer._memoryAnalyzers[id]
end

-- Remove analyzer by ID
function MemoryAnalyzer.remove(id)
	MemoryAnalyzer._memoryAnalyzers[id] = nil
end

-- List all analyzer IDs
function MemoryAnalyzer.list()
	local ids = {}
	for id, _ in pairs(MemoryAnalyzer._memoryAnalyzers) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Enable analyzer
function MemoryAnalyzer:enable()
	self.enabled = true
end

-- Disable analyzer
function MemoryAnalyzer:disable()
	self.enabled = false
end

-- Check if capture can proceed and return base address
-- Returns baseAddr on success, nil on failure
function MemoryAnalyzer:_checkCanCapture(baseAddress)
	if not self.enabled then
		LOG("Analyzer is disabled. Capture aborted.")
		return nil
	end

	if self.rateLimit > 0 then
		local now = os.time()
		if (now - self._lastCaptureTime) < self.rateLimit then
			LOG("Rate limit exceeded. Capture aborted.")
			return nil
		end
	end

	local baseAddr = baseAddress or self._lastBaseAddress
	if not baseAddr then
		error("No base address available for capture")
	end

	return baseAddr
end

-- Resolve pointer chain and return final address
function MemoryAnalyzer:_resolveAddress(baseAddr)
	local addr = baseAddr
	local chain = self.pointerChain or {}
	for i, offset in ipairs(chain) do
		local ptr = MemoryAnalyzer._dll.memory.readPointer(addr)
		if not ptr or ptr == 0 then
			error(string.format("Failed to resolve pointer at 0x%X (offset index %d)", addr, i))
		end
		addr = ptr + offset
	end
	return addr
end

-- Capture memory state if analyzer is enabled and rate limit is not exceeded
-- If baseAddress is not specified, it will use the last baseAddress set
-- Returns the capture index (1-based)
function MemoryAnalyzer:capture(baseAddress)
	local baseAddr = self:_checkCanCapture(baseAddress)
	if not baseAddr then
		-- can't capture
		return nil
	end
	self._lastCaptureTime = os.time()

	local addr = self:_resolveAddress(baseAddr)
	local data = MemoryAnalyzer._dll.memory.readByteArray(addr, self.size)
	if not data then
		error(string.format("Failed to read memory at 0x%X", addr))
	end

	local captureData = {
		timestamp = os.time(),
		address = addr,
		data = data,
		baseAddress = baseAddr
	}

	self._lastBaseAddress = baseAddr
	table.insert(self._captures, captureData)
	return #self._captures
end

-- Clear all captures and results
function MemoryAnalyzer:clear()
	self._captures = {}
	self._results = {}
end

-- Get number of captures
function MemoryAnalyzer:getCaptureCount()
	return #self._captures
end

-- Get capture by index (1-based)
function MemoryAnalyzer:getCapture(index)
	if index < 1 or index > #self._captures then
		error(string.format("Capture index %d out of range [1,%d]", index, #self._captures))
	end
	return self._captures[index]
end

-- Remove capture by index (1-based)
function MemoryAnalyzer:removeCapture(index)
	if index < 1 or index > #self._captures then
		error(string.format("Capture index %d out of range [1,%d]", index, #self._captures))
	end
	table.remove(self._captures, index)
end

-- List all captures with basic info
function MemoryAnalyzer:listCaptures()
	local captureList = {}
	for i, capture in ipairs(self._captures) do
		table.insert(captureList, {
			index = i,
			timestamp = capture.timestamp,
			address = capture.address,
			baseAddress = capture.baseAddress
		})
	end
	return captureList
end

-- Compare up to the last N captures
-- n: number of recent captures to compare (default: all)
-- includeData: if true, adds detailed value data to the result
-- resultId: optional ID to store result for later retrieval
function MemoryAnalyzer:getChanges(n, includeData, resultId)
	local result = analysis.getChanges(self._captures, self, self.id, n, includeData)

	if resultId then
		self._results[resultId] = result
	end

	return result
end

-- Find offsets where values match a condition across all captures
-- operator: ==, ~=, <, <=, >, >= (comparison operators by type)
-- targetValue: value to compare against
-- valueType: byte, int, pointer, string, bytearray
function MemoryAnalyzer:findOffsets(operator, targetValue, valueType)
	return analysis.findOffsets(self._captures, self, operator, targetValue, valueType)
end

-- Get stored result by ID
function MemoryAnalyzer:getResult(resultId)
	return self._results[resultId]
end

-- Remove stored result by ID
function MemoryAnalyzer:removeResult(resultId)
	self._results[resultId] = nil
end

-- List all stored result IDs
function MemoryAnalyzer:listResults()
	local ids = {}
	for id, _ in pairs(self._results) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Re-export analysis functions for convenience
MemoryAnalyzer.buildChangeRanges = analysis.buildChangeRanges
MemoryAnalyzer.compareChanges = analysis.compareChanges
MemoryAnalyzer.getChangedData = analysis.getChangedData
MemoryAnalyzer.logChanges = analysis.logChanges
MemoryAnalyzer.crossCheckOffsets = analysis.crossCheckOffsets
MemoryAnalyzer.compareValuesByOffset = analysis.compareValuesByOffset

return MemoryAnalyzer
