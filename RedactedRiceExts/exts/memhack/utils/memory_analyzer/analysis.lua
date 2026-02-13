-- Analysis functions for memory comparison results

local analysis = {}

-- Build both changed and unchanged ranges with alignment support
-- compareFunc(byteIdx) should return true if byte is changed
-- alignment: group bytes by alignment (1 = byte-by-byte, 4 = 4-byte groups, etc.)
--            helps prevent detecting single byte changes in multi-byte values
function analysis.buildChangeRanges(size, compareFunc, alignment)
	alignment = alignment or 4
	if size % alignment ~= 0 then
		error("Size ( " .. size .. " ) must be divisible by alignment ( " .. alignment .. " )")
	end

	local changedRanges = {}
	local unchangedRanges = {}

	local changedInRange = false
	local unchangedInRange = false
	local changedStart = nil
	local unchangedStart = nil

	local byteIdx = 1
	while byteIdx <= size do
		local isChanged = false
		for offset = 0, alignment - 1 do
			if compareFunc(byteIdx + offset) then
				isChanged = true
				break
			end
		end

		if isChanged then
			if not changedInRange then
				changedStart = byteIdx
				changedInRange = true
			end
			if unchangedInRange then
				local rangeEnd = byteIdx - 1
				table.insert(unchangedRanges, {
					start = unchangedStart - 1,
					endOffset = rangeEnd - 1,
					count = rangeEnd - unchangedStart + 1
				})
				unchangedInRange = false
			end
		else
			if not unchangedInRange then
				unchangedStart = byteIdx
				unchangedInRange = true
			end
			if changedInRange then
				local rangeEnd = byteIdx - 1
				table.insert(changedRanges, {
					start = changedStart - 1,
					endOffset = rangeEnd - 1,
					count = rangeEnd - changedStart + 1
				})
				changedInRange = false
			end
		end

		byteIdx = byteIdx + alignment
	end

	if changedInRange then
		table.insert(changedRanges, {
			start = changedStart - 1,
			endOffset = size - 1,
			count = size - changedStart + 1
		})
	end
	if unchangedInRange then
		table.insert(unchangedRanges, {
			start = unchangedStart - 1,
			endOffset = size - 1,
			count = size - unchangedStart + 1
		})
	end

	return changedRanges, unchangedRanges
end

-- Compare changed ranges across multiple results
-- Takes array of results (from getChanges)
-- includeData: if true, automatically adds detailed value data to the result
function analysis.compareChanges(results, includeData)
	if type(results) ~= "table" or #results == 0 then
		error("compareChanges requires array of results")
	end

	-- Use first result to determine analyzer properties
	local firstResult = results[1]
	if not firstResult._dataset then
		error("Results must contain dataset reference")
	end

	local analyzer = firstResult._dataset._analyzer
	local size = analyzer.size
	local alignment = analyzer.alignment

	-- Ensure all results use the same analyzer
	for i, result in ipairs(results) do
		if result._dataset._analyzer ~= analyzer then
			error(string.format("Result %d uses a different analyzer than first result. All results must use the same analyzer.", i))
		end
	end

	-- Merge dataset info
	local allDatasets = {}
	local allCaptures = {}
	for _, result in ipairs(results) do
		for _, dsInfo in ipairs(result.datasets) do
			table.insert(allDatasets, dsInfo)
		end
		if result._captures then
			for _, capture in ipairs(result._captures) do
				table.insert(allCaptures, capture)
			end
		end
	end

	-- Compare to find what changed across all results with alignment
	local changedRanges, unchangedRanges = analysis.buildChangeRanges(size, function(byteIdx)
		local firstValue = nil
		for _, result in ipairs(results) do
			if result._captures and #result._captures > 0 then
				local value = string.byte(result._captures[1].data, byteIdx)
				if firstValue == nil then
					firstValue = value
				elseif value ~= firstValue then
					return true
				end
			end
		end
		return false
	end, alignment)

	local result = {
		datasets = allDatasets,
		changedRanges = changedRanges,
		unchangedRanges = unchangedRanges,
		_captures = allCaptures,
		_startIdx = 1,
		_alignment = alignment
	}

	-- Automatically add data if requested
	if includeData then
		result = analysis.getChangedData(result)
	end
	return result
end

