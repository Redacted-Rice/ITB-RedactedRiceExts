local plus_manager = {
	PLUS_DEBUG = nil,

	_cplus_plus_ex = nil,
	_localRandomCount = nil,  -- Track local random count for this session
	_usedSkillsPerRun = {},  -- skillId -> true for per_run skills used this run

	_registeredSkills = {},  -- category -> skillId -> {shortName, fullName, description, bonuses, skillType, reusability}
	_registeredSkillsIds = {},  -- skillId -> category
	_constraintFunctions = {},  -- Array of function(pilot, selectedSkills, candidateSkillId) -> boolean

	_enabledSkills = {},  -- skillId -> {shortName, fullName, description, bonuses, skillType, reusability}
	_enabledSkillsIds = {},  -- Array of skill ids enabled
}

plus_manager.REUSABLILITY = { [1] = "REUSABLE", REUSABLE = 1, [2] = "PER_PILOT", PER_PILOT = 2, [3] = "PER_RUN", PER_RUN = 3}
local REUSABLE = plus_manager.REUSABLILITY.REUSABLE
local PER_PILOT = plus_manager.REUSABLILITY.PER_PILOT
local PER_RUN = plus_manager.REUSABLILITY.PER_RUN

plus_manager.DEFAULT_REUSABILITY = PER_PILOT
plus_manager.DEFAULT_WEIGHT = 1.0
plus_manager.VANILLA_SKILLS = {
	{id = "Health", shortName = "Pilot_HealthShort", fullName = "Pilot_HealthName", description= "Pilot_HealthDesc", bonuses = {health = 2}, saveVal = 0, reusability = REUSABLE },
	{id = "Move", shortName = "Pilot_MoveShort", fullName = "Pilot_MoveName", description= "Pilot_MoveDesc", bonuses = {move = 1}, saveVal = 1, reusability = REUSABLE },
	{id = "Grid", shortName = "Pilot_GridShort", fullName = "Pilot_GridName", description= "Pilot_GridDesc", bonuses = {grid = 3}, saveVal = 2, reusability = REUSABLE },
	{id = "Reactor", shortName = "Pilot_ReactorShort", fullName = "Pilot_ReactorName", description= "Pilot_ReactorDesc", bonuses = {cores = 1}, saveVal = 3, reusability = REUSABLE },
	{id = "Opener", shortName = "Pilot_OpenerName", fullName = "Pilot_OpenerName", description= "Pilot_OpenerDesc", saveVal = 4, reusability = PER_PILOT },
	{id = "Closer", shortName = "Pilot_CloserName", fullName = "Pilot_CloserName", description= "Pilot_CloserDesc", saveVal = 5, reusability = PER_PILOT },
	{id = "Popular", shortName = "Pilot_PopularName", fullName = "Pilot_PopularName", description= "Pilot_PopularDesc", saveVal = 6, reusability = PER_PILOT }, -- Maybe reusable? investigate
	{id = "Thick", shortName = "Pilot_ThickName", fullName = "Pilot_ThickName", description= "Pilot_ThickDesc", saveVal = 7, reusability = PER_PILOT },
	{id = "Skilled", shortName = "Pilot_SkilledName", fullName = "Pilot_SkilledName", description= "Pilot_SkilledDesc", bonuses = {health = 2, move = 1}, saveVal = 8, reusability = REUSABLE },
	{id = "Invulnerable", shortName = "Pilot_InvulnerableName", fullName = "Pilot_InvulnerableName", description= "Pilot_InvulnerableDesc", saveVal = 9, reusability = REUSABLE },
	{id = "Adrenaline", shortName = "Pilot_AdrenalineName", fullName = "Pilot_AdrenalineName", description= "Pilot_AdrenalineDesc", saveVal = 10, reusability = PER_PILOT }, -- Maybe reusable? investigate
	{id = "Pain", shortName = "Pilot_PainName", fullName = "Pilot_PainName", description= "Pilot_PainDesc", saveVal = 11, reusability = PER_PILOT }, -- Maybe reusable? investigate
	{id = "Regen", shortName = "Pilot_RegenName", fullName = "Pilot_RegenName", description= "Pilot_RegenDesc", saveVal = 12, reusability = PER_PILOT }, -- Maybe reusable? investigate
	{id = "Conservative", shortName = "Pilot_ConservativeName", fullName = "Pilot_ConservativeName", description= "Pilot_ConservativeDesc", saveVal = 13, reusability = PER_PILOT }, -- Maybe reusable? investigate
}

