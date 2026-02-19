-- Memory comparison and filtering functions

local path = GetParentPath(...)
local utils = require(path .. "utils")

local comparison = {}

-- Build both filtered and unfiltered ranges with alignment support
-- compareFunc(byteIdx) should return true if byte matches the filter criteria
-- alignment: group bytes by alignment (1 = byte-by-byte, 4 = 4-byte groups, etc.)
-- requireAll: if true, ALL bytes in chunk must match; if false, ANY byte matching means chunk matches
-- Returns: filteredRanges (matched filter), unfilteredRanges (didn't match filter)
local function buildRanges(size, compareFunc, alignment, requireAll)
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

-- Core comparison function with custom comparator
-- captures: all available captures
-- captureIndices: indices to compare
-- analyzer: analyzer instance
-- name: analyzer name for metadata
-- comparatorFunc: function(selectedCaptures, byteIdx) -> bool (true if matches filter)
-- requireAll: if true, ALL bytes in chunk must match; if false, ANY byte matching means chunk matches
local function compareCaptures(captures, captureIndices, analyzer, name, comparatorFunc, requireAll)
	local count = #captures

	if count < 2 then
		error("Need at least 2 captures to compare")
	end

	local indices = utils.parseCaptureIndices(captureIndices, count)
	if #indices < 2 then
		error("Need at least 2 capture indices to compare")
	end

	local selectedCaptures = {}
	for _, idx in ipairs(indices) do
		table.insert(selectedCaptures, captures[idx])
	end

	local filteredRanges, unfilteredRanges = buildRanges(
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
function comparison.getChangedOnce(captures, captureIndices, analyzer, name)
	local comparator = function(selectedCaptures, byteIdx)
		local firstValue = string.byte(selectedCaptures[1].data, byteIdx)
		for i = 2, #selectedCaptures do
			if string.byte(selectedCaptures[i].data, byteIdx) ~= firstValue then
				return true
			end
		end
		return false
	end
	return compareCaptures(captures, captureIndices, analyzer, name, comparator, false)
end

-- Compare captures - changed in every transition
-- ANY byte changed every time in the alignment chunk = chunk is changed
function comparison.getChangedEvery(captures, captureIndices, analyzer, name)
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
	return compareCaptures(captures, captureIndices, analyzer, name, comparator, false)
end

-- Compare captures - never changed
-- ALL bytes must be unchanged in the alignment chunk = chunk is unchanged
function comparison.getUnchanged(captures, captureIndices, analyzer, name)
	local comparator = function(selectedCaptures, byteIdx)
		local firstValue = string.byte(selectedCaptures[1].data, byteIdx)
		for i = 2, #selectedCaptures do
			if string.byte(selectedCaptures[i].data, byteIdx) ~= firstValue then
				return false
			end
		end
		return true
	end
	return compareCaptures(captures, captureIndices, analyzer, name, comparator, true)
end

-- Compare captures with custom comparator function
-- comparatorFunc(selectedCaptures, byteIdx) should return true if byte matches your filter
-- requireAll: if true, ALL bytes in chunk must match; if false (default), ANY byte matching means chunk matches
function comparison.getCustomChanges(captures, captureIndices, analyzer, name, comparatorFunc, requireAll)
	if type(comparatorFunc) ~= "function" then
		error("comparatorFunc must be a function")
	end
	requireAll = requireAll or false
	return compareCaptures(captures, captureIndices, analyzer, name, comparatorFunc, requireAll)
end

-- Filter result ranges based on custom criteria
-- result: result object to filter
-- filterSpec: filter specification
--   Mode 1 (Range-level filtering):
--     - filterSpec is a function: function(range, captures) -> bool
--       - return true to keep entire range
--   Mode 2 (Alignment-chunk filtering):
--     - filterSpec is a table with:
--       - filter: function(offset, values) -> bool
--         - offset: byte offset of this alignment chunk
--         - values: array of alignment-sized values from each capture at this offset
--                   (byte for alignment=1, short for alignment=2, int for alignment=4)
--         - return true to keep this alignment chunk
--       - ranges: "filtered", "unfiltered", or "both" (which ranges to filter)
-- Returns new result with only ranges/chunks that pass the filter
function comparison.filterResult(result, filterSpec)
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
						local value = utils.readAlignedValue(capture.data, offset, alignment)
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

return comparison