-- Get detailed value data for a result
-- Adds value progressions to ranges based on whatToAdd
-- whatToAdd can be "changed", "unchanged", or "both"/nil. Defaults to nil (both)
function analysis.getChangedData(result, whatToAdd)
	if not result._captures then
		LOG("No captures found in result")
		return result
	end

	local captures = result._captures
	local startIdx = result._startIdx or 1

	-- Determine what changes to get
	local getChanged = true
	local getUnchanged = true
	if flags == "both" or flags == nil then
		getChanged = true
		getUnchanged = true
	elseif flags == "changed" then
		getUnchanged = false
	elseif flags == "unchanged" then
		getChanged = false
	else
		LOG("flags must be 'changed', 'unchanged', 'both', or nil (default)")
		return result
	end

	-- Add values to changed ranges
	if getChanged then
		for _, range in ipairs(result.changedRanges or {}) do
			range.values = {}
			for byteOffset = range.start, range.endOffset do
				local byteIdx = byteOffset + 1
				local progression = {}
				for i, capture in ipairs(captures) do
					table.insert(progression, {
						captureIndex = startIdx + i - 1,
						value = string.byte(capture.data, byteIdx),
						address = capture.address + byteOffset
					})
				end
				table.insert(range.values, progression)
			end
		end
	end

	-- Add values to unchanged ranges
	if getUnchanged then
		for _, range in ipairs(result.unchangedRanges or {}) do
			if #captures > 0 then
				range.value = string.byte(captures[1].data, range.start + 1)
				range.address = captures[1].address + range.start
			end
		end
	end

	return result
end

-- Find the matching offset values in multiple arrays
-- Returns sorted array of offsets that appear in all input arrays
function analysis._crossCheckOffsets(offsetSets)
	if #offsetSets == 0 then
		return {}
	end
	if #offsetSets == 1 then
		return offsetSets[1]
	end
	-- Build set from first array
	local commonOffsets = {}
	for _, offset in ipairs(offsetSets[1]) do
		commonOffsets[offset] = true
	end

	-- compare with remaining arrays
	-- For each array, form a new array of all offsets that
	-- match the previous common offsets
	for i = 2, #offsetSets do
		local nextSet = {}
		for _, offset in ipairs(offsetSets[i]) do
			if commonOffsets[offset] then
				nextSet[offset] = true
			end
		end
		commonOffsets = nextSet
	end

	-- Convert back to array and sort
	local result = {}
	for offset, _ in pairs(commonOffsets) do
		table.insert(result, offset)
	end
	table.sort(result)

	return result
end

-- cross check offsets across multiple arrays to find common offsets
-- offsetArrays - array of offsets to compare to find matches
-- Returns an array of offsets present in all input arrays
function analysis.crossCheckOffsets(offsetArrays)
	if type(offsetArrays) ~= "table" or #offsetArrays == 0 then
		error("offsetArrays must be a non-empty array of offset arrays")
	end

	-- Validate that each element is an array
	for i, offsetArray in ipairs(offsetArrays) do
		if type(offsetArray) ~= "table" then
			error(string.format("offsetArrays[%d] must be an array of offsets", i))
		end
	end

	return analysis._crossCheckOffsets(offsetArrays)
end

-- Compare values based on offset across datasets using value/relative conditions
-- Supported operators by type:
--   byte & int: ==, ~=, <, <=, >, >=, increased, decreased
--   Other types: ==, ~=, changed only
-- Returns an array of offsets matching all conditions
function analysis.compareValuesByOffset(valueType, datasetDefs)
	-- Note - alignment is applied in the underlying findOffsets and _findRelativeOffsets functions
	if type(valueType) ~= "string" then
		error("valueType must be a type string (i.e. 'int' or 'byte')")
	end
	if type(datasetDefs) ~= "table" or #datasetDefs == 0 then
		error("datasetDefs must be non-empty array of specifications")
	end

	-- Find offsets for each spec
	local offsetSets = {}
	for i, datasetDef in ipairs(datasetDefs) do
		if not datasetDef.dataset then
			error(string.format("Spec %d missing 'dataset' field", i))
		end

		local offsets
		if datasetDef.relative then
			-- Validate relative type support
			if (datasetDef.relative == "increased" or datasetDef.relative == "decreased") then
				if valueType ~= "int" and valueType ~= "byte" then
					error(string.format("Relative type '%s' only supported for 'int' and 'byte'. Type '%s' only supports 'changed'", spec.relative, valueType))
				end
			end
			offsets = analysis._findRelativeOffsets(datasetDef.dataset, datasetDef.relative, valueType)
		elseif datasetDef.operator and datasetDef.val ~= nil then
			offsets = datasetDef.dataset:findOffsets(datasetDef.operator, datasetDef.val, valueType)
		else
			error(string.format("datasetDef %d must have either 'relative' or both 'operator' and 'val'", i))
		end

		table.insert(offsetSets, offsets)
	end

	return analysis._crossCheckOffsets(offsetSets)
end

