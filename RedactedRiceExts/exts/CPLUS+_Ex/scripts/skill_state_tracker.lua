--[[
	Skill State Tracking for CPLUS+

	Tracks two states for each skill:
	1. InRun - skill is on any pilot in the run (and they're high enough level)
	2. Active - skill is on one of the 3 pilots in active mechs

	Integrates with memhack hooks to detect changes and fire appropriate skill hooks.
--]]

local skill_state_tracker = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "StateTracker", cplus_plus_ex.DEBUG.STATE_TRACKER and cplus_plus_ex.DEBUG.ENABLED)

local hooks = nil
local utils = nil
local original_combineBonuses = nil  -- Store original _combineBonuses function

-- State tracking tables
function skill_state_tracker:_resetAllTrackers()
	self._hasAppliedSkill = false
	self._isAssigningSkills = false
	self._enabledSkills = {}  -- skillId -> true (skill is enabled in config)
	self._inRunSkills = {}    -- skillId -> {pilotAddr -> {pilot, skillIndices}} where skillIndices is array of 1 and/or 2
	self._activeSkills = {}   -- skillId -> {pawnId -> {pilot, skillIndices}}
	self._virtualSkillObjects = {}  -- pilotId -> array of PilotLvlUpSkill objects for more than 2 skills
end
skill_state_tracker:_resetAllTrackers()

function skill_state_tracker:init()
	hooks = cplus_plus_ex._subobjects.hooks
	utils = cplus_plus_ex._subobjects.utils

	-- Override memhack's Pilot:_combineBonuses to include virtual skills
	self:_overrideCombineBonuses()

	return self
end

-- Override memhack's Pilot:_combineBonuses to include virtual skill bonuses
function skill_state_tracker:_overrideCombineBonuses()
	local Pilot = memhack.structs.Pilot
	original_combineBonuses = Pilot._combineBonuses

	Pilot._combineBonuses = function(self)
		local virtualSkillObjs = skill_state_tracker:getVirtualSkillObjects(self)

		-- If no virtual skills, just call original combining logic
		if not virtualSkillObjs or #virtualSkillObjs == 0 then
			original_combineBonuses(self)
			return
		end

		-- If we have virtual skills, manually combine all skills into skill 1
		-- This prevents conflicts between skill 2 and virtual skill bonuses
		local skill1 = self:getLvlUpSkill(1)
		local skill2 = self:getLvlUpSkill(2)

		if not skill1 then
			return
		end

		-- Calculate total bonuses from all sources
		local totalBonuses = {health = 0, cores = 0, grid = 0, move = 0}

		-- Add skill 1 bonuses
		totalBonuses.health = totalBonuses.health + skill1:getHealthBonus()
		totalBonuses.cores = totalBonuses.cores + skill1:getCoresBonus()
		totalBonuses.grid = totalBonuses.grid + skill1:getGridBonus()
		totalBonuses.move = totalBonuses.move + skill1:getMoveBonus()

		-- Add skill 2 bonuses if present
		if skill2 then
			totalBonuses.health = totalBonuses.health + skill2:getHealthBonus()
			totalBonuses.cores = totalBonuses.cores + skill2:getCoresBonus()
			totalBonuses.grid = totalBonuses.grid + skill2:getGridBonus()
			totalBonuses.move = totalBonuses.move + skill2:getMoveBonus()
		end

		-- Add virtual skill bonuses
		for _, skillObj in ipairs(virtualSkillObjs) do
			totalBonuses.health = totalBonuses.health + skillObj:getHealthBonus()
			totalBonuses.cores = totalBonuses.cores + skillObj:getCoresBonus()
			totalBonuses.grid = totalBonuses.grid + skillObj:getGridBonus()
			totalBonuses.move = totalBonuses.move + skillObj:getMoveBonus()
		end

		local pilotId = self:getIdStr()
		logger.logDebug(SUBMODULE, "Combining all bonuses for pilot %s: +%d HP, +%d Move, +%d Grid, +%d Reactor",
				pilotId, totalBonuses.health, totalBonuses.move, totalBonuses.grid, totalBonuses.cores)

		-- Set all combined bonuses in skill 1
		skill1:_setHealthBonus(totalBonuses.health)
		skill1:_setCoresBonus(totalBonuses.cores)
		skill1:_setGridBonus(totalBonuses.grid)
		skill1:_setMoveBonus(totalBonuses.move)
	end
	logger.logInfo(SUBMODULE, "Overridden Pilot:_combineBonuses to include virtual skill bonuses")
