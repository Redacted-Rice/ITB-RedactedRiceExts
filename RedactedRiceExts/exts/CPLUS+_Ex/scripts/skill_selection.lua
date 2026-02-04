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

-- Local references to other submodules (set during init)
local skill_constraints = nil
local skill_config_module = nil
local utils = nil

-- Initialize the module
function skill_selection:init()
	skill_constraints = cplus_plus_ex._subobjects.skill_constraints
	skill_config_module = cplus_plus_ex._subobjects.skill_config
	utils = cplus_plus_ex._subobjects.utils

	modApi.events.onPodWindowShown:subscribe(function() skill_selection:applySkillToPodPilot() end)
	modApi.events.onPerfectIslandWindowShown:subscribe(function() skill_selection:applySkillToPerfectIslandPilot() end)
	return self
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
function skill_selection:getWeightedRandomSkillId(availableSkills)
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

function skill_selection:createAvailableSkills()
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
		local candidateSkillId = skill_selection:getWeightedRandomSkillId(availableSkills)
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

local function skillDataToTable(id, shortName, fullName, description, saveVal, bonuses)
	return {id = id, shortName = shortName, fullName = fullName, description = description,
		healthBonus = bonuses.health, coresBonus = bonuses.cores, gridBonus = bonuses.grid,
		moveBonus = bonuses.move, saveVal = saveVal}
end

-- TODO: Removing pilots in between seems to cause issues

-- Main function to apply level up skills to a pilot (handles both skill slots)
-- Takes a memhack pilot struct and applies both skill slots (1 and 2)
-- Checks GAME memory and either loads existing skills or creates and assigns new ones
function skill_selection:applySkillsToPilot(pilot)
	if pilot == nil then
		logger.logWarn(SUBMODULE, "Pilot is nil in applySkillsToPilot - skipping")
		return
	end

	local availableSkills = self:createAvailableSkills()

	-- Use pilot ID as the key for storing skills for now. Multiple pilots with same ID is
	-- technically possible but not allowed by vanilla so this may change later
	local pilotId = pilot:getIdStr()

	-- Try to get stored skills
	local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]

	-- If the skills are not stored, we need to assign them
	if storedSkills ~= nil then
		logger.logDebug(SUBMODULE, "Read stored skill for pilot %s", pilotId)
	-- if its the time traveler, save the current skills
	elseif cplus_plus_ex._subobjects.time_traveler.timeTraveler and cplus_plus_ex._subobjects.time_traveler.timeTraveler._address == pilot._address then
		local lus = cplus_plus_ex._subobjects.time_traveler.timeTraveler:getLvlUpSkills()
		storedSkills = {lus:getSkill1():getIdStr(), lus:getSkill2():getIdStr()}
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills
		logger.logDebug(SUBMODULE, "Read time traveler skills for pilot %s", pilotId)
	-- otherwise assign random skills
	else
		-- Select 2 random skills that satisfy all registered constraint functions
		storedSkills = skill_selection:selectRandomSkills(availableSkills, pilot, 2)
		if storedSkills == nil then
			return
		end

		-- Store the skills in GAME
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills

		-- Track newly assigned skills for per_run constraints
		skill_selection:markPerRunSkillAsUsed(storedSkills[1])
		skill_selection:markPerRunSkillAsUsed(storedSkills[2])

		logger.logDebug(SUBMODULE, "Assigning random skills to pilot %s", pilotId)
	end

	local skill1Id = storedSkills[1]
	local skill2Id = storedSkills[2]
	local skill1 = skill_config_module.enabledSkills[skill1Id]
	local skill2 = skill_config_module.enabledSkills[skill2Id]

	if not skill2 then
		storedSkills[2] = nil
	end
	if not skill1 then
		skill1Id = skill1Id or "<unknown>"
		logger.logWarn(SUBMODULE, "Pilot " .. pilotId .. " skill 1 " .. skill1Id ..
				" is disabled, assigning new one")
		storedSkills[1] = nil
		skill1Id = self:selectRandomSkill(availableSkills, pilot, 1, storedSkills)
		GAME.cplus_plus_ex.pilotSkills[pilotId][1] = skill1Id
		skill1 = skill_config_module.enabledSkills[skill1Id]
	end
	if not skill2 then
		skill2Id = skill2Id or "<unknown>"
		logger.logWarn(SUBMODULE, "Pilot %s skill 2 %s is disabled, assigning new one", pilotId, skill2Id)
		skill2Id = self:selectRandomSkill(availableSkills, pilot, 2, storedSkills)
		GAME.cplus_plus_ex.pilotSkills[pilotId][2] = skill2Id
		skill2 = skill_config_module.enabledSkills[skill2Id]
	end


	-- Determine saveVal for skill 1
	-- If skill has saveVal = -1, assign random value (0-13)
	local saveVal1 = skill1.saveVal
	if saveVal1 == -1 then
		saveVal1 = math.random(0, 13)
		logger.logDebug(SUBMODULE, "Assigned random saveVal %d to skill %s for pilot %s", saveVal1, skill1Id, pilotId)
	end

	-- Determine saveVal for skill 2
	-- If skill has saveVal = -1, assign random value (0-13)
	local saveVal2 = skill2.saveVal
	if saveVal2 == -1 then
		saveVal2 = math.random(0, 13)
		logger.logDebug(SUBMODULE, "Assigned random saveVal %d to skill %s for pilot %s", saveVal2, skill2Id, pilotId)
	end

	-- If both skills have the same saveVal, reassign skill2
	if saveVal1 == saveVal2 then
		-- Generate from 0-12, increment if >= saveVal1 to exclude skill1's value
		-- This guarantees a different value
		saveVal2 = math.random(0, 12)
		if saveVal2 >= saveVal1 then
			saveVal2 = saveVal2 + 1
		end
		logger.logDebug(SUBMODULE, "SaveVal conflict detected for pilot %s, reassigned skill2 saveVal to %d", pilotId, saveVal2)
	end

	logger.logInfo(SUBMODULE, "Applying skills to pilot " .. pilotId .. ": [" .. storedSkills[1] .. ", " .. storedSkills[2] .. "]")

	-- Apply both skills with their determined saveVal
	pilot:setLvlUpSkill(1, skillDataToTable(
			skill1Id, skill1.shortName, skill1.fullName, skill1.description, saveVal1, skill1.bonuses))
	pilot:setLvlUpSkill(2, skillDataToTable(
			skill2Id, skill2.shortName, skill2.fullName, skill2.description, saveVal2, skill2.bonuses))
