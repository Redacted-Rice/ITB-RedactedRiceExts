-- Tests for skill reusability system
-- Reusable, per_pilot, per_run, and allowReusableSkills option

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("PLUS Manager Reusability Constraints", function()
	before_each(function()
		helper.resetState()
		plus_manager.allowReusableSkills = true  -- Allow reusable skills for these tests
		plus_manager:registerReusabilityConstraintFunction()
		plus_manager:registerPlusExclusionInclusionConstraintFunction()
	end)

	describe("Reusable Skills", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Reusable1", shortName = "R1", fullName = "Reusable1", description = "Test", reusability = "reusable"},
				{id = "Reusable2", shortName = "R2", fullName = "Reusable2", description = "Test", reusability = "reusable"},
			})
		end)

		it("should allow reusable skills multiple times", function()
			local pilot = helper.createMockPilot("TestPilot")

			plus_manager:markPerRunSkillAsUsed("Reusable1")

			local result = plus_manager:checkSkillConstraints(pilot, {}, "Reusable1")
			assert.is_true(result)
		end)
	end)

	describe("Per-Pilot Skills", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "PerPilot1", shortName = "PP1", fullName = "PerPilot1", description = "Test", reusability = "per_pilot"},
				{id = "PerPilot2", shortName = "PP2", fullName = "PerPilot2", description = "Test", reusability = "per_pilot"},
			})
		end)

		it("should prevent duplicate per_pilot skill on same pilot", function()
			local pilot = helper.createMockPilot("Pilot1")

			local result = plus_manager:checkSkillConstraints(pilot, {"PerPilot1"}, "PerPilot1")
			assert.is_false(result)
		end)

		it("should allow per_pilot skill for different pilots", function()
			local pilot1 = helper.createMockPilot("Pilot1")
			local pilot2 = helper.createMockPilot("Pilot2")

			local result1 = plus_manager:checkSkillConstraints(pilot1, {"PerPilot1"}, "PerPilot2")
			assert.is_true(result1)

			local result2 = plus_manager:checkSkillConstraints(pilot2, {}, "PerPilot1")
			assert.is_true(result2)
		end)
	end)

	describe("Per-Run Skills", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "PerRun1", shortName = "PR1", fullName = "PerRun1", description = "Test", reusability = "per_run"},
				{id = "PerRun2", shortName = "PR2", fullName = "PerRun2", description = "Test", reusability = "per_run"},
			})
		end)

		it("should prevent per_run skill from being used twice in same run", function()
			local pilot1 = helper.createMockPilot("Pilot1")
			local pilot2 = helper.createMockPilot("Pilot2")

			plus_manager:markPerRunSkillAsUsed("PerRun1")

			local result = plus_manager:checkSkillConstraints(pilot2, {}, "PerRun1")
			assert.is_false(result)
		end)

		it("should prevent duplicate per_run skill on same pilot", function()
			local pilot = helper.createMockPilot("Pilot1")

			local result = plus_manager:checkSkillConstraints(pilot, {"PerRun1"}, "PerRun1")
			assert.is_false(result)
		end)

		it("should allow per_run skill after clearing run tracking", function()
			local pilot = helper.createMockPilot("TestPilot")

			plus_manager:markPerRunSkillAsUsed("PerRun1")

			local result1 = plus_manager:checkSkillConstraints(pilot, {}, "PerRun1")
			assert.is_false(result1)

			plus_manager._usedSkillsPerRun = {}

			local result2 = plus_manager:checkSkillConstraints(pilot, {}, "PerRun1")
			assert.is_true(result2)
		end)
	end)

	describe("AllowReusableSkills Option", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Reusable", shortName = "R", fullName = "Reusable", description = "Test", reusability = "reusable"},
			})
		end)

		it("should treat reusable as per_pilot when allowReusableSkills is false", function()
			plus_manager.allowReusableSkills = false

			local pilot = helper.createMockPilot("Pilot1")

			local result = plus_manager:checkSkillConstraints(pilot, {"Reusable"}, "Reusable")
			assert.is_false(result)
		end)

		it("should allow reusable skills normally when allowReusableSkills is true", function()
			plus_manager.allowReusableSkills = true

			local pilot = helper.createMockPilot("Pilot1")

			local result = plus_manager:checkSkillConstraints(pilot, {}, "Reusable")
			assert.is_true(result)
		end)
	end)
end)