end

-- Mark the start of skill assignment so we disabling firing hooks on tracking changes
function skill_state_tracker:_beginAssignment()
	self._isAssigningSkills = true
end

-- Mark that skills have been applied (called by main module after assignment)
function skill_state_tracker:_updateAfterAssignment()
	logger.logDebug(SUBMODULE, "Post-assignment: updating in-run and active skill states")
	self._hasAppliedSkill = true
	self._isAssigningSkills = false
	-- Update in-run and active states after skills have been assigned to triggers
	-- any changes
	self:_updateAllStates()
end

-- Update states only if pilot level changed (called on pilot changed event)
function skill_state_tracker:_updateStatesIfNeeded(pilot, changes)
	-- Check if level changed. This is the only change that will affect skill availability
	if changes.level then
		self:_updateAllStates()
	end
end

------------------ Helper functions ------------------

-- Check if a pilot is high enough level for the skill at the given index to be earned
-- Virtual skills are always considered earned
function skill_state_tracker:hasPilotEarnedSkillIndex(pilot, skillIndex)
	if not pilot then return false end

	-- Virtual skills (slots 3+) are always earned
	if skillIndex > cplus_plus_ex.MAX_SKILL_SLOTS then
		return true
	end

	-- Real skills require level
	local result = pilot:getLevel() >= skillIndex
	return result
end

function skill_state_tracker:getPilotEarnedSkillIndexes(pilot)
	local pilotLevel = pilot:getLevel()
	local result = {}

	-- Add earned real skills
	for skillIndex = 1, pilotLevel do
		table.insert(result, skillIndex)
	end

	-- Add all virtual skills
	local virtualSkills = self:getVirtualSkills(pilot)

	for virtIndex, _ in ipairs(virtualSkills) do
		table.insert(result, 2 + virtIndex)
	end

	return result
end

function skill_state_tracker:getPilotSkillIndices(skillId, pilot, checkEarned)
	if checkEarned == nil then checkEarned = true end

	local indices = {}

	-- Check real skills
	for skillIndex = 1, cplus_plus_ex.MAX_SKILL_SLOTS do
		local skill = pilot:getLvlUpSkill(skillIndex)
		if skill and skill:getIdStr() == skillId then
			if not checkEarned or self:hasPilotEarnedSkillIndex(pilot, skillIndex) then
				table.insert(indices, skillIndex)
			end
		end
	end

	-- Check virtual skills
	-- Virtual skills are always earned
	local virtualSkills = self:getVirtualSkills(pilot)

	for virtIndex, vSkillId in ipairs(virtualSkills) do
		if vSkillId == skillId then
			-- Virtual skill slot indices start at 3
			table.insert(indices, 2 + virtIndex)
		end
	end

	return indices
end

function skill_state_tracker:isSkillOnPilot(skillId, pilot, checkEarned)
	return self:isSkillOnPilots(skillId, {pilot}, checkEarned)
end

function skill_state_tracker:isSkillOnPawn(skillId, pawn, checkEarned)
	local pilot = pawn:GetPilot()
	if pilot then
		return self:isSkillOnPilot(skillId, pilot, checkEarned)
	end
end

-- Check if a skill is on any pilot in the given list
-- pilots: list of pilots to check (defaults to all available pilots)
-- checkEarned: if true, only check earned skills (defaults to true)
function skill_state_tracker:isSkillOnPilots(skillId, pilots, checkEarned)
	if pilots == nil then
		if not Game then return false end
		pilots = Game:GetAvailablePilots()
	end
	if not pilots or #pilots == 0 then return false end

	if checkEarned == nil then checkEarned = true end

	for _, pilot in ipairs(pilots) do
		if pilot then
			-- Check real skills
			for skillIndex = 1, cplus_plus_ex.MAX_SKILL_SLOTS do
				local skill = pilot:getLvlUpSkill(skillIndex)
				if skill then
					local currentSkillId = skill:getIdStr()
					if currentSkillId == skillId then
						if not checkEarned then
							return true
						elseif self:hasPilotEarnedSkillIndex(pilot, skillIndex) then
							return true
						end
					end
				end
			end

			-- Check virtual skills
			local virtualSkills = self:getVirtualSkills(pilot)

			for _, vSkillId in ipairs(virtualSkills) do
				if vSkillId == skillId then
					return true  -- Virtual skills are always earned
				end
			end
		else
			logger.logWarn(SUBMODULE, "Pilot " .. idx .. " is nil in isSkillOnPilots - skipping")
		end
	end
	return false
