-- Skill Constraints Module
-- Handles constraint definitions and registration which evaluate and modify skill assignment
-- These are not run time modifyiable but always active even if "empty". The actual values
-- and exclusions used by the constraints are handled in the registry config module

local skill_constraints = {}

-- Reference to owner and other modules (set during init)
local owner = nil
local skill_config_module = nil
local skill_selection = nil
local utils = nil

-- Module state
skill_constraints.constraintFunctions = {}  -- Array of function(pilot, selectedSkills, candidateSkillId) -> boolean

-- Initialize the module with reference to owner
function skill_constraints.init(ownerRef)
	owner = ownerRef
	skill_config_module = ownerRef._modules.skill_config
	skill_selection = ownerRef._modules.skill_selection
	utils = ownerRef._modules.utils

	skill_constraints.registerReusabilityConstraintFunction()
	skill_constraints.registerPlusExclusionInclusionConstraintFunction()
	skill_constraints.registerSkillExclusionDependencyConstraintFunction()
end

-- Checks if a skill can be assigned to the given pilot
-- using all registered constraint functions
-- Returns true if all constraints pass, false otherwise
function skill_constraints.checkSkillConstraints(pilot, selectedSkills, candidateSkillId)
	-- Check all constraint functions
	for _, constraintFn in ipairs(skill_constraints.constraintFunctions) do
		if not constraintFn(pilot, selectedSkills, candidateSkillId) then
			return false
		end
	end
	return true
end

-- Registers a constraint function for skill assignment
-- These functions take pilot, selectedSkills, and candidateSkillId and return true if the candidate skill can be assigned to the pilot
--   pilot - The memhack pilot struct
--   selectedSkills - Array like table of skill IDs that have already been selected for this pilot
--   candidateSkillId - The skill ID being considered for assignment
-- The default pilot inclusion/exclusion and duplicate prevention use this same function. These can be
-- used as examples for using constraint functions
function skill_constraints.registerConstraintFunction(constraintFn)
	table.insert(skill_constraints.constraintFunctions, constraintFn)
	if owner.PLUS_DEBUG then
		LOG("PLUS Ext: Registered constraint function")
	end
end

-- This enforces pilot exclusions (Vanilla blacklist API) and inclusion restrictions
function skill_constraints.registerPlusExclusionInclusionConstraintFunction()
	skill_constraints.registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Get the skill object to check its type
		local skill = skill_config_module.enabledSkills[candidateSkillId]

		if skill == nil then
			LOG("PLUS Ext warning: Skill " .. candidateSkillId .. " not found in enabled skills")
			return false
		end

		-- For inclusion skills check if pilot is in inclusion list
		-- For default skills check if pilot is NOT in exclusion list (must be absent)
		local isInclusionSkill = skill.skillType == "inclusion"

		if isInclusionSkill then
			-- Check inclusion list
			local pilotList = skill_config_module.config.pilotSkillInclusions[pilotId]
			local skillInList = pilotList and pilotList[candidateSkillId]
			local allowed = skillInList == true
			if not allowed and owner.PLUS_DEBUG then
				LOG("PLUS Ext: Prevented inclusion skill " .. candidateSkillId .. " for pilot " .. pilotId)
			end
			return allowed
		else
			-- Check for an exclusion
			local hasExclusion = skill_config_module.config.pilotSkillExclusions[pilotId] and skill_config_module.config.pilotSkillExclusions[pilotId][candidateSkillId]
			if hasExclusion and owner.PLUS_DEBUG then
				LOG("PLUS Ext: Prevented exclusion skill " .. candidateSkillId .. " for pilot " .. pilotId)
			end
			return not hasExclusion
		end
	end)
end

-- This enforces per_pilot and per_run skill restrictions
function skill_constraints.registerReusabilityConstraintFunction()
	skill_constraints.registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()
		local skill = skill_config_module.enabledSkills[candidateSkillId]

		local reusability = skill_config_module.config.skillConfigs[candidateSkillId].reusability
		-- If we do not allow reusable skills, we need to change it to PER_PILOT
		if (not skill_config_module.config.allowReusableSkills) and reusability == owner.REUSABLILITY.REUSABLE then
			reusability = owner.REUSABLILITY.PER_PILOT
		end

		if reusability == owner.REUSABLILITY.PER_PILOT or reusability == owner.REUSABLILITY.PER_RUN then
			-- Check if this pilot already has this skill in their selected slots
			-- This applies to both per_pilot and per_run (per_run is stricter and includes this check)
			for _, skillId in ipairs(selectedSkills) do
				if skillId == candidateSkillId then
					if owner.PLUS_DEBUG then
						LOG("PLUS Ext: Prevented " .. reusability .. " skill " .. candidateSkillId .. " for pilot " .. pilotId .. " (already selected)")
					end
					return false
				end
			end

			-- Additional check for per_run: ensure not used by ANY pilot
			if reusability == owner.REUSABLILITY.PER_RUN then
				if skill_selection.usedSkillsPerRun[candidateSkillId] then
					if owner.PLUS_DEBUG then
						LOG("PLUS Ext: Prevented per_run skill " .. candidateSkillId .. " for pilot " .. pilotId .. " (already used this run)")
					end
					return false
				end
			end
		end
		-- reusability == "reusable" always passes
		return true
	end)
end

-- This enforces skill to skill exclusions and depencencies
function skill_constraints.registerSkillExclusionDependencyConstraintFunction()
	skill_constraints.registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- pilot id for logging
		local pilotId = pilot:getIdStr()

		-- Check if candidate is excluded by any already selected skill
		if skill_config_module.config.skillExclusions[candidateSkillId] then
			for _, selectedSkillId in ipairs(selectedSkills) do
				if skill_config_module.config.skillExclusions[candidateSkillId][selectedSkillId] then
					if owner.PLUS_DEBUG then
						LOG("PLUS Ext: Prevented skill " .. candidateSkillId .. " for pilot " .. pilotId ..
							" (mutually exclusive with already selected skill " .. selectedSkillId .. ")")
					end
					return false
				end
			end
		end

		-- If candidate has dependencies at least one must be in selectedSkills already
		if skill_config_module.config.skillDependencies[candidateSkillId] then
			local hasDependency = false

			for requiredSkillId, _ in pairs(skill_config_module.config.skillDependencies[candidateSkillId]) do
				for _, selectedSkillId in ipairs(selectedSkills) do
					if selectedSkillId == requiredSkillId then
						hasDependency = true
						break
					end
				end
				if hasDependency then
					break
				end
			end

			if not hasDependency then
				if owner.PLUS_DEBUG then
					LOG("PLUS Ext: Prevented skill " .. candidateSkillId .. " for pilot " .. pilotId ..
						" (requires one of: " .. utils.setToString(skill_config_module.config.skillDependencies[candidateSkillId]) .. ")")
				end
				return false
			end
		end

		return true
	end)
end

return skill_constraints
