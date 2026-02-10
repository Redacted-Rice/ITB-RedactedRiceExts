-- Tests for skillsSelected hook
-- Verifies that skillsSelected hook fires for each pilot BEFORE their skills are applied
-- Hook signature: (pilot, skillId1, skillId2)

local helper = require("helpers/plus_manager_helper")
local mocks = require("helpers/mocks")

-- Initialize the extension
local cplus_plus_ex = helper.plus_manager
local hooks = cplus_plus_ex.hooks

describe("Skills Selected Hook", function()
	local originalHooks

	before_each(function()
		helper.resetState()
		
		-- Save reference to original hooks array (already initialized by plus_manager)
		originalHooks = hooks.skillsSelectedHooks
		-- Create a fresh empty array for tests
		hooks.skillsSelectedHooks = {}
	end)

	after_each(function()
		-- Restore original hooks
		if originalHooks then
			hooks.skillsSelectedHooks = originalHooks
		end
	end)

	describe("hook registration", function()
		it("should allow adding hook callback", function()
			local called = false

			cplus_plus_ex:addSkillsSelectedHook(function()
				called = true
			end)

			-- Verify hook was added
			assert.are.equal(1, #hooks.skillsSelectedHooks)

			-- Fire hook and verify it was called
			local mockPilot = {}
			hooks.fireSkillsSelectedHooks(mockPilot, "Skill1", "Skill2")
			assert.is_true(called)
		end)

		it("should allow adding multiple hooks", function()
			local count = 0

			cplus_plus_ex:addSkillsSelectedHook(function() count = count + 1 end)
			cplus_plus_ex:addSkillsSelectedHook(function() count = count + 10 end)
			cplus_plus_ex:addSkillsSelectedHook(function() count = count + 100 end)

			assert.are.equal(3, #hooks.skillsSelectedHooks)

			local mockPilot = {}
			hooks.fireSkillsSelectedHooks(mockPilot, "Skill1", "Skill2")
			assert.are.equal(111, count)
		end)
	end)

	describe("hook firing with arguments", function()
		it("should pass pilot and skill IDs to hook", function()
			local capturedPilot, capturedSkill1, capturedSkill2

			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skillId1, skillId2)
				capturedPilot = pilot
				capturedSkill1 = skillId1
				capturedSkill2 = skillId2
			end)

			local mockPilot = { name = "TestPilot" }
			hooks.fireSkillsSelectedHooks(mockPilot, "Health", "Move")

			assert.are.equal(mockPilot, capturedPilot)
			assert.are.equal("Health", capturedSkill1)
			assert.are.equal("Move", capturedSkill2)
		end)
	end)

	describe("multiple hook execution", function()
		it("should call all registered hooks in order", function()
			local callOrder = {}

			cplus_plus_ex:addSkillsSelectedHook(function()
				table.insert(callOrder, 1)
			end)
			cplus_plus_ex:addSkillsSelectedHook(function()
				table.insert(callOrder, 2)
			end)
			cplus_plus_ex:addSkillsSelectedHook(function()
				table.insert(callOrder, 3)
			end)

			local mockPilot = {}
			hooks.fireSkillsSelectedHooks(mockPilot, "Skill1", "Skill2")

			assert.are.equal(3, #callOrder)
			assert.are.equal(1, callOrder[1])
			assert.are.equal(2, callOrder[2])
			assert.are.equal(3, callOrder[3])
		end)

		it("should pass same arguments to all hooks", function()
			local captures = {}

			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skillId1, skillId2)
				table.insert(captures, {pilot = pilot, skill1 = skillId1, skill2 = skillId2})
			end)
			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skillId1, skillId2)
				table.insert(captures, {pilot = pilot, skill1 = skillId1, skill2 = skillId2})
			end)

			local mockPilot = { name = "TestPilot" }
			hooks.fireSkillsSelectedHooks(mockPilot, "Health", "Move")

			assert.are.equal(2, #captures)
			assert.are.equal(mockPilot, captures[1].pilot)
			assert.are.equal(mockPilot, captures[2].pilot)
			assert.are.equal("Health", captures[1].skill1)
			assert.are.equal("Health", captures[2].skill1)
			assert.are.equal("Move", captures[1].skill2)
			assert.are.equal("Move", captures[2].skill2)
		end)
	end)

	describe("error handling", function()
		it("should continue calling hooks after one fails", function()
			local hook2Called = false

			cplus_plus_ex:addSkillsSelectedHook(function()
				error("Test error")
			end)
			cplus_plus_ex:addSkillsSelectedHook(function()
				hook2Called = true
			end)

			-- Should not throw, but log error
			local mockPilot = {}
			hooks.fireSkillsSelectedHooks(mockPilot, "Skill1", "Skill2")

			-- Second hook should still be called
			assert.is_true(hook2Called)
		end)
	end)
end)
