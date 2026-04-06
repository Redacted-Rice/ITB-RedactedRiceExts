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

	describe("Pilot Exclusion/Inclusion by Function", function()
		it("should defer pilot exclusion predicates until execution", function()
			helper.setupTestSkills({
				{id = "TestSkill1", shortName = "TS1", fullName = "TestSkill1", description = "Test"},
			})

			-- Register exclusions for pilots whose ID starts with "Pilot_A"
			plus_manager._subobjects.skill_registry:registerPilotSkillExclusionsByFunction(
				"TestSkill1",
				function(pilotId)
					return string.sub(pilotId, 1, 7) == "Pilot_A"
				end
			)

			-- Check that predicate was deferred, not executed immediately
			assert.equals(1, #plus_manager._subobjects.skill_registry.deferredPilotPredicates.exclusions)

			-- Execute deferred predicates
			plus_manager._subobjects.skill_registry:_executeDeferredPilotPredicates()

			local exclusions = plus_manager._subobjects.skill_config.codeDefinedRelationships[plus_manager._subobjects.skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS]

			-- Check that exclusions were added for pilots starting with "Pilot_A"
			local foundExclusion = false
			for pilotId, skills in pairs(exclusions) do
				if string.sub(pilotId, 1, 7) == "Pilot_A" and skills["TestSkill1"] then
					foundExclusion = true
					break
				end
			end
		end)

		it("should defer pilot inclusion predicates until execution", function()
			helper.setupTestSkills({
				{id = "TestSkill2", shortName = "TS2", fullName = "TestSkill2", description = "Test", skillType = "inclusion"},
			})

			-- Register inclusions for pilots whose ID contains "Special"
			plus_manager._subobjects.skill_registry:registerPilotSkillInclusionsByFunction(
				"TestSkill2",
				function(pilotId)
					return string.find(pilotId, "Special") ~= nil
				end
			)

			-- Check that predicate was deferred, not executed immediately
			assert.equals(1, #plus_manager._subobjects.skill_registry.deferredPilotPredicates.inclusions)

			-- Execute deferred predicates
			plus_manager._subobjects.skill_registry:_executeDeferredPilotPredicates()

			local inclusions = plus_manager._subobjects.skill_config.codeDefinedRelationships[plus_manager._subobjects.skill_config.RelationshipType.PILOT_SKILL_INCLUSIONS]

			-- Check that inclusions were added for pilots containing "Special"
			local foundInclusion = false
			for pilotId, skills in pairs(inclusions) do
				if string.find(pilotId, "Special") and skills["TestSkill2"] then
					foundInclusion = true
					break
				end
			end
		end)

		it("should handle multiple skills in predicate function", function()
			helper.setupTestSkills({
				{id = "TestSkillA", shortName = "TSA", fullName = "TestSkillA", description = "Test"},
				{id = "TestSkillB", shortName = "TSB", fullName = "TestSkillB", description = "Test"},
			})

			plus_manager._subobjects.skill_registry:registerPilotSkillExclusionsByFunction(
				{"TestSkillA", "TestSkillB"},
				function(pilotId)
					return pilotId == "Pilot_Artificial" or pilotId == "Placeholder_Pilot"
				end
			)

			-- Execute deferred predicates
			plus_manager._subobjects.skill_registry:_executeDeferredPilotPredicates()

			local exclusions = plus_manager._subobjects.skill_config.codeDefinedRelationships[plus_manager._subobjects.skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS]

			-- Both skills should be excluded for the specified pilots
			assert.is_not_nil(exclusions["Pilot_Artificial"])
			assert.is_not_nil(exclusions["Placeholder_Pilot"])
		end)

		it("should handle multiple predicate calls for the same skill additively", function()
			helper.setupTestSkills({
				{id = "TestSkillMulti", shortName = "TSM", fullName = "TestSkillMulti", description = "Test"},
			})

			-- First source excludes from AI pilot
			plus_manager._subobjects.skill_registry:registerPilotSkillExclusionsByFunction(
				"TestSkillMulti",
				function(pilotId)
					return pilotId == "Pilot_Artificial"
				end
			)

			-- Second source excludes from placeholder pilot
			plus_manager._subobjects.skill_registry:registerPilotSkillExclusionsByFunction(
				"TestSkillMulti",
				function(pilotId)
					return pilotId == "Placeholder_Pilot"
				end
			)

			-- Should have stored both predicates
			assert.equals(2, #plus_manager._subobjects.skill_registry.deferredPilotPredicates.exclusions)

			-- Execute deferred predicates
			plus_manager._subobjects.skill_registry:_executeDeferredPilotPredicates()

			local exclusions = plus_manager._subobjects.skill_config.codeDefinedRelationships[plus_manager._subobjects.skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS]

			-- Both pilots should have the exclusion applied
			assert.is_true(exclusions["Pilot_Artificial"]["TestSkillMulti"])
			assert.is_true(exclusions["Placeholder_Pilot"]["TestSkillMulti"])
		end)
	end)

	describe("Skill Category Exclusions", function()
		it("should register exclusions for all skills in specified categories", function()
			helper.setupTestSkills({
				{id = "CategoryTestSkill1", shortName = "CTS1", fullName = "CategoryTestSkill1", description = "Test"},
				{id = "UtilitySkill1", shortName = "US1", fullName = "UtilitySkill1", description = "Test"},
				{id = "UtilitySkill2", shortName = "US2", fullName = "UtilitySkill2", description = "Test"},
				{id = "DefenseSkill1", shortName = "DS1", fullName = "DefenseSkill1", description = "Test"},
			})

			-- Register the skills with specific categories
			plus_manager._subobjects.skill_registry.registeredSkills["UtilitySkill1"].category = "Utility"
			plus_manager._subobjects.skill_registry.registeredSkills["UtilitySkill2"].category = "Utility"
			plus_manager._subobjects.skill_registry.registeredSkills["DefenseSkill1"].category = "Defense"

			-- Exclude CategoryTestSkill1 from all Utility skills
			plus_manager._subobjects.skill_registry:registerSkillCategoryExclusions("CategoryTestSkill1", "Utility")

			local exclusions = plus_manager._subobjects.skill_config.codeDefinedRelationships[plus_manager._subobjects.skill_config.RelationshipType.SKILL_EXCLUSIONS]

			-- CategoryTestSkill1 should exclude both Utility skills
			assert.is_not_nil(exclusions["CategoryTestSkill1"])
			assert.is_true(exclusions["CategoryTestSkill1"]["UtilitySkill1"])
			assert.is_true(exclusions["CategoryTestSkill1"]["UtilitySkill2"])

			-- DefenseSkill1 should not be excluded
			assert.is_nil(exclusions["CategoryTestSkill1"]["DefenseSkill1"])

			-- Exclusion should be bidirectional
			assert.is_true(exclusions["UtilitySkill1"]["CategoryTestSkill1"])
			assert.is_true(exclusions["UtilitySkill2"]["CategoryTestSkill1"])
		end)

		it("should handle multiple categories in exclusion", function()
			helper.setupTestSkills({
				{id = "MultiCatSkill", shortName = "MCS", fullName = "MultiCatSkill", description = "Test"},
				{id = "Cat1Skill", shortName = "C1S", fullName = "Cat1Skill", description = "Test"},
				{id = "Cat2Skill", shortName = "C2S", fullName = "Cat2Skill", description = "Test"},
				{id = "Cat3Skill", shortName = "C3S", fullName = "Cat3Skill", description = "Test"},
			})

			plus_manager._subobjects.skill_registry.registeredSkills["Cat1Skill"].category = "Category1"
			plus_manager._subobjects.skill_registry.registeredSkills["Cat2Skill"].category = "Category2"
			plus_manager._subobjects.skill_registry.registeredSkills["Cat3Skill"].category = "Category3"

			-- Exclude MultiCatSkill from both Category1 and Category2
			plus_manager._subobjects.skill_registry:registerSkillCategoryExclusions("MultiCatSkill", {"Category1", "Category2"})

			local exclusions = plus_manager._subobjects.skill_config.codeDefinedRelationships[plus_manager._subobjects.skill_config.RelationshipType.SKILL_EXCLUSIONS]
			assert.is_true(exclusions["MultiCatSkill"]["Cat1Skill"])
			assert.is_true(exclusions["MultiCatSkill"]["Cat2Skill"])
			assert.is_nil(exclusions["MultiCatSkill"]["Cat3Skill"])
		end)

		it("should apply category exclusions automatically during skill registration", function()
			-- Register a skill with skill_cat_excl parameter
			plus_manager:registerSkill("TestCategory", {
				id = "AutoExclSkill",
				shortName = "AES",
				fullName = "AutoExclSkill",
				description = "Test",
				skill_cat_excl = "Vanilla"
			})

			local exclusions = plus_manager._subobjects.skill_config.codeDefinedRelationships[plus_manager._subobjects.skill_config.RelationshipType.SKILL_EXCLUSIONS]

			-- AutoExclSkill should exclude all vanilla skills
			assert.is_not_nil(exclusions["AutoExclSkill"])
			-- Check that at least one vanilla skill is excluded
			local foundVanillaExclusion = false
			for excludedSkill, _ in pairs(exclusions["AutoExclSkill"]) do
				if plus_manager._subobjects.skill_registry.registeredSkills[excludedSkill] and
				   plus_manager._subobjects.skill_registry.registeredSkills[excludedSkill].category == "Vanilla" then
					foundVanillaExclusion = true
					break
				end
			end
			assert.is_true(foundVanillaExclusion, "Should exclude at least one vanilla skill")
		end)
	end)
end)
