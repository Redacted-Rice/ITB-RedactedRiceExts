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

-- State tracking tables
function skill_state_tracker:_resetAllTrackers()
	-- Free all virtual skill objects before clearing trackers
	-- First time its called, the table may not be setup yet
	if self._virtualSkillObjects then
		self:_freeAllVirtualSkillObjects()
	end

	self._hasAppliedSkill = false
	self._isAssigningSkills = false
	self._enabledSkills = {}  -- skillId -> true (skill is enabled in config)
	self._inRunSkills = {}    -- skillId -> {pilotAddr -> {pilot, skillIndices}} where skillIndices is array of 1 and/or 2
	self._activeSkills = {}   -- skillId -> {pawnId -> {pilot, skillIndices}}
	self._virtualSkillObjects = {}  -- pilotId -> array of PilotLvlUpSkill objects for more than 2 skills
end

function skill_state_tracker:init()
	hooks = cplus_plus_ex._subobjects.hooks
	utils = cplus_plus_ex._subobjects.utils

	return self
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
	local virtualSkills = self:getVirtualSkills(pilot:getIdStr())

	for virtIndex, _ in ipairs(virtualSkills) do
		table.insert(result, cplus_plus_ex.MAX_SKILL_SLOTS + virtIndex)
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
	local virtualSkills = self:getVirtualSkills(pilot:getIdStr())

	for virtIndex, vSkillId in ipairs(virtualSkills) do
		if vSkillId == skillId then
			-- Virtual skill slot indices start at MAX_SKILL_SLOTS + 1
			table.insert(indices, cplus_plus_ex.MAX_SKILL_SLOTS + virtIndex)
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
			local virtualSkills = self:getVirtualSkills(pilot:getIdStr())

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
			local virtualSkills = self:getVirtualSkills(pilot:getIdStr())

			for virtIndex, vSkillId in ipairs(virtualSkills) do
				if vSkillId == skillId then
					table.insert(skillIndices, cplus_plus_ex.MAX_SKILL_SLOTS + virtIndex)
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
			local skill = self:_getSkillByIndex(instance.pilot, skillIndex)
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
			local skill = self:_getSkillByIndex(pilot, skillIndex)
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
					local skillStruct = self:_getSkillByIndex(data.pilot, skillIndex)
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
					local skillStruct = self:_getSkillByIndex(data.pilot, skillIndex)
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
			local skill = self:_getSkillByIndex(instance.pilot, skillIndex)
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
			local skill = self:_getSkillByIndex(pilot, skillIndex)
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
					local skillStruct = self:_getSkillByIndex(data.pilot, skillIndex)
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
					local skillStruct = self:_getSkillByIndex(data.pilot, skillIndex)
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

-------------------- Helper: Get Skill by Index (Real or Virtual) --------------------

-- Helper to get a skill by index, handling both real (1-2) and virtual (3+) skills
-- This avoids calling pilot:getLvlUpSkill() with indices > 2 which triggers warnings
function skill_state_tracker:_getSkillByIndex(pilot, skillIndex)
	if skillIndex <= cplus_plus_ex.MAX_SKILL_SLOTS then
		-- Real skill
		return pilot:getLvlUpSkill(skillIndex)
	else
		-- Virtual skill
		local pilotId = pilot:getIdStr()
		local virtualIndex = skillIndex - cplus_plus_ex.MAX_SKILL_SLOTS
		return self:getVirtualSkillObject(pilotId, virtualIndex)
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

	-- Update states which will handle real and virtual skills
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

