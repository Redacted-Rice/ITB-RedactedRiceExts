-- Skill Constraints Module
-- Handles constraint definitions and registration which evaluate and modify skill assignment
-- These are not runtime modifiable but always active even if "empty". The actual values
-- and exclusions used by the constraints are handled in the registry config module

local skill_constraints = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "SkillConstraints", cplus_plus_ex.DEBUG.CONSTRAINTS and cplus_plus_ex.DEBUG.ENABLED)

-- Local references to other submodules (set during init)
local skill_config_module = nil
local skill_selection = nil
local utils = nil

-- Module state
skill_constraints.constraintFunctions = {}  -- Array of function(pilot, selectedSkills, candidateSkillId) -> boolean

-- Initialize the module
function skill_constraints:init()
	skill_config_module = cplus_plus_ex._subobjects.skill_config
	skill_selection = cplus_plus_ex._subobjects.skill_selection
	utils = cplus_plus_ex._subobjects.utils

	self:registerReusabilityConstraintFunction()
	self:registerPlusExclusionInclusionConstraintFunction()
	self:registerSkillExclusionConstraintFunction()
	return self
end

-- Checks if a skill can be assigned to the given pilot
-- using all registered constraint functions
-- Returns true if all constraints pass, false otherwise
function skill_constraints:checkSkillConstraints(pilot, selectedSkills, candidateSkillId)
	-- Check all constraint functions
	for _, constraintFn in ipairs(self.constraintFunctions) do
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
function skill_constraints:registerConstraintFunction(constraintFn)
	table.insert(self.constraintFunctions, constraintFn)
	logger.logDebug(SUBMODULE, "Registered constraint function")
end

-- This enforces pilot exclusions (Vanilla blacklist API) and inclusion restrictions
function skill_constraints:registerPlusExclusionInclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Get the skill object to check its type
		local skill = skill_config_module.enabledSkills[candidateSkillId]

		if skill == nil then
			logger.logWarn(SUBMODULE, "Skill " .. candidateSkillId .. " not found in enabled skills")
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
			if not allowed then
				logger.logDebug(SUBMODULE, "Prevented inclusion skill %s for pilot %s", candidateSkillId, pilotId)
			end
		return allowed
		else
			-- Check for an exclusion
			local hasExclusion = skill_config_module.config.pilotSkillExclusions[pilotId] and skill_config_module.config.pilotSkillExclusions[pilotId][candidateSkillId]
			if hasExclusion then
				logger.logDebug(SUBMODULE, "Prevented exclusion skill %s for pilot %s", candidateSkillId, pilotId)
			end
			return not hasExclusion
		end
	end)
end

-- This enforces per_pilot and per_run skill restrictions
function skill_constraints:registerReusabilityConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()
		local skill = skill_config_module.enabledSkills[candidateSkillId]

		local reusability = skill_config_module.config.skillConfigs[candidateSkillId].reusability
		-- If we do not allow reusable skills, we need to change it to PER_PILOT
		if (not skill_config_module.config.allowReusableSkills) and reusability == cplus_plus_ex.REUSABLILITY.REUSABLE then
			reusability = cplus_plus_ex.REUSABLILITY.PER_PILOT
		end

		if reusability == cplus_plus_ex.REUSABLILITY.PER_PILOT or reusability == cplus_plus_ex.REUSABLILITY.PER_RUN then
			-- Check if this pilot already has this skill in their selected slots
			-- This applies to both per_pilot and per_run (per_run is stricter and includes this check)
			for _, skillId in pairs(selectedSkills) do
				if skillId == candidateSkillId then
					if cplus_plus_ex.PLUS_DEBUG then
						logger.logDebug(SUBMODULE, "Prevented %s skill %s for pilot %s (already selected)",
								reusability, candidateSkillId, pilotId)
					end
					return false
				end
			end

			-- Additional check for per_run: ensure not used by ANY pilot
			if reusability == cplus_plus_ex.REUSABLILITY.PER_RUN then
				if skill_selection.usedSkillsPerRun[candidateSkillId] then
					if cplus_plus_ex.PLUS_DEBUG then
						logger.logDebug(SUBMODULE, "Prevented per_run skill %s for pilot %s (already used this run)",
								candidateSkillId, pilotId)
					end
					return false
				end
			end
		end
		-- reusability == "reusable" always passes
		return true
	end)
end

-- This enforces skill to skill exclusions
function skill_constraints:registerSkillExclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- pilot id for logging
		local pilotId = pilot:getIdStr()

		-- Check if candidate is excluded by any already selected skill
		if skill_config_module.config.skillExclusions[candidateSkillId] then
			for _, selectedSkillId in pairs(selectedSkills) do
				if skill_config_module.config.skillExclusions[candidateSkillId][selectedSkillId] then
					logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (mutually exclusive with already selected skill %s)",
							candidateSkillId, pilotId, selectedSkillId)
					return false
				end
			end
		end

		return true
	end)
end

return skill_constraints
