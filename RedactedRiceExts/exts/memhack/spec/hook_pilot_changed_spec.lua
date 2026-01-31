-- Tests for pilotChanged hook
-- Verifies that pilotChanged hook fires when pilot properties change
-- Hook signature: (pilot, changes) where changes = {field = {old = val, new = val}}

local specHelper = require("helpers/spec_helper")
local mocks = require("helpers/mocks")

-- Initialize the extension with mock DLL
local memhack = specHelper.initMemhack()
local hooks = memhack.hooks

describe("Pilot Changed Hook", function()
	local hooksCalled
	local mockPilot
	local originalHooks

	before_each(function()
		hooksCalled = {}

		-- Save original hooks array and clear it for testing
		-- The fire function already exists from memhack initialization
		originalHooks = hooks.pilotChangedHooks
		hooks.pilotChangedHooks = {}

		mockPilot = mocks.createMockPilot({
			pilotId = "TestPilot",
			level = 1,
			xp = 25
		})
	end)

	after_each(function()
		-- Restore original hooks
		if originalHooks then
			hooks.pilotChangedHooks = originalHooks
		end
	end)

	describe("hook registration", function()
		it("should allow adding hook callback", function()
			local called = false

			hooks:addPilotChangedHook(function()
				called = true
			end)

			-- Verify hook was added
			assert.are.equal(1, #hooks.pilotChangedHooks)

			-- Fire hook and verify it was called
			local changes = {level = {old = 1, new = 2}}
			hooks.firePilotChangedHooks(mockPilot, changes)
			assert.is_true(called)
		end)

		it("should allow adding multiple hooks", function()
			local count = 0

			hooks:addPilotChangedHook(function() count = count + 1 end)
			hooks:addPilotChangedHook(function() count = count + 10 end)
			hooks:addPilotChangedHook(function() count = count + 100 end)

			assert.are.equal(3, #hooks.pilotChangedHooks)

			local changes = {level = {old = 1, new = 2}}
			hooks.firePilotChangedHooks(mockPilot, changes)
			assert.are.equal(111, count)
		end)
	end)

	describe("hook firing with arguments", function()
		it("should pass pilot and changes to hook", function()
			local capturedPilot, capturedChanges

			hooks:addPilotChangedHook(function(pilot, changes)
				capturedPilot = pilot
				capturedChanges = changes
			end)

			local changes = {
				level = {old = 1, new = 2}
			}
			hooks.firePilotChangedHooks(mockPilot, changes)

			assert.are.equal(mockPilot, capturedPilot)
			assert.are.same(changes, capturedChanges)
		end)
	end)

	describe("multiple hook execution", function()
		it("should call all registered hooks in order", function()
			local callOrder = {}

			hooks:addPilotChangedHook(function()
				table.insert(callOrder, 1)
			end)
			hooks:addPilotChangedHook(function()
				table.insert(callOrder, 2)
			end)
			hooks:addPilotChangedHook(function()
				table.insert(callOrder, 3)
			end)

			local changes = {level = {old = 1, new = 2}}
			hooks.firePilotChangedHooks(mockPilot, changes)

			assert.are.equal(3, #callOrder)
			assert.are.equal(1, callOrder[1])
			assert.are.equal(2, callOrder[2])
			assert.are.equal(3, callOrder[3])
		end)

		it("should pass same arguments to all hooks", function()
			local captures = {}

			hooks:addPilotChangedHook(function(pilot, changes)
				table.insert(captures, {pilot = pilot, changes = changes})
			end)
			hooks:addPilotChangedHook(function(pilot, changes)
				table.insert(captures, {pilot = pilot, changes = changes})
			end)

			local changes = {level = {old = 1, new = 2}}
			hooks.firePilotChangedHooks(mockPilot, changes)

			assert.are.equal(2, #captures)
			assert.are.equal(mockPilot, captures[1].pilot)
			assert.are.equal(mockPilot, captures[2].pilot)
			assert.are.same(changes, captures[1].changes)
			assert.are.same(changes, captures[2].changes)
		end)
	end)

	describe("error handling", function()
		it("should continue calling hooks after one fails", function()
			local hook2Called = false

			hooks:addPilotChangedHook(function()
				error("Test error")
			end)
			hooks:addPilotChangedHook(function()
				hook2Called = true
			end)

			-- Should not throw, but log error
			local changes = {level = {old = 1, new = 2}}
			hooks.firePilotChangedHooks(mockPilot, changes)

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
			-- This test verifies that the re-entrant wrapper is actually being used for pilotChanged hooks
			-- by checking the order and arguments of hook calls.

			local hook1Calls = {}
			local hook2Calls = {}

			-- First hook modifies pilot during first call and triggers re-entrant call
			hooks:addPilotChangedHook(function(p, changes)
				table.insert(hook1Calls, changes)

				if #hook1Calls == 1 then
					-- Modify pilot state
					mockPilot._level = 2
					-- Trigger re-entrant call - should set flag and return immediately
					hooks.firePilotChangedHooks(mockPilot, {level = {old = 1, new = 2}})
				end
			end)

			-- Second hook just records changes
			hooks:addPilotChangedHook(function(p, changes)
				table.insert(hook2Calls, changes)
			end)

			local initialChanges = {xp = {old = 0, new = 10}}
			hooks.firePilotChangedHooks(mockPilot, initialChanges)

			-- Both hooks called twice
			assert.are.equal(2, #hook1Calls)
			assert.are.equal(2, #hook2Calls)

			-- Verify queuing behavior by checking call order/args
			-- If queuing works both hook1 & hook 2 are called with the initial changes then a second time
			-- with the new changes. If queuing is not working, then hook1 is called with initial, hook1 is
			-- called with the updated, hook2 is called with the updated and then finally called with the
			-- initial

			-- Both called first with the original changes
			assert.are.same({xp = {old = 0, new = 10}}, hook1Calls[1])
			assert.are.same({xp = {old = 0, new = 10}}, hook2Calls[1])

			-- Both called second with the updated changes
			assert.are.same({level = {old = 1, new = 2}}, hook1Calls[2])
			assert.are.same({level = {old = 1, new = 2}}, hook2Calls[2])

			-- Verify state tracker has final state
			local pilotAddr = mockPilot:getAddress()
			local trackedState = memhack.stateTracker._pilotTrackers[pilotAddr]
			assert.is_not_nil(trackedState)
			assert.are.equal(2, trackedState.level)
			assert.are.equal(25, trackedState.xp)
		end)
	end)

	describe("events integration", function()
		it("should have onPilotChanged event", function()
			assert.is_not_nil(hooks.events)
			assert.is_not_nil(hooks.events.onPilotChanged)
		end)

		it("should have created pilotChangedHooks array", function()
			-- Verify that the original hooks array exists (created by addTo)
			assert.is_not_nil(originalHooks)
			assert.is_table(originalHooks)
		end)

	it("should dispatch onPilotChanged event when hook fires with original hooks", function()
		-- Restore original hooks (contains event dispatcher)
		-- The fire function already exists and will use the restored array
		hooks.pilotChangedHooks = originalHooks

		-- Track event dispatch
		local eventDispatched = false
		local eventArgs = nil

		-- Mock the event dispatch method
		local originalDispatch = hooks.events.onPilotChanged.dispatch
		hooks.events.onPilotChanged.dispatch = function(self, ...)
			eventDispatched = true
			eventArgs = {...}
		end

		-- Fire the hook
		local changes = {level = {old = 1, new = 2}}
		hooks.firePilotChangedHooks(mockPilot, changes)

		-- Verify event was dispatched
		assert.is_true(eventDispatched)
		assert.are.equal(mockPilot, eventArgs[1])
		assert.are.same(changes, eventArgs[2])

		-- Restore
		hooks.events.onPilotChanged.dispatch = originalDispatch
	end)
	end)
end)
