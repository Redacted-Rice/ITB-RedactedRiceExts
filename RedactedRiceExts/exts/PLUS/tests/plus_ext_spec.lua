-- Unit tests for PLUS extension skill assignment and constraint system
-- Run with: busted tests/plus_ext_spec.lua

-- Mock external dependencies that plus_ext needs
_G.LOG = function(msg) end  -- Silent logging for tests
_G.GAME = {
	plus_ext = {
		pilotSkills = {},
		randomSeed = 12345,
		randomSeedCnt = 0
	}
}

-- Load the module
package.path = package.path .. ";../scripts/?.lua"
require("plus_ext")

describe("PLUS Extension", function()
	-- Reset state before each test
	before_each(function()
		-- Reset plus_ext state
		plus_ext._registeredSkills = {}
		plus_ext._registeredSkillsIds = {}
		plus_ext._enabledSkills = {}
		plus_ext._enabledSkillsIds = {}
		plus_ext._pilotSkillExclusions = {}
		plus_ext._pilotSkillInclusions = {}
		plus_ext._constraintFunctions = {}
		plus_ext._localRandomCount = nil
		
		-- Reset GAME state
		GAME.plus_ext.pilotSkills = {}
		GAME.plus_ext.randomSeed = 12345
		GAME.plus_ext.randomSeedCnt = 0
		
		-- Reset RNG to ensure deterministic tests
		math.randomseed(12345)
	end)
	
	-- Create a minimal mock pilot struct
	local function createMockPilot(pilotId)
		return {
			getIdStr = function(self)
				return pilotId
			end
		}
	end
	
	-- Register and enable test skills
	local function setupTestSkills(skills)
		for _, skill in ipairs(skills) do
			plus_ext:registerSkill("test", skill)
		end
		plus_ext:enableCategory("test")
	end
	
	describe("Skill Registration and Enabling", function()
		it("should register a skill correctly", function()
			plus_ext:registerSkill("test", {
				id = "TestSkill",
				shortName = "Test Short",
				fullName = "Test Full",
				description = "Test Description",
				bonuses = {health = 1}
			})
			
			assert.is_not_nil(plus_ext._registeredSkills["test"])
			assert.is_not_nil(plus_ext._registeredSkills["test"]["TestSkill"])
			assert.equals("test", plus_ext._registeredSkillsIds["TestSkill"])
		end)
		
		it("should enable a category of skills", function()
			plus_ext:registerSkill("test", {id = "Skill1", shortName = "S1", fullName = "S1", description = "D1"})
			plus_ext:registerSkill("test", {id = "Skill2", shortName = "S2", fullName = "S2", description = "D2"})
			
			plus_ext:enableCategory("test")
			
			assert.is_not_nil(plus_ext._enabledSkills["Skill1"])
			assert.is_not_nil(plus_ext._enabledSkills["Skill2"])
			assert.equals(2, #plus_ext._enabledSkillsIds)
		end)
	end)
	
	describe("Constraint Function Registration", function()
		it("should register a constraint function", function()
			local constraintCalled = false
			
			plus_ext:registerConstraintFunction(function(pilot, selected, candidate)
				constraintCalled = true
				return true
			end)
			
			assert.equals(1, #plus_ext._constraintFunctions)
			
			-- Test that the function is called
			local pilot = createMockPilot("TestPilot")
			plus_ext:checkSkillConstraints(pilot, {}, "TestSkill")
			assert.is_true(constraintCalled)
		end)
		
		it("should check all registered constraints", function()
			local callCount = 0
			
			for i = 1, 3 do
				plus_ext:registerConstraintFunction(function(pilot, selected, candidate)
					callCount = callCount + 1
					return true
				end)
			end
			
			local pilot = createMockPilot("TestPilot")
			local result = plus_ext:checkSkillConstraints(pilot, {}, "TestSkill")
			
			assert.equals(3, callCount)
			assert.is_true(result)
		end)
		
		it("should return false if any constraint fails", function()
			plus_ext:registerConstraintFunction(function() return true end)
			plus_ext:registerConstraintFunction(function() return false end)
			plus_ext:registerConstraintFunction(function() return true end)
			
			local pilot = createMockPilot("TestPilot")
			local result = plus_ext:checkSkillConstraints(pilot, {}, "TestSkill")
			
			assert.is_false(result)
		end)
	end)
	
	describe("No Duplicates Constraint", function()
		before_each(function()
			plus_ext:registerNoDupsConstraintFunction()
			
			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
			})
		end)
		
		it("should allow a skill that hasn't been selected", function()
			local pilot = createMockPilot("TestPilot")
			local result = plus_ext:checkSkillConstraints(pilot, {}, "Health")
			
			assert.is_true(result)
		end)
		
		it("should prevent duplicate skills", function()
			local pilot = createMockPilot("TestPilot")
			local selectedSkills = {"Health"}
			local result = plus_ext:checkSkillConstraints(pilot, selectedSkills, "Health")
			
			assert.is_false(result)
		end)
	end)
	
	describe("Pilot Skill Exclusions", function()
		before_each(function()
			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
			})
			
			plus_ext:registerPlusExclusionInclusionConstraintFunction()
		end)
		
		it("should register exclusions for a pilot", function()
			plus_ext:registerPilotSkillExclusions("Pilot_Zoltan", {"Health", "Move"})
			
			local exclusions = plus_ext._pilotSkillExclusions["Pilot_Zoltan"]
			assert.is_not_nil(exclusions)
			assert.is_true(exclusions["Health"])
			assert.is_true(exclusions["Move"])
		end)
		
		it("should prevent excluded skills for a pilot", function()
			plus_ext:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"})
			
			local pilot = createMockPilot("Pilot_Zoltan")
			local result = plus_ext:checkSkillConstraints(pilot, {}, "Health")
			
			assert.is_false(result)
		end)
		
		it("should allow non-excluded skills for a pilot", function()
			plus_ext:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"})
			
			local pilot = createMockPilot("Pilot_Zoltan")
			local result = plus_ext:checkSkillConstraints(pilot, {}, "Move")
			
			assert.is_true(result)
		end)
		
		it("should not affect other pilots", function()
			plus_ext:registerPilotSkillExclusions("Pilot_Zoltan", {"Health"})
			
			local pilot = createMockPilot("Pilot_Other")
			local result = plus_ext:checkSkillConstraints(pilot, {}, "Health")
			
			assert.is_true(result)
		end)
	end)
	
	describe("Pilot Skill Inclusions", function()
		before_each(function()
			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Special", shortName = "SP", fullName = "Special", description = "Test", skillType = "inclusion"},
			})
			
			plus_ext:registerPlusExclusionInclusionConstraintFunction()
		end)
		
		it("should register inclusions for a pilot", function()
			plus_ext:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})
			
			local inclusions = plus_ext._pilotSkillInclusions["Pilot_Soldier"]
			assert.is_not_nil(inclusions)
			assert.is_true(inclusions["Special"])
		end)
		
		it("should allow inclusion skills for included pilots", function()
			plus_ext:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})
			
			local pilot = createMockPilot("Pilot_Soldier")
			local result = plus_ext:checkSkillConstraints(pilot, {}, "Special")
			
			assert.is_true(result)
		end)
		
		it("should prevent inclusion skills for non-included pilots", function()
			plus_ext:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})
			
			local pilot = createMockPilot("Pilot_Other")
			local result = plus_ext:checkSkillConstraints(pilot, {}, "Special")
			
			assert.is_false(result)
		end)
		
		it("should not affect default skills", function()
			plus_ext:registerPilotSkillInclusions("Pilot_Soldier", {"Special"})
			
			local pilot = createMockPilot("Pilot_Other")
			local result = plus_ext:checkSkillConstraints(pilot, {}, "Health")
			
			assert.is_true(result)
		end)
	end)
	
	describe("Random Skill Selection", function()
		before_each(function()
			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
				{id = "Reactor", shortName = "RC", fullName = "Reactor", description = "Test"},
			})
			
			plus_ext:registerNoDupsConstraintFunction()
			plus_ext:registerPlusExclusionInclusionConstraintFunction()
		end)
		
		it("should select the requested number of skills", function()
			local pilot = createMockPilot("TestPilot")
			local skills = plus_ext:selectRandomSkills(pilot, 2)
			
			assert.is_not_nil(skills)
			assert.equals(2, #skills)
		end)
		
		it("should return nil if constraints are impossible to satisfy", function()
			-- Exclude all but one skill, but try to select 2
			plus_ext:registerPilotSkillExclusions("TestPilot", {"Health", "Move", "Grid"})
			
			local pilot = createMockPilot("TestPilot")
			local skills = plus_ext:selectRandomSkills(pilot, 2)
			
			assert.is_nil(skills)
		end)
	end)
	
	describe("Complex Constraint Scenarios", function()
		before_each(function()
			setupTestSkills({
				{id = "Health", shortName = "HP", fullName = "Health", description = "Test"},
				{id = "Move", shortName = "MV", fullName = "Move", description = "Test"},
				{id = "Grid", shortName = "GR", fullName = "Grid", description = "Test"},
				{id = "Reactor", shortName = "RC", fullName = "Reactor", description = "Test"},
				{id = "Special1", shortName = "S1", fullName = "Special1", description = "Test", skillType = "inclusion"},
				{id = "Special2", shortName = "S2", fullName = "Special2", description = "Test", skillType = "inclusion"},
			})
			
			plus_ext:registerNoDupsConstraintFunction()
			plus_ext:registerPlusExclusionInclusionConstraintFunction()
		end)
		
		it("should handle multiple exclusions and inclusions together", function()
			plus_ext:registerPilotSkillExclusions("TestPilot", {"Health", "Move"})
			plus_ext:registerPilotSkillInclusions("TestPilot", {"Special1", "Special2"})
			
			local pilot = createMockPilot("TestPilot")
			local skills = plus_ext:selectRandomSkills(pilot, 2)
			
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
			plus_ext:registerConstraintFunction(function(pilot, selected, candidate)
				return not string.match(candidate, "^G")
			end)
			
			local pilot = createMockPilot("TestPilot")
			local skills = plus_ext:selectRandomSkills(pilot, 2)
			
			assert.is_not_nil(skills)
			assert.equals(2, #skills)
			
			-- Should not have Grid
			for _, skill in ipairs(skills) do
				assert.is_not.equals("Grid", skill)
			end
		end)
	end)
end)
