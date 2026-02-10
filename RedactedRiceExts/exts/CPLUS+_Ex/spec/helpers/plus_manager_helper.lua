-- Shared test helpers for CPLUS+ Extension tests

local M = {}
local mocks = require("helpers/mocks")

-- Store original math.random function
local _originalMathRandom = math.random

-- Setup globals needed by the extension
function M.setupGlobals()
	_G.LOG = _G.LOG or function(msg) end

	_G.GetParentPath = _G.GetParentPath or function(modPath)
		return ""
	end

	-- Initialize memhack logging before CPLUS+ modules load
	if not _G.memhack then
		_G.memhack = {}
		_G.memhack.DEBUG = {
			ENABLED = true,
			HOOKS = true,
			STRUCTS = true,
			STATE_TRACKER = true,
			SCANNER = false,
		}
		-- Load logger from memhack using loadfile
		local loggingFile = "../memhack/utils/logging.lua"
		local loggingFunc, err = loadfile(loggingFile)
		if not loggingFunc then
			error("Failed to load memhack logger: " .. tostring(err))
		end
		_G.memhack.logger = loggingFunc()
	end

	-- Mock modApi events
	_G.modApi = _G.modApi or {}
	_G.modApi.events = _G.modApi.events or {}
	_G.modApi.events.onPodWindowShown = { subscribe = function() end }
	_G.modApi.events.onPerfectIslandWindowShown = { subscribe = function() end }
	_G.modApi.events.onGameEntered = { subscribe = function() end }
	_G.modApi.events.onGameExited = { subscribe = function() end }
	_G.modApi.events.onGameVictory = { subscribe = function() end }
	_G.modApi.events.onMainMenuEntered = { subscribe = function() end }
	_G.modApi.events.onHangarEntered = { subscribe = function() end }
	_G.modApi.events.onModsFirstLoaded = { subscribe = function() end }
	_G.modApi.events.onModsLoaded = { subscribe = function() end }
	_G.modApi.scheduleHook = function() end
	_G.modApi.addSaveGameHook = function() end

	_G.Event = _G.Event or function() return {dispatch = function() end} end
	_G.Game = _G.Game or {}
	_G.Board = nil

	_G.sdlext = _G.sdlext or {
		addModContent = function() end
	}

	_G.GAME = {
		cplus_plus_ex = {
			pilotSkills = {},
			randomSeed = 12345,
			randomSeedCnt = 0
		}
	}
end

-- Stub memhack with minimal API needed by CPLUS+
function M.stubMemhack()
	-- Preserve memhack.logger if it was set up
	local logger = _G.memhack and _G.memhack.logger
	local DEBUG = _G.memhack and _G.memhack.DEBUG

	local Event = _G.Event
	_G.memhack = {
		logger = logger,  -- Preserve logger
		DEBUG = DEBUG,      -- Preserve DEBUG config
		hooks = {
			events = {
				onPilotChanged = Event(),
				onPilotLvlUpSkillChanged = Event(),
			},
			addTo = function(hookTbl, owner, debugId)
				hookTbl.events = hookTbl.events or {}
				for _, name in ipairs(hookTbl) do
					local Name = name:gsub("^.", string.upper)
					local hookId = name.."Hooks"
					local eventId = "on"..Name
					local addHook = "add"..Name.."Hook"

					hookTbl.events[eventId] = _G.Event()
					hookTbl[hookId] = {}
					hookTbl[addHook] = function(self, fn)
						table.insert(self[hookId], fn)
					end

					if owner then
						owner[addHook] = function(self, fn)
							return hookTbl[addHook](hookTbl, fn)
						end
					end
				end
			end,
			reload = function(hookTbl, debugId) end,
			buildBroadcastFunc = function(hooksField, tbl, argsFunc, parentsToPrepend, debugId)
				return function(...)
					local hooks = tbl[hooksField]
					if hooks then
						for _, hook in ipairs(hooks) do
							pcall(hook, ...)
						end
					end
				end
			end,
		},
		-- Stub hook registration functions
		addPilotChangedHook = function(self, fn) end,
		addPilotLvlUpSkillChangedHook = function(self, fn) end,
	}
end

-- Initialize CPLUS+ extension
M.setupGlobals()
M.stubMemhack()

require("cplus_plus_ex")
M.plus_manager = cplus_plus_ex
M.plus_manager:initModules()
M.plus_manager:exposeAPI()

