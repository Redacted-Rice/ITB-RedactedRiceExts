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

-- Initialize the module
function skill_registry:init()
	skill_config = cplus_plus_ex._subobjects.skill_config
	utils = cplus_plus_ex._subobjects.utils

	self:_registerVanilla()
	return self
end

-- Called after all mods are loaded
function skill_registry:_postModsLoaded()
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
-- reusabilityLimit is optional defines the minimum (most permissive) reusability allowed. If not set, defaults to defaultReusability
--   This sets the lower bound on what users can configure (higher values = more restrictive)
-- slotRestriction is optional defines which skill slot this skill can appear in. Defaults to any
--   ANY (1) - can appear in either slot 1 or 2 - vanilla behavior
--   FIRST (2) - can only appear in slot 1
--   SECOND (3) - can only appear in slot 2
-- weight optional default weight for the skill
-- icon optional path to 21x21 image to display in the skills config menu
function skill_registry:registerSkill(category, idOrTable, shortName, fullName, description, bonuses, skillType, saveVal,
		defaultReusability, reusabilityLimit, slotRestriction, weight, icon)
	local id = idOrTable
	if type(idOrTable) == "table" then
		id = idOrTable.id
		shortName = idOrTable.shortName
		fullName = idOrTable.fullName
		description = idOrTable.description
		bonuses = idOrTable.bonuses
		skillType = idOrTable.skillType
		saveVal = idOrTable.saveVal
		-- allows single reusability value to be passed in as defaultReusability & reusabilityLimit
		defaultReusability = idOrTable.defaultReusability or idOrTable.reusability
		-- nil will default to defaultReusability
		reusabilityLimit = idOrTable.reusabilityLimit
		slotRestriction = idOrTable.slotRestriction
		weight = idOrTable.weight
		icon = idOrTable.icon
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

	-- Validate and normalize reusabilityLimit
	-- If not provided, default to same as defaultReusability (no restriction beyond default)
	if reusabilityLimit ~= nil then
		reusabilityLimit = utils.normalizeReusabilityToInt(reusabilityLimit)
		if not reusabilityLimit then
			logger.logWarn(SUBMODULE, "Skill '" .. id .. "' has invalid reusabilityLimit '" .. tostring(reusabilityLimit) ..
					"' 1-3 (corresponding to enum values in REUSABLILITY). Defaulting to match defaultReusability")
			reusabilityLimit = defaultReusability
		end
	else
		reusabilityLimit = defaultReusability
	end

	-- Validate that defaultReusability >= reusabilityLimit (higher numbers = more restrictive)
	if defaultReusability < reusabilityLimit then
		logger.logWarn(SUBMODULE, "Skill '" .. id .. "' has defaultReusability (" .. defaultReusability ..
				") less restrictive than reusabilityLimit (" .. reusabilityLimit .. "). Adjusting default to match limit.")
		defaultReusability = reusabilityLimit
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

	-- Register the skill with its type and reusability included in the skill data
	skill_registry.registeredSkills[id] = { id = id, category = category, shortName = shortName, fullName = fullName, description = description,
			bonuses = bonuses or {},
			skillType = skillType or "default",
			saveVal = saveVal,
			defaultReusability = defaultReusability,
			reusabilityLimit = reusabilityLimit,
			icon = icon,
	}

	-- add a config value with default reusability
	skill_config:setSkillConfig(id, {enabled = true, reusability = defaultReusability, slotRestriction = slotRestriction, weight = weight})
end

-- Registers all vanilla skills
function skill_registry:_registerVanilla()
	-- Register all vanilla skills
	for _, skill in ipairs(cplus_plus_ex.VANILLA_SKILLS) do
		self:registerSkill("Vanilla", skill)
	end
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
