-- Tests for skill_constraints module (CONSOLIDATED)
-- All constraint-related tests: constraint function registration, pilot constraints,
-- reusability constraints, and skill-to-skill constraints

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("Skill Constraints Module", function()
	before_each(function()
		helper.resetState()
	end)

	describe("Constraint Function Registration", function()
		before_each(function()
			-- Clear built in constraints for these tests to test registration logic
			plus_manager._modules.skill_constraints.constraintFunctions = {}
		end)

		it("should register a constraint function", function()
			local constraintCalled = false

			plus_manager:registerConstraintFunction(function(pilot, selected, candidate)
				constraintCalled = true
				return true
			end)

			assert.equals(1, #plus_manager._modules.skill_constraints.constraintFunctions)

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

	describe("Pilot Skill Exclusions", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
			})
		end)

		it("should register exclusions for a pilot", function()
			plus_manager:registerPilotSkillExclusions("Pilot_Zoltan", {"Health", "Move"})

			local exclusions = plus_manager.config.pilotSkillExclusions["Pilot_Zoltan"]
			assert.is_not_nil(exclusions)
			assert.is_true(exclusions["Health"])
			assert.is_true(exclusions["Move"])
		end)

		it("should prevent excluded skills for a pilot", function()
			plus_manager:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"})

			local pilot = helper.createMockPilot("Pilot_Zoltan")
			local result = plus_manager:checkSkillConstraints(pilot, {}, "Health")

			assert.is_false(result)
		end)

		it("should allow non-excluded skills for a pilot", function()
			plus_manager:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"})

			local pilot = helper.createMockPilot("Pilot_Zoltan")
			local result = plus_manager:checkSkillConstraints(pilot, {}, "Move")

			assert.is_true(result)
		end)

		it("should not affect other pilots", function()
			plus_manager:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"})

			local pilot = helper.createMockPilot("Pilot_Other")
			local result = plus_manager:checkSkillConstraints(pilot, {}, "Health")

			assert.is_true(result)
		end)
	end)

	describe("Pilot Skill Inclusions", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Special", shortName = "SP", fullName = "Special", description = "Test", skillType = "inclusion"},
			})
		end)

		it("should register inclusions for a pilot", function()
			plus_manager:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})

			local inclusions = plus_manager.config.pilotSkillInclusions["Pilot_Soldier"]
			assert.is_not_nil(inclusions)
			assert.is_true(inclusions["Special"])
		end)

		it("should allow inclusion skills for included pilots", function()
			plus_manager:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})

			local pilot = helper.createMockPilot("Pilot_Soldier")
			local result = plus_manager:checkSkillConstraints(pilot, {}, "Special")

			assert.is_true(result)
		end)

		it("should prevent inclusion skills for non-included pilots", function()
			plus_manager:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})

			local pilot = helper.createMockPilot("Pilot_Other")
			local result = plus_manager:checkSkillConstraints(pilot, {}, "Special")

			assert.is_false(result)
		end)

		it("should not affect default skills", function()
			plus_manager:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})

			local pilot = helper.createMockPilot("Pilot_Other")
			local result = plus_manager:checkSkillConstraints(pilot, {}, "Health")

			assert.is_true(result)
		end)
	end)

	describe("Pilot Exclusion Scanning from Global", function()
		local Pilot = {}
		Pilot.__index = Pilot

		before_each(function()
			_G.Pilot = Pilot
		end)

		after_each(function()
			_G.Pilot = nil
			for key in pairs(_G) do
				if type(key) == "string" and key:match("^Pilot_Test") then
					_G[key] = nil
				end
			end
		end)

		it("should scan _G for pilots with Blacklist and register exclusions", function()
			_G.Pilot_TestA = setmetatable({
				Name = "Test Pilot A",
				Blacklist = {"Health", "Move"}
			}, Pilot)

			_G.Pilot_TestB = setmetatable({
				Name = "Test Pilot B",
				Blacklist = {"Grid"}
			}, Pilot)

			plus_manager._modules.skill_registry.readPilotExclusionsFromGlobal()

			local exclusionsA = plus_manager.config.pilotSkillExclusions["Pilot_TestA"]
			assert.is_not_nil(exclusionsA)
			assert.is_true(exclusionsA["Health"])
			assert.is_true(exclusionsA["Move"])

			local exclusionsB = plus_manager.config.pilotSkillExclusions["Pilot_TestB"]
			assert.is_not_nil(exclusionsB)
			assert.is_true(exclusionsB["Grid"])
		end)

		it("should skip pilots without Blacklist", function()
			_G.Pilot_TestNoBlacklist = setmetatable({
				Name = "No Blacklist Pilot"
			}, Pilot)

			plus_manager._modules.skill_registry.readPilotExclusionsFromGlobal()

			local exclusions = plus_manager.config.pilotSkillExclusions["Pilot_TestNoBlacklist"]
			assert.is_nil(exclusions)
		end)

		it("should not clear registered exclusions", function()
			plus_manager:registerPilotSkillExclusions("Pilot_Manual", {"Health"})

			plus_manager._modules.skill_registry.readPilotExclusionsFromGlobal()

			local manualExclusions = plus_manager.config.pilotSkillExclusions["Pilot_Manual"]
			assert.is_not_nil(manualExclusions)
			assert.is_true(manualExclusions["Health"])
		end)
	end)

	describe("Reusable Skills", function()
		before_each(function()
			plus_manager.config.allowReusableSkills = true  -- Allow reusable skills for these tests
			helper.setupTestSkills({
				{id = "Reusable1", shortName = "R1", fullName = "Reusable1", description = "Test", reusability = plus_manager.REUSABLILITY.REUSABLE},
				{id = "Reusable2", shortName = "R2", fullName = "Reusable2", description = "Test", reusability = plus_manager.REUSABLILITY.REUSABLE},
			})
		end)

		it("should allow reusable skills multiple times", function()
			local pilot = helper.createMockPilot("TestPilot")

			plus_manager._modules.skill_selection.markPerRunSkillAsUsed("Reusable1")

			local result = plus_manager:checkSkillConstraints(pilot, {}, "Reusable1")
			assert.is_true(result)
		end)
	end)

	describe("Per-Pilot Skills", function()
		before_each(function()
			plus_manager.config.allowReusableSkills = true
			helper.setupTestSkills({
				{id = "PerPilot1", shortName = "PP1", fullName = "PerPilot1", description = "Test", reusability = plus_manager.REUSABLILITY.PER_PILOT},
				{id = "PerPilot2", shortName = "PP2", fullName = "PerPilot2", description = "Test", reusability = plus_manager.REUSABLILITY.PER_PILOT},
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
			plus_manager.config.allowReusableSkills = true
			helper.setupTestSkills({
				{id = "PerRun1", shortName = "PR1", fullName = "PerRun1", description = "Test", reusability = plus_manager.REUSABLILITY.PER_RUN},
				{id = "PerRun2", shortName = "PR2", fullName = "PerRun2", description = "Test", reusability = plus_manager.REUSABLILITY.PER_RUN},
			})
		end)

		it("should prevent per_run skill from being used twice in same run", function()
			local pilot1 = helper.createMockPilot("Pilot1")
			local pilot2 = helper.createMockPilot("Pilot2")

			plus_manager._modules.skill_selection.markPerRunSkillAsUsed("PerRun1")

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

			plus_manager._modules.skill_selection.markPerRunSkillAsUsed("PerRun1")

			local result1 = plus_manager:checkSkillConstraints(pilot, {}, "PerRun1")
			assert.is_false(result1)

			plus_manager._modules.skill_selection.usedSkillsPerRun = {}

			local result2 = plus_manager:checkSkillConstraints(pilot, {}, "PerRun1")
			assert.is_true(result2)
		end)
	end)

	describe("AllowReusableSkills Option", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Reusable", shortName = "R", fullName = "Reusable", description = "Test", reusability = plus_manager.REUSABLILITY.REUSABLE},
			})
		end)

		it("should treat reusable as per_pilot when allowReusableSkills is false", function()
			plus_manager.config.allowReusableSkills = false

			local pilot = helper.createMockPilot("Pilot1")

			local result = plus_manager:checkSkillConstraints(pilot, {"Reusable"}, "Reusable")
			assert.is_false(result)
		end)

		it("should allow reusable skills normally when allowReusableSkills is true", function()
			plus_manager.config.allowReusableSkills = true

			local pilot = helper.createMockPilot("Pilot1")

			local result = plus_manager:checkSkillConstraints(pilot, {}, "Reusable")
			assert.is_true(result)
		end)
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

			assert.is_not_nil(plus_manager.config.skillExclusions["Fire"])
			assert.is_true(plus_manager.config.skillExclusions["Fire"]["Ice"])
			assert.is_true(plus_manager.config.skillExclusions["Ice"]["Fire"])
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

			assert.is_not_nil(plus_manager.config.skillDependencies["AdvancedFire"])
			assert.is_true(plus_manager.config.skillDependencies["AdvancedFire"]["BasicFire"])
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
			assert.is_not_nil(plus_manager.config.skillDependencies["AdvancedFire"])
			assert.is_true(plus_manager.config.skillDependencies["AdvancedFire"]["BasicFire"])

			-- Try to create chain: MasterFire depends on AdvancedFire (which is already dependent)
			local success = plus_manager:registerSkillDependency("MasterFire", "AdvancedFire")

			-- Chain should be prevented - should return false
			assert.is_false(success)
			-- MasterFire should not have any dependencies registered
			assert.is_nil(plus_manager.config.skillDependencies["MasterFire"])
		end)

		it("should allow multiple non-dependent skills to depend on the same base skill", function()
			-- Both AdvancedFire and AdvancedIce can depend on BasicFire
			plus_manager:registerSkillDependency("AdvancedFire", "BasicFire")
			plus_manager:registerSkillDependency("AdvancedIce", "BasicFire")

			-- Both should be registered successfully
			assert.is_not_nil(plus_manager.config.skillDependencies["AdvancedFire"])
			assert.is_true(plus_manager.config.skillDependencies["AdvancedFire"]["BasicFire"])

			assert.is_not_nil(plus_manager.config.skillDependencies["AdvancedIce"])
			assert.is_true(plus_manager.config.skillDependencies["AdvancedIce"]["BasicFire"])
		end)

		it("should prevent any chain regardless of registration order", function()
			helper.setupTestSkills({
				{id = "Base", shortName = "BS", fullName = "Base", description = "Test"},
				{id = "Mid", shortName = "MD", fullName = "Mid", description = "Test"},
				{id = "Top", shortName = "TP", fullName = "Top", description = "Test"},
			})

			-- Register Base -> Mid dependency first
			plus_manager:registerSkillDependency("Mid", "Base")
			assert.is_not_nil(plus_manager.config.skillDependencies["Mid"])

			-- Try to chain Mid -> Top (should be prevented)
			local success = plus_manager:registerSkillDependency("Top", "Mid")
			assert.is_false(success)
			assert.is_nil(plus_manager.config.skillDependencies["Top"])
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
