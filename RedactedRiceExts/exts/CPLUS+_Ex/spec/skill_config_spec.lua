-- Tests for skill_config module
-- Configuration management and weight adjustment logic

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("Skill Config Module", function()
	before_each(function()
		helper.resetState()
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
