--[[
	State Tracking for Memhack Structures

	This module provides utilities for:
	1. Capturing and comparing state of memory structures (for change detection)
	2. Tracking pilot and skill state changes
	3. Managing "set" vs "memory" values for skill bonuses (cores/grid combining)
--]]

local stateTracker = {}

-- Pilot and skill state trackers
stateTracker._pilotTrackers = {}
stateTracker._skillTrackers = {}

-- Track "set" values for skill bonuses (cores/grid)
-- Maps skill address to {coresBonus = X, gridBonus = Y}
-- These are what external code sees when accessing skills
-- Actual memory may contain combined values based on pilot level
stateTracker._skillSetValues = {}

stateTracker.init = function()
	stateTracker.registerTriggerEvents()
	-- hooks wrapped explicitly in memhack.lua
	return stateTracker
end

stateTracker.load = function()
	stateTracker.registerTriggerHooks()
end

-------------------- State Capture and Comparison --------------------

-- Capture a single value from an object using either:
-- - A field name which will use standard getter
-- - A custom getter function name
function stateTracker.captureValue(obj, valOrGetter)
	if not obj then
		error("obj cannot be nil")
	end

	if type(valOrGetter) ~= "string" then
		error("valOrGetter must be a string (field name or getter function name)")
	end

	-- Check if it's a function name or field name
	if type(obj[valOrGetter]) == "function" then
		return obj[valOrGetter](obj)
	else
		-- Assume it's a field name, use standard getter
		local getterName = StructManager.makeStdGetterName(valOrGetter)
		if type(obj[getterName]) ~= "function" then
			error(string.format("Getter '%s' not found on object for field '%s'", getterName, valOrGetter))
		end
		return obj[getterName](obj)
	end
end

-- TODO: Optimize reading for a whole object capture? Maybe more effort than its worth

-- Capture state from an object based on a state definition
-- stateDefinition format:
--   - Array entries (numeric keys): field names to capture using standard getters
--   - Table entries with string values: fieldName = "customGetterName"
-- valsToCheck: optional table of field names to check (if nil, checks all)
function stateTracker.captureState(obj, stateDefinition, valsToCheck)
	local capturedState = {}

	if not stateDefinition then
		return capturedState
	end

	for key, value in pairs(stateDefinition) do
		local fieldName
		local getterName

		-- Array-style entry - just a field name and use it to get the standard getter
		if type(key) == "number" then
			fieldName = value
			getterName = StructManager.makeStdGetterName(fieldName)
		-- Map-style entry: field name with custom getter info
		else
			fieldName = key
			getterName = value
		end

		-- Only capture if we're checking this field (or checking all as in valsToCheck is nil)
		if not valsToCheck or valsToCheck[fieldName] then
			if type(obj[getterName]) == "function" then
				capturedState[fieldName] = obj[getterName](obj)
			else
				error(string.format("Getter '%s' not found on object for field '%s'", getterName, fieldName))
			end
		end
	end

	return capturedState
end

-- Compare two state tables and return changed fields
-- Note: Compares by reference NOT content - if there is a table, it will not check or
-- detect if it has changed content but ONLY if its the SAME REFERENCE
-- checkRemoved - If nil or true detect removed fields. If false, only checks fields
--		in newState (any other in oldState not in new state are ignored)
function stateTracker.compareStates(oldState, newState, checkRemoved)
	-- Default to true (detect removed fields by default)
	if checkRemoved == nil then
		checkRemoved = true
	end

	local changes = {}

	-- Check for changed or new values
	for fieldName, newValue in pairs(newState) do
		local oldValue = oldState[fieldName]
		if oldValue ~= newValue then
			changes[fieldName] = {
				old = oldValue,
				new = newValue
			}
		end
	end

	-- Check for removed fields if specified or by default
	if checkRemoved then
		for fieldName, oldValue in pairs(oldState) do
			if newState[fieldName] == nil then
				changes[fieldName] = {
					old = oldValue,
					new = nil
				}
			end
		end
	end

	return changes
end

--------- Skill Set Value Tracking (for cores/grid bonus combining) ----------------