-- Config params that will be changeable and saveable via GUI
plus_manager.config = {
	allowReusableSkills = true, -- will be set on load by options but default to vanilla
	autoAdjustWeights = true,  -- Auto-adjust weights for dependent skills (default true)
	pilotSkillExclusions = {}, -- pilotId -> excluded skill ids (set-like table) - auto-loaded from pilot Blacklists
	pilotSkillInclusions = {}, -- pilotId -> included skill ids (set-like table)
	skillExclusions = {},  -- skillId -> excluded skill ids (set-like table) - skills that cannot be taken together
	skillDependencies = {},  -- skillId -> required skill ids (set-like table) - skills that require another skill to be selected
	skillConfigs = {}, -- skillId -> enabled, weight, reusability
}

function deepcopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[deepcopy(orig_key)] = deepcopy(orig_value)
		end
		setmetatable(copy, deepcopy(getmetatable(orig)))
	else
		copy = orig
	end
	return copy
end

-- Helper function to convert a set-like table to a comma-separated string
-- Used for logging skill lists
local function setToString(setTable)
	local items = {}
	for key, _ in pairs(setTable) do
		table.insert(items, key)
	end
	return table.concat(items, ", ")
end

plus_manager.SkillConfig = {
	-- "default" to false - its not been added yet but when registering we will set
	-- it to default enabled and add it appropriately via setConfigs and having it
	-- false will allow that to add to state list correctly
	enabled = false,
	set_weight = plus_manager.DEFAULT_WEIGHT,
	adj_weight = plus_manager.DEFAULT_WEIGHT,
	reusability = plus_manager.DEFAULT_REUSABILITY,
}

function plus_manager.SkillConfig.new(data)
	local instance = setmetatable({}, plus_manager.SkillConfig)

	-- copy any struct values using passed values or the defaults
	-- Use deep copies just in case (currently not needed but future proofing)
	for k, v in pairs(plus_manager.SkillConfig) do
		if data and data[k] then
			instance[k] = deepcopy(data[k])
		else
			instance[k] = deepcopy(v)
		end
	end
	return instance
end

function plus_manager:initGameSaveData()
	if GAME == nil then
		return
	end

	if GAME.cplus_plus_ex == nil then
		GAME.cplus_plus_ex = {}
	end

	if GAME.cplus_plus_ex.pilotSkills == nil then
		GAME.cplus_plus_ex.pilotSkills = {}
	end

	if GAME.cplus_plus_ex.randomSeed == nil then
		-- Initialize with a seed based on os.time() and 0 rolls
		GAME.cplus_plus_ex.randomSeed = os.time()
		GAME.cplus_plus_ex.randomSeedCnt = 0
	end

	if self._localRandomCount ~= GAME.cplus_plus_ex.randomSeedCnt then
		-- reset our local count to force a re-roll to ensure we
		-- stay inline
		self._localRandomCount = nil
	end

	if self.PLUS_DEBUG then LOG("PLUS Ext: Game entered, storage initialized") end
end


function plus_manager:normalizeReusabilityToInt(reusability)
	reusability = reusability or self.DEFAULT_REUSABILITY

	-- Now try to convert it
	local normalizeReuse = self.REUSABLILITY[reusability]
	-- if it converted to a string, then an int was already passed so we want to keep that
	if type(normalizeReuse) == "string" then
		normalizeReuse = reusability
	-- if it was null, its out of range!
	elseif not normalizeReuse then
		normalizeReuse = nil
	end
	return normalizeReuse
end

function plus_manager:getAllowedReusability(skillId)
	-- This is called by register before the skills are registered so default to all allowed
	local minReusability = self._registeredSkills.reusability or self.REUSABLILITY.REUSABLE
	local allowed = {}

	for val = minReusability, self.REUSABLILITY.PER_RUN do
		allowed[val] = true
	end
	return allowed
end

---------------- Registration (Default value) functions -------------------