end

-- Get all pilots from list that have this skill
-- pilots: list of pilots to check (defaults to all available pilots)
-- checkEarned: if true, only include earned skills (defaults to true)
-- Returns: list of {pilot, skillIndices} where skillIndices is array of skill slot numbers (1 and/or 2)
function skill_state_tracker:getPilotsWithSkill(skillId, pilots, checkEarned)
	if pilots == nil then
		if not Game then return {} end
		pilots = Game:GetAvailablePilots()
	end

	local result = {}
	if not pilots or #pilots == 0 then return result end

	if checkEarned == nil then checkEarned = true end
	for _, pilot in ipairs(pilots) do
		if pilot then
			local skillIndices = {}

			-- Check real skills
			for skillIndex = 1, cplus_plus_ex.MAX_SKILL_SLOTS do
				local skill = pilot:getLvlUpSkill(skillIndex)

				if skill then
					local currentSkillId = skill:getIdStr()
					if currentSkillId == skillId then
						if not checkEarned then
							table.insert(skillIndices, skillIndex)
						elseif self:hasPilotEarnedSkillIndex(pilot, skillIndex) then
							table.insert(skillIndices, skillIndex)
						end
					end
				end
			end

			-- Check virtual skills
			local virtualSkills = self:getVirtualSkills(pilot)

			for virtIndex, virtualSkill in ipairs(virtualSkills) do
				if virtualSkill.id == skillId then
					table.insert(skillIndices, 2 + virtIndex)
				end
			end

			-- If we found any, add them
			if #skillIndices > 0 then
				table.insert(result, {
					pilot = pilot,
					skillIndices = skillIndices
			})
		end
	else
		logger.logWarn(SUBMODULE, "Pilot " .. idx .. " is nil in getPilotsWithSkill - skipping")
	end
	end
	return result
end

-- Get which mechs have a specific skill
-- checkEarned: if true, only include earned skills (defaults to true)
-- Returns: list of {pawnId, pilot, skillIndices}
function skill_state_tracker:getMechsWithSkill(skillId, checkEarned)
	local mechs = {}
	if not Game then return mechs end

	if checkEarned == nil then checkEarned = true end
	local pilots = self:getPilotsWithSkill(skillId, Game:GetSquadPilots(), checkEarned)
	for _, pilotData in ipairs(pilots) do
		-- Data will be non-nil - getPilotsWithSkill handles this already
		local pawnId = pilotData.pilot:getPawnId()
		if pawnId then
			table.insert(mechs, {
				pawnId = pawnId,
				pilot = pilotData.pilot,
				skillIndices = pilotData.skillIndices
			})
		end
	end
	return mechs
end

-------------------- Enabled/Disabled Tracking --------------------

-- Check if a skill is currently enabled in config
function skill_state_tracker:isSkillEnabled(skillId)
	return self._enabledSkills[skillId] == true
end

-- Get all enabled skills
-- Returns: {skillId = true, ...}
function skill_state_tracker:getSkillsEnabled()
	return self._enabledSkills
end

-- Update enabled skills state and fire hooks for changes
-- Only fires hooks if we're in a game
function skill_state_tracker:_updateEnabledSkills()
	local newEnabledSkills = cplus_plus_ex._subobjects.skill_config:getEnabledSkillsSet()
	local hooksToFire = {}

	-- Check for newly enabled skills
	for skillId in pairs(newEnabledSkills) do
		if not self._enabledSkills[skillId] then
			table.insert(hooksToFire, {skillId = skillId, enabled = true})
		end
	end

	-- Check for newly disabled skills
	for skillId in pairs(self._enabledSkills) do
		if not newEnabledSkills[skillId] then
			table.insert(hooksToFire, {skillId = skillId, enabled = false})
		end
	end

	-- Update state
	self._enabledSkills = newEnabledSkills

	-- Only fire hooks if we're in a game
	if Game then
		for _, hook in ipairs(hooksToFire) do
			logger.logDebug(SUBMODULE, "Skill Enabled: %s is %s - Firing hooks...", hook.skillId,
					(hook.enabled and "enabled" or "disabled"))
			hooks.fireSkillEnabledHooks(hook.skillId, hook.enabled)
		end
	end
