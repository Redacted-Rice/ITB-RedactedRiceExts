--[[
	Skill State Tracking for CPLUS+

	Tracks two states for each skill:
	1. InRun - skill is on any pilot in the run (and they're high enough level)
	2. Active - skill is on one of the 3 pilots in active mechs

	Integrates with memhack hooks to detect changes and fire appropriate skill hooks.
--]]

local skill_state_tracker = {}

-- Reference to owner (set during init)
local owner = nil

-- State tracking tables
skill_state_tracker._enabledSkills = {}  -- skillId -> true (skill is enabled in config)
skill_state_tracker._inRunSkills = {}    -- skillId -> {pilotAddr -> {pilot, skillIndices}} where skillIndices is array of 1 and/or 2
skill_state_tracker._activeSkills = {}   -- skillId -> {pawnId -> {pilot, skillIndices}}

skill_state_tracker.DEBUG = true

function skill_state_tracker:init(ownerRef)
	owner = ownerRef
	self.addEvents()
	return self
end

function skill_state_tracker:load()
	skill_state_tracker.addHooks()

	-- Perform initial state update
	skill_state_tracker.updateAllStates()
end

------------------ Helper functions ------------------

-- Check if a pilot is high enough level for the skill at the given index to be earned
local function hasPilotEarnedSkillIndex(pilot, skillIndex)
	if not pilot then return false end
	return pilot:getLevel() >= skillIndex
end

local function getPilotEarnedSkillIndexes(pilot)
	local pilotLevel = pilot:getLevel()
	local result = {}
	for skillIndex = 1, pilotLevel do
		table.insert(result, skillIndex)
	end
	return result
end

-- Check if a skill is on any pilot in the given list
-- pilots: list of pilots to check (defaults to all available pilots)
-- checkEarned: if true, only check earned skills (defaults to true)
function skill_state_tracker.isSkillOnPilots(skillId, pilots, checkEarned)
	if pilots == nil then
		if not Game then return false end
		pilots = Game:GetAvailablePilots()
	end
	if not pilots or #pilots == 0 then return false end

	if checkEarned == nil then checkEarned = true end
	for _, pilot in ipairs(pilots) do
		for skillIndex = 1, 2 do
			local skill = pilot:getLvlUpSkill(skillIndex)
			if skill and skill:getIdStr() == skillId then
				if not checkEarned then
					return true
				elseif hasPilotEarnedSkillIndex(pilot, skillIndex) then
					return true
				end
			end
		end
	end
	return false
end

-- Get all pilots from list that have this skill
-- pilots: list of pilots to check (defaults to all available pilots)
-- checkEarned: if true, only include earned skills (defaults to true)
-- Returns: list of {pilot, skillIndices} where skillIndices is array of skill slot numbers (1 and/or 2)
function skill_state_tracker.getPilotsWithSkill(skillId, pilots, checkEarned)
	if pilots == nil then
		if not Game then return {} end
		pilots = Game:GetAvailablePilots()
	end

	local result = {}
	if not pilots or #pilots == 0 then return result end

	if checkEarned == nil then checkEarned = true end
	for _, pilot in ipairs(pilots) do
		local skillIndices = {}

		for skillIndex = 1, 2 do
			local skill = pilot:getLvlUpSkill(skillIndex)

			if skill and skill:getIdStr() == skillId then
				if not checkEarned then
					table.insert(skillIndices, skillIndex)
				elseif hasPilotEarnedSkillIndex(pilot, skillIndex) then
					table.insert(skillIndices, skillIndex)
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
	end
	return result
end

-- Get which mechs have a specific skill
-- checkEarned: if true, only include earned skills (defaults to true)
-- Returns: list of {pawnId, pilot, skillIndices}
function skill_state_tracker.getMechsWithSkill(skillId, checkEarned)
	local mechs = {}
	if not Game then return mechs end

	if checkEarned == nil then checkEarned = true end
	local pilots = skill_state_tracker.getPilotsWithSkill(skillId, Game:GetSquadPilots(), checkEarned)
	for _, pilotData in ipairs(pilots) do
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
function skill_state_tracker.isSkillEnabled(skillId)
	return skill_state_tracker._enabledSkills[skillId] == true
end

-- Get all enabled skills
-- Returns: {skillId = true, ...}
function skill_state_tracker.getSkillsEnabled()
	return skill_state_tracker._enabledSkills
end

-- Update enabled skills state and fire hooks for changes
function skill_state_tracker.updateEnabledSkills()
	local newEnabledSkills = owner._modules.skill_config.getEnabledSkillsSet()

	-- Check for newly enabled skills
	for skillId in pairs(newEnabledSkills) do
		if not skill_state_tracker._enabledSkills[skillId] then
			if skill_state_tracker.DEBUG then
				LOG("CPLUS+ State Tracker: Skill " .. skillId .. " enabled - Firing hooks...")
			end
			owner.hooks.fireSkillEnabledHooks(skillId, true)
		end
	end

	-- Check for newly disabled skills
	for skillId in pairs(skill_state_tracker._enabledSkills) do
		if not newEnabledSkills[skillId] then
			if skill_state_tracker.DEBUG then
				LOG("CPLUS+ State Tracker: Skill " .. skillId .. " disabled - Firing hooks...")
			end
			owner.hooks.fireSkillEnabledHooks(skillId, false)
		end
	end

	-- Update state
	skill_state_tracker._enabledSkills = newEnabledSkills
end

-------------------- InRun Tracking --------------------

-- Check if a skill is in run at all (on available pilots, any level)
function skill_state_tracker.isSkillInRun(skillId)
	local inRun = skill_state_tracker._inRunSkills[skillId]
	return inRun ~= nil and next(inRun) ~= nil
end

-- Get skills in run (user-friendly format)
-- Returns: {skillId -> [{pilot, skillIndices}, ...], ...}
function skill_state_tracker.getSkillsInRun()
	local result = {}
	for skillId, pilots in pairs(skill_state_tracker._inRunSkills) do
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
function skill_state_tracker.determineInRunSkillsState()
	local result = {}
	if not Game then return result end

	-- Loop through pilots once and build state for all skills
	local availablePilots = Game:GetAvailablePilots()
	for _, pilot in ipairs(availablePilots) do
		local pilotAddr = pilot:getAddress()
		-- Check each skill slot
		for _, skillIndex in ipairs(getPilotEarnedSkillIndexes(pilot)) do
			local skillId = pilot:getLvlUpSkill(skillIndex):getIdStr()
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

	return result
end

-- Update in-run skills state and fire hooks for changes
function skill_state_tracker.updateInRunSkills()
	if not Game then
		-- No game active, clear all in-run skills
		skill_state_tracker._inRunSkills = {}
		return
	end

	-- Determine new in-run skills state (already in internal format)
	local newInRunSkills = skill_state_tracker.determineInRunSkillsState()

	-- Check for newly added pilots with skills
	for skillId, newPilots in pairs(newInRunSkills) do
		local oldPilots = skill_state_tracker._inRunSkills[skillId] or {}
		for pilotAddr, data in pairs(newPilots) do
			if not oldPilots[pilotAddr] then
				if skill_state_tracker.DEBUG then
					LOG(string.format("CPLUS+ State Tracker: Skill in-run added - %s (pilot: %s) - Firing hooks...", skillId, tostring(pilotAddr)))
				end
				-- Fire hook for each skill instance
				for _, skillIndex in ipairs(data.skillIndices) do
					local skill = data.pilot:getLvlUpSkill(skillIndex)
					owner.hooks.fireSkillInRunHooks(skillId, true, data.pilot, skill)
				end
			end
		end
	end

	-- Check for removed pilots with skills
	for skillId, oldPilots in pairs(skill_state_tracker._inRunSkills) do
		local newPilots = newInRunSkills[skillId] or {}
		for pilotAddr, data in pairs(oldPilots) do
			if not newPilots[pilotAddr] then
				if skill_state_tracker.DEBUG then
					LOG(string.format("CPLUS+ State Tracker: Skill in-run removed - %s (pilot: %s) - Firing hooks...", skillId, tostring(pilotAddr)))
				end
				-- Fire hook for each skill instance
				for _, skillIndex in ipairs(data.skillIndices) do
					local skill = data.pilot:getLvlUpSkill(skillIndex)
					owner.hooks.fireSkillInRunHooks(skillId, false, data.pilot, skill)
				end
			end
		end
	end

	-- Update state
	skill_state_tracker._inRunSkills = newInRunSkills
end

-------------------- Active/Inactive Tracking --------------------

-- Check if a skill is currently active (on one of the 3 active mechs)
function skill_state_tracker.isSkillActive(skillId)
	local active = skill_state_tracker._activeSkills[skillId]
	return active ~= nil and next(active) ~= nil
end

-- Get active skills (user-friendly format)
-- Returns: {skillId -> [{pawnId, pilot, skillIndices}, ...], ...}
function skill_state_tracker.getSkillsActive()
	local result = {}
	for skillId, mechs in pairs(skill_state_tracker._activeSkills) do
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
function skill_state_tracker.determineActiveSkillsState()
	local result = {}
	if not Game or not Board then return result end

	-- Loop through squad pilots once and build state for all skills
	local squadPilots = Game:GetSquadPilots()
	for _, pilot in ipairs(squadPilots) do
		local pawnId = pilot:getPawnId()
		-- Check each skill slot
		for _, skillIndex in ipairs(getPilotEarnedSkillIndexes(pilot)) do
			local skillId = pilot:getLvlUpSkill(skillIndex):getIdStr()
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

	return result
end

-- Update active skills state and fire hooks for changes
function skill_state_tracker.updateActiveSkills()
	if not Game or not Board then
		-- No game active or no board, clear all active skills
		skill_state_tracker._activeSkills = {}
		return
	end

	-- Determine new active skills state (already in internal format)
	local newActiveSkills = skill_state_tracker.determineActiveSkillsState()

	-- Check for newly active skills
	for skillId, newMechs in pairs(newActiveSkills) do
		local oldMechs = skill_state_tracker._activeSkills[skillId] or {}
		for pawnId, data in pairs(newMechs) do
			if not oldMechs[pawnId] then
				if skill_state_tracker.DEBUG then
					LOG(string.format("CPLUS+ State Tracker: Skill active added - %s (pawnId: %s) - Firing hooks...", skillId, tostring(pawnId)))
				end
				-- Fire hook for each skill instance
				for _, skillIndex in ipairs(data.skillIndices) do
					local skill = data.pilot:getLvlUpSkill(skillIndex)
					owner.hooks.fireSkillActiveHooks(skillId, true, pawnId, data.pilot, skill)
				end
			end
		end
	end

	-- Check for newly inactive skills
	for skillId, oldMechs in pairs(skill_state_tracker._activeSkills) do
		local newMechs = newActiveSkills[skillId] or {}
		for pawnId, data in pairs(oldMechs) do
			if not newMechs[pawnId] then
				if skill_state_tracker.DEBUG then
					LOG(string.format("CPLUS+ State Tracker: Skill active removed - %s (pawnId: %s) - Firing hooks...", skillId, tostring(pawnId)))
				end
				-- Fire hook for each skill instance
				for _, skillIndex in ipairs(data.skillIndices) do
					local skill = data.pilot:getLvlUpSkill(skillIndex)
					owner.hooks.fireSkillActiveHooks(skillId, false, pawnId, data.pilot, skill)
				end
			end
		end
	end

	-- Update state
	skill_state_tracker._activeSkills = newActiveSkills
end

-------------------- State Update Orchestration --------------------

-- Update all skill states (called from various triggers)
function skill_state_tracker.updateAllStates()
	skill_state_tracker.updateEnabledSkills()
	skill_state_tracker.updateInRunSkills()
	skill_state_tracker.updateActiveSkills()
end

-------------------- Event and Hook Registration --------------------

function skill_state_tracker.addEvents()
	-- Update when entering/exiting game (clean up state)
	modApi.events.onGameEntered:subscribe(function()
		skill_state_tracker.updateAllStates()
	end)

	modApi.events.onGameExited:subscribe(function()
		skill_state_tracker.updateAllStates()
	end)
end

function skill_state_tracker.addHooks()
	-- Update when game is saved (covers level ups, xp gains)
	modApi:addSaveGameHook(function()
		skill_state_tracker.updateAllStates()
	end)

	-- When pilot changes, check if skills became in-run or active/inactive
	memhack:addPilotChangedHook(function(pilot, changes)
		-- Check if level changed. This is the only change that will affect skill availability
		if changes.level then
			skill_state_tracker.updateAllStates()
		end
	end)

	-- When a skill changes, update in-run and active states
	memhack:addPilotLvlUpSkillChangedHook(function(pilot, skill, changes)
		skill_state_tracker.updateAllStates()
	end)
end

return skill_state_tracker
