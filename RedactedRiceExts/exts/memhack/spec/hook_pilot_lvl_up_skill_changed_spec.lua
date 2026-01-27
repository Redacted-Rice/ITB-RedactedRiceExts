-- Tests for pilot skill changed hook
-- Verifies that pilotLvlUpSkillChanged hook fires when skills are modified
-- Hook signature: (pilot, skill, changes) where changes = {field = {old = val, new = val}}
-- Note: The pilot is automatically prepended from the skill's parent reference

local specHelper = require("helpers/spec_helper")
local mocks = require("helpers/mocks")

-- Initialize the extension with mock DLL
local memhack = specHelper.initMemhack()
local hooks = memhack.hooks

describe("Pilot Skill Changed Hook", function()
	local pilot
	local skill1
	local skill2
	local originalHooks

	before_each(function()
		-- Save original hooks array and clear it for testing
		-- The fire function already exists from memhack initialization
		originalHooks = hooks.pilotLvlUpSkillChangedHooks
		hooks.pilotLvlUpSkillChangedHooks = {}

		pilot = mocks.createMockPilot({
			pilotId = "TestPilot",
			level = 1
		})

		-- Get skills with parent references properly set
		local lvlUpSkills = pilot:getLvlUpSkills()
		skill1 = lvlUpSkills:getSkill1()
		skill2 = lvlUpSkills:getSkill2()
	end)

	after_each(function()
		if originalHooks then
			hooks.pilotLvlUpSkillChangedHooks = originalHooks
		end
	end)

	describe("hook registration", function()
		it("should allow adding hook callback", function()
			local called = false

			hooks:addPilotLvlUpSkillChangedHook(function()
				called = true
			end)

			assert.are.equal(1, #hooks.pilotLvlUpSkillChangedHooks)

			hooks.firePilotLvlUpSkillChangedHooks(skill1, {id = {old = "OldSkill", new = "NewSkill"}})
			assert.is_true(called)
		end)

		it("should allow adding multiple hooks", function()
			local count = 0

			hooks:addPilotLvlUpSkillChangedHook(function() count = count + 1 end)
			hooks:addPilotLvlUpSkillChangedHook(function() count = count + 10 end)

			assert.are.equal(2, #hooks.pilotLvlUpSkillChangedHooks)

			hooks.firePilotLvlUpSkillChangedHooks(skill1, {id = {old = "OldSkill", new = "NewSkill"}})
			assert.are.equal(11, count)
		end)
	end)

	describe("hook firing with arguments", function()
		it("should pass pilot, skill, and changes to hook", function()
			local capturedPilot, capturedSkill, capturedChanges

			hooks:addPilotLvlUpSkillChangedHook(function(pilot, skill, changes)
				capturedPilot = pilot
				capturedSkill = skill
				capturedChanges = changes
			end)

			local changes = {
				id = {old = "OldSkill", new = "NewSkill"}
			}
			hooks.firePilotLvlUpSkillChangedHooks(skill1, changes)

			-- Pilot should be prepended from parent
			assert.are.equal(pilot, capturedPilot)
			assert.are.equal(skill1, capturedSkill)
			assert.are.same(changes, capturedChanges)
		end)

		it("should pass nil pilot when skill has no parent", function()
			local capturedPilot, capturedSkill, capturedChanges

			hooks:addPilotLvlUpSkillChangedHook(function(pilot, skill, changes)
				capturedPilot = pilot
				capturedSkill = skill
				capturedChanges = changes
			end)

			-- Create orphan skill without parent
			local orphanSkill = mocks.createMockSkill({skillId = "Orphan"})

			local changes = {id = {old = "OldSkill", new = "NewSkill"}}
			hooks.firePilotLvlUpSkillChangedHooks(orphanSkill, changes)

			-- Pilot should be nil (not omitted)
			assert.is_nil(capturedPilot)
			assert.are.equal(orphanSkill, capturedSkill)
			assert.are.same(changes, capturedChanges)
		end)

		it("should prepend correct pilot for skill1", function()
			local capturedPilot

			hooks:addPilotLvlUpSkillChangedHook(function(p, s, c)
				capturedPilot = p
			end)

			hooks.firePilotLvlUpSkillChangedHooks(skill1, {id = {old = "OldSkill", new = "NewSkill"}})

			assert.are.equal(pilot, capturedPilot)
			assert.are.equal("TestPilot", capturedPilot:getIdStr())
		end)

		it("should prepend correct pilot for skill2", function()
			local capturedPilot

			hooks:addPilotLvlUpSkillChangedHook(function(p, s, c)
				capturedPilot = p
			end)

			hooks.firePilotLvlUpSkillChangedHooks(skill2, {id = {old = "OldSkill", new = "NewSkill"}})

			assert.are.equal(pilot, capturedPilot)
			assert.are.equal("TestPilot", capturedPilot:getIdStr())
		end)

		it("should pass skill changes correctly", function()
			local capturedChanges

			hooks:addPilotLvlUpSkillChangedHook(function(p, s, c)
				capturedChanges = c
			end)

			local changes = {
				id = {old = "OldSkill", new = "NewSkill"},
				saveVal = {old = 0, new = 5},
				coresBonus = {old = 0, new = 2}
			}
			hooks.firePilotLvlUpSkillChangedHooks(skill1, changes)

			assert.are.same(changes, capturedChanges)
			assert.are.equal("OldSkill", capturedChanges.id.old)
			assert.are.equal("NewSkill", capturedChanges.id.new)
			assert.are.equal(0, capturedChanges.saveVal.old)
			assert.are.equal(5, capturedChanges.saveVal.new)
		end)
	end)

	describe("multiple hook execution", function()
		it("should call all registered hooks in order", function()
			local callOrder = {}

			hooks:addPilotLvlUpSkillChangedHook(function()
				table.insert(callOrder, 1)
			end)
			hooks:addPilotLvlUpSkillChangedHook(function()
				table.insert(callOrder, 2)
			end)
			hooks:addPilotLvlUpSkillChangedHook(function()
				table.insert(callOrder, 3)
			end)

			hooks.firePilotLvlUpSkillChangedHooks(skill1, {id = {old = "OldSkill", new = "NewSkill"}})

			assert.are.equal(3, #callOrder)
			assert.are.equal(1, callOrder[1])
			assert.are.equal(2, callOrder[2])
			assert.are.equal(3, callOrder[3])
		end)

		it("should pass same arguments to all hooks", function()
			local captures = {}

			hooks:addPilotLvlUpSkillChangedHook(function(pilot, skill, changes)
				table.insert(captures, {pilot = pilot, skill = skill, changes = changes})
			end)
			hooks:addPilotLvlUpSkillChangedHook(function(pilot, skill, changes)
				table.insert(captures, {pilot = pilot, skill = skill, changes = changes})
			end)

			local changes = {id = {old = "Old", new = "New"}}
			hooks.firePilotLvlUpSkillChangedHooks(skill1, changes)

			assert.are.equal(2, #captures)
			assert.are.equal(pilot, captures[1].pilot)
			assert.are.equal(pilot, captures[2].pilot)
			assert.are.equal(skill1, captures[1].skill)
			assert.are.equal(skill1, captures[2].skill)
			assert.are.same(changes, captures[1].changes)
			assert.are.same(changes, captures[2].changes)
		end)
	end)

	describe("error handling", function()
		it("should continue calling hooks after one fails", function()
			local hook2Called = false

			hooks:addPilotLvlUpSkillChangedHook(function()
				error("Test error")
			end)
			hooks:addPilotLvlUpSkillChangedHook(function()
				hook2Called = true
			end)

			-- Should not throw, but log error
			hooks.firePilotLvlUpSkillChangedHooks(skill1, {id = {old = "OldSkill", new = "NewSkill"}})

			-- Second hook should still be called
			assert.is_true(hook2Called)
		end)
	end)

	describe("re-entrant wrapper integration", function()
		before_each(function()
			-- Re-apply re-entrant wrapper for this test suite
			-- (main before_each rebuilds broadcast functions which removes the wrapper)
			memhack.stateTracker.wrapHooksToUpdateStateTrackers()
		end)
		
		it("should queue re-entrant calls and re-fire with actual state changes", function()
			-- This test verifies that the re-entrant wrapper is actually being used for skill changed hooks
			-- by checking the order and arguments of hook calls.

			local hook1Calls = {}
			local hook2Calls = {}

			-- First hook modifies skill during first call and triggers re-entrant call
			hooks:addPilotLvlUpSkillChangedHook(function(p, s, changes)
				table.insert(hook1Calls, changes)

				if #hook1Calls == 1 then
					-- Modify skill state
					skill1._grid_bonus = 2
					-- Trigger re-entrant call - should set flag and return immediately
					hooks.firePilotLvlUpSkillChangedHooks(skill1, {gridBonus = {old = 0, new = 2}})
				end
			end)

			-- Second hook just records changes
			hooks:addPilotLvlUpSkillChangedHook(function(p, s, changes)
				table.insert(hook2Calls, changes)
			end)

			skill1._cores_bonus = 1
			local initialChanges = {coresBonus = {old = 0, new = 1}}
			hooks.firePilotLvlUpSkillChangedHooks(skill1, initialChanges)

			-- Both hooks called twice
			assert.are.equal(2, #hook1Calls)
			assert.are.equal(2, #hook2Calls)

			-- Verify queuing behavior by checking call order/args
			-- If queuing works both hook1 & hook 2 are called with the initial changes then a second time
			-- with the new changes. If queuing is not working, then hook1 is called with initial, hook1 is
			-- called with the updated, hook2 is called with the updated and then finally called with the
			-- initial

			-- Both called first with the original changes
			assert.are.same({coresBonus = {old = 0, new = 1}}, hook1Calls[1])
			assert.are.same({coresBonus = {old = 0, new = 1}}, hook2Calls[1])

			-- Both called second with the updated changes
			assert.are.same({gridBonus = {old = 0, new = 2}}, hook1Calls[2])
			assert.are.same({gridBonus = {old = 0, new = 2}}, hook2Calls[2])

			-- Verify state tracker has final state
			local skillAddr = skill1:getAddress()
			local trackedState = memhack.stateTracker._skillTrackers[skillAddr]
			assert.is_not_nil(trackedState)
			assert.are.equal(2, trackedState.gridBonus)
			assert.are.equal(1, trackedState.coresBonus)
		end)
	end)

	describe("events integration", function()
		it("should have onPilotLvlUpSkillChanged event", function()
			assert.is_not_nil(hooks.events)
			assert.is_not_nil(hooks.events.onPilotLvlUpSkillChanged)
		end)

		it("should have created pilotLvlUpSkillChangedHooks array", function()
			assert.is_not_nil(originalHooks)
			assert.is_table(originalHooks)
		end)

	it("should dispatch onPilotLvlUpSkillChanged event when hook fires with original hooks", function()
		-- Restore original hooks (contains event dispatcher)
		-- The fire function already exists and will use the restored array
		hooks.pilotLvlUpSkillChangedHooks = originalHooks

		-- Track event dispatch
		local eventDispatched = false
		local eventArgs = nil

		-- Mock the event dispatch method
		local originalDispatch = hooks.events.onPilotLvlUpSkillChanged.dispatch
		hooks.events.onPilotLvlUpSkillChanged.dispatch = function(self, ...)
			eventDispatched = true
			eventArgs = {...}
		end

		-- Fire the hook
		local changes = {id = {old = "OldSkill", new = "NewSkill"}}
		hooks.firePilotLvlUpSkillChangedHooks(skill1, changes)

		-- Verify event was dispatched
		assert.is_true(eventDispatched)
		-- Note: Event receives prepended parent argument
		assert.are.equal(pilot, eventArgs[1])
		assert.are.equal(skill1, eventArgs[2])
		assert.are.same(changes, eventArgs[3])

		-- Restore
		hooks.events.onPilotLvlUpSkillChanged.dispatch = originalDispatch
	end)
	end)
end)
