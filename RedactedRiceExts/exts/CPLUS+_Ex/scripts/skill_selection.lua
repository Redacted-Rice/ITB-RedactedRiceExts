-- Skill Selection Module
-- Handles weighted random selection and application of skills to pilots
-- This is the core logic for determining and assigning skills to pilots

local skill_selection = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "SkillSelection", cplus_plus_ex.DEBUG.SELECTION and cplus_plus_ex.DEBUG.ENABLED)

-- Module state
skill_selection.localRandomCount = nil  -- Track local random count for this session
skill_selection.usedSkillsPerRun = {}   -- skillId -> true for per_run skills used this run
skill_selection._pilotsAssignedThisRun = {}  -- pilotId -> true for pilots assigned this run
skill_selection.virtualSkillSourceCallbacks = {}  -- sourceId -> onSkillInvalidatedCallback

-- Local references to other submodules (set during init)
local skill_constraints = nil
local skill_config_module = nil
local utils = nil
local hooks = nil
local skill_state_tracker = nil

-- Initialize the module
function skill_selection:init()
	skill_constraints = cplus_plus_ex._subobjects.skill_constraints
	skill_config_module = cplus_plus_ex._subobjects.skill_config
	utils = cplus_plus_ex._subobjects.utils
	hooks = cplus_plus_ex._subobjects.hooks
	skill_state_tracker = cplus_plus_ex._subobjects.skill_state_tracker

	return self
end

-- Clear pilot assignment tracking used on reset/enter/exit events
function skill_selection:_clearPilotTracking()
	self._pilotsAssignedThisRun = {}
end

-- Initialize game save data for skills
-- technically redundant with the data in modloader save data
-- but this is a more intuitive spot for it and only the minimal
-- needed data for skills
function skill_selection:_initGameSaveData()
	if GAME == nil then
		GAME = {}
	end

	if GAME.cplus_plus_ex == nil then
		GAME.cplus_plus_ex = {}
	end

	-- Initialize save data
	if GAME.cplus_plus_ex.pilotSkills == nil then
		GAME.cplus_plus_ex.pilotSkills = {}
	end

	-- This manages the save data and which skills are assigned
	-- skill_state_tracker manages the runtime objects
	if GAME.cplus_plus_ex.pilotVirtualSkills == nil then
		GAME.cplus_plus_ex.pilotVirtualSkills = {}
	end

	if GAME.cplus_plus_ex.randomSeed == nil then
		-- The random is initialized using game turn. So we create our own
		-- source seed based on time
		local seed = os.time()
		GAME.cplus_plus_ex.randomSeed = seed
	end

	if GAME.cplus_plus_ex.randomSeedCnt == nil then
		GAME.cplus_plus_ex.randomSeedCnt = 0
	end
end

function skill_selection:canBeVirtualSkill(skillId)
	if cplus_plus_ex.NON_VIRTUAL_SKILLS[skillId] then
		logger.logWarn(SUBMODULE, "Skill %s cannot be used as virtual skill (hardcoded vanilla limitation)", skillId)
		return false
	end
	return true
end

-- Register a virtual skill source with callbacks
-- sourceId: unique identifier for the source (e.g., "warbot", "sgt_drake")
-- callback: option callback function called when a virtual skill from this source becomes invalid
--   - onSkillInvalidated(pilot, skillData, alreadyAssigned)
--     the callback returns the same skillId to keep it, nil to remove it, or a different skillId to replace it.
function skill_selection:registerVirtualSkillSource(sourceId, callback)
	if type(sourceId) ~= "string" or sourceId == "" then
		logger.logError(SUBMODULE, "registerVirtualSkillSource: sourceId must be a non-empty string")
		return false
	end
	if callback and type(callback) ~= "function" then
		logger.logError(SUBMODULE, "registerVirtualSkillSource: callback must be a function")
		return false
	end

	self.virtualSkillSourceCallbacks[sourceId] = callback
	logger.logInfo(SUBMODULE, "Registered virtual skill source: %s", sourceId)
	return true
end

-- Add a virtual skill to a pilot
-- skillId: ID of the skill to add
-- source: optional source identifier (defaults to "unspecified")
-- Returns: true if successful, false if skill is invalid or there was an error
function skill_selection:addVirtualSkillToPilot(pilot, skillId, source)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "addVirtualSkillToPilot: expected Pilot struct, got %s", type(pilot))
		return false
	end

	if type(skillId) ~= "string" then
		logger.logError(SUBMODULE, "addVirtualSkillToPilot: expected skillId string, got %s", type(skillId))
		return false
	end

	local successCount = self:addVirtualSkillsToPilot(pilot, {skillId}, source)
	return successCount == 1
end

