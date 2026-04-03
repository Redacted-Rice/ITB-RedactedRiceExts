-- Skill Registration Module
-- Handles registering skills, exclusions, and inclusions
-- Registered skills will be default enabled and the registered inclusions
-- and exclusions are default values. These can be changed at
-- runtime and the values used are stored in skill_config module

local skill_registry = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "SkillRegistry", cplus_plus_ex.DEBUG.REGISTRY and cplus_plus_ex.DEBUG.ENABLED)

-- Local references to other submodules (set during init)
local skill_config = nil
local utils = nil

-- Module state
skill_registry.registeredSkills = {}  -- skillId -> {id, category, shortName, fullName, description, bonuses, skillType, reusability, icon}
-- We defer predicates until after all the mods are loaded to ensure all pilots are available
skill_registry.deferredPilotPredicates = {
	exclusions = {},  -- Array of {skillIds, predicateFn}
	inclusions = {},  -- Array of {skillIds, predicateFn}
}

-- Initialize the module
function skill_registry:init()
	skill_config = cplus_plus_ex._subobjects.skill_config
	utils = cplus_plus_ex._subobjects.utils

	self:_registerVanilla()
	return self
end

-- Called after all mods are loaded
function skill_registry:_postModsLoaded()
	-- Execute all deferred predicate functions
	self:_executeDeferredPilotPredicates()

	-- Read vanilla pilot exclusions to support vanilla API
	self:_readPilotExclusionsFromGlobal()
end

