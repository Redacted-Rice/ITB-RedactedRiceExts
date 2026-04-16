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

	self:_registerSlotRestrictionConstraintFunction()
	self:_registerReusabilityConstraintFunction()
	self:_registerPlusExclusionInclusionConstraintFunction()
	self:_registerSkillExclusionConstraintFunction()
	self:_registerGroupConstraintFunction()
	self:_registerPilotGroupExclusionConstraintFunction()
	self:_registerPilotGroupInclusionConstraintFunction()
	self:_registerSkillGroupExclusionConstraintFunction()
	self:_registerGroupGroupExclusionConstraintFunction()
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

-- This enforces slot restrictions (first only, second only, or either)
function skill_constraints:_registerSlotRestrictionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- Calculate current slot index from number of already selected skills
		local idx = #selectedSkills + 1

		local slotRestriction = skill_config_module.config.skillConfigs[candidateSkillId].slotRestriction

		if slotRestriction == cplus_plus_ex.SLOT_RESTRICTION.FIRST and idx ~= 1 then
			logger.logDebug(SUBMODULE, "Skill %s restricted to First slot, rejecting for slot %d", candidateSkillId, idx)
			return false
		elseif slotRestriction == cplus_plus_ex.SLOT_RESTRICTION.SECOND and idx ~= 2 then
			logger.logDebug(SUBMODULE, "Skill %s restricted to Second slot, rejecting for slot %d", candidateSkillId, idx)
			return false
		end

		return true
	end)
end

-- This enforces pilot exclusions (Vanilla blacklist API) and inclusion restrictions
function skill_constraints:_registerPlusExclusionInclusionConstraintFunction()
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
function skill_constraints:_registerReusabilityConstraintFunction()
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
					logger.logDebug(SUBMODULE, "Prevented %s skill %s for pilot %s (already selected)",
							reusability, candidateSkillId, pilotId)
					return false
				end
			end

			-- Additional check for per_run: ensure not used by ANY pilot
			if reusability == cplus_plus_ex.REUSABLILITY.PER_RUN then
				if skill_selection.usedSkillsPerRun[candidateSkillId] then
					logger.logDebug(SUBMODULE, "Prevented per_run skill %s for pilot %s (already used this run)",
							candidateSkillId, pilotId)
					return false
				end
			end
		end
		-- reusability == "reusable" always passes
		return true
	end)
end

-- This enforces skill to skill exclusions
function skill_constraints:_registerSkillExclusionConstraintFunction()
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

-- This enforces group constraints - only one skill from each group per pilot
function skill_constraints:_registerGroupConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- Check if group exclusions are enabled
		if not skill_config_module.config.enableGroupExclusions then
			return true
		end

		local pilotId = pilot:getIdStr()

		-- Check each group to see if candidate and any selected skill share a group
		for groupName, group in pairs(skill_config_module.groups) do
			-- Only enforce mutual exclusion if onlyOnePerPilot is enabled for this group
			if group.onlyOnePerPilot then
				local candidateInGroup = group.skillIds[candidateSkillId]

				if candidateInGroup then
					-- Candidate is in this group, check if any selected skill is also in it
					for _, selectedSkillId in ipairs(selectedSkills) do
						if group.skillIds[selectedSkillId] then
							logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (group '%s' conflict with already selected skill %s)",
									candidateSkillId, pilotId, groupName, selectedSkillId)
							return false
						end
					end
				end
			end
		end

		return true
	end)
end

-- This enforces pilot to group exclusions
function skill_constraints:_registerPilotGroupExclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Check if pilot is excluded from any groups containing this skill
		local excludedGroups = skill_config_module.config.pilotGroupExclusions[pilotId]
		if excludedGroups then
			-- Get all groups for this skill
			local skillGroups = skill_config_module:_getMergedGroupsForSkill(candidateSkillId)
			for _, groupName in ipairs(skillGroups) do
				if excludedGroups[groupName] then
					logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (excluded from group '%s')",
							candidateSkillId, pilotId, groupName)
					return false
				end
			end
		end

		return true
	end)
end

