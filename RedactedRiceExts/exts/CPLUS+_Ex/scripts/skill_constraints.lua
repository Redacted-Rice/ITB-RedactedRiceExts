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
skill_constraints.constraintFunctions = {}  -- Array of "any" constraint functions that apply to all skills
skill_constraints.inclusionConstraintFunctions = {}  -- Array of inclusion constraint functions that apply to inclusion skills
skill_constraints.exclusionConstraintFunctions = {}  -- Array of exclusion constraint functions that apply to default/exclusion skills

-- Initialize the module
function skill_constraints:init()
	skill_config_module = cplus_plus_ex._subobjects.skill_config
	skill_selection = cplus_plus_ex._subobjects.skill_selection
	utils = cplus_plus_ex._subobjects.utils

	-- Register any type constraints that apply to all skills
	self:_registerSlotRestrictionConstraintFunction()
	self:_registerReusabilityConstraintFunction()
	self:_registerSkillExclusionConstraintFunction()
	self:_registerGroupExclusionConstraintFunction()

	-- Register inclusion constraints that only apply to inclusion skills
	self:_registerPilotInclusionConstraintFunction()
	self:_registerSquadInclusionConstraintFunction()

	-- Register exclusion constraints that only apply to default/exclusion skills
	self:_registerPilotExclusionConstraintFunction()
	self:_registerSquadExclusionConstraintFunction()

	return self
end

-- Checks if a skill can be assigned to the given pilot
-- using all registered constraint functions
-- Returns true if all constraints pass, false otherwise
-- slotIdx: optional explicit skill slot (1 or 2). When omitted, inferred as #selectedSkills + 1
function skill_constraints:checkSkillConstraints(pilot, selectedSkills, candidateSkillId, slotIdx)
	-- Get the skill to check if it's an inclusion skill
	-- If skill doesn't exist, treat as non-inclusion (default/exclusion behavior)
	local skill = skill_config_module.enabledSkills[candidateSkillId]
	if not skill then
		logger.logWarn(SUBMODULE, "Skill %s not found in enabled skills", candidateSkillId)
		return false
	end

	-- Stash slot on the call for constraint functions that need it
	self._currentSlotIdx = slotIdx or (#selectedSkills + 1)

	-- If its an inclusion, firt see if its even allowed
	if utils.isInclusionSkill(skill.skillType) then
		-- At least one inclusion constraint must pass to contiune
		local hasInclusionMatch = false
		for _, constraintFn in ipairs(self.inclusionConstraintFunctions) do
			if constraintFn(pilot, selectedSkills, candidateSkillId) then
				hasInclusionMatch = true
				break  -- Found at least one match, can stop checking
			end
		end
		-- If no inclusion constraints passed, reject immediately
		if not hasInclusionMatch then
			self._currentSlotIdx = nil
			return false
		end
	end

	-- Run the constraints applicable to all skills
	-- All must pass to be allowed
	for _, constraintFn in ipairs(self.constraintFunctions) do
		if not constraintFn(pilot, selectedSkills, candidateSkillId) then
			self._currentSlotIdx = nil
			return false
		end
	end

	-- If its an exclusion, run the constraints applicable to exclusions
	if utils.isExclusionSkill(skill.skillType) then
		-- All must pass to be allowed
		for _, constraintFn in ipairs(self.exclusionConstraintFunctions) do
			if not constraintFn(pilot, selectedSkills, candidateSkillId) then
				self._currentSlotIdx = nil
				return false
			end
		end
	end

	-- Made it all the way through - we are good!
	self._currentSlotIdx = nil
	return true
end

-- Registers a constraint function for skill assignment
-- constraintType: Optional, can be:
--   - "inclusion": Only runs for inclusion skills, OR logic (at least one must pass)
--   - "exclusion": Exclusion-type checks, runs for exclusion skills, AND logic (all must pass)
--   - "any" or nil: General checks, runs for ALL skills, AND logic (all must pass)
function skill_constraints:registerConstraintFunction(constraintFn, constraintType)
	if constraintType == "inclusion" then
		table.insert(self.inclusionConstraintFunctions, constraintFn)
		logger.logDebug(SUBMODULE, "Registered inclusion constraint function")
	elseif constraintType == "exclusion" then
		table.insert(self.exclusionConstraintFunctions, constraintFn)
		logger.logDebug(SUBMODULE, "Registered exclusion constraint function")
	else
		-- Default to "any" - runs for all skills
		table.insert(self.constraintFunctions, constraintFn)
		logger.logDebug(SUBMODULE, "Registered 'any' constraint function")
	end
end

-- This enforces slot restrictions (first only, second only, or either)
function skill_constraints:_registerSlotRestrictionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- Prefer explicit slot from checkSkillConstraints and fall back to inference
		local idx = skill_constraints._currentSlotIdx or (#selectedSkills + 1)

		local slotRestriction = skill_config_module.config.skillConfigs[candidateSkillId].slotRestriction

		if slotRestriction == cplus_plus_ex.SLOT_RESTRICTION.FIRST and idx ~= 1 then
			logger.logDebug(SUBMODULE, "Skill %s restricted to First slot, rejecting for slot %d", candidateSkillId, idx)
			return false
		elseif slotRestriction == cplus_plus_ex.SLOT_RESTRICTION.SECOND and idx ~= 2 then
			logger.logDebug(SUBMODULE, "Skill %s restricted to Second slot, rejecting for slot %d", candidateSkillId, idx)
			return false
		end

		return true
	end, "any")
end

-- This enforces pilot inclusion restrictions
-- Only allows specific pilots to receive certain inclusion skills
function skill_constraints:_registerPilotInclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Check pilot inclusion list
		local pilotList = skill_config_module.config.pilotSkillInclusions[pilotId]
		local isIncluded = pilotList and pilotList[candidateSkillId]

		if isIncluded then
			logger.logDebug(SUBMODULE, "Pilot inclusion matched for skill %s and pilot %s", candidateSkillId, pilotId)
		end
		return isIncluded == true
	end, "inclusion")