end

-------------------- InRun Tracking --------------------

-- Check if a skill is in run at all (on available pilots, any level)
function skill_state_tracker:isSkillInRun(skillId)
	local inRun = self._inRunSkills[skillId]
	local result = inRun ~= nil and next(inRun) ~= nil
	return result
end

-- Get skills in run (user-friendly format)
-- Returns: {skillId -> [{pilot, skillIndices}, ...], ...}
function skill_state_tracker:getSkillsInRun()
	local result = {}
	for skillId, pilots in pairs(self._inRunSkills) do
		result[skillId] = {}
		for _, data in pairs(pilots) do
			table.insert(result[skillId], {
				pilot = data.pilot,
				skillIndices = data.skillIndices
			})
		end
	end
	return result
end

-- Get skill struct objects for a specific skill that is in run
-- skillId: the skill ID to get structs for
-- Returns: array of skill struct objects (PilotLvlUpSkill)
function skill_state_tracker:getSkillObjsInRun(skillId)
	local result = {}
	local allInRun = self:getSkillsInRun()
	local instances = allInRun[skillId] or {}
	for _, instance in ipairs(instances) do
		for _, skillIndex in ipairs(instance.skillIndices) do
			local skill = instance.pilot:getLvlUpSkill(skillIndex)
			if skill then
				table.insert(result, skill)
			end
		end
	end
	return result
end

-- Determine in-run skills state for all enabled skills
-- Returns in internal state format: {skillId -> {pilotAddr -> {pilot, skillIndices}}}
function skill_state_tracker:_determineInRunSkillsState()
	local result = {}
	if not Game then return result end

	-- Loop through pilots once and build state for all skills
	local availablePilots = Game:GetAvailablePilots()
	for _, pilot in ipairs(availablePilots) do
		local pilotAddr = pilot:getAddress()
		-- Check each skill slot
		for _, skillIndex in ipairs(self:getPilotEarnedSkillIndexes(pilot)) do
			local skill = pilot:getLvlUpSkill(skillIndex)
			if skill then
				local skillId = skill:getIdStr()
				if not result[skillId] then
					result[skillId] = {}
				end
				if not result[skillId][pilotAddr] then
					result[skillId][pilotAddr] = {
						pilot = pilot,
						skillIndices = {},
					}
				end
				table.insert(result[skillId][pilotAddr].skillIndices, skillIndex)
			end
		end
	end
	return result
end

-- Update in-run skills state and fire hooks for changes
-- Only fires hooks if we're in a game
function skill_state_tracker:_updateInRunSkills()
	if not Game then
		-- No game active, clear all in-run skills
		self._inRunSkills = {}
		return
	end

	-- Determine new in-run skills state (already in internal format)
	local newInRunSkills = self:_determineInRunSkillsState()
	local hooksToFire = {}

	-- Check for newly added pilots with skills
	for skillId, newPilots in pairs(newInRunSkills) do
		local oldPilots = self._inRunSkills[skillId] or {}
		for pilotAddr, data in pairs(newPilots) do
			if not oldPilots[pilotAddr] then
				-- Queue hook for each skill instance
				for _, skillIndex in ipairs(data.skillIndices) do
					local skillStruct = data.pilot:getLvlUpSkill(skillIndex)
					table.insert(hooksToFire, {skillId = skillId, isInRun = true, pilot = data.pilot, skillStruct = skillStruct})
				end
			end
		end
	end

	-- Check for removed pilots with skills
	for skillId, oldPilots in pairs(self._inRunSkills) do
		local newPilots = newInRunSkills[skillId] or {}
		for pilotAddr, data in pairs(oldPilots) do
			if not newPilots[pilotAddr] then
				-- Queue hook for each skill instance. Skill may be nil if pilot was removed
				for _, skillIndex in ipairs(data.skillIndices) do
					local skillStruct = data.pilot:getLvlUpSkill(skillIndex)
					table.insert(hooksToFire, {skillId = skillId, isInRun = false, pilot = data.pilot, skillStruct = skillStruct})
				end
			end
		end
	end

	-- Update state
	self._inRunSkills = newInRunSkills

	-- Fire all queued hooks in order
	for _, hook in ipairs(hooksToFire) do
		logger.logDebug(SUBMODULE, "Skill In Run: %s %s - Firing hooks...", hook.skillId,
				(hook.isInRun and "in run" or "no longer in run"))
		hooks.fireSkillInRunHooks(hook.skillId, hook.isInRun, hook.pilot, hook.skillStruct)
	end