-- This enforces pilot to group inclusions
function skill_constraints:_registerPilotGroupInclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Check if pilot has any group inclusions
		local includedGroups = skill_config_module.config.pilotGroupInclusions[pilotId]
		if includedGroups and next(includedGroups) then
			-- Pilot has group inclusions, skill must be in at least one included group
			local skillGroups = skill_config_module:_getMergedGroupsForSkill(candidateSkillId)

			-- Check if skill is in any included group
			for _, groupName in ipairs(skillGroups) do
				if includedGroups[groupName] then
					return true
				end
			end

			-- Skill is not in any included group, prevent it
			logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (not in any included groups)",
					candidateSkillId, pilotId)
			return false
		end

		return true
	end)
end

-- Helper to check if a skill is excluded from any group in a set
-- Returns true if blocked, false if allowed
local function isSkillExcludedFromGroups(candidateSkillId, groupSet, exclusionTable, pilotId, logContext)
	local candidateExclusions = exclusionTable[candidateSkillId]
	if not candidateExclusions then
		return false
	end

	for _, groupName in ipairs(groupSet) do
		if candidateExclusions[groupName] then
			logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (%s excluded from group '%s')",
					candidateSkillId, pilotId, logContext, groupName)
			return true
		end
	end
	return false
end

-- Helper to check if candidate's groups are excluded by any selected skill's groups
-- Returns true if blocked, false if allowed
local function areGroupsExcluded(candidateGroups, selectedSkills, exclusionTable, candidateSkillId, pilotId, logPrefix)
	for _, candidateGroup in ipairs(candidateGroups) do
		local excludedGroups = exclusionTable[candidateGroup]

		if excludedGroups then
			for _, selectedSkillId in pairs(selectedSkills) do
				local selectedSkillGroups = skill_config_module:_getMergedGroupsForSkill(selectedSkillId)

				for _, selectedGroup in ipairs(selectedSkillGroups) do
					if excludedGroups[selectedGroup] then
						logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (%s group '%s' excluded from group '%s' of skill %s)",
								candidateSkillId, pilotId, logPrefix, candidateGroup, selectedGroup, selectedSkillId)
						return true
					end
				end
			end
		end
	end
	return false
end

-- This enforces skill to group exclusions
function skill_constraints:_registerSkillGroupExclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()
		local candidateGroups = skill_config_module:_getMergedGroupsForSkill(candidateSkillId)

		-- Check candidate's exclusions against selected skills' groups
		for _, selectedSkillId in pairs(selectedSkills) do
			local selectedSkillGroups = skill_config_module:_getMergedGroupsForSkill(selectedSkillId)
			if isSkillExcludedFromGroups(candidateSkillId, selectedSkillGroups,
					skill_config_module.config.skillGroupExclusions, pilotId, "skill") then
				return false
			end
		end

		-- Check reverse: selected skills' exclusions against candidate's groups
		for _, selectedSkillId in pairs(selectedSkills) do
			if isSkillExcludedFromGroups(selectedSkillId, candidateGroups,
					skill_config_module.config.skillGroupExclusions, pilotId, "selected skill") then
				return false
			end
		end

		return true
	end)
end

-- This enforces group to group exclusions
function skill_constraints:_registerGroupGroupExclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()
		local candidateGroups = skill_config_module:_getMergedGroupsForSkill(candidateSkillId)

		-- Check if candidate's groups are excluded by any selected skill's groups
		if areGroupsExcluded(candidateGroups, selectedSkills,
				skill_config_module.config.groupGroupExclusions, candidateSkillId, pilotId, "candidate") then
			return false
		end

		-- Check reverse: if any selected skill's group is excluded from candidate's groups
		for _, selectedSkillId in pairs(selectedSkills) do
			local selectedSkillGroups = skill_config_module:_getMergedGroupsForSkill(selectedSkillId)

			for _, selectedGroup in ipairs(selectedSkillGroups) do
				local excludedGroups = skill_config_module.config.groupGroupExclusions[selectedGroup]

				if excludedGroups then
					for _, candidateGroup in ipairs(candidateGroups) do
						if excludedGroups[candidateGroup] then
							logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (selected group '%s' of skill %s excluded from candidate group '%s')",
									candidateSkillId, pilotId, selectedGroup, selectedSkillId, candidateGroup)
							return false
						end
					end
				end
			end
		end

		return true
	end)
end

return skill_constraints
