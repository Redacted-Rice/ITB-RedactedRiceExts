-- Tests for postAssigningLvlUpSkills hook
-- Verifies that postAssigningLvlUpSkills hook fires after skills are assigned
-- Hook signature: no arguments

local helper = require("helpers/plus_manager_helper")
local mocks = require("helpers/mocks")

-- Initialize the extension
local cplus_plus_ex = helper.plus_manager
local hooks = cplus_plus_ex.hooks

describe("Post Assigning LvlUp Skills Hook", function()
	local originalHooks

	before_each(function()
		helper.resetState()
		
		-- Save reference to original hooks array (already initialized by plus_manager)
		originalHooks = hooks.postAssigningLvlUpSkillsHooks
		-- Create a fresh empty array for tests
		hooks.postAssigningLvlUpSkillsHooks = {}
	end)

	after_each(function()
		-- Restore original hooks
		if originalHooks then
			hooks.postAssigningLvlUpSkillsHooks = originalHooks
		end
	end)

	describe("hook registration", function()
		it("should allow adding hook callback", function()
			local called = false

			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				called = true
			end)

			-- Verify hook was added
			assert.are.equal(1, #hooks.postAssigningLvlUpSkillsHooks)

			-- Fire hook and verify it was called
			hooks.firePostAssigningLvlUpSkillsHooks()
			assert.is_true(called)
		end)

		it("should allow adding multiple hooks", function()
			local count = 0

			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function() count = count + 1 end)
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function() count = count + 10 end)
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function() count = count + 100 end)

			assert.are.equal(3, #hooks.postAssigningLvlUpSkillsHooks)

			hooks.firePostAssigningLvlUpSkillsHooks()
			assert.are.equal(111, count)
		end)
	end)

	describe("multiple hook execution", function()
		it("should call all registered hooks in order", function()
			local callOrder = {}

			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				table.insert(callOrder, 1)
			end)
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				table.insert(callOrder, 2)
			end)
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				table.insert(callOrder, 3)
			end)

			hooks.firePostAssigningLvlUpSkillsHooks()

			assert.are.equal(3, #callOrder)
			assert.are.equal(1, callOrder[1])
			assert.are.equal(2, callOrder[2])
			assert.are.equal(3, callOrder[3])
		end)
	end)

	describe("error handling", function()
		it("should continue calling hooks after one fails", function()
			local hook2Called = false

			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				error("Test error")
			end)
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				hook2Called = true
			end)

			-- Should not throw, but log error
			hooks.firePostAssigningLvlUpSkillsHooks()

			-- Second hook should still be called
			assert.is_true(hook2Called)
		end)
	end)
end)
