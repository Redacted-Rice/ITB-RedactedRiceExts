-- Tests for skill-to-skill constraints
-- Exclusions and dependencies between skills

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("PLUS Manager Skill-to-Skill Constraints", function()
	before_each(function()
		helper.resetState()
		plus_manager:registerReusabilityConstraintFunction()
		plus_manager:registerPlusExclusionInclusionConstraintFunction()
		plus_manager:registerSkillExclusionDependencyConstraintFunction()
	end)

	describe("Skill Exclusions", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Fire", shortName = "FR", fullName = "Fire", description = "Test"},
				{id = "Ice", shortName = "IC", fullName = "Ice", description = "Test"},
				{id = "Lightning", shortName = "LT", fullName = "Lightning", description = "Test"},
				{id = "Water", shortName = "WT", fullName = "Water", description = "Test"},
			})
		end)

		it("should register skill exclusion", function()
			plus_manager:registerSkillExclusion("Fire", "Ice")

			assert.is_not_nil(plus_manager._skillExclusions["Fire"])
			assert.is_true(plus_manager._skillExclusions["Fire"]["Ice"])
			assert.is_true(plus_manager._skillExclusions["Ice"]["Fire"])
		end)

		it("should prevent mutually exclusive skills from being selected together", function()
			plus_manager:registerSkillExclusion("Fire", "Ice")

			local pilot = helper.createMockPilot("TestPilot")

			-- Fire already selected, Ice should be rejected
			local result = plus_manager:checkSkillConstraints(pilot, {"Fire"}, "Ice")
			assert.is_false(result)
			-- Ice already selected, Fire should be rejected
			local result = plus_manager:checkSkillConstraints(pilot, {"Ice"}, "Fire")
			assert.is_false(result)
		end)

		it("should allow non-excluded skills", function()
			plus_manager:registerSkillExclusion("Fire", "Ice")

			local pilot = helper.createMockPilot("TestPilot")

			-- Fire and Lightning are not excluded
			local result = plus_manager:checkSkillConstraints(pilot, {"Fire"}, "Lightning")
			assert.is_true(result)
		end)

		it("should handle multiple exclusions for one skill", function()
			plus_manager:registerSkillExclusion("Fire", "Ice")
			plus_manager:registerSkillExclusion("Fire", "Water")

			local pilot = helper.createMockPilot("TestPilot")

			-- Fire excludes both Ice and Water
			local resultIce = plus_manager:checkSkillConstraints(pilot, {"Fire"}, "Ice")
			assert.is_false(resultIce)

			local resultWater = plus_manager:checkSkillConstraints(pilot, {"Fire"}, "Water")
			assert.is_false(resultWater)

			-- But Lightning is still okay
			local resultLightning = plus_manager:checkSkillConstraints(pilot, {"Fire"}, "Lightning")
			assert.is_true(resultLightning)
		end)

		it("should handle chain exclusions", function()
			plus_manager:registerSkillExclusion("Fire", "Ice")
			plus_manager:registerSkillExclusion("Ice", "Water")

			local pilot = helper.createMockPilot("TestPilot")

			-- Fire excludes Ice
			assert.is_false(plus_manager:checkSkillConstraints(pilot, {"Fire"}, "Ice"))

			-- Ice excludes Water
			assert.is_false(plus_manager:checkSkillConstraints(pilot, {"Ice"}, "Water"))

			-- But Fire and Water are not excluded (no transitive exclusion)
			assert.is_true(plus_manager:checkSkillConstraints(pilot, {"Fire"}, "Water"))
		end)
	end)

	describe("Skill Dependencies", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "BasicFire", shortName = "BF", fullName = "BasicFire", description = "Test"},
				{id = "AdvancedFire", shortName = "AF", fullName = "AdvancedFire", description = "Test"},
				{id = "MasterFire", shortName = "MF", fullName = "MasterFire", description = "Test"},
				{id = "BasicIce", shortName = "BI", fullName = "BasicIce", description = "Test"},
				{id = "AdvancedIce", shortName = "AI", fullName = "AdvancedIce", description = "Test"},
			})
		end)

		it("should register skill dependency", function()
			plus_manager:registerSkillDependency("AdvancedFire", "BasicFire")

			assert.is_not_nil(plus_manager._skillDependencies["AdvancedFire"])
			assert.is_true(plus_manager._skillDependencies["AdvancedFire"]["BasicFire"])
		end)

		it("should allow dependent skill when dependency is selected", function()
			plus_manager:registerSkillDependency("AdvancedFire", "BasicFire")

			local pilot = helper.createMockPilot("TestPilot")

			-- BasicFire already selected, AdvancedFire should be allowed
			local result = plus_manager:checkSkillConstraints(pilot, {"BasicFire"}, "AdvancedFire")
			assert.is_true(result)
		end)

		it("should prevent dependent skill when dependency is not selected", function()
			plus_manager:registerSkillDependency("AdvancedFire", "BasicFire")

			local pilot = helper.createMockPilot("TestPilot")

			-- No dependencies selected, AdvancedFire should be rejected
			local result = plus_manager:checkSkillConstraints(pilot, {}, "AdvancedFire")
			assert.is_false(result)
		end)

		it("should prevent dependent skill when wrong dependency is selected", function()
			plus_manager:registerSkillDependency("AdvancedFire", "BasicFire")

			local pilot = helper.createMockPilot("TestPilot")

			-- BasicIce selected, but AdvancedFire requires BasicFire
			local result = plus_manager:checkSkillConstraints(pilot, {"BasicIce"}, "AdvancedFire")
			assert.is_false(result)
		end)

		it("should support multiple dependencies (any one satisfies)", function()
			plus_manager:registerSkillDependency("MasterFire", "BasicFire")
			plus_manager:registerSkillDependency("MasterFire", "AdvancedFire")

			local pilot = helper.createMockPilot("TestPilot")

			-- Either BasicFire or AdvancedFire satisfies the requirement
			local resultBasic = plus_manager:checkSkillConstraints(pilot, {"BasicFire"}, "MasterFire")
			assert.is_true(resultBasic)

			local resultAdvanced = plus_manager:checkSkillConstraints(pilot, {"AdvancedFire"}, "MasterFire")
			assert.is_true(resultAdvanced)

			-- Both also works
			local resultBoth = plus_manager:checkSkillConstraints(pilot, {"BasicFire", "AdvancedFire"}, "MasterFire")
			assert.is_true(resultBoth)

			-- Neither fails
			local resultNeither = plus_manager:checkSkillConstraints(pilot, {}, "MasterFire")
			assert.is_false(resultNeither)
		end)

		it("should allow skills without dependencies", function()
			plus_manager:registerSkillDependency("AdvancedFire", "BasicFire")

			local pilot = helper.createMockPilot("TestPilot")

			-- BasicFire has no dependencies
			local result = plus_manager:checkSkillConstraints(pilot, {}, "BasicFire")
			assert.is_true(result)
		end)

		it("should prevent chain dependencies (dependent -> dependent)", function()
			-- First dependency: AdvancedFire depends on BasicFire
			plus_manager:registerSkillDependency("AdvancedFire", "BasicFire")
			
			-- Verify first dependency was registered
			assert.is_not_nil(plus_manager._skillDependencies["AdvancedFire"])
			assert.is_true(plus_manager._skillDependencies["AdvancedFire"]["BasicFire"])
			
			-- Try to create chain: MasterFire depends on AdvancedFire (which is already dependent)
			plus_manager:registerSkillDependency("MasterFire", "AdvancedFire")
			
			-- Chain should be prevented - MasterFire should not have any dependencies registered
			assert.is_nil(plus_manager._skillDependencies["MasterFire"])
		end)

		it("should allow multiple non-dependent skills to depend on the same base skill", function()
			-- Both AdvancedFire and AdvancedIce can depend on BasicFire
			plus_manager:registerSkillDependency("AdvancedFire", "BasicFire")
			plus_manager:registerSkillDependency("AdvancedIce", "BasicFire")
			
			-- Both should be registered successfully
			assert.is_not_nil(plus_manager._skillDependencies["AdvancedFire"])
			assert.is_true(plus_manager._skillDependencies["AdvancedFire"]["BasicFire"])
			
			assert.is_not_nil(plus_manager._skillDependencies["AdvancedIce"])
			assert.is_true(plus_manager._skillDependencies["AdvancedIce"]["BasicFire"])
		end)

		it("should prevent any chain regardless of registration order", function()
			helper.setupTestSkills({
				{id = "Base", shortName = "BS", fullName = "Base", description = "Test"},
				{id = "Mid", shortName = "MD", fullName = "Mid", description = "Test"},
				{id = "Top", shortName = "TP", fullName = "Top", description = "Test"},
			})

			-- Register Base -> Mid dependency first
			plus_manager:registerSkillDependency("Mid", "Base")
			assert.is_not_nil(plus_manager._skillDependencies["Mid"])
			
			-- Try to chain Mid -> Top (should be prevented)
			plus_manager:registerSkillDependency("Top", "Mid")
			assert.is_nil(plus_manager._skillDependencies["Top"])
		end)
	end)

	describe("Combined Exclusions and Dependencies", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Fire", shortName = "FR", fullName = "Fire", description = "Test"},
				{id = "Ice", shortName = "IC", fullName = "Ice", description = "Test"},
				{id = "AdvancedFire", shortName = "AF", fullName = "AdvancedFire", description = "Test"},
				{id = "AdvancedIce", shortName = "AI", fullName = "AdvancedIce", description = "Test"},
			})
		end)

		it("should enforce both exclusions and dependencies", function()
			plus_manager:registerSkillExclusion("Fire", "Ice")
			plus_manager:registerSkillDependency("AdvancedFire", "Fire")

			local pilot = helper.createMockPilot("TestPilot")

			-- Fire allows AdvancedFire
			assert.is_true(plus_manager:checkSkillConstraints(pilot, {"Fire"}, "AdvancedFire"))

			-- Fire excludes Ice
			assert.is_false(plus_manager:checkSkillConstraints(pilot, {"Fire"}, "Ice"))

			-- Ice doesn't allow AdvancedFire (wrong dependency)
			assert.is_false(plus_manager:checkSkillConstraints(pilot, {"Ice"}, "AdvancedFire"))
		end)
	end)
end)
