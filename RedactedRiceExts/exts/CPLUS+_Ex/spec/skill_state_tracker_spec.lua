-- Tests for skill_state_tracker.lua functionality
-- Verifies state tracking, hook firing, and memhack integration

local helper = require("helpers/plus_manager_helper")
local mocks = require("helpers/mocks")
local plus_manager = helper.plus_manager
local skill_state_tracker = helper.plus_manager._subobjects.skill_state_tracker

describe("Skill State Tracker", function()
	before_each(function()
		helper.resetState()
	end)

	describe("skillEnabled tracking", function()
		it("should fire hook when skill is enabled", function()
			local hookCalls = {}
			plus_manager:addSkillEnabledHook(function(skillId, enabled)
				if skillId == "TestSkill" then
					table.insert(hookCalls, {skillId = skillId, enabled = enabled})
				end
			end)

			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			assert.are.equal(1, #hookCalls)
			assert.are.equal("TestSkill", hookCalls[1].skillId)
			assert.is_true(hookCalls[1].enabled)
		end)

		it("should fire hook when skill is disabled", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")
			assert.is_true(skill_state_tracker:isSkillEnabled("TestSkill"))

			local hookCalls = {}
			plus_manager:addSkillEnabledHook(function(skillId, enabled)
				if skillId == "TestSkill" then
					table.insert(hookCalls, {skillId = skillId, enabled = enabled})
				end
			end)

			plus_manager:disableSkill("TestSkill")

			assert.are.equal(1, #hookCalls)
			assert.are.equal("TestSkill", hookCalls[1].skillId)
			assert.is_false(hookCalls[1].enabled)
		end)

		it("should return all enabled skills", function()
			plus_manager:registerSkill("test", "Skill1", "S1", "Skill 1", "Test")
			plus_manager:registerSkill("test", "Skill2", "S2", "Skill 2", "Test")
			plus_manager:registerSkill("test", "Skill3", "S3", "Skill 3", "Test")

			local enabledSkills = skill_state_tracker:getSkillsEnabled()

			assert.is_true(enabledSkills["Skill1"])
			assert.is_true(enabledSkills["Skill2"])
			assert.is_true(enabledSkills["Skill3"])
		end)
	end)

	describe("skillInRun tracking", function()
		it("should track skill not in run when no pilots", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			skill_state_tracker:updateInRunSkills()

			assert.is_false(skill_state_tracker:isSkillInRun("TestSkill"))
		end)

		it("should track skill in run when pilot has skill", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(1)
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			_G.Game.GetAvailablePilots = function() return {mockPilot} end

			skill_state_tracker:updateInRunSkills()

			assert.is_true(skill_state_tracker:isSkillInRun("TestSkill"))
		end)

		it("should not track skill if pilot level too low", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(0)  -- Level 0, skill requires level 1
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			_G.Game.GetAvailablePilots = function() return {mockPilot} end

			skill_state_tracker:updateInRunSkills()

			assert.is_false(skill_state_tracker:isSkillInRun("TestSkill"))
		end)

		it("should fire hook when skill becomes in-run", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(1)
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			local hookCalls = {}
			plus_manager:addSkillInRunHook(function(skillId, isInRun, pilot, skill)
				if skillId == "TestSkill" then
					table.insert(hookCalls, {
						skillId = skillId,
						isInRun = isInRun,
						pilotId = pilot:getIdStr()
					})
				end
			end)

			_G.Game.GetAvailablePilots = function() return {mockPilot} end

			skill_state_tracker:updateInRunSkills()

			assert.are.equal(1, #hookCalls)
			assert.is_true(hookCalls[1].isInRun)
			assert.are.equal("TestPilot", hookCalls[1].pilotId)
		end)

		it("should fire hook when skill removed from run", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(1)
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			_G.Game.GetAvailablePilots = function() return {mockPilot} end

			skill_state_tracker:updateInRunSkills()
			assert.is_true(skill_state_tracker:isSkillInRun("TestSkill"))

			local hookCalls = {}
			plus_manager:addSkillInRunHook(function(skillId, isInRun, pilot, skill)
				if skillId == "TestSkill" then
					table.insert(hookCalls, {
						skillId = skillId,
						isInRun = isInRun
					})
				end
			end)

			-- Remove pilot from run
			_G.Game.GetAvailablePilots = function() return {} end
			skill_state_tracker:updateInRunSkills()

			assert.are.equal(1, #hookCalls)
			assert.is_false(hookCalls[1].isInRun)
		end)

		it("should fire hook for each skill instance when pilot has same skill in both slots", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(2)  -- Level 2 to earn both skills
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")
			mockPilot:setLvlUpSkill(2, "TestSkill", "Test", "Test Skill", "Description")

			local hookCalls = {}
			plus_manager:addSkillInRunHook(function(skillId, isInRun, pilot, skill)
				if skillId == "TestSkill" then
					table.insert(hookCalls, {skillId = skillId, isInRun = isInRun})
				end
			end)

			_G.Game.GetAvailablePilots = function() return {mockPilot} end

			skill_state_tracker:updateInRunSkills()

			-- Should fire twice - once for each skill instance
			assert.are.equal(2, #hookCalls)
			assert.is_true(hookCalls[1].isInRun)
			assert.is_true(hookCalls[2].isInRun)
		end)

		it("should return all skills in run", function()
			plus_manager:registerSkill("test", "Skill1", "S1", "Skill 1", "Test")
			plus_manager:registerSkill("test", "Skill2", "S2", "Skill 2", "Test")

			local mockPilot1 = mocks.createMockPilot("Pilot1")
			mockPilot1:setLevel(1)
			mockPilot1:setLvlUpSkill(1, "Skill1", "S1", "Skill 1", "Test")

			local mockPilot2 = mocks.createMockPilot("Pilot2")
			mockPilot2:setLevel(1)
			mockPilot2:setLvlUpSkill(1, "Skill2", "S2", "Skill 2", "Test")

			_G.Game.GetAvailablePilots = function() return {mockPilot1, mockPilot2} end

			skill_state_tracker:updateInRunSkills()

			local skillsInRun = skill_state_tracker:getSkillsInRun()

			assert.is_not_nil(skillsInRun["Skill1"])
			assert.is_not_nil(skillsInRun["Skill2"])
		end)
	end)

	describe("skillActive tracking", function()
		before_each(function()
			-- Mock Board for active skill tests
			_G.Board = {
				GetPawn = function(pawnId)
					return nil  -- Default: no pawns
				end
			}
		end)

		it("should track skill not active when no squad pilots", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			skill_state_tracker:updateActiveSkills()

			assert.is_false(skill_state_tracker:isSkillActive("TestSkill"))
		end)

		it("should track skill active when squad pilot has skill", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(1)
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			local mockPawn = {
				GetPilot = function() return mockPilot end
			}
			_G.Board.GetPawn = function(pawnId)
				if pawnId == 0 then return mockPawn end
				return nil
			end

			_G.Game.GetSquadPilots = function() return {mockPilot} end

			skill_state_tracker:updateActiveSkills()

			assert.is_true(skill_state_tracker:isSkillActive("TestSkill"))
		end)

		it("should not track skill if squad pilot level too low", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(0)  -- Level 0, skill requires level 1
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			local mockPawn = {
				GetPilot = function() return mockPilot end
			}
			_G.Board.GetPawn = function(pawnId)
				if pawnId == 0 then return mockPawn end
				return nil
			end

			_G.Game.GetSquadPilots = function() return {mockPilot} end

			skill_state_tracker:updateActiveSkills()

			assert.is_false(skill_state_tracker:isSkillActive("TestSkill"))
		end)

		it("should fire hook when skill becomes active", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(1)
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			local hookCalls = {}
			plus_manager:addSkillActiveHook(function(skillId, isActive, pawnId, pilot, skill)
				if skillId == "TestSkill" then
					table.insert(hookCalls, {
						skillId = skillId,
						isActive = isActive,
						pawnId = pawnId,
						pilotId = pilot:getIdStr()
					})
				end
			end)

			local mockPawn = {
				GetPilot = function() return mockPilot end
			}
			_G.Board.GetPawn = function(pawnId)
				if pawnId == 1 then return mockPawn end
				return nil
			end

			_G.Game.GetSquadPilots = function() return {mockPilot} end

			skill_state_tracker:updateActiveSkills()

			assert.are.equal(1, #hookCalls)
			assert.is_true(hookCalls[1].isActive)
			assert.are.equal(1, hookCalls[1].pawnId)
			assert.are.equal("TestPilot", hookCalls[1].pilotId)
		end)

		it("should fire hook when skill becomes inactive", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(1)
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			local mockPawn = {
				GetPilot = function() return mockPilot end
			}
			_G.Board.GetPawn = function(pawnId)
				if pawnId == 0 then return mockPawn end
				return nil
			end

			_G.Game.GetSquadPilots = function() return {mockPilot} end

			skill_state_tracker:updateActiveSkills()
			assert.is_true(skill_state_tracker:isSkillActive("TestSkill"))

			local hookCalls = {}
			plus_manager:addSkillActiveHook(function(skillId, isActive, pawnId, pilot, skill)
				if skillId == "TestSkill" then
					table.insert(hookCalls, {
						skillId = skillId,
						isActive = isActive,
						pawnId = pawnId
					})
				end
			end)

			-- Remove pilot from squad
			_G.Game.GetSquadPilots = function() return {} end

			skill_state_tracker:updateActiveSkills()

			assert.are.equal(1, #hookCalls)
			assert.is_false(hookCalls[1].isActive)
			assert.are.equal(0, hookCalls[1].pawnId)
		end)

		it("should fire hook for each skill instance when active pilot has same skill in both slots", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(2)  -- Level 2 to earn both skills
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")
			mockPilot:setLvlUpSkill(2, "TestSkill", "Test", "Test Skill", "Description")

			local hookCalls = {}
			plus_manager:addSkillActiveHook(function(skillId, isActive, pawnId, pilot, skill)
				if skillId == "TestSkill" then
					table.insert(hookCalls, {skillId = skillId, isActive = isActive, pawnId = pawnId})
				end
			end)

			local mockPawn = {
				GetPilot = function() return mockPilot end
			}
			_G.Board.GetPawn = function(pawnId)
				if pawnId == 2 then return mockPawn end
				return nil
			end

			_G.Game.GetSquadPilots = function() return {mockPilot} end

			skill_state_tracker:updateActiveSkills()

			-- Should fire twice - once for each skill instance
			assert.are.equal(2, #hookCalls)
			assert.is_true(hookCalls[1].isActive)
			assert.are.equal(2, hookCalls[1].pawnId)
			assert.is_true(hookCalls[2].isActive)
			assert.are.equal(2, hookCalls[2].pawnId)
		end)

		it("should return all active skills", function()
			plus_manager:registerSkill("test", "Skill1", "S1", "Skill 1", "Test")
			plus_manager:registerSkill("test", "Skill2", "S2", "Skill 2", "Test")

			local mockPilot1 = mocks.createMockPilot("Pilot1")
			mockPilot1:setLevel(1)
			mockPilot1:setLvlUpSkill(1, "Skill1", "S1", "Skill 1", "Test")

			local mockPilot2 = mocks.createMockPilot("Pilot2")
			mockPilot2:setLevel(1)
			mockPilot2:setLvlUpSkill(1, "Skill2", "S2", "Skill 2", "Test")

			local mockPawn1 = {GetPilot = function() return mockPilot1 end}
			local mockPawn2 = {GetPilot = function() return mockPilot2 end}

			_G.Board.GetPawn = function(pawnId)
				if pawnId == 0 then return mockPawn1 end
				if pawnId == 1 then return mockPawn2 end
				return nil
			end

			_G.Game.GetSquadPilots = function() return {mockPilot1, mockPilot2} end

			skill_state_tracker:updateActiveSkills()

			local activeSkills = skill_state_tracker:getSkillsActive()

			assert.is_not_nil(activeSkills["Skill1"])
			assert.is_not_nil(activeSkills["Skill2"])
		end)
	end)

	describe("helper functions", function()
		before_each(function()
			-- Ensure Board is set up for tests that need it
			_G.Board = _G.Board or {
				GetPawn = function(pawnId)
					return nil  -- Default: no pawns
				end
			}
		end)

		it("should get pilots with specific skill", function()
			plus_manager:registerSkill("test", "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot1 = mocks.createMockPilot("Pilot1")
			mockPilot1:setLevel(1)
			mockPilot1:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot2 = mocks.createMockPilot("Pilot2")
			mockPilot2:setLevel(1)
			mockPilot2:setLvlUpSkill(1, "OtherSkill", "Other", "Other Skill", "Description")

			local pilots = {mockPilot1, mockPilot2}
			local pilotsWithSkill = skill_state_tracker:getPilotsWithSkill("TestSkill", pilots, true)

			assert.are.equal(1, #pilotsWithSkill)
			assert.are.equal(mockPilot1, pilotsWithSkill[1].pilot)
			assert.are.equal(1, #pilotsWithSkill[1].skillIndices)
			assert.are.equal(1, pilotsWithSkill[1].skillIndices[1])
		end)

		it("should check if skill is on pilots", function()
			local mockPilot1 = mocks.createMockPilot("Pilot1")
			mockPilot1:setLevel(1)
			mockPilot1:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			local mockPilot2 = mocks.createMockPilot("Pilot2")
			mockPilot2:setLevel(1)
			mockPilot2:setLvlUpSkill(1, "OtherSkill", "Other", "Other Skill", "Description")

			local pilots = {mockPilot1, mockPilot2}

			assert.is_true(skill_state_tracker:isSkillOnPilots("TestSkill", pilots, true))
			assert.is_false(skill_state_tracker:isSkillOnPilots("NonExistent", pilots, true))
		end)

		it("should get mechs with specific skill", function()
			local mockPilot = mocks.createMockPilot("TestPilot")
			mockPilot:setLevel(1)
			mockPilot:setLvlUpSkill(1, "TestSkill", "Test", "Test Skill", "Description")

			local mockPawn = {
				GetPilot = function() return mockPilot end
			}
			_G.Board.GetPawn = function(pawnId)
				if pawnId == 1 then return mockPawn end
				return nil
			end

			_G.Game.GetSquadPilots = function() return {mockPilot} end

			local mechsWithSkill = skill_state_tracker:getMechsWithSkill("TestSkill", true)

			assert.are.equal(1, #mechsWithSkill)
			assert.are.equal(1, mechsWithSkill[1].pawnId)
			assert.are.equal(mockPilot, mechsWithSkill[1].pilot)
		end)
	end)
end)