end

-------------------- Active/Inactive Tracking --------------------

-- Check if a skill is currently active (on one of the 3 active mechs)
function skill_state_tracker:isSkillActive(skillId)
	local active = self._activeSkills[skillId]
	return active ~= nil
end

-- Get active skills (user-friendly format)
-- Returns: {skillId -> [{pawnId, pilot, skillIndices}, ...], ...}
function skill_state_tracker:getSkillsActive()
	local result = {}
	for skillId, mechs in pairs(self._activeSkills) do
		result[skillId] = {}
		for pawnId, data in pairs(mechs) do
			table.insert(result[skillId], {
				pawnId = pawnId,
				pilot = data.pilot,
				skillIndices = data.skillIndices
			})
		end
	end
	return result
end

-- Get skill struct objects for a specific skill that is active
-- skillId: the skill ID to get structs for
-- Returns: array of skill struct objects (PilotLvlUpSkill)
function skill_state_tracker:getSkillObjsActive(skillId)
	local result = {}
	local allActive = self:getSkillsActive()
	local instances = allActive[skillId] or {}
	for _, instance in ipairs(instances) do
		for _, skillIndex in ipairs(instance.skillIndices) do
			local skill = instance.pilot:getLvlUpSkill(skillIndex)
			if skill then
				table.insert(result, skill)
			end
		end
	end
	return result
end

-- Determine active skills state for all enabled skills
-- Returns in internal state format: {skillId -> {pawnId -> {pilot, skillIndices}}}
function skill_state_tracker:_determineActiveSkillsState()
	local result = {}
	if not Game or not Board then return result end

	-- Loop through squad pilots once and build state for all skills
	local squadPilots = Game:GetSquadPilots()
	for _, pilot in ipairs(squadPilots) do
		local pawnId = pilot:getPawnId()
		-- Check each skill slot
		for _, skillIndex in ipairs(self:getPilotEarnedSkillIndexes(pilot)) do
			local skill = pilot:getLvlUpSkill(skillIndex)
			if skill then
				local skillId = skill:getIdStr()
				if not result[skillId] then
					result[skillId] = {}
				end
				if not result[skillId][pawnId] then
					result[skillId][pawnId] = {
						pilot = pilot,
						skillIndices = {},
					}
				end
				table.insert(result[skillId][pawnId].skillIndices, skillIndex)
			end
		end
	end

	return result
end

-- Update active skills state and fire hooks for changes
-- Only fires hooks if we're in a game
function skill_state_tracker:_updateActiveSkills()
	if not Game or not Board then
		-- No game active or no board, clear all active skills
		self._activeSkills = {}
		return
	end

	-- Determine new active skills state (already in internal format)
	local newActiveSkills = self:_determineActiveSkillsState()
	local hooksToFire = {}

	-- Check for newly active skills
	for skillId, newMechs in pairs(newActiveSkills) do
		local oldMechs = self._activeSkills[skillId] or {}
		for pawnId, data in pairs(newMechs) do
			if not oldMechs[pawnId] then
				-- Queue hook for each skill instance
				for _, skillIndex in ipairs(data.skillIndices) do
					local skillStruct = data.pilot:getLvlUpSkill(skillIndex)
					table.insert(hooksToFire, {skillId = skillId, isActive = true, pawnId = pawnId, pilot = data.pilot, skillStruct = skillStruct})
				end
			end
		end
	end

	-- Check for newly inactive skills
	for skillId, oldMechs in pairs(self._activeSkills) do
		local newMechs = newActiveSkills[skillId] or {}
		for pawnId, data in pairs(oldMechs) do
			if not newMechs[pawnId] then
				-- Queue hook for each skill instance. Skill may be nil if pilot was removed
				for _, skillIndex in ipairs(data.skillIndices) do
					local skillStruct = data.pilot:getLvlUpSkill(skillIndex)
					table.insert(hooksToFire, {skillId = skillId, isActive = false, pawnId = pawnId, pilot = data.pilot, skillStruct = skillStruct})
				end
			end
		end
	end

	-- Update state
	self._activeSkills = newActiveSkills

	-- Fire all queued hooks in order
	for _, hook in ipairs(hooksToFire) do
		logger.logDebug(SUBMODULE, "Skill Active: %s %s - Firing hooks...", hook.skillId,
				(hook.isActive and "is active" or "no longer is active"))
		hooks.fireSkillActiveHooks(hook.skillId, hook.isActive, hook.pawnId, hook.pilot, hook.skillStruct)
	end
