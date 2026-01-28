-- Tests for skillInRun hook
-- Verifies that skillInRun hook fires when skills become available/unavailable in a run
-- Hook signature: (skillId, isInRun, pilot, skill) where isInRun is boolean

local helper = require("helpers/plus_manager_helper")
local mocks = require("helpers/mocks")

-- Initialize the extension
local cplus_plus_ex = helper.plus_manager
local hooks = cplus_plus_ex.hooks

describe("Skill In Run Hook", function()
	local mockPilot
	local mockSkill
	local originalHooks

	before_each(function()
		helper.resetState()
		
		-- Save reference to original hooks array (already initialized by plus_manager)
		originalHooks = hooks.skillInRunHooks
		-- Create a fresh empty array for tests
		hooks.skillInRunHooks = {}

		-- Create mock pilot and skill
		mockPilot = mocks.createMockPilot({
			pilotId = "TestPilot",
			level = 1
		})
		mockSkill = mockPilot:getLvlUpSkill(1)
	end)

	after_each(function()
		-- Restore original hooks
		if originalHooks then
			hooks.skillInRunHooks = originalHooks
		end
	end)

	describe("hook registration", function()
		it("should allow adding hook callback", function()
			local called = false

			cplus_plus_ex:addSkillInRunHook(function()
				called = true
			end)

			-- Verify hook was added
			assert.are.equal(1, #hooks.skillInRunHooks)

			-- Fire hook and verify it was called
			hooks.fireSkillInRunHooks("TestSkill", true, mockPilot, mockSkill)
			assert.is_true(called)
		end)

		it("should allow adding multiple hooks", function()
			local count = 0

			cplus_plus_ex:addSkillInRunHook(function() count = count + 1 end)
			cplus_plus_ex:addSkillInRunHook(function() count = count + 10 end)
			cplus_plus_ex:addSkillInRunHook(function() count = count + 100 end)

			assert.are.equal(3, #hooks.skillInRunHooks)

			hooks.fireSkillInRunHooks("TestSkill", true, mockPilot, mockSkill)
			assert.are.equal(111, count)
		end)
	end)

	describe("hook firing with arguments", function()
		it("should pass skillId, isInRun, pilot, and skill to hook", function()
			local capturedSkillId, capturedIsInRun, capturedPilot, capturedSkill

			cplus_plus_ex:addSkillInRunHook(function(skillId, isInRun, pilot, skill)
				capturedSkillId = skillId
				capturedIsInRun = isInRun
				capturedPilot = pilot
				capturedSkill = skill
			end)

			hooks.fireSkillInRunHooks("TestSkill", true, mockPilot, mockSkill)

			assert.are.equal("TestSkill", capturedSkillId)
			assert.is_true(capturedIsInRun)
			assert.are.equal(mockPilot, capturedPilot)
			assert.are.equal(mockSkill, capturedSkill)
		end)

		it("should handle isInRun = false", function()
			local capturedSkillId, capturedIsInRun

			cplus_plus_ex:addSkillInRunHook(function(skillId, isInRun, pilot, skill)
				capturedSkillId = skillId
				capturedIsInRun = isInRun
			end)

			hooks.fireSkillInRunHooks("TestSkill", false, mockPilot, mockSkill)

			assert.are.equal("TestSkill", capturedSkillId)
			assert.is_false(capturedIsInRun)
		end)
	end)

	describe("multiple hook execution", function()
		it("should call all registered hooks in order", function()
			local callOrder = {}

			cplus_plus_ex:addSkillInRunHook(function()
				table.insert(callOrder, 1)
			end)
			cplus_plus_ex:addSkillInRunHook(function()
				table.insert(callOrder, 2)
			end)
			cplus_plus_ex:addSkillInRunHook(function()
				table.insert(callOrder, 3)
			end)

			hooks.fireSkillInRunHooks("TestSkill", true, mockPilot, mockSkill)

			assert.are.equal(3, #callOrder)
			assert.are.equal(1, callOrder[1])
			assert.are.equal(2, callOrder[2])
			assert.are.equal(3, callOrder[3])
		end)

		it("should pass same arguments to all hooks", function()
			local captures = {}

			cplus_plus_ex:addSkillInRunHook(function(skillId, isInRun, pilot, skill)
				table.insert(captures, {
					skillId = skillId,
					isInRun = isInRun,
					pilot = pilot,
					skill = skill
				})
			end)
			cplus_plus_ex:addSkillInRunHook(function(skillId, isInRun, pilot, skill)
				table.insert(captures, {
					skillId = skillId,
					isInRun = isInRun,
					pilot = pilot,
					skill = skill
				})
			end)

			hooks.fireSkillInRunHooks("TestSkill", true, mockPilot, mockSkill)

			assert.are.equal(2, #captures)
			assert.are.equal("TestSkill", captures[1].skillId)
			assert.are.equal("TestSkill", captures[2].skillId)
			assert.is_true(captures[1].isInRun)
			assert.is_true(captures[2].isInRun)
			assert.are.equal(mockPilot, captures[1].pilot)
			assert.are.equal(mockPilot, captures[2].pilot)
			assert.are.equal(mockSkill, captures[1].skill)
			assert.are.equal(mockSkill, captures[2].skill)
		end)
	end)

	describe("error handling", function()
		it("should continue calling hooks after one fails", function()
			local hook2Called = false

			cplus_plus_ex:addSkillInRunHook(function()
				error("Test error")
			end)
			cplus_plus_ex:addSkillInRunHook(function()
				hook2Called = true
			end)

			-- Should not throw, but log error
			hooks.fireSkillInRunHooks("TestSkill", true, mockPilot, mockSkill)

			-- Second hook should still be called
			assert.is_true(hook2Called)
		end)
	end)
end)
