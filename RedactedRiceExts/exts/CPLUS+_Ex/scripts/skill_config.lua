-- Skill Configuration Module
-- Handles skill configuration, enabling/disabling, etc.
-- This is the core, runtime changeable data storage

local skill_config = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "SkillConfig", cplus_plus_ex.DEBUG.CONFIG and cplus_plus_ex.DEBUG.ENABLED)

-- Local references to other submodules (set during init)
local skill_registry = nil
local utils = nil

-- Relationship Type Enum
skill_config.RelationshipType = {
	PILOT_SKILL_EXCLUSIONS = "pilotSkillExclusions",
	PILOT_SKILL_INCLUSIONS = "pilotSkillInclusions",
	SKILL_EXCLUSIONS = "skillExclusions",
}

-- Mapping from relationship type to config keys and UI metadata
local relationshipConfigKeys = {
	[skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS] = {
		added = "addedPilotSkillExclusions",
		removed = "removedPilotSkillExclusions",
		sortOrder = "pilotSkillExclusionsSortOrder",
		title = "Exclusions: Pilot → Skill",
		tooltip = "Prevent specific pilots from receiving certain skills",
		sourceLabel = "Pilot",
		targetLabel = "Skill",
		isBidirectional = false,
	},
	[skill_config.RelationshipType.PILOT_SKILL_INCLUSIONS] = {
		added = "addedPilotSkillInclusions",
		removed = "removedPilotSkillInclusions",
		sortOrder = "pilotSkillInclusionsSortOrder",
		title = "Inclusions: Pilot → Skill ",
		tooltip = "Allow specific pilots to receive the skill",
		sourceLabel = "Pilot",
		targetLabel = "Skill",
		isBidirectional = false,
	},
	[skill_config.RelationshipType.SKILL_EXCLUSIONS] = {
		added = "addedSkillExclusions",
		removed = "removedSkillExclusions",
		sortOrder = "skillExclusionsSortOrder",
		title = "Exclusions: Skill ↔ Skill",
		tooltip = "Prevent certain skills from being selected together on the same pilot",
		sourceLabel = "Skill",
		targetLabel = "Skill",
		isBidirectional = true,
	},
}

-- Public getter for relationship metadata
function skill_config:getRelationshipMetadata(relationshipType)
	return relationshipConfigKeys[relationshipType]
end

-- SkillConfig class definition
-- Note: Defaults are set in new() to avoid forward reference issues
skill_config.SkillConfig = {
	enabled = false,
	weight = cplus_plus_ex.DEFAULT_WEIGHT,
	reusability = cplus_plus_ex.DEFAULT_REUSABILITY,
	slotRestriction = cplus_plus_ex.DEFAULT_SLOT_RESTRICTION,
}
skill_config.SkillConfig.__index = skill_config.SkillConfig

function skill_config.SkillConfig.new(data)
	local instance = setmetatable({}, skill_config.SkillConfig)

	-- copy any struct values using passed values or the defaults
	-- Use deep copies just in case (currently not needed but future proofing)
	for k, v in pairs(skill_config.SkillConfig) do
		if data and data[k] then
			instance[k] = utils.deepcopy(data[k])
		else
			instance[k] = utils.deepcopy(v)
		end
	end
	return instance
end

-- Config structure - owned by this module
-- These are runtime changeable configuration parameters
skill_config.config = {
	allowReusableSkills = false, -- will be set on load by options but default to vanilla
	enablePoolExclusions = true, -- Enable pool based skill exclusions
	skillConfigs = {}, -- skillId -> enabled, weight, reusability, slotRestriction
	skillConfigSortOrder = 1, -- 1=Name, 2=Enabled, 3=Reusability, 4=Slot, 5=Weight/%
	categoryCollapseStates = {}, -- category name -> collapsed state
	emptyPools = {}, -- poolName -> true for manually created empty pools
	poolsCollapseStates = {}, -- poolName -> collapsed state
	poolsItemsPerRow = 4, -- Number of skills to show per row in pool grid
	poolsAdded = {}, -- skillId -> {poolName: true} user additions
	poolsRemoved = {}, -- skillId -> {poolName: true} user removals
}
-- Track if saved config was loaded
skill_config.configLoaded = false

