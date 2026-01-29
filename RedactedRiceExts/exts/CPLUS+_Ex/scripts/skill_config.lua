-- Skill Configuration Module
-- Handles skill configuration, enabling/disabling, and weight adjustments
-- This is the core, runtime changeable data storage

local skill_config = {}

-- Local references to other submodules (set during init)
local skill_registry = nil
local utils = nil

-- SkillConfig class definition
-- Note: Defaults are set in new() to avoid forward reference issues
skill_config.SkillConfig = {
	enabled = false,
	set_weight = cplus_plus_ex.DEFAULT_WEIGHT,
	adj_weight = cplus_plus_ex.DEFAULT_WEIGHT,
	reusability = cplus_plus_ex.DEFAULT_REUSABILITY,
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
	pilotSkillExclusions = {}, -- pilotId -> excluded skill ids (set-like table) - auto-loaded from pilot Blacklists
	pilotSkillInclusions = {}, -- pilotId -> included skill ids (set-like table)
	skillExclusions = {},  -- skillId -> excluded skill ids (set-like table) - skills that cannot be taken together
	skillConfigs = {}, -- skillId -> enabled, weight, reusability
}

-- Module state
skill_config.enabledSkills = {}  -- skillId -> {shortName, fullName, description, bonuses, skillType, reusability}
skill_config.enabledSkillsIds = {}  -- Array of skill ids enabled

-- Initialize the module
function skill_config:init()
	skill_registry = cplus_plus_ex._subobjects.skill_registry
	utils = cplus_plus_ex._subobjects.utils
	return self
end

-- Called after all mods are loaded
function skill_config:postModsLoaded()
	-- Set the defaults to our registered/setup values
	self:captureDefaultConfigs()

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
	if skill_registry.registeredSkills[skillId] and skill_registry.registeredSkills[skillId].reusability then
		minReusability = skill_registry.registeredSkills[skillId].reusability
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

	if config.set_weight then
		if config.set_weight < 0 then
			LOG("PLUS Ext error: Skill weight must be >= 0, got " .. config.set_weight)
			return
		end
		new_config.set_weight = config.set_weight
		-- Also update adj_weight to match. It may be adjusted later as well but this ensures
		-- we have a valid value if for some reason we don't call auto-adjust weights (like
		-- we are doing in some of the tests)
		new_config.adj_weight = config.set_weight
		LOG(new_config.set_weight .. " " .. config.set_weight)
	end

	if config.reusability then
		local normalizeReuse = utils.normalizeReusabilityToInt(config.reusability)
		if not normalizeReuse then
			LOG("PLUS Ext: Error: Invalid skill reusability passed: " .. config.reusability)
			return
		elseif not self:getAllowedReusability(skillId)[normalizeReuse] then
			LOG("PLUS Ext: Error: Unallowed skill reusability passed: " .. config.reusability .. "(normalized to ".. normalizeReuse ..")")
			return
		end
		new_config.reusability = config.reusability
		LOG(new_config.reusability .. " " .. config.reusability)
	end

	-- If we reached here, its a good config. Apply it
	self.config.skillConfigs[skillId] = new_config
	if new_config.enabled and not curr_config.enabled then
		self:_enableSkill_internal(skillId)
	elseif not new_config.enabled and curr_config.enabled then
		self:_disableSkill_internal(skillId)
	end

	if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: Set config for skill " .. skillId) end
end

function skill_config:enableSkill(skillId)
	self:setSkillConfig(skillId, {enabled = true})
end

function skill_config:disableSkill(skillId)
	self:setSkillConfig(skillId, {enabled = false})
end

-- Enable a skill. Should not be called directly
function skill_config:_enableSkill_internal(id)
	local skill = skill_registry.registeredSkills[id]

	-- Check if already enabled
	if self.enabledSkills[id] ~= nil then
		LOG("PLUS Ext warning: Skill " .. id .. " already enabled, skipping")
	else
		-- Add the skill to enabled list. We don't care at this point if its inclusion type or not
		self.enabledSkills[id] = skill
		table.insert(self.enabledSkillsIds, id)

		if cplus_plus_ex.PLUS_DEBUG then
			local skillType = skill.skillType
			local reusability = skill.reusability
			LOG("PLUS Ext: Enabled skill: " .. id .. " (type: " .. skillType .. ", reusability: " .. reusability .. ")")
		end

		-- Trigger state update for enabled skills
		if cplus_plus_ex._subobjects and cplus_plus_ex._subobjects.skill_state_tracker then
			cplus_plus_ex._subobjects.skill_state_tracker:updateEnabledSkills()
		end
	end
	if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: Skill " .. id .. " enabled") end
end

