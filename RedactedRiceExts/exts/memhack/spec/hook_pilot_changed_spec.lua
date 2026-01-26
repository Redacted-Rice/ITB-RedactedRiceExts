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

		-- Initialize hooks (this sets up the hook arrays and fire functions)
		hooks:addTo(hooks)
		hooks:initBroadcastHooks(hooks)
		hooks:load()  -- This adds the event dispatcher hooks

		-- Save reference to original hooks array (now contains event dispatcher)
		originalHooks = hooks.pilotChangedHooks
		-- Create a fresh empty array for tests
		hooks.pilotChangedHooks = {}
		-- Rebuild broadcast function to point to the new empty array
		hooks:initBroadcastHooks(hooks)

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
			hooks.firePilotChangedHooks(mockPilot, {})
			assert.is_true(called)
		end)

		it("should allow adding multiple hooks", function()
			local count = 0

			hooks:addPilotChangedHook(function() count = count + 1 end)
			hooks:addPilotChangedHook(function() count = count + 10 end)
			hooks:addPilotChangedHook(function() count = count + 100 end)

			assert.are.equal(3, #hooks.pilotChangedHooks)

			hooks.firePilotChangedHooks(mockPilot, {})
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

			hooks.firePilotChangedHooks(mockPilot, {})

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
			hooks.firePilotChangedHooks(mockPilot, {})

			-- Second hook should still be called
			assert.is_true(hook2Called)
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
		-- Restore original hooks (contains event dispatcher) and rebuild broadcast function
		hooks.pilotChangedHooks = originalHooks
		hooks:initBroadcastHooks(hooks)

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
