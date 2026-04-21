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
	skillConfigs = {}, -- skillId -> enabled, weight, reusability, slotRestriction
	categoryCollapseStates = {}, -- category name -> collapsed state
	enableGroupExclusions = true, -- Main toggle for group exclusions
	emptyGroups = {}, -- groupName -> true for manually created empty groups
	groupsAdded = {}, -- skillId -> {groupName = true} - User added group memberships
	groupsRemoved = {}, -- skillId -> {groupName = true} - User removed code defined group memberships
	groupSettings = {}, -- groupName -> {enabled = bool} - Per group settings
	groupsItemsPerRow = 4, -- Grid size for group skill display
	groupsCollapseStates = {}, -- groupName -> collapsed state
}
-- Track if saved config was loaded
skill_config.configLoaded = false

-- Initialize relationship tables using enum
for relType, keys in pairs(relationshipConfigKeys) do
	skill_config.config[relType] = {}  -- Active runtime relationships
	skill_config.config[keys.added] = {}  -- User added relationships
	skill_config.config[keys.removed] = {}  -- User removed, code defined relationships
	skill_config.config[keys.sortOrder] = 1  -- Sort order (1 = first column, 2 = second column)
end

-- Code defined relationships which are read and set during registration but not
-- saved so they can be changed easily
skill_config.codeDefinedRelationships = {}
for _, relType in pairs(skill_config.RelationshipType) do
	skill_config.codeDefinedRelationships[relType] = {}
end

-- Tracks which groups each skill is assigned to via code, not user edits
skill_config.codeDefinedGroups = {}

-- Module state
skill_config.enabledSkills = {}  -- skillId -> {shortName, fullName, description, bonuses, skillType, reusability, icon}
skill_config.enabledSkillsIds = {}  -- Array of skill ids enabled
skill_config.groups = {}  -- groupName -> {name, skillIds = {skillId -> true}, enabled = bool}

-- Initialize the module
function skill_config:init()
	skill_registry = cplus_plus_ex._subobjects.skill_registry
	utils = cplus_plus_ex._subobjects.utils
	return self
end

-- Called after all mods are loaded
function skill_config:_postModsLoaded()
	self:_rebuildRelationships()
	self:_rebuildGroups()

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
	local reusabilityLimit = cplus_plus_ex.REUSABLILITY.REUSABLE
	if skill_registry.registeredSkills[skillId] and skill_registry.registeredSkills[skillId].reusabilityLimit then
		reusabilityLimit = skill_registry.registeredSkills[skillId].reusabilityLimit
	end
	local allowed = {}
	-- Set false for values below the limit
	for val = cplus_plus_ex.REUSABLILITY.REUSABLE, reusabilityLimit - 1 do
		allowed[val] = false
	end
	-- Set true for values at or above the limit
	for val = reusabilityLimit, cplus_plus_ex.REUSABLILITY.PER_RUN do
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

		logger.logDebug(SUBMODULE, "Enabled skill: %s (type: %s, defaultReusability: %s, reusabilityLimit: %s)",
				id, skill.skillType, skill.defaultReusability, skill.reusabilityLimit)

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

-- Merge code defined groups with user modifications for a specific skill
function skill_config:_mergeGroupsForSkill(skillId, codeDefinedTable, addedTable, removedTable)
	local merged = {}

	-- Start with code defined groups
	local codeGroups = codeDefinedTable[skillId] or {}
	for groupName, _ in pairs(codeGroups) do
		-- Only include if not in removed list
		if not (removedTable[skillId] and removedTable[skillId][groupName]) then
			merged[groupName] = true
		end
	end

	-- Add user additions
	local userGroups = addedTable[skillId] or {}
	for groupName, _ in pairs(userGroups) do
		merged[groupName] = true
	end

	return merged
end

-- Get merged groups for a skill as an array
function skill_config:_getMergedGroupsForSkill(skillId)
	local mergedDict = self:_mergeGroupsForSkill(
		skillId,
		self.codeDefinedGroups,
		self.config.groupsAdded or {},
		self.config.groupsRemoved or {}
	)

	-- Convert to array
	local merged = {}
	for groupName in pairs(mergedDict) do
		table.insert(merged, groupName)
	end

	return merged
end

