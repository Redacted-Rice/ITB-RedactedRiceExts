-- Unit tests for PLUS extension skill assignment and constraint system
-- Run with: busted tests/cplus_plus_ex_spec.lua

-- Mock external dependencies that cplus_plus_ex needs
_G.LOG = function(msg) end  -- Silent logging for tests
_G.GAME = {
	cplus_plus_ex = {
		pilotSkills = {},
		randomSeed = 12345,
		randomSeedCnt = 0
	}
}

-- Load the module
package.path = package.path .. ";../scripts/?.lua"
require("cplus_plus_ex")

describe("PLUS Extension", function()
	-- Reset state before each test
	before_each(function()
		-- Reset cplus_plus_ex state
		cplus_plus_ex._registeredSkills = {}
		cplus_plus_ex._registeredSkillsIds = {}
		cplus_plus_ex._enabledSkills = {}
		cplus_plus_ex._enabledSkillsIds = {}
		cplus_plus_ex._pilotSkillExclusionsAuto = {}
		cplus_plus_ex._pilotSkillExclusionsManual = {}
		cplus_plus_ex._pilotSkillInclusions = {}
		cplus_plus_ex._constraintFunctions = {}
		cplus_plus_ex._localRandomCount = nil

		-- Reset GAME state
		GAME.cplus_plus_ex.pilotSkills = {}
		GAME.cplus_plus_ex.randomSeed = 12345
		GAME.cplus_plus_ex.randomSeedCnt = 0

		-- Reset RNG to ensure deterministic tests
		math.randomseed(12345)

		-- Clear any test pilots from _G
		for key in pairs(_G) do
			if type(key) == "string" and key:match("^Pilot_Test") then
				_G[key] = nil
			end
		end
	end)

	-- Create a minimal mock pilot struct
	local function createMockPilot(pilotId)
		return {
			getIdStr = function(self)
				return pilotId
			end
		}
	end

	-- Register and enable test skills
	local function setupTestSkills(skills)
		for _, skill in ipairs(skills) do
			cplus_plus_ex:registerSkill("test", skill)
		end
		cplus_plus_ex:enableCategory("test")
	end

	describe("Skill Registration and Enabling", function()
		it("should register a skill correctly", function()
			cplus_plus_ex:registerSkill("test", {
				id = "TestSkill",
				shortName = "Test Short",
				fullName = "Test Full",
				description = "Test Description",
				bonuses = {health = 1}
			})

			assert.is_not_nil(cplus_plus_ex._registeredSkills["test"])
			assert.is_not_nil(cplus_plus_ex._registeredSkills["test"]["TestSkill"])
			assert.equals("test", cplus_plus_ex._registeredSkillsIds["TestSkill"])
		end)

		it("should enable a category of skills", function()
			cplus_plus_ex:registerSkill("test", {id = "Skill1", shortName = "S1", fullName = "S1", description = "D1"})
			cplus_plus_ex:registerSkill("test", {id = "Skill2", shortName = "S2", fullName = "S2", description = "D2"})

			cplus_plus_ex:enableCategory("test")

			assert.is_not_nil(cplus_plus_ex._enabledSkills["Skill1"])
			assert.is_not_nil(cplus_plus_ex._enabledSkills["Skill2"])
			assert.equals(2, #cplus_plus_ex._enabledSkillsIds)
		end)
	end)

	describe("Constraint Function Registration", function()
		it("should register a constraint function", function()
			local constraintCalled = false

			cplus_plus_ex:registerConstraintFunction(function(pilot, selected, candidate)
				constraintCalled = true
				return true
			end)

			assert.equals(1, #cplus_plus_ex._constraintFunctions)

			-- Test that the function is called
			local pilot = createMockPilot("TestPilot")
			cplus_plus_ex:checkSkillConstraints(pilot, {}, "TestSkill")
			assert.is_true(constraintCalled)
		end)

		it("should check all registered constraints", function()
			local callCount = 0

			for i = 1, 3 do
				cplus_plus_ex:registerConstraintFunction(function(pilot, selected, candidate)
					callCount = callCount + 1
					return true
				end)
			end

			local pilot = createMockPilot("TestPilot")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "TestSkill")

			assert.equals(3, callCount)
			assert.is_true(result)
		end)

		it("should return false if any constraint fails", function()
			cplus_plus_ex:registerConstraintFunction(function() return true end)
			cplus_plus_ex:registerConstraintFunction(function() return false end)
			cplus_plus_ex:registerConstraintFunction(function() return true end)

			local pilot = createMockPilot("TestPilot")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "TestSkill")

			assert.is_false(result)
		end)
	end)

	describe("No Duplicates Constraint", function()
		before_each(function()
			cplus_plus_ex:registerNoDupsConstraintFunction()

			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
			})
		end)

		it("should allow a skill that hasn't been selected", function()
			local pilot = createMockPilot("TestPilot")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "Health")

			assert.is_true(result)
		end)

		it("should prevent duplicate skills", function()
			local pilot = createMockPilot("TestPilot")
			local selectedSkills = {"Health"}
			local result = cplus_plus_ex:checkSkillConstraints(pilot, selectedSkills, "Health")

			assert.is_false(result)
		end)
	end)

	describe("Pilot Skill Exclusions", function()
		before_each(function()
			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
			})

			cplus_plus_ex:registerPlusExclusionInclusionConstraintFunction()
		end)

		it("should register manual exclusions for a pilot", function()
			cplus_plus_ex:registerPilotSkillExclusions("Pilot_Zoltan", {"Health", "Move"}, false)

			local exclusions = cplus_plus_ex._pilotSkillExclusionsManual["Pilot_Zoltan"]
			assert.is_not_nil(exclusions)
			assert.is_true(exclusions["Health"])
			assert.is_true(exclusions["Move"])
		end)

		it("should register auto exclusions for a pilot", function()
			cplus_plus_ex:registerPilotSkillExclusions("Pilot_Zoltan", {"Health", "Move"}, true)

			local exclusions = cplus_plus_ex._pilotSkillExclusionsAuto["Pilot_Zoltan"]
			assert.is_not_nil(exclusions)
			assert.is_true(exclusions["Health"])
			assert.is_true(exclusions["Move"])
		end)

		it("should prevent manually excluded skills for a pilot", function()
			cplus_plus_ex:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"}, false)

			local pilot = createMockPilot("Pilot_Zoltan")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "Health")

			assert.is_false(result)
		end)

		it("should prevent auto excluded skills for a pilot", function()
			cplus_plus_ex:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"}, true)

			local pilot = createMockPilot("Pilot_Zoltan")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "Health")

			assert.is_false(result)
		end)

		it("should allow non-excluded skills for a pilot", function()
			cplus_plus_ex:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"}, false)

			local pilot = createMockPilot("Pilot_Zoltan")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "Move")

			assert.is_true(result)
		end)

		it("should not affect other pilots", function()
			cplus_plus_ex:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"}, false)

			local pilot = createMockPilot("Pilot_Other")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "Health")

			assert.is_true(result)
		end)
	end)

	describe("Pilot Skill Inclusions", function()
		before_each(function()
			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Special", shortName = "SP", fullName = "Special", description = "Test", skillType = "inclusion"},
			})

			cplus_plus_ex:registerPlusExclusionInclusionConstraintFunction()
		end)

		it("should register inclusions for a pilot", function()
			cplus_plus_ex:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})

			local inclusions = cplus_plus_ex._pilotSkillInclusions["Pilot_Soldier"]
			assert.is_not_nil(inclusions)
			assert.is_true(inclusions["Special"])
		end)

		it("should allow inclusion skills for included pilots", function()
			cplus_plus_ex:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})

			local pilot = createMockPilot("Pilot_Soldier")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "Special")

			assert.is_true(result)
		end)

		it("should prevent inclusion skills for non-included pilots", function()
			cplus_plus_ex:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})

			local pilot = createMockPilot("Pilot_Other")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "Special")

			assert.is_false(result)
		end)

		it("should not affect default skills", function()
			cplus_plus_ex:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})

			local pilot = createMockPilot("Pilot_Other")
			local result = cplus_plus_ex:checkSkillConstraints(pilot, {}, "Health")

			assert.is_true(result)
		end)
	end)

	describe("Random Skill Selection", function()
		before_each(function()
			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
				{id = "Reactor", shortName = "RC", fullName = "Reactor", description = "Test"},
			})

			cplus_plus_ex:registerNoDupsConstraintFunction()
			cplus_plus_ex:registerPlusExclusionInclusionConstraintFunction()
		end)

		it("should select the requested number of skills", function()
			local pilot = createMockPilot("TestPilot")
			local skills = cplus_plus_ex:selectRandomSkills(pilot, 2)

			assert.is_not_nil(skills)
			assert.equals(2, #skills)
		end)

		it("should return nil if constraints are impossible to satisfy", function()
			-- Exclude all but one skill, but try to select 2
			cplus_plus_ex:registerPilotSkillExclusions("TestPilot", {"Health", "Move", "Grid"}, false)

			local pilot = createMockPilot("TestPilot")
			local skills = cplus_plus_ex:selectRandomSkills(pilot, 2)

			assert.is_nil(skills)
		end)
	end)

	describe("Complex Constraint Scenarios", function()
		before_each(function()
			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
				{id = "Reactor", shortName = "RC", fullName = "Reactor", description = "Test"},
				{id = "Special1", shortName = "S1", fullName = "Special1", description = "Test", skillType = "inclusion"},
				{id = "Special2", shortName = "S2", fullName = "Special2", description = "Test", skillType = "inclusion"},
			})

			cplus_plus_ex:registerNoDupsConstraintFunction()
			cplus_plus_ex:registerPlusExclusionInclusionConstraintFunction()
		end)

		it("should handle multiple exclusions and inclusions together", function()
			cplus_plus_ex:registerPilotSkillExclusions("TestPilot", {"Health", "Move"}, false)
			cplus_plus_ex:registerPilotSkillInclusions("TestPilot", {"Special1", "Special2"})

			local pilot = createMockPilot("TestPilot")
			local skills = cplus_plus_ex:selectRandomSkills(pilot, 2)

			assert.is_not_nil(skills)
			assert.equals(2, #skills)

			-- Should not have Health or Move
			for _, skill in ipairs(skills) do
				assert.is_not.equals("Health", skill)
				assert.is_not.equals("Move", skill)
			end
		end)

		it("should allow custom constraints to combine with built-in constraints", function()
			-- Add custom constraint: no skills starting with 'G'
			cplus_plus_ex:registerConstraintFunction(function(pilot, selected, candidate)
				return not string.match(candidate, "^G")
			end)

			local pilot = createMockPilot("TestPilot")
			local skills = cplus_plus_ex:selectRandomSkills(pilot, 2)

			assert.is_not_nil(skills)
			assert.equals(2, #skills)

			-- Should not have Grid
			for _, skill in ipairs(skills) do
				assert.is_not.equals("Grid", skill)
			end
		end)
	end)

	describe("SaveVal Validation", function()
		it("should accept valid boundary saveVal values (0 and 13)", function()
			-- Test lower boundary (0)
			cplus_plus_ex:registerSkill("test", {id = "Skill0", shortName = "S0", fullName = "Skill0", description = "Test", saveVal = 0})
			assert.equals(0, cplus_plus_ex._registeredSkills["test"]["Skill0"].saveVal)

			-- Test upper boundary (13)
			cplus_plus_ex:registerSkill("test", {id = "Skill13", shortName = "S13", fullName = "Skill13", description = "Test", saveVal = 13})
			assert.equals(13, cplus_plus_ex._registeredSkills["test"]["Skill13"].saveVal)
		end)

		it("should convert invalid saveVal to -1", function()
			-- Test value above valid range
			cplus_plus_ex:registerSkill("test", {id = "SkillAbove", shortName = "SA", fullName = "SkillAbove", description = "Test", saveVal = 14})
			assert.equals(-1, cplus_plus_ex._registeredSkills["test"]["SkillAbove"].saveVal, "saveVal 14 should be converted to -1")

			-- Test value below valid range
			cplus_plus_ex:registerSkill("test", {id = "SkillBelow", shortName = "SB", fullName = "SkillBelow", description = "Test", saveVal = -2})
			assert.equals(-1, cplus_plus_ex._registeredSkills["test"]["SkillBelow"].saveVal, "saveVal -2 should be converted to -1")
		end)
	end)

	describe("Pilot Exclusion Scanning from Global", function()
		-- Mock Pilot class for metatable checks
		local Pilot = {}
		Pilot.__index = Pilot

		before_each(function()
			_G.Pilot = Pilot
		end)

		after_each(function()
			_G.Pilot = nil
			-- Clean up test pilots
			for key in pairs(_G) do
				if type(key) == "string" and key:match("^Pilot_Test") then
					_G[key] = nil
				end
			end
		end)

		it("should scan _G for pilots with Blacklist and register exclusions", function()
			-- Create test pilots with Blacklist
			_G.Pilot_TestA = setmetatable({
				Name = "Test Pilot A",
				Blacklist = {"Health", "Move"}
			}, Pilot)

			_G.Pilot_TestB = setmetatable({
				Name = "Test Pilot B",
				Blacklist = {"Grid"}
			}, Pilot)

			cplus_plus_ex:registerPilotExclusionsFromGlobal()

			-- Check auto exclusions were registered
			local exclusionsA = cplus_plus_ex._pilotSkillExclusionsAuto["Pilot_TestA"]
			assert.is_not_nil(exclusionsA)
			assert.is_true(exclusionsA["Health"])
			assert.is_true(exclusionsA["Move"])

			local exclusionsB = cplus_plus_ex._pilotSkillExclusionsAuto["Pilot_TestB"]
			assert.is_not_nil(exclusionsB)
			assert.is_true(exclusionsB["Grid"])
		end)

		it("should skip pilots without Blacklist", function()
			_G.Pilot_TestNoBlacklist = setmetatable({
				Name = "No Blacklist Pilot"
			}, Pilot)

			cplus_plus_ex:registerPilotExclusionsFromGlobal()

			local exclusions = cplus_plus_ex._pilotSkillExclusionsAuto["Pilot_TestNoBlacklist"]
			assert.is_nil(exclusions)
		end)

		it("should clear auto exclusions on each call", function()
			-- First call
			_G.Pilot_TestFirst = setmetatable({
				Name = "First Pilot",
				Blacklist = {"Health"}
			}, Pilot)

			cplus_plus_ex:registerPilotExclusionsFromGlobal()
			assert.is_not_nil(cplus_plus_ex._pilotSkillExclusionsAuto["Pilot_TestFirst"])

			-- Remove pilot and call again
			_G.Pilot_TestFirst = nil
			cplus_plus_ex:registerPilotExclusionsFromGlobal()

			-- Auto exclusions should be cleared
			assert.is_nil(cplus_plus_ex._pilotSkillExclusionsAuto["Pilot_TestFirst"])
		end)

		it("should not clear manual exclusions", function()
			-- Add manual exclusion
			cplus_plus_ex:registerPilotSkillExclusions("Pilot_Manual", {"Health"}, false)

			-- Run auto scan
			cplus_plus_ex:registerPilotExclusionsFromGlobal()

			-- Manual exclusion should still exist
			local manualExclusions = cplus_plus_ex._pilotSkillExclusionsManual["Pilot_Manual"]
			assert.is_not_nil(manualExclusions)
			assert.is_true(manualExclusions["Health"])
		end)
	end)

	describe("Automatic SaveVal Selection and Conflict Resolution", function()
		local mockPilot
		local mockLvlUpSkills
		local appliedSkill1SaveVal, appliedSkill2SaveVal

		before_each(function()
			-- Mock the pilot and lvlUpSkills structure
			mockLvlUpSkills = {
				getSkill1 = function()
					return {
						getSaveVal = function() return appliedSkill1SaveVal or 0 end
					}
				end,
				getSkill2 = function()
					return {
						getSaveVal = function() return appliedSkill2SaveVal or 1 end
					}
				end
			}

			mockPilot = {
				getIdStr = function() return "TestPilot" end,
				getLvlUpSkills = function() return mockLvlUpSkills end,
				setLvlUpSkill = function(self, index, id, shortName, fullName, description, saveVal, bonuses)
					if index == 1 then
						appliedSkill1SaveVal = saveVal
					else
						appliedSkill2SaveVal = saveVal
					end
				end
			}

			-- Reset applied values
			appliedSkill1SaveVal = nil
			appliedSkill2SaveVal = nil
		end)

		it("should use defined saveVal when provided", function()
			setupTestSkills({
				{id = "SkillDefined1", shortName = "SD1", fullName = "SkillDefined1", description = "Test", saveVal = 5},
				{id = "SkillDefined2", shortName = "SD2", fullName = "SkillDefined2", description = "Test", saveVal = 7},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot"] = {"SkillDefined1", "SkillDefined2"}

			cplus_plus_ex:applySkillsToPilot(mockPilot)

			assert.equals(5, appliedSkill1SaveVal)
			assert.equals(7, appliedSkill2SaveVal)
		end)

		it("should assign random saveVal (0-13) when set to -1", function()
			setupTestSkills({
				{id = "SkillRandom1", shortName = "SR1", fullName = "SkillRandom1", description = "Test", saveVal = -1},
				{id = "SkillRandom2", shortName = "SR2", fullName = "SkillRandom2", description = "Test", saveVal = -1},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot"] = {"SkillRandom1", "SkillRandom2"}

			cplus_plus_ex:applySkillsToPilot(mockPilot)

			-- Should be in valid range
			assert.is_true(appliedSkill1SaveVal >= 0 and appliedSkill1SaveVal <= 13, "Skill1 saveVal should be 0-13")
			assert.is_true(appliedSkill2SaveVal >= 0 and appliedSkill2SaveVal <= 13, "Skill2 saveVal should be 0-13")

			-- Should be different (conflict resolution)
			assert.is_not.equals(appliedSkill1SaveVal, appliedSkill2SaveVal, "Random saveVals should be different")
		end)

		it("should resolve conflicts when both skills have same defined saveVal", function()
			setupTestSkills({
				{id = "SkillConflict1", shortName = "SC1", fullName = "SkillConflict1", description = "Test", saveVal = 6},
				{id = "SkillConflict2", shortName = "SC2", fullName = "SkillConflict2", description = "Test", saveVal = 6},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot"] = {"SkillConflict1", "SkillConflict2"}

			cplus_plus_ex:applySkillsToPilot(mockPilot)

			assert.equals(6, appliedSkill1SaveVal, "Skill1 should keep its defined saveVal")
			assert.is_not.equals(6, appliedSkill2SaveVal, "Skill2 should be reassigned")
			assert.is_true(appliedSkill2SaveVal >= 0 and appliedSkill2SaveVal <= 13, "Skill2 should be in valid range")
		end)
	end)
end)
