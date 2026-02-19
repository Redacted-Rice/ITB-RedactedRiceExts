-- Value data enrichment functions for analysis results

local path = GetParentPath(...)
local utils = require(path .. "utils")

local values = {}

-- Clear any existing data enrichment from result
local function clearData(result)
	for _, range in ipairs(result.filtered or {}) do
		range.values = nil
		range.uniqueValues = nil
	end
	for _, range in ipairs(result.unfiltered or {}) do
		range.values = nil
		range.uniqueValues = nil
	end
	result._dataType = nil
end

-- Process a range to add all value progressions (shows every value)
local function processAllValues(range, captures, captureIndices, alignment)
	range.values = {}
	for offset = range.start, range.endOffset, alignment do
		local progression = {}

		for i, capture in ipairs(captures) do
			local value = utils.readAlignedValue(capture.data, offset, alignment)
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
local function processChangedValues(range, captures, captureIndices, alignment)
	range.values = {}
	for offset = range.start, range.endOffset, alignment do
		local progression = {}
		local lastValue = nil

		for i, capture in ipairs(captures) do
			local value = utils.readAlignedValue(capture.data, offset, alignment)

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
local function processRangeUnique(range, captures, captureIndices, alignment)
	range.uniqueValues = {}
	for offset = range.start, range.endOffset, alignment do
		local valueCounts = {}
		for _, capture in ipairs(captures) do
			local value = utils.readAlignedValue(capture.data, offset, alignment)
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
local function addData(result, ranges, processorFunc, dataType)
	if not result._captures then
		LOG("No captures found in result")
		return result
	end

	ranges = ranges or "filtered"

	clearData(result)

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
function values.addAllCapturesValues(result, ranges)
	return addData(result, ranges, processAllValues, "all")
end

-- Add changed value progressions to result
function values.addChangedCapturesValues(result, ranges)
	return addData(result, ranges, processChangedValues, "changes")
end

-- Add unique value counts to result
function values.addUniqueCapturesValues(result, ranges)
	return addData(result, ranges, processRangeUnique, "unique")
end

return values