-- saveVal is optional and must be between 0-13 (vanilla range). This will be used so if
-- the extension fails to load or is uninstalled, a suitable vanilla skill will be used
-- instead. If not provided or out of range, a random vanilla value will be used.
-- The save data in vanilla only supports 0-13. Anything out of range is clamped to this range
-- reusability is optional defines how the skill can be reused. Defaults to per_pilot to align with vanilla
--   "reusable" - can be assigned to any pilot any number of times
--   "per_pilot" - a pilot can only have this skill once - vanilla behavior
--   "per_run" - can only be assigned once per run across all pilots. Would be for very strong skills or skills that
--			affect the game state in a one time only way
-- weight optional default weight for the skill
function plus_manager:registerSkill(category, idOrTable, shortName, fullName, description, bonuses, skillType, saveVal, reusability, weight)
	if self._registeredSkills[category] == nil then
		self._registeredSkills[category] = {}
	end

	local id = idOrTable
	if type(idOrTable) == "table" then
		id = idOrTable.id
		shortName = idOrTable.shortName
		fullName = idOrTable.fullName
		description = idOrTable.description
		bonuses = idOrTable.bonuses
		skillType = idOrTable.skillType
		saveVal = idOrTable.saveVal
		reusability = idOrTable.reusability
		weight = idOrTable.weight
	end

	-- Check if ID is already registered globally
	if self._registeredSkillsIds[id] ~= nil then
		self:logAndShowErrorPopup("PLUS Ext error: Skill ID '" .. id .. "' in category '" .. category ..
				"' conflicts with existing skill from category '" .. self._registeredSkillsIds[id] .. "'.")
		return
	end

	-- Validate and normalize saveVal
	-- Default to -1 if not provided
	local originalSaveVal = saveVal
	saveVal = saveVal or -1
	-- Convert non-numbers or values outside 0-13 range to -1 (random assignment)
	if type(saveVal) ~= "number" or saveVal < 0 or saveVal > 13 then
		if originalSaveVal ~= nil and originalSaveVal ~= -1 then
			LOG("PLUS Ext: Warning: Skill '" .. id .. "' has invalid saveVal '" .. tostring(originalSaveVal) ..
					"' (must be 0-13 or -1). Using random assignment (-1) instead.")
		end
		saveVal = -1
	end

	-- Validate and normalize reusability
	-- First handle nil input
	reusability = self:normalizeReusabilityToInt(reusability)
	if not reusability then
		LOG("PLUS Ext: Warning: Skill '" .. id .. "' has invalid reusability '" .. tostring(reusability) ..
			"' 1-3 (corresponding to enum values in plus_manager.REUSABLILITY. Defaulting to PER_PILOT")
		reusability = self.DEFAULT_REUSABILITY
	end

	-- Register the skill with its type and reusability included in the skill data
	self._registeredSkills[category][id] = { shortName = shortName, fullName = fullName, description = description,
			bonuses = bonuses or {},
			skillType = skillType or "default",
			saveVal = saveVal, reusability = reusability,
	}
	self._registeredSkillsIds[id] = category

	-- add a config value
	self:setSkillConfig(id, {enabled = true, reusability = reusability, set_weight = weight})
end

-- Registers all vanilla skills
function plus_manager:registerVanilla()
	-- Register all vanilla skills
	for _, skill in ipairs(self.VANILLA_SKILLS) do
		self:registerSkill("vanilla", skill)
	end
end

-- Helper function to register pilot-skill relationships
-- targetTable: either _pilotSkillExclusionsAuto, _pilotSkillExclusionsManual, or _pilotSkillInclusions
-- relationshipType: "exclusion" or "inclusion" (for debug logging)
-- isAuto: true if auto-loaded, false if manual (for debug logging)
local function registerPilotSkillRelationship(self, targetTable, pilotId, skillIds, relationshipType)
	if targetTable[pilotId] == nil then
		targetTable[pilotId] = {}
	end

	for _, skillId in ipairs(skillIds) do
		-- store with skillId as key so it acts like a set
		targetTable[pilotId][skillId] = true

		if self.PLUS_DEBUG then
			local action = relationshipType == "exclusion" and "cannot have" or "can have"
			LOG("PLUS Ext: Registered " .. relationshipType .. " - Pilot " .. pilotId .. " " .. action .. " skill " .. skillId)
		end
	end
end

-- Registers pilot skill exclusions
-- Takes pilot id and list of skill ids to exclude
-- isAuto true if auto-loaded from pilot Blacklist, false/nil if manually registered via API. Defaults to false
function plus_manager:registerPilotSkillExclusions(pilotId, skillIds)
	registerPilotSkillRelationship(self, self.config.pilotSkillExclusions, pilotId, skillIds, "exclusion")
end

-- Registers pilot skill inclusions
-- Takes pilot id and list of skill ids to include
-- This is only needed for specific inclusion skills. Any default
-- enabled, non-excluded skill will be available as well as any added here
function plus_manager:registerPilotSkillInclusions(pilotId, skillIds)
	registerPilotSkillRelationship(self, self.config.pilotSkillInclusions, pilotId, skillIds, "inclusion")
end

-- Registers a skill to skill exclusion
-- Takes two skill ids that cannot be selected for the same pilot
function plus_manager:registerSkillExclusion(skillId, excludedSkillId)
	if self.config.skillExclusions[skillId] == nil then
		self.config.skillExclusions[skillId] = {}
	end
	if self.config.skillExclusions[excludedSkillId] == nil then
		self.config.skillExclusions[excludedSkillId] = {}
	end

	-- Register exclusion in both directions
	self.config.skillExclusions[skillId][excludedSkillId] = true
	self.config.skillExclusions[excludedSkillId][skillId] = true

	if self.PLUS_DEBUG then
		LOG("PLUS Ext: Registered exclusion: " .. skillId .. " <-> " .. excludedSkillId)
	end
end