-- Add multiple virtual skills to a pilot
-- skillIds: array of skill IDs to add
-- source: optional source identifier (defaults to "unspecified")
-- Returns: number of skills successfully added
function skill_selection:addVirtualSkillsToPilot(pilot, skillIds, source)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "addVirtualSkillsToPilot: expected Pilot struct, got %s", type(pilot))
		return 0
	end

	if not skillIds or #skillIds == 0 then
		logger.logWarn(SUBMODULE, "No skill IDs provided to addVirtualSkillsToPilot")
		return 0
	end
	if source == nil then
		source = "unspecified"
	end

	self:_initGameSaveData()
	local pilotId = pilot:getIdStr()
	local successCount = 0

	-- Initialize virtual skills array for this pilot if needed
	if not GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] then
		GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] = {}
	end

	for _, skillId in ipairs(skillIds) do
		-- Check if skill can be virtual
		if not self:canBeVirtualSkill(skillId) then
			logger.logWarn(SUBMODULE, "Skill %s cannot be used as virtual skill", skillId)
		else
			-- Validate skill exists and is enabled
			local skill = skill_config_module.enabledSkills[skillId]
			if not skill then
				logger.logWarn(SUBMODULE, "Skill %s is not enabled or does not exist", skillId)
			else
				-- Store as object with metadata
				table.insert(GAME.cplus_plus_ex.pilotVirtualSkills[pilotId], {
						id = skillId,
						source = source,
				})

				logger.logDebug(SUBMODULE, "Added virtual skill %s (source: %s) to pilot %s at slot %d",
						skillId, source, pilotId, cplus_plus_ex.MAX_SKILL_SLOTS + #GAME.cplus_plus_ex.pilotVirtualSkills[pilotId])

				self:_markPerRunSkillAsUsed(skillId)
				successCount = successCount + 1
			end
		end
	end

	if successCount > 0 then
		-- Sync objects and update virtual bonuses and fire hooks
		-- This will create new objects or reuse existing ones as appropriate
		skill_state_tracker:_updateAllStates()
	end
	return successCount
end

-- Apply virtual skills to a pilot (replaces existing virtual skills in GAME)
-- This is for loading from save data (like time travelers) - replaces instead of appending
-- Use this instead of addVirtualSkillsToPilot when loading skills that should replace existing ones
-- virtualSkills: array of skillIds or skillData struts { id = string, source = string } (Can be mixed)
-- defaultSource: used when an entry omits source (defaults to "unspecified")
function skill_selection:applyVirtualSkillIdsToPilot(pilot, virtualSkills, defaultSource)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "applyVirtualSkillIdsToPilot: expected Pilot struct, got %s", type(pilot))
		return false
	end

	if not virtualSkills then
		virtualSkills = {}
	end
	if defaultSource == nil then
		defaultSource = "unspecified"
	end

	self:_initGameSaveData()
	local pilotId = pilot:getIdStr()

	-- Replace the entire virtual skills array (like applySkillIdsToPilot does for regular skills)
	GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] = {}

	for _, skillEntry in ipairs(virtualSkills) do
		local skillId = skillEntry.id and skillEntry.id or skillEntry
		local entrySource = skillEntry.source or defaultSource
		if not self:canBeVirtualSkill(skillId) then
			logger.logWarn(SUBMODULE, "Skill %s cannot be used as virtual skill", skillId)
		else
			local skill = skill_config_module.enabledSkills[skillId]
			if not skill then
				logger.logWarn(SUBMODULE, "Skill %s is not enabled or does not exist", skillId)
			else
				table.insert(GAME.cplus_plus_ex.pilotVirtualSkills[pilotId], {
					id = skillId,
					source = entrySource,
				})
				self:_markPerRunSkillAsUsed(skillId)
				logger.logInfo(SUBMODULE, "Applied virtual skill %s (source: %s) to pilot %s (slot %d)",
						skillId, entrySource, pilotId, cplus_plus_ex.MAX_SKILL_SLOTS + #GAME.cplus_plus_ex.pilotVirtualSkills[pilotId])
			end
		end
	end

	if #GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] > 0 then
		-- Sync objects and update virtual bonuses
		skill_state_tracker:_updateAllStates()
	end

	return true
end

-- Add random virtual skills to a pilot
-- count: number of random skills to add
-- source: optional source identifier (defaults to "unspecified")
-- Returns: number of skills successfully added, array of selected skill IDs
function skill_selection:addRandomVirtualSkillsToPilot(pilot, count, source)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "addRandomVirtualSkillsToPilot: expected Pilot struct, got %s", type(pilot))
		return 0, {}
	end

	if not count or count <= 0 then
		logger.logWarn(SUBMODULE, "Invalid count %s for addRandomVirtualSkillsToPilot", tostring(count))
		return 0, {}
	end
	if source == nil then
		source = "unspecified"
	end

	-- Get currently assigned skills (both real and virtual) to avoid duplicates
	local skill_state_tracker = cplus_plus_ex._subobjects.skill_state_tracker
	local assignedSkills = skill_state_tracker:getAllSkills(pilot)

	local virtualCompatibleSkills = self:_getVirtualCompatibleSkillPool()
	if #virtualCompatibleSkills == 0 then
		logger.logWarn(SUBMODULE, "No virtual-compatible skills available")
		return 0, {}
	end

	-- Select random skills
	local selectedSkills = {}
	for i = 1, count do
		-- Select a random skill that isn't already assigned
		local potentialSkills = utils.shallowcopy(virtualCompatibleSkills)

		-- We use a virtual slot index here (MAX_SKILL_SLOTS + current virtual count + 1)
		local pilotId = pilot:getIdStr()
		self:_initGameSaveData()
		local virtualSlotIndex = cplus_plus_ex.MAX_SKILL_SLOTS + #(GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] or {}) + 1

		local skillId = self:selectRandomSkill(potentialSkills, pilot, virtualSlotIndex, assignedSkills)

		if skillId then
			table.insert(selectedSkills, skillId)
			table.insert(assignedSkills, skillId)
			logger.logDebug(SUBMODULE, "Selected random virtual skill %s for pilot %s (source: %s)", skillId, pilotId, source)
		else
			logger.logWarn(SUBMODULE, "Failed to find valid random virtual skill %d for pilot %s", i, pilotId)
			break
		end
	end

	-- Add all selected skills at once with source
	local successCount = self:addVirtualSkillsToPilot(pilot, selectedSkills, source)
	return successCount, selectedSkills