end


-- Apply skills to all pilots - both squad and storage
function skill_selection:applySkillsToAllPilots()
	-- ensure game data is initialized
	skill_selection:initGameSaveData()

	if #skill_config_module.enabledSkillsIds == 0 then
		logger.logWarn(SUBMODULE, "No enabled skills, skipping pilot skill assignment")
		return
	end

	-- Assign skills for all squad and storage pilots
	local pilots = Game:GetAvailablePilots()
	logger.logDebug(SUBMODULE, "Starting skill assignment for %d pilots", #pilots)

	-- Reset per_run tracking and rebuild it from currently assigned skills
	skill_selection.usedSkillsPerRun = {}
	for idx, pilot in pairs(pilots) do
		if pilot ~= nil then
			local pilotId = pilot:getIdStr()
			local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]

			if storedSkills ~= nil then
				-- This pilot has assigned skills, mark them as used for per_run tracking
				for _, skillId in ipairs(storedSkills) do
					skill_selection:markPerRunSkillAsUsed(skillId)
				end
			else
				logger.logWarn(SUBMODULE, "Stored skills for pilot %s are nil in applySkillsToAllPilots - skipping", idx)
			end
		else
			logger.logWarn(SUBMODULE, "Pilot %s is nil in applySkillsToAllPilots - skipping", idx)
		end
	end

	-- Assign skills to pilots now that we updated the per run skills
	for _, pilot in pairs(pilots) do
		skill_selection:applySkillsToPilot(pilot)
	end

	logger.logInfo(SUBMODULE, "Applied skills to " .. #pilots .. " pilot(s)")
end

function skill_selection:applySkillToPodPilot()
	-- If its a pilot, assign skills
	local pilot = Game:GetPodRewardPilot()
	skill_selection:applySkillsToPilot(pilot)
end

function skill_selection:applySkillToPerfectIslandPilot()
	-- If its a pilot, assign skills
	local pilot = Game:GetPerfectIslandRewardPilot()
	skill_selection:applySkillsToPilot(pilot)
end

-- Marks a per_run skill as used for this run
-- Only per_run skills need global tracking - per_pilot is handled by constraint checking selectedSkills
function skill_selection:markPerRunSkillAsUsed(skillId)
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