-- Registers a skill dependency
-- Takes a skill id and a required skill id
-- The dependent skill can only be selected if the required skill is already selected
-- Call multiple times to add multiple dependencies that would work - only one of the
-- added need to be assigned to satisfy the dependency
-- Note: Chain dependencies are not allowed - a dependent skill cannot depend on another dependent skill
function plus_manager:registerSkillDependency(skillId, requiredSkillId)
	-- Prevent chain dependencies - requiredSkillId cannot itself be a dependent skill
	if self.config.skillDependencies[requiredSkillId] ~= nil then
		LOG("PLUS Ext error: Cannot register dependency: " .. skillId .. " -> " .. requiredSkillId ..
			". Chain dependencies are not allowed. The required skill '" .. requiredSkillId ..
			"' is already a dependent skill.")
		return false
	end

	if self.config.skillDependencies[skillId] == nil then
		self.config.skillDependencies[skillId] = {}
	end

	self.config.skillDependencies[skillId][requiredSkillId] = true

	if self.PLUS_DEBUG then
		LOG("PLUS Ext: Registered dependency: " .. skillId .. " requires " .. requiredSkillId)
	end

	return true
end


----------------- Configuration changes -------------

-- Sets the configs for a skill and updates enabled states
function plus_manager:setSkillConfig(skillId, config)
	local curr_config = self.config.skillConfigs[skillId] or self.SkillConfig.new()
	local new_config = deepcopy(curr_config)

	if config.enabled ~= nil then
		if config.enabled then
			new_config.enabled = true
		else
			new_config.enabled = false
		end
	end

	if config.set_weight then
		if config.set_weight < 0 then
			LOG("PLUS Ext error: Skill weight must be >= 0, got " .. set_weight)
			return
		end
		new_config.set_weight = config.set_weight
		-- Also update adj_weight to match. It may be adjusted later as well but this ensures
		-- we have a valid value if for some reason we don't call auto-adjust weights (like
		-- we are doing in some of the tests)
		new_config.adj_weight = config.set_weight
	end

	if config.reusability then
		local normalizeReuse = self:normalizeReusabilityToInt(config.reusability)
		if not normalizeReuse then
			LOG("PLUS Ext: Error: Invalid skill reusability passed: " .. config.reusability)
			return
		elseif not self:getAllowedReusability(skillId)[normalizeReuse] then
			LOG("PLUS Ext: Error: Unallowed skill reusability passed: " .. config.reusability .. "(normalized to ".. normalizeReuse ..")")
			return
		end
		new_config.reusability = config.reusability
	end

	-- If we reached here, its a good config. Apply it
	self.config.skillConfigs[skillId] = new_config
	if new_config.enabled and not curr_config.enabled then
		self:enableSkill(skillId)
	elseif not new_config.enabled and curr_config.enabled then
		self:disableSkill(skillId)
	end

	if self.PLUS_DEBUG then LOG("PLUS Ext: Set config for skill " .. skillId) end
end

-- Enable a skill. Should not be called directly
function plus_manager:enableSkill(id)
	category =  self._registeredSkillsIds[id]
	skill = self._registeredSkills[category][id]

	-- Check if already enabled
	if self._enabledSkills[id] ~= nil then
		LOG("PLUS Ext warning: Skill " .. id .. " already enabled, skipping")
	else
		-- Add the skill to enabled list. We don't care at this point if its inclusion type or not
		self._enabledSkills[id] = skill
		table.insert(self._enabledSkillsIds, id)

		if self.PLUS_DEBUG then
			local skillType = skill.skillType
			local reusability = skill.reusability
			if self.PLUS_DEBUG then LOG("PLUS Ext: Enabled skill: " .. id .. " (type: " .. skillType .. ", reusability: " .. reusability .. ")") end
		end
	end
	if self.PLUS_DEBUG then LOG("PLUS Ext: Skill " .. id .. " enabled") end
end

-- Disable a skill. Should not be called directly
function plus_manager:disableSkill(id)
	if self._enabledSkills[id] == nil then
		LOG("PLUS Ext: Warning: Skill " .. id .. " already disabled, skipping")
	else
		self._enabledSkills[id] = nil
		for idx, skillId in ipairs(self._enabledSkillsIds) do
			if skillId == id then
				table.remove(self._enabledSkillsIds, idx)
				if self.PLUS_DEBUG then LOG("PLUS Ext: Disabled skill: " .. id .. " (idx: " .. idx .. ")") end
				break
			end
		end
	end
	if self.PLUS_DEBUG then LOG("PLUS Ext: Skill " .. id .. " disabled") end
end

-- TODO: More functions for these non skill config fields are needed