-- Disable a skill. Should not be called directly
function skill_config:_disableSkill_internal(id)
	if self.enabledSkills[id] == nil then
		LOG("PLUS Ext: Warning: Skill " .. id .. " already disabled, skipping")
	else
		self.enabledSkills[id] = nil
		for idx, skillId in ipairs(self.enabledSkillsIds) do
			if skillId == id then
				table.remove(self.enabledSkillsIds, idx)
				if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: Disabled skill: " .. id .. " (idx: " .. idx .. ")") end
				break
			end
		end

		-- Trigger state update for enabled skills
		if cplus_plus_ex._subobjects and cplus_plus_ex._subobjects.skill_state_tracker then
			cplus_plus_ex._subobjects.skill_state_tracker:updateEnabledSkills()
		end
	end
	if cplus_plus_ex.PLUS_DEBUG then LOG("PLUS Ext: Skill " .. id .. " disabled") end
end

-- Copy set weights to adjusted weights for all skills
-- This can be extended in the future if we need weight adjustment logic
function skill_config:setAdjustedWeightsConfigs()
	-- Copy all the set weights to adj weights for all skills
	for skillId, _ in pairs(skill_registry.registeredSkills) do
		local config = self.config.skillConfigs[skillId]
		config.adj_weight = config.set_weight
	end
end

function skill_config:captureDefaultConfigs()
	self.defaultConfig = utils.deepcopy(self.config)
end

-- Resets configuration to default state
-- Restores all values to what they were at initial load (after registration and auto-loading)
function skill_config:resetToDefaults()
	utils.deepcopyInPlace(self.config, self.defaultConfig)

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
		cplus_plus_ex._subobjects.skill_state_tracker:updateEnabledSkills()
	end

	-- Note: Saving is handled by the caller (e.g., UI saveConfiguration())
	if cplus_plus_ex.PLUS_DEBUG then
		LOG("PLUS Ext: Reset configuration to defaults")
	end
end

-- Save configuration to modcontent.lua (pattern from time_traveler.lua)
function skill_config:saveConfiguration()
	if not modApi:isProfilePath() then return end

	if cplus_plus_ex.PLUS_DEBUG then
		LOG("PLUS Ext: Saving skill configuration to modcontent.lua")
	end

	sdlext.config(
		modApi:getCurrentProfilePath().."modcontent.lua",
		function(obj)
			obj.cplus_plus_ex = obj.cplus_plus_ex or {}
			-- reset the whole table on save? Maybe just copy over changes like on load?
			obj.cplus_plus_ex.skill_config = utils.deepcopy(skill_config.config)
		end
	)
end

-- Load configuration from modcontent.lua (pattern from time_traveler.lua)
-- Merges saved config into current config to preserve defaults for newly added skills
function skill_config:loadConfiguration()
	if not modApi:isProfilePath() then return end

	if cplus_plus_ex.PLUS_DEBUG then
		LOG("PLUS Ext: Loading skill configuration from modcontent.lua")
	end

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
				if savedConfig.autoAdjustWeights ~= nil then
					skill_config.config.autoAdjustWeights = savedConfig.autoAdjustWeights
				end

				-- Update sparse, saved as added tables
				-- We don't merge these since we only save exclusions not relationships
				if savedConfig.pilotSkillExclusions then
					skill_config.config.pilotSkillExclusions = utils.deepcopy(savedConfig.pilotSkillExclusions)
				end
				if savedConfig.pilotSkillInclusions then
					skill_config.config.pilotSkillInclusions = utils.deepcopy(savedConfig.pilotSkillInclusions)
				end
			if savedConfig.skillExclusions then
				skill_config.config.skillExclusions = utils.deepcopy(savedConfig.skillExclusions)
			end

				-- Merge skillConfigs to update existing skill but preserve new defaults
				if savedConfig.skillConfigs then
					for skillId, savedSkillConfig in pairs(savedConfig.skillConfigs) do
						-- Only update if skill was registered
						if skill_config.config.skillConfigs[skillId] then
							skill_config.config.skillConfigs[skillId] = utils.deepcopy(savedSkillConfig)
						else
							if cplus_plus_ex.PLUS_DEBUG then
								LOG("PLUS Ext: Ignoring saved config for removed skill: " .. skillId)
							end
						end
					end
				end

				skill_config:rebuildEnabledSkills()

				if cplus_plus_ex.PLUS_DEBUG then
					LOG("PLUS Ext: Loaded and merged skill configuration")
				end
			end
		end
	)
end

function skill_config:rebuildEnabledSkills()
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
		cplus_plus_ex._subobjects.skill_state_tracker:updateEnabledSkills()
	end
end

return skill_config
