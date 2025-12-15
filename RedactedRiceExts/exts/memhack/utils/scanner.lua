--[[
	Memory Scanner for memhack

	Each Scanner instance represents a single scan.
	Create multiple Scanner instances for concurrent scans.
--]]

local Scanner = {}
Scanner.__index = Scanner

-- Module-level dll reference (set during init)
local dll = nil

-- Scan types
Scanner.SCAN_TYPE = {
	EXACT = "exact",
	INCREASED = "increased",
	DECREASED = "decreased",
	CHANGED = "changed",
	UNCHANGED = "unchanged",
	NOT = "not"
}

-- Data types with comparison functions
Scanner.DATA_TYPE = {
	BYTE = {
		name = "byte",
		size = 1,
		read = function(addr) return dll.memory.readByte(addr) end,
		compare = function(a, b) return a == b end,
		greaterThan = function(a, b) return a > b end,
		lessThan = function(a, b) return a < b end
	},
	INT = {
		name = "int",
		size = 4,
		read = function(addr) return dll.memory.readInt(addr) end,
		compare = function(a, b) return a == b end,
		greaterThan = function(a, b) return a > b end,
		lessThan = function(a, b) return a < b end
	},
	FLOAT = {
		name = "float",
		size = 4,
		read = function(addr) return dll.memory.readFloat(addr) end,
		compare = function(a, b) return math.abs(a - b) < 0.0001 end,
		greaterThan = function(a, b) return a > b + 0.0001 end,
		lessThan = function(a, b) return a < b - 0.0001 end
	},
	DOUBLE = {
		name = "double",
		size = 8,
		read = function(addr) return dll.memory.readDouble(addr) end,
		compare = function(a, b) return math.abs(a - b) < 0.00000001 end,
		greaterThan = function(a, b) return a > b + 0.00000001 end,
		lessThan = function(a, b) return a < b - 0.00000001 end
	},
	BOOL = {
		name = "bool",
		size = 1,
		read = function(addr) return dll.memory.readBool(addr) end,
		compare = function(a, b) return a == b end,
		greaterThan = function(a, b) return a and not b end,
		lessThan = function(a, b) return not a and b end
	},
	STRING = {
		name = "string",
		size = nil,
		read = function(addr, maxLen) return dll.memory.readCString(addr, maxLen or 256) end,
		compare = function(a, b) return a == b end,
		greaterThan = function(a, b) return a > b end,
		lessThan = function(a, b) return a < b end
	}
}


-- Initialize base scanner
function Scanner.init(dllRef)
	dll = dllRef
end

-- Create a new scanner instance for a single scan
function Scanner.new(dataType, options)
	if not dll then
		error("Scanner not initialized. Call Scanner.init(dll) first.")
	end

	options = options or {}

	if not dataType or not dataType.read then
		error("Invalid data type provided to Scanner.new")
	end

	local self = setmetatable({}, Scanner)
	self.dataType = dataType
	self.results = {}
	self.isFirstScan = true
	self.maxResults = options.maxResults or 100000
	self.stringMaxLength = options.stringMaxLength or 256
	self.alignment = options.alignment or dataType.size or 1

	return self
end

-- Read value at address (handles string special case)
local function readValue(dataType, addr, stringMaxLength)
	if dataType.name == "string" then
		return dataType.read(addr, stringMaxLength)
	else
		return dataType.read(addr)
	end
end

-- Scan a single memory region
local function scanRegion(self, region, scanType, value, results)
	local addr = region.base
	local endAddr = region.base + region.size
	local resultCount = #results

	while addr < endAddr and resultCount < self.maxResults do
		local success, currentValue = pcall(readValue, self.dataType, addr, self.stringMaxLength)

		if success and currentValue ~= nil then
			if self:checkMatch(currentValue, value, scanType, nil) then
				table.insert(results, { address = addr, value = currentValue })
				resultCount = resultCount + 1

				if resultCount >= self.maxResults then
					return true -- Max results reached
				end
			end
		end

		addr = addr + self.alignment
	end

	return false -- Continue scanning
end

-- Perform initial scan across all heap regions
function Scanner:firstScan(scanType, value)
	if not self.isFirstScan then
		error("First scan already performed. Use rescan() for subsequent scans or reset to start over.")
	end

	local regions = dll.process.getHeapRegions(false)
	local results = {}

	for _, region in ipairs(regions) do
		local maxReached = scanRegion(self, region, scanType, value, results)
		if maxReached then
			break
		end
	end

	self.results = results
	self.isFirstScan = false

	return {
		resultCount = #results,
		maxResultsReached = #results >= self.maxResults
	}
end

-- Refine existing scan results
function Scanner:rescan(scanType, value)
	if self.isFirstScan then
		error("Must perform first scan before refining. Use firstScan() first.")
	end

	local newResults = {}

	for _, result in ipairs(self.results) do
		local success, currentValue = pcall(readValue, self.dataType, result.address, self.stringMaxLength)

		if success and currentValue ~= nil then
			if self:checkMatch(currentValue, value, scanType, result.value) then
				table.insert(newResults, { address = result.address, value = currentValue })
			end
		end
	end

	self.results = newResults
	return { resultCount = #newResults }
end

-- Check if a value matches the scan criteria
function Scanner:checkMatch(currentValue, targetValue, scanType, oldValue)
	if scanType == Scanner.SCAN_TYPE.EXACT then
		return self.dataType.compare(currentValue, targetValue)
	elseif scanType == Scanner.SCAN_TYPE.NOT then
		return not self.dataType.compare(currentValue, targetValue)
	elseif scanType == Scanner.SCAN_TYPE.INCREASED then
		return oldValue and self.dataType.greaterThan(currentValue, oldValue)
	elseif scanType == Scanner.SCAN_TYPE.DECREASED then
		return oldValue and self.dataType.lessThan(currentValue, oldValue)
	elseif scanType == Scanner.SCAN_TYPE.CHANGED then
		return oldValue and not self.dataType.compare(currentValue, oldValue)
	elseif scanType == Scanner.SCAN_TYPE.UNCHANGED then
		return oldValue and self.dataType.compare(currentValue, oldValue)
	end
	return false
end

-- Get scan results
function Scanner:getResults(offset, limit)
	offset = offset or 0
	limit = limit or 100

	local results = {}
	local startIdx = offset + 1
	local endIdx = math.min(offset + limit, #self.results)

	for i = startIdx, endIdx do
		table.insert(results, {
			address = self.results[i].address,
			value = self.results[i].value
		})
	end

	return {
		results = results,
		totalCount = #self.results,
		offset = offset,
		limit = limit
	}
end

-- Get result count
function Scanner:getResultCount()
	return #self.results
end

-- Reset scan to initial state
function Scanner:reset()
	self.results = {}
	self.isFirstScan = true
end

return Scanner