-- Removes a dependency between skills
function plus_manager:removeSkillDependency(skillId, requiredSkillId)
	if self.config.skillDependencies[skillId] then
		self.config.skillDependencies[skillId][requiredSkillId] = nil

		-- If no more dependencies, remove the entry entirely
		local hasAny = false
		for _, _ in pairs(self.config.skillDependencies[skillId]) do
			hasAny = true
			break
		end

		if not hasAny then
			self.config.skillDependencies[skillId] = nil
		end

		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Removed dependency: " .. skillId .. " no longer requires " .. requiredSkillId)
		end

		return true
	end

	return false
end

-- Auto-adjusts skill weights based on dependencies
-- Only runs if _autoAdjustDependentWeights is true
-- Dependent skills get weight = (numEnabledSkills - 2) / numDependencies
-- Dependency skills get weight += 0.5 per dependent
function plus_manager:setAdjustedWeightsConfigs()
	-- first just copy all the set weights to adj weights for all skills
	for skillId, _ in pairs(self._registeredSkillsIds) do
		local config = self.config.skillConfigs[skillId]
		config.adj_weight = config.set_weight
	end

	if not self.config.autoAdjustWeights then
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Auto-adjust disabled, skipping weight adjustment")
		end
		return
	end

	local dependencyUsages = {}
	local numSkills = #self._enabledSkillsIds

	-- Process all dependent skills
	for dependentSkillId, dependencies in pairs(self.config.skillDependencies) do
		-- Only adjust if the skill is enabled
		if self._enabledSkills[dependentSkillId] then
			local config = self.config.skillConfigs[dependentSkillId]

			-- Count number of dependencies for this skill
			local numDependencies = 0
			for _, _ in pairs(dependencies) do
				numDependencies = numDependencies + 1
			end

			-- Calculate new weight multiplier: (total skills - 2) / number of dependencies
			-- Use -2 to remove the dependent skill but also the already selected dependency skill
			local newWeightMult = math.max(0, (numSkills - 2) / numDependencies)
			-- Don't use setSkillWeight here as we want to preserve configured weight separately
			config.adj_weight = newWeightMult * config.set_weight
			if self.PLUS_DEBUG then
				LOG("PLUS Ext: Auto-adjusted dependent skill " .. dependentSkillId .. " weight to " .. config.adj_weight ..
						" (base=" .. config.set_weight .. ", numSkills=" .. numSkills .. ", numDependencies=" .. numDependencies .. ")")
			end
		end

		-- Track dependency usage for bumping up the base skill as well
		for requiredSkillId, _ in pairs(dependencies) do
			if dependencyUsages[requiredSkillId] == nil then
				dependencyUsages[requiredSkillId] = 1
			else
				dependencyUsages[requiredSkillId] = dependencyUsages[requiredSkillId] + 1
			end
		end
	end

	-- Increase weight of skills that are dependencies for others
	for skillId, dependencyCount in pairs(dependencyUsages) do
		local config = self.config.skillConfigs[skillId]
		config.adj_weight = config.set_weight + (dependencyCount * 0.5)
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Increased dependency skill " .. skillId .. " weight to " .. config.adj_weight ..
					" (base=" .. config.set_weight .. ", usedBy=" .. dependencyCount .. ")")
		end
	end
end


-- Resets configuration to default state
-- Restores all values to what they were at initial load (after registration and auto-loading)
function plus_manager:resetToDefaults()
	self.config = deepcopy(self.defaultConfig)
	-- TODO: Update internal state vars as well
	-- TODO: save? Or is this handled elsewhere?
end

------------ Randomization functions ---------------------

-- Uses the stored seed and sequential access count to ensure deterministic random values
-- The RNG is seeded once per session, then we fast forward to the saved count
-- availableSkills - array like table of skill IDs to select from
function plus_manager:getWeightedRandomSkillId(availableSkills)
	if #availableSkills == 0 then
		LOG("PLUS Ext error: No skills available in list")
		return nil
	end

	-- Calculate total weight for the available skills
	local totalWeight = 0
	for _, skillId in ipairs(availableSkills) do
		totalWeight = totalWeight + self.config.skillConfigs[skillId].adj_weight
	end

	-- Get seed and count from saved game data
	local seed = GAME.cplus_plus_ex.randomSeed
	local savedCount = GAME.cplus_plus_ex.randomSeedCnt

	-- If this is the first call this session, initialize the RNG to match
	-- what is in our saved data
	if self._localRandomCount == nil then
		math.randomseed(seed)
		for i = 1, savedCount do
			math.random()
		end
		self._localRandomCount = savedCount
		if self.PLUS_DEBUG then LOG("PLUS Ext: Initialized RNG with seed " .. seed .. " and fast-forwarded " .. savedCount .. " times") end
	end

	-- Weighted random selection
	local randomValue = math.random() * totalWeight
	self._localRandomCount = self._localRandomCount + 1
	GAME.cplus_plus_ex.randomSeedCnt = self._localRandomCount

	local cumulativeWeight = 0
	for _, skillId in ipairs(availableSkills) do
		cumulativeWeight = cumulativeWeight +  self.config.skillConfigs[skillId].adj_weight
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
function plus_manager:selectRandomSkills(pilot, count)
	if #self._enabledSkillsIds == 0 then
		LOG("PLUS Ext error: No enabled skills available")
		return nil
	end

	local selectedSkills = {}

	-- Create a copy of all available skill IDs as an array. This will be our
	-- base list and we will narrow it down as we go if we try to assign
	-- an unallowed skill
	local availableSkills = {}
	for _, skillId in ipairs(self._enabledSkillsIds) do
		table.insert(availableSkills, skillId)
	end

	-- Keep selecting until we have enough skills or run out of options
	while #selectedSkills < count and #availableSkills > 0 do
		-- Get a weighted random skill from the available pool
		local candidateSkillId = self:getWeightedRandomSkillId(availableSkills)
		if candidateSkillId == nil then
			return nil
		end

		if self:checkSkillConstraints(pilot, selectedSkills, candidateSkillId) then
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

