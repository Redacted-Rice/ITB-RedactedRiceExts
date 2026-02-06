-- Tests for skill_registry module
-- Registration, saveVal validation, and skill management

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("Skill Registry Module", function()
	before_each(function()
		helper.resetState()
	end)

	describe("Skill Registration", function()
		it("should register a skill correctly", function()
			plus_manager:registerSkill("test", {
				id = "TestSkill",
				shortName = "Test Short",
				fullName = "Test Full",
				description = "Test Description",
				bonuses = {health = 1}
			})

			assert.is_not_nil(plus_manager._subobjects.skill_registry.registeredSkills["TestSkill"])
			assert.equals("test", plus_manager._subobjects.skill_registry.registeredSkills["TestSkill"].category)
		end)

		it("should default reusability to PER_PILOT", function()
			plus_manager:registerSkill("test", {
				id = "TestSkill",
				shortName = "Test",
				fullName = "Test Skill",
				description = "Test"
			})

			assert.equals(plus_manager.REUSABLILITY.PER_PILOT, plus_manager._subobjects.skill_registry.registeredSkills["TestSkill"].reusability)
		end)
	end)

	describe("SaveVal Validation", function()
		it("should accept valid boundary saveVal values (0 and 13)", function()
			plus_manager:registerSkill("test", {id = "Skill0", shortName = "S0", fullName = "Skill0", description = "Test", saveVal = 0})
			assert.equals(0, plus_manager._subobjects.skill_registry.registeredSkills["Skill0"].saveVal)

			plus_manager:registerSkill("test", {id = "Skill13", shortName = "S13", fullName = "Skill13", description = "Test", saveVal = 13})
			assert.equals(13, plus_manager._subobjects.skill_registry.registeredSkills["Skill13"].saveVal)
		end)

		it("should convert invalid saveVal to -1", function()
			plus_manager:registerSkill("test", {id = "SkillAbove", shortName = "SA", fullName = "SkillAbove", description = "Test", saveVal = 14})
			assert.equals(-1, plus_manager._subobjects.skill_registry.registeredSkills["SkillAbove"].saveVal)

			plus_manager:registerSkill("test", {id = "SkillBelow", shortName = "SB", fullName = "SkillBelow", description = "Test", saveVal = -2})
			assert.equals(-1, plus_manager._subobjects.skill_registry.registeredSkills["SkillBelow"].saveVal)
		end)
	end)

	describe("Automatic SaveVal Selection and Conflict Resolution", function()
		local mockPilot
		local tracking

		before_each(function()
			-- Create mock pilot with tracking using convenience helper
			mockPilot, tracking = helper.createMockPilotWithTracking("TestPilot")
		end)

		it("should use defined saveVal when provided", function()
			helper.setupTestSkills({
				{id = "SkillDefined1", shortName = "SD1", fullName = "SkillDefined1", description = "Test", saveVal = 5},
				{id = "SkillDefined2", shortName = "SD2", fullName = "SkillDefined2", description = "Test", saveVal = 7},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot"] = {{id = "SkillDefined1"}, {id = "SkillDefined2"}}

			plus_manager:applySkillsToPilot(mockPilot)

			assert.equals(5, tracking.skill1SaveVal)
			assert.equals(7, tracking.skill2SaveVal)
		end)

		it("should assign random saveVal (0-13) when set to -1", function()
			helper.setupTestSkills({
				{id = "SkillRandom1", shortName = "SR1", fullName = "SkillRandom1", description = "Test", saveVal = -1},
				{id = "SkillRandom2", shortName = "SR2", fullName = "SkillRandom2", description = "Test", saveVal = -1},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot"] = {{id = "SkillRandom1"}, {id = "SkillRandom2"}}

			plus_manager:applySkillsToPilot(mockPilot)

			-- Should be in valid range
			assert.is_true(tracking.skill1SaveVal >= 0 and tracking.skill1SaveVal <= 13, "Skill1 saveVal should be 0-13")
			assert.is_true(tracking.skill2SaveVal >= 0 and tracking.skill2SaveVal <= 13, "Skill2 saveVal should be 0-13")

			-- Should be different (conflict resolution)
			assert.is_not.equals(tracking.skill1SaveVal, tracking.skill2SaveVal, "Random saveVals should be different")
		end)

		it("should resolve conflicts when both skills have same defined saveVal", function()
			helper.setupTestSkills({
				{id = "SkillConflict1", shortName = "SC1", fullName = "SkillConflict1", description = "Test", saveVal = 6},
				{id = "SkillConflict2", shortName = "SC2", fullName = "SkillConflict2", description = "Test", saveVal = 6},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot"] = {{id = "SkillConflict1"}, {id = "SkillConflict2"}}

			plus_manager:applySkillsToPilot(mockPilot)

			assert.equals(6, tracking.skill1SaveVal, "Skill1 should keep its defined saveVal")
			assert.is_not.equals(6, tracking.skill2SaveVal, "Skill2 should be reassigned")
			assert.is_true(tracking.skill2SaveVal >= 0 and tracking.skill2SaveVal <= 13, "Skill2 should be in valid range")
		end)
	end)
end)