end

-------------------- State Update Orchestration --------------------

-- Update all skill states (called from various triggers)
function skill_state_tracker:_updateAllStates()
	-- Skip updates if we're in the middle of assigning skills
	-- The postAssignment hook will handle the final update
	if self._isAssigningSkills then
		logger.logDebug(SUBMODULE, "Update all states: skipping during assignment")
		return
	end

	-- Sync virtual skill objects from save data
	self:_syncAllVirtualSkillObjects()

	self:_updateEnabledSkills()
	if self._hasAppliedSkill then
		self:_updateInRunSkills()
		self:_updateActiveSkills()
	else
		logger.logDebug(SUBMODULE, "Update all states: skipping In Run and Active")
	end
end

-------------------- Virtual Skill Object Management --------------------

-- Allocate memory for a virtual skill object
-- Returns: address of allocated memory
function skill_state_tracker:_allocateSkillMemory()
	-- Allocate a chunk of memory to use as the skill so we can use all the memhack fns on it
	local PilotLvlUpSkill = memhack.structs.PilotLvlUpSkill
	local size = PilotLvlUpSkill:StructSize()
	local zeroString = string.rep("\0", size)
	return memhack.dll.memory.allocNullTermString(zeroString)
end

-- Create a virtual skill object in allocated memory
function skill_state_tracker:_createVirtualSkillObject(pilot, skillId)
	local skill_config_module = cplus_plus_ex._subobjects.skill_config
	local skill = skill_config_module.enabledSkills[skillId]
	if not skill then
		logger.logError(SUBMODULE, "Cannot create virtual skill object for unknown skill: %s", skillId)
		return nil
	end

	local addr = self:_allocateSkillMemory()
	local skillObj = memhack.structs.PilotLvlUpSkill.new(addr, false)

	-- Initialize the skill object with data
	skillObj:setIdStr(skillId)
	skillObj:setShortNameStr(skill.shortName or skillId)
	skillObj:setFullNameStr(skill.fullName or skillId)
	skillObj:setDescriptionStr(skill.description or "")
	skillObj:setSaveVal(skill.saveVal or 0)
	if skill.bonuses then
		skillObj:setHealthBonus(skill.bonuses.health or 0)
		skillObj:setMoveBonus(skill.bonuses.move or 0)
		skillObj:setCoresBonus(skill.bonuses.cores or 0)
		skillObj:setGridBonus(skill.bonuses.grid or 0)
	end

	logger.logDebug(SUBMODULE, "Created virtual skill object for %s at address 0x%X", skillId, addr)
	return skillObj
end

-- Get all virtual skill objects for a pilot
-- Returns: array of PilotLvlUpSkill objects
function skill_state_tracker:getVirtualSkillObjects(pilot)
	local pilotId = pilot:getIdStr()
	return self._virtualSkillObjects[pilotId] or {}
end

-- Get a specific virtual skill object by slot index (1-based from virtual skills)
-- slotIndex: 1 for first virtual skill (slot 3), 2 for second (slot 4), etc.
function skill_state_tracker:getVirtualSkillObject(pilot, slotIndex)
	local pilotId = pilot:getIdStr()
	local objs = self._virtualSkillObjects[pilotId]
	if not objs then
		return nil
	end
	return objs[slotIndex]
end

-- Store a virtual skill object
function skill_state_tracker:_addVirtualSkillObject(pilot, skillObj)
	local pilotId = pilot:getIdStr()
	if not self._virtualSkillObjects[pilotId] then
		self._virtualSkillObjects[pilotId] = {}
	end
	table.insert(self._virtualSkillObjects[pilotId], skillObj)
end

-- Remove a virtual skill object at a specific index
function skill_state_tracker:_removeVirtualSkillObject(pilot, index)
	local pilotId = pilot:getIdStr()
	if self._virtualSkillObjects[pilotId] then
		table.remove(self._virtualSkillObjects[pilotId], index)
	end
end

-- Clear all virtual skill objects for a pilot
function skill_state_tracker:_clearVirtualSkillObjects(pilot)
	local pilotId = pilot:getIdStr()
	self._virtualSkillObjects[pilotId] = {}
end

