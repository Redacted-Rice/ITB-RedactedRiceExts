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
	local changedRanges, unchangedRanges = buildChangeRanges(size, function(byteIdx)
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
-- Adds value progressions to ranges
function analysis.getChangedData(result)
	if not result._captures then
		return result  -- Already has data or no captures
	end

	local captures = result._captures
	local startIdx = result._startIdx or 1

	-- Add values to changed ranges
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

	-- Add values to unchanged ranges
	for _, range in ipairs(result.unchangedRanges or {}) do
		if #captures > 0 then
			range.value = string.byte(captures[1].data, range.start + 1)
			range.address = captures[1].address + range.start
		end
	end

	return result
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
