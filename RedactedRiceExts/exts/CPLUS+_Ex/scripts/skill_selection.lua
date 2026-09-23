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
skill_selection._pilotsAssignedThisRun = {}  -- pilotUid -> true for pilots assigned this run
skill_selection.virtualSkillSourceCallbacks = {}  -- sourceId -> onSkillInvalidatedCallback

-- Local references to other submodules (set during init)
local skill_constraints = nil
local skill_config_module = nil
local utils = nil
local hooks = nil
local skill_state_tracker = nil
local pilot_uid = nil

-- Initialize the module
function skill_selection:init()
	skill_constraints = cplus_plus_ex._subobjects.skill_constraints
	skill_config_module = cplus_plus_ex._subobjects.skill_config
	utils = cplus_plus_ex._subobjects.utils
	hooks = cplus_plus_ex._subobjects.hooks
	skill_state_tracker = cplus_plus_ex._subobjects.skill_state_tracker
	pilot_uid = cplus_plus_ex._subobjects.pilot_uid

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
	local pilotUid = pilot:getUidStr()
	local successCount = 0

	-- Initialize virtual skills array for this pilot if needed
	if not GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid] then
		GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid] = {}
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
				table.insert(GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid], {
						id = skillId,
						source = source,
				})

				logger.logDebug(SUBMODULE, "Added virtual skill %s (source: %s) to pilot %s at slot %d",
						skillId, source, pilot:getUidStr(),
						cplus_plus_ex.MAX_SKILL_SLOTS + #GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid])

				self:markPerRunSkillAsUsed(skillId)
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
	local pilotUid = pilot:getUidStr()

	-- Replace the entire virtual skills array (like applySkillIdsToPilot does for regular skills)
	GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid] = {}

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
				table.insert(GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid], {
					id = skillId,
					source = entrySource,
				})
				self:markPerRunSkillAsUsed(skillId)
				logger.logInfo(SUBMODULE, "Applied virtual skill %s (source: %s) to pilot %s (slot %d)",
						skillId, entrySource, pilot:getUidStr(),
						cplus_plus_ex.MAX_SKILL_SLOTS + #GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid])
			end
		end
	end

	if #GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid] > 0 then
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
		local pilotUid = pilot:getUidStr()
		self:_initGameSaveData()
		local virtualSlotIndex = cplus_plus_ex.MAX_SKILL_SLOTS + #(GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid] or {}) + 1

		local skillId = self:selectRandomSkill(potentialSkills, pilot, virtualSlotIndex, assignedSkills)

		if skillId then
			table.insert(selectedSkills, skillId)
			table.insert(assignedSkills, skillId)
			logger.logDebug(SUBMODULE, "Selected random virtual skill %s for pilot %s (source: %s)",
				skillId, pilot:getUidStr(), source)
		else
			logger.logWarn(SUBMODULE, "Failed to find valid random virtual skill %d for pilot %s", i, pilot:getUidStr())
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
	local pilotUid = pilot:getUidStr()
	local virtualSkills = GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid]

	if not virtualSkills or #virtualSkills == 0 then
		logger.logWarn(SUBMODULE, "Pilot %s has no virtual skills to remove", pilot:getUidStr())
		return false
	end

	for i, skillData in ipairs(virtualSkills) do
		if skillData.id == skillId then
			-- Remove from save data
			table.remove(virtualSkills, i)
			logger.logInfo(SUBMODULE, "Removed virtual skill %s from pilot %s", skillId, pilot:getUidStr())

			-- Remove the corresponding object from state tracker
			skill_state_tracker:_removeVirtualSkillObjectBySkillId(pilot, skillId)

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
	local pilotUid = pilot:getUidStr()

	-- Clear save data
	GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid] = {}
	logger.logInfo(SUBMODULE, "Cleared all virtual skills from pilot %s", pilot:getUidStr())

	-- Clear the corresponding objects from state tracker
	skill_state_tracker:_clearVirtualSkillObjects(pilot)

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

		if skill_constraints:checkSkillConstraints(pilot, selectedSkills, candidateSkillId, idx) then
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

	local pilotUid = pilot:getUidStr()

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

	self:_initGameSaveData()

	local availableSkills = self:getAssignableSkillIds()

	-- Try to get stored skills by pilot UID
	local pilotUid = pilot:getUidStr()
	local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotUid]
	local skillIds = {}

	-- If the skills are not stored, we need to assign them
	local found = false
	if storedSkills ~= nil then
		-- Incomplete entries (e.g. empty table left by a failed validate) must not
		-- short-circuit time-traveler / preserve / random assignment paths
		if storedSkills[1] and storedSkills[2]
				and type(storedSkills[1].id) == "string" and type(storedSkills[2].id) == "string" then
			logger.logDebug(SUBMODULE, "Read stored skill for pilot %s", pilot:getUidStr())
			skillIds = {storedSkills[1].id, storedSkills[2].id}
			found = true
		else
			logger.logWarn(SUBMODULE, "Clearing incomplete stored skills for pilot %s", pilot:getUidStr())
			GAME.cplus_plus_ex.pilotSkills[pilotUid] = nil
			storedSkills = nil
		end
	end
	-- if its the time traveler, save the current skills
	if not found and cplus_plus_ex._subobjects.time_traveler.potentialTimeTravelers then
		local time_traveler = cplus_plus_ex._subobjects.time_traveler

		-- Check if this pilot is the time traveler and narrow down the list. There should only
		-- be one at this point that matches our address
		found = time_traveler:narrowTimeTraveler(pilot._address)
		if found then
			logger.logDebug(SUBMODULE, "Found time traveler pilot %s at %d", pilot:getUidStr(), pilot._address)

			-- Get regular skills from the time traveler pilot object
			local lus = time_traveler.potentialTimeTravelers[1]:getLvlUpSkills()
			skillIds = {lus:getSkill1():getIdStr(), lus:getSkill2():getIdStr()}
			storedSkills = { {id = skillIds[1]}, {id = skillIds[2]} }
			logger.logDebug(SUBMODULE, "Read time traveler skills for pilot %s", pilot:getUidStr())

			-- Virtual skills are stored in GAME and not in the pilot object itself so we need to load
			-- these from persistent memory instead of from the time traveler directly
			local virtualSkills = time_traveler:refreshTimeTravlerDataAndGetVirtSkills(pilot)
			if virtualSkills then
				GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid] = {}
				local loadedIds = {}
				for _, skillEntry in ipairs(virtualSkills) do
					-- Insert a copy
					table.insert(GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid], {
						id = skillEntry.id,
						source = skillEntry.source,
					})
					table.insert(loadedIds, skillEntry.id)
				end
				logger.logInfo(SUBMODULE, "Populated GAME state with %d virtual skills for time traveler %s: %s",
					#loadedIds, pilot:getUidStr(), table.concat(loadedIds, ", "))
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

		logger.logDebug(SUBMODULE, "Assigning random skills to pilot %s", pilot:getUidStr())
	end

	-- Use common validation and application logic
	return self:_validateAndApplySkills(pilot, storedSkills, fireHooks)
end

-- Check whether a skill is invalid for assignment
function skill_selection:_isInvalidAssignableSkill(pilot, skillId, skill, selectedSkills, slotIdx)
	if not skill then
		return true
	end
	local skill_registry_module = cplus_plus_ex._subobjects.skill_registry
	if skill_registry_module:isInternalSkill(skillId) then
		return false
	end
	return not skill_constraints:checkSkillConstraints(pilot, selectedSkills, skillId, slotIdx)
end

-- Check whether an already stored skill can be kept.
-- Temporarily ignore this pilot's own per_run claim from rebuild so we don't self block.
function skill_selection:_isInvalidExistingSkill(pilot, skillId, skill, selectedSkills, slotIdx)
	self:unmarkPerRunSkill(skillId)
	local invalid = self:_isInvalidAssignableSkill(pilot, skillId, skill, selectedSkills, slotIdx)
	if not invalid then
		self:markPerRunSkillAsUsed(skillId)
	end
	return invalid
end

-- Internal function to validate and apply skills to the pilot.
-- saveVals are UID tokens and are preserved across skill id changes.
-- Takes storedSkills structure: { {id = skill1Id}, {id = skill2Id} }
-- Only commits GAME.cplus_plus_ex.pilotSkills[pilotUid] on full success so failed
-- validation never leaves an empty/partial entry that blocks later assignment.
function skill_selection:_validateAndApplySkills(pilot, storedSkills, fireHooks)
	local pilotUid = pilot:getUidStr()

	self:_initGameSaveData()

	local skill1Id = storedSkills[1].id or "<unknown>"
	local skill2Id = storedSkills[2].id or "<unknown>"
	local skill1 = skill_config_module.enabledSkills[skill1Id]
	local skill2 = skill_config_module.enabledSkills[skill2Id]

	-- Skill 1 is checked first and has priority over skill 2
	if self:_isInvalidExistingSkill(pilot, skill1Id, skill1, {}, 1) then
		logger.logWarn(SUBMODULE, "Pilot " .. pilot:getUidStr() .. " skill 1 " .. skill1Id ..
				" is invalid (disabled or violates constraints), assigning new one")
		local selectedForSlot1 = {}
		local availableSkillsSlot1 = self:getAssignableSkillIds()
		local newSkill1Id = self:selectRandomSkill(availableSkillsSlot1, pilot, 1, selectedForSlot1)
		if not newSkill1Id then
			logger.logError(SUBMODULE, "Failed to find valid skill 1 for pilot " .. pilot:getUidStr() .. " - constraints too restrictive")
			return false
		end
		skill1Id = newSkill1Id
		storedSkills[1] = {id = skill1Id}
		skill1 = skill_config_module.enabledSkills[skill1Id]
	end

	if self:_isInvalidExistingSkill(pilot, skill2Id, skill2, {skill1Id}, 2) then
		logger.logWarn(SUBMODULE, "Pilot " .. pilot:getUidStr() .. " skill 2 " .. skill2Id ..
				" is invalid (disabled or violates constraints), assigning new one")
		-- Only skill1 as prior selection. Do not include old skill2 (would make slot idx infer as 3).
		local selectedForSlot2 = {skill1Id}
		local availableSkillsSlot2 = self:getAssignableSkillIds()
		local newSkill2Id = self:selectRandomSkill(availableSkillsSlot2, pilot, 2, selectedForSlot2)
		if not newSkill2Id then
			-- Roll back skill 1 claim if it was marked during revalidation above
			self:unmarkPerRunSkill(skill1Id)
			logger.logError(SUBMODULE, "Failed to find valid skill 2 for pilot " .. pilot:getUidStr() .. " - constraints too restrictive")
			return false
		end
		skill2Id = newSkill2Id
		storedSkills[2] = {id = skill2Id}
		skill2 = skill_config_module.enabledSkills[skill2Id]
	end

	-- Fire skillsSelected hook after selecting but before applying skills
	-- The other inRun/Active hooks will be called after they are set
	-- and the level up skills will also trigger if it changed
	if fireHooks then
		hooks.fireSkillsSelectedHooks(pilot, skill1Id, skill2Id)
	end

	-- Get the stored skills
	GAME.cplus_plus_ex.pilotSkills[pilotUid] = storedSkills
	logger.logInfo(SUBMODULE, "Applying skills to pilot " .. pilot:getUidStr() ..
		": [" .. storedSkills[1].id .. ", " .. storedSkills[2].id .. "]")

	-- Apply skill ids/text/bonuses but keep UID saveVals.
	-- Always rewrite when id changes; also rewrite if saveVals drifted off UID.
	local cur1 = pilot:getLvlUpSkill(1)
	local cur2 = pilot:getLvlUpSkill(2)
	local saveVal1, saveVal2 = pilot_uid:_readSaveValPair(pilot)
	local need1 = skill1Id ~= cur1:getIdStr() or cur1:getSaveVal() ~= saveVal1
	local need2 = skill2Id ~= cur2:getIdStr() or cur2:getSaveVal() ~= saveVal2

	if need1 then
		local skill1Data = self:_skillDataToTable(
				skill1Id, skill1.shortName, skill1.fullName, skill1.description, saveVal1, skill1.bonuses)
		pilot:setLvlUpSkill(1, skill1Data)
	end
	if need2 then
		local skill2Data = self:_skillDataToTable(
				skill2Id, skill2.shortName, skill2.fullName, skill2.description, saveVal2, skill2.bonuses)
		pilot:setLvlUpSkill(2, skill2Data)
	end

	-- Commit final level-up skills (including any rerolled during validation above)
	self:markPerRunSkillAsUsed(skill1Id)
	self:markPerRunSkillAsUsed(skill2Id)

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
		local uid = pilot:getUidStr()
		if not skill_selection._pilotsAssignedThisRun[uid] then
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
		local uid = pilot:getUidStr()
		local isNewPilot = not skill_selection._pilotsAssignedThisRun[uid]

		local success = self:applySkillsToPilot(pilot, isNewPilot)
		if success then
			successCount = successCount + 1
			-- Mark pilot as assigned this run
			if isNewPilot then
				skill_selection._pilotsAssignedThisRun[uid] = true
			end
		else
			failCount = failCount + 1
			logger.logError(SUBMODULE, "Could not assign valid skills to pilot " .. pilot:getUidStr() ..
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
	self:_assignNewPilot(pilot)
end

function skill_selection:_selectSkillsForPerfectIslandPilot()
	-- If its a pilot, assign skills
	local pilot = Game:GetPerfectIslandRewardPilot()
	if not pilot then return end
	self:_assignNewPilot(pilot)
end

function skill_selection:_assignNewPilot(pilot)
	local uid = pilot:getUidStr()
	local isNewPilot = not skill_selection._pilotsAssignedThisRun[uid]

	if isNewPilot then
		-- Fire pre hook
		hooks.firePreAssigningLvlUpSkillsHooks()
	end

	-- Apply skills with hooks
	self:applySkillsToPilot(pilot, isNewPilot)

	if isNewPilot then
		-- Fire pre hook
		skill_selection._pilotsAssignedThisRun[uid] = true
		hooks.firePostAssigningLvlUpSkillsHooks()
	end
end

-- Validate and sync virtual skills for a pilot
-- Validates each virtual skill against constraints and removes invalid ones
-- Invalid ones can be specially handled with a registered callback or will be re-rolled otherwise
function skill_selection:_validateAndSyncVirtualSkills(pilot)
	self:_initGameSaveData()
	local pilotUid = pilot:getUidStr()
	local virtualSkills = GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid]

	if not virtualSkills or #virtualSkills == 0 then
		return -- No virtual skills to validate
	end

	logger.logDebug(SUBMODULE, "Validating and syncing %d virtual skills for pilot %s",
		#virtualSkills, pilot:getUidStr())

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
			logger.logWarn(SUBMODULE, "Virtual skill %s at slot %d for pilot %s cannot be virtual, removing",
				skillId, skillSlot, pilot:getUidStr())
			isInvalid = true
		elseif not skill then
			logger.logWarn(SUBMODULE, "Virtual skill %s at slot %d for pilot %s is disabled, removing",
				skillId, skillSlot, pilot:getUidStr())
			isInvalid = true
		elseif not skill_constraints:checkSkillConstraints(pilot, constraintCheckSkills, skillId) then
			logger.logWarn(SUBMODULE, "Virtual skill %s at slot %d for pilot %s violates constraints, removing",
				skillId, skillSlot, pilot:getUidStr())
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
					logger.logInfo(SUBMODULE, "Rerolled virtual skill %s -> %s for pilot %s", skillId, newSkillId, pilot:getUidStr())
				else
					newSkillId = nil
					logger.logWarn(SUBMODULE, "Failed to reroll invalid skill %s for pilot %s, removing", skillId, pilot:getUidStr())
				end
			else
				local success, result = pcall(callback, pilot, skillData, constraintCheckSkills)
				if not success then
					newSkillId = nil
					logger.logError(SUBMODULE, "Error in onSkillInvalidated for source %s: %s", source, result)
				elseif result == nil then
					newSkillId = nil
					logger.logDebug(SUBMODULE, "Removing invalid virtual skill %s for pilot %s (source: %s) because callback returned nil", skillId, pilot:getUidStr(), source)
				elseif result == skillId then
					logger.logDebug(SUBMODULE, "Kept invalid virtual skill %s for pilot %s (source: %s)", skillId, pilot:getUidStr(), source)
				else
					newSkillId = result
					logger.logDebug(SUBMODULE, "Adding virtual skill %s for pilot %s (source: %s)", result, pilot:getUidStr(), source)
				end
			end
		end
		if newSkillId then
			table.insert(newVirtualSkills, { id = newSkillId, source = source })
			table.insert(constraintCheckSkills, newSkillId)
			self:markPerRunSkillAsUsed(newSkillId)
		end
	end

	GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid] = newVirtualSkills

	-- Sync runtime objects to validated GAME entries
	skill_state_tracker:_syncVirtualSkillObjects(pilot)
end

-- Rebuild global per_run used-skill tracking from GAME state for all pilots.
-- Called at the start of batch assignment; does not unmark skills removed mid-run.
function skill_selection:_rebuildUsedSkillsPerRunFromGameState(pilots)
	self.usedSkillsPerRun = {}
	for _, pilot in pairs(pilots) do
		local pilotUid = pilot:getUidStr()
		local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotUid]
		if storedSkills then
			for _, skillData in ipairs(storedSkills) do
				if skillData and skillData.id then
					self:markPerRunSkillAsUsed(skillData.id)
				end
			end
		end
		local virtualSkills = GAME.cplus_plus_ex.pilotVirtualSkills[pilotUid]
		if virtualSkills then
			for _, skillEntry in ipairs(virtualSkills) do
				local skillId = skillEntry.id
				if skillId then
					self:markPerRunSkillAsUsed(skillId)
				end
			end
		end
	end
end

-- Record a skill as assigned this run (per_run skills only).
-- Call after a skill is applied to a pilot, not during pool selection.
-- Never unmarks on removal - applySkillsToAllPilots rebuilds from GAME when selecitng new skills.
function skill_selection:markPerRunSkillAsUsed(skillId)
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

-- Release a per_run claim so a pilot can keep or replace their own stored skill during revalidation.
function skill_selection:unmarkPerRunSkill(skillId)
	if not skillId or not self.usedSkillsPerRun[skillId] then
		return
	end

	local config = skill_config_module.config.skillConfigs[skillId]
	-- Unmark even if currently disabled so replacement selection isn't blocked by a stale claim
	if not config or config.reusability == cplus_plus_ex.REUSABLILITY.PER_RUN then
		self.usedSkillsPerRun[skillId] = nil
		logger.logDebug(SUBMODULE, "Released per_run claim for skill %s", skillId)
	end
end

return skill_selection