-- Rebuild groups index from code defined + user changes
function skill_config:_rebuildGroups()
	self.groups = {}

	if not self.config or not self.config.skillConfigs then
		logger.logDebug(SUBMODULE, "_rebuildGroups: No config or skillConfigs yet")
		return
	end

	-- Process all registered skills
	for skillId in pairs(self.config.skillConfigs) do
		local mergedGroups = self:_getMergedGroupsForSkill(skillId)

		if #mergedGroups > 0 then
			logger.logDebug(SUBMODULE, "_rebuildGroups: Skill '%s' has %d group(s): %s",
				skillId, #mergedGroups, table.concat(mergedGroups, ", "))

			for _, groupName in ipairs(mergedGroups) do
				if not self.groups[groupName] then
					-- Initialize group with settings from config or defaults
					local settings = self.config.groupSettings[groupName] or {}
					self.groups[groupName] = {
						name = groupName,
						skillIds = {},
						enabled = settings.enabled ~= false  -- Default to enabled
					}
					logger.logDebug(SUBMODULE, "_rebuildGroups: Created group '%s'", groupName)
				else
					-- Group exists, update settings from config in case they changed
					local settings = self.config.groupSettings[groupName] or {}
					self.groups[groupName].enabled = settings.enabled ~= false
				end
				self.groups[groupName].skillIds[skillId] = true
			end
		end
	end

	-- Count groups
	local count = 0
	for _ in pairs(self.groups) do count = count + 1 end

	logger.logDebug(SUBMODULE, "Rebuilt groups index: %d group(s)", count)
	for groupName, group in pairs(self.groups) do
		local skillCount = 0
		for _ in pairs(group.skillIds) do skillCount = skillCount + 1 end
		logger.logDebug(SUBMODULE, "  Group '%s': %d skill(s), enabled=%s",
			groupName, skillCount, tostring(group.enabled))
	end
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

	-- Clear all user modified groups
	self.config.groupsAdded = {}
	self.config.groupsRemoved = {}
	self.config.emptyGroups = {}
	self.config.groupSettings = {}

	-- Clear the configLoaded flag so coded enable/disable can apply
	self.configLoaded = false

	-- Rebuild active relationship tables and groups from code defined sources
	self:_rebuildRelationships()
	self:_rebuildGroups()

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

				-- Load group related configuration
				if savedConfig.enableGroupExclusions ~= nil then
					skill_config.config.enableGroupExclusions = savedConfig.enableGroupExclusions
				end

				if savedConfig.groupsAdded then
					skill_config.config.groupsAdded = utils.deepcopy(savedConfig.groupsAdded)
				end

				if savedConfig.groupsRemoved then
					skill_config.config.groupsRemoved = utils.deepcopy(savedConfig.groupsRemoved)
				end

				if savedConfig.emptyGroups then
					skill_config.config.emptyGroups = utils.deepcopy(savedConfig.emptyGroups)
				end

				if savedConfig.groupSettings then
					skill_config.config.groupSettings = utils.deepcopy(savedConfig.groupSettings)
				end

				if savedConfig.groupsItemsPerRow then
					skill_config.config.groupsItemsPerRow = savedConfig.groupsItemsPerRow
				end

				if savedConfig.groupsCollapseStates then
					skill_config.config.groupsCollapseStates = utils.deepcopy(savedConfig.groupsCollapseStates)
				end

				self:_rebuildRelationships()
				self:_rebuildGroups()

				-- Merge skillConfigs to update existing skill but preserve new defaults
				if savedConfig.skillConfigs then
					for skillId, savedSkillConfig in pairs(savedConfig.skillConfigs) do
						-- Only update if skill was registered
						if skill_config.config.skillConfigs[skillId] then
							skill_config.config.skillConfigs[skillId] = utils.deepcopy(savedSkillConfig)
						else
							logger.logDebug(SUBMODULE, "Ignoring saved config for removed skill: %s", skillId)
						end
					end
				end

				-- Mark that we loaded a saved config so future coded enable/disable calls will be ignored
				skill_config.configLoaded = true

				self:_rebuildEnabledSkills()
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

-- Check if a group membership is code defined
function skill_config:isCodeDefinedGroup(skillId, groupName)
	return self.codeDefinedGroups[skillId] and self.codeDefinedGroups[skillId][groupName] == true
end

function skill_config:registerSkillToGroupToRuntime(skillId, groupName)
	if not self.config.skillConfigs[skillId] then
		logger.logWarn(SUBMODULE, "Skill '%s' not registered", skillId)
		return false
	end

	-- Get current merged groups for this skill as dictionary
	local currentGroups = self:_mergeGroupsForSkill(
		skillId,
		self.codeDefinedGroups,
		self.config.groupsAdded,
		self.config.groupsRemoved
	)

	-- Check if already in merged group dictionary
	if currentGroups[groupName] then
		logger.logDebug(SUBMODULE, "Skill '%s' already in group '%s'", skillId, groupName)
		return true
	end

	-- Check if this is code defined
	local isCodeDefined = self:isCodeDefinedGroup(skillId, groupName)

	if isCodeDefined then
		-- It's code defined but was removed by user and now being readded,
		-- so remove from groupsRemoved
		if self.config.groupsRemoved[skillId] then
			self.config.groupsRemoved[skillId][groupName] = nil
			-- Clean up empty tables
			if next(self.config.groupsRemoved[skillId]) == nil then
				self.config.groupsRemoved[skillId] = nil
			end
		end
		logger.logDebug(SUBMODULE, "Removed '%s' from groupsRemoved for skill '%s'", groupName, skillId)
	else
		-- User defined addition, track it
		if not self.config.groupsAdded[skillId] then
			self.config.groupsAdded[skillId] = {}
		end
		self.config.groupsAdded[skillId][groupName] = true
		logger.logDebug(SUBMODULE, "Added '%s' to groupsAdded for skill '%s'", groupName, skillId)
	end

	-- Remove from emptyGroups if it was an empty, manually created group
	if self.config.emptyGroups[groupName] then
		self.config.emptyGroups[groupName] = nil
	end

	self:_rebuildGroups()
	logger.logInfo(SUBMODULE, "Added skill '%s' to group '%s'", skillId, groupName)
	return true
end

function skill_config:removeSkillFromGroupFromRuntime(skillId, groupName)
	if not self.config.skillConfigs[skillId] then
		logger.logWarn(SUBMODULE, "Skill '%s' not registered", skillId)
		return false
	end

	-- Get current merged groups for this skill
	local currentGroups = self:_mergeGroupsForSkill(
		skillId,
		self.codeDefinedGroups,
		self.config.groupsAdded,
		self.config.groupsRemoved
	)

	-- Check if currently in group
	if not currentGroups[groupName] then
		logger.logDebug(SUBMODULE, "Skill '%s' not in group '%s'", skillId, groupName)
		return true
	end

	-- Check if this is code defined
	local isCodeDefined = self:isCodeDefinedGroup(skillId, groupName)

	if isCodeDefined then
		-- It's code defined, so track removal
		if not self.config.groupsRemoved[skillId] then
			self.config.groupsRemoved[skillId] = {}
		end
		self.config.groupsRemoved[skillId][groupName] = true
		logger.logDebug(SUBMODULE, "Added '%s' to groupsRemoved for skill '%s'", groupName, skillId)
	else
		-- User defined, remove from groupsAdded
		if self.config.groupsAdded[skillId] then
			self.config.groupsAdded[skillId][groupName] = nil
			-- Clean up empty tables
			if next(self.config.groupsAdded[skillId]) == nil then
				self.config.groupsAdded[skillId] = nil
			end
		end
		logger.logDebug(SUBMODULE, "Removed '%s' from groupsAdded for skill '%s'", groupName, skillId)
	end

	self:_rebuildGroups()
	logger.logInfo(SUBMODULE, "Removed skill '%s' from group '%s'", skillId, groupName)
	return true
end

function skill_config:addGroupToRuntime(groupName)
	self.config.emptyGroups[groupName] = true
	self:_rebuildGroups()
	logger.logInfo(SUBMODULE, "Created empty group '%s'", groupName)
end

function skill_config:deleteGroupFromRuntime(groupName)
	-- Remove group from all skills by updating added/removed tracking
	for skillId in pairs(self.config.skillConfigs) do
		-- Check if skill is currently in this group
		if self:isSkillInGroup(skillId, groupName) then
			-- Remove the skill from the group
			self:removeSkillFromGroupFromRuntime(skillId, groupName)
		end
	end

	-- Remove from empty groups tracking
	self.config.emptyGroups[groupName] = nil

	-- Remove group settings
	self.config.groupSettings[groupName] = nil

	-- Remove group UI state
	self.config.groupsCollapseStates[groupName] = nil

	logger.logInfo(SUBMODULE, "Deleted group '%s'", groupName)
end

function skill_config:getGroup(groupName)
	-- Return group from computed index if it exists
	if self.groups[groupName] then
		return self.groups[groupName]
	end

	-- Return empty group structure if it's a manually created empty group
	if self.config.emptyGroups[groupName] then
		local settings = self.config.groupSettings[groupName] or {}
		return {
			name = groupName,
			skillIds = {},
			enabled = settings.enabled ~= false
		}
	end

	return nil
end

function skill_config:listGroups()
	local groupNames = {}

	-- Add groups with skills from computed index
	for groupName in pairs(self.groups) do
		table.insert(groupNames, groupName)
	end

	-- Add empty groups that were manually created
	for groupName in pairs(self.config.emptyGroups) do
		local alreadyAdded = false
		for _, existing in ipairs(groupNames) do
			if existing == groupName then
				alreadyAdded = true
				break
			end
		end
		if not alreadyAdded then
			table.insert(groupNames, groupName)
		end
	end

	table.sort(groupNames)
	logger.logDebug(SUBMODULE, "listGroups: Returning %d group(s)", #groupNames)
	return groupNames
end

function skill_config:setGroupEnabled(groupName, enabled)
	if not self.config.groupSettings[groupName] then
		self.config.groupSettings[groupName] = {}
	end

	self.config.groupSettings[groupName].enabled = enabled

	-- Update the computed group if it exists
	if self.groups[groupName] then
		self.groups[groupName].enabled = enabled
	end

	logger.logInfo(SUBMODULE, "Set group '%s' enabled=%s", groupName, tostring(enabled))
	return true
end

function skill_config:isSkillInGroup(skillId, groupName)
	local group = self.groups[groupName]
	if not group then return false end
	return group.skillIds[skillId] == true
end

return skill_config
