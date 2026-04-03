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
	enableCategoryExclusions = true, -- Enable category based skill exclusions
	skillConfigs = {}, -- skillId -> enabled, weight, reusability, slotRestriction
	skillConfigSortOrder = 1, -- 1=Name, 2=Enabled, 3=Reusability, 4=Slot, 5=Weight/%
	categoryCollapseStates = {}, -- category name -> collapsed state
	emptyCategories = {}, -- categoryName -> true for manually created empty categories
	categoriesCollapseStates = {}, -- categoryName -> collapsed state
	categoriesItemsPerRow = 4, -- Number of skills to show per row in category grid
	categoriesAdded = {}, -- skillId -> {categoryName: true} user additions
	categoriesRemoved = {}, -- skillId -> {categoryName: true} user removals
	categorySettings = {}, -- categoryName -> {onlyOnePerPilot: bool, pilotInclusions: [], pilotExclusions: []}
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

-- configured categories put in reverse index for easy constraint checking
skill_config.categories = {}  -- categoryName -> { skillIds: {skillId: true} }

-- Code defined relationships which are read and set during registration but not
-- saved so they can be changed easily
skill_config.codeDefinedRelationships = {}
for _, relType in pairs(skill_config.RelationshipType) do
	skill_config.codeDefinedRelationships[relType] = {}
end

-- Code defined categories which are read and set during registration but not saved
--- Structure: skillId -> {categoryName: true}
skill_config.codeDefinedCategories = {}

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
	self:_rebuildCategories()

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

	-- Handle categories parameter
	if config.categories ~= nil then
		if type(config.categories) ~= "table" then
			logger.logError(SUBMODULE, "Invalid categories passed for skill %s: must be array of strings", skillId)
			return
		end
		-- Validate all category names are strings
		for _, categoryName in ipairs(config.categories) do
			if type(categoryName) ~= "string" then
				logger.logError(SUBMODULE, "Invalid category name in categories for skill %s: must be string, got %s", skillId, type(categoryName))
				return
			end
		end

		-- Store as code defined categories using dictionary structure
		if not self.codeDefinedCategories[skillId] then
			self.codeDefinedCategories[skillId] = {}
		end
		for _, categoryName in ipairs(config.categories) do
			self.codeDefinedCategories[skillId][categoryName] = true
		end
		if #config.categories > 0 then
			logger.logDebug(SUBMODULE, "Set code defined categories for skill %s: %s", skillId, table.concat(config.categories, ", "))
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

--- Check if a skill's category membership is code defined
function skill_config:isCodeDefinedCategory(skillId, categoryName)
	return self.codeDefinedCategories[skillId] and self.codeDefinedCategories[skillId][categoryName] == true
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

	-- Clear all user modified categories
	self.config.categoriesAdded = {}
	self.config.categoriesRemoved = {}
	self.config.emptyCategories = {}

	-- Rebuild active relationship and category tables from code defined sources
	self:_rebuildRelationships()
	self:_rebuildCategories()

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

				-- Load category collapse states
				if savedConfig.categoriesCollapseStates then
					skill_config.config.categoriesCollapseStates = utils.deepcopy(savedConfig.categoriesCollapseStates)
				end

				-- Load category grid preference
				if savedConfig.categoriesItemsPerRow then
					skill_config.config.categoriesItemsPerRow = savedConfig.categoriesItemsPerRow
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

				-- Load user category modifications (added/removed)
				if savedConfig.categoriesAdded then
					skill_config.config.categoriesAdded = utils.deepcopy(savedConfig.categoriesAdded)
				end
				if savedConfig.categoriesRemoved then
					skill_config.config.categoriesRemoved = utils.deepcopy(savedConfig.categoriesRemoved)
				end

				-- Load empty categories
				if savedConfig.emptyCategories then
					skill_config.config.emptyCategories = utils.deepcopy(savedConfig.emptyCategories)
				end

				-- Load enableCategoryExclusions setting
				if savedConfig.enableCategoryExclusions ~= nil then
					skill_config.config.enableCategoryExclusions = savedConfig.enableCategoryExclusions
				end

				-- Load category settings (onlyOnePerPilot, pilotInclusions, pilotExclusions)
				if savedConfig.categorySettings then
					skill_config.config.categorySettings = utils.deepcopy(savedConfig.categorySettings)
				end

				self:_rebuildEnabledSkills()
				-- Rebuild categories from code-defined + user modifications
				self:_rebuildCategories()
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