-- Initialize relationship tables using enum
for relType, keys in pairs(relationshipConfigKeys) do
	skill_config.config[relType] = {}  -- Active runtime relationships
	skill_config.config[keys.added] = {}  -- User added relationships
	skill_config.config[keys.removed] = {}  -- User removed, code defined relationships
	skill_config.config[keys.sortOrder] = 1  -- Sort order
end

-- configured pools put in reverse index for easy constraint checking
skill_config.pools = {}  -- poolName -> { skillIds: {skillId: true} }

-- Code defined relationships which are read and set during registration but not
-- saved so they can be changed easily
skill_config.codeDefinedRelationships = {}
for _, relType in pairs(skill_config.RelationshipType) do
	skill_config.codeDefinedRelationships[relType] = {}
end

-- Code defined pools which are read and set during registration but not saved
--- Structure: skillId -> {poolName: true}
skill_config.codeDefinedPools = {}

-- Module state
skill_config.enabledSkills = {}  -- skillId -> {shortName, fullName, description, bonuses, skillType, reusability, icon}
skill_config.enabledSkillsIds = {}  -- Array of skill ids enabled

-- Initialize the module
function skill_config:init()
	skill_registry = cplus_plus_ex._subobjects.skill_registry
	utils = cplus_plus_ex._subobjects.utils
	return self
end

-- Called after all mods are loaded
function skill_config:_postModsLoaded()
	self:_rebuildRelationships()
	self:_rebuildPools()

	-- Set the defaults to our registered/setup values
	logger.logDebug(SUBMODULE, "Post-mods loaded: capturing default configs")
	self:_captureDefaultConfigs()

	-- Log summary of registered skills
	local enabledCount = #self.enabledSkillsIds
	local totalCount = 0
	for _ in pairs(self.config.skillConfigs) do totalCount = totalCount + 1 end
	logger.logInfo(SUBMODULE, "Configuration loaded: " .. enabledCount .. " enabled / " .. totalCount .. " total skills")

	-- Load any saved configurations
	self:loadConfiguration()
end

-- Get all enabled skill IDs as a set (skillId -> true)
function skill_config:getEnabledSkillsSet()
	local enabledSet = {}
	for skillId, skillConfig in pairs(self.config.skillConfigs) do
		if skillConfig.enabled then
			enabledSet[skillId] = true
		end
	end
	return enabledSet
end

-- Get allowed reusability options for a skill
function skill_config:getAllowedReusability(skillId)
	-- This is called by register before the skills are registered so default to all allowed
	local minReusability = cplus_plus_ex.REUSABLILITY.REUSABLE
	if skill_registry.registeredSkills[skillId] and skill_registry.registeredSkills[skillId].maxReusability then
		minReusability = skill_registry.registeredSkills[skillId].maxReusability
	end
	local allowed = {}

	for val = minReusability, cplus_plus_ex.REUSABLILITY.PER_RUN do
		allowed[val] = true
	end
	return allowed
end

