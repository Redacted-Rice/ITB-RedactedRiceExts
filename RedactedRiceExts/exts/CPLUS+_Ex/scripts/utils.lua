-- Shared utility functions for CPLUS+ Extension

local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "utils", false)

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

-- Shallow copy function for tables (only copies first level)
function utils.shallowcopy(orig)
	if type(orig) ~= 'table' then
		return orig
	end

	local copy = {}
	for k, v in pairs(orig) do
		copy[k] = v
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

-- Normalize slot restriction value to integer constant
function utils.normalizeSlotRestrictionToInt(slotRestriction)
	if slotRestriction == nil then
		return nil
	end

	if type(slotRestriction) == "number" then
		if slotRestriction == cplus_plus_ex.SLOT_RESTRICTION.ANY or
				slotRestriction == cplus_plus_ex.SLOT_RESTRICTION.FIRST or
				slotRestriction == cplus_plus_ex.SLOT_RESTRICTION.SECOND then
			return slotRestriction
		end
		return nil
	end

	if type(slotRestriction) == "string" then
		if slotRestriction == "ANY" or slotRestriction == "any" then
			return cplus_plus_ex.SLOT_RESTRICTION.ANY
		elseif slotRestriction == "FIRST" or slotRestriction == "first" then
			return cplus_plus_ex.SLOT_RESTRICTION.FIRST
		elseif slotRestriction == "SECOND" or slotRestriction == "second" then
			return cplus_plus_ex.SLOT_RESTRICTION.SECOND
		end
	end

	return nil
end

-- Pilot registry to avoid expensive _G searches
local pilotRegistry = {}
local originalCreatePilot = nil

-- Override CreatePilot to maintain our own registry
function utils._initPilotTracking()
	if originalCreatePilot then
		logger.logDebug(SUBMODULE, "Pilot tracking already initialized")
		return
	end

	originalCreatePilot = CreatePilot
	function CreatePilot(data)
		-- Call original function
		originalCreatePilot(data)

		-- Add to our registry for fast lookup
		if data.Id and data.Id ~= "Placeholder_Pilot" and data.Id ~= "Pilot_Artificial" then
			pilotRegistry[data.Id] = true
			logger.logDebug(SUBMODULE, "Registered pilot: %s", data.Id)
		end
	end

	logger.logInfo(SUBMODULE, "CreatePilot override applied for pilot tracking")
end

-- Populate registry with existing pilots (called after all mods load)
function utils._populatePilotRegistry()
	-- Search _G one time only to populate the registry
	local count = 0
	for k, v in pairs(_G) do
		if type(v) == "table" and getmetatable(v) == Pilot then
			if k ~= "Placeholder_Pilot" and k ~= "Pilot_Artificial" then
				pilotRegistry[k] = true
				count = count + 1
			end
		end
	end

	logger.logInfo(SUBMODULE, "Pilot registry populated with %d pilots", count)
end

-- Fast pilot lookup using registry (no _G search)
function utils.searchForAllPilotIds(includeAi, includePlaceholder)
	local pilots = {}

	-- Add from registry
	for pilotId in pairs(pilotRegistry) do
		table.insert(pilots, pilotId)
	end

	-- Add special pilots if requested
	if includePlaceholder and _G["Placeholder_Pilot"] then
		table.insert(pilots, "Placeholder_Pilot")
	end
	if includeAi and _G["Pilot_Artificial"] then
		table.insert(pilots, "Pilot_Artificial")
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

function utils.isExclusionSkill(skillType)
	return skillType == "default" or skillType == "exclusion"
end

function utils.isInclusionSkill(skillType)
	return skillType == "inclusion"
end

utils.ADVANCED_PILOTS = {
	"Pilot_Arrogant",
	"Pilot_Caretaker",
	"Pilot_Chemical",
	"Pilot_Delusional",
}

utils.DEFAULT_PILOT_PORTRAIT_SCALE = 2
local pilotPortraitCache = {}

utils.unnamedPilotDisplayNames = {
	Pilot_Rust = "Corp. Rust",
	Pilot_Detritus = "Corp. Detritus",
	Pilot_Pinnacle = "Corp. Pinnacle",
	Pilot_Archive = "Corp. Archive",
}

-- Resolve display name for cyborg pilots without an explicit pilot Name field.
-- Uses pawn.Name (e.g. "Entborg") or pawn localization key (e.g. BeetleMech -> "Techno-Beetle").
function utils.getCyborgMechDisplayName(pilotId)
	if not pilotId then
		return pilotId
	end

	local pawn = cplus_plus_ex.getTechnoVekPawn(pilotId)
	if pawn and pawn.Name and pawn.Name ~= "" then
		return GetText(pawn.Name) or pawn.Name
	end

	local pawnName = pilotId:match("^Pilot_(.+)$")
	if pawnName then
		local mechName = GetText(pawnName)
		if mechName and mechName ~= "" then
			return mechName
		end
	end

	return pilotId
end

function utils.getPilotDisplayName(pilotOrId)
	if type(pilotOrId) == "table" and getmetatable(pilotOrId) == memhack.structs.Pilot then
		local nameKey = pilotOrId:getName():get()
		if nameKey and nameKey ~= "" then
			return GetText(nameKey) or nameKey or pilotOrId:getIdStr()
		end

		local pilotId = pilotOrId:getIdStr()
		if cplus_plus_ex.isCyborg(pilotId) then
			return utils.getCyborgMechDisplayName(pilotId)
		end
		return pilotOrId:getIdStr()
	end

	local pilotId = pilotOrId
	local pilotDef = _G[pilotId]
	if not pilotDef then
		return pilotId
	end

	local pilotName = pilotDef.Name
	if pilotName == nil or pilotName == "" then
		if cplus_plus_ex.isCyborg(pilotId) then
			return utils.getCyborgMechDisplayName(pilotId)
		end
		return utils.unnamedPilotDisplayNames[pilotId] or pilotId
	end

	return GetText(pilotName) or pilotName or pilotId
end

function utils.getPilotPortraitPath(pilotId)
	local pilotDef = _G[pilotId]
	if not pilotDef then
		return nil
	end

	local portrait = pilotDef.Portrait
	if portrait and portrait ~= "" then
		return "img/portraits/" .. portrait .. ".png"
	end

	local advanced = list_contains(utils.ADVANCED_PILOTS, pilotId)
	local prefix = advanced and "img/advanced/portraits/pilots/" or "img/portraits/pilots/"
	return prefix .. pilotId .. ".png"
end

function utils.getPilotPortraitSurface(pilotOrId, scale)
	scale = scale or utils.DEFAULT_PILOT_PORTRAIT_SCALE
	local pilotId = type(pilotOrId) == "string" and pilotOrId or pilotOrId:getIdStr()
	local cacheKey = pilotId .. "@" .. tostring(scale)
	if not pilotPortraitCache[cacheKey] then
		local path = utils.getPilotPortraitPath(pilotId)
		if path then
			pilotPortraitCache[cacheKey] = sdlext.getSurface({
				path = path,
				scale = scale,
			})
		end
	end
	return pilotPortraitCache[cacheKey]
end

return utils
