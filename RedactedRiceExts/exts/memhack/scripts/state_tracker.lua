--[[
	State Tracking for Memhack Structures

	This module provides utilities for:
	1. Capturing and comparing state of memory structures (for change detection)
	2. Tracking pilot and skill state changes
	3. Managing "set" vs "memory" values for skill bonuses (cores/grid combining)
--]]

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("Memhack", "StateTracker", memhack.DEBUG.STATE_TRACKER and memhack.DEBUG.ENABLED)

local stateTracker = {}

-- Pilot and skill state trackers
stateTracker._pilotTrackers = {}
stateTracker._skillTrackers = {}

-- Track "set" values for skill bonuses (cores/grid)
-- Maps skill address to {coresBonus = X, gridBonus = Y}
-- These are what external code sees when accessing skills
-- Actual memory may contain combined values based on pilot level
stateTracker._skillSetValues = {}

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
		local result = obj[valOrGetter](obj)
		return result
	else
		-- Assume it's a field name, use standard getter
		local getterName = StructManager.makeStdGetterName(valOrGetter)
		if type(obj[getterName]) ~= "function" then
			error(string.format("Getter '%s' not found on object for field '%s'", getterName, valOrGetter))
		end
		local result = obj[getterName](obj)
		return result
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

-- Check for level up skill changes on a pilot and fire hooks if changes detected
function stateTracker.checkForLvlUpSkillChanges(pilot)
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
						memhack._subobjects.hooks.firePilotLvlUpSkillChangedHooks(skill, changes)
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
				memhack._subobjects.hooks.firePilotChangedHooks(pilot, changes)
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

-- Build a re-entrant wrapper for a hook fire function
-- This handles re-entrant calls (hooks called during hook execution) by:
-- 1. Setting a flag when re-entrant call is detected
-- 2. Completing all current hooks first
-- 3. Re-capturing state and firing again if flag was set
--
-- Args:
--   hookName: Name of the hook (e.g., "PilotChanged")
--   stateDef: State definition for capturing state
--   tracker: The tracker table (_pilotTrackers or _skillTrackers)
function stateTracker.buildReentrantHookWrapper(hookName, stateDef, tracker)
	-- Track if we're currently executing and if changes occurred during execution
	local isExecuting = false
	local changesPending = false
	local fireHookName = "fire"..hookName.."Hooks"
	local rawFireFn = memhack._subobjects.hooks[fireHookName]
	-- arbitrary number of iterations to prevent infinite loops
	local MAX_ITERATIONS = 20

	return function(obj, changes)
		-- If there are not changes, bail now
		if not changes or not next(changes) then
			return
		-- If we're already executing, just mark that changes happened
		elseif isExecuting then
			changesPending = true
			return
		end

		-- Mark that we're executing so we can detect re-entrant calls
		isExecuting = true


		-- Update the tracked state before calling the hooks. This prevents the
		-- tracker from detecting and firing changes a second time and this also
		-- lets us compare state afterward to see what changes were made by
		-- re-entrant calls
		local objAddr = obj:getAddress()
		tracker[objAddr] = stateTracker.captureState(obj, stateDef)

		local iteration = 0
		while changes and next(changes) do
			iteration = iteration + 1
			-- Check for max iterations specifically so we can detect if we finished
			-- or ran out of iterations
			if iteration > MAX_ITERATIONS then
				isExecuting = false
				error(string.format(
					"%s exceeded max iterations (%d). Possible infinite loop in hook callbacks. Aborting",
					fireHookName, MAX_ITERATIONS
				))
				return
			end

			-- clear re-entrant flag and fire fns
			changesPending = false
			rawFireFn(obj, changes)

			-- if no changes were detected, we are done - state will
			-- match the previous tracked state so no need to update it
			if not changesPending then
				break
			end

			-- Re-entrant call detected, re-capture state, find the changes,
			-- and update the tracked state. If there actually is no change (e.g.
			-- it got changed then changed back) then it will break at the top
			-- of the loop check
			local oldState = tracker[objAddr]
			local newState = stateTracker.captureState(obj, stateDef)
			changes = stateTracker.compareStates(oldState, newState)
			tracker[objAddr] = newState
		end

		-- Clear executing flag
		isExecuting = false
	end
end

function stateTracker:wrapHooksToUpdateStateTrackers()
	-- Wrap pilot changed hook with re-entrant support
	memhack._subobjects.hooks.firePilotChangedHooks = stateTracker.buildReentrantHookWrapper(
		"PilotChanged",
		memhack.structs.Pilot.stateDefinition,
		stateTracker._pilotTrackers
	)

	-- Wrap skill changed hook with re-entrant support
	memhack._subobjects.hooks.firePilotLvlUpSkillChangedHooks = stateTracker.buildReentrantHookWrapper(
		"PilotLvlUpSkillChanged",
		memhack.structs.PilotLvlUpSkill.stateDefinition,
		stateTracker._skillTrackers
	)
end

return stateTracker