-- Sets the configs for a skill and updates enabled states
function skill_config:setSkillConfig(skillId, config)
	local curr_config = self.config.skillConfigs[skillId] or self.SkillConfig.new()
	local new_config = utils.deepcopy(curr_config)

	if config.enabled ~= nil then
		if config.enabled then
			new_config.enabled = true
		else
			new_config.enabled = false
		end
	end

	if config.weight then
		if config.weight < 0 then
			logger.logError(SUBMODULE, "Skill weight must be >= 0, got " .. config.weight .. " for skill " .. skillId)
			return
		end
		new_config.weight = config.weight
		logger.logDebug(SUBMODULE, "Set skill weight from %f to %f for skill %s", curr_config.weight, config.weight, skillId)
	end

	if config.reusability then
		local normalizeReuse = utils.normalizeReusabilityToInt(config.reusability)
		if not normalizeReuse then
			logger.logError(SUBMODULE, "Invalid skill reusability passed: " .. config.reusability .. " for skill " .. skillId)
			return
		elseif not self:getAllowedReusability(skillId)[normalizeReuse] then
			logger.logError(SUBMODULE, "Unallowed skill reusability passed: " .. config.reusability .. " (normalized to " .. normalizeReuse .. ") for skill " .. skillId)
			return
		end
		new_config.reusability = normalizeReuse
		logger.logDebug(SUBMODULE, "Set skill reusability from %s (value=%s) to %s (value=%s) for skill %s",
				cplus_plus_ex.REUSABLILITY[utils.normalizeReusabilityToInt(curr_config.reusability)],
				tostring(curr_config.reusability), cplus_plus_ex.REUSABLILITY[normalizeReuse],
				tostring(normalizeReuse), skillId)
	end

	if config.slotRestriction then
		local normalizeSlot = utils.normalizeSlotRestrictionToInt(config.slotRestriction)
		if not normalizeSlot then
			logger.logError(SUBMODULE, "Invalid skill slot restriction passed: " .. config.slotRestriction .. " for skill " .. skillId)
			return
		end
		new_config.slotRestriction = normalizeSlot
		logger.logDebug(SUBMODULE, "Set skill slot restriction from %s to %s for skill %s",
				cplus_plus_ex.SLOT_RESTRICTION[utils.normalizeSlotRestrictionToInt(curr_config.slotRestriction)],
				cplus_plus_ex.SLOT_RESTRICTION[normalizeSlot], skillId)
	end

	-- Handle pools parameter
	if config.pools ~= nil then
		if type(config.pools) ~= "table" then
			logger.logError(SUBMODULE, "Invalid pools passed for skill %s: must be array of strings", skillId)
			return
		end
		-- Validate all pool names are strings
		for _, poolName in ipairs(config.pools) do
			if type(poolName) ~= "string" then
				logger.logError(SUBMODULE, "Invalid pool name in pools for skill %s: must be string, got %s", skillId, type(poolName))
				return
			end
		end

		-- Store as code defined pools using dictionary structure
		if not self.codeDefinedPools[skillId] then
			self.codeDefinedPools[skillId] = {}
		end
		for _, poolName in ipairs(config.pools) do
			self.codeDefinedPools[skillId][poolName] = true
		end
		if #config.pools > 0 then
			logger.logDebug(SUBMODULE, "Set code defined pools for skill %s: %s", skillId, table.concat(config.pools, ", "))
		end
	end

	-- If we reached here, its a good config. Apply it
	self.config.skillConfigs[skillId] = new_config

	if new_config.enabled and not curr_config.enabled then
		self:_enableSkill_internal(skillId)
	elseif not new_config.enabled and curr_config.enabled then
		self:_disableSkill_internal(skillId)
	end

	logger.logDebug(SUBMODULE, "Set config for skill %s", skillId)
end

function skill_config:enableSkill(skillId, forceApply)
	-- Only apply if config was not loaded from save (configLoaded flag), unless force is true (from UI)
	if not forceApply and self.configLoaded then
		return
	end
	self:setSkillConfig(skillId, {enabled = true})
end

function skill_config:disableSkill(skillId, forceApply)
	-- Only apply if config was not loaded from save (configLoaded flag), unless force is true (from UI)
	if not forceApply and self.configLoaded then
		return
	end
	self:setSkillConfig(skillId, {enabled = false})
end

-- Enable a skill. Should not be called directly
function skill_config:_enableSkill_internal(id)
	local skill = skill_registry.registeredSkills[id]

	-- Check if already enabled
	if self.enabledSkills[id] ~= nil then
		logger.logWarn(SUBMODULE, "Skill " .. id .. " already enabled, skipping")
	else
		-- Add the skill to enabled list. We don't care at this point if its inclusion type or not
		self.enabledSkills[id] = skill
		table.insert(self.enabledSkillsIds, id)

		logger.logDebug(SUBMODULE, "Enabled skill: %s (type: %s, defaultReusability: %s, maxReusability: %s)",
				id, skill.skillType, skill.defaultReusability, skill.maxReusability)

		-- Trigger state update for enabled skills
		if cplus_plus_ex._subobjects and cplus_plus_ex._subobjects.skill_state_tracker then
			cplus_plus_ex._subobjects.skill_state_tracker:_updateEnabledSkills()
		end
	end
	logger.logDebug(SUBMODULE, "Skill %s enabled", id)
