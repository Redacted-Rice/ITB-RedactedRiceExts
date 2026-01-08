-- Shared test helpers for plus_manager tests

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
M.plus_manager = require("plus_manager")

-- Reset all plus_manager state
function M.resetState()
	local pm = M.plus_manager
	pm._registeredSkills = {}
	pm._registeredSkillsIds = {}
	pm._enabledSkills = {}
	pm._enabledSkillsIds = {}
	pm._constraintFunctions = {}
	pm._localRandomCount = nil
	pm._usedSkillsPerRun = {}

	-- Reset config structure
	pm.config = {
		allowReusableSkills = true,
		autoAdjustWeights = true,
		pilotSkillExclusions = {},
		pilotSkillInclusions = {},
		skillExclusions = {},
		skillDependencies = {},
		skillConfigs = {},
	}

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
