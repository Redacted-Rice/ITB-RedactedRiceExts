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
skill_registry.registeredSkills = {}  -- skillId -> {id, group, shortName, fullName, description, bonuses, skillType, reusability, icon}
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
	-- Search for all pilots once
	local pilotIds = utils.searchForAllPilotIds()

	-- Execute all deferred predicate functions
	self:_executeDeferredPilotPredicates(pilotIds)

	-- Read vanilla pilot exclusions to support vanilla API
	self:_readPilotVanillaExclusions(pilotIds)
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
-- groups optional array of pool names (strings) this skill belongs to
function skill_registry:registerSkill(group, idOrTable, shortName, fullName, description, bonuses, skillType, saveVal,
		defaultReusability, reusabilityLimit, slotRestriction, weight, icon, groups)
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
		groups = idOrTable.groups
	end

	-- Check if ID is already registered globally
	if skill_registry.registeredSkills[id] ~= nil then
		logger.logError(SUBMODULE, "Skill ID '" .. id .. "' in group '" .. group .. "' conflicts with existing skill from group '" ..
				skill_registry.registeredSkills[id].group .. "'.")
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

	-- Validate groups
	logger.logDebug(SUBMODULE, "registerSkill '%s': Validating groups, type=%s", id, type(groups))
	if groups ~= nil then
		if type(groups) ~= "table" then
			logger.logWarn(SUBMODULE, "Skill '%s' has invalid groups (must be array of strings). Ignoring groups.", id)
			groups = {}
		else
			logger.logDebug(SUBMODULE, "registerSkill '%s': groups is table, checking array contents", id)
			-- Validate all group names are strings and rebuild array without invalid entries
			local validGroups = {}
			for i, groupName in ipairs(groups) do
				logger.logDebug(SUBMODULE, "  Group[%d]: type=%s, value=%s", i, type(groupName), tostring(groupName))
				if type(groupName) == "string" then
					table.insert(validGroups, groupName)
				else
					logger.logWarn(SUBMODULE, "Skill '%s' has invalid group name at index %d (must be string). Ignoring this group.", id, i)
				end
			end
			groups = validGroups
			logger.logDebug(SUBMODULE, "registerSkill '%s': %d valid group(s) after validation", id, #groups)
		end
	else
		logger.logDebug(SUBMODULE, "registerSkill '%s': groups is nil, using empty array", id)
		groups = {}
	end

	-- Register the skill with its type and reusability included in the skill data
	skill_registry.registeredSkills[id] = { id = id, group = group, shortName = shortName, fullName = fullName, description = description,
			bonuses = bonuses or {},
			skillType = skillType or "default",
			saveVal = saveVal,
			defaultReusability = defaultReusability,
			reusabilityLimit = reusabilityLimit,
			icon = icon,
	}

	-- add a config value groups will be updated in setSkillConfig
	if #groups > 0 then
		logger.logInfo(SUBMODULE, "Registering skill '%s' with %d group(s): %s", id, #groups, table.concat(groups, ", "))
	end

	-- add a config value with default reusability
	skill_config:setSkillConfig(id, {enabled = true, reusability = defaultReusability, slotRestriction = slotRestriction, weight = weight, groups = groups})
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

--- Registers a group with optional settings and skills
function skill_registry:registerGroup(nameOrTable, onlyOnePerPilot, skills)
	local name = nameOrTable

	-- Handle table-based call
	if type(nameOrTable) == "table" then
		name = nameOrTable.name
		onlyOnePerPilot = nameOrTable.onlyOnePerPilot
		skills = nameOrTable.skills
	end

	if not name or type(name) ~= "string" then
		logger.logError(SUBMODULE, "Group name is required and must be a string")
		return false
	end

	-- Store group settings if provided
	if onlyOnePerPilot ~= nil then
		skill_config:setGroupSettings(name, {onlyOnePerPilot = onlyOnePerPilot})
	end

	-- Add skills to the group if provided
	if skills then
		self:registerSkillToGroup(skills, name)
	else
		-- Create an empty group if no skills provided
		skill_config.config.emptyGroups[name] = true
	end

	logger.logDebug(SUBMODULE, "Registered group '%s'", name)
end

-- Registers skills to groups. Can handle single or array like tables of skills/groups
function skill_registry:registerSkillToGroup(skillIdOrSkillIds, groupIdOrGroupIds)
	-- Normalize to arrays
	local skillIds = type(skillIdOrSkillIds) == "table" and skillIdOrSkillIds or {skillIdOrSkillIds}
	local groupIds = type(groupIdOrGroupIds) == "table" and groupIdOrGroupIds or {groupIdOrGroupIds}

	-- Add each skill to each group in codeDefinedGroups
	for _, skillId in ipairs(skillIds) do
		if not skill_config.config.skillConfigs[skillId] then
			logger.logWarn(SUBMODULE, "Skill '%s' not registered, skipping", skillId)
		else
			for _, groupId in ipairs(groupIds) do
				if not skill_config.codeDefinedGroups[skillId] then
					skill_config.codeDefinedGroups[skillId] = {}
				end
				skill_config.codeDefinedGroups[skillId][groupId] = true
				logger.logDebug(SUBMODULE, "Registered skill '%s' to group '%s'", skillId, groupId)
			end
		end
	end

	-- Rebuild groups to reflect changes
	skill_config:_rebuildGroups()
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
function skill_registry:_executeDeferredPilotPredicates(pilotIds)
	-- Search for all pilots once
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

-- Registers skill group exclusions
-- Takes a skill id and a list/set of group names
-- Adds coded skill-skill exclusions between the given skill and all skills in the specified groups
function skill_registry:registerSkillGroupExclusions(skillId, groups)
	if type(groups) == "string" then
		groups = {groups}
	end

	local groupSet = {}
	for _, group in ipairs(groups) do
		groupSet[group] = true
	end
	local exclusionCount = 0

	-- Iterate through all registered skills and find matching groups
	for otherSkillId, skill in pairs(self.registeredSkills) do
		if otherSkillId ~= skillId and groupSet[skill.group] then
			self:registerSkillExclusion(skillId, otherSkillId)
			exclusionCount = exclusionCount + 1
		end
	end

	logger.logInfo(SUBMODULE, "Applied group exclusions for skill %s: excluded %d skill(s) from %d categor(y/ies)",
			skillId, exclusionCount, #groups)
end

-- Collects blacklists from pilot definitions in _G
local function _collectVanillaExclusionsFromPilots(pilotIds)
	local pilotExclusions = {}
	local blacklistCount = 0

	for _, key in pairs(pilotIds) do
		local pilotData = _G[key]
		if pilotData.Blacklist ~= nil and type(pilotData.Blacklist) == "table" and #pilotData.Blacklist > 0 then
			if not pilotExclusions[key] then
				pilotExclusions[key] = {}
			end

			for _, skillId in ipairs(pilotData.Blacklist) do
				pilotExclusions[key][skillId] = true
			end

			blacklistCount = blacklistCount + 1
			logger.logDebug(SUBMODULE, "Collected %d blacklist exclusions for pilot %s",
					#pilotData.Blacklist, key)
		end
	end
	return pilotExclusions, blacklistCount
end

-- Gets group display name for a pilot
local function _getPilotGroupDisplayName(pilotId)
	local pilotObj = _G[pilotId]
	if pilotObj and pilotObj.Name and pilotObj.Name ~= "" then
		if _G.GetText then
			return GetText(pilotObj.Name) or pilotObj.Name
		else
			return pilotObj.Name
		end
	else
		return pilotId:gsub("^Pilot_", "")
	end
end

-- Merges registered group based exclusions into collected exclusions
-- Only processes entries with "group:" prefix, expanding them to individual skills
local function _mergeRegisteredExclusions(pilotExclusions, registeredExclusions)
	local registeredCount = 0

	for pilotId, targetSet in pairs(registeredExclusions) do
		for targetId, _ in pairs(targetSet) do
			-- Only process group based exclusions (entries with "group:" prefix)
			if targetId:match("^group:") then
				local groupName = targetId:sub(7) -- Remove "group:" prefix

				-- Get all skills in this group
				local group = skill_config.groups[groupName]
				if group and group.skillIds then
					if not pilotExclusions[pilotId] then
						pilotExclusions[pilotId] = {}
					end

					-- Add each skill from the group to the exclusions
					for skillId, _ in pairs(group.skillIds) do
						if not pilotExclusions[pilotId][skillId] then
							pilotExclusions[pilotId][skillId] = true
							registeredCount = registeredCount + 1
						end
					end

					logger.logDebug(SUBMODULE, "Merged group '%s' exclusions for pilot %s", groupName, pilotId)
				else
					logger.logWarn(SUBMODULE, "Group '%s' not found for pilot %s exclusion", groupName, pilotId)
				end
			end
			-- Ignore non group exclusions (individual skill exclusions)
		end
	end
	return registeredCount
end

-- Creates a sorted key from a skill set for pool matching
local function _createSkillSetKey(skillSet)
	local sortedSkills = {}
	for skillId, _ in pairs(skillSet) do
		table.insert(sortedSkills, skillId)
	end
	table.sort(sortedSkills)
	return table.concat(sortedSkills, "|"), sortedSkills
end

-- Creates or reuses a pool for a pilot's exclusions
local function _createOrReusePool(pilotId, pilotName, skillSet, poolsBySkillSet)
	local skillSetKey, sortedSkills = _createSkillSetKey(skillSet)

	logger.logDebug(SUBMODULE, "Looking for pool with skill set key: %s", skillSetKey)

	if poolsBySkillSet[skillSetKey] then
		-- Reuse existing pool
		local poolName = poolsBySkillSet[skillSetKey]
		logger.logInfo(SUBMODULE, "Reusing existing pool '%s' for pilot %s (%d skills: %s)",
				poolName, pilotId, #sortedSkills, table.concat(sortedSkills, ", "))
		return poolName
	else
		-- Create new pool
		local poolName = pilotName
		poolsBySkillSet[skillSetKey] = poolName

		-- Add all skills to this pool as code defined groups
		for _, skillId in ipairs(sortedSkills) do
			if not skill_config.codeDefinedGroups[skillId] then
				skill_config.codeDefinedGroups[skillId] = {}
			end
			skill_config.codeDefinedGroups[skillId][poolName] = true
		end

		logger.logInfo(SUBMODULE, "Created NEW pool '%s' for pilot %s with %d skill(s): %s",
				poolName, pilotId, #sortedSkills, table.concat(sortedSkills, ", "))
		return poolName
	end
end

--- Registers a pilot group exclusion. Supports an array like table of group names or a single group name
function skill_registry:registerPilotGroupExclusion(pilotId, groupNamesOrGroupName)
	-- Normalize to array
	local groupNames = type(groupNamesOrGroupName) == "table" and groupNamesOrGroupName or {groupNamesOrGroupName}

	for _, gName in ipairs(groupNames) do
		-- Add to codeDefinedRelationships for UI display (using "group:" prefix)
		if not skill_config.codeDefinedRelationships[skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS][pilotId] then
			skill_config.codeDefinedRelationships[skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS][pilotId] = {}
		end
		skill_config.codeDefinedRelationships[skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS][pilotId]["group:" .. gName] = true

		-- Also store in config for constraint checking
		if not skill_config.config.pilotGroupExclusions[pilotId] then
			skill_config.config.pilotGroupExclusions[pilotId] = {}
		end
		skill_config.config.pilotGroupExclusions[pilotId][gName] = true

		logger.logDebug(SUBMODULE, "Registered pilot-group exclusion: %s -> group:%s", pilotId, gName)
	end
end

-- Collects all pilot exclusions from blacklists, registered exclusions, and predicates
-- and converts them to groups. Creates or reuses groups based on the exact set of
-- excluded skills. Then creates pilot group exclusions so the pilot cannot get those
-- skills.
function skill_registry:_readPilotVanillaExclusions(pilotIds)
	-- Ensure groups are built before we try to reuse them
	skill_config:_rebuildGroups()

	-- Collect blacklists from pilot definitions
	local pilotExclusions, blacklistCount = _collectVanillaExclusionsFromPilots(pilotIds)

	-- Merge registered exclusions from API calls
	local registeredExclusions = skill_config.codeDefinedRelationships[skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS]
	local registeredCount = _mergeRegisteredExclusions(pilotExclusions, registeredExclusions)

	logger.logInfo(SUBMODULE, "Collected exclusions: %d pilots with blacklists, %d total registered exclusions",
			blacklistCount, registeredCount)

	-- Create or reuse pools for each pilot's combined exclusions
	-- Seed poolsBySkillSet with existing groups so they can be reused
	local poolsBySkillSet = {}
	for groupName, groupData in pairs(skill_config.groups) do
		if groupData.skillIds then
			local skillSetKey = _createSkillSetKey(groupData.skillIds)
			poolsBySkillSet[skillSetKey] = groupName
			logger.logDebug(SUBMODULE, "Seeded pool lookup with existing group '%s' (key: %s)", groupName, skillSetKey)
		end
	end

	for pilotId, skillSet in pairs(pilotExclusions) do
		local pilotName = _getPilotGroupDisplayName(pilotId)
		local poolName = _createOrReusePool(pilotId, pilotName, skillSet, poolsBySkillSet)

		-- Register the pilot-group exclusion using the public API
		self:registerPilotGroupExclusion(pilotId, poolName)
	end

	logger.logInfo(SUBMODULE, "Exclusion processing complete: %d pilot(s) scanned", #pilotIds)

	-- Rebuild groups after creating pools
	skill_config:_rebuildGroups()

	-- Log pilot group exclusions
	local pilotGroupExclusionCount = 0
	for pilotId, groups in pairs(skill_config.config.pilotGroupExclusions) do
		for groupName, _ in pairs(groups) do
			logger.logDebug(SUBMODULE, "  Pilot %s excluded from group '%s'", pilotId, groupName)
		end
	end
end

return skill_registry
