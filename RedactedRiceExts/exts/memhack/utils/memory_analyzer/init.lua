--[[
	Memory Analyzer - Useful tool for analyzing memory changes and patterns to
	reverse engineer structures and data for memhack (or maybe memedit)
--]]

local path = GetParentPath(...)

local MemoryAnalyzer = {}
MemoryAnalyzer.__index = MemoryAnalyzer

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("memhack", "MemAnalyzer", false)

-- Load analysis submodules
local comparison = require(path .. "comparison")
local values = require(path .. "values")
local logging = require(path .. "logging")

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
		logger.logError(SUBMODULE, "Memory analyzer with ID '%s' already exists", id)
		return nil
	end

	options = options or {}

	local instance = setmetatable({}, MemoryAnalyzer)
	instance.id = id
	instance.size = size

	instance.baseAddress = options.baseAddress or nil
	instance.pointerChain = options.pointerChain or {}
	instance.alignment = options.alignment or 4  -- Default 4-byte alignment

	if instance.size % instance.alignment ~= 0 then
		logger.logError(SUBMODULE, "Size (%d) must be divisible by alignment (%d)", instance.size, instance.alignment)
		return nil
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
		logger.logWarn(SUBMODULE, "Analyzer is disabled. Capture aborted.")
		return nil
	end

	if self.rateLimit > 0 then
		local now = os.time()
		if (now - self._lastCaptureTime) < self.rateLimit then
			logger.logWarn(SUBMODULE, "Rate limit exceeded. Capture aborted.")
			return nil
		end
	end

	local baseAddr = baseAddress or self._lastBaseAddress
	if not baseAddr then
		logger.logError(SUBMODULE, "No base address available for capture")
		return nil
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
			logger.logError(SUBMODULE, "Failed to resolve pointer at 0x%X (offset index %d)", addr, i)
			return nil
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
	if not addr then
		return nil
	end
	
	local data = MemoryAnalyzer._dll.memory.readByteArray(addr, self.size)
	if not data then
		logger.logError(SUBMODULE, "Failed to read memory at 0x%X", addr)
		return nil
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
		logger.logError(SUBMODULE, "Capture index %d out of range [1,%d]", index, #self._captures)
		return nil
	end
	return self._captures[index]
end

-- Remove capture by index (1-based)
function MemoryAnalyzer:removeCapture(index)
	if index < 1 or index > #self._captures then
		logger.logError(SUBMODULE, "Capture index %d out of range [1,%d]", index, #self._captures)
		return false
	end
	table.remove(self._captures, index)
	return true
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

-- Compare captures - changed at least once
-- captureIndices: array of indices, number for last N, or nil for all
-- resultId: optional ID to store result for later retrieval
-- Returns: {filtered=ranges that changed, unfiltered=ranges that didn't}
function MemoryAnalyzer:getChangedOnce(captureIndices, resultId)
	local result = comparison.getChangedOnce(self._captures, captureIndices, self, self.id)
	if result and resultId then
		self._results[resultId] = result
	end
	return result
end

-- Compare captures - changed in every transition
-- captureIndices: array of indices, number for last N, or nil for all
-- resultId: optional ID to store result for later retrieval
-- Returns: {filtered=ranges that changed every time, unfiltered=ranges that didn't}
function MemoryAnalyzer:getChangedEvery(captureIndices, resultId)
	local result = comparison.getChangedEvery(self._captures, captureIndices, self, self.id)
	if result and resultId then
		self._results[resultId] = result
	end
	return result
end

-- Compare captures - never changed
-- captureIndices: array of indices, number for last N, or nil for all
-- resultId: optional ID to store result for later retrieval
-- Returns: {filtered=ranges that never changed, unfiltered=ranges that did}
function MemoryAnalyzer:getUnchanged(captureIndices, resultId)
	local result = comparison.getUnchanged(self._captures, captureIndices, self, self.id)
	if result and resultId then
		self._results[resultId] = result
	end
	return result
end

-- Compare captures with custom comparator
-- captureIndices: array of indices, number for last N, or nil for all
-- comparatorFunc: function(selectedCaptures, byteIdx) -> bool (true if matches filter)
-- resultId: optional ID to store result for later retrieval
-- Returns: {filtered=ranges that match comparator, unfiltered=ranges that don't}
function MemoryAnalyzer:getCustomChanges(captureIndices, comparatorFunc, resultId)
	local result = comparison.getCustomChanges(self._captures, captureIndices, self, self.id, comparatorFunc)
	if result and resultId then
		self._results[resultId] = result
	end
	return result
end

-- Search for offsets matching a value pattern across captures
-- pattern: array with exact values, nil (any value), or wildcard names (strings starting with "$")
--   - Exact values: numeric values that must match exactly
--   - nil: unnamed wildcard, matches any value
--   - "$name": named wildcard, must be consistent wherever the same name appears
--
-- captureIndices: array of indices, number for last N, or nil for all (must match pattern length)
-- resultId: optional ID to store result for later retrieval
-- Returns: {filtered=ranges matching pattern, unfiltered=ranges not matching}
function MemoryAnalyzer:getMatchingPattern(pattern, captureIndices, resultId)
	local result = comparison.getMatchingPattern(self._captures, pattern, captureIndices, self, self.id)
	if result and resultId then
		self._results[resultId] = result
	end
	return result
end

-- Add all value progressions to result (shows every value for each chunk)
-- result: result object or resultId string
-- ranges: "filtered" (default), "unfiltered", or "both"
-- Common helper for add* functions - handles result lookup and storage
function MemoryAnalyzer:_addDataHelper(result, analysisFunc, ranges)
	ranges = ranges or "filtered"

	local resultId = nil
	if type(result) == "string" then
		resultId = result
		result = self._results[resultId]
		if not result then
			logger.logError(SUBMODULE, "Result ID not found: %s", resultId)
			return nil
		end
	end

	result = analysisFunc(result, ranges)

	if resultId then
		self._results[resultId] = result
	end

	return result
end

-- Add all value progressions to result (shows every value for each chunk)
-- result: result object or resultId string
-- ranges: "filtered" (default), "unfiltered", or "both"
function MemoryAnalyzer:addAllCapturesValues(result, ranges)
	return self:_addDataHelper(result, values.addAllCapturesValues, ranges)
end

-- Add changed value progressions to result (only shows when value changes)
-- result: result object or resultId string
-- ranges: "filtered" (default), "unfiltered", or "both"
function MemoryAnalyzer:addChangedCapturesValues(result, ranges)
	return self:_addDataHelper(result, values.addChangedCapturesValues, ranges)
end

-- Add unique value counts to result
-- result: result object or resultId string
-- ranges: "filtered" (default), "unfiltered", or "both"
function MemoryAnalyzer:addUniqueCapturesValues(result, ranges)
	return self:_addDataHelper(result, values.addUniqueCapturesValues, ranges)
end

-- Log a result (displays whatever data has been added via add* functions)
-- result: result object or resultId string
-- Logs all ranges and all data without limits
function MemoryAnalyzer:log(result)
	if type(result) == "string" then
		result = self._results[result]
		if not result then
			logger.logError(SUBMODULE, "Result ID not found")
			return
		end
	end

	if not result then
		logger.logError(SUBMODULE, "Result is nil")
		return
	end

	logging.logChanges(result)
end

-- Filter a result based on custom criteria
-- result: result object or resultId string
-- filterSpec: filter specification (see comparison.filterResult for details)
--   Range-level: function(range, captures) -> bool
--   Chunk-level: {alignment=N, filter=function(offset, values) -> bool, ranges="filtered"}
--     values are alignment-sized (byte/short/int depending on alignment)
-- resultId: optional ID to store filtered result
-- Returns new result with only ranges/chunks that pass the filter
function MemoryAnalyzer:filterResult(result, filterSpec, resultId)
	if type(result) == "string" then
		result = self._results[result]
		if not result then
			logger.logError(SUBMODULE, "Result ID not found")
			return nil
		end
	end

	local filtered = comparison.filterResult(result, filterSpec)
	if resultId then
		self._results[resultId] = filtered
	end
	return filtered
end

return MemoryAnalyzer
