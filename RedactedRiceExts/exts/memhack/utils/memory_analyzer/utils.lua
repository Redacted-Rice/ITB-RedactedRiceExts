-- Utility functions for memory analysis

local utils = {}

-- Read value based on alignment size
-- alignment: 1 (byte), 2 (short), 4 (int/pointer)
function utils.readAlignedValue(data, offset, alignment)
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
function utils.parseCaptureIndices(captureIndices, totalCount)
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

return utils