-- Main function to apply level up skills to a pilot (handles both skill slots)
-- Takes a memhack pilot struct and applies both skill slots (1 and 2)
-- Checks GAME memory and either loads existing skills or creates and assigns new ones
function plus_manager:applySkillsToPilot(pilot)
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
		if self.PLUS_DEBUG then LOG("PLUS Ext: Read stored skill") end
	-- if its the time traveler, save the current skills
	elseif self._cplus_plus_ex.timeTraveler and self._cplus_plus_ex.timeTraveler._address == pilot._address then
		local lus = self._cplus_plus_ex.timeTraveler:getLvlUpSkills()
		storedSkills = {lus:getSkill1():getIdStr(), lus:getSkill2():getIdStr()}
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills
		if self.PLUS_DEBUG then LOG("PLUS Ext: Read time traveler skills") end
	-- otherwise assign random skills
	else
		-- Select 2 random skills that satisfy all registered constraint functions
		storedSkills = self:selectRandomSkills(pilot, 2)
		if storedSkills == nil then
			return
		end

		-- Store the skills in GAME
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills

		-- Track newly assigned skills for per_run constraints
		self:markPerRunSkillAsUsed(storedSkills[1])
		self:markPerRunSkillAsUsed(storedSkills[2])

		if self.PLUS_DEBUG then LOG("PLUS Ext: Assigning random skills")
		end
	end

	local skill1Id = storedSkills[1]
	local skill2Id = storedSkills[2]
	local skill1 = self._enabledSkills[skill1Id]
	local skill2 = self._enabledSkills[skill2Id]

	-- Determine saveVal for skill 1
	-- If skill has saveVal = -1, assign random value (0-13)
	local saveVal1 = skill1.saveVal
	if saveVal1 == -1 then
		saveVal1 = math.random(0, 13)
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Assigned random saveVal " .. saveVal1 .. " to skill " .. skill1Id .. " for pilot " .. pilotId)
		end
	end

	-- Determine saveVal for skill 2
	-- If skill has saveVal = -1, assign random value (0-13)
	local saveVal2 = skill2.saveVal
	if saveVal2 == -1 then
		saveVal2 = math.random(0, 13)
		if self.PLUS_DEBUG then
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
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: SaveVal conflict detected for pilot " .. pilotId .. ", reassigned skill2 saveVal to " .. saveVal2)
		end
	end

	if self.PLUS_DEBUG then
		LOG("PLUS Ext: Applying skills to pilot " .. pilotId .. ": [" .. storedSkills[1] .. ", " .. storedSkills[2] .. "]")
	end

	-- Apply both skills with their determined saveVal
	pilot:setLvlUpSkill(1, skill1Id, skill1.shortName, skill1.fullName, skill1.description, saveVal1, skill1.bonuses)
	pilot:setLvlUpSkill(2, skill2Id, skill2.shortName, skill2.fullName, skill2.description, saveVal2, skill2.bonuses)
end