end

-- Disable a skill. Should not be called directly
function skill_config:_disableSkill_internal(id)
	if self.enabledSkills[id] == nil then
		logger.logWarn(SUBMODULE, "Skill " .. id .. " already disabled, skipping")
	else
		self.enabledSkills[id] = nil
		for idx, skillId in ipairs(self.enabledSkillsIds) do
			if skillId == id then
				table.remove(self.enabledSkillsIds, idx)
				logger.logDebug(SUBMODULE, "Disabled skill: %s (idx: %d)", id, idx)
				break
			end
		end

		-- Trigger state update for enabled skills
		if cplus_plus_ex._subobjects and cplus_plus_ex._subobjects.skill_state_tracker then
			cplus_plus_ex._subobjects.skill_state_tracker:_updateEnabledSkills()
		end
	end
	logger.logDebug(SUBMODULE, "Skill %s disabled", id)
end

-- Check if a relationship exists
function skill_config:_relationshipExists(relationshipTable, sourceId, targetId)
	return relationshipTable[sourceId] ~= nil and relationshipTable[sourceId][targetId] == true
end

-- Add a relationship
function skill_config:_addRelationship(relationshipTable, sourceId, targetId)
	if not relationshipTable[sourceId] then
		relationshipTable[sourceId] = {}
	end
	relationshipTable[sourceId][targetId] = true
end

-- Remove a relationship
function skill_config:_removeRelationship(relationshipTable, sourceId, targetId)
	if relationshipTable[sourceId] then
		relationshipTable[sourceId][targetId] = nil
		local hasAny = false
		for _, _ in pairs(relationshipTable[sourceId]) do
			hasAny = true
			break
		end
		if not hasAny then
			relationshipTable[sourceId] = nil
		end
	end
end

-- Merge code defined relationships with user modifications (adds and removal of code defined ones)
function skill_config:_mergeRelationships(codeDefinedTable, addedTable, removedTable)
	local merged = {}

	for sourceId, targets in pairs(codeDefinedTable) do
		for targetId, _ in pairs(targets) do
			if not self:_relationshipExists(removedTable, sourceId, targetId) then
				self:_addRelationship(merged, sourceId, targetId)
			end
		end
	end

	for sourceId, targets in pairs(addedTable) do
		for targetId, _ in pairs(targets) do
			self:_addRelationship(merged, sourceId, targetId)
		end
	end

	return merged
end

-- Rebuild runtime relationship tables
function skill_config:_rebuildRelationships()
	for relType, keys in pairs(relationshipConfigKeys) do
		self.config[relType] = self:_mergeRelationships(
			self.codeDefinedRelationships[relType],
			self.config[keys.added],
			self.config[keys.removed]
		)
	end

	logger.logDebug(SUBMODULE, "Rebuilt active relationships for constraint checking")
end

-- User adds a relationship
function skill_config:addRelationshipToRuntime(relationshipType, sourceId, targetId)
	local keys = relationshipConfigKeys[relationshipType]
	if not keys then
		logger.logError(SUBMODULE, "Invalid relationship type: " .. tostring(relationshipType))
		return
	end

	local codeDefinedTable = self.codeDefinedRelationships[relationshipType]
	local addedTable = self.config[keys.added]
	local removedTable = self.config[keys.removed]
	local runtimeTable = self.config[relationshipType]

	if self:_relationshipExists(codeDefinedTable, sourceId, targetId) then
		self:_removeRelationship(removedTable, sourceId, targetId)
	else
		self:_addRelationship(addedTable, sourceId, targetId)
	end

	self:_addRelationship(runtimeTable, sourceId, targetId)
end

