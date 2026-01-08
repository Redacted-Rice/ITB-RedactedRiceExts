-- Tests for pilot-specific features
-- Exclusions, inclusions, and global blacklist scanning

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("PLUS Manager Pilot Constraints", function()
	before_each(function()
		helper.resetState()
	end)

	describe("Pilot Skill Exclusions", function()
		before_each(function()
			helper.setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
			})

			plus_manager:registerPlusExclusionInclusionConstraintFunction()
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

			plus_manager:registerPlusExclusionInclusionConstraintFunction()
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

			plus_manager:readPilotExclusionsFromGlobal()

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

			plus_manager:readPilotExclusionsFromGlobal()

			local exclusions = plus_manager.config.pilotSkillExclusions["Pilot_TestNoBlacklist"]
			assert.is_nil(exclusions)
		end)

		it("should not clear registered exclusions", function()
			plus_manager:registerPilotSkillExclusions("Pilot_Manual", {"Health"})

			plus_manager:readPilotExclusionsFromGlobal()

			local manualExclusions = plus_manager.config.pilotSkillExclusions["Pilot_Manual"]
			assert.is_not_nil(manualExclusions)
			assert.is_true(manualExclusions["Health"])
		end)
	end)
end)
