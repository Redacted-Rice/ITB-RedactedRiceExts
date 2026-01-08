-- Shared test helpers for CPLUS+ Extension tests

local M = {}

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

-- Load the module
require("cplus_plus_ex")
M.plus_manager = cplus_plus_ex  -- Maintain compatibility with existing tests
local skill_config = M.plus_manager._modules.skill_config

-- Reset all state
function M.resetState()
	local pm = M.plus_manager
	local skill_registry = pm._modules.skill_registry
	local skill_config_module = pm._modules.skill_config
	local skill_constraints = pm._modules.skill_constraints
	local skill_selection = pm._modules.skill_selection
	local time_traveler = pm._modules.time_traveler
	
	-- Reset skill_registry module state
	skill_registry.registeredSkills = {}
	skill_registry.registeredSkillsIds = {}
	
	-- Reset skill_config module state
	skill_config_module.enabledSkills = {}
	skill_config_module.enabledSkillsIds = {}
	
	-- Reset skill_constraints module state
	skill_constraints.constraintFunctions = {}
	
	-- Reset skill_selection module state
	skill_selection.localRandomCount = nil
	skill_selection.usedSkillsPerRun = {}
	
	-- Reset time_traveler module state
	time_traveler.pilotStructs = nil
	time_traveler.lastSavedPersistentData = nil
	time_traveler.timeTraveler = nil

	-- Reset config structure (owned by skill_config module)
	skill_config.config.allowReusableSkills = true
	skill_config.config.autoAdjustWeights = true
	skill_config.config.pilotSkillExclusions = {}
	skill_config.config.pilotSkillInclusions = {}
	skill_config.config.skillExclusions = {}
	skill_config.config.skillDependencies = {}
	skill_config.config.skillConfigs = {}

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
	pm:initModules()
	
	-- Clear vanilla skills and enabled skills for test isolation
	-- Tests will register their own skills as needed
	skill_registry.registeredSkills = {}
	skill_registry.registeredSkillsIds = {}
	skill_config_module.enabledSkills = {}
	skill_config_module.enabledSkillsIds = {}
	skill_config.config.skillConfigs = {}
end

-- Create a minimal mock pilot struct
function M.createMockPilot(pilotId)
	return {
		getIdStr = function(self)
			return pilotId
		end
	}
end

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
