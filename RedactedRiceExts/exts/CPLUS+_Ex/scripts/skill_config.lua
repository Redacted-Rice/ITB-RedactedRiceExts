-- Skill Configuration Module
-- Handles skill configuration, enabling/disabling, and weight adjustments
-- This is the core, runtime changeable data storage

local skill_config = {}

-- Reference to owner and other modules (set during init)
local owner = nil
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
	autoAdjustWeights = true,  -- Auto-adjust weights for dependent skills (default true)
	pilotSkillExclusions = {}, -- pilotId -> excluded skill ids (set-like table) - auto-loaded from pilot Blacklists
	pilotSkillInclusions = {}, -- pilotId -> included skill ids (set-like table)
	skillExclusions = {},  -- skillId -> excluded skill ids (set-like table) - skills that cannot be taken together
	skillDependencies = {},  -- skillId -> required skill ids (set-like table) - skills that require another skill to be selected
	skillConfigs = {}, -- skillId -> enabled, weight, reusability
}

-- Module state
skill_config.enabledSkills = {}  -- skillId -> {shortName, fullName, description, bonuses, skillType, reusability}
skill_config.enabledSkillsIds = {}  -- Array of skill ids enabled

-- Initialize the module with reference to owner
function skill_config.init(ownerRef)
	owner = ownerRef
	skill_registry = ownerRef._modules.skill_registry
	utils = ownerRef._modules.utils
end

-- Get allowed reusability options for a skill
function skill_config.getAllowedReusability(skillId)
	-- This is called by register before the skills are registered so default to all allowed
	local minReusability = skill_registry.registeredSkills.reusability or owner.REUSABLILITY.REUSABLE
	local allowed = {}

	for val = minReusability, owner.REUSABLILITY.PER_RUN do
		allowed[val] = true
	end
	return allowed
end

-- Sets the configs for a skill and updates enabled states
function skill_config.setSkillConfig(skillId, config)
	local curr_config = skill_config.config.skillConfigs[skillId] or skill_config.SkillConfig.new()
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
	end

	if config.reusability then
		local normalizeReuse = utils.normalizeReusabilityToInt(config.reusability, owner.REUSABLILITY)
		if not normalizeReuse then
			LOG("PLUS Ext: Error: Invalid skill reusability passed: " .. config.reusability)
			return
		elseif not skill_config.getAllowedReusability(skillId)[normalizeReuse] then
			LOG("PLUS Ext: Error: Unallowed skill reusability passed: " .. config.reusability .. "(normalized to ".. normalizeReuse ..")")
			return
		end
		new_config.reusability = config.reusability
	end

	-- If we reached here, its a good config. Apply it
	skill_config.config.skillConfigs[skillId] = new_config
	if new_config.enabled and not curr_config.enabled then
		skill_config._enableSkill_internal(skillId)
	elseif not new_config.enabled and curr_config.enabled then
		skill_config._disableSkill_internal(skillId)
	end

	if owner.PLUS_DEBUG then LOG("PLUS Ext: Set config for skill " .. skillId) end
end

function skill_config.enableSkill(skillId)
	skill_config.setSkillConfig(skillId, {enabled = true})
end

function skill_config.disableSkill(skillId)
	skill_config.setSkillConfig(skillId, {enabled = false})
end

-- Enable a skill. Should not be called directly
function skill_config._enableSkill_internal(id)
	local category = skill_registry.registeredSkillsIds[id]
	local skill = skill_registry.registeredSkills[category][id]

	-- Check if already enabled
	if skill_config.enabledSkills[id] ~= nil then
		LOG("PLUS Ext warning: Skill " .. id .. " already enabled, skipping")
	else
		-- Add the skill to enabled list. We don't care at this point if its inclusion type or not
		skill_config.enabledSkills[id] = skill
		table.insert(skill_config.enabledSkillsIds, id)

		if owner.PLUS_DEBUG then
			local skillType = skill.skillType
			local reusability = skill.reusability
			if owner.PLUS_DEBUG then LOG("PLUS Ext: Enabled skill: " .. id .. " (type: " .. skillType .. ", reusability: " .. reusability .. ")") end
		end
	end
	if owner.PLUS_DEBUG then LOG("PLUS Ext: Skill " .. id .. " enabled") end
end

-- Disable a skill. Should not be called directly
function skill_config._disableSkill_internal(id)
	if skill_config.enabledSkills[id] == nil then
		LOG("PLUS Ext: Warning: Skill " .. id .. " already disabled, skipping")
	else
		skill_config.enabledSkills[id] = nil
		for idx, skillId in ipairs(skill_config.enabledSkillsIds) do
			if skillId == id then
				table.remove(skill_config.enabledSkillsIds, idx)
				if owner.PLUS_DEBUG then LOG("PLUS Ext: Disabled skill: " .. id .. " (idx: " .. idx .. ")") end
				break
			end
		end
	end
	if owner.PLUS_DEBUG then LOG("PLUS Ext: Skill " .. id .. " disabled") end
end

-- Removes a dependency between skills
function skill_config.removeSkillDependency(skillId, requiredSkillId)
	if skill_config.config.skillDependencies[skillId] then
		skill_config.config.skillDependencies[skillId][requiredSkillId] = nil

		-- If no more dependencies, remove the entry entirely
		local hasAny = false
		for _, _ in pairs(skill_config.config.skillDependencies[skillId]) do
			hasAny = true
			break
		end

		if not hasAny then
			skill_config.config.skillDependencies[skillId] = nil
		end

		if owner.PLUS_DEBUG then
			LOG("PLUS Ext: Removed dependency: " .. skillId .. " no longer requires " .. requiredSkillId)
		end

		return true
	end

	return false
end

-- Auto-adjusts skill weights based on dependencies
-- Only runs if autoAdjustWeights is true
-- Dependent skills get weight = (numEnabledSkills - 2) / numDependencies
-- Dependency skills get weight += 0.5 per dependent
function skill_config.setAdjustedWeightsConfigs()
	-- first just copy all the set weights to adj weights for all skills
	for skillId, _ in pairs(skill_registry.registeredSkillsIds) do
		local config = skill_config.config.skillConfigs[skillId]
		config.adj_weight = config.set_weight
	end

	if not skill_config.config.autoAdjustWeights then
		if owner.PLUS_DEBUG then
			LOG("PLUS Ext: Auto-adjust disabled, skipping weight adjustment")
		end
		return
	end

	local dependencyUsages = {}
	local numSkills = #skill_config.enabledSkillsIds

	-- Process all dependent skills
	for dependentSkillId, dependencies in pairs(skill_config.config.skillDependencies) do
		-- Only adjust if the skill is enabled
		if skill_config.enabledSkills[dependentSkillId] then
			local config = skill_config.config.skillConfigs[dependentSkillId]

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
			if owner.PLUS_DEBUG then
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
		local config = skill_config.config.skillConfigs[skillId]
		config.adj_weight = config.set_weight + (dependencyCount * 0.5)
		if owner.PLUS_DEBUG then
			LOG("PLUS Ext: Increased dependency skill " .. skillId .. " weight to " .. config.adj_weight ..
					" (base=" .. config.set_weight .. ", usedBy=" .. dependencyCount .. ")")
		end
	end
end

-- Resets configuration to default state
-- Restores all values to what they were at initial load (after registration and auto-loading)
function skill_config.resetToDefaults()
	skill_config.config = utils.deepcopy(owner.defaultConfig)
	-- TODO: Update internal state vars as well
	-- TODO: save? Or is this handled elsewhere?
end

return skill_config