-- User removes a relationship
function skill_config:removeRelationshipFromRuntime(relationshipType, sourceId, targetId)
	local keys = relationshipConfigKeys[relationshipType]
	if not keys then
		logger.logError(SUBMODULE, "Invalid relationship type: " .. tostring(relationshipType))
		return
	end

	local codeDefinedTable = self.codeDefinedRelationships[relationshipType]
	local addedTable = self.config[keys.added]
	local removedTable = self.config[keys.removed]
	local runtimeTable = self.config[relationshipType]

	if self:_relationshipExists(codeDefinedTable, sourceId, targetId) then
		self:_addRelationship(removedTable, sourceId, targetId)
	else
		self:_removeRelationship(addedTable, sourceId, targetId)
	end

	self:_removeRelationship(runtimeTable, sourceId, targetId)
end

-- Check if relationship is code defined
function skill_config:isCodeDefinedRelationship(relationshipType, sourceId, targetId)
	return self:_relationshipExists(self.codeDefinedRelationships[relationshipType], sourceId, targetId)
end

--- Check if a skill's pool membership is code defined
function skill_config:isCodeDefinedPool(skillId, poolName)
	return self.codeDefinedPools[skillId] and self.codeDefinedPools[skillId][poolName] == true
end

function skill_config:_captureDefaultConfigs()
	self.defaultConfig = utils.deepcopy(self.config)
end

-- Resets configuration to default state
-- Restores all values to what they were at initial load - i.e. to the
-- code defined relationships and default values for skills
function skill_config:resetToDefaults()
	-- Restore all config values from the captured defaults
	utils.deepcopyInPlace(self.config, self.defaultConfig)

	-- Clear all user modified relationships
	for _, keys in pairs(relationshipConfigKeys) do
		self.config[keys.added] = {}
		self.config[keys.removed] = {}
	end
	
	-- Clear the configLoaded flag so coded enable/disable can apply
	self.configLoaded = false

	-- Clear all user modified pools
	self.config.poolsAdded = {}
	self.config.poolsRemoved = {}
	self.config.emptyPools = {}

	-- Rebuild active relationship and pool tables from code defined sources
	self:_rebuildRelationships()
	self:_rebuildPools()

	-- Rebuild enabled skills list from the reset config
	self.enabledSkills = {}
	self.enabledSkillsIds = {}

	for skillId, skillConfigObj in pairs(self.config.skillConfigs) do
		if skillConfigObj.enabled then
			local skill = skill_registry.registeredSkills[skillId]
			self.enabledSkills[skillId] = skill
			table.insert(self.enabledSkillsIds, skillId)
		end
	end

	-- Trigger state update for enabled skills
	if cplus_plus_ex._subobjects and cplus_plus_ex._subobjects.skill_state_tracker then
		cplus_plus_ex._subobjects.skill_state_tracker:_updateEnabledSkills()
	end

	-- Note: Saving is handled by the caller (e.g., UI saveConfiguration())
	logger.logDebug(SUBMODULE, "Reset configuration to defaults")
end

-- Save configuration to modcontent.lua (pattern from time_traveler.lua)
function skill_config:saveConfiguration()
	if not modApi:isProfilePath() then return end

	logger.logDebug(SUBMODULE, "Saving skill configuration to modcontent.lua")

	sdlext.config(
		modApi:getCurrentProfilePath().."modcontent.lua",
		function(obj)
			-- Get existing cplus_plus section if it exists or create it
			obj.cplus_plus_ex = obj.cplus_plus_ex or {}
			-- Just copy over the whole table each time instead of trying to update
			obj.cplus_plus_ex.skill_config = utils.deepcopy(skill_config.config)

			-- Clear runtime computed relationship tables - they will be rebuilt on load
			for _, relType in pairs(skill_config.RelationshipType) do
				obj.cplus_plus_ex.skill_config[relType] = nil
			end

			-- clear out some unneded fields
			for id, config in pairs(obj.cplus_plus_ex.skill_config.skillConfigs) do
				config.__index = nil
				config.new = nil
			end
		end
	)
end

