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
skill_registry.pilotExclusionFunctions = {}  -- skillId -> array of functions(pilotId) that return true if pilot should be excluded
skill_registry.pilotInclusionFunctions = {}  -- skillId -> array of functions(pilotId) that return true if pilot should be included

-- Initialize the module
function skill_registry:init()
	skill_config = cplus_plus_ex._subobjects.skill_config
	utils = cplus_plus_ex._subobjects.utils

	self:_registerVanilla()
	return self
end

-- Called after all mods are loaded
function skill_registry:_postModsLoaded()
	-- Get all pilot IDs
	local allPilotIds = utils.searchForAllPilotIds()
	
	-- Read vanilla pilot exclusions to support vanilla API
	self:_readPilotExclusionsFromGlobal(allPilotIds)
	
	-- Expand function based pilot exclusions/inclusions into actual pilot IDs
	self:_expandPilotConstraintFunctions(allPilotIds)
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
-- constraints optional table defining relationships and constraints for this skill:
--   groups - string or array of group names this skill belongs to
--   skillExclusions - string or array of skill IDs that are mutually exclusive with this skill
--   pilotExclusions - string or array of pilot IDs that cannot have this skill
--   pilotInclusions - string or array of pilot IDs that can have this skill
function skill_registry:registerSkill(category, idOrTable, shortName, fullName, description, bonuses, skillType, saveVal,
		defaultReusability, reusabilityLimit, slotRestriction, weight, icon, constraints)
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
		constraints = idOrTable.constraints
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

	-- Process constraints table if provided
	if constraints ~= nil then
		if type(constraints) ~= "table" then
			logger.logWarn(SUBMODULE, "Skill '%s' has invalid constraints (must be table). Ignoring constraints.", id)
		else
			-- Register groups
			if constraints.groups ~= nil then
				if type(constraints.groups) == "string" then
					self:registerSkillToGroup(id, constraints.groups)
				elseif type(constraints.groups) == "table" then
					for _, groupName in ipairs(constraints.groups) do
						if type(groupName) == "string" then
							self:registerSkillToGroup(id, groupName)
						else
							logger.logWarn(SUBMODULE, "Skill '%s' has invalid group name (must be string). Ignoring.", id)
						end
					end
				else
					logger.logWarn(SUBMODULE, "Skill '%s' has invalid groups format (must be string or array). Ignoring.", id)
				end
			end

			-- Register skill exclusions
			if constraints.skillExclusions ~= nil then
				if type(constraints.skillExclusions) == "string" then
					self:registerSkillExclusion(id, constraints.skillExclusions)
				elseif type(constraints.skillExclusions) == "table" then
					for _, excludedSkillId in ipairs(constraints.skillExclusions) do
						if type(excludedSkillId) == "string" then
							self:registerSkillExclusion(id, excludedSkillId)
						else
							logger.logWarn(SUBMODULE, "Skill '%s' has invalid excluded skill ID (must be string). Ignoring.", id)
						end
					end
				else
					logger.logWarn(SUBMODULE, "Skill '%s' has invalid skillExclusions format (must be string or array). Ignoring.", id)
				end
			end

			-- Register pilot exclusions (can be strings or functions)
			if constraints.pilotExclusions ~= nil then
				if type(constraints.pilotExclusions) == "string" then
					self:registerPilotSkillExclusions(constraints.pilotExclusions, id)
				elseif type(constraints.pilotExclusions) == "table" then
					for _, pilotIdOrFn in ipairs(constraints.pilotExclusions) do
						if type(pilotIdOrFn) == "string" then
							self:registerPilotSkillExclusions(pilotIdOrFn, id)
						elseif type(pilotIdOrFn) == "function" then
							-- Store function based exclusions separately
							if not self.pilotExclusionFunctions[id] then
								self.pilotExclusionFunctions[id] = {}
							end
							table.insert(self.pilotExclusionFunctions[id], pilotIdOrFn)
							logger.logDebug(SUBMODULE, "Registered function based pilot exclusion for skill '%s'", id)
						else
							logger.logWarn(SUBMODULE, "Skill '%s' has invalid pilot exclusion (must be string or function). Ignoring.", id)
						end
					end
				else
					logger.logWarn(SUBMODULE, "Skill '%s' has invalid pilotExclusions format (must be string or array). Ignoring.", id)
				end
			end

			-- Register pilot inclusions (can be strings or functions)
			if constraints.pilotInclusions ~= nil then
				if type(constraints.pilotInclusions) == "string" then
					self:registerPilotSkillInclusions(constraints.pilotInclusions, id)
				elseif type(constraints.pilotInclusions) == "table" then
					for _, pilotIdOrFn in ipairs(constraints.pilotInclusions) do
						if type(pilotIdOrFn) == "string" then
							self:registerPilotSkillInclusions(pilotIdOrFn, id)
						elseif type(pilotIdOrFn) == "function" then
							-- Store function based inclusions separately
							if not self.pilotInclusionFunctions[id] then
								self.pilotInclusionFunctions[id] = {}
							end
							table.insert(self.pilotInclusionFunctions[id], pilotIdOrFn)
							logger.logDebug(SUBMODULE, "Registered function based pilot inclusion for skill '%s'", id)
						else
							logger.logWarn(SUBMODULE, "Skill '%s' has invalid pilot inclusion (must be string or function). Ignoring.", id)
						end
					end
				else
					logger.logWarn(SUBMODULE, "Skill '%s' has invalid pilotInclusions format (must be string or array). Ignoring.", id)
				end
			end
		end
	end
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

