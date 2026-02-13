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

-- Local references to other submodules (set during init)
local skill_constraints = nil
local skill_config_module = nil
local utils = nil
local hooks = nil

-- Initialize the module
function skill_selection:init()
	skill_constraints = cplus_plus_ex._subobjects.skill_constraints
	skill_config_module = cplus_plus_ex._subobjects.skill_config
	utils = cplus_plus_ex._subobjects.utils
	hooks = cplus_plus_ex._subobjects.hooks

	return self
end

-- Clear pilot assignment tracking used on reset/enter/exit events
function skill_selection:clearPilotTracking()
	self._pilotsAssignedThisRun = {}
end

-- Initialize game save data for skills
-- technically redundant with the data in modloader save data
-- but this is a more intuitive spot for it and only the minimal
-- needed data for skills
function skill_selection:initGameSaveData()
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

function skill_selection:_createAvailableSkills()
	-- Create a copy of all available skill IDs as an array. This will be our
	-- base list and we will narrow it down as we go if we try to assign
	-- an unallowed skill
	local availableSkills = {}
	for _, skillId in ipairs(skill_config_module.enabledSkillsIds) do
		table.insert(availableSkills, skillId)
	end
	return availableSkills
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
			selectedSkills[idx] = candidateSkillId
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
-- I pass count even though its currently only expected to be 2 just because I feel
-- like it could be interesting and possible to have pilots with more than two skills
function skill_selection:selectRandomSkills(availableSkills, pilot, count)
	if #skill_config_module.enabledSkillsIds == 0 then
		logger.logError(SUBMODULE, "No enabled skills available")
		return nil
	end

	local selectedSkills = {}

	for idx = 1, count do
		if not self:selectRandomSkill(availableSkills, pilot, idx, selectedSkills) then
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

function skill_selection:skillDataToTable(id, shortName, fullName, description, saveVal, bonuses)
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

-- Main function to apply level up skills to a pilot (handles both skill slots)
-- Takes a memhack pilot struct and applies both skill slots (1 and 2)
-- Checks GAME memory and either loads existing skills or creates and assigns new ones
-- fireHooks: if true, fires skillsSelected hook before applying skills (defaults to false)
function skill_selection:applySkillsToPilot(pilot, fireHooks)
	if pilot == nil then
		logger.logWarn(SUBMODULE, "Pilot is nil in applySkillsToPilot - skipping")
		return
	end

	if fireHooks == nil then fireHooks = false end

	local availableSkills = self:_createAvailableSkills()

	-- Use pilot ID as the key for storing skills for now. Multiple pilots with same ID is
	-- technically possible but not allowed by vanilla so this may change later
	local pilotId = pilot:getIdStr()

	-- Try to get stored skills
	local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]
	local skillIds = {}

	-- If the skills are not stored, we need to assign them
	if storedSkills ~= nil then
		logger.logDebug(SUBMODULE, "Read stored skill for pilot %s", pilotId)
		skillIds = {storedSkills[1].id, storedSkills[2].id}
	-- if its the time traveler, save the current skills
	elseif cplus_plus_ex._subobjects.time_traveler.timeTraveler and cplus_plus_ex._subobjects.time_traveler.timeTraveler._address == pilot._address then
		local lus = cplus_plus_ex._subobjects.time_traveler.timeTraveler:getLvlUpSkills()
		skillIds = {lus:getSkill1():getIdStr(), lus:getSkill2():getIdStr()}
		storedSkills = { {id = skillIds[1]}, {id = skillIds[2]} }
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills
		logger.logDebug(SUBMODULE, "Read time traveler skills for pilot %s", pilotId)
	-- otherwise assign random skills
	else
		-- Select 2 random skills that satisfy all registered constraint functions
		skillIds = self:selectRandomSkills(availableSkills, pilot, 2)
		if skillIds == nil then
			return
		end
		-- Convert to table format so we can associat saveVals and update in game state
		storedSkills = { {id = skillIds[1]}, {id = skillIds[2]} }
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills

		-- Track newly assigned skills for per_run constraints
		self:_markPerRunSkillAsUsed(skillIds[1])
		self:_markPerRunSkillAsUsed(skillIds[2])

		logger.logDebug(SUBMODULE, "Assigning random skills to pilot %s", pilotId)
	end

	local skill1Id = skillIds[1] or "<unknown>"
	local skill2Id = skillIds[2] or "<unknown>"
	local skill1 = skill_config_module.enabledSkills[skill1Id]
	local skill2 = skill_config_module.enabledSkills[skill2Id]

	if not skill2 then
		skillIds[2] = nil
	end
	if not skill1 then
		logger.logWarn(SUBMODULE, "Pilot " .. pilotId .. " skill 1 " .. skill1Id .. " is disabled, assigning new one")
		skillIds[1] = nil
		skill1Id = self:selectRandomSkill(availableSkills, pilot, 1, skillIds)
		GAME.cplus_plus_ex.pilotSkills[pilotId][1] = {id = skill1Id}
		storedSkills[1] = {id = skill1Id}
		skill1 = skill_config_module.enabledSkills[skill1Id]
	end
	if not skill2 then
		logger.logWarn(SUBMODULE, "Pilot " .. pilotId .. " skill 2 " .. skill2Id .. " is disabled, assigning new one")
		skill2Id = self:selectRandomSkill(availableSkills, pilot, 2, skillIds)
		GAME.cplus_plus_ex.pilotSkills[pilotId][2] = {id = skill2Id}
		storedSkills[2] = {id = skill2Id}
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

	logger.logInfo(SUBMODULE, "Applying skills to pilot " .. pilotId .. ": [" .. storedSkills[1].id .. ", " .. storedSkills[2].id .. "]")

	-- Apply both skills with their determined saveVal
	if skill1Id ~= pilot:getLvlUpSkill(1):getIdStr() then
		pilot:setLvlUpSkill(1, self:skillDataToTable(
				skill1Id, skill1.shortName, skill1.fullName, skill1.description, saveVal1, skill1.bonuses))
	end
	if skill2Id ~= pilot:getLvlUpSkill(2):getIdStr() then
		pilot:setLvlUpSkill(2, self:skillDataToTable(
				skill2Id, skill2.shortName, skill2.fullName, skill2.description, saveVal2, skill2.bonuses))
	end

