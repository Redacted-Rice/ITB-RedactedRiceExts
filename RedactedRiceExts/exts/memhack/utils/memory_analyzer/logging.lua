-- Logging functions for analysis results

local logger = memhack.logger
local SUBMODULE = logger.register("memhack", "MemAnalyzer.logging", false)

local logging = {}

-- Helper to check if ranges have any data associated with them
local function rangesHaveData(ranges)
	for i = 1, #ranges do
		local range = ranges[i]
		if (range.values and #range.values > 0) or (range.uniqueValues and #range.uniqueValues > 0) then
			return true
		end
	end
	return false
end

-- Helper to log a set of ranges with their data
local function logRanges(ranges, rangeType, result, alignment, formatStr)
	for i = 1, #ranges do
		local range = ranges[i]
		logger.logInfo(SUBMODULE, "    [0x%X - 0x%X] (%d bytes)", range.start, range.endOffset, range.count)

		if range.values then
			for j = 1, #range.values do
				local progression = range.values[j]
				local values = {}
				for _, v in ipairs(progression) do
					table.insert(values, string.format(formatStr, v.value))
				end
				-- progression[1].address is the actual address for this chunk
				local chunkOffset = progression[1] and (progression[1].address - result._captures[1].address) or (range.start + (j-1) * alignment)
				logger.logInfo(SUBMODULE, "      0x%X: %s", chunkOffset, table.concat(values, " -> "))
			end
		end

		if range.uniqueValues then
			for j = 1, #range.uniqueValues do
				local uniqueData = range.uniqueValues[j]
				local valueStrs = {}
				for _, vCount in ipairs(uniqueData.values) do
					table.insert(valueStrs, string.format(formatStr .. "(%d)", vCount.value, vCount.count))
				end
				logger.logInfo(SUBMODULE, "      0x%X: %s", uniqueData.offset, table.concat(valueStrs, ", "))
			end
		end
	end
end

-- Log changes from a result (logs everything - all ranges, all data)
function logging.logChanges(result)

	local name = result.name or "Unknown"
	local captureIndices = result.captureIndices or {}
	local alignment = result._alignment or 4

	local filteredRanges = result.filtered or {}
	local unfilteredRanges = result.unfiltered or {}

	-- Determine format string based on alignment
	local formatStr = "0x%02X"  -- byte
	if alignment == 2 then
		formatStr = "0x%04X"  -- short
	elseif alignment == 4 then
		formatStr = "0x%08X"  -- int/pointer
	end

	-- Check which sections have data
	local filteredHasData = rangesHaveData(filteredRanges)
	local unfilteredHasData = rangesHaveData(unfilteredRanges)
	
	-- Decide what to print:
	-- Both have data or neither has data -> print both
	-- Only one has data -> print only that one
	local printFiltered = (#filteredRanges > 0) and (filteredHasData or not unfilteredHasData)
	local printUnfiltered = (#unfilteredRanges > 0) and (unfilteredHasData or not filteredHasData)

	logger.logInfo(SUBMODULE, "Analyzer '%s' (captures: [%s], alignment: %d): %d filtered ranges, %d unfiltered ranges",
		name, table.concat(captureIndices, ","), alignment, #filteredRanges, #unfilteredRanges)

	if printFiltered then
		logger.logInfo(SUBMODULE, "  Filtered Ranges (%d total):", #filteredRanges)
		logRanges(filteredRanges, "filtered", result, alignment, formatStr)
	end

	if printUnfiltered then
		logger.logInfo(SUBMODULE, "  Unfiltered Ranges (%d total):", #unfilteredRanges)
		logRanges(unfilteredRanges, "unfiltered", result, alignment, formatStr)
	end
end

return logging