end

function skill_selection:removeVirtualSkillFromPilot(pilot, skillId)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "removeVirtualSkillFromPilot: expected Pilot struct, got %s", type(pilot))
		return false
	end

	if type(skillId) ~= "string" then
		logger.logError(SUBMODULE, "removeVirtualSkillFromPilot: expected skillId string, got %s", type(skillId))
		return false
	end

	self:_initGameSaveData()
	local pilotId = pilot:getIdStr()
	local virtualSkills = GAME.cplus_plus_ex.pilotVirtualSkills[pilotId]

	if not virtualSkills or #virtualSkills == 0 then
		logger.logWarn(SUBMODULE, "Pilot %s has no virtual skills to remove", pilotId)
		return false
	end

	for i, skillData in ipairs(virtualSkills) do
		if skillData.id == skillId then
			-- Remove from save data
			table.remove(virtualSkills, i)
			logger.logInfo(SUBMODULE, "Removed virtual skill %s from pilot %s", skillId, pilotId)

			-- Remove the corresponding object from state tracker
			skill_state_tracker:_removeVirtualSkillObjectBySkillId(pilotId, skillId)

			-- Update virtual bonuses and fire hooks
			skill_state_tracker:_updateAllStates()
			return true
		end
	end
	return false
end

function skill_selection:clearVirtualSkillsFromPilot(pilot)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "clearVirtualSkillsFromPilot: expected Pilot struct, got %s", type(pilot))
		return false
	end

	self:_initGameSaveData()
	local pilotId = pilot:getIdStr()

	-- Clear save data
	GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] = {}
	logger.logInfo(SUBMODULE, "Cleared all virtual skills from pilot %s", pilotId)

	-- Clear the corresponding objects from state tracker
	skill_state_tracker:_clearVirtualSkillObjects(pilotId)

	-- Update virtual bonuses and fire hooks
	skill_state_tracker:_updateAllStates()
	return true
end

-- Clear in memory session to force a recalculation
function skill_selection:_resetRandomSession()
	skill_selection.localRandomCount = nil
end