-- Load configuration from modcontent.lua (pattern from time_traveler.lua)
-- Merges saved config into current config to preserve defaults for newly added skills
function skill_config:loadConfiguration()
	if not modApi:isProfilePath() then return end

	logger.logDebug(SUBMODULE, "Loading skill configuration from modcontent.lua")

	sdlext.config(
		modApi:getCurrentProfilePath().."modcontent.lua",
		function(obj)
			if obj.cplus_plus_ex and obj.cplus_plus_ex.skill_config then
				local savedConfig = obj.cplus_plus_ex.skill_config

				-- Merge saved config into current config
				-- This preserves defaults for newly registered skills

				-- Update simple boolean flags
				if savedConfig.allowReusableSkills ~= nil then
					skill_config.config.allowReusableSkills = savedConfig.allowReusableSkills
				end

				-- Update UI sort preferences
				if savedConfig.skillConfigSortOrder then
					skill_config.config.skillConfigSortOrder = savedConfig.skillConfigSortOrder
				end

				-- Load relationship sort orders and added/removed tables
				for _, keys in pairs(relationshipConfigKeys) do
					if savedConfig[keys.sortOrder] then
						skill_config.config[keys.sortOrder] = savedConfig[keys.sortOrder]
					end
					if savedConfig[keys.added] then
						skill_config.config[keys.added] = utils.deepcopy(savedConfig[keys.added])
					end
					if savedConfig[keys.removed] then
						skill_config.config[keys.removed] = utils.deepcopy(savedConfig[keys.removed])
					end
				end

				-- Load category collapse states
				if savedConfig.categoryCollapseStates then
					skill_config.config.categoryCollapseStates = utils.deepcopy(savedConfig.categoryCollapseStates)
				end

				-- Load pool collapse states
				if savedConfig.poolsCollapseStates then
					skill_config.config.poolsCollapseStates = utils.deepcopy(savedConfig.poolsCollapseStates)
				end

				-- Load pool grid preference
				if savedConfig.poolsItemsPerRow then
					skill_config.config.poolsItemsPerRow = savedConfig.poolsItemsPerRow
				end

				self:_rebuildRelationships()

				-- Merge skillConfigs to update existing skill but preserve new defaults
				if savedConfig.skillConfigs then
					for skillId, savedSkillConfig in pairs(savedConfig.skillConfigs) do
						-- Only update if skill was registered
						if skill_config.config.skillConfigs[skillId] then
							-- Copy saved config
							skill_config.config.skillConfigs[skillId] = utils.deepcopy(savedSkillConfig)
						else
							logger.logDebug(SUBMODULE, "Ignoring saved config for removed skill: %s", skillId)
						end
					end
				end
				
				-- Mark that we loaded a saved config so future coded enable/disable calls will be ignored
				skill_config.configLoaded = true

				-- Load user pool modifications (added/removed)
				if savedConfig.poolsAdded then
					skill_config.config.poolsAdded = utils.deepcopy(savedConfig.poolsAdded)
				end
				if savedConfig.poolsRemoved then
					skill_config.config.poolsRemoved = utils.deepcopy(savedConfig.poolsRemoved)
				end

				-- Load empty pools
				if savedConfig.emptyPools then
					skill_config.config.emptyPools = utils.deepcopy(savedConfig.emptyPools)
				end

				-- Load enablePoolExclusions setting
				if savedConfig.enablePoolExclusions ~= nil then
					skill_config.config.enablePoolExclusions = savedConfig.enablePoolExclusions
				end

				self:_rebuildEnabledSkills()
				-- Rebuild pools from code-defined + user modifications
				self:_rebuildPools()
				logger.logDebug(SUBMODULE, "Loaded and merged skill configuration")
			end
		end
	)
end

function skill_config:_rebuildEnabledSkills()
	-- Rebuild enabled skills list from merged config
	self.enabledSkills = {}
	self.enabledSkillsIds = {}

	for skillId, skillConfigObj in pairs(self.config.skillConfigs) do
		if skillConfigObj.enabled then
			local skill = skill_registry.registeredSkills[skillId]
			self.enabledSkills[skillId] = skill
			table.insert(self.enabledSkillsIds, skillId)
		end
	end

	-- Trigger state update for enabled skills
	if cplus_plus_ex._subobjects and cplus_plus_ex._subobjects.skill_state_tracker then
		cplus_plus_ex._subobjects.skill_state_tracker:_updateEnabledSkills()
	end
