-- Analysis functions for memory comparison results

local analysis = {}

-- Read value based on alignment size
-- alignment: 1 (byte), 2 (short), 4 (int/pointer)
function analysis._readAlignedValue(data, offset, alignment)
	local byteIdx = offset + 1

	if alignment == 1 then
		return string.byte(data, byteIdx)
	elseif alignment == 2 then
		if byteIdx + 1 > #data then return nil end
		local b1, b2 = string.byte(data, byteIdx, byteIdx + 1)
		return b1 + b2 * 256
	elseif alignment == 4 then
		if byteIdx + 3 > #data then return nil end
		local b1, b2, b3, b4 = string.byte(data, byteIdx, byteIdx + 3)
		return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
	else
		error(string.format("Unsupported alignment: %d (use 1, 2, or 4)", alignment))
	end
end

-- Parse capture indices into array
-- captureIndices: array of indices, number for last N, or nil for all
-- totalCount: total number of captures available
-- Returns array of 1-based indices
function analysis._parseCaptureIndices(captureIndices, totalCount)
	local indices = {}

	if captureIndices == nil then
		for i = 1, totalCount do
			table.insert(indices, i)
		end
	elseif type(captureIndices) == "number" then
		local n = captureIndices
		if n <= 0 then n = totalCount end
		if n > totalCount then
			LOG(string.format("Warning: Requested %d captures but only %d available. Using all captures.", n, totalCount))
			n = totalCount
		end
		local startIdx = math.max(1, totalCount - n + 1)
		for i = startIdx, totalCount do
			table.insert(indices, i)
		end
	elseif type(captureIndices) == "table" then
		for _, idx in ipairs(captureIndices) do
			if idx < 1 or idx > totalCount then
				error(string.format("Capture index %d out of range [1,%d]", idx, totalCount))
			end
			table.insert(indices, idx)
		end
	else
		error("captureIndices must be nil, number, or array of indices")
	end

	return indices
end

-- Core comparison function with custom comparator
-- captures: all available captures
-- captureIndices: indices to compare
-- analyzer: analyzer instance
-- name: analyzer name for metadata
-- comparatorFunc: function(selectedCaptures, byteIdx) -> bool (true if matches filter)
-- requireAll: if true, ALL bytes in chunk must match; if false, ANY byte matching means chunk matches
function analysis._compareCaptures(captures, captureIndices, analyzer, name, comparatorFunc, requireAll)
	local count = #captures

	if count < 2 then
		error("Need at least 2 captures to compare")
	end

	local indices = analysis._parseCaptureIndices(captureIndices, count)
	if #indices < 2 then
		error("Need at least 2 capture indices to compare")
	end

	local selectedCaptures = {}
	for _, idx in ipairs(indices) do
		table.insert(selectedCaptures, captures[idx])
	end

	local filteredRanges, unfilteredRanges = analysis._buildRanges(
		analyzer.size,
		function(byteIdx)
			return comparatorFunc(selectedCaptures, byteIdx)
		end,
		analyzer.alignment,
		requireAll
	)

	local result = {
		name = name,
		captureIndices = indices,
		filtered = filteredRanges,
		unfiltered = unfilteredRanges,
		_captures = selectedCaptures,
		_analyzer = analyzer,
		_alignment = analyzer.alignment
	}

	return result
end

-- Compare captures - changed at least once
-- ANY byte changed in the alignment chunk = chunk is changed
function analysis.getChangedOnce(captures, captureIndices, analyzer, name)
	local comparator = function(selectedCaptures, byteIdx)
		local firstValue = string.byte(selectedCaptures[1].data, byteIdx)
		for i = 2, #selectedCaptures do
			if string.byte(selectedCaptures[i].data, byteIdx) ~= firstValue then
				return true
			end
		end
		return false
	end
	return analysis._compareCaptures(captures, captureIndices, analyzer, name, comparator, false)
end

-- Compare captures - changed in every transition
-- ANY byte changed every time in the alignment chunk = chunk is changed
function analysis.getChangedEvery(captures, captureIndices, analyzer, name)
	local comparator = function(selectedCaptures, byteIdx)
		for i = 2, #selectedCaptures do
			local prevValue = string.byte(selectedCaptures[i-1].data, byteIdx)
			local currValue = string.byte(selectedCaptures[i].data, byteIdx)
			if currValue == prevValue then
				return false
			end
		end
		return true
	end
	return analysis._compareCaptures(captures, captureIndices, analyzer, name, comparator, false)
end

