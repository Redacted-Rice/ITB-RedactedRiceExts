-- Pilot Overrides for Virtual Skills Support
-- This module overrides memhack Pilot functions to support virtual skills (slots 3+)
-- transparently through the standard memhack API

local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "Pilot Overrides", cplus_plus_ex.DEBUG.ENABLED)

local pilot_overrides = {}

-- Store original functions
local original_getLvlUpSkill = nil
local original_setLvlUpSkill = nil
local original_combineBonuses = nil
local original_GetSkillInfo = nil  -- Store the truly original GetSkillInfo
local getSkillInfoOverrideApplied = false  -- Track if we've already applied the override

-- Reference to skill_state_tracker
local skill_state_tracker = cplus_plus_ex._subobjects.skill_state_tracker

--- Override Pilot:getLvlUpSkill to support virtual skills (indexes 3+)
--- For indexes 1-2: delegates to original memhack implementation
--- For indexes 3+: returns virtual skill objects from CPLUS+ tracking
function pilot_overrides:_overrideGetLvlUpSkill()
	local Pilot = memhack.structs.Pilot

	-- Store original if not already stored
	if not original_getLvlUpSkill then
		original_getLvlUpSkill = Pilot.getLvlUpSkill
	end

	Pilot.getLvlUpSkill = function(self, index)
		-- Validate index
		if not index or type(index) ~= "number" or index < 1 then
			logger.logError(SUBMODULE, "Invalid skill index: %s (must be positive number)", tostring(index))
			return nil
		end

		-- Real skills (1-2): use original implementation
		if index <= cplus_plus_ex.MAX_SKILL_SLOTS then
			return original_getLvlUpSkill(self, index)
		end

		-- Virtual skills (3+): get from CPLUS+ tracking
		local pilotId = self:getIdStr()
		if not pilotId then
			logger.logError(SUBMODULE, "Cannot get skill for pilot with no ID")
			return nil
		end

		local virtualSkills = skill_state_tracker:getVirtualSkillObjects(pilotId)
		local virtualIndex = index - cplus_plus_ex.MAX_SKILL_SLOTS

		if virtualIndex > #virtualSkills then
			logger.logDebug(SUBMODULE, "Pilot %s does not have skill at index %d (has %d virtual skills)",
				pilotId, index, #virtualSkills)
			return nil
		end

		return virtualSkills[virtualIndex]
	end

	logger.logInfo(SUBMODULE, "Overridden Pilot:getLvlUpSkill to support virtual skills")
end

-------------------- Override: setLvlUpSkill --------------------

--- Override Pilot:setLvlUpSkill to support virtual skills (indexes 3+)
--- For indexes 1-2: delegates to original memhack implementation
--- For indexes 3+: modifies virtual skill objects from CPLUS+ tracking
function pilot_overrides:_overrideSetLvlUpSkill()
	local Pilot = memhack.structs.Pilot

	-- Store original if not already stored
	if not original_setLvlUpSkill then
		original_setLvlUpSkill = Pilot.setLvlUpSkill
	end

	Pilot.setLvlUpSkill = function(self, index, structOrNewVals)
		-- Validate index
		if not index or type(index) ~= "number" or index < 1 then
			logger.logError(SUBMODULE, "Invalid skill index: %s (must be positive number)", tostring(index))
			return
		end

		-- Real skills (1-2): use original implementation
		if index <= cplus_plus_ex.MAX_SKILL_SLOTS then
			original_setLvlUpSkill(self, index, structOrNewVals)
			return
		end

		-- Virtual skills (3+): modify CPLUS+ tracked objects
		local pilotId = self:getIdStr()
		if not pilotId then
			logger.logError(SUBMODULE, "Cannot set skill for pilot with no ID")
			return
		end

		local virtualSkills = skill_state_tracker:getVirtualSkillObjects(pilotId)
		local virtualIndex = index - cplus_plus_ex.MAX_SKILL_SLOTS

		if virtualIndex > #virtualSkills then
			logger.logError(SUBMODULE, "Pilot %s does not have skill at index %d (has %d virtual skills)",
				pilotId, index, #virtualSkills)
			return
		end

		local skillObj = virtualSkills[virtualIndex]

		-- Handle both struct and table arguments (match original behavior)
		if not structOrNewVals then
			logger.logError(SUBMODULE, "Cannot set nil value for skill at index %d", index)
			return
		end

		if type(structOrNewVals) == "table" then
			-- Check if it's a PilotLvlUpSkill struct (has _address method)
			if type(structOrNewVals._address) == "function" then
				-- It's a struct - use the standard set method
				skillObj:set(structOrNewVals)
			else
				-- It's a table of field values to set
				for field, value in pairs(structOrNewVals) do
					-- Convert field name to setter name (e.g., "healthBonus" -> "setHealthBonus")
					local setterName = "set" .. field:sub(1,1):upper() .. field:sub(2)

					if type(skillObj[setterName]) == "function" then
						skillObj[setterName](skillObj, value)
					else
						logger.logWarn(SUBMODULE, "No setter '%s' for field '%s' on virtual skill at index %d",
							setterName, field, index)
					end
				end
			end
		else
			logger.logError(SUBMODULE, "structOrNewVals must be a table, got %s", type(structOrNewVals))
		end
	end

	logger.logInfo(SUBMODULE, "Overridden Pilot:setLvlUpSkill to support virtual skills")
end

function pilot_overrides:_overrideCombineBonuses()
	local Pilot = memhack.structs.Pilot

	-- Store original if not already stored
	if not original_combineBonuses then
		original_combineBonuses = Pilot._combineBonuses
	end

	Pilot._combineBonuses = function(self)
		local pilotId = self:getIdStr()

		-- If no pilot ID, use original logic
		if not pilotId then
			logger.logDebug(SUBMODULE, "No pilot ID, using original combineBonuses")
			original_combineBonuses(self)
			return
		end

		-- Get virtual skills
		local virtualSkillObjs = skill_state_tracker:getVirtualSkillObjects(pilotId)

		-- If no virtual skills, use original logic
		if #virtualSkillObjs == 0 then
			logger.logDebug(SUBMODULE, "No virtual skills for %s, using original combineBonuses", pilotId)
			original_combineBonuses(self)
			return
		end

		-- We have virtual skills - manually combine all skills
		logger.logDebug(SUBMODULE, "Combining bonuses for %s with %d virtual skills", pilotId, #virtualSkillObjs)

		local skill1 = self:getLvlUpSkill(1)
		local skill2 = self:getLvlUpSkill(2)

		if not skill1 or not skill2 then
			logger.logWarn(SUBMODULE, "Missing real skills for pilot %s", pilotId)
			return
		end

		-- Get set values from state tracker (these are the "logical" values external code sees)
		local skill1Set = memhack.stateTracker:getSkillSetValues(skill1)
		local skill2Set = memhack.stateTracker:getSkillSetValues(skill2)

		-- Calculate total bonuses from all sources
		local totalBonuses = {
			health = skill1Set.healthBonus + skill2Set.healthBonus,
			cores = skill1Set.coresBonus + skill2Set.coresBonus,
			grid = skill1Set.gridBonus + skill2Set.gridBonus,
			move = skill1Set.moveBonus + skill2Set.moveBonus
		}

		-- Add virtual skill bonuses (only if they've been earned)
		local pilotLevel = self:getLevel()
		for virtualIdx, virtualSkill in ipairs(virtualSkillObjs) do
			local virtualSlotNum = cplus_plus_ex.MAX_SKILL_SLOTS + virtualIdx

			-- Check if this virtual skill has been earned
			if skill_state_tracker:hasPilotEarnedSkillIndex(self, virtualSlotNum) then
				local virtualSet = memhack.stateTracker:getSkillSetValues(virtualSkill)
				totalBonuses.health = totalBonuses.health + virtualSet.healthBonus
				totalBonuses.cores = totalBonuses.cores + virtualSet.coresBonus
				totalBonuses.grid = totalBonuses.grid + virtualSet.gridBonus
				totalBonuses.move = totalBonuses.move + virtualSet.moveBonus

				logger.logDebug(SUBMODULE, "  Added virtual skill %d: +%d health, +%d cores, +%d grid, +%d move",
					virtualIdx, virtualSet.healthBonus, virtualSet.coresBonus, virtualSet.gridBonus, virtualSet.moveBonus)
			end
		end

		-- Apply bonuses to memory based on pilot level and what's been earned
		-- Health and move are always set to their set values (game handles stacking)
		skill1:_setHealthBonus(skill1Set.healthBonus)
		skill1:_setMoveBonus(skill1Set.moveBonus)
		skill2:_setHealthBonus(skill2Set.healthBonus)
		skill2:_setMoveBonus(skill2Set.moveBonus)

		-- Cores and grid: combine into skill1 only if level >= 2 AND skill 2 is earned
		if pilotLevel >= 2 and skill_state_tracker:hasPilotEarnedSkillIndex(self, cplus_plus_ex.MAX_SKILL_SLOTS) then
			-- Pilot has earned skill 2, combine all bonuses into skill 1
			skill1:_setCoresBonus(totalBonuses.cores)
			skill1:_setGridBonus(totalBonuses.grid)
			skill2:_setCoresBonus(0)
			skill2:_setGridBonus(0)

			logger.logDebug(SUBMODULE, "Combined bonuses into skill1: +%d cores, +%d grid", totalBonuses.cores, totalBonuses.grid)
		else
			-- Level < 2 or skill 2 not earned yet: only apply skill 1's bonuses
			skill1:_setCoresBonus(skill1Set.coresBonus)
			skill1:_setGridBonus(skill1Set.gridBonus)
			skill2:_setCoresBonus(skill2Set.coresBonus)
			skill2:_setGridBonus(skill2Set.gridBonus)

			logger.logDebug(SUBMODULE, "Not combining (level=%d, earned slot 2=%s)", pilotLevel,
				tostring(skill_state_tracker:hasPilotEarnedSkillIndex(self, cplus_plus_ex.MAX_SKILL_SLOTS)))
		end
	end

	logger.logInfo(SUBMODULE, "Overridden Pilot:_combineBonuses to support virtual skills")
end

--- Override GetSkillInfo to automatically append virtual skills to pilot descriptions
--- This is called after other mods load to ensure if they override the same function,
--- we override it last and can control it.
--- Only applies the override once per game session to prevent double-appending.
function pilot_overrides:applyGetSkillInfoOverride()
	-- Check if we've already applied the override
	if getSkillInfoOverrideApplied then
		logger.logDebug(SUBMODULE, "GetSkillInfo override already applied, skipping")
		LOG("GetSkillInfo override already applied, skipping (PLAIN LOG)")
		return
	end
	logger.logInfo(SUBMODULE, "Overriding GetSkillInfo to automatically append virtual skills")

	-- Store the original function
	if not original_GetSkillInfo then
		original_GetSkillInfo = GetSkillInfo
		logger.logDebug(SUBMODULE, "Stored original GetSkillInfo function")
	end

	-- Apply the override using the truly original function
	function GetSkillInfo(skill)
		-- Get the original skill info
		local originalSkillInfo = original_GetSkillInfo(skill)

		-- Check for virtual skills and append them automatically
		local baseDesc = GetText(originalSkillInfo.desc)
		local dynamicDesc = pilot_overrides:buildVirtualSkillDescription(baseDesc, skill)

		-- If description changed (virtual skills were added), return modified version
		if dynamicDesc ~= baseDesc then
			logger.logDebug(SUBMODULE, "Added virtual skills to %s", skill)
			return PilotSkill(skill, dynamicDesc)
		end

		-- No virtual skills found, return original
		return originalSkillInfo
	end

	-- Mark as applied
	getSkillInfoOverrideApplied = true
	logger.logInfo(SUBMODULE, "GetSkillInfo override applied successfully")
end

--- Build skill description with virtual skills appended
--- Automatically checks all pilots and appends virtual skill names if found
--- Works for both regular pilots and time travelers
function pilot_overrides:buildVirtualSkillDescription(baseDescription, pilotSkillId)
	-- Between missions, add note about extra info panel instead of listing skills
	if not Game then
		-- Check time travelers from persistent data if pilot not found in current squad
		local time_traveler = cplus_plus_ex._subobjects.time_traveler
		if time_traveler and time_traveler.potentialTimeTravelers then
			for _, timeTravelerPilot in ipairs(time_traveler.potentialTimeTravelers) do
				local pilotSkill = timeTravelerPilot:getSkill():get()
				if pilotSkill == pilotSkillId then
					local pilotId = timeTravelerPilot:getIdStr()
					local virtualSkills = skill_state_tracker:getVirtualSkills(pilotId)
	
					if virtualSkills and #virtualSkills > 0 then
						-- Collect virtual skill names
						local skillNames = {}
						for j, skillId in ipairs(virtualSkills) do
							local skillData = cplus_plus_ex._subobjects.skill_registry:getRegisteredSkillInfo(skillId)
							if skillData then
								table.insert(skillNames, GetText(skillData.fullName))
							end
						end
	
						-- Append to description
						if #skillNames > 0 then
							return baseDescription .. "\n" .. table.concat(skillNames, ", ")
						end
					end
				end
			end
		end
		return baseDescription
	end

	-- Check all available pilots for this skill
	local pilots = Game:GetAvailablePilots()
	for i, pilotStruct in ipairs(pilots) do
		local pilotSkill = pilotStruct:getSkill():get()

		if pilotSkill == pilotSkillId then
			local pilotId = pilotStruct:getIdStr()
			local virtualSkills = skill_state_tracker:getVirtualSkills(pilotId)

			if virtualSkills and #virtualSkills > 0 then
				-- Collect virtual skill names
				local skillNames = {}
				for j, skillId in ipairs(virtualSkills) do
					local skillData = cplus_plus_ex._subobjects.skill_registry:getRegisteredSkillInfo(skillId)
					if skillData then
						table.insert(skillNames, GetText(skillData.fullName))
					end
				end

				-- Append to description
				if #skillNames > 0 then
					return baseDescription .. "\n\nExtra Skills: " .. table.concat(skillNames, ", ")
				end
			end
			return baseDescription
		end
	end

	-- Pilot not found, return base description
	return baseDescription
end

--- Initialize all pilot overrides
--- Must be called after skill_state_tracker is initialized
function pilot_overrides:init()
	logger.logInfo(SUBMODULE, "Initializing Pilot overrides for virtual skills support")

	-- Apply critical overrides
	self:_overrideGetLvlUpSkill()
	self:_overrideSetLvlUpSkill()
	self:_overrideCombineBonuses()

	logger.logInfo(SUBMODULE, "Pilot overrides initialized successfully")
	return self
end

return pilot_overrides
