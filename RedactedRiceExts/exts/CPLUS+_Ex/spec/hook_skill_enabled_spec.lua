-- Tests for skillEnabled hook
-- Verifies that skillEnabled hook fires when skills are enabled/disabled
-- Hook signature: (skillId, enabled) where enabled is boolean

local helper = require("helpers/plus_manager_helper")
local mocks = require("helpers/mocks")

-- Initialize the extension
local cplus_plus_ex = helper.plus_manager
local hooks = cplus_plus_ex.hooks

describe("Skill Enabled Hook", function()
	local originalHooks

	before_each(function()
		helper.resetState()
		
		-- Save reference to original hooks array (already initialized by plus_manager)
		originalHooks = hooks.skillEnabledHooks
		-- Create a fresh empty array for tests
		hooks.skillEnabledHooks = {}
		-- Rebuild broadcast function to point to the new empty array
		hooks:initBroadcastHooks(hooks)
	end)

	after_each(function()
		-- Restore original hooks
		if originalHooks then
			hooks.skillEnabledHooks = originalHooks
		end
	end)

	describe("hook registration", function()
		it("should allow adding hook callback", function()
			local called = false

			cplus_plus_ex:addSkillEnabledHook(function()
				called = true
			end)

			-- Verify hook was added
			assert.are.equal(1, #hooks.skillEnabledHooks)

			-- Fire hook and verify it was called
			hooks.fireSkillEnabledHooks("TestSkill", true)
			assert.is_true(called)
		end)

		it("should allow adding multiple hooks", function()
			local count = 0

			cplus_plus_ex:addSkillEnabledHook(function() count = count + 1 end)
			cplus_plus_ex:addSkillEnabledHook(function() count = count + 10 end)
			cplus_plus_ex:addSkillEnabledHook(function() count = count + 100 end)

			assert.are.equal(3, #hooks.skillEnabledHooks)

			hooks.fireSkillEnabledHooks("TestSkill", true)
			assert.are.equal(111, count)
		end)
	end)

	describe("hook firing with arguments", function()
		it("should pass skillId and enabled state to hook", function()
			local capturedSkillId, capturedEnabled

			cplus_plus_ex:addSkillEnabledHook(function(skillId, enabled)
				capturedSkillId = skillId
				capturedEnabled = enabled
			end)

			hooks.fireSkillEnabledHooks("TestSkill", true)

			assert.are.equal("TestSkill", capturedSkillId)
			assert.is_true(capturedEnabled)
		end)

		it("should handle enabled = false", function()
			local capturedSkillId, capturedEnabled

			cplus_plus_ex:addSkillEnabledHook(function(skillId, enabled)
				capturedSkillId = skillId
				capturedEnabled = enabled
			end)

			hooks.fireSkillEnabledHooks("TestSkill", false)

			assert.are.equal("TestSkill", capturedSkillId)
			assert.is_false(capturedEnabled)
		end)
	end)

	describe("multiple hook execution", function()
		it("should call all registered hooks in order", function()
			local callOrder = {}

			cplus_plus_ex:addSkillEnabledHook(function()
				table.insert(callOrder, 1)
			end)
			cplus_plus_ex:addSkillEnabledHook(function()
				table.insert(callOrder, 2)
			end)
			cplus_plus_ex:addSkillEnabledHook(function()
				table.insert(callOrder, 3)
			end)

			hooks.fireSkillEnabledHooks("TestSkill", true)

			assert.are.equal(3, #callOrder)
			assert.are.equal(1, callOrder[1])
			assert.are.equal(2, callOrder[2])
			assert.are.equal(3, callOrder[3])
		end)

		it("should pass same arguments to all hooks", function()
			local captures = {}

			cplus_plus_ex:addSkillEnabledHook(function(skillId, enabled)
				table.insert(captures, {skillId = skillId, enabled = enabled})
			end)
			cplus_plus_ex:addSkillEnabledHook(function(skillId, enabled)
				table.insert(captures, {skillId = skillId, enabled = enabled})
			end)

			hooks.fireSkillEnabledHooks("TestSkill", true)

			assert.are.equal(2, #captures)
			assert.are.equal("TestSkill", captures[1].skillId)
			assert.are.equal("TestSkill", captures[2].skillId)
			assert.is_true(captures[1].enabled)
			assert.is_true(captures[2].enabled)
		end)
	end)

	describe("error handling", function()
		it("should continue calling hooks after one fails", function()
			local hook2Called = false

			cplus_plus_ex:addSkillEnabledHook(function()
				error("Test error")
			end)
			cplus_plus_ex:addSkillEnabledHook(function()
				hook2Called = true
			end)

			-- Should not throw, but log error
			hooks.fireSkillEnabledHooks("TestSkill", true)

			-- Second hook should still be called
			assert.is_true(hook2Called)
		end)
	end)
end)
