--[[
	Memory Analyzer - Useful tool for analyzing memory changes and patterns to
	reverse engineer structures and data for memhack (or maybe memedit)
--]]

local path = GetParentPath(...)

local MemoryAnalyzer = {}
MemoryAnalyzer.__index = MemoryAnalyzer

MemoryAnalyzer.Dataset = require(path .. "dataset")
MemoryAnalyzer.analysis = require(path .. "analysis")

local Dataset = MemoryAnalyzer.Dataset
local analysis = MemoryAnalyzer.analysis

-- Module level storage (following StructManager pattern)
MemoryAnalyzer._memoryAnalyzers = {}
MemoryAnalyzer._dll = nil

function MemoryAnalyzer:init(dll)
	self._dll = dll
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

	-- Datasets and current dataset
	instance._datasets = {}
	instance._currentDataset = nil

	MemoryAnalyzer._memoryAnalyzers[id] = instance
	return instance
end

-- Get existing analyzer by ID
function MemoryAnalyzer:get(id)
	return self._memoryAnalyzers[id]
end

-- Remove analyzer by ID
function MemoryAnalyzer:remove(id)
	self._memoryAnalyzers[id] = nil
end

-- List all analyzer IDs
function MemoryAnalyzer:list()
	local ids = {}
	for id, _ in pairs(self._memoryAnalyzers) do
		table.insert(ids, id)
	end
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

-- Set current dataset for captures
function MemoryAnalyzer:setCurrentDataset(name)
	if not self._datasets[name] then
		error(string.format("Dataset '%s' does not exist", name))
	end
	self._currentDataset = name
end

-- Create dataset and sets it to the current dataset
function MemoryAnalyzer:createDataset(name)
	if type(name) ~= "string" then
		error("createDataset requires a string dataset name")
	end

	if self._datasets[name] then
		error(string.format("Dataset '%s' already exists", name))
	end

	-- Create it and set it as the current dataset
	local dataset = Dataset.new(self, name)
	self._datasets[name] = dataset
	self._currentDataset = name

	return dataset
end

-- Capture to current dataset if analyzer is enabled and rate limit is not exceeded
-- If baseAddress is not specified, it will use the last baseAddress set
function MemoryAnalyzer:capture(baseAddress)
	if not self.enabled then
		LOG("Analyzer is disabled. Capture aborted.")
		return nil
	end

	if not self._currentDataset then
		error("No current dataset set. Call setCurrentDataset() or createDataset() first")
	end

	-- Check rate limit
	if self.rateLimit > 0 then
		local now = os.time()
		if (now - self._lastCaptureTime) < self.rateLimit then
			LOG("Rate limit exceeded. Capture aborted.")
			return nil
		end
		self._lastCaptureTime = now
	end

	local dataset = self._datasets[self._currentDataset]
	local result = dataset:_capture(baseAddress)
	return result
end

-- Re-export analysis functions for convenience
MemoryAnalyzer.buildChangeRanges = analysis.buildChangeRanges
MemoryAnalyzer.compareChanges = analysis.compareChanges
MemoryAnalyzer.getChangedData = analysis.getChangedData
MemoryAnalyzer.logChanges = analysis.logChanges
MemoryAnalyzer.crossCheckOffsets = analysis.crossCheckOffsets
MemoryAnalyzer.compareValuesByOffset = analysis.compareValuesByOffset

return MemoryAnalyzer