-- Free memory for a virtual skill object
-- obj: PilotLvlUpSkill object to deallocate
function skill_state_tracker:_freeVirtualSkillObject(obj)
	if not obj then
		return
	end
	-- Check if it's a PilotLvlUpSkill struct using memhack's type system
	if type(obj) ~= "userdata" or getmetatable(obj) ~= memhack.structs.PilotLvlUpSkill then
		logger.logWarn(SUBMODULE, "Cannot free virtual skill object: expected PilotLvlUpSkill struct, got %s", type(obj))
		return
	end

	local addr = obj:getAddress()
	if not addr or addr == 0 then
		logger.logWarn(SUBMODULE, "Cannot free virtual skill object with invalid address")
		return
	end

	local skillId = obj:getIdStr()
	logger.logDebug(SUBMODULE, "Freeing virtual skill object %s at address 0x%X", skillId, addr)

	-- Free the allocated memory
	local success, err = pcall(function()
		memhack.dll.memory.freeNullTermString(addr)
	end)

	if not success then
		logger.logError(SUBMODULE, "Failed to free memory for virtual skill object %s at 0x%X: %s", skillId, addr, err)
	end
end

-- Create a virtual skill object in allocated memory (does not add to tracking)
-- Returns the skill object or nil on error
function skill_state_tracker:_createVirtualSkillObject(pilot, skillId)
	local pilotId = pilot:getIdStr()
	local skill_config_module = cplus_plus_ex._subobjects.skill_config
	local skill = skill_config_module.enabledSkills[skillId]
	if not skill then
		logger.logError(SUBMODULE, "Cannot create virtual skill object for unknown skill: %s", skillId)
		return nil
	end

	-- Allocate memory for the new skill object
	local addr = self:_allocateSkillMemory()
	if not addr then
		logger.logError(SUBMODULE, "Failed to allocate memory for virtual skill object: %s", skillId)
		return nil
	end

	local skillObj = memhack.structs.PilotLvlUpSkill.new(addr, false)
	if not skillObj then
		logger.logError(SUBMODULE, "Failed to create PilotLvlUpSkill struct for virtual skill: %s", skillId)
		return nil
	end
	-- Set the parent pilot
	skillObj._parent = {
		Pilot = pilot,
	}

	-- Pre-initialize ItBString unionType fields to LOCAL using hidden setter
	-- This makes the ItBString structs valid so _noFire setters won't fail validation
	local layout = memhack.structs.PilotLvlUpSkill._layout
	for _, fieldName in ipairs({"id", "shortName", "fullName", "description"}) do
		local fieldDef = layout[fieldName]
		if fieldDef then
			local itbStr = memhack.structs.ItBString.new(addr + fieldDef.offset, false)
			itbStr:_setUnionType(memhack.structs.ItBString.LOCAL)
		end
	end

	-- Use _noFire setters to initialize all fields without triggering change detection
	skillObj:_setId_noFire(skillId)
	skillObj:_setShortName_noFire(skill.shortName or skillId)
	skillObj:_setFullName_noFire(skill.fullName or skillId)
	skillObj:_setDescription_noFire(skill.description or "")
	skillObj:_setSaveVal_noFire(skill.saveVal or 0)

	-- Initialize bonus values (memory is already zeroed, so default to 0)
	local healthBonus = (skill.bonuses and skill.bonuses.health) or 0
	local moveBonus = (skill.bonuses and skill.bonuses.move) or 0
	local coresBonus = (skill.bonuses and skill.bonuses.cores) or 0
	local gridBonus = (skill.bonuses and skill.bonuses.grid) or 0

	-- Set bonuses in memory using _noFire
	skillObj:_setHealthBonus_noFire(healthBonus)
	skillObj:_setMoveBonus_noFire(moveBonus)
	skillObj:_setCoresBonus_noFire(coresBonus)
	skillObj:_setGridBonus_noFire(gridBonus)

	logger.logDebug(SUBMODULE, "Created virtual skill object for %s at address 0x%X", skillId, addr)
	return skillObj
end

-- Get all virtual skill objects for a pilot
-- pilotId: pilot ID string (e.g. "Pilot_Warbot")
-- Returns: array of PilotLvlUpSkill objects
function skill_state_tracker:getVirtualSkillObjects(pilotId)
	if type(pilotId) ~= "string" then
		logger.logError(SUBMODULE, "getVirtualSkillObjects: expected pilotId string, got %s", type(pilotId))
		return {}
	end
	return self._virtualSkillObjects[pilotId] or {}
