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
function skill_state_tracker:resetAllTrackers()
	self._hasAppliedSkill = false
	self._enabledSkills = {}  -- skillId -> true (skill is enabled in config)
	self._inRunSkills = {}    -- skillId -> {pilotAddr -> {pilot, skillIndices}} where skillIndices is array of 1 and/or 2
	self._activeSkills = {}   -- skillId -> {pawnId -> {pilot, skillIndices}}
end
skill_state_tracker:resetAllTrackers()

function skill_state_tracker:init()
	hooks = cplus_plus_ex._subobjects.hooks
	utils = cplus_plus_ex._subobjects.utils
	return self
end

-- Mark that skills have been applied (called by main module after assignment)
function skill_state_tracker:updateAfterAssignment()
	logger.logDebug(SUBMODULE, "Post-assignment: updating in-run and active skill states")
	self._hasAppliedSkill = true
	-- Update in-run and active states after skills have been assigned to triggers
	-- any changes
	self:updateAllStates()
end

-- Update states only if pilot level changed (called on pilot changed event)
function skill_state_tracker:updateStatesIfNeeded(pilot, changes)
	-- Check if level changed. This is the only change that will affect skill availability
	if changes.level then
		self:updateAllStates()
	end
end

------------------ Helper functions ------------------

-- Check if a pilot is high enough level for the skill at the given index to be earned
local function hasPilotEarnedSkillIndex(pilot, skillIndex)
	if not pilot then return false end
	local result = pilot:getLevel() >= skillIndex
	return result
end

local function getPilotEarnedSkillIndexes(pilot)
	local pilotLevel = pilot:getLevel()
	local result = {}
	for skillIndex = 1, pilotLevel do
		table.insert(result, skillIndex)
	end
	return result
end

function skill_state_tracker:isSkillOnPilot(skillId, pilot, checkEarned)
	return self:isSkillOnPilots(skillId, {pilot}, checkEarned)
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
			for skillIndex = 1, 2 do
				local skill = pilot:getLvlUpSkill(skillIndex)
				if skill then
					local currentSkillId = skill:getIdStr()
					if currentSkillId == skillId then
						if not checkEarned then
							return true
						elseif hasPilotEarnedSkillIndex(pilot, skillIndex) then
							return true
						end
					end
				end
			end
		else
			logger.logWarn(SUBMODULE, "Pilot %s is nil in isSkillOnPilots - skipping", idx)
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

			for skillIndex = 1, 2 do
				local skill = pilot:getLvlUpSkill(skillIndex)

				if skill then
					local currentSkillId = skill:getIdStr()
					if currentSkillId == skillId then
						if not checkEarned then
							table.insert(skillIndices, skillIndex)
						elseif hasPilotEarnedSkillIndex(pilot, skillIndex) then
							table.insert(skillIndices, skillIndex)
						end
					end
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
			logger.logWarn(SUBMODULE, "Pilot %s is nil in getPilotsWithSkill - skipping", idx)
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
function skill_state_tracker:updateEnabledSkills()
	if not Game then
		-- No game active, clear all enabled skills
		self._enabledSkills = {}
		return
	end

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

	-- Fire all queued hooks in order
	for _, hook in ipairs(hooksToFire) do
		logger.logDebug(SUBMODULE, "Skill Enabled: %s is %s - Firing hooks...", hook.skillId,
				(hook.enabled and "enabled" or "disabled"))
		hooks.fireSkillEnabledHooks(hook.skillId, hook.enabled)
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
		for _, skillIndex in ipairs(getPilotEarnedSkillIndexes(pilot)) do
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
function skill_state_tracker:updateInRunSkills()
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
		for _, skillIndex in ipairs(getPilotEarnedSkillIndexes(pilot)) do
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
function skill_state_tracker:updateActiveSkills()
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
function skill_state_tracker:updateAllStates()
	self:updateEnabledSkills()
	if self._hasAppliedSkill then
		self:updateInRunSkills()
		self:updateActiveSkills()
	else
		logger.logDebug(SUBMODULE, "Update all states: skipping In Run and Active")
	end
end

return skill_state_tracker