-- Apply skills to all pilots in the squad
function plus_manager:applySkillsToAllPilots()
	-- ensure game data is initialized
	self:initGameSaveData()

	if #self._enabledSkillsIds == 0 then
		if self.PLUS_DEBUG then LOG("PLUS Ext: No enabled skills, skipping pilot skill assignment") end
		return
	end

	local pilots = self._cplus_plus_ex:getAllPilots()

	-- Reset per_run tracking and rebuild it from currently assigned skills
	self._usedSkillsPerRun = {}
	for _, pilot in pairs(pilots) do
		local pilotId = pilot:getIdStr()
		local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]

		if storedSkills ~= nil then
			-- This pilot has assigned skills, mark them as used for per_run tracking
			for _, skillId in ipairs(storedSkills) do
				self:markPerRunSkillAsUsed(skillId)
			end
		end
	end

	-- Assign skills to pilots now that we updated the per run skills
	for _, pilot in pairs(pilots) do
		self:applySkillsToPilot(pilot)
	end

	if self.PLUS_DEBUG then LOG("PLUS Ext: Applied skills to " .. #pilots .. " pilot(s)") end
end


------------ Constraint functions ---------------------

-- Checks if a skill can be assigned to the given pilot
-- using all registered constraint functions
-- Returns true if all constraints pass, false otherwise
function plus_manager:checkSkillConstraints(pilot, selectedSkills, candidateSkillId)
	-- Check all constraint functions
	for _, constraintFn in ipairs(self._constraintFunctions) do
		if not constraintFn(pilot, selectedSkills, candidateSkillId) then
			return false
		end
	end
	return true
end

-- Registers a constraint function for skill assignment
-- These functions take pilot, selectedSkills, and candidateSkillId and return true if the candidateskill can be assigned to the pilot
--   pilot - The memhack pilot struct
--   selectedSkills - Array like table of skill IDs that have already been selected for this pilot
--   candidateSkillId - The skill ID being considered for assignment
-- The default pilot inclusion/exclusion and duplicate prevention use this same function. These can be
-- used as examples for using constraint functions
function plus_manager:registerConstraintFunction(constraintFn)
	table.insert(self._constraintFunctions, constraintFn)
	if self.PLUS_DEBUG then
		LOG("PLUS Ext: Registered constraint function")
	end
end

-- This enforces pilot exclusions (Vanilla blacklist API) and inclusion restrictions
function plus_manager:registerPlusExclusionInclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Get the skill object to check its type
		local skill = self._enabledSkills[candidateSkillId]

		if skill == nil then
			LOG("PLUS Ext warning: Skill " .. candidateSkillId .. " not found in enabled skills")
			return false
		end

		-- For inclusion skills check if pilot is in inclusion list
		-- For default skills check if pilot is NOT in exclusion list (must be absent)
		local isInclusionSkill = skill.skillType == "inclusion"

		if isInclusionSkill then
			-- Check inclusion list
			local pilotList = self.config.pilotSkillInclusions[pilotId]
			local skillInList = pilotList and pilotList[candidateSkillId]
			local allowed = skillInList == true
			if not allowed and self.PLUS_DEBUG then
				LOG("PLUS Ext: Prevented inclusion skill " .. candidateSkillId .. " for pilot " .. pilotId)
			end
			return allowed
		else
			-- Check for an exclusion
			local hasExclusion = self.config.pilotSkillExclusions[pilotId] and self.config.pilotSkillExclusions[pilotId][candidateSkillId]
			if hasExclusion and self.PLUS_DEBUG then
				LOG("PLUS Ext: Prevented exclusion skill " .. candidateSkillId .. " for pilot " .. pilotId)
			end
			return not hasExclusion
		end
	end)
end

-- This enforces per_pilot and per_run skill restrictions
function plus_manager:registerReusabilityConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()
		local skill = self._enabledSkills[candidateSkillId]


		local reusability = self.config.skillConfigs[candidateSkillId].reusability
		-- If we do not allow reusable skills, we need to change it to PER_PILOT
		if (not self.config.allowReusableSkills) and reusability == self.REUSABLILITY.REUSABLE then
			reusability = self.REUSABLILITY.PER_PILOT
		end

		if reusability == self.REUSABLILITY.PER_PILOT or reusability == self.REUSABLILITY.PER_RUN then
			-- Check if this pilot already has this skill in their selected slots
			-- This applies to both per_pilot and per_run (per_run is stricter and includes this check)
			for _, skillId in ipairs(selectedSkills) do
				if skillId == candidateSkillId then
					if self.PLUS_DEBUG then
						LOG("PLUS Ext: Prevented " .. reusability .. " skill " .. candidateSkillId .. " for pilot " .. pilotId .. " (already selected)")
					end
					return false
				end
			end

			-- Additional check for per_run: ensure not used by ANY pilot
			if reusability == self.REUSABLILITY.PER_RUN then
				if self._usedSkillsPerRun[candidateSkillId] then
					if self.PLUS_DEBUG then
						LOG("PLUS Ext: Prevented per_run skill " .. candidateSkillId .. " for pilot " .. pilotId .. " (already used this run)")
					end
					return false
				end
			end
		end
		-- reusability == "reusable" always passes
		return true
	end)
end