function skill_config:_rebuildCategories()
	-- Rebuild categories from code defined and user modifications
	self.categories = {}

	if not self.config or not self.config.skillConfigs then
		logger.logDebug(SUBMODULE, "_rebuildCategories: No config or skillConfigs yet")
		return
	end

	-- Process all registered skills
	for skillId in pairs(self.config.skillConfigs) do
		-- Get merged category list for this skill
		local mergedCategories = self:_getMergedCategoriesForSkill(skillId)

		if #mergedCategories > 0 then
			logger.logDebug(SUBMODULE, "_rebuildCategories: Skill '%s' has %d category(s): %s",
				skillId, #mergedCategories, table.concat(mergedCategories, ", "))

			for _, categoryName in ipairs(mergedCategories) do
				if not self.categories[categoryName] then
					-- Initialize category with settings from config or defaults
					local settings = self.config.categorySettings[categoryName] or {}
					self.categories[categoryName] = {
						name = categoryName,
						skillIds = {},
						onlyOnePerPilot = settings.onlyOnePerPilot or false,
						pilotInclusions = settings.pilotInclusions or {},
						pilotExclusions = settings.pilotExclusions or {}
					}
					logger.logDebug(SUBMODULE, "_rebuildCategories: Created category '%s'", categoryName)
				end
				self.categories[categoryName].skillIds[skillId] = true
			end
		end
	end

	logger.logInfo(SUBMODULE, "Rebuilt categories index: %d category(s)", self:_countCategories())
	for categoryName, category in pairs(self.categories) do
		local skillCount = 0
		for _ in pairs(category.skillIds) do skillCount = skillCount + 1 end
		logger.logInfo(SUBMODULE, "  Category '%s': %d skill(s)", categoryName, skillCount)
	end
end

--- Merge code defined categories with user modifications
--- Returns dictionary: {categoryName: true}
function skill_config:_mergeCategoriesForSkill(skillId, codeDefinedTable, addedTable, removedTable)
	local merged = {}

	-- Start with code defined categories
	local codeCategories = codeDefinedTable[skillId] or {}
	for categoryName, _ in pairs(codeCategories) do
		-- Only include if not in removed list
		if not (removedTable[skillId] and removedTable[skillId][categoryName]) then
			merged[categoryName] = true
		end
	end

	-- Add user additions
	local added = addedTable[skillId] or {}
	for categoryName, _ in pairs(added) do
		merged[categoryName] = true
	end

	return merged
end

--- Get merged category list for a skill (code + added - removed) as array for convenience
--- This is a helper that converts the dictionary to an array
function skill_config:_getMergedCategoriesForSkill(skillId)
	local mergedDict = self:_mergeCategoriesForSkill(
		skillId,
		self.codeDefinedCategories,
		self.config.categoriesAdded or {},
		self.config.categoriesRemoved or {}
	)

	-- Convert dictionary to array
	local merged = {}
	for categoryName in pairs(mergedDict) do
		table.insert(merged, categoryName)
	end

	return merged
end

--- Check if a skill is currently in a category (after merging code defined and user changes)
function skill_config:isSkillInCategory(skillId, categoryName)
	local category = self.categories[categoryName]
	if not category then
		return false
	end
	return category.skillIds[skillId] == true
end

function skill_config:_countCategories()
	local count = 0
	for _ in pairs(self.categories) do count = count + 1 end
	return count
end

function skill_config:deleteCategory(categoryName)
	-- Remove category from all skills by updating added/removed tracking
	for skillId in pairs(self.config.skillConfigs) do
		-- Check if skill is currently in this category
		if self:isSkillInCategory(skillId, categoryName) then
			-- Remove the skill from the category
			self:removeSkillFromCategory(skillId, categoryName)
		end
	end

	-- Remove from empty categories tracking
	self.config.emptyCategories[categoryName] = nil

	-- Remove category UI state
	self.config.categoriesCollapseStates[categoryName] = nil

	-- Rebuild is handled by removeSkillFromCategory calls above
	logger.logDebug(SUBMODULE, "Deleted category '%s'", categoryName)
	return true
end

function skill_config:addSkillToCategory(skillId, categoryName)
	if not self.config.skillConfigs[skillId] then
		logger.logError(SUBMODULE, "Skill '%s' not registered", skillId)
		return false
	end

	-- Get current merged categories for this skill as dictionary
	local currentCategories = self:_mergeCategoriesForSkill(
		skillId,
		self.codeDefinedCategories,
		self.config.categoriesAdded,
		self.config.categoriesRemoved
	)

	-- Check if already in merged category dictionary
	if currentCategories[categoryName] then
		logger.logDebug(SUBMODULE, "Skill '%s' already in category '%s'", skillId, categoryName)
		return true
	end

	-- Check if this is code defined
	local isCodeDefined = self:isCodeDefinedCategory(skillId, categoryName)

	if isCodeDefined then
		-- It is code defined but was removed by user adn readded so remove from removals dictionary
		if self.config.categoriesRemoved[skillId] then
			self.config.categoriesRemoved[skillId][categoryName] = nil
		end
		logger.logDebug(SUBMODULE, "Removed '%s' from categoriesRemoved for skill '%s'", categoryName, skillId)
	else
		-- It is a user addition so add to additions dictionary
		if not self.config.categoriesAdded[skillId] then
			self.config.categoriesAdded[skillId] = {}
		end
		self.config.categoriesAdded[skillId][categoryName] = true
		logger.logDebug(SUBMODULE, "Added '%s' to categoriesAdded for skill '%s'", categoryName, skillId)
	end

	-- Remove from emptyCategories if it was an empty, manually created category
	if self.config.emptyCategories[categoryName] then
		self.config.emptyCategories[categoryName] = nil
	end

	self:_rebuildCategories()
	return true
end

function skill_config:removeSkillFromCategory(skillId, categoryName)
	if not self.config.skillConfigs[skillId] then
		logger.logWarn(SUBMODULE, "Skill '%s' not registered", skillId)
		return false
	end

	-- Get current merged categories for this skill
	local currentCategories = self:_mergeCategoriesForSkill(
		skillId,
		self.codeDefinedCategories,
		self.config.categoriesAdded,
		self.config.categoriesRemoved
	)

	-- Check if currently in category
	if not currentCategories[categoryName] then
		logger.logDebug(SUBMODULE, "Skill '%s' not in category '%s'", skillId, categoryName)
		return true
	end

	-- Check if this is code-defined
	local isCodeDefined = self:isCodeDefinedCategory(skillId, categoryName)

	if isCodeDefined then
		-- It is code defined so add to removals dictionary
		if not self.config.categoriesRemoved[skillId] then
			self.config.categoriesRemoved[skillId] = {}
		end
		self.config.categoriesRemoved[skillId][categoryName] = true
		logger.logDebug(SUBMODULE, "Added '%s' to categoriesRemoved for skill '%s'", categoryName, skillId)
	else
		-- It is a user addition so remove from additions dictionary
		if self.config.categoriesAdded[skillId] then
			self.config.categoriesAdded[skillId][categoryName] = nil
			logger.logDebug(SUBMODULE, "Removed '%s' from categoriesAdded for skill '%s'", categoryName, skillId)
		end
	end

	self:_rebuildCategories()
	return true
end

function skill_config:getCategory(categoryName)
	-- Return category from computed index if it exists
	if self.categories[categoryName] then
		return self.categories[categoryName]
	end

	-- Return empty category structure if it's a manually created empty category
	if self.config.emptyCategories[categoryName] then
		return {
			name = categoryName,
			skillIds = {}
		}
	end

	return nil
end

function skill_config:listCategories()
	local categoryNames = {}

	-- Add categories with skills (from computed index)
	for categoryName in pairs(self.categories) do
		table.insert(categoryNames, categoryName)
	end

	-- Add empty categories that were manually created
	for categoryName in pairs(self.config.emptyCategories) do
		local alreadyAdded = false
		for _, existing in ipairs(categoryNames) do
			if existing == categoryName then
				alreadyAdded = true
				break
			end
		end
		if not alreadyAdded then
			table.insert(categoryNames, categoryName)
		end
	end

	table.sort(categoryNames)
	logger.logDebug(SUBMODULE, "listCategories: Returning %d category(s)", #categoryNames)
	return categoryNames
end

-- Get category settings (onlyOnePerPilot, pilotInclusions, pilotExclusions)
function skill_config:getCategorySettings(categoryName)
	return self.config.categorySettings[categoryName] or {
		onlyOnePerPilot = false,
		pilotInclusions = {},
		pilotExclusions = {}
	}
end

-- Update category settings
function skill_config:setCategorySettings(categoryName, settings)
	if not self.config.categorySettings[categoryName] then
		self.config.categorySettings[categoryName] = {}
	end

	if settings.onlyOnePerPilot ~= nil then
		self.config.categorySettings[categoryName].onlyOnePerPilot = settings.onlyOnePerPilot
	end

	if settings.pilotInclusions ~= nil then
		self.config.categorySettings[categoryName].pilotInclusions = settings.pilotInclusions
	end

	if settings.pilotExclusions ~= nil then
		self.config.categorySettings[categoryName].pilotExclusions = settings.pilotExclusions
	end

	-- Rebuild to apply changes
	self:_rebuildCategories()
	return true
end

function skill_config:isSkillInCategory(skillId, categoryName)
	local category = self.categories[categoryName]
	if not category then return false end
	return category.skillIds[skillId] == true
end

return skill_config