end

function skill_config:_rebuildPools()
	-- Rebuild pools from code defined and user modifications
	self.pools = {}

	if not self.config or not self.config.skillConfigs then
		logger.logDebug(SUBMODULE, "_rebuildPools: No config or skillConfigs yet")
		return
	end

	-- Process all registered skills
	for skillId in pairs(self.config.skillConfigs) do
		-- Get merged pool list for this skill
		local mergedPools = self:_getMergedPoolsForSkill(skillId)

		if #mergedPools > 0 then
			logger.logDebug(SUBMODULE, "_rebuildPools: Skill '%s' has %d pool(s): %s",
				skillId, #mergedPools, table.concat(mergedPools, ", "))

			for _, poolName in ipairs(mergedPools) do
				if not self.pools[poolName] then
					self.pools[poolName] = {
						name = poolName,
						skillIds = {}
					}
					logger.logDebug(SUBMODULE, "_rebuildPools: Created pool '%s'", poolName)
				end
				self.pools[poolName].skillIds[skillId] = true
			end
		end
	end

	logger.logInfo(SUBMODULE, "Rebuilt pools index: %d pool(s)", self:_countPools())
	for poolName, pool in pairs(self.pools) do
		local skillCount = 0
		for _ in pairs(pool.skillIds) do skillCount = skillCount + 1 end
		logger.logInfo(SUBMODULE, "  Pool '%s': %d skill(s)", poolName, skillCount)
	end
end

--- Merge code defined pools with user modifications
--- Returns dictionary: {poolName: true}
function skill_config:_mergePoolsForSkill(skillId, codeDefinedTable, addedTable, removedTable)
	local merged = {}

	-- Start with code defined pools
	local codePools = codeDefinedTable[skillId] or {}
	for poolName, _ in pairs(codePools) do
		-- Only include if not in removed list
		if not (removedTable[skillId] and removedTable[skillId][poolName]) then
			merged[poolName] = true
		end
	end

	-- Add user additions
	local added = addedTable[skillId] or {}
	for poolName, _ in pairs(added) do
		merged[poolName] = true
	end

	return merged
end

--- Get merged pool list for a skill (code + added - removed) as array for convenience
--- This is a helper that converts the dictionary to an array
function skill_config:_getMergedPoolsForSkill(skillId)
	local mergedDict = self:_mergePoolsForSkill(
		skillId,
		self.codeDefinedPools,
		self.config.poolsAdded or {},
		self.config.poolsRemoved or {}
	)

	-- Convert dictionary to array
	local merged = {}
	for poolName in pairs(mergedDict) do
		table.insert(merged, poolName)
	end

	return merged
end

--- Check if a skill is currently in a pool (after merging code defined and user changes)
function skill_config:isSkillInPool(skillId, poolName)
	local pool = self.pools[poolName]
	if not pool then
		return false
	end
	return pool.skillIds[skillId] == true
end

function skill_config:_countPools()
	local count = 0
	for _ in pairs(self.pools) do count = count + 1 end
	return count
end

function skill_config:deletePool(poolName)
	-- Remove pool from all skills by updating added/removed tracking
	for skillId in pairs(self.config.skillConfigs) do
		-- Check if skill is currently in this pool
		if self:isSkillInPool(skillId, poolName) then
			-- Remove the skill from the pool
			self:removeSkillFromPool(skillId, poolName)
		end
	end

	-- Remove from empty pools tracking
	self.config.emptyPools[poolName] = nil

	-- Remove pool UI state
	self.config.poolsCollapseStates[poolName] = nil

	-- Rebuild is handled by removeSkillFromPool calls above
	logger.logDebug(SUBMODULE, "Deleted pool '%s'", poolName)
	return true
end

function skill_config:addSkillToPool(skillId, poolName)
	if not self.config.skillConfigs[skillId] then
		logger.logError(SUBMODULE, "Skill '%s' not registered", skillId)
		return false
	end

	-- Get current merged pools for this skill as dictionary
	local currentPools = self:_mergePoolsForSkill(
		skillId,
		self.codeDefinedPools,
		self.config.poolsAdded,
		self.config.poolsRemoved
	)

	-- Check if already in merged pool dictionary
	if currentPools[poolName] then
		logger.logDebug(SUBMODULE, "Skill '%s' already in pool '%s'", skillId, poolName)
		return true
	end

	-- Check if this is code defined
	local isCodeDefined = self:isCodeDefinedPool(skillId, poolName)

	if isCodeDefined then
		-- It is code defined but was removed by user adn readded so remove from removals dictionary
		if self.config.poolsRemoved[skillId] then
			self.config.poolsRemoved[skillId][poolName] = nil
		end
		logger.logDebug(SUBMODULE, "Removed '%s' from poolsRemoved for skill '%s'", poolName, skillId)
	else
		-- It is a user addition so add to additions dictionary
		if not self.config.poolsAdded[skillId] then
			self.config.poolsAdded[skillId] = {}
		end
		self.config.poolsAdded[skillId][poolName] = true
		logger.logDebug(SUBMODULE, "Added '%s' to poolsAdded for skill '%s'", poolName, skillId)
	end

	-- Remove from emptyPools if it was an empty, manually created pools
	if self.config.emptyPools[poolName] then
		self.config.emptyPools[poolName] = nil
	end

	self:_rebuildPools()
	return true
end

function skill_config:removeSkillFromPool(skillId, poolName)
	if not self.config.skillConfigs[skillId] then
		logger.logWarn(SUBMODULE, "Skill '%s' not registered", skillId)
		return false
	end

	-- Get current merged pools for this skill
	local currentPools = self:_mergePoolsForSkill(
		skillId,
		self.codeDefinedPools,
		self.config.poolsAdded,
		self.config.poolsRemoved
	)

	-- Check if currently in pool
	if not currentPools[poolName] then
		logger.logDebug(SUBMODULE, "Skill '%s' not in pool '%s'", skillId, poolName)
		return true
	end

	-- Check if this is code defined
	local isCodeDefined = self:isCodeDefinedPool(skillId, poolName)

	if isCodeDefined then
		-- It is code defined so add to removals dictionary
		if not self.config.poolsRemoved[skillId] then
			self.config.poolsRemoved[skillId] = {}
		end
		self.config.poolsRemoved[skillId][poolName] = true
		logger.logDebug(SUBMODULE, "Added '%s' to poolsRemoved for skill '%s'", poolName, skillId)
	else
		-- It is a user addition so remove from additions dictionary
		if self.config.poolsAdded[skillId] then
			self.config.poolsAdded[skillId][poolName] = nil
			logger.logDebug(SUBMODULE, "Removed '%s' from poolsAdded for skill '%s'", poolName, skillId)
		end
	end

	self:_rebuildPools()
	return true
end

function skill_config:getPool(poolName)
	-- Return pool from computed index if it exists
	if self.pools[poolName] then
		return self.pools[poolName]
	end

	-- Return empty pool structure if it's a manually created empty pool
	if self.config.emptyPools[poolName] then
		return {
			name = poolName,
			skillIds = {}
		}
	end

	return nil
end

function skill_config:listPools()
	local poolNames = {}

	-- Add pools with skills (from computed index)
	for poolName in pairs(self.pools) do
		table.insert(poolNames, poolName)
	end

	-- Add empty pools that were manually created
	for poolName in pairs(self.config.emptyPools) do
		local alreadyAdded = false
		for _, existing in ipairs(poolNames) do
			if existing == poolName then
				alreadyAdded = true
				break
			end
		end
		if not alreadyAdded then
			table.insert(poolNames, poolName)
		end
	end

	table.sort(poolNames)
	logger.logDebug(SUBMODULE, "listPools: Returning %d pool(s)", #poolNames)
	return poolNames
end

function skill_config:isSkillInPool(skillId, poolName)
	local pool = self.pools[poolName]
	if not pool then return false end
	return pool.skillIds[skillId] == true
end

return skill_config