-- This enforces skill to skill exclusions and depencencies
function plus_manager:registerSkillExclusionDependencyConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- pilot id for logging
		local pilotId = pilot:getIdStr()

		-- Check if candidate is excluded by any already selected skill
		if self.config.skillExclusions[candidateSkillId] then
			for _, selectedSkillId in ipairs(selectedSkills) do
				if self.config.skillExclusions[candidateSkillId][selectedSkillId] then
					if self.PLUS_DEBUG then
						LOG("PLUS Ext: Prevented skill " .. candidateSkillId .. " for pilot " .. pilotId ..
							" (mutually exclusive with already selected skill " .. selectedSkillId .. ")")
					end
					return false
				end
			end
		end

		-- If candidate has dependencies at least one must be in selectedSkills already
		if self.config.skillDependencies[candidateSkillId] then
			local hasDependency = false

			for requiredSkillId, _ in pairs(self.config.skillDependencies[candidateSkillId]) do
				for _, selectedSkillId in ipairs(selectedSkills) do
					if selectedSkillId == requiredSkillId then
						hasDependency = true
						break
					end
				end
				if hasDependency then
					break
				end
			end

			if not hasDependency then
				if self.PLUS_DEBUG then
					LOG("PLUS Ext: Prevented skill " .. candidateSkillId .. " for pilot " .. pilotId ..
						" (requires one of: " .. setToString(self.config.skillDependencies[candidateSkillId]) .. ")")
				end
				return false
			end
		end

		return true
	end)
end

-- Marks a per_run skill as used for this run
-- Only per_run skills need global tracking - per_pilot is handled by constraint checking selectedSkills
function plus_manager:markPerRunSkillAsUsed(skillId)
	local skill = self._enabledSkills[skillId]
	if skill == nil then
		return
	end

	if self.config.skillConfigs[skillId].reusability == self.REUSABLILITY.PER_RUN then
		-- Check if already marked
		if self._usedSkillsPerRun[skillId] then
			LOG("PLUS Ext: Warning: per_run skill " .. skillId .. " already marked as used")
		end

		-- Mark skill as used this run
		self._usedSkillsPerRun[skillId] = true
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Marked per_run skill " .. skillId .. " as used this run")
		end
	end
	-- reusable and per_pilot skills don't need tracking
end


------------ Init/Load/Default config ---------------------

-- Scans global for all pilot definitions and registers their Blacklist exclusions
-- This maintains the vanilla method of defining pilot exclusions to be compatible
-- without any specific changes for using this extension
function plus_manager:readPilotExclusionsFromGlobal()
	if _G.Pilot == nil then
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Error: Pilot class not found, skipping exclusion registration")
		end
		return
	end

	local pilotCount = 0
	local exclusionCount = 0

	-- Scan _G for all Pilot instances using metatable check
	-- This assumes all pilots are created via Pilot:new (e.g. via CreatePilot()) which
	-- will automatically set the metatable to Pilot
	for key, value in pairs(_G) do
		if type(key) == "string" and type(value) == "table" and getmetatable(value) == _G.Pilot then
			pilotCount = pilotCount + 1

			-- Check if the pilot has a Blacklist array
			if value.Blacklist ~= nil and type(value.Blacklist) == "table" and #value.Blacklist > 0 then
				-- Register the blacklist as auto loaded exclusions
				self:registerPilotSkillExclusions(key, value.Blacklist)
				exclusionCount = exclusionCount + 1

				if self.PLUS_DEBUG then
					LOG("PLUS Ext: Found " .. #value.Blacklist .. " exclusion(s) for pilot " .. key)
				end
			end
		end
	end

	if self.PLUS_DEBUG then
		LOG("PLUS Ext: Scanned " .. pilotCount .. " pilot(s), registered exclusions for " .. exclusionCount .. " pilot(s)")
	end
end

function plus_manager:addEvents()
	modApi.events.onModsFirstLoaded:subscribe(function()
		self:postModsLoadedConfig()
	end)
	if self.PLUS_DEBUG then LOG("PLUS Ext: Manager: Initialized and subscribed to game events") end
end

function plus_manager:init(parent)
	self._cplus_plus_ex = parent
	self.PLUS_DEBUG = parent.PLUS_DEBUG

	-- Register vanilla skills
	self:registerVanilla()

	-- Register built-in constraint functions
	self:registerReusabilityConstraintFunction()
	self:registerPlusExclusionInclusionConstraintFunction()
	self:registerSkillExclusionDependencyConstraintFunction()

	-- Add events for auto adjusting weights
	self:addEvents()
end

function plus_manager:load(options)
	-- TODO: Remove?
end


function plus_manager:postModsLoadedConfig()
	-- Read vanilla pilot exclusions to support vanilla API
	self:readPilotExclusionsFromGlobal()

	-- Auto-adjust weights for dependencies
	self:setAdjustedWeightsConfigs()

	-- Set the defaults to our registered/setup values
	self.defaultConfig = deepcopy(configs)

	-- TODO: Then load any saved configurations
end

return plus_manager