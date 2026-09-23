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

			assert.equals(plus_manager.REUSABLILITY.PER_PILOT, plus_manager._subobjects.skill_registry.registeredSkills["TestSkill"].defaultReusability)
			assert.equals(plus_manager.REUSABLILITY.PER_PILOT, plus_manager._subobjects.skill_registry.registeredSkills["TestSkill"].reusabilityLimit)
		end)

		it("should support separate default and reusability limit", function()
			plus_manager:registerSkill("test", {
				id = "TestSkillSeparate",
				shortName = "Test",
				fullName = "Test Skill",
				description = "Test",
				defaultReusability = plus_manager.REUSABLILITY.PER_RUN,
				reusabilityLimit = plus_manager.REUSABLILITY.PER_PILOT
			})

			local skill = plus_manager._subobjects.skill_registry.registeredSkills["TestSkillSeparate"]
			assert.equals(plus_manager.REUSABLILITY.PER_RUN, skill.defaultReusability)
			assert.equals(plus_manager.REUSABLILITY.PER_PILOT, skill.reusabilityLimit)

			-- Config should use default
			local config = plus_manager._subobjects.skill_config.config.skillConfigs["TestSkillSeparate"]
			assert.equals(plus_manager.REUSABLILITY.PER_RUN, config.reusability)

			-- Allowed reusability should respect limit
			local allowed = plus_manager._subobjects.skill_config:getAllowedReusability("TestSkillSeparate")
			assert.is_false(allowed[plus_manager.REUSABLILITY.REUSABLE])
			assert.is_true(allowed[plus_manager.REUSABLILITY.PER_PILOT])
			assert.is_true(allowed[plus_manager.REUSABLILITY.PER_RUN])
		end)

		it("should enforce that default is not less restrictive than limit", function()
			plus_manager:registerSkill("test", {
				id = "TestSkillInvalid",
				shortName = "Test",
				fullName = "Test Skill",
				description = "Test",
				defaultReusability = plus_manager.REUSABLILITY.REUSABLE,      -- Less restrictive
				reusabilityLimit = plus_manager.REUSABLILITY.PER_RUN      -- More restrictive
			})

			local skill = plus_manager._subobjects.skill_registry.registeredSkills["TestSkillInvalid"]
			-- Default should be adjusted to match limit
			assert.equals(plus_manager.REUSABLILITY.PER_RUN, skill.defaultReusability)
			assert.equals(plus_manager.REUSABLILITY.PER_RUN, skill.reusabilityLimit)
		end)

		it("should support 'reusability' field name in passed table", function()
			plus_manager:registerSkill("test", {
				id = "TestSkillLegacy",
				shortName = "Test",
				fullName = "Test Skill",
				description = "Test",
				reusability = plus_manager.REUSABLILITY.PER_PILOT
			})

			local skill = plus_manager._subobjects.skill_registry.registeredSkills["TestSkillLegacy"]
			-- Should map to both default and limit
			assert.equals(plus_manager.REUSABLILITY.PER_PILOT, skill.defaultReusability)
			assert.equals(plus_manager.REUSABLILITY.PER_PILOT, skill.reusabilityLimit)
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

	describe("Identity SaveVal preservation", function()
		local mockPilot
		local tracking

		before_each(function()
			mockPilot, tracking = helper.createMockPilotWithTracking("TestPilot")
			-- Distinct UID pair already on the pilot
			mockPilot:getLvlUpSkill(1):setSaveVal(5)
			mockPilot:getLvlUpSkill(2):setSaveVal(7)
		end)

		it("should preserve UID saveVals when applying stored skills", function()
			helper.setupTestSkills({
				{id = "SkillDefined1", shortName = "SD1", fullName = "SkillDefined1", description = "Test", saveVal = 0},
				{id = "SkillDefined2", shortName = "SD2", fullName = "SkillDefined2", description = "Test", saveVal = 1},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot:5:7"] = {{id = "SkillDefined1"}, {id = "SkillDefined2"}}

			plus_manager:applySkillsToPilot(mockPilot)

			assert.equals(5, tracking.skill1SaveVal)
			assert.equals(7, tracking.skill2SaveVal)
			assert.equals("TestPilot:5:7", mockPilot:getUidStr())
		end)

		it("should preserve saveVals when applying skills to a new pilot", function()
			helper.setupTestSkills({
				{id = "SkillRandom1", shortName = "SR1", fullName = "SkillRandom1", description = "Test", saveVal = -1},
				{id = "SkillRandom2", shortName = "SR2", fullName = "SkillRandom2", description = "Test", saveVal = -1},
			})

			mockPilot:getLvlUpSkill(1):setSaveVal(3)
			mockPilot:getLvlUpSkill(2):setSaveVal(3)

			plus_manager:applySkillsToPilot(mockPilot)

			assert.equals(3, tracking.skill1SaveVal)
			assert.equals(3, tracking.skill2SaveVal)
			assert.equals("TestPilot:3:3", mockPilot:getUidStr())
		end)

		it("should keep UID saveVals across skill id swaps", function()
			helper.setupTestSkills({
				{id = "SkillA", shortName = "SA", fullName = "SkillA", description = "Test", saveVal = 0},
				{id = "SkillB", shortName = "SB", fullName = "SkillB", description = "Test", saveVal = 1},
				{id = "SkillC", shortName = "SC", fullName = "SkillC", description = "Test", saveVal = 2},
				{id = "SkillD", shortName = "SD", fullName = "SkillD", description = "Test", saveVal = 3},
			})

			GAME.cplus_plus_ex.pilotSkills["TestPilot:5:7"] = {{id = "SkillA"}, {id = "SkillB"}}
			plus_manager:applySkillsToPilot(mockPilot)
			assert.equals(5, tracking.skill1SaveVal)
			assert.equals(7, tracking.skill2SaveVal)

			plus_manager:applySkillIdsToPilot(mockPilot, {"SkillC", "SkillD"}, false)
			assert.equals(5, tracking.skill1SaveVal)
			assert.equals(7, tracking.skill2SaveVal)
			assert.equals("TestPilot:5:7", mockPilot:getUidStr())
		end)
	end)
end)
