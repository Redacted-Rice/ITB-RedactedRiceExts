-- Skill Registration Module
-- Handles registering skills, exclusions, inclusions, and dependencies
-- Registered skills will be default enabled and the registered inclusions,
-- exclusions, and dependencies are default values. These can be changed
-- run time and the values used are stored in skill_config module

local skill_registry = {}

-- Reference to owner (set during init)
local owner = nil
local skill_config = nil
local utils = nil

-- Module state
skill_registry.registeredSkills = {}  -- skillId -> {id, category, shortName, fullName, description, bonuses, skillType, reusability}

-- Initialize the module with reference to owner
function skill_registry.init(ownerRef)
	owner = ownerRef
	skill_config = ownerRef._modules.skill_config
	utils = ownerRef._modules.utils

	skill_registry.registerVanilla()
end

-- saveVal is optional and must be between 0-13 (vanilla range). This will be used so if
-- the extension fails to load or is uninstalled, a suitable vanilla skill will be used
-- instead. If not provided or out of range, a random vanilla value will be used.
-- The save data in vanilla only supports 0-13. Anything out of range is clamped to this range
-- reusability is optional defines how the skill can be reused. Defaults to per_pilot to align with vanilla
--   REUSABLE (1) - can be assigned to any pilot any number of times
--   PER_PILOT (2) - a pilot can only have this skill once - vanilla behavior
--   PER_RUN (3) - can only be assigned once per run across all pilots. Would be for very strong skills or skills that
--			affect the game state in a one time only way
-- weight optional default weight for the skill
function skill_registry.registerSkill(category, idOrTable, shortName, fullName, description, bonuses, skillType, saveVal, reusability, weight)
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
	if skill_registry.registeredSkills[id] ~= nil then
		utils.logAndShowErrorPopup("PLUS Ext error: Skill ID '" .. id .. "' in category '" .. category ..
				"' conflicts with existing skill from category '" .. skill_registry.registeredSkills[id].category .. "'.")
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
	reusability = utils.normalizeReusabilityToInt(reusability)
	if not reusability then
		LOG("PLUS Ext: Warning: Skill '" .. id .. "' has invalid reusability '" .. tostring(reusability) ..
				"' 1-3 (corresponding to enum values in REUSABLILITY. Defaulting to PER_PILOT")
		reusability = owner.DEFAULT_REUSABILITY
	end

	-- Register the skill with its type and reusability included in the skill data
	skill_registry.registeredSkills[id] = { id = id, category = category, shortName = shortName, fullName = fullName, description = description,
			bonuses = bonuses or {},
			skillType = skillType or "default",
			saveVal = saveVal, reusability = reusability,
	}

	-- add a config value
	skill_config.setSkillConfig(id, {enabled = true, reusability = reusability, set_weight = weight})
end

-- Registers all vanilla skills
function skill_registry.registerVanilla()
	-- Register all vanilla skills
	for _, skill in ipairs(owner.VANILLA_SKILLS) do
		skill_registry.registerSkill("vanilla", skill)
	end
end

-- Helper function to register pilot-skill relationships
local function registerPilotSkillRelationship(targetTable, pilotId, skillIds, relationshipType)
	if targetTable[pilotId] == nil then
		targetTable[pilotId] = {}
	end

	for _, skillId in ipairs(skillIds) do
		-- store with skillId as key so it acts like a set
		targetTable[pilotId][skillId] = true

		if owner.PLUS_DEBUG then
			local action = relationshipType == "exclusion" and "cannot have" or "can have"
			LOG("PLUS Ext: Registered " .. relationshipType .. " - Pilot " .. pilotId .. " " .. action .. " skill " .. skillId)
		end
	end
end

-- Registers pilot skill exclusions
-- Takes pilot id and list of skill ids to exclude
function skill_registry.registerPilotSkillExclusions(pilotId, skillIds)
	registerPilotSkillRelationship(skill_config.config.pilotSkillExclusions, pilotId, skillIds, "exclusion")
end

-- Registers pilot skill inclusions
-- Takes pilot id and list of skill ids to include
-- This is only needed for specific inclusion skills. Any default
-- enabled, non-excluded skill will be available as well as any added here
function skill_registry.registerPilotSkillInclusions(pilotId, skillIds)
	registerPilotSkillRelationship(skill_config.config.pilotSkillInclusions, pilotId, skillIds, "inclusion")
end

-- Registers a skill to skill exclusion
-- Takes two skill ids that cannot be selected for the same pilot
function skill_registry.registerSkillExclusion(skillId, excludedSkillId)
	if skill_config.config.skillExclusions[skillId] == nil then
		skill_config.config.skillExclusions[skillId] = {}
	end
	if skill_config.config.skillExclusions[excludedSkillId] == nil then
		skill_config.config.skillExclusions[excludedSkillId] = {}
	end

	-- Register exclusion in both directions
	skill_config.config.skillExclusions[skillId][excludedSkillId] = true
	skill_config.config.skillExclusions[excludedSkillId][skillId] = true

	if owner.PLUS_DEBUG then
		LOG("PLUS Ext: Registered exclusion: " .. skillId .. " <-> " .. excludedSkillId)
	end
end

-- Registers a skill dependency
-- Takes a skill id and a required skill id
-- The dependent skill can only be selected if the required skill is already selected
-- Call multiple times to add multiple dependencies that would work - only one of the
-- added need to be assigned to satisfy the dependency
-- Note: Chain dependencies are not allowed - a dependent skill cannot depend on another dependent skill
function skill_registry.registerSkillDependency(skillId, requiredSkillId)
	-- Prevent chain dependencies - requiredSkillId cannot itself be a dependent skill
	if skill_config.config.skillDependencies[requiredSkillId] ~= nil then
		LOG("PLUS Ext error: Cannot register dependency: " .. skillId .. " -> " .. requiredSkillId ..
				". Chain dependencies are not allowed. The required skill '" .. requiredSkillId ..
				"' is already a dependent skill.")
		return false
	end

	if skill_config.config.skillDependencies[skillId] == nil then
		skill_config.config.skillDependencies[skillId] = {}
	end

	skill_config.config.skillDependencies[skillId][requiredSkillId] = true

	if owner.PLUS_DEBUG then
		LOG("PLUS Ext: Registered dependency: " .. skillId .. " requires " .. requiredSkillId)
	end

	return true
end

-- Scans global for all pilot definitions and registers their Blacklist exclusions
-- This maintains the vanilla method of defining pilot exclusions to be compatible
-- without any specific changes for using this extension
function skill_registry.readPilotExclusionsFromGlobal()
	if _G.Pilot == nil then
		if owner.PLUS_DEBUG then
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
				skill_registry.registerPilotSkillExclusions(key, value.Blacklist)
				exclusionCount = exclusionCount + 1

				if owner.PLUS_DEBUG then
					LOG("PLUS Ext: Found " .. #value.Blacklist .. " exclusion(s) for pilot " .. key)
				end
			end
		end
	end

	if owner.PLUS_DEBUG then
		LOG("PLUS Ext: Scanned " .. pilotCount .. " pilot(s), registered exclusions for " .. exclusionCount .. " pilot(s)")
	end
end

return skill_registry