end

-- This enforces squad inclusion restrictions
-- Only allows pilots in specific squads to receive certain inclusion skills
function skill_constraints:_registerSquadInclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Get squad ID
		local squadId = GAME and GAME.additionalSquadData and GAME.additionalSquadData.squad
		if not squadId then
			return false
		end

		-- Check squad inclusion list
		local squadList = skill_config_module.config.squadSkillInclusions[squadId]
		local isIncluded = squadList and squadList[candidateSkillId]

		if isIncluded then
			logger.logDebug(SUBMODULE, "Squad inclusion matched for skill %s and squad %s", candidateSkillId, squadId)
		end
		return isIncluded == true
	end, "inclusion")
end

-- This enforces pilot exclusions (vanilla blacklist)
-- Prevents specific pilots from receiving certain skills
function skill_constraints:_registerPilotExclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Check for pilot exclusion
		local hasExclusion = skill_config_module.config.pilotSkillExclusions[pilotId]
			and skill_config_module.config.pilotSkillExclusions[pilotId][candidateSkillId]

		if hasExclusion then
			logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (pilot excluded)", candidateSkillId, pilotId)
		end

		return not hasExclusion
	end, "exclusion")
end

-- This enforces squad exclusions
-- Prevents all pilots in certain squads from receiving certain skills
function skill_constraints:_registerSquadExclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Get squad ID
		local squadId = GAME and GAME.additionalSquadData and GAME.additionalSquadData.squad

		-- Check for squad exclusion
		local hasExclusion = squadId and
			skill_config_module.config.squadSkillExclusions[squadId] and
			skill_config_module.config.squadSkillExclusions[squadId][candidateSkillId]

		if hasExclusion then
			logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (squad %s excluded)", candidateSkillId, pilotId, squadId)
		end

		return not hasExclusion
	end, "exclusion")
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
	end, "any")
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
	end, "any")
end

-- This enforces group exclusions - only one skill from each group per pilot
function skill_constraints:_registerGroupExclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- Skip if group exclusions are disabled
		if not skill_config_module.config.enableGroupExclusions then
			return true
		end

		local pilotId = pilot:getIdStr()

		-- Find which groups the candidate skill belongs to
		for groupName, group in pairs(skill_config_module.groups) do
			-- Skip if group is disabled
			if group.enabled and group.skillIds[candidateSkillId] then
				-- Check if any already selected skill is in the same group
				for _, selectedSkillId in pairs(selectedSkills) do
					if group.skillIds[selectedSkillId] then
						logger.logDebug(SUBMODULE, "Prevented skill %s for pilot %s (group '%s' already has skill %s)",
								candidateSkillId, pilotId, groupName, selectedSkillId)
						return false
					end
				end
			end
		end
		return true
	end, "any")
end

return skill_constraints
