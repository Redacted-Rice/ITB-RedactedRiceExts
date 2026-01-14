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

-- Mock memhack.hooks for tests
_G.memhack = _G.memhack or {}
_G.memhack.hooks = _G.memhack.hooks or {
	fireOnPilotLevelChanged = {}
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
	local pilot_bonus_combiner = pm._modules.pilot_bonus_combiner

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

-- Create a mock skill with all required methods
-- Optional params: skillId, coresBonus, gridBonus, saveVal
function M.createMockSkill(params)
	params = params or {}
	return {
		_id = params.skillId or "",
		_cores_bonus = params.coresBonus or 0,
		_grid_bonus = params.gridBonus or 0,
		_save_val = params.saveVal or 0,
		getIdStr = function(self) return self._id end,
		getCoresBonus = function(self) return self._cores_bonus end,
		getGridBonus = function(self) return self._grid_bonus end,
		getSaveVal = function(self) return self._save_val end,
		setCoresBonus = function(self, value) self._cores_bonus = value end,
		setGridBonus = function(self, value) self._grid_bonus = value end,
		setSaveVal = function(self, value) self._save_val = value end,
	}
end

-- Create a mock lvl up skills array with two skills
-- Can optionally pass in existing skill mocks, otherwise creates new ones
function M.createMockLvlUpSkills(skill1, skill2)
	local mockSkill1 = skill1 or M.createMockSkill()
	local mockSkill2 = skill2 or M.createMockSkill()

	return {
		_skill1 = mockSkill1,
		_skill2 = mockSkill2,
		getSkill1 = function(self) return self._skill1 end,
		getSkill2 = function(self) return self._skill2 end,
	}
end

-- Create a minimal mock pilot struct
-- Optional params: pilotId, level, lvlUpSkills
-- Can be called with a string (pilotId) or table with params
function M.createMockPilot(params)
	-- Handle string argument (just pilot ID)
	if type(params) == "string" then
		params = {pilotId = params}
	end
	params = params or {}
	local pilotId = params.pilotId or params[1] or "MockPilot"
	local level = params.level or 0
	local mockLvlUpSkills = params.lvlUpSkills or M.createMockLvlUpSkills()

	return {
		_id = pilotId,
		_level = level,
		_lvlUpSkills = mockLvlUpSkills,
		getIdStr = function(self) return self._id end,
		getLevel = function(self) return self._level end,
		getLvlUpSkills = function(self) return self._lvlUpSkills end,
		setLvlUpSkill = function(self, skillNum, skillId, shortName, fullName, description, saveVal, bonuses)
			-- Store skill info in the appropriate mock skill
			local skill = (skillNum == 1) and mockLvlUpSkills._skill1 or mockLvlUpSkills._skill2
			skill._id = skillId
			skill._save_val = saveVal
			if bonuses then
				skill._cores_bonus = bonuses.cores or 0
				skill._grid_bonus = bonuses.grid or 0
			end
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

-- Create a complete mock pilot with skill tracking for testing skill application
-- Returns: pilot, tracking
-- Where tracking has:
--   - skill1SaveVal: the saveVal applied to skill slot 1
--   - skill2SaveVal: the saveVal applied to skill slot 2
--   - skill1: the mock skill object in slot 1
--   - skill2: the mock skill object in slot 2
function M.createMockPilotWithTracking(pilotId)
	pilotId = pilotId or "TestPilot"
	
	-- Create tracking object to store applied values
	local tracking = {
		skill1SaveVal = nil,
		skill2SaveVal = nil,
		skill1 = nil,
		skill2 = nil,
	}
	
	-- Create mock skills
	local mockSkill1 = M.createMockSkill()
	local mockSkill2 = M.createMockSkill()
	
	tracking.skill1 = mockSkill1
	tracking.skill2 = mockSkill2
	
	-- Override getSaveVal to return tracked values
	mockSkill1.getSaveVal = function() return tracking.skill1SaveVal or 0 end
	mockSkill2.getSaveVal = function() return tracking.skill2SaveVal or 1 end
	
	-- Create mock lvl up skills
	local mockLvlUpSkills = M.createMockLvlUpSkills(mockSkill1, mockSkill2)
	
	-- Create mock pilot
	local mockPilot = M.createMockPilot({
		pilotId = pilotId,
		level = 0,
		lvlUpSkills = mockLvlUpSkills
	})
	
	-- Override setLvlUpSkill to track applied saveVals
	mockPilot.setLvlUpSkill = function(self, index, id, shortName, fullName, description, saveVal, bonuses)
		local skill = (index == 1) and mockSkill1 or mockSkill2
		skill._id = id
		skill._save_val = saveVal
		if bonuses then
			skill._cores_bonus = bonuses.cores or 0
			skill._grid_bonus = bonuses.grid or 0
		end
		
		-- Track applied saveVals for assertions
		if index == 1 then
			tracking.skill1SaveVal = saveVal
		else
			tracking.skill2SaveVal = saveVal
		end
	end
	
	return mockPilot, tracking
end

return M