-- Clear all virtual skill objects for all pilots
function skill_state_tracker:_clearAllVirtualSkillObjects()
	for pilotId, _ in pairs(self._virtualSkillObjects) do
		self._virtualSkillObjects[pilotId] = nil
	end
	self._virtualSkillObjects = {}
end

-- Synchronize virtual skill objects with save data
-- This ensures objects match the skill IDs in GAME.cplus_plus_ex.pilotVirtualSkills
-- Reuses existing objects where possible, creates new ones as needed, removes orphans
function skill_state_tracker:_syncVirtualSkillObjects(pilot)
	local pilotId = pilot:getIdStr()

	-- Get the skill IDs from save data
	local savedSkillIds = {}
	if GAME and GAME.cplus_plus_ex and GAME.cplus_plus_ex.pilotVirtualSkills then
		savedSkillIds = GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] or {}
	end

	-- Get current objects
	local currentObjects = self._virtualSkillObjects[pilotId] or {}
	local existingMap = {}
	for _, obj in ipairs(currentObjects) do
		local skillId = obj:getIdStr()
		existingMap[skillId] = obj
	end

	-- Build new objects array matching save data order
	local newObjects = {}
	for _, skillId in ipairs(savedSkillIds) do
		local obj = existingMap[skillId]
		if obj then
			-- Reuse existing object
			table.insert(newObjects, obj)
			logger.logDebug(SUBMODULE, "Reusing virtual skill object for %s on pilot %s", skillId, pilotId)
		else
			-- Create new object
			obj = self:_createVirtualSkillObject(pilot, skillId)
			if obj then
				table.insert(newObjects, obj)
				logger.logDebug(SUBMODULE, "Created new virtual skill object for %s on pilot %s", skillId, pilotId)
			else
				logger.logWarn(SUBMODULE, "Failed to create virtual skill object for %s on pilot %s", skillId, pilotId)
			end
		end
	end

	-- Replace the objects array
	self._virtualSkillObjects[pilotId] = newObjects
	logger.logDebug(SUBMODULE, "Synced %d virtual skill objects for pilot %s", #newObjects, pilotId)
end

-- Synchronize virtual skill objects for all pilots
function skill_state_tracker:_syncAllVirtualSkillObjects()
	if not GAME or not GAME.cplus_plus_ex or not GAME.cplus_plus_ex.pilotVirtualSkills then
		return
	end

	-- Sync for each pilot that has virtual skills
	for pilotId, _ in pairs(GAME.cplus_plus_ex.pilotVirtualSkills) do
		-- Get pilot from memory
		local pilot = memhack.structs.Pilot.getById(pilotId)
		if pilot then
			self:_syncVirtualSkillObjects(pilot)
		end
	end
end

-- Update virtual bonuses and fire hooks
-- This combines syncing objects, _combineBonuses, and _updateAllStates for efficiency
function skill_state_tracker:_updateVirtualSkillsAndStates(pilot)
	-- First sync objects from save data
	self:_syncVirtualSkillObjects(pilot)

	-- Trigger _combineBonuses to update bonuses with virtual skills
	pilot:_combineBonuses()

	-- Update state tracking to fire appropriate hooks
	self:_updateAllStates()
end

-------------------- Virtual Skill Query Functions --------------------

function skill_state_tracker:getVirtualSkills(pilot)
	if not GAME or not GAME.cplus_plus_ex or not GAME.cplus_plus_ex.pilotVirtualSkills then
		return {}
	end

	local pilotId = pilot:getIdStr()
	return GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] or {}
end

-- Get total skill count for a pilot including virtual skills
function skill_state_tracker:getTotalSkillCount(pilot)
	local realSkills = cplus_plus_ex.MAX_SKILL_SLOTS
	local virtualSkills = #self:getVirtualSkills(pilot)
	return realSkills + virtualSkills
end

-- Get all skill IDs assigned to a pilot including virtual skills
-- Returns: array of skill ID strings
function skill_state_tracker:getAllSkills(pilot)
	local skillIds = {}

	-- Add real skills
	for i = 1, 2 do
		local skill = pilot:getLvlUpSkill(i)
		if skill then
			table.insert(skillIds, skill:getIdStr())
		end
	end

	-- Add virtual skills
	for _, skillId in ipairs(self:getVirtualSkills(pilot)) do
		table.insert(skillIds, skillId)
	end

	return skillIds
end

return skill_state_tracker