-- Uses the stored seed and sequential access count to ensure deterministic random values
-- The RNG is seeded once per session, then we fast forward to the saved count
-- availableSkills - array like table of skill IDs to select from
function skill_selection:_getWeightedRandomSkillId(availableSkills)
	if #availableSkills == 0 then
		logger.logError(SUBMODULE, "No skills available in list")
		return nil
	end

	-- Calculate total weight for the available skills
	local totalWeight = 0
	for _, skillId in ipairs(availableSkills) do
		totalWeight = totalWeight + skill_config_module.config.skillConfigs[skillId].weight
	end

	-- Get seed and count from saved game data
	local seed = GAME.cplus_plus_ex.randomSeed
	local savedCount = GAME.cplus_plus_ex.randomSeedCnt

	-- If this is the first call this session, initialize the RNG to match
	-- what is in our saved data
	if skill_selection.localRandomCount == nil then
		math.randomseed(seed)
		for i = 1, savedCount do
			math.random()
		end
		skill_selection.localRandomCount = savedCount
		logger.logDebug(SUBMODULE, "Initialized RNG with seed %d and fast-forwarded %d times", seed, savedCount)
	end

	-- Weighted random selection
	local randomValue = math.random() * totalWeight
	skill_selection.localRandomCount = skill_selection.localRandomCount + 1
	GAME.cplus_plus_ex.randomSeedCnt = skill_selection.localRandomCount

	local cumulativeWeight = 0
	for _, skillId in ipairs(availableSkills) do
		cumulativeWeight = cumulativeWeight + skill_config_module.config.skillConfigs[skillId].weight
		if randomValue <= cumulativeWeight then
			return skillId
		end
	end

	-- Fallback to last skill. We shouldn't get here but just in case
	logger.logError(SUBMODULE, "Weighted selection failed! Falling back to last skill")
	return availableSkills[#availableSkills]
end

function skill_selection:getAssignableSkillIds()
	-- Assignable skills only; internal skills can be set explicitly but never assigned randomly.
	local availableSkills = {}
	local skill_registry_module = cplus_plus_ex._subobjects.skill_registry
	for _, skillId in ipairs(skill_config_module.enabledSkillsIds) do
		if not skill_registry_module:isInternalSkill(skillId) then
			table.insert(availableSkills, skillId)
		end
	end
	return availableSkills
end

function skill_selection:_getVirtualCompatibleSkillPool()
	local availableSkills = self:getAssignableSkillIds()
	local virtualCompatibleSkills = {}

	for _, skillId in ipairs(availableSkills) do
		if self:canBeVirtualSkill(skillId) then
			table.insert(virtualCompatibleSkills, skillId)
		end
	end

	return virtualCompatibleSkills
end

function skill_selection:selectRandomSkill(availableSkills, pilot, idx, selectedSkills)
	while true do
		-- Get a weighted random skill from the available pool
		local candidateSkillId = self:_getWeightedRandomSkillId(availableSkills)
		if candidateSkillId == nil then
			break
		end

		if skill_constraints:checkSkillConstraints(pilot, selectedSkills, candidateSkillId) then
			-- If valid, add to the selected but do not remove yet
			-- Allows for potential duplicates in the future
			if idx then
				selectedSkills[idx] = candidateSkillId
			end
			return candidateSkillId
		else
			-- If the skill is invalid, remove it from the pool
			for i, skillId in ipairs(availableSkills) do
				if skillId == candidateSkillId then
					table.remove(availableSkills, i)
					break
				end
			end
		end
	end
	return false
end

-- Selects random level up skills based on count and configured constraints
-- Returns a array like table of skill IDs that satisfy the constraints
function skill_selection:selectRandomSkills(availableSkills, pilot, count)
	if #skill_config_module.enabledSkillsIds == 0 then
		logger.logError(SUBMODULE, "No enabled skills available")
		return nil
	end

	local selectedSkills = {}

	for idx = 1, count do
		-- Create fresh copy of available skills for each slot to avoid contamination from previous slot failures
		local freshAvailableSkills = utils.shallowcopy(availableSkills)
		logger.logDebug(SUBMODULE, "Selecting skill for slot %d with %d available skills", idx, #freshAvailableSkills)
		if not self:selectRandomSkill(freshAvailableSkills, pilot, idx, selectedSkills) then
			return nil
		end
	end

	-- Check we assigned the expected number of skill
	if #selectedSkills ~= count then
		logger.logError(SUBMODULE, "Failed to select " .. count .. " skills. Selected " .. #selectedSkills ..
				". Constraints may be impossible to satisfy with available skills.")
		return nil
	end
	return selectedSkills
end

function skill_selection:_skillDataToTable(id, shortName, fullName, description, saveVal, bonuses)
	return {id = id, shortName = shortName, fullName = fullName, description = description,
		healthBonus = bonuses.health or 0, coresBonus = bonuses.cores or 0, gridBonus = bonuses.grid or 0,
		moveBonus = bonuses.move or 0, saveVal = saveVal}
end

-- Generate a random saveVal (0-13), optionally excluding a specific value
-- If excludeVal is provided, generates 0-12 and increments if >= excludeVal
-- This ensures the returned value is different from excludeVal
function skill_selection:_generateSaveVal(excludeVal)
	if excludeVal == nil then
		return math.random(0, 13)
	else
		local val = math.random(0, 12)
		if val >= excludeVal then
			val = val + 1
		end
		return val
	end
end

-- Assign or get saveVal for a skill, ensuring it's different from excludeVal
-- preassignedVal: the current saveVal from memory (preassigned value to preserve if possible)
-- Preference: registered, stored, in-memory
function skill_selection:_getOrAssignSaveVal(storedSkill, registeredSkill, pilotId, skillId, preassignedVal, excludeVal)
	-- Determine our starting save val
	-- In order registered, stored, in-memory
	local resolved = false
	local saveVal = nil
	if registeredSkill.saveVal and registeredSkill.saveVal >= 0 then
		if registeredSkill.saveVal == excludeVal then
			logger.logDebug(SUBMODULE, "Found registered saveVal %d but it conflicts with excludeVal", excludeVal)
		else
			saveVal = registeredSkill.saveVal
			logger.logDebug(SUBMODULE, "Found registered saveVal %d for skill %s for pilot %s", saveVal, skillId, pilotId)
		end
	end

	if not saveVal and storedSkill.saveVal and storedSkill.saveVal >= 0 then
		if storedSkill.saveVal == excludeVal then
			logger.logDebug(SUBMODULE, "Found stored saveVal %d but it conflicts with excludeVal", excludeVal)
		else
			saveVal = storedSkill.saveVal
			logger.logDebug(SUBMODULE, "Found stored saveVal %d for skill %s for pilot %s", saveVal, skillId, pilotId)
		end
	end

	if not saveVal and preassignedVal and preassignedVal >= 0 then
		if preassignedVal == excludeVal then
			logger.logDebug(SUBMODULE, "Found preassinged saveVal %d but it conflicts with excludeVal", excludeVal)
		else
			saveVal = preassignedVal
			logger.logDebug(SUBMODULE, "Found preassinged saveVal %d for skill %s for pilot %s", saveVal, skillId, pilotId)
		end
	end

	-- Check for conflict with excludeVal and reassign if needed
	if not saveVal then
		saveVal = self:_generateSaveVal(excludeVal)
		logger.logDebug(SUBMODULE, "SaveVal conflict detected for pilot %s, reassigned saveVal to %d", pilotId, saveVal)
	end

	-- Store the assigned saveVal
	storedSkill.saveVal = saveVal
	return saveVal
end

-- Apply specific skills to a pilot
-- Takes a memhack pilot struct and specific skill IDs to apply
-- skillIds: table with two skill IDs {skill1Id, skill2Id}
-- fireHooks: if true, fires skillsSelected hook before applying skills (defaults to false)
function skill_selection:applySkillIdsToPilot(pilot, skillIds, fireHooks)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "applySkillIdsToPilot: expected Pilot struct, got %s", type(pilot))
		return false
	end

	if type(skillIds) ~= "table" or #skillIds ~= 2 then
		logger.logError(SUBMODULE, "applySkillIdsToPilot: expected skillIds table with 2 entries, got %s", type(skillIds))
		return false
	end

	if type(skillIds[1]) ~= "string" or type(skillIds[2]) ~= "string" then
		logger.logError(SUBMODULE, "applySkillIdsToPilot: expected skillId strings, got %s and %s", type(skillIds[1]), type(skillIds[2]))
		return false
	end

	local pilotId = pilot:getIdStr()
	-- ensure game data is initialized
	skill_selection:_initGameSaveData()
	if not GAME.cplus_plus_ex.pilotSkills[pilotId] then
		GAME.cplus_plus_ex.pilotSkills[pilotId] = {}
	end

	-- Apply the skills to the pilot
	if fireHooks == nil then fireHooks = false end
	local storedSkills = { {id = skillIds[1]}, {id = skillIds[2]} }
	return self:_validateAndApplySkills(pilot, storedSkills, fireHooks)
end

-- Main function to apply level up skills to a pilot (handles both skill slots)
-- Takes a memhack pilot struct and applies both skill slots (1 and 2)
-- Checks GAME memory and either loads existing skills or creates and assigns new ones
-- fireHooks: if true, fires skillsSelected hook before applying skills (defaults to false)
function skill_selection:applySkillsToPilot(pilot, fireHooks)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "applySkillsToPilot: expected Pilot struct, got %s", type(pilot))
		return false
	end

	if fireHooks == nil then fireHooks = false end

	local availableSkills = self:getAssignableSkillIds()

	-- Use pilot ID as the key for storing skills for now. Multiple pilots with same ID is
	-- technically possible but not allowed by vanilla so this may change later
	local pilotId = pilot:getIdStr()

	-- Check if we have any stored pilot skills to determine if this is a new run or
	-- a mid run when CPLUS+ was enabled
	local hasAnyStoredSkills = false
	for _ in pairs(GAME.cplus_plus_ex.pilotSkills) do
		hasAnyStoredSkills = true
		break
	end

	-- Try to get stored skills
	local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]
	local skillIds = {}

	-- If the skills are not stored, we need to assign them
	local found = false
	if storedSkills ~= nil then
		logger.logDebug(SUBMODULE, "Read stored skill for pilot %s", pilotId)
		skillIds = {storedSkills[1].id, storedSkills[2].id}
		found = true
	end
	-- if its the time traveler, save the current skills
	if not found and cplus_plus_ex._subobjects.time_traveler.potentialTimeTravelers then
		local time_traveler = cplus_plus_ex._subobjects.time_traveler

		-- Check if this pilot is the time traveler and narrow down the list. There should only
		-- be one at this point that matches our address
		found = time_traveler:narrowTimeTraveler(pilot._address)
		if found then
			logger.logDebug(SUBMODULE, "Found time traveler pilot %s at %d", pilotId, pilot._address)

			-- Get regular skills from the time traveler pilot object
			local lus = time_traveler.potentialTimeTravelers[1]:getLvlUpSkills()
			skillIds = {lus:getSkill1():getIdStr(), lus:getSkill2():getIdStr()}
			storedSkills = { {id = skillIds[1]}, {id = skillIds[2]} }
			logger.logDebug(SUBMODULE, "Read time traveler skills for pilot %s", pilotId)

			-- Virtual skills are stored in GAME and not in the pilot object itself so we need to load
			-- these from persistent memory instead of from the time traveler directly
			local virtualSkills = time_traveler:refreshTimeTravlerDataAndGetVirtSkills(pilotId)
			if virtualSkills then
				self:_initGameSaveData()
				GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] = {}
				local loadedIds = {}
				for _, skillEntry in ipairs(virtualSkills) do
					-- Insert a copy
					table.insert(GAME.cplus_plus_ex.pilotVirtualSkills[pilotId], {
						id = skillEntry.id,
						source = skillEntry.source,
					})
					table.insert(loadedIds, skillEntry.id)
				end
				logger.logInfo(SUBMODULE, "Populated GAME state with %d virtual skills for time traveler %s: %s",
					#loadedIds, pilotId, table.concat(loadedIds, ", "))
			end
		end
	end
	-- Check if we should preserve existing vanilla skills
	-- If its the first run or a run without, try to preserve existing skills
	if not found and not hasAnyStoredSkills then
		local pilotXp = pilot:getXp()
		local pilotLevel = pilot:getLevel()

		if pilotXp > 0 or pilotLevel > 0 then
			-- Pilot existed before CPLUS+ was active - preserve their current skills
			local memSkill1 = pilot:getLvlUpSkill(1)
			local memSkill2 = pilot:getLvlUpSkill(2)

			if memSkill1 and memSkill2 then
				skillIds = {memSkill1:getIdStr(), memSkill2:getIdStr()}
				storedSkills = { {id = skillIds[1]}, {id = skillIds[2]} }
				found = true
				logger.logInfo(SUBMODULE, "Preserving existing skills for pilot " .. pilotId .. " (XP=" .. pilotXp ..
						", Level=" .. pilotLevel .. ") - first time with CPLUS+ active")
			end
		end
	end
	-- otherwise assign random skills
	if not found then
		-- Select 2 random skills that satisfy all registered constraint functions
		skillIds = self:selectRandomSkills(availableSkills, pilot, 2)
		if skillIds == nil then
			return false
		end
		-- Convert to table format so we can associat saveVals and update in game state
		storedSkills = { {id = skillIds[1]}, {id = skillIds[2]} }

		logger.logDebug(SUBMODULE, "Assigning random skills to pilot %s", pilotId)
	end

	-- Use common validation and application logic
	return self:_validateAndApplySkills(pilot, storedSkills, fireHooks)
end

-- Internal function to validate, assign saveVals, and apply skills to the pilot
-- Takes storedSkills structure: { {id = skill1Id}, {id = skill2Id} }
function skill_selection:_validateAndApplySkills(pilot, storedSkills, fireHooks)
	local pilotId = pilot:getIdStr()

	local skill1Id = storedSkills[1].id or "<unknown>"
	local skill2Id = storedSkills[2].id or "<unknown>"
	local skill1 = skill_config_module.enabledSkills[skill1Id]
	local skill2 = skill_config_module.enabledSkills[skill2Id]

	local skillIds = {skill1Id, skill2Id}
	local skill_registry_module = cplus_plus_ex._subobjects.skill_registry

	local function isInvalidAssignableSkill(skillId, skill, selectedSkills)
		if not skill then
			return true
		end
		if skill_registry_module:isInternalSkill(skillId) then
			return false
		end
		return not skill_constraints:checkSkillConstraints(pilot, selectedSkills, skillId)
	end

	-- If skills are disabled or now violate constraints, assign random ones
	if not skill2 then
		skillIds[2] = nil
	end
	-- Skill one is checked without skill2 regardless as its first assigned and as such
	-- has priority in any conflicts
	if isInvalidAssignableSkill(skill1Id, skill1, {}) then
		logger.logWarn(SUBMODULE, "Pilot " .. pilotId .. " skill 1 " .. skill1Id ..
				" is invalid (disabled or violates constraints), assigning new one")
		skillIds[1] = nil
		-- Create fresh copy of available skills for this slot to avoid contamination from other slot failures
		local availableSkillsSlot1 = self:getAssignableSkillIds()
		skill1Id = self:selectRandomSkill(availableSkillsSlot1, pilot, 1, skillIds)
		if not skill1Id then
			logger.logError(SUBMODULE, "Failed to find valid skill 1 for pilot " .. pilotId .. " - constraints too restrictive")
			return false
		end
		GAME.cplus_plus_ex.pilotSkills[pilotId][1] = {id = skill1Id}
		storedSkills[1] = {id = skill1Id}
		skillIds[1] = skill1Id
		skill1 = skill_config_module.enabledSkills[skill1Id]
	end
	if isInvalidAssignableSkill(skill2Id, skill2, {skill1Id}) then
		logger.logWarn(SUBMODULE, "Pilot " .. pilotId .. " skill 2 " .. skill2Id ..
				" is invalid (disabled or violates constraints), assigning new one")
		-- Create fresh copy of available skills for this slot to avoid contamination from other slot failures
		local availableSkillsSlot2 = self:getAssignableSkillIds()
		skill2Id = self:selectRandomSkill(availableSkillsSlot2, pilot, 2, skillIds)
		if not skill2Id then
			logger.logError(SUBMODULE, "Failed to find valid skill 2 for pilot " .. pilotId .. " - constraints too restrictive")
			return false
		end
		GAME.cplus_plus_ex.pilotSkills[pilotId][2] = {id = skill2Id}
		storedSkills[2] = {id = skill2Id}
		skillIds[2] = skill2Id
		skill2 = skill_config_module.enabledSkills[skill2Id]
	end

	-- Fire skillsSelected hook after selecting but before applying skills
	-- The other inRun/Active hooks will be called after they are set
	-- and the level up skills will also trigger if it changed
	if fireHooks then
		hooks.fireSkillsSelectedHooks(pilot, skill1Id, skill2Id)
	end

	-- Read current saveVals from memory (preassigned values to preserve if possible)
	local preassignedSaveVal1 = pilot:getLvlUpSkill(1) and pilot:getLvlUpSkill(1):getSaveVal() or nil
	local preassignedSaveVal2 = pilot:getLvlUpSkill(2) and pilot:getLvlUpSkill(2):getSaveVal() or nil

	-- Assign saveVals, ensuring they're different
	local saveVal1 = self:_getOrAssignSaveVal(storedSkills[1], skill1, pilotId, skill1Id, preassignedSaveVal1, nil)
	local saveVal2 = self:_getOrAssignSaveVal(storedSkills[2], skill2, pilotId, skill2Id, preassignedSaveVal2, saveVal1)
	-- Make sure save game data is updated
	GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills

	logger.logInfo(SUBMODULE, "Applying skills to pilot " .. pilotId .. ": [" .. storedSkills[1].id .. ", " .. storedSkills[2].id .. "]")

	-- Apply both skills with their determined saveVal
	if skill1Id ~= pilot:getLvlUpSkill(1):getIdStr() then
		local skill1Data = self:_skillDataToTable(
				skill1Id, skill1.shortName, skill1.fullName, skill1.description, saveVal1, skill1.bonuses)
		pilot:setLvlUpSkill(1, skill1Data)
	end
	if skill2Id ~= pilot:getLvlUpSkill(2):getIdStr() then
		local skill2Data = self:_skillDataToTable(
				skill2Id, skill2.shortName, skill2.fullName, skill2.description, saveVal2, skill2.bonuses)
		pilot:setLvlUpSkill(2, skill2Data)
	end

	-- Commit final level-up skills (including any rerolled during validation above)
	self:_markPerRunSkillAsUsed(skill1Id)
	self:_markPerRunSkillAsUsed(skill2Id)

	-- Validate virtual skills in GAME, sync runtime objects
	self:_validateAndSyncVirtualSkills(pilot)
	return true
end

-- Apply skills to all pilots - both squad and storage
function skill_selection:applySkillsToAllPilots()
	-- ensure game data is initialized
	self:_initGameSaveData()

	if #skill_config_module.enabledSkillsIds == 0 then
		logger.logWarn(SUBMODULE, "No enabled skills, skipping pilot skill assignment")
		return
	end

	-- Assign skills for all squad and storage pilots
	local pilots = Game:GetAvailablePilots()
	logger.logDebug(SUBMODULE, "Checking and maybe doing skill assignment for %d pilots", #pilots)

	-- Check if any pilots have not had skills assigned yet this run
	local newPilots = {}
	for _, pilot in pairs(pilots) do
		local pilotId = pilot:getIdStr()
		if not skill_selection._pilotsAssignedThisRun[pilotId] then
			table.insert(newPilots, pilot)
		end
	end
	local hasNewPilots = #newPilots > 0

	-- Only fire pre assignment hook if there are new pilots
	if hasNewPilots then
		logger.logDebug(SUBMODULE, "Found %d new pilot(s) to assign skills to", #newPilots)
		hooks.firePreAssigningLvlUpSkillsHooks()
	end

	-- Rebuild global per_run tracking from all pilots already in GAME (never unmark on skill removal)
	self:_rebuildUsedSkillsPerRunFromGameState(pilots)

	-- Assign skills to any new pilots which will include validating already
	-- selected skills against contraints and choosing new ones if they
	-- are no longer valid
	local successCount = 0
	local failCount = 0

	for _, pilot in pairs(newPilots) do
		local pilotId = pilot:getIdStr()
		local isNewPilot = not skill_selection._pilotsAssignedThisRun[pilotId]

		local success = self:applySkillsToPilot(pilot, isNewPilot)
		if success then
			successCount = successCount + 1
			-- Mark pilot as assigned this run
			if isNewPilot then
			   skill_selection._pilotsAssignedThisRun[pilotId] = true
			end
		else
			failCount = failCount + 1
			logger.logError(SUBMODULE, "Could not assign valid skills to pilot " .. pilotId ..
					" - constraints are impossible to satisfy. Check relationship settings.")
		end
	end

	if failCount > 0 then
		logger.logWarn(SUBMODULE, "Applied skills to " .. successCount .. " pilot(s), " .. failCount .. " failed due to impossible constraints")
	else
		logger.logDebug(SUBMODULE, "Successfully applied skills to " .. successCount .. " pilot(s)")
	end

	-- Only fire post assignment hook if there were new pilots
	if hasNewPilots then
		logger.logDebug(SUBMODULE, "Finished assigning skills")
		hooks.firePostAssigningLvlUpSkillsHooks()
	end
end

function skill_selection:_selectSkillsForPodPilot()
	-- If its a pilot, assign skills
	local pilot = Game:GetPodRewardPilot()
	if not pilot then return end

	local pilotId = pilot:getIdStr()
	-- It should always be a new pilot
	local isNewPilot = not skill_selection._pilotsAssignedThisRun[pilotId]

	if isNewPilot then
		-- Fire pre hook
		hooks.firePreAssigningLvlUpSkillsHooks()
	end

	-- Apply skills with hooks
	self:applySkillsToPilot(pilot, isNewPilot)

	if isNewPilot then
		skill_selection._pilotsAssignedThisRun[pilotId] = true
		hooks.firePostAssigningLvlUpSkillsHooks()
	end
end

function skill_selection:_selectSkillsForPerfectIslandPilot()
	-- If its a pilot, assign skills
	local pilot = Game:GetPerfectIslandRewardPilot()
	if not pilot then return end

	local pilotId = pilot:getIdStr()
	-- It may not be "new" if they minimized the menu and brought it back up
	local isNewPilot = not skill_selection._pilotsAssignedThisRun[pilotId]

	if isNewPilot then
		-- Fire pre hook
		hooks.firePreAssigningLvlUpSkillsHooks()
	end

	-- Apply skills with hooks
	self:applySkillsToPilot(pilot, isNewPilot)

	if isNewPilot then
		skill_selection._pilotsAssignedThisRun[pilotId] = true

		-- Fire post hook and immediately update states
		hooks.firePostAssigningLvlUpSkillsHooks()
	end
end

-- Validate and sync virtual skills for a pilot
-- Validates each virtual skill against constraints and removes invalid ones
-- Invalid ones can be specially handled with a registered callback or will be re-rolled otherwise
function skill_selection:_validateAndSyncVirtualSkills(pilot)
	self:_initGameSaveData()
	local pilotId = pilot:getIdStr()
	local virtualSkills = GAME.cplus_plus_ex.pilotVirtualSkills[pilotId]

	if not virtualSkills or #virtualSkills == 0 then
		return -- No virtual skills to validate
	end

	logger.logDebug(SUBMODULE, "Validating and syncing %d virtual skills for pilot %s", #virtualSkills, pilotId)

	-- Get only the real skills (not virtual) for constraint checking base
	local realSkills = {}
	for i = 1, cplus_plus_ex.MAX_SKILL_SLOTS do
		local skill = pilot:getLvlUpSkill(i)
		if skill then
			table.insert(realSkills, skill:getIdStr())
		end
	end

	-- Validate each virtual skill and handle invalid ones
	-- Start with the real skills for constraint checking
	local constraintCheckSkills = {}
	for _, realSkillId in ipairs(realSkills) do
		table.insert(constraintCheckSkills, realSkillId)
	end

	-- Rebuild the list as we go to ensure no gaps in slot ids
	local newVirtualSkills = {}
	for _, skillData in ipairs(virtualSkills) do
		local skillId = skillData.id
		local source = skillData.source or "unspecified"
		local skillSlot = #constraintCheckSkills + 1
		local skill = skill_config_module.enabledSkills[skillId]

		local isInvalid = false
		if not self:canBeVirtualSkill(skillId) then
			logger.logWarn(SUBMODULE, "Virtual skill %s at slot %d for pilot %s cannot be virtual, removing", skillId, skillSlot, pilotId)
			isInvalid = true
		elseif not skill then
			logger.logWarn(SUBMODULE, "Virtual skill %s at slot %d for pilot %s is disabled, removing", skillId, skillSlot, pilotId)
			isInvalid = true
		elseif not skill_constraints:checkSkillConstraints(pilot, constraintCheckSkills, skillId) then
			logger.logWarn(SUBMODULE, "Virtual skill %s at slot %d for pilot %s violates constraints, removing", skillId, skillSlot, pilotId)
			isInvalid = true
		end

		local newSkillId = skillId
		if isInvalid then
			local callback = self.virtualSkillSourceCallbacks[source]
			if not callback then
				local potentialSkills = self:_getVirtualCompatibleSkillPool()
				local rerolledSkillId = self:selectRandomSkill(potentialSkills, pilot, nil, constraintCheckSkills)
				if rerolledSkillId then
					newSkillId = rerolledSkillId
					logger.logInfo(SUBMODULE, "Rerolled virtual skill %s -> %s for pilot %s", skillId, newSkillId, pilotId)
				else
					newSkillId = nil
					logger.logWarn(SUBMODULE, "Failed to reroll invalid skill %s for pilot %s, removing", skillId, pilotId)
				end
			else
				local success, result = pcall(callback, pilot, skillData, constraintCheckSkills)
				if not success then
					newSkillId = nil
					logger.logError(SUBMODULE, "Error in onSkillInvalidated for source %s: %s", source, result)
				elseif result == nil then
					newSkillId = nil
					logger.logDebug(SUBMODULE, "Removing invalid virtual skill %s for pilot %s (source: %s) because callback returned nil", skillId, pilotId, source)
				elseif result == skillId then
					logger.logDebug(SUBMODULE, "Kept invalid virtual skill %s for pilot %s (source: %s)", skillId, pilotId, source)
				else
					newSkillId = result
					logger.logDebug(SUBMODULE, "Adding virtual skill %s for pilot %s (source: %s)", result, pilotId, source)
				end
			end
		end
		if newSkillId then
			table.insert(newVirtualSkills, { id = newSkillId, source = source })
			table.insert(constraintCheckSkills, newSkillId)
			self:_markPerRunSkillAsUsed(newSkillId)
		end
	end

	GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] = newVirtualSkills

	-- Sync runtime objects to validated GAME entries
	skill_state_tracker:_syncVirtualSkillObjects(pilot)
end

-- Rebuild global per_run used-skill tracking from GAME state for all pilots.
-- Called at the start of batch assignment; does not unmark skills removed mid-run.
function skill_selection:_rebuildUsedSkillsPerRunFromGameState(pilots)
	self.usedSkillsPerRun = {}
	for _, pilot in pairs(pilots) do
		local pilotId = pilot:getIdStr()
		local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]
		if storedSkills then
			for _, skillData in ipairs(storedSkills) do
				if skillData and skillData.id then
					self:_markPerRunSkillAsUsed(skillData.id)
				end
			end
		end
		local virtualSkills = GAME.cplus_plus_ex.pilotVirtualSkills[pilotId]
		if virtualSkills then
			for _, skillEntry in ipairs(virtualSkills) do
				local skillId = skillEntry.id
				if skillId then
					self:_markPerRunSkillAsUsed(skillId)
				end
			end
		end
	end
end

-- Record a skill as assigned this run (per_run skills only).
-- Call after a skill is applied to a pilot, not during pool selection.
-- Never unmarks on removal - applySkillsToAllPilots rebuilds from GAME when selecitng new skills.
function skill_selection:_markPerRunSkillAsUsed(skillId)
	local skill = skill_config_module.enabledSkills[skillId]
	if skill == nil then
		return
	end

	if skill_config_module.config.skillConfigs[skillId].reusability == cplus_plus_ex.REUSABLILITY.PER_RUN then
		if self.usedSkillsPerRun[skillId] then
			logger.logDebug(SUBMODULE, "per_run skill %s already committed this run", skillId)
		else
			self.usedSkillsPerRun[skillId] = true
			logger.logDebug(SUBMODULE, "Committed per_run skill %s for this run", skillId)
		end
	end
	-- reusable and per_pilot skills don't need tracking
end

return skill_selection
