-- Tests for weighted random selection functionality
-- Tests the getWeightedRandomSkillId function with various weight configurations

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("PLUS Manager Weighted Random Selection", function()
	before_each(function()
		helper.resetState()
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
			local result = plus_manager:getWeightedRandomSkillId({})
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
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
			assert.equals("Health", result)

			-- Mock random value of 0.5 * 3.0 = 1.5 -> should select Move
			helper.mockMathRandom({0.5})
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
			assert.equals("Move", result)

			-- Mock random value of 0.9 * 3.0 = 2.7 -> should select Grid
			helper.mockMathRandom({0.9})
			result = plus_manager:getWeightedRandomSkillId(availableSkills)
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
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
			assert.equals("Common", result)

			-- Test selecting Common (random = 0.5 * 19 = 9.5, still in Common range)
			helper.mockMathRandom({0.5})
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
			assert.equals("Common", result)

			-- Test selecting Uncommon (random = 0.65 * 19 = 12.35)
			helper.mockMathRandom({0.65})
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
			assert.equals("Uncommon", result)

			-- Test selecting Rare (random = 0.85 * 19 = 16.15)
			helper.mockMathRandom({0.85})
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
			assert.equals("Rare", result)

			-- Test selecting Epic (random = 0.99 * 19 = 18.81)
			helper.mockMathRandom({0.99})
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
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
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
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
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
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
			local result = plus_manager:getWeightedRandomSkillId(availableSkills)
			assert.equals("Skill2", result)

			helper.mockMathRandom({0.99})
			result = plus_manager:getWeightedRandomSkillId(availableSkills)
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
			-- Initial state: _localRandomCount should be nil
			assert.is_nil(plus_manager._localRandomCount)

			helper.mockMathRandom({0.5})
			plus_manager:getWeightedRandomSkillId({"SkillX", "SkillY"})

			-- After first call, _localRandomCount should be initialized
			assert.is_not_nil(plus_manager._localRandomCount)
			assert.equals(1, plus_manager._localRandomCount)
		end)

		it("should increment random count on each call", function()
			helper.mockMathRandom({0.5, 0.5, 0.5})

			plus_manager:getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(1, plus_manager._localRandomCount)

			plus_manager:getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(2, plus_manager._localRandomCount)

			plus_manager:getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(3, plus_manager._localRandomCount)
		end)

		it("should sync random count to GAME state", function()
			helper.mockMathRandom({0.5, 0.5})

			plus_manager:getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(1, GAME.cplus_plus_ex.randomSeedCnt)

			plus_manager:getWeightedRandomSkillId({"SkillX", "SkillY"})
			assert.equals(2, GAME.cplus_plus_ex.randomSeedCnt)
		end)
	end)

	describe("Auto-Adjust Weights for Dependencies", function()
		it("should calculate weight based on (numSkills - 2) / numDependencies", function()
			helper.setupTestSkills({
				{id = "Base1", shortName = "B1", fullName = "Base1", description = "Test"},
				{id = "Base2", shortName = "B2", fullName = "Base2", description = "Test"},
				{id = "Base3", shortName = "B3", fullName = "Base3", description = "Test"},
				{id = "Base4", shortName = "B4", fullName = "Base4", description = "Test"},
				{id = "Dependent1", shortName = "D1", fullName = "Dependent1", description = "Test"},
			})
			-- Total: 5 skills

			plus_manager:registerSkillDependency("Dependent1", "Base1")
			plus_manager:setAdjustedWeightsConfigs()

			-- Dependent1 has 1 dependency, 5 total skills: (5-2)/1 = 3.0 times base weight
			-- Base weight is 1.0, so 3.0 * 1.0 = 3.0
			assert.equals(3.0, plus_manager.config.skillConfigs["Dependent1"].adj_weight)
			-- Base1 gets +0.5: 1.0 + 0.5 = 1.5
			assert.equals(1.5, plus_manager.config.skillConfigs["Base1"].adj_weight)
			-- Others unchanged (1.0)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base2"].adj_weight)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base3"].adj_weight)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base4"].adj_weight)
		end)

		it("should handle multiple dependencies reducing weight", function()
			helper.setupTestSkills({
				{id = "Base1", shortName = "B1", fullName = "Base1", description = "Test"},
				{id = "Base2", shortName = "B2", fullName = "Base2", description = "Test"},
				{id = "Base3", shortName = "B3", fullName = "Base3", description = "Test"},
				{id = "Base4", shortName = "B4", fullName = "Base4", description = "Test"},
				{id = "Complex", shortName = "CX", fullName = "Complex", description = "Test"},
			})
			-- Total: 5 skills

			plus_manager:registerSkillDependency("Complex", "Base1")
			plus_manager:registerSkillDependency("Complex", "Base2")
			plus_manager:setAdjustedWeightsConfigs()

			-- Complex has 2 dependencies, 5 total skills: (5-2)/2 = 1.5 times base weight
			-- Base weight is 1.0, so 1.5 * 1.0 = 1.5
			assert.equals(1.5, plus_manager.config.skillConfigs["Complex"].adj_weight)
			-- Both bases get +0.5: 1.0 + 0.5 = 1.5
			assert.equals(1.5, plus_manager.config.skillConfigs["Base1"].adj_weight)
			assert.equals(1.5, plus_manager.config.skillConfigs["Base2"].adj_weight)
			-- Others unchanged (1.0)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base3"].adj_weight)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base4"].adj_weight)
		end)

		it("should accumulate dependency weight increases", function()
			helper.setupTestSkills({
				{id = "Popular", shortName = "PP", fullName = "Popular", description = "Test"},
				{id = "Dependent1", shortName = "D1", fullName = "Dependent1", description = "Test"},
				{id = "Dependent2", shortName = "D2", fullName = "Dependent2", description = "Test"},
				{id = "Dependent3", shortName = "D3", fullName = "Dependent3", description = "Test"},
			})

			plus_manager:registerSkillDependency("Dependent1", "Popular")
			plus_manager:registerSkillDependency("Dependent2", "Popular")
			plus_manager:registerSkillDependency("Dependent3", "Popular")
			plus_manager:setAdjustedWeightsConfigs()

			-- Popular is used by 3 dependents: 1.0 + (3 * 0.5) = 2.5
			assert.equals(2.5, plus_manager.config.skillConfigs["Popular"].adj_weight)

			-- Each dependent has 1 dependency, 4 total skills: (4-2)/1 = 2.0 times base weight
			-- Base weight is 1.0, so 2.0 * 1.0 = 2.0
			assert.equals(2.0, plus_manager.config.skillConfigs["Dependent1"].adj_weight)
			assert.equals(2.0, plus_manager.config.skillConfigs["Dependent2"].adj_weight)
			assert.equals(2.0, plus_manager.config.skillConfigs["Dependent3"].adj_weight)
		end)

		it("should use autoAdjustWeights config flag", function()
			helper.setupTestSkills({
				{id = "Base1", shortName = "B1", fullName = "Base1", description = "Test"},
				{id = "Base2", shortName = "B2", fullName = "Base2", description = "Test"},
				{id = "Base3", shortName = "B3", fullName = "Base3", description = "Test"},
				{id = "Dependent", shortName = "DP", fullName = "Dependent", description = "Test"},
			})

			plus_manager:registerSkillDependency("Dependent", "Base1")

			-- Disable auto-adjust
			plus_manager.config.autoAdjustWeights = false
			plus_manager:setAdjustedWeightsConfigs()

			-- Weights should remain at base values (1.0)
			assert.equals(1.0, plus_manager.config.skillConfigs["Dependent"].adj_weight)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base1"].adj_weight)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base2"].adj_weight)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base3"].adj_weight)
		end)

		it("should multiply custom base weights by dependency factor", function()
			helper.setupTestSkills({
				{id = "Base1", shortName = "B1", fullName = "Base1", description = "Test", weight = 2.0},
				{id = "Base2", shortName = "B2", fullName = "Base2", description = "Test"},
				{id = "Base3", shortName = "B3", fullName = "Base3", description = "Test"},
				{id = "Dependent", shortName = "DP", fullName = "Dependent", description = "Test", weight = 2.0},
			})
			-- 2 skills total

			plus_manager:registerSkillDependency("Dependent", "Base1")
			plus_manager:setAdjustedWeightsConfigs()

			-- Dependent has custom weight 2.0, adjusted by (4-2)/1 = 2, so 2.0 * 2 = 4.0
			assert.equals(4.0, plus_manager.config.skillConfigs["Dependent"].adj_weight)
			-- Base gets +0.5: 2.0 + 0.5 = 2.5
			assert.equals(2.5, plus_manager.config.skillConfigs["Base1"].adj_weight)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base2"].adj_weight)
			assert.equals(1.0, plus_manager.config.skillConfigs["Base3"].adj_weight)
		end)
	end)

end)