end


-- Apply skills to all pilots - both squad and storage
function skill_selection:applySkillsToAllPilots()
	-- ensure game data is initialized
	self:initGameSaveData()

	if #skill_config_module.enabledSkillsIds == 0 then
		logger.logWarn(SUBMODULE, "No enabled skills, skipping pilot skill assignment")
		return
	end

	-- Assign skills for all squad and storage pilots
	local pilots = Game:GetAvailablePilots()
	logger.logDebug(SUBMODULE, "Starting skill assignment for %d pilots", #pilots)

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

	-- Reset per_run tracking and rebuild it from all pilots with stored skills
	-- We need to check all pilots because per_run tracking is global
	skill_selection.usedSkillsPerRun = {}
	for idx, pilot in pairs(pilots) do
		local pilotId = pilot:getIdStr()
		local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]

		if storedSkills ~= nil then
			-- This pilot has assigned skills, mark them as used for per_run tracking
			for _, skillData in ipairs(storedSkills) do
				self:_markPerRunSkillAsUsed(skillData.id)
			end
		else
			logger.logWarn(SUBMODULE, "Stored skills for pilot %s are nil in applySkillsToAllPilots - skipping", idx)
		end
	end

	-- Assign skills to any pilots (this handles the reset turn case)
	for _, pilot in pairs(pilots) do
		local pilotId = pilot:getIdStr()
		local isNewPilot = not skill_selection._pilotsAssignedThisRun[pilotId]

		self:applySkillsToPilot(pilot, isNewPilot)

		-- Mark pilot as assigned this run
		if isNewPilot then
			skill_selection._pilotsAssignedThisRun[pilotId] = true
		end
	end

	logger.logInfo(SUBMODULE, "Applied skills to " .. #pilots .. " pilot(s)")

	-- Only fire post assignment hook if there were new pilots
	if hasNewPilots then
		hooks.firePostAssigningLvlUpSkillsHooks()
	end
end

function skill_selection:applySkillToPodPilot()
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

function skill_selection:applySkillToPerfectIslandPilot()
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

-- Marks a per_run skill as used for this run
-- Only per_run skills need global tracking - per_pilot is handled by constraint checking selectedSkills
function skill_selection:_markPerRunSkillAsUsed(skillId)
	local skill = skill_config_module.enabledSkills[skillId]
	if skill == nil then
		return
	end

	if skill_config_module.config.skillConfigs[skillId].reusability == cplus_plus_ex.REUSABLILITY.PER_RUN then
		-- Check if already marked
		if skill_selection.usedSkillsPerRun[skillId] then
			logger.logWarn(SUBMODULE, "per_run skill " .. skillId .. " already marked as used")
		end

		-- Mark skill as used this run
		skill_selection.usedSkillsPerRun[skillId] = true
		logger.logDebug(SUBMODULE, "Marked per_run skill %s as used this run", skillId)
	end
	-- reusable and per_pilot skills don't need tracking
end

return skill_selection