end

-- Get a specific virtual skill object by slot index (1-based from virtual skills)
-- pilotId: pilot ID string (e.g. "Pilot_Warbot")
-- slotIndex: 1 for first virtual skill (slot 3), 2 for second (slot 4), etc.
function skill_state_tracker:getVirtualSkillObject(pilotId, slotIndex)
	if type(pilotId) ~= "string" then
		logger.logError(SUBMODULE, "getVirtualSkillObject: expected pilotId string, got %s", type(pilotId))
		return nil
	end
	local objs = self:getVirtualSkillObjects(pilotId)
	if not objs then
		return nil
	end
	return objs[slotIndex]
end

-- Remove a virtual skill object by skill ID
-- Returns true if found and removed, false otherwise
function skill_state_tracker:_removeVirtualSkillObjectBySkillId(pilotId, skillId)
	if not self._virtualSkillObjects[pilotId] then
		return false
	end

	for i, obj in ipairs(self._virtualSkillObjects[pilotId]) do
		if obj:getIdStr() == skillId then
			-- Free the memory before removing from tracking
			self:_freeVirtualSkillObject(obj)
			table.remove(self._virtualSkillObjects[pilotId], i)
			logger.logDebug(SUBMODULE, "Removed virtual skill object %s from pilot %s", skillId, pilotId)
			return true
		end
	end
	return false
end

-- Clear all virtual skill objects for a pilot
function skill_state_tracker:_clearVirtualSkillObjects(pilotId)
	local objects = self._virtualSkillObjects[pilotId] or {}
	local count = #objects

	-- Free all memory before clearing
	for _, obj in ipairs(objects) do
		self:_freeVirtualSkillObject(obj)
	end

	self._virtualSkillObjects[pilotId] = {}
	logger.logDebug(SUBMODULE, "Cleared and freed %d virtual skill objects from pilot %s", count, pilotId)
end

-- Free all virtual skill objects for all pilots
function skill_state_tracker:_freeAllVirtualSkillObjects()
	local totalCount = 0
	for pilotId, objects in pairs(self._virtualSkillObjects) do
		logger.logDebug(SUBMODULE, "pilotId: %s, objects type: %s, count: %s",
				tostring(pilotId), type(objects), type(objects) == "table" and #objects or "N/A")

		local count = #objects
		totalCount = totalCount + count

		for _, obj in ipairs(objects) do
			self:_freeVirtualSkillObject(obj)
		end
	end

	if totalCount > 0 then
		logger.logInfo(SUBMODULE, "Freed %d virtual skill objects for all pilots during cleanup", totalCount)
	end
end

-- Synchronize virtual skill objects with save data
-- Handles duplicates: if save data has ["SkillA", "SkillA", "SkillB"], creates 3 objects
function skill_state_tracker:_syncVirtualSkillObjects(pilot)
	local pilotId = pilot:getIdStr()

	-- Get what skills we need
	local savedSkillIds = {}
	if GAME and GAME.cplus_plus_ex and GAME.cplus_plus_ex.pilotVirtualSkills then
		savedSkillIds = GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] or {}
	end

	-- Get current objects
	local currentObjects = self._virtualSkillObjects[pilotId] or {}

	-- Build new array matching save data
	local newObjects = {}
	for _, skillId in ipairs(savedSkillIds) do
		-- Try to find an object with this skillId in currentObjects
		local found = false
		for i, obj in ipairs(currentObjects) do
			if obj:getIdStr() == skillId then
				-- Reuse this object
				table.insert(newObjects, obj)
				table.remove(currentObjects, i)  -- Remove so we don't reuse it for duplicates
				found = true
				logger.logDebug(SUBMODULE, "Reusing object for %s on pilot %s", skillId, pilotId)
				break
			end
		end

		if not found then
			-- Need to create a new object
			local obj = self:_createVirtualSkillObject(pilot, skillId)
			if obj then
				table.insert(newObjects, obj)
				logger.logDebug(SUBMODULE, "Created object for %s on pilot %s", skillId, pilotId)
			else
				logger.logError(SUBMODULE, "Failed to create object for %s on pilot %s", skillId, pilotId)
			end
		end
	end

	-- Free any orphaned objects that are no longer in save data
	for _, orphanedObj in ipairs(currentObjects) do
		local orphanedSkillId = orphanedObj:getIdStr()
		logger.logDebug(SUBMODULE, "Freeing orphaned virtual skill object %s for pilot %s", orphanedSkillId, pilotId)
		self:_freeVirtualSkillObject(orphanedObj)
	end

	-- Replace with new array
	self._virtualSkillObjects[pilotId] = newObjects

	logger.logDebug(SUBMODULE, "Synced pilot %s: %d skills in save data = %d objects",
			pilotId, #savedSkillIds, #newObjects)
end

-- Synchronize virtual skill objects for all pilots
function skill_state_tracker:_syncAllVirtualSkillObjects()
	if not GAME or not GAME.cplus_plus_ex or not GAME.cplus_plus_ex.pilotVirtualSkills then
		return
	end

	if not Game then
		return
	end

	-- Build set of available pilot IDs
	local availablePilotIds = {}
	local allPilots = Game:GetAvailablePilots()
	for _, pilot in ipairs(allPilots) do
		local pilotId = pilot:getIdStr()
		availablePilotIds[pilotId] = pilot

		-- Only sync if this pilot has virtual skills in save data
		if GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] then
			self:_syncVirtualSkillObjects(pilot)
			-- Trigger _combineBonuses to update bonuses with virtual skills
			pilot:_combineBonuses()
		end
	end

	-- Clean up any tracked virtual skill objects for pilots that are no longer available
	for pilotId, _ in pairs(self._virtualSkillObjects) do
		if not availablePilotIds[pilotId] then
			logger.logDebug(SUBMODULE, "Cleaning up virtual skill objects for unavailable pilot %s", pilotId)
			self:_clearVirtualSkillObjects(pilotId)
		end
	end