-- Compare captures - never changed
-- ALL bytes must be unchanged in the alignment chunk = chunk is unchanged
function analysis.getUnchanged(captures, captureIndices, analyzer, name)
	local comparator = function(selectedCaptures, byteIdx)
		local firstValue = string.byte(selectedCaptures[1].data, byteIdx)
		for i = 2, #selectedCaptures do
			if string.byte(selectedCaptures[i].data, byteIdx) ~= firstValue then
				return false
			end
		end
		return true
	end
	return analysis._compareCaptures(captures, captureIndices, analyzer, name, comparator, true)
end

-- Compare captures with custom comparator function
-- comparatorFunc(selectedCaptures, byteIdx) should return true if byte matches your filter
-- requireAll: if true, ALL bytes in chunk must match; if false (default), ANY byte matching means chunk matches
function analysis.getCustomChanges(captures, captureIndices, analyzer, name, comparatorFunc, requireAll)
	if type(comparatorFunc) ~= "function" then
		error("comparatorFunc must be a function")
	end
	requireAll = requireAll or false
	return analysis._compareCaptures(captures, captureIndices, analyzer, name, comparatorFunc, requireAll)
end

-- Build both filtered and unfiltered ranges with alignment support
-- compareFunc(byteIdx) should return true if byte matches the filter criteria
-- alignment: group bytes by alignment (1 = byte-by-byte, 4 = 4-byte groups, etc.)
-- requireAll: if true, ALL bytes in chunk must match; if false, ANY byte matching means chunk matches
-- Returns: filteredRanges (matched filter), unfilteredRanges (didn't match filter)
function analysis._buildRanges(size, compareFunc, alignment, requireAll)
	alignment = alignment or 4
	if size % alignment ~= 0 then
		error("Size ( " .. size .. " ) must be divisible by alignment ( " .. alignment .. " )")
	end

	local filteredRanges = {}
	local unfilteredRanges = {}

	local filteredInRange = false
	local unfilteredInRange = false
	local filteredStart = nil
	local unfilteredStart = nil

	local byteIdx = 1
	while byteIdx <= size do
		local matchesFilter
		if requireAll then
			-- ALL bytes in the alignment chunk must match the filter
			matchesFilter = true
			for offset = 0, alignment - 1 do
				if not compareFunc(byteIdx + offset) then
					matchesFilter = false
					break
				end
			end
		else
			-- ANY byte in the alignment chunk matching means the chunk matches
			matchesFilter = false
			for offset = 0, alignment - 1 do
				if compareFunc(byteIdx + offset) then
					matchesFilter = true
					break
				end
			end
		end

		if matchesFilter then
			if not filteredInRange then
				filteredStart = byteIdx
				filteredInRange = true
			end
			if unfilteredInRange then
				local rangeEnd = byteIdx - 1
				table.insert(unfilteredRanges, {
					start = unfilteredStart - 1,
					endOffset = rangeEnd - 1,
					count = rangeEnd - unfilteredStart + 1
				})
				unfilteredInRange = false
			end
		else
			if not unfilteredInRange then
				unfilteredStart = byteIdx
				unfilteredInRange = true
			end
			if filteredInRange then
				local rangeEnd = byteIdx - 1
				table.insert(filteredRanges, {
					start = filteredStart - 1,
					endOffset = rangeEnd - 1,
					count = rangeEnd - filteredStart + 1
				})
				filteredInRange = false
			end
		end

		byteIdx = byteIdx + alignment
	end

	if filteredInRange then
		table.insert(filteredRanges, {
			start = filteredStart - 1,
			endOffset = size - 1,
			count = size - filteredStart + 1
		})
	end
	if unfilteredInRange then
		table.insert(unfilteredRanges, {
			start = unfilteredStart - 1,
			endOffset = size - 1,
			count = size - unfilteredStart + 1
		})
	end

	return filteredRanges, unfilteredRanges
end

-- Clear any existing values from result
function analysis._clearValues(result)
	for _, range in ipairs(result.filtered or {}) do
		range.values = nil
		range.uniqueValues = nil
	end
	for _, range in ipairs(result.unfiltered or {}) do
		range.values = nil
		range.uniqueValues = nil
	end
	result._dataType = nil
	result._dataOptions = nil
end

-- Process a range to add all value progressions (shows every value)
function analysis._processAllValues(range, captures, captureIndices, alignment)
	range.values = {}
	for offset = range.start, range.endOffset, alignment do
		local progression = {}

		for i, capture in ipairs(captures) do
			local value = analysis._readAlignedValue(capture.data, offset, alignment)
			table.insert(progression, {
				captureIndex = captureIndices[i],
				value = value,
				address = capture.address + offset
			})
		end
		table.insert(range.values, progression)
	end
end

-- Process a range to add changed value progressions (only shows when value changes)
function analysis._processChangedValues(range, captures, captureIndices, alignment)
	range.values = {}
	for offset = range.start, range.endOffset, alignment do
		local progression = {}
		local lastValue = nil

		for i, capture in ipairs(captures) do
			local value = analysis._readAlignedValue(capture.data, offset, alignment)

			if value ~= lastValue then
				table.insert(progression, {
					captureIndex = captureIndices[i],
					value = value,
					address = capture.address + offset
				})
				lastValue = value
			end
		end
		table.insert(range.values, progression)
	end
end

-- Process a range to add unique value counts
function analysis._processRangeUnique(range, captures, captureIndices, alignment)
	range.uniqueValues = {}
	for offset = range.start, range.endOffset, alignment do
		local valueCounts = {}
		for _, capture in ipairs(captures) do
			local value = analysis._readAlignedValue(capture.data, offset, alignment)
			if value then
				valueCounts[value] = (valueCounts[value] or 0) + 1
			end
		end

		local uniqueList = {}
		for value, count in pairs(valueCounts) do
			table.insert(uniqueList, {value = value, count = count})
		end
		table.sort(uniqueList, function(a, b) return a.count > b.count end)

		table.insert(range.uniqueValues, {
			offset = offset,
			values = uniqueList
		})
	end
end

-- Core function that adds data to results
-- ranges: "filtered", "unfiltered", or "both"
-- processorFunc: function(range, captures, captureIndices, alignment)
-- dataType: "all", "changes", or "unique"
function analysis._addValues(result, ranges, processorFunc, dataType)
	if not result._captures then
		LOG("No captures found in result")
		return result
	end

	ranges = ranges or "filtered"

	analysis._clearValues(result)

	local captures = result._captures
	local captureIndices = result.captureIndices or {}
	local alignment = result._alignment

	if ranges == "filtered" or ranges == "both" then
		for _, range in ipairs(result.filtered or {}) do
			processorFunc(range, captures, captureIndices, alignment)
		end
	end

	if ranges == "unfiltered" or ranges == "both" then
		for _, range in ipairs(result.unfiltered or {}) do
			processorFunc(range, captures, captureIndices, alignment)
		end
	end

	result._dataType = dataType
	return result
end

-- Add all value progressions to result
function analysis.addAllCapturesValues(result, ranges)
	return analysis._addValues(result, ranges, analysis._processAllValues, "all")
end

-- Add changed value progressions to result
function analysis.addChangedCapturesValues(result, ranges)
	return analysis._addValues(result, ranges, analysis._processChangedValues, "changes")
end

-- Add unique value counts to result
function analysis.addUniqueCapturesValues(result, ranges)
	return analysis._addValues(result, ranges, analysis._processRangeUnique, "unique")
end

-- Helper to log a set of ranges with their data
function analysis._logRanges(ranges, rangeType, result, alignment, formatStr)
	for i = 1, #ranges do
		local range = ranges[i]
		if range.count == alignment then
			LOG(string.format("    [+0x%X]:", range.start))
		else
			LOG(string.format("    [+0x%X - +0x%X] (%d bytes):", range.start, range.endOffset, range.count))
		end

		if range.values then
			for j = 1, #range.values do
				local progression = range.values[j]
				local values = {}
				for _, v in ipairs(progression) do
					table.insert(values, string.format(formatStr, v.value))
				end
				-- progression[1].address is the actual address for this chunk
				local chunkOffset = progression[1] and (progression[1].address - result._captures[1].address) or (range.start + (j-1) * alignment)
				LOG(string.format("      +0x%X: %s", chunkOffset, table.concat(values, " -> ")))
			end
		end

		if range.uniqueValues then
			for j = 1, #range.uniqueValues do
				local uniqueData = range.uniqueValues[j]
				local valueStrs = {}
				for _, vCount in ipairs(uniqueData.values) do
					table.insert(valueStrs, string.format(formatStr .. "(%d)", vCount.value, vCount.count))
				end
				LOG(string.format("      +0x%X: %s", uniqueData.offset, table.concat(valueStrs, ", ")))
			end
		end
	end
end

-- Log changes from a result (logs everything - all ranges, all data)
function analysis.logChanges(result)

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

	LOG(string.format("Analyzer '%s' (captures: [%s], alignment: %d): %d filtered ranges, %d unfiltered ranges",
		name, table.concat(captureIndices, ","), alignment, #filteredRanges, #unfilteredRanges))

	if #filteredRanges > 0 then
		LOG(string.format("  Filtered Ranges (%d total):", #filteredRanges))
		analysis._logRanges(filteredRanges, "filtered", result, alignment, formatStr)
	end

	if #unfilteredRanges > 0 then
		LOG(string.format("  Unfiltered Ranges (%d total):", #unfilteredRanges))
		analysis._logRanges(unfilteredRanges, "unfiltered", result, alignment, formatStr)
	end
end

-- Filter result ranges based on custom criteria
-- result: result object to filter
-- filterSpec: filter specification
--   Mode 1 (range-level): function(range, captures) -> bool
--     - range: {start, endOffset, count}
--     - captures: array of capture data
--     - return true to keep the range
--   Mode 2 (alignment-chunk): {alignment=N, filter=function(offset, values) -> bool, ranges="filtered"}
--     - alignment: size of chunks to test (default: result._alignment)
--     - filter: function(offset, values) -> bool
--       - offset: byte offset within memory region
--       - values: array of alignment-sized values from each capture at this offset
--                 (byte for alignment=1, short for alignment=2, int for alignment=4)
--       - return true to keep this alignment chunk
--     - ranges: "filtered", "unfiltered", or "both" (which ranges to filter)
-- Returns new result with only ranges/chunks that pass the filter
function analysis.filterResult(result, filterSpec)
	if not result then
		error("Result is required")
	end

	if not result._captures or #result._captures == 0 then
		error("Result must have captures")
	end

	-- Determine filter mode
	local isRangeFilter = type(filterSpec) == "function"
	local isChunkFilter = type(filterSpec) == "table" and filterSpec.filter

	if not isRangeFilter and not isChunkFilter then
		error("filterSpec must be a function or table with 'filter' field")
	end

	local captures = result._captures
	local newFiltered = {}
	local newUnfiltered = {}

	if isRangeFilter then
		-- Mode 1: Range-level filtering
		for _, range in ipairs(result.filtered or {}) do
			if filterSpec(range, captures) then
				table.insert(newFiltered, range)
			end
		end
		for _, range in ipairs(result.unfiltered or {}) do
			table.insert(newUnfiltered, range)
		end
	else
		-- Mode 2: Alignment-chunk filtering
		local alignment = filterSpec.alignment or result._alignment
		local rangeMode = filterSpec.ranges or "filtered"
		local filterFunc = filterSpec.filter

		-- Helper to filter ranges by alignment chunks
		local function filterRangesByChunks(ranges)
			local filtered = {}
			for _, range in ipairs(ranges) do
				-- Test each alignment chunk in the range
				local keptChunks = {}
				for offset = range.start, range.endOffset, alignment do
					-- Gather aligned values at this offset from all captures
					local values = {}
					for _, capture in ipairs(captures) do
						local value = analysis._readAlignedValue(capture.data, offset, alignment)
						if value then
							table.insert(values, value)
						end
					end

					-- Test this chunk
					if #values > 0 and filterFunc(offset, values) then
						table.insert(keptChunks, offset)
					end
				end

				-- Build new ranges from kept chunks
				if #keptChunks > 0 then
					local currentStart = keptChunks[1]
					local currentEnd = keptChunks[1]

					for i = 2, #keptChunks do
						local offset = keptChunks[i]
						if offset == currentEnd + alignment then
							currentEnd = offset
						else
							-- Gap found, emit current range
							table.insert(filtered, {
								start = currentStart,
								endOffset = currentEnd + alignment - 1,
								count = currentEnd - currentStart + alignment
							})
							currentStart = offset
							currentEnd = offset
						end
					end

					-- Emit final range
					table.insert(filtered, {
						start = currentStart,
						endOffset = currentEnd + alignment - 1,
						count = currentEnd - currentStart + alignment
					})
				end
			end
			return filtered
		end

		-- Apply to filtered and/or unfiltered ranges
		if rangeMode == "filtered" or rangeMode == "both" then
			newFiltered = filterRangesByChunks(result.filtered or {})
		else
			newFiltered = result.filtered or {}
		end

		if rangeMode == "unfiltered" or rangeMode == "both" then
			newUnfiltered = filterRangesByChunks(result.unfiltered or {})
		else
			newUnfiltered = result.unfiltered or {}
		end
	end

	-- Build new result
	local newResult = {
		name = (result.name or "Unknown") .. "_filtered",
		captureIndices = result.captureIndices,
		filtered = newFiltered,
		unfiltered = newUnfiltered,
		_captures = result._captures,
		_analyzer = result._analyzer,
		_alignment = result._alignment
	}

	return newResult
end

return analysis
