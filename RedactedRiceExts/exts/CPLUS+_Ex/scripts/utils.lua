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

-- Helper function to convert a set-like table to a comma-separated string
-- Used for logging skill lists
function utils.setToString(setTable)
	local items = {}
	for key, _ in pairs(setTable) do
		table.insert(items, key)
	end
	return table.concat(items, ", ")
end

-- Normalize reusability value to integer constant
function utils.normalizeReusabilityToInt(reusability, REUSABLILITY)
	if reusability == nil then
		return nil
	end

	if type(reusability) == "number" then
		if reusability == REUSABLILITY.REUSABLE or
		   reusability == REUSABLILITY.PER_PILOT or
		   reusability == REUSABLILITY.PER_RUN then
			return reusability
		end
		return nil
	end

	if type(reusability) == "string" then
		if reusability == "REUSABLE" or reusability == "reusable" then
			return REUSABLILITY.REUSABLE
		elseif reusability == "PER_PILOT" or reusability == "per_pilot" then
			return REUSABLILITY.PER_PILOT
		elseif reusability == "PER_RUN" or reusability == "per_run" then
			return REUSABLILITY.PER_RUN
		end
	end

	return nil
end

-- Shows an error popup to the user
function utils.showErrorPopup(message)
	if modApi then
		modApi:scheduleHook(50, function()
			sdlext.showDialog(
				function(dialog)
					local ui = require("ui")
					local frame = Ui()
						:widthpx(500):heightpx(200)
						:caption("PLUS Extension Error")

					frame:addSurface(Ui()
						:width(1):height(1)
						:decorate({ DecoSolid(deco.colors.buttonborder) })
					)

					local scrollarea = UiScrollArea()
						:width(1):height(1)
						:padding(10)
					frame:add(scrollarea)

					local textbox = UiTextBox(message)
						:width(1)
					scrollarea:add(textbox)

					return frame
				end
			)
		end)
	end
end

function utils.logAndShowErrorPopup(message)
	LOG(message)
	utils.showErrorPopup(message)
end

-- Helper function to get all pilots in the current squad
-- in the future add pilots in hanger here as well
function utils.getAllSquadPilots()
	if not Game then return nil end

	local pilots = {}
	for i = 0, 2 do
		local pawnId = i
		local pawn = Game:GetPawn(pawnId)

		if pawn ~= nil then
			local pilot = pawn:GetPilot()
			if pilot ~= nil then
				pilots[i + 1] = pilot
			end
		end
	end
	return pilots
end

return utils