end

-------------------- Virtual Skill Query Functions --------------------

function skill_state_tracker:getVirtualSkills(pilotId)
	if type(pilotId) ~= "string" then
		logger.logError(SUBMODULE, "Expected pilotId string, got %s", type(pilotId))
		return {}
	end

	if not GAME or not GAME.cplus_plus_ex or not GAME.cplus_plus_ex.pilotVirtualSkills then
		logger.logDebug(SUBMODULE, "%s - GAME state not ready, returning {}", pilotId)
		return {}
	end

	local skills = GAME.cplus_plus_ex.pilotVirtualSkills[pilotId] or {}
	logger.logDebug(SUBMODULE, "%s - returning %d skills: %s",
		pilotId, #skills, table.concat(skills, ", "))
	return skills
end

-- Get total skill count for a pilot including virtual skills
function skill_state_tracker:getTotalSkillCount(pilotId)
	if type(pilotId) ~= "string" then
		logger.logError(SUBMODULE, "getTotalSkillCount: expected pilotId string, got %s", type(pilotId))
		return cplus_plus_ex.MAX_SKILL_SLOTS
	end
	local realSkills = cplus_plus_ex.MAX_SKILL_SLOTS
	local virtualSkills = #self:getVirtualSkills(pilotId)
	return realSkills + virtualSkills
end

-- Get all skill IDs assigned to a pilot including virtual skills
-- Returns: array of skill ID strings
function skill_state_tracker:getAllSkills(pilot)
	local skillIds = {}

	-- Add real skills
	for i = 1, cplus_plus_ex.MAX_SKILL_SLOTS do
		local skill = pilot:getLvlUpSkill(i)
		if skill then
			table.insert(skillIds, skill:getIdStr())
		end
	end

	-- Add virtual skills
	for _, skillId in ipairs(self:getVirtualSkills(pilot:getIdStr())) do
		table.insert(skillIds, skillId)
	end

	return skillIds
end

skill_state_tracker:_resetAllTrackers()
return skill_state_tracker