-- Reset all state
function M.resetState()
	local pm = M.plus_manager

	-- First, completely reset Game and Board to prevent any lingering state
	_G.Game = {
		GetAvailablePilots = function() return {} end,
		GetSquadPilots = function() return {} end
	}
	_G.Board = nil

	GAME.cplus_plus_ex.pilotSkills = {}
	GAME.cplus_plus_ex.randomSeed = 12345
	GAME.cplus_plus_ex.randomSeedCnt = 0

	-- Restore original math.random and reseed
	M.restoreMathRandom()
	math.randomseed(12345)

	-- Clear test pilots from _G
	for key in pairs(_G) do
		if type(key) == "string" and key:match("^Pilot_Test") then
			_G[key] = nil
		end
	end

	-- Re-initialize modules (registers constraints, vanilla skills, etc.)
	-- Note: This calls skill_state_tracker:load() which calls updateAllStates()
	-- so Game/Board MUST be reset before this
	pm:initModules()

	-- Now access modules after they've been initialized
	local skill_registry = pm._subobjects.skill_registry
	local skill_config_module = pm._subobjects.skill_config
	local skill_constraints = pm._subobjects.skill_constraints
	local skill_selection = pm._subobjects.skill_selection
	local time_traveler = pm._subobjects.time_traveler
	local skill_state_tracker = pm._subobjects.skill_state_tracker

	-- Reset skill_registry module state
	skill_registry.registeredSkills = {}

	-- Reset skill_config module state
	skill_config_module.enabledSkills = {}
	skill_config_module.enabledSkillsIds = {}

	-- Reset skill_constraints module state
	skill_constraints.constraintFunctions = {}
	-- Re-register built-in constraint functions after clearing
	skill_constraints:registerReusabilityConstraintFunction()
	skill_constraints:registerPlusExclusionInclusionConstraintFunction()
	skill_constraints:registerSkillExclusionConstraintFunction()

	-- Reset skill_selection module state
	skill_selection.localRandomCount = nil
	skill_selection.usedSkillsPerRun = {}

	-- Reset time_traveler module state
	time_traveler.squadPilots = nil
	time_traveler.lastSavedPersistentData = nil
	time_traveler.timeTraveler = nil

	-- Reset skill_state_tracker module state after initModules to override any state
	-- that may have been set
	skill_state_tracker._enabledSkills = {}
	skill_state_tracker._inRunSkills = {}
	skill_state_tracker._activeSkills = {}

	-- Reset skill_selection assignment tracking
	skill_selection._pilotsAssignedThisRun = {}
	skill_selection.usedSkillsPerRun = {}
	skill_selection.localRandomCount = nil

	-- Reset hooks module state to clear any added during tests
	local hooks_module = pm.hooks
	hooks_module.skillEnabledHooks = {}
	hooks_module.skillInRunHooks = {}
	hooks_module.skillActiveHooks = {}
	hooks_module.preAssigningLvlUpSkillsHooks = {}
	hooks_module.postAssigningLvlUpSkillsHooks = {}
	hooks_module.skillsSelectedHooks = {}
	hooks_module:initBroadcastHooks(hooks_module)

	-- Reset config structure (owned by skill_config module)
	pm.config.allowReusableSkills = true
	pm.config.pilotSkillExclusions = {}
	pm.config.pilotSkillInclusions = {}
	pm.config.skillExclusions = {}
	pm.config.skillConfigs = {}

	-- Clear vanilla skills and enabled skills for test isolation
	-- Tests will register their own skills as needed
	skill_registry.registeredSkills = {}
	skill_config_module.enabledSkills = {}
	skill_config_module.enabledSkillsIds = {}
	pm.config.skillConfigs = {}
end

-- Re-export mock functions from mocks module
M.createMockSkill = mocks.createMockSkill
M.createMockLvlUpSkills = mocks.createMockLvlUpSkills
M.createMockPilot = mocks.createMockPilot
M.createMockPilotWithTracking = mocks.createMockPilotWithTracking

-- Register test skills which also enables them
function M.setupTestSkills(skills)
	for _, skill in ipairs(skills) do
		M.plus_manager:registerSkill("test", skill)
	end
end

-- Mock math.random to return predetermined values
-- Takes an array of values to return in sequence
function M.mockMathRandom(values)
	local index = 1
	math.random = function(...)
		if index <= #values then
			local value = values[index]
			index = index + 1
			return value
		else
			-- return nil to make sure we are aware we ran out of values
			-- as this could cause unexpected test behavior
			return nil
		end
	end
end

-- Restore original math.random function
function M.restoreMathRandom()
	math.random = _originalMathRandom
end

-- Clean up all globals set by CPLUS+ tests to prevent pollution
-- Call this after all CPLUS+ tests complete
function M.cleanupGlobals()
	-- Remove CPLUS+ globals
	_G.cplus_plus_ex = nil
	_G.GAME = nil
	_G.Game = nil
	_G.Board = nil
	_G.modApi = nil
	_G.Event = nil
	_G.sdlext = nil
	_G.LOG = nil
	_G.GetParentPath = nil

	-- Remove memhack stub (critical for memhack tests to work)
	_G.memhack = nil

	-- Clear package.loaded for CPLUS+ modules to ensure fresh load next time
	for key in pairs(package.loaded) do
		if type(key) == "string" and (
			key:match("^cplus_plus") or
			key:match("^scripts%.") or
			key:match("^helpers%.")
		) then
			package.loaded[key] = nil
		end
	end
end

return M