-- Find typed relative offsets for int & byte types
-- Supports increased, decreased, changed
-- Uses analyzer's alignment setting to determine which offsets to check
function analysis._findTypedRelativeOffsets(dataset, relativeType, valueType)
	local size = dataset._analyzer.size
	local alignment = dataset._analyzer.alignment
	-- Only supports int & byte
	local typeSize = (valueType == "int") and 4 or 1
	local matchingOffsets = {}

	for offset = 0, size - typeSize, alignment do
		local allMatch = true
		local prevValue = nil

		for captureIdx, capture in ipairs(dataset.captures) do
			local value = dataset:_getValueAtOffset(capture.data, offset, valueType, nil)

			if captureIdx == 1 then
				prevValue = value
			else
				local matches = false
				if relativeType == "increased" then
					matches = (value > prevValue)
				elseif relativeType == "decreased" then
					matches = (value < prevValue)
				elseif relativeType == "changed" then
					matches = (value ~= prevValue)
				else
					error(string.format("Unsupported relative type: %s", relativeType))
				end

				if not matches then
					allMatch = false
					break
				end
				prevValue = value
			end
		end

		if allMatch then
			table.insert(matchingOffsets, offset)
		end
	end

	return matchingOffsets
end

-- Find byte level changed offsets for all types
-- Only supports 'changed' comparison
-- Uses analyzer's alignment setting to determine which offsets to check
function analysis._findByteChangedOffsets(dataset)
	local size = dataset._analyzer.size
	local alignment = dataset._analyzer.alignment
	local matchingOffsets = {}

	for offset = 0, size - 1, alignment do
		local byteIdx = offset + 1
		local allMatch = true
		local prevValue = string.byte(dataset.captures[1].data, byteIdx)

		for i = 2, #dataset.captures do
			local currValue = string.byte(dataset.captures[i].data, byteIdx)
			if currValue == prevValue then
				allMatch = false
				break
			end
			prevValue = currValue
		end

		if allMatch then
			table.insert(matchingOffsets, offset)
		end
	end

	return matchingOffsets
end

-- Find offsets where values changed relatively (increased/decreased/changed)
-- For byte/int: Uses typed comparison (increased/decreased/changed supported)
-- For other types: Uses byte-level comparison (only 'changed' supported)
function analysis._findRelativeOffsets(dataset, relativeType, valueType)
	if #dataset.captures < 2 then
		LOG("Need at least 2 captures for relative comparison")
		return {}
	end

	-- Validate valueType if doing increased/decreased
	if (relativeType == "increased" or relativeType == "decreased") then
		if valueType ~= "int" and valueType ~= "byte" then
			error(string.format("Relative type '%s' only supported for int/byte types", relativeType))
		end
	end

	-- Use appropriate helper based on type and operation
	if valueType == "int" or valueType == "byte" then
		return analysis._findTypedRelativeOffsets(dataset, relativeType, valueType)
	else
		-- For other types, only 'changed' supported
		if relativeType ~= "changed" then
			error(string.format("Type '%s' only supports 'changed' relative comparison", valueType))
		end
		return analysis._findByteChangedOffsets(dataset)
	end
end

-- Log changes from a result
-- If the result has value data in ranges, it will be logged
-- If not, only range information is logged
function analysis.logChanges(result, maxDisplay)
	maxDisplay = maxDisplay or 20

	-- Use result as-is, don't auto-calculate data
	local dataToLog = result

	-- Build dataset info string
	local dsNames = {}
	for _, dsInfo in ipairs(dataToLog.datasets) do
		table.insert(dsNames, dsInfo.name)
	end

	if #dataToLog.datasets == 1 then
		LOG(string.format("Dataset '%s': Found %d changed ranges",
			dsNames[1], #dataToLog.changedRanges))
	else
		LOG(string.format("Comparison: Found %d changed ranges across %d datasets",
			#dataToLog.changedRanges, #dataToLog.datasets))
		LOG("  Datasets: " .. table.concat(dsNames, ", "))
	end

	if #dataToLog.changedRanges == 0 then
		LOG("  No changes detected")
		return
	end

	local displayCount = math.min(#dataToLog.changedRanges, maxDisplay)
	for i = 1, displayCount do
		local range = dataToLog.changedRanges[i]
		if range.count == 1 then
			LOG(string.format("  [+0x%X]:", range.start))
		else
			LOG(string.format("  [+0x%X - +0x%X] (%d bytes):", range.start, range.endOffset, range.count))
		end

		-- Show values if they were added
		if range.values then
			local bytesToShow = math.min(range.count, 3)
			for j = 1, bytesToShow do
				local progression = range.values[j]
				local values = {}
				for _, v in ipairs(progression) do
					table.insert(values, string.format("0x%02X", v.value))
				end
				LOG(string.format("    +0x%X: %s", range.start + j - 1, table.concat(values, " -> ")))
			end
			if range.count > bytesToShow then
				LOG(string.format("    ... and %d more bytes in range", range.count - bytesToShow))
			end
		end
	end

	if #dataToLog.changedRanges > maxDisplay then
		LOG(string.format("  ... and %d more ranges", #dataToLog.changedRanges - maxDisplay))
	end
end

return analysis
