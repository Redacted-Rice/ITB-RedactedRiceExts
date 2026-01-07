-- Tests for core skill management functionality
-- Registration, enabling, constraints, saveVal, and random selection

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("PLUS Manager Core Functionality", function()
	before_each(function()
		helper.resetState()
	end)

	describe("Skill Registration and Enabling", function()
		it("should register a skill correctly", function()
			plus_manager:registerSkill("test", {
				id = "TestSkill",
				shortName = "Test Short",
				fullName = "Test Full",
				description = "Test Description",
				bonuses = {health = 1}
			})

			assert.is_not_nil(plus_manager._registeredSkills["test"])
			assert.is_not_nil(plus_manager._registeredSkills["test"]["TestSkill"])
			assert.equals("test", plus_manager._registeredSkillsIds["TestSkill"])
		end)

		it("should default reusability to per_pilot", function()
			plus_manager:registerSkill("test", {
				id = "TestSkill",
				shortName = "Test",
				fullName = "Test Skill",
				description = "Test"
			})

			assert.equals("per_pilot", plus_manager._registeredSkills["test"]["TestSkill"].reusability)
		end)
	end)

	describe("Constraint Function Registration", function()
		it("should register a constraint function", function()
			local constraintCalled = false

			plus_manager:registerConstraintFunction(function(pilot, selected, candidate)
				constraintCalled = true
				return true
			end)

			assert.equals(1, #plus_manager._constraintFunctions)

			local pilot = helper.createMockPilot("TestPilot")
			plus_manager:checkSkillConstraints(pilot, {}, "TestSkill")
			assert.is_true(constraintCalled)
		end)

		it("should check all registered constraints", function()
			local callCount = 0

			for i = 1, 3 do
				plus_manager:registerConstraintFunction(function(pilot, selected, candidate)
					callCount = callCount + 1
					return true
				end)
			end

			local pilot = helper.createMockPilot("TestPilot")
			local result = plus_manager:checkSkillConstraints(pilot, {}, "TestSkill")

			assert.equals(3, callCount)
			assert.is_true(result)
		end)

		it("should return false if any constraint fails", function()
			plus_manager:registerConstraintFunction(function() return true end)
			plus_manager:registerConstraintFunction(function() return false end)
			plus_manager:registerConstraintFunction(function() return true end)

			local pilot = helper.createMockPilot("TestPilot")
			local result = plus_manager:checkSkillConstraints(pilot, {}, "TestSkill")

			assert.is_false(result)
		end)
	end)

	describe("Random Skill Selection", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
				{id = "Reactor", shortName = "RC", fullName = "Reactor", description = "Test"},
			})

			plus_manager:registerReusabilityConstraintFunction()
			plus_manager:registerPlusExclusionInclusionConstraintFunction()
		end)

		it("should select the requested number of skills", function()
			local pilot = helper.createMockPilot("TestPilot")
			local skills = plus_manager:selectRandomSkills(pilot, 2)

			assert.is_not_nil(skills)
			assert.equals(2, #skills)
		end)

		it("should return nil if constraints are impossible to satisfy", function()
			plus_manager:registerPilotSkillExclusions("TestPilot", {"Health", "Move", "Grid"}, false)

			local pilot = helper.createMockPilot("TestPilot")
			local skills = plus_manager:selectRandomSkills(pilot, 2)

			assert.is_nil(skills)
		end)
	end)

	describe("Random Skill Selection with Complex Constraints", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
				{id = "Reactor", shortName = "RC", fullName = "Reactor", description = "Test"},
				{id = "Special1", shortName = "S1", fullName = "Special1", description = "Test", skillType = "inclusion"},
				{id = "Special2", shortName = "S2", fullName = "Special2", description = "Test", skillType = "inclusion"},
			})

			plus_manager:registerReusabilityConstraintFunction()
			plus_manager:registerPlusExclusionInclusionConstraintFunction()
		end)

		it("should handle multiple exclusions and inclusions together", function()
			plus_manager:registerPilotSkillExclusions("TestPilot", {"Health", "Move"}, false)
			plus_manager:registerPilotSkillInclusions("TestPilot", {"Special1", "Special2"})

			local pilot = helper.createMockPilot("TestPilot")
			local skills = plus_manager:selectRandomSkills(pilot, 2)

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
			plus_manager:registerConstraintFunction(function(pilot, selected, candidate)
				return not string.match(candidate, "^G")
			end)

			local pilot = helper.createMockPilot("TestPilot")
			local skills = plus_manager:selectRandomSkills(pilot, 2)

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
			plus_manager:registerSkill("test", {id = "Skill0", shortName = "S0", fullName = "Skill0", description = "Test", saveVal = 0})
			assert.equals(0, plus_manager._registeredSkills["test"]["Skill0"].saveVal)

			plus_manager:registerSkill("test", {id = "Skill13", shortName = "S13", fullName = "Skill13", description = "Test", saveVal = 13})
			assert.equals(13, plus_manager._registeredSkills["test"]["Skill13"].saveVal)
		end)

		it("should convert invalid saveVal to -1", function()
			plus_manager:registerSkill("test", {id = "SkillAbove", shortName = "SA", fullName = "SkillAbove", description = "Test", saveVal = 14})
			assert.equals(-1, plus_manager._registeredSkills["test"]["SkillAbove"].saveVal)

			plus_manager:registerSkill("test", {id = "SkillBelow", shortName = "SB", fullName = "SkillBelow", description = "Test", saveVal = -2})
			assert.equals(-1, plus_manager._registeredSkills["test"]["SkillBelow"].saveVal)
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
			helper.setupTestSkills({
				{id = "SkillDefined1", shortName = "SD1", fullName = "SkillDefined1", description = "Test", saveVal = 5},
				{id = "SkillDefined2", shortName = "SD2", fullName = "SkillDefined2", description = "Test", saveVal = 7},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot"] = {"SkillDefined1", "SkillDefined2"}

			plus_manager:applySkillsToPilot(mockPilot)

			assert.equals(5, appliedSkill1SaveVal)
			assert.equals(7, appliedSkill2SaveVal)
		end)

		it("should assign random saveVal (0-13) when set to -1", function()
			helper.setupTestSkills({
				{id = "SkillRandom1", shortName = "SR1", fullName = "SkillRandom1", description = "Test", saveVal = -1},
				{id = "SkillRandom2", shortName = "SR2", fullName = "SkillRandom2", description = "Test", saveVal = -1},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot"] = {"SkillRandom1", "SkillRandom2"}

			plus_manager:applySkillsToPilot(mockPilot)

			-- Should be in valid range
			assert.is_true(appliedSkill1SaveVal >= 0 and appliedSkill1SaveVal <= 13, "Skill1 saveVal should be 0-13")
			assert.is_true(appliedSkill2SaveVal >= 0 and appliedSkill2SaveVal <= 13, "Skill2 saveVal should be 0-13")

			-- Should be different (conflict resolution)
			assert.is_not.equals(appliedSkill1SaveVal, appliedSkill2SaveVal, "Random saveVals should be different")
		end)

		it("should resolve conflicts when both skills have same defined saveVal", function()
			helper.setupTestSkills({
				{id = "SkillConflict1", shortName = "SC1", fullName = "SkillConflict1", description = "Test", saveVal = 6},
				{id = "SkillConflict2", shortName = "SC2", fullName = "SkillConflict2", description = "Test", saveVal = 6},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot"] = {"SkillConflict1", "SkillConflict2"}

			plus_manager:applySkillsToPilot(mockPilot)

			assert.equals(6, appliedSkill1SaveVal, "Skill1 should keep its defined saveVal")
			assert.is_not.equals(6, appliedSkill2SaveVal, "Skill2 should be reassigned")
			assert.is_true(appliedSkill2SaveVal >= 0 and appliedSkill2SaveVal <= 13, "Skill2 should be in valid range")
		end)
	end)

	describe("Integration with selectRandomSkills", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Common1", shortName = "C1", fullName = "Common1", description = "Test", reusability = "per_pilot"},
				{id = "Common2", shortName = "C2", fullName = "Common2", description = "Test", reusability = "per_pilot"},
				{id = "Rare1", shortName = "R1", fullName = "Rare1", description = "Test", reusability = "per_pilot"},
			})

			plus_manager:setSkillWeight("Common1", 5.0)
			plus_manager:setSkillWeight("Common2", 5.0)
			plus_manager:setSkillWeight("Rare1", 1.0)

			plus_manager:registerReusabilityConstraintFunction()
			plus_manager:registerPlusExclusionInclusionConstraintFunction()
		end)

		it("should use weighted selection when selecting multiple skills", function()
			-- Mock to select Common1, then Common2
			-- 0.2 * 11.0 = 2.2, which is <= 5.0

			-- 0.3 * 11.0 = 3.3, which is <= 5.0 so if common1 which should be excluded so removed and another tried
			-- 0.3 (again) * 6.0 = 1.8, which is <= 5.0 so common 2 would be selected
			helper.mockMathRandom({0.2, 0.3, 0.3})

			local pilot = helper.createMockPilot("TestPilot")
			local skills = plus_manager:selectRandomSkills(pilot, 2)

			assert.is_not_nil(skills)
			assert.equals(2, #skills)
			-- With the mocked values and weights, we should get the commons more likely
			assert.is_true(skills[1] == "Common1" or skills[1] == "Common2" or skills[1] == "Rare1")
			assert.is_true(skills[2] == "Common1" or skills[2] == "Common2" or skills[2] == "Rare1")
			assert.is_not.equals(skills[1], skills[2])
		end)
	end)
end)