-- Register a skill as part of a group
-- This is the code defined way to add skills to groups
-- Groups are created implicitly when skills are added to them
function skill_registry:registerSkillToGroup(skillId, groupName)
	if not skill_config.codeDefinedGroups[skillId] then
		skill_config.codeDefinedGroups[skillId] = {}
	end

	skill_config.codeDefinedGroups[skillId][groupName] = true

	logger.logDebug(SUBMODULE, "Registered skill '%s' to group '%s'", skillId, groupName)
end

-- Scans global for all pilot definitions and registers their Blacklist exclusions
-- This maintains the vanilla method of defining pilot exclusions to be compatible
-- without any specific changes for using this extension
function skill_registry:_readPilotExclusionsFromGlobal(allPilotIds)
	if _G.Pilot == nil then
		logger.logError(SUBMODULE, "Pilot class not found, skipping exclusion registration")
		return
	end

	-- If allPilotIds not provided, search for them
	if allPilotIds == nil then
		allPilotIds = utils.searchForAllPilotIds()
	end

	local pilotCount = 0
	local exclusionCount = 0

	for _, pilotId in pairs(allPilotIds) do
		local pilot = _G[pilotId]

		-- Check if the pilot has a Blacklist array
		if pilot.Blacklist ~= nil and type(pilot.Blacklist) == "table" and #pilot.Blacklist > 0 then
			-- Register the blacklist as auto loaded exclusions
			self:registerPilotSkillExclusions(pilotId, pilot.Blacklist)
			exclusionCount = exclusionCount + 1

			logger.logDebug(SUBMODULE, "Found %d exclusion(s) for pilot %s", #pilot.Blacklist, key)
		end
	end

	logger.logInfo(SUBMODULE, "Scanned " .. #allPilotIds .. " pilot(s), registered exclusions for " ..
			exclusionCount .. " pilot(s)")
end

-- Expands function based pilot constraints into actual pilot IDs after all mods are loaded
function skill_registry:_expandPilotConstraintFunctions(allPilotIds)
	if _G.Pilot == nil then
		logger.logError(SUBMODULE, "Pilot class not found, skipping function expansion")
		return
	end
	
	local exclusionExpansions = 0
	local inclusionExpansions = 0

	-- Expand exclusion functions
	for skillId, exclusionFns in pairs(self.pilotExclusionFunctions) do
		for _, fn in ipairs(exclusionFns) do
			for _, pilotId in ipairs(allPilotIds) do
				if fn(pilotId) then
					self:registerPilotSkillExclusions(pilotId, skillId)
					exclusionExpansions = exclusionExpansions + 1
					logger.logDebug(SUBMODULE, "Function expanded: excluded pilot %s from skill %s", pilotId, skillId)
				end
			end
		end
	end

	-- Expand inclusion functions
	for skillId, inclusionFns in pairs(self.pilotInclusionFunctions) do
		for _, fn in ipairs(inclusionFns) do
			for _, pilotId in ipairs(allPilotIds) do
				if fn(pilotId) then
					self:registerPilotSkillInclusions(pilotId, skillId)
					inclusionExpansions = inclusionExpansions + 1
					logger.logDebug(SUBMODULE, "Function expanded: included pilot %s for skill %s", pilotId, skillId)
				end
			end
		end
	end

	if exclusionExpansions > 0 or inclusionExpansions > 0 then
		logger.logInfo(SUBMODULE, "Expanded pilot constraint functions: %d exclusions, %d inclusions", 
				exclusionExpansions, inclusionExpansions)
	end
end

return skill_registry
