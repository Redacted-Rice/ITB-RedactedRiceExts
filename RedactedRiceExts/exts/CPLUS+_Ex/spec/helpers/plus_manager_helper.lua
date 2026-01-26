-- Shared test helpers for CPLUS+ Extension tests

local M = {}
local mocks = require("helpers/mocks")

-- Mock external dependencies
_G.LOG = function(msg) end
_G.GAME = {
	cplus_plus_ex = {
		pilotSkills = {},
		randomSeed = 12345,
		randomSeedCnt = 0
	}
}

-- Store original math.random function
local _originalMathRandom = math.random

-- Mock modApi for tests
_G.modApi = _G.modApi or {}
_G.modApi.events = _G.modApi.events or {}
_G.modApi.events.onPodWindowShown = {
	subscribe = function(self, callback) end
}
_G.modApi.events.onPerfectIslandWindowShown = {
	subscribe = function(self, callback) end
}
_G.modApi.scheduleHook = function(self, delay, callback)
	-- Mock implementation - do nothing, as executing the callback would require full UI libraries
	-- Tests should not be showing error dialogs anyway
end

-- Mock memhack.hooks for tests
_G.memhack = _G.memhack or {}
_G.memhack.hooks = _G.memhack.hooks or {}
_G.memhack.hooks.events = _G.memhack.hooks.events or {
	onPilotChanged = {
		subscribe = function(self, callback) end
	},
	onPilotLvlUpSkillChanged = {
		subscribe = function(self, callback) end
	}
}

-- Load the module
require("cplus_plus_ex")
M.plus_manager = cplus_plus_ex
-- Initialize modules so _modules table is available
M.plus_manager:initModules("")

-- Reset all state
function M.resetState()
	local pm = M.plus_manager

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
	pm:initModules("")

	-- Now access modules after they've been initialized
	local skill_registry = pm._modules.skill_registry
	local skill_config_module = pm._modules.skill_config
	local skill_constraints = pm._modules.skill_constraints
	local skill_selection = pm._modules.skill_selection
	local time_traveler = pm._modules.time_traveler

	-- Reset skill_registry module state
	skill_registry.registeredSkills = {}

	-- Reset skill_config module state
	skill_config_module.enabledSkills = {}
	skill_config_module.enabledSkillsIds = {}

	-- Reset skill_constraints module state
	skill_constraints.constraintFunctions = {}
	-- Re-register built-in constraint functions after clearing
	skill_constraints.registerReusabilityConstraintFunction()
	skill_constraints.registerPlusExclusionInclusionConstraintFunction()
	skill_constraints.registerSkillExclusionDependencyConstraintFunction()

	-- Reset skill_selection module state
	skill_selection.localRandomCount = nil
	skill_selection.usedSkillsPerRun = {}

	-- Reset time_traveler module state
	time_traveler.pilotStructs = nil
	time_traveler.lastSavedPersistentData = nil
	time_traveler.timeTraveler = nil

	-- Reset config structure (owned by skill_config module)
	pm.config.allowReusableSkills = true
	pm.config.autoAdjustWeights = true
	pm.config.pilotSkillExclusions = {}
	pm.config.pilotSkillInclusions = {}
	pm.config.skillExclusions = {}
	pm.config.skillDependencies = {}
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

return M