-- Get set value for a skill bonus field
-- Returns the set value if tracked, otherwise returns the actual memory value
-- and initializes the set value tracker with it
function stateTracker.getSkillSetValue(skill, field)
	local skillAddr = skill:getAddress()
	local setVals = stateTracker._skillSetValues[skillAddr]

	if setVals and setVals[field] ~= nil then
		return setVals[field]
	end

	-- No set value tracked, get from memory and initialize tracking
	-- Use the raw memory getter (hidden getter with _ prefix)
	local rawGetterName = "_" .. memhack.structManager.makeStdGetterName(field)
	local memoryValue = skill[rawGetterName](skill)

	-- Initialize set value from memory
	stateTracker.setSkillSetValue(skill, field, memoryValue)

	return memoryValue
end

-- Set tracked value for a skill bonus field
-- This tracks what external code should see when accessing this field
function stateTracker.setSkillSetValue(skill, field, value)
	local skillAddr = skill:getAddress()

	if not stateTracker._skillSetValues[skillAddr] then
		stateTracker._skillSetValues[skillAddr] = {}
	end

	stateTracker._skillSetValues[skillAddr][field] = value
end

-- Get all set values for a skill
-- Returns table with coresBonus and gridBonus (or actual values if not tracked)
function stateTracker.getSkillSetValues(skill)
	return {
		coresBonus = stateTracker.getSkillSetValue(skill, "coresBonus"),
		gridBonus = stateTracker.getSkillSetValue(skill, "gridBonus")
	}
end

-- Cleanup stale skill set value trackers
-- Called by hooks system when pilots/skills are removed
function stateTracker.cleanupStaleSkillSetValues(activeSkills)
	for addr in pairs(stateTracker._skillSetValues) do
		if not activeSkills[addr] then
			stateTracker._skillSetValues[addr] = nil
		end
	end
end

-------------------- Pilot and Skill State Change Tracking ---------------------

-- Capture and update pilot state in tracker
function stateTracker.capturePilotState(pilot)
	if not pilot then return end

	local pilotAddr = pilot:getAddress()
	if memhack.structs and memhack.structs.Pilot and memhack.structs.Pilot.stateDefinition then
		stateTracker._pilotTrackers[pilotAddr] = stateTracker.captureState(
			pilot, memhack.structs.Pilot.stateDefinition)
	end
end

-- Capture and update skill state in tracker
function stateTracker.captureSkillState(skill)
	if not skill then return end

	local skillAddr = skill:getAddress()
	if memhack.structs and memhack.structs.PilotLvlUpSkill and memhack.structs.PilotLvlUpSkill.stateDefinition then
		stateTracker._skillTrackers[skillAddr] = stateTracker.captureState(
			skill, memhack.structs.PilotLvlUpSkill.stateDefinition)
	end
end

-- Check for level up skill changes on a pilot and fire hooks if changes detected
function stateTracker.checkForLvlUpSkillChanges(pilot)
	if not memhack.structs.PilotLvlUpSkill or not memhack.structs.PilotLvlUpSkill.stateDefinition then
		return
	end

	local lvlUpSkills = pilot:getLvlUpSkills()
	if lvlUpSkills then
		for i = 1, 2 do
			local skill = pilot:getLvlUpSkill(i)
			if skill then
				local skillAddr = skill:getAddress()
				local oldState = stateTracker._skillTrackers[skillAddr]
				local newState = stateTracker.captureState(skill, memhack.structs.PilotLvlUpSkill.stateDefinition)

				if oldState then
					-- Compare states and fire hook if changed
					local changes = stateTracker.compareStates(oldState, newState)
					if next(changes) then
						-- Call into hooks to fire
						memhack.hooks.firePilotLvlUpSkillChangedHooks(skill, changes)
					end
				end
				-- Update tracked state
				stateTracker._skillTrackers[skillAddr] = newState
			end
		end
	end
end

