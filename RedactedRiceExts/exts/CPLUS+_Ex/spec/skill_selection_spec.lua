-- Tests for skill_selection module (CONSOLIDATED)
-- All selection-related tests: random selection, weighted selection, and RNG management

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("Skill Selection Module", function()
	before_each(function()
		helper.resetState()
	end)

	describe("Random Skill Selection", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
				{id = "Reactor", shortName = "RC", fullName = "Reactor", description = "Test"},
			})
		end)

		it("should select the requested number of skills", function()
			local pilot = helper.createMockPilot("TestPilot")
			local skills = plus_manager._modules.skill_selection.selectRandomSkills(pilot, 2)

			assert.is_not_nil(skills)
			assert.equals(2, #skills)
		end)

		it("should return nil if constraints are impossible to satisfy", function()
			plus_manager:registerPilotSkillExclusions("TestPilot", {"Health", "Move", "Grid"})

			local pilot = helper.createMockPilot("TestPilot")
			local skills = plus_manager._modules.skill_selection.selectRandomSkills(pilot, 2)

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
		end)

		it("should handle multiple exclusions and inclusions together", function()
			plus_manager:registerPilotSkillExclusions("TestPilot", {"Health", "Move"})
			plus_manager:registerPilotSkillInclusions("TestPilot", {"Special1", "Special2"})

			local pilot = helper.createMockPilot("TestPilot")
			local skills = plus_manager._modules.skill_selection.selectRandomSkills(pilot, 2)

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
			local skills = plus_manager._modules.skill_selection.selectRandomSkills(pilot, 2)

			assert.is_not_nil(skills)
			assert.equals(2, #skills)

			-- Should not have Grid
			for _, skill in ipairs(skills) do
				assert.is_not.equals("Grid", skill)
			end
		end)
	end)

	describe("Weighted Selection Integration", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Common1", shortName = "C1", fullName = "Common1", description = "Test", reusability = plus_manager.REUSABLILITY.PER_PILOT},
				{id = "Common2", shortName = "C2", fullName = "Common2", description = "Test", reusability = plus_manager.REUSABLILITY.PER_PILOT},
				{id = "Rare1", shortName = "R1", fullName = "Rare1", description = "Test", reusability = plus_manager.REUSABLILITY.PER_PILOT},
			})

			plus_manager:setSkillConfig("Common1", {set_weight = 5.0})
			plus_manager:setSkillConfig("Common2", {set_weight = 5.0})
			plus_manager:setSkillConfig("Rare1", {set_weight = 1.0})
		end)

		it("should use weighted selection when selecting multiple skills", function()
			local pilot = helper.createMockPilot("TestPilot")
			local skills = plus_manager._modules.skill_selection.selectRandomSkills(pilot, 2)

			assert.is_not_nil(skills)
			assert.equals(2, #skills)
			-- Should select 2 different skills
			assert.is_not.equals(skills[1], skills[2])
			-- Both should be valid skill IDs
			assert.is_true(skills[1] == "Common1" or skills[1] == "Common2" or skills[1] == "Rare1")
			assert.is_true(skills[2] == "Common1" or skills[2] == "Common2" or skills[2] == "Rare1")
		end)
	end)

	describe("Basic Weighted Selection", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
			})
		end)

		it("should return nil for empty skill list", function()
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId({})
			assert.is_nil(result)
		end)

		it("should handle equal weights (uniform distribution)", function()
			-- Set all to same weight
			plus_manager:setSkillConfig("Health", {set_weight = 1.0})
			plus_manager:setSkillConfig("Move", {set_weight = 1.0})
			plus_manager:setSkillConfig("Grid", {set_weight = 1.0})

			local availableSkills = {"Health", "Move", "Grid"}

			-- Mock random value of 0.3 * 3.0 = 0.9 -> should select Health
			helper.mockMathRandom({0.1})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Health", result)

			-- Mock random value of 0.5 * 3.0 = 1.5 -> should select Move
			helper.mockMathRandom({0.5})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Move", result)

			-- Mock random value of 0.9 * 3.0 = 2.7 -> should select Grid
			helper.mockMathRandom({0.9})
			result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Grid", result)
		end)
	end)

	describe("Weighted Selection with Different Weights", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Common", shortName = "CM", fullName = "Common", description = "Test"},
				{id = "Uncommon", shortName = "UC", fullName = "Uncommon", description = "Test"},
				{id = "Rare", shortName = "RR", fullName = "Rare", description = "Test"},
				{id = "Epic", shortName = "EP", fullName = "Epic", description = "Test"},
			})
		end)

		it("should respect custom weights (high weight more likely)", function()
			plus_manager:setSkillConfig("Common", {set_weight = 10.0})
			plus_manager:setSkillConfig("Uncommon", {set_weight = 5.0})
			plus_manager:setSkillConfig("Rare", {set_weight = 3.0})
			plus_manager:setSkillConfig("Epic", {set_weight = 1.0})

			local availableSkills = {"Common", "Uncommon", "Rare", "Epic"}

			-- Total = 19
			-- Common: 0 - 10
			-- Uncommon: 10 - 15
			-- Rare: 15 - 18
			-- Epic: 18 - 19

			-- Test selecting Common (random = 0.2 * 19 = 3.8)
			helper.mockMathRandom({0.2})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Common", result)

			-- Test selecting Common (random = 0.5 * 19 = 9.5, still in Common range)
			helper.mockMathRandom({0.5})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Common", result)

			-- Test selecting Uncommon (random = 0.65 * 19 = 12.35)
			helper.mockMathRandom({0.65})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Uncommon", result)

			-- Test selecting Rare (random = 0.85 * 19 = 16.15)
			helper.mockMathRandom({0.85})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Rare", result)

			-- Test selecting Epic (random = 0.99 * 19 = 18.81)
			helper.mockMathRandom({0.99})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Epic", result)
		end)
	end)

	describe("Edge Cases for Weighted Selection", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "SkillA", shortName = "SA", fullName = "SkillA", description = "Test"},
				{id = "SkillB", shortName = "SB", fullName = "SkillB", description = "Test"},
				{id = "SkillC", shortName = "SC", fullName = "SkillC", description = "Test"},
			})
		end)

		it("should handle zero weight (effectively disabled)", function()
			-- SkillA has weight 0, SkillB and SkillC have weight 1
			plus_manager:setSkillConfig("SkillA", {set_weight = 0.0})
			plus_manager:setSkillConfig("SkillB", {set_weight = 1.0})
			plus_manager:setSkillConfig("SkillC", {set_weight = 1.0})

			local availableSkills = {"SkillA", "SkillB", "SkillC"}

			-- Total weight = 2.0
			-- SkillA: 0.0 - 0.0 (impossible to select)
			-- SkillB: 0.0 - 1.0
			-- SkillC: 1.0 - 2.0

			-- Even with very low random, should skip SkillA
			helper.mockMathRandom({0.01})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.is_not.equals("SkillA", result)
			assert.is_true(result == "SkillB" or result == "SkillC")
		end)

		it("should handle boundary random value at cumulative weight threshold", function()
			plus_manager:setSkillConfig("SkillA", {set_weight = 1.0})
			plus_manager:setSkillConfig("SkillB", {set_weight = 1.0})
			plus_manager:setSkillConfig("SkillC", {set_weight = 1.0})
			plus_manager:setSkillConfig("SkillD", {set_weight = 1.0})

			local availableSkills = {"SkillA", "SkillB", "SkillC", "SkillD"}

			-- Total weight = 4.0
			-- Test exact boundary: 1.0 / 4.0 = 0.25
			helper.mockMathRandom({0.25})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			-- Should select SkillA (randomValue * 4 = 1.0, which is <= 1.0)
			assert.equals("SkillA", result)
		end)
	end)

	describe("Weighted Selection with Subset of Skills", function()
		before_each(function()
			-- Register and enable 5 skills, but only pass subset to getWeightedRandomSkillId
			helper.setupTestSkills({
				{id = "Skill1", shortName = "S1", fullName = "Skill1", description = "Test"},
				{id = "Skill2", shortName = "S2", fullName = "Skill2", description = "Test"},
				{id = "Skill3", shortName = "S3", fullName = "Skill3", description = "Test"},
				{id = "Skill4", shortName = "S4", fullName = "Skill4", description = "Test"},
				{id = "Skill5", shortName = "S5", fullName = "Skill5", description = "Test"},
			})

			plus_manager:setSkillConfig("Skill1", {set_weight = 1.0})
			plus_manager:setSkillConfig("Skill2", {set_weight = 2.0})
			plus_manager:setSkillConfig("Skill3", {set_weight = 3.0})
			plus_manager:setSkillConfig("Skill4", {set_weight = 4.0})
			plus_manager:setSkillConfig("Skill5", {set_weight = 5.0})
		end)

		it("should only consider weights of skills in availableSkills list", function()
			-- Only pass Skill2 and Skill4
			local availableSkills = {"Skill2", "Skill4"}

			-- Total weight = 2.0 + 4.0 = 6.0
			-- Skill2: 0 - 2.0
			-- Skill4: 2.0 - 6.0

			helper.mockMathRandom({0.2})
			local result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Skill2", result)

			helper.mockMathRandom({0.99})
			result = plus_manager._modules.skill_selection.getWeightedRandomSkillId(availableSkills)
			assert.equals("Skill4", result)
		end)
	end)

	describe("Deterministic RNG State Management", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "SkillX", shortName = "SX", fullName = "SkillX", description = "Test"},
				{id = "SkillY", shortName = "SY", fullName = "SkillY", description = "Test"},
			})
		end)

		it("should initialize RNG state on first call", function()
			-- Initial state: localRandomCount should be nil
			assert.is_nil(plus_manager._modules.skill_selection.localRandomCount)

			helper.mockMathRandom({0.5})
			plus_manager._modules.skill_selection.getWeightedRandomSkillId({"SkillX", "SkillY"})

			-- After first call, localRandomCount should be initialized
			assert.is_not_nil(plus_manager._modules.skill_selection.localRandomCount)
			assert.equals(1, plus_manager._modules.skill_selection.localRandomCount)
		end)

		it("should increment random count on each call", function()
			helper.mockMathRandom({0.5, 0.5, 0.5})

			plus_manager._modules.skill_selection.getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(1, plus_manager._modules.skill_selection.localRandomCount)

			plus_manager._modules.skill_selection.getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(2, plus_manager._modules.skill_selection.localRandomCount)

			plus_manager._modules.skill_selection.getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(3, plus_manager._modules.skill_selection.localRandomCount)
		end)

		it("should sync random count to GAME state", function()
			helper.mockMathRandom({0.5, 0.5})

			plus_manager._modules.skill_selection.getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(1, GAME.cplus_plus_ex.randomSeedCnt)

			plus_manager._modules.skill_selection.getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(2, GAME.cplus_plus_ex.randomSeedCnt)
		end)
	end)
end)
