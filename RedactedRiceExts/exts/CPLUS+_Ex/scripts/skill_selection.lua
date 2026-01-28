-- Skill Selection Module
-- Handles weighted random selection and application of skills to pilots
-- This is the core logic for determining and assigning skills to pilots

local skill_selection = {}

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
		LOG("PLUS Ext error: No skills available in list")
		return nil
	end

	-- Calculate total weight for the available skills
	local totalWeight = 0
	for _, skillId in ipairs(availableSkills) do
		totalWeight = totalWeight + skill_config_module.config.skillConfigs[skillId].adj_weight
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
		if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: Initialized RNG with seed " .. seed .. " and fast-forwarded " .. savedCount .. " times") end
	end

	-- Weighted random selection
	local randomValue = math.random() * totalWeight
	skill_selection.localRandomCount = skill_selection.localRandomCount + 1
	GAME.cplus_plus_ex.randomSeedCnt = skill_selection.localRandomCount

	local cumulativeWeight = 0
	for _, skillId in ipairs(availableSkills) do
		cumulativeWeight = cumulativeWeight + skill_config_module.config.skillConfigs[skillId].adj_weight
		if randomValue <= cumulativeWeight then
			return skillId
		end
	end

	-- Fallback to last skill. We shouldn't get here but just in case
	LOG("PLUS Ext error: Weighted selection failed! Falling back to last skill")
	return availableSkills[#availableSkills]
end

-- Selects random level up skills based on count and configured constraints
-- Returns a array like table of skill IDs that satisfy the constraints
-- I pass count even though its currently only expected to be 2 just because I feel
-- like it could be interesting and possible to have pilots with more than two skills
function skill_selection:selectRandomSkills(pilot, count)
	if #skill_config_module.enabledSkillsIds == 0 then
		LOG("PLUS Ext error: No enabled skills available")
		return nil
	end

	local selectedSkills = {}

	-- Create a copy of all available skill IDs as an array. This will be our
	-- base list and we will narrow it down as we go if we try to assign
	-- an unallowed skill
	local availableSkills = {}
	for _, skillId in ipairs(skill_config_module.enabledSkillsIds) do
		table.insert(availableSkills, skillId)
	end

	-- Keep selecting until we have enough skills or run out of options
	while #selectedSkills < count and #availableSkills > 0 do
		-- Get a weighted random skill from the available pool
		local candidateSkillId = skill_selection:getWeightedRandomSkillId(availableSkills)
		if candidateSkillId == nil then
			return nil
		end

		if skill_constraints:checkSkillConstraints(pilot, selectedSkills, candidateSkillId) then
			-- If valid, add to the selected but do not remove yet
			-- Allows for potential duplicates in the future
			table.insert(selectedSkills, candidateSkillId)
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

	-- Check we assigned the expected number of skill
	if #selectedSkills ~= count then
		LOG("PLUS Ext error: Failed to select " .. count .. " skills. Selected " .. #selectedSkills .. ". Constraints may be impossible to satisfy with available skills.")
		return nil
	end
	return selectedSkills
end

local function skillDataToTable(id, shortName, fullName, description, saveVal, bonuses)
	return {id = id, shortName = shortName, fullName = fullName, description = description,
		healthBonus = bonuses.health, coresBonus = bonuses.cores, gridBonus = bonuses.grid,
		moveBonus = bonuses.move, saveVal = saveVal}
end

-- Main function to apply level up skills to a pilot (handles both skill slots)
-- Takes a memhack pilot struct and applies both skill slots (1 and 2)
-- Checks GAME memory and either loads existing skills or creates and assigns new ones
function skill_selection:applySkillsToPilot(pilot)
	if pilot == nil then
		LOG("PLUS Ext error: Pilot is nil")
		return
	end

	-- Use pilot ID as the key for storing skills for now. Multiple pilots with same ID is
	-- technically possible but not allowed by vanilla so this may change later
	local pilotId = pilot:getIdStr()

	-- Try to get stored skills
	local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]

	-- If the skills are not stored, we need to assign them
	if storedSkills ~= nil then
		if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: Read stored skill") end
	-- if its the time traveler, save the current skills
	elseif cplus_plus_ex._subobjects.time_traveler.timeTraveler and cplus_plus_ex._subobjects.time_traveler.timeTraveler._address == pilot._address then
		local lus = cplus_plus_ex._subobjects.time_traveler.timeTraveler:getLvlUpSkills()
		storedSkills = {lus:getSkill1():getIdStr(), lus:getSkill2():getIdStr()}
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills
		if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: Read time traveler skills") end
	-- otherwise assign random skills
	else
		-- Select 2 random skills that satisfy all registered constraint functions
		storedSkills = skill_selection:selectRandomSkills(pilot, 2)
		if storedSkills == nil then
			return
		end

		-- Store the skills in GAME
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills

		-- Track newly assigned skills for per_run constraints
		skill_selection:markPerRunSkillAsUsed(storedSkills[1])
		skill_selection:markPerRunSkillAsUsed(storedSkills[2])

		if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: Assigning random skills")
		end
	end

	local skill1Id = storedSkills[1]
	local skill2Id = storedSkills[2]
	local skill1 = skill_config_module.enabledSkills[skill1Id]
	local skill2 = skill_config_module.enabledSkills[skill2Id]

	-- Determine saveVal for skill 1
	-- If skill has saveVal = -1, assign random value (0-13)
	local saveVal1 = skill1.saveVal
	if saveVal1 == -1 then
		saveVal1 = math.random(0, 13)
		if cplus_plus_ex.PLUS_DEBUG then
			LOG("PLUS Ext: Assigned random saveVal " .. saveVal1 .. " to skill " .. skill1Id .. " for pilot " .. pilotId)
		end
	end

	-- Determine saveVal for skill 2
	-- If skill has saveVal = -1, assign random value (0-13)
	local saveVal2 = skill2.saveVal
	if saveVal2 == -1 then
		saveVal2 = math.random(0, 13)
		if cplus_plus_ex.PLUS_DEBUG then
			LOG("PLUS Ext: Assigned random saveVal " .. saveVal2 .. " to skill " .. skill2Id .. " for pilot " .. pilotId)
		end
	end

	-- If both skills have the same saveVal, reassign skill2
	if saveVal1 == saveVal2 then
		-- Generate from 0-12, increment if >= saveVal1 to exclude skill1's value
		-- This guarantees a different value
		saveVal2 = math.random(0, 12)
		if saveVal2 >= saveVal1 then
			saveVal2 = saveVal2 + 1
		end
		if cplus_plus_ex.PLUS_DEBUG then
			LOG("PLUS Ext: SaveVal conflict detected for pilot " .. pilotId .. ", reassigned skill2 saveVal to " .. saveVal2)
		end
	end

	if cplus_plus_ex.PLUS_DEBUG then
		LOG("PLUS Ext: Applying skills to pilot " .. pilotId .. ": [" .. storedSkills[1] .. ", " .. storedSkills[2] .. "]")
	end

	-- Apply both skills with their determined saveVal
	pilot:setLvlUpSkill(1, skillDataToTable(
			skill1Id, skill1.shortName, skill1.fullName, skill1.description, saveVal1, skill1.bonuses))
	pilot:setLvlUpSkill(2, skillDataToTable(
			skill2Id, skill2.shortName, skill2.fullName, skill2.description, saveVal2, skill2.bonuses))
end

-- Apply skills to all pilots in the squad
function skill_selection:applySkillsToAllPilots()
	-- ensure game data is initialized
	skill_selection:initGameSaveData()

	if #skill_config_module.enabledSkillsIds == 0 then
		if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: No enabled skills, skipping pilot skill assignment") end
		return
	end

	-- Assign skills for all squad and storage pilots
	local pilots = Game:GetAvailablePilots()

	-- Reset per_run tracking and rebuild it from currently assigned skills
	skill_selection.usedSkillsPerRun = {}
	for _, pilot in pairs(pilots) do
		local pilotId = pilot:getIdStr()
		local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]

		if storedSkills ~= nil then
			-- This pilot has assigned skills, mark them as used for per_run tracking
			for _, skillId in ipairs(storedSkills) do
				skill_selection:markPerRunSkillAsUsed(skillId)
			end
		end
	end

	-- Assign skills to pilots now that we updated the per run skills
	for _, pilot in pairs(pilots) do
		skill_selection:applySkillsToPilot(pilot)
	end

	if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: Applied skills to " .. #pilots .. " pilot(s)") end
end

function skill_selection:applySkillToPodPilot()
	-- If its a pilot, assign skills
	local pilot = Game:GetPodRewardPilot()
	if pilot and pilot:getAddress() ~= 0 then
		skill_selection:applySkillsToPilot(pilot)
	end
end

function skill_selection:applySkillToPerfectIslandPilot()
	-- If its a pilot, assign skills
	local pilot = Game:GetPerfectIslandRewardPilot()
	if pilot and pilot:getAddress() ~= 0 then
		skill_selection:applySkillsToPilot(pilot)
	end
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
			LOG("PLUS Ext: Warning: per_run skill " .. skillId .. " already marked as used")
		end

		-- Mark skill as used this run
		skill_selection.usedSkillsPerRun[skillId] = true
		if cplus_plus_ex.PLUS_DEBUG then
			LOG("PLUS Ext: Marked per_run skill " .. skillId .. " as used this run")
		end
	end
	-- reusable and per_pilot skills don't need tracking
end

return skill_selection
