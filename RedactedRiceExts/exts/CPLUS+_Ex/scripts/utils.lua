-- Shared utility functions for CPLUS+ Extension

local utils = {}

-- Deep copy function for tables
-- Note: Does not deep copy metatables to avoid circular references
function utils.deepcopy(orig, seen)
	local orig_type = type(orig)
	local copy

	if orig_type == 'table' then
		-- Check if we've already copied this table (circular reference)
		seen = seen or {}
		if seen[orig] then
			return seen[orig]
		end

		copy = {}
		seen[orig] = copy

		for orig_key, orig_value in next, orig, nil do
			copy[utils.deepcopy(orig_key, seen)] = utils.deepcopy(orig_value, seen)
		end

		-- Copy metatable reference but don't deep copy it (avoids circular refs)
		local mt = getmetatable(orig)
		if mt then
			setmetatable(copy, mt)
		end
	else
		copy = orig
	end
	return copy
end

-- Deep copy function for tables that preserves the top level table
-- Note: Does not deep copy metatables to avoid circular references
function utils.deepcopyInPlace(copy, orig)
	if type(copy) == 'table' and type(orig) == 'table' then
		-- clear the table first
		for k, _ in pairs(copy) do
			copy[k] = nil
		end

		-- Check if we've already copied this table (circular reference)
		seen = {}
		seen[orig] = copy

		for orig_key, orig_value in next, orig, nil do
			copy[utils.deepcopy(orig_key, seen)] = utils.deepcopy(orig_value, seen)
		end

		-- Copy metatable reference but don't deep copy it (avoids circular refs)
		local mt = getmetatable(orig)
		if mt then
			setmetatable(copy, mt)
		end
	end
	return copy
end

-- Helper function to convert a set-like table to a comma-separated string
-- Used for logging skill lists
function utils.setToString(setTable)
	local items = {}
	for key, _ in pairs(setTable) do
		table.insert(items, key)
	end
	local result = table.concat(items, ", ")
	return result
end

-- Normalize reusability value to integer constant
function utils.normalizeReusabilityToInt(reusability)
	if reusability == nil then
		return nil
	end

	if type(reusability) == "number" then
		if reusability == cplus_plus_ex.REUSABLILITY.REUSABLE or
				reusability == cplus_plus_ex.REUSABLILITY.PER_PILOT or
				reusability == cplus_plus_ex.REUSABLILITY.PER_RUN then
			return reusability
		end
		return nil
	end

	if type(reusability) == "string" then
		if reusability == "REUSABLE" or reusability == "reusable" then
			return cplus_plus_ex.REUSABLILITY.REUSABLE
		elseif reusability == "PER_PILOT" or reusability == "per_pilot" then
			return cplus_plus_ex.REUSABLILITY.PER_PILOT
		elseif reusability == "PER_RUN" or reusability == "per_run" then
			return cplus_plus_ex.REUSABLILITY.PER_RUN
		end
	end

	return nil
end

-- Shows an error popup to the user
-- TODO: There is a simpler way to do this in modAPI alread
function utils.showErrorPopup(message)
	sdlext.showButtonDialog(
		"CPLUS+ Ex Error",
		message,
		function() end,
		{"OK"}
	)
end

function utils.logAndShowErrorPopup(message)
	-- Log to console with ERROR level
	LOG("CPLUS+: ERR: " .. message)
	-- Show error popup if modApi is available
	utils.showErrorPopup(message)
end

-- TODO: Hijack AddPilot function? How does ModLoader override vanilla functions?
-- See if I can do that instead so I don't have to search _G which is costly and has
-- a noticible freeze

-- Helper function to get all pilots in the current squad
-- in the future add pilots in hanger here as well
function utils.searchForAllPilotIds(includeAi, includePlaceholder)
	local pilots = {}
	for k, v in pairs(_G) do
		if type(v) == "table" and getmetatable(v) == Pilot then
			-- if we don't include placeholder and we find it, skip it
			if (not includePlaceholder) and k == "Placeholder_Pilot" then
				--skip
			-- same for AI
			elseif (not includeAi) and k == "Pilot_Artificial" then
				--skip
			else
				table.insert(pilots, k)
			end
		end
	end
	return pilots
end

function utils.sortByValue(t, comparator)
	-- extract keys
	local keys = {}
	for k in pairs(t) do
		keys[#keys+1] = k
	end

	-- Sort keys by their associated values
	table.sort(keys, function(a, b)
		if comparator then
			return comparator(t[a], t[b])
		else
			return t[a] < t[b]
		end
	end)
	return keys
end

return utils