-- saveVal is optional and must be between 0-13 (vanilla range). This will be used so if
-- the extension fails to load or is uninstalled, a suitable vanilla skill will be used
-- instead. If not provided or out of range, a random vanilla value will be used.
-- The save data in vanilla only supports 0-13. Anything out of range is clamped to this range
-- defaultReusability is optional defines the default/starting reusability. Defaults to per_pilot to align with vanilla
--   REUSABLE (1) - can be assigned to any pilot any number of times
--   PER_PILOT (2) - a pilot can only have this skill once - vanilla behavior
--   PER_RUN (3) - can only be assigned once per run across all pilots. Would be for very strong skills or skills that
--			affect the game state in a one time only way
-- maxReusability is optional defines the maximum (most restrictive) reusability allowed. If not set, defaults to defaultReusability
--   This sets the lower bound on what users can configure (higher values = more restrictive)
-- slotRestriction is optional defines which skill slot this skill can appear in. Defaults to any
--   ANY (1) - can appear in either slot 1 or 2 - vanilla behavior
--   FIRST (2) - can only appear in slot 1
--   SECOND (3) - can only appear in slot 2
-- weight optional default weight for the skill
-- icon optional path to 21x21 image to display in the skills config menu
-- pools optional array of pool names (strings) this skill belongs to
function skill_registry:registerSkill(category, idOrTable, shortName, fullName, description, bonuses, skillType, saveVal,
		defaultReusability, maxReusability, slotRestriction, weight, icon, pools)
	local id = idOrTable
	if type(idOrTable) == "table" then
		id = idOrTable.id
		shortName = idOrTable.shortName
		fullName = idOrTable.fullName
		description = idOrTable.description
		bonuses = idOrTable.bonuses
		skillType = idOrTable.skillType
		saveVal = idOrTable.saveVal
		-- allows single reusability value to be passed in as defaultReusability & maxReusability
		defaultReusability = idOrTable.defaultReusability or idOrTable.reusability
		-- nil will default to defaultReusability
		maxReusability = idOrTable.maxReusability
		slotRestriction = idOrTable.slotRestriction
		weight = idOrTable.weight
		icon = idOrTable.icon
		pools = idOrTable.pools
	end

	-- Check if ID is already registered globally
	if skill_registry.registeredSkills[id] ~= nil then
		logger.logError(SUBMODULE, "Skill ID '" .. id .. "' in category '" .. category .. "' conflicts with existing skill from category '" ..
				skill_registry.registeredSkills[id].category .. "'.")
		return
	end

	-- Validate and normalize saveVal
	-- Default to -1 if not provided
	local originalSaveVal = saveVal
	saveVal = saveVal or -1
	-- Convert non-numbers or values outside 0-13 range to -1 (random assignment)
	if type(saveVal) ~= "number" or saveVal < 0 or saveVal > 13 then
		if originalSaveVal ~= nil and originalSaveVal ~= -1 then
			logger.logWarn(SUBMODULE, "Skill '" .. id .. "' has invalid saveVal '" .. tostring(originalSaveVal) ..
					"' (must be 0-13 or -1). Using random assignment (-1) instead.")
		end
		saveVal = -1
	end

	-- Validate and normalize defaultReusability
	defaultReusability = utils.normalizeReusabilityToInt(defaultReusability)
	if not defaultReusability then
		logger.logWarn(SUBMODULE, "Skill '" .. id .. "' has invalid defaultReusability '" .. tostring(defaultReusability) ..
				"' 1-3 (corresponding to enum values in REUSABLILITY). Defaulting to PER_PILOT")
		defaultReusability = cplus_plus_ex.DEFAULT_REUSABILITY
	end

	-- Validate and normalize maxReusability
	-- If not provided, default to same as defaultReusability (no restriction beyond default)
	if maxReusability ~= nil then
		maxReusability = utils.normalizeReusabilityToInt(maxReusability)
		if not maxReusability then
			logger.logWarn(SUBMODULE, "Skill '" .. id .. "' has invalid maxReusability '" .. tostring(maxReusability) ..
					"' 1-3 (corresponding to enum values in REUSABLILITY). Defaulting to match defaultReusability")
			maxReusability = defaultReusability
		end
	else
		maxReusability = defaultReusability
	end

	-- Validate that defaultReusability <= maxReusability (higher numbers = more restrictive)
	if defaultReusability > maxReusability then
		logger.logWarn(SUBMODULE, "Skill '" .. id .. "' has defaultReusability (" .. defaultReusability ..
				") more restrictive than maxReusability (" .. maxReusability .. "). Adjusting maxReusability to match default.")
		maxReusability = defaultReusability
	end

	-- Validate and normalize slot restriction
	slotRestriction = utils.normalizeSlotRestrictionToInt(slotRestriction)
	if not slotRestriction then
		if slotRestriction ~= nil then
			logger.logWarn(SUBMODULE, "Skill '" .. id .. "' has invalid slotRestriction '" .. tostring(slotRestriction) ..
					"' 1-3 (corresponding to enum values in SLOT_RESTRICTION). Defaulting to ANY")
		end
		slotRestriction = cplus_plus_ex.DEFAULT_SLOT_RESTRICTION
	end

	-- Validate pools
	logger.logDebug(SUBMODULE, "registerSkill '%s': Validating pools, type=%s", id, type(pools))
	if pools ~= nil then
		if type(pools) ~= "table" then
			logger.logWarn(SUBMODULE, "Skill '%s' has invalid pools (must be array of strings). Ignoring pools.", id)
			pools = {}
		else
			logger.logDebug(SUBMODULE, "registerSkill '%s': pools is table, checking array contents", id)
			-- Validate all pool names are strings and rebuild array without invalid entries
			local validPools = {}
			for i, poolName in ipairs(pools) do
				logger.logDebug(SUBMODULE, "  Pool[%d]: type=%s, value=%s", i, type(poolName), tostring(poolName))
				if type(poolName) == "string" then
					table.insert(validPools, poolName)
				else
					logger.logWarn(SUBMODULE, "Skill '%s' has invalid pool name at index %d (must be string). Ignoring this pool.", id, i)
				end
			end
			pools = validPools
			logger.logDebug(SUBMODULE, "registerSkill '%s': %d valid pool(s) after validation", id, #pools)
		end
	else
		logger.logDebug(SUBMODULE, "registerSkill '%s': pools is nil, using empty array", id)
		pools = {}
	end

	-- Register the skill with its type and reusability included in the skill data
	skill_registry.registeredSkills[id] = { id = id, category = category, shortName = shortName, fullName = fullName, description = description,
			bonuses = bonuses or {},
			skillType = skillType or "default",
			saveVal = saveVal,
			defaultReusability = defaultReusability,
			maxReusability = maxReusability,
			icon = icon,
	}

	-- add a config value pools will be updated in setSkillConfig
	if #pools > 0 then
		logger.logInfo(SUBMODULE, "Registering skill '%s' with %d pool(s): %s", id, #pools, table.concat(pools, ", "))
	end

	-- add a config value with default reusability
	skill_config:setSkillConfig(id, {enabled = true, reusability = defaultReusability, slotRestriction = slotRestriction, weight = weight, pools = pools})

	-- Apply skill category exclusions if provided
	if skill_cat_excl then
		self:registerSkillCategoryExclusions(id, skill_cat_excl)
	end
end

-- Registers all vanilla skills
function skill_registry:_registerVanilla()
	logger.logInfo(SUBMODULE, "_registerVanilla: Registering %d vanilla skills", #cplus_plus_ex.VANILLA_SKILLS)
	-- Register all vanilla skills
	for _, skill in ipairs(cplus_plus_ex.VANILLA_SKILLS) do
		self:registerSkill("Vanilla", skill)
	end
	logger.logInfo(SUBMODULE, "_registerVanilla: Complete")
end

-- Helper function to register pilot-skill relationships
function skill_registry:_registerPilotSkillRelationship(targetTable, pilotId, skillIds, relationshipType)
	if targetTable[pilotId] == nil then
		targetTable[pilotId] = {}
	end

	if type(skillIds) == "string" then
		skillIds = {skillIds}
	end

	for _, skillId in ipairs(skillIds) do
		-- store with skillId as key so it acts like a set
		targetTable[pilotId][skillId] = true

	logger.logDebug(SUBMODULE, "%s - Pilot %s %s skill %s", relationshipType, pilotId,
			(relationshipType == "exclusion" and "cannot have" or "can have"), skillId)
	end
end

-- Registers pilot skill exclusions
-- Takes pilot id and list of skill ids to exclude
function skill_registry:registerPilotSkillExclusions(pilotId, skillIds)
	self:_registerPilotSkillRelationship(
			skill_config.codeDefinedRelationships[skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS],
			pilotId, skillIds, "exclusion"
	)
end

-- Registers pilot skill inclusions
-- Takes pilot id and list of skill ids to include
-- This is only needed for specific inclusion skills. Any default
-- enabled, non-excluded skill will be available as well as any added here
function skill_registry:registerPilotSkillInclusions(pilotId, skillIds)
	self:_registerPilotSkillRelationship(
			skill_config.codeDefinedRelationships[skill_config.RelationshipType.PILOT_SKILL_INCLUSIONS],
			pilotId, skillIds, "inclusion"
	)
end

-- Registers a skill to skill exclusion
-- Takes two skill ids that cannot be selected for the same pilot
function skill_registry:registerSkillExclusion(skillId, excludedSkillId)
	local skillExclusionsTable = skill_config.codeDefinedRelationships[skill_config.RelationshipType.SKILL_EXCLUSIONS]

	if skillExclusionsTable[skillId] == nil then
		skillExclusionsTable[skillId] = {}
	end
	if skillExclusionsTable[excludedSkillId] == nil then
		skillExclusionsTable[excludedSkillId] = {}
	end

	-- Register exclusion in both directions
	skillExclusionsTable[skillId][excludedSkillId] = true
	skillExclusionsTable[excludedSkillId][skillId] = true

	logger.logDebug(SUBMODULE, "Registered exclusion: %s <-> %s", skillId, excludedSkillId)
end

-- Registers pilot skill exclusions using a predicate function
-- Takes a list of skill ids and a function that accepts a pilot id and returns true if the exclusion should apply
-- The function is deferred and will be executed during _postModsLoaded after all pilots are loaded
function skill_registry:registerPilotSkillExclusionsByFunction(skillIds, predicateFn)
	if type(skillIds) == "string" then
		skillIds = {skillIds}
	end

	if type(predicateFn) ~= "function" then
		logger.logError(SUBMODULE, "predicateFn must be a function")
		return
	end

	-- Store for deferred execution
	table.insert(self.deferredPilotPredicates.exclusions, {
		skillIds = skillIds,
		predicateFn = predicateFn
	})

	logger.logDebug(SUBMODULE, "Deferred exclusion predicate registered for %d skill(s)", #skillIds)
end

-- Registers pilot skill inclusions using a predicate function
-- Takes a list of skill ids and a function that accepts a pilot id and returns true if the inclusion should apply
-- The function is deferred and will be executed during _postModsLoaded after all pilots are loaded
function skill_registry:registerPilotSkillInclusionsByFunction(skillIds, predicateFn)
	if type(skillIds) == "string" then
		skillIds = {skillIds}
	end

	if type(predicateFn) ~= "function" then
		logger.logError(SUBMODULE, "predicateFn must be a function")
		return
	end

	-- Store for deferred execution
	table.insert(self.deferredPilotPredicates.inclusions, {
		skillIds = skillIds,
		predicateFn = predicateFn
	})

	logger.logDebug(SUBMODULE, "Deferred inclusion predicate registered for %d skill(s)", #skillIds)
end

-- Executes all deferred pilot predicate functions
-- Called during _postModsLoaded after all mods (and pilots) are loaded
function skill_registry:_executeDeferredPilotPredicates()
	-- Search for all pilots once
	local pilotIds = utils.searchForAllPilotIds()
	local pilotCount = #pilotIds

	logger.logInfo(SUBMODULE, "Executing deferred pilot predicates for %d pilot(s)", pilotCount)

	-- Execute exclusion predicates
	for _, entry in ipairs(self.deferredPilotPredicates.exclusions) do
		local exclusionCount = 0
		for _, pilotId in ipairs(pilotIds) do
			local shouldExclude = entry.predicateFn(pilotId)
			if shouldExclude then
				self:registerPilotSkillExclusions(pilotId, entry.skillIds)
				exclusionCount = exclusionCount + 1
			end
		end
		logger.logDebug(SUBMODULE, "Applied exclusion predicate: %d pilot(s) affected for %d skill(s)",
				exclusionCount, #entry.skillIds)
	end

	-- Execute inclusion predicates
	for _, entry in ipairs(self.deferredPilotPredicates.inclusions) do
		local inclusionCount = 0
		for _, pilotId in ipairs(pilotIds) do
			local shouldInclude = entry.predicateFn(pilotId)
			if shouldInclude then
				self:registerPilotSkillInclusions(pilotId, entry.skillIds)
				inclusionCount = inclusionCount + 1
			end
		end
		logger.logDebug(SUBMODULE, "Applied inclusion predicate: %d pilot(s) affected for %d skill(s)",
				inclusionCount, #entry.skillIds)
	end

	logger.logInfo(SUBMODULE, "Completed deferred predicates: %d exclusion(s), %d inclusion(s)",
			#self.deferredPilotPredicates.exclusions, #self.deferredPilotPredicates.inclusions)
end

-- Registers skill category exclusions
-- Takes a skill id and a list/set of category names
-- Adds coded skill-skill exclusions between the given skill and all skills in the specified categories
function skill_registry:registerSkillCategoryExclusions(skillId, categories)
	if type(categories) == "string" then
		categories = {categories}
	end

	local categorySet = {}
	for _, cat in ipairs(categories) do
		categorySet[cat] = true
	end
	local exclusionCount = 0

	-- Iterate through all registered skills and find matching categories
	for otherSkillId, skill in pairs(self.registeredSkills) do
		if otherSkillId ~= skillId and categorySet[skill.category] then
			self:registerSkillExclusion(skillId, otherSkillId)
			exclusionCount = exclusionCount + 1
		end
	end

	logger.logInfo(SUBMODULE, "Applied category exclusions for skill %s: excluded %d skill(s) from %d categor(y/ies)",
			skillId, exclusionCount, #categories)
end

-- Scans global for all pilot definitions and registers their Blacklist exclusions
-- This maintains the vanilla method of defining pilot exclusions to be compatible
-- without any specific changes for using this extension
function skill_registry:_readPilotExclusionsFromGlobal()
	if _G.Pilot == nil then
		logger.logError(SUBMODULE, "Pilot class not found, skipping exclusion registration")
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

				logger.logDebug(SUBMODULE, "Found %d exclusion(s) for pilot %s", #value.Blacklist, key)
			end
		end
	end

	logger.logInfo(SUBMODULE, "Scanned " .. pilotCount .. " pilot(s), registered exclusions for " ..
			exclusionCount .. " pilot(s)")
end

return skill_registry
