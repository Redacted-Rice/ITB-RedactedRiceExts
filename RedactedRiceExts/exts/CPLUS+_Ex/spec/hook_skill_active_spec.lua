-- Tests for skillActive hook
-- Verifies that skillActive hook fires when skills become active/inactive on squad mechs
-- Hook signature: (skillId, isActive, pawnId, pilot, skill) where isActive is boolean and pawnId is 0-2

local helper = require("helpers/plus_manager_helper")
local mocks = require("helpers/mocks")

-- Initialize the extension
local cplus_plus_ex = helper.plus_manager
local hooks = cplus_plus_ex.hooks

describe("Skill Active Hook", function()
	local mockPilot
	local mockSkill
	local originalHooks

	before_each(function()
		helper.resetState()
		
		-- Save reference to original hooks array (already initialized by plus_manager)
		originalHooks = hooks.skillActiveHooks
		-- Create a fresh empty array for tests
		hooks.skillActiveHooks = {}
		-- Rebuild broadcast function to point to the new empty array
		hooks:initBroadcastHooks(hooks)

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
			hooks.skillActiveHooks = originalHooks
		end
	end)

	describe("hook registration", function()
		it("should allow adding hook callback", function()
			local called = false

			cplus_plus_ex:addSkillActiveHook(function()
				called = true
			end)

			-- Verify hook was added
			assert.are.equal(1, #hooks.skillActiveHooks)

			-- Fire hook and verify it was called
			hooks.fireSkillActiveHooks("TestSkill", true, 0, mockPilot, mockSkill)
			assert.is_true(called)
		end)

		it("should allow adding multiple hooks", function()
			local count = 0

			cplus_plus_ex:addSkillActiveHook(function() count = count + 1 end)
			cplus_plus_ex:addSkillActiveHook(function() count = count + 10 end)
			cplus_plus_ex:addSkillActiveHook(function() count = count + 100 end)

			assert.are.equal(3, #hooks.skillActiveHooks)

			hooks.fireSkillActiveHooks("TestSkill", true, 1, mockPilot, mockSkill)
			assert.are.equal(111, count)
		end)
	end)

	describe("hook firing with arguments", function()
		it("should pass skillId, isActive, pawnId, pilot, and skill to hook", function()
			local capturedSkillId, capturedIsActive, capturedPawnId, capturedPilot, capturedSkill

			cplus_plus_ex:addSkillActiveHook(function(skillId, isActive, pawnId, pilot, skill)
				capturedSkillId = skillId
				capturedIsActive = isActive
				capturedPawnId = pawnId
				capturedPilot = pilot
				capturedSkill = skill
			end)

			hooks.fireSkillActiveHooks("TestSkill", true, 2, mockPilot, mockSkill)

			assert.are.equal("TestSkill", capturedSkillId)
			assert.is_true(capturedIsActive)
			assert.are.equal(2, capturedPawnId)
			assert.are.equal(mockPilot, capturedPilot)
			assert.are.equal(mockSkill, capturedSkill)
		end)

		it("should handle isActive = false", function()
			local capturedSkillId, capturedIsActive, capturedPawnId

			cplus_plus_ex:addSkillActiveHook(function(skillId, isActive, pawnId, pilot, skill)
				capturedSkillId = skillId
				capturedIsActive = isActive
				capturedPawnId = pawnId
			end)

			hooks.fireSkillActiveHooks("TestSkill", false, 0, mockPilot, mockSkill)

			assert.are.equal("TestSkill", capturedSkillId)
			assert.is_false(capturedIsActive)
			assert.are.equal(0, capturedPawnId)
		end)

		it("should handle all valid pawnId values (0, 1, 2)", function()
			local captures = {}

			cplus_plus_ex:addSkillActiveHook(function(skillId, isActive, pawnId, pilot, skill)
				table.insert(captures, pawnId)
			end)

			hooks.fireSkillActiveHooks("TestSkill", true, 0, mockPilot, mockSkill)
			hooks.fireSkillActiveHooks("TestSkill", true, 1, mockPilot, mockSkill)
			hooks.fireSkillActiveHooks("TestSkill", true, 2, mockPilot, mockSkill)

			assert.are.equal(3, #captures)
			assert.are.equal(0, captures[1])
			assert.are.equal(1, captures[2])
			assert.are.equal(2, captures[3])
		end)
	end)

	describe("multiple hook execution", function()
		it("should call all registered hooks in order", function()
			local callOrder = {}

			cplus_plus_ex:addSkillActiveHook(function()
				table.insert(callOrder, 1)
			end)
			cplus_plus_ex:addSkillActiveHook(function()
				table.insert(callOrder, 2)
			end)
			cplus_plus_ex:addSkillActiveHook(function()
				table.insert(callOrder, 3)
			end)

			hooks.fireSkillActiveHooks("TestSkill", true, 0, mockPilot, mockSkill)

			assert.are.equal(3, #callOrder)
			assert.are.equal(1, callOrder[1])
			assert.are.equal(2, callOrder[2])
			assert.are.equal(3, callOrder[3])
		end)

		it("should pass same arguments to all hooks", function()
			local captures = {}

			cplus_plus_ex:addSkillActiveHook(function(skillId, isActive, pawnId, pilot, skill)
				table.insert(captures, {
					skillId = skillId,
					isActive = isActive,
					pawnId = pawnId,
					pilot = pilot,
					skill = skill
				})
			end)
			cplus_plus_ex:addSkillActiveHook(function(skillId, isActive, pawnId, pilot, skill)
				table.insert(captures, {
					skillId = skillId,
					isActive = isActive,
					pawnId = pawnId,
					pilot = pilot,
					skill = skill
				})
			end)

			hooks.fireSkillActiveHooks("TestSkill", true, 1, mockPilot, mockSkill)

			assert.are.equal(2, #captures)
			assert.are.equal("TestSkill", captures[1].skillId)
			assert.are.equal("TestSkill", captures[2].skillId)
			assert.is_true(captures[1].isActive)
			assert.is_true(captures[2].isActive)
			assert.are.equal(1, captures[1].pawnId)
			assert.are.equal(1, captures[2].pawnId)
			assert.are.equal(mockPilot, captures[1].pilot)
			assert.are.equal(mockPilot, captures[2].pilot)
			assert.are.equal(mockSkill, captures[1].skill)
			assert.are.equal(mockSkill, captures[2].skill)
		end)
	end)

	describe("error handling", function()
		it("should continue calling hooks after one fails", function()
			local hook2Called = false

			cplus_plus_ex:addSkillActiveHook(function()
				error("Test error")
			end)
			cplus_plus_ex:addSkillActiveHook(function()
				hook2Called = true
			end)

			-- Should not throw, but log error
			hooks.fireSkillActiveHooks("TestSkill", true, 0, mockPilot, mockSkill)

			-- Second hook should still be called
			assert.is_true(hook2Called)
		end)
	end)
end)