-- Check for pilot and skill changes and fire hooks if detected
function stateTracker.checkForPilotAndLvlUpSkillChanges()
	if not Game then return end
	if not memhack.structs.Pilot or not memhack.structs.Pilot.stateDefinition then return end

	local pilots = Game:GetSquadPilots()
	for _, pilot in ipairs(pilots) do
		local pilotAddr = pilot:getAddress()

		-- First check for skill changes
		stateTracker.checkForLvlUpSkillChanges(pilot)

		-- Check pilot changes
		local oldState = stateTracker._pilotTrackers[pilotAddr]
		local newState = stateTracker.captureState(pilot, memhack.structs.Pilot.stateDefinition)

		if oldState then
			-- Compare states and fire hook if changed
			local changes = stateTracker.compareStates(oldState, newState)
			if next(changes) then
				-- Call into hooks to fire
				memhack.hooks.firePilotChangedHooks(pilot, changes)
			end
		end

		-- Update tracked state
		stateTracker._pilotTrackers[pilotAddr] = newState
	end
end

-- Check for state changes in pilots and skills (main entry point)
function stateTracker.checkForStateChanges()
	stateTracker.checkForPilotAndLvlUpSkillChanges()
end

------------------ State tracking management -------------------

-- Clean up stale state trackers to prevent memory leaks
-- Removes trackers for pilots/skills that no longer exist
function stateTracker.cleanupStaleTrackers()
	if not Game then
		-- No game active, clear all trackers
		stateTracker._pilotTrackers = {}
		stateTracker._skillTrackers = {}
		stateTracker.cleanupStaleSkillSetValues({})
		return
	end

	-- Build set of currently active addresses
	local activePilots = {}
	local activeSkills = {}

	local pilots = Game:GetSquadPilots()
	for _, pilot in ipairs(pilots) do
		local pilotAddr = pilot:getAddress()
		activePilots[pilotAddr] = true

		-- Also track this pilot's skills
		local lvlUpSkills = pilot:getLvlUpSkills()
		if lvlUpSkills then
			for i = 1, 2 do
				local skill = pilot:getLvlUpSkill(i)
				if skill then
					activeSkills[skill:getAddress()] = true
				end
			end
		end
	end

	-- Remove stale pilot trackers
	for addr in pairs(stateTracker._pilotTrackers) do
		if not activePilots[addr] then
			stateTracker._pilotTrackers[addr] = nil
		end
	end

	-- Remove stale skill trackers
	for addr in pairs(stateTracker._skillTrackers) do
		if not activeSkills[addr] then
			stateTracker._skillTrackers[addr] = nil
		end
	end

	-- Remove stale skill set value trackers
	stateTracker.cleanupStaleSkillSetValues(activeSkills)
end

function stateTracker.wrapHooksToUpdateStateTrackers()
	-- Build the raw broadcast functions
	local rawFirePilotChanged = memhack.hooks.firePilotChangedHooks
	local rawFireSkillChanged = memhack.hooks.firePilotLvlUpSkillChangedHooks

	-- Wrap to capture state after firing to prevents double firing from state tracking
	memhack.hooks.firePilotChangedHooks = function(pilot, changes)
		rawFirePilotChanged(pilot, changes)
		stateTracker.capturePilotState(pilot)
	end
	memhack.hooks.firePilotLvlUpSkillChangedHooks = function(skill, changes)
		rawFireSkillChanged(skill, changes)
		stateTracker.captureSkillState(skill)
	end
end

function stateTracker.registerTriggerHooks()
	-- Should cover general level ups and earning of xp
	modApi:addSaveGameHook(function()
		stateTracker.checkForStateChanges()
	end)
end

function stateTracker.registerTriggerEvents()
	-- should cover adding levels/xp via console
	modApi.events.onConsoleToggled:subscribe(function()
		stateTracker.checkForStateChanges()
	end)

	-- Clean up stale trackers when a new game is started or ended
	modApi.events.onGameEntered:subscribe(function()
		stateTracker.cleanupStaleTrackers()
	end)
	modApi.events.onGameExited:subscribe(function()
		stateTracker.cleanupStaleTrackers()
	end)
	modApi.events.onGameVictory:subscribe(function()
		stateTracker.cleanupStaleTrackers()
	end)
end

return stateTracker
