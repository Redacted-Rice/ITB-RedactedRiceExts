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

-- Load the module
M.plus_manager = require("plus_manager")

-- Reset all plus_manager state
function M.resetState()
	local pm = M.plus_manager
	pm._registeredSkills = {}
	pm._registeredSkillsIds = {}
	pm._enabledSkills = {}
	pm._enabledSkillsIds = {}
	pm._pilotSkillExclusionsAuto = {}
	pm._pilotSkillExclusionsManual = {}
	pm._pilotSkillInclusions = {}
	pm._skillExclusions = {}
	pm._skillDependencies = {}
	pm._constraintFunctions = {}
	pm._localRandomCount = nil
	pm._usedSkillsPerRun = {}
	pm.allowReusableSkills = false

	GAME.cplus_plus_ex.pilotSkills = {}
	GAME.cplus_plus_ex.randomSeed = 12345
	GAME.cplus_plus_ex.randomSeedCnt = 0

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

-- Register and enable test skills
function M.setupTestSkills(skills)
	for _, skill in ipairs(skills) do
		M.plus_manager:registerSkill("test", skill)
	end
	M.plus_manager:enableCategory("test")
end

return M
