-- Tests for hooks.lua functionality
-- Verifies hook registration, firing, and parent argument handling

local specHelper = require("helpers/spec_helper")
local mocks = require("helpers/mocks")

-- Initialize the extension with mock DLL
local memhack = specHelper.initMemhack()
local hooks = memhack.hooks
local stateTracker = memhack.stateTracker

describe("Hooks Module", function()
	describe("buildBroadcastFunc without parent args", function()
		local callLog
		local fireFunc
		local originalHooks

		before_each(function()
			callLog = {}

			-- Save original hooks and create fresh array
			originalHooks = hooks.pilotChangedHooks
			hooks.pilotChangedHooks = {}

			-- Build the broadcast function
			fireFunc = hooks.buildBroadcastFunc("pilotChangedHooks", hooks, nil, nil, nil)
		end)

		after_each(function()
			if originalHooks then
				hooks.pilotChangedHooks = originalHooks
			end
		end)

		it("should fire hook with original arguments", function()
			hooks.pilotChangedHooks[1] = function(pilot, changes)
				table.insert(callLog, {pilot = pilot, changes = changes})
			end

			local mockPilot = {id = "TestPilot"}
			local changes = {level = {old = 1, new = 2}}

			fireFunc(mockPilot, changes)

			assert.are.equal(1, #callLog)
			assert.are.same(mockPilot, callLog[1].pilot)
			assert.are.same(changes, callLog[1].changes)
		end)

		it("should fire multiple registered hooks", function()
			local hook1Called = false
			local hook2Called = false

			hooks.pilotChangedHooks[1] = function() hook1Called = true end
			hooks.pilotChangedHooks[2] = function() hook2Called = true end

			fireFunc()

			assert.is_true(hook1Called)
			assert.is_true(hook2Called)
		end)

		it("should handle hooks with no arguments", function()
			local called = false

			hooks.pilotChangedHooks[1] = function()
				called = true
			end

			fireFunc()

			assert.is_true(called)
		end)
	end)

	describe("buildBroadcastFunc with parent prepending", function()
		local callLog
		local fireFunc
		local originalHooks

		before_each(function()
			callLog = {}

			-- Save original hooks and create fresh array
			originalHooks = hooks.pilotLvlUpSkillChangedHooks
			hooks.pilotLvlUpSkillChangedHooks = {}

			-- Build the broadcast function with parent prepending
			fireFunc = hooks.buildBroadcastFunc("pilotLvlUpSkillChangedHooks", hooks, nil, {"Pilot"}, nil)
		end)

		after_each(function()
			if originalHooks then
				hooks.pilotLvlUpSkillChangedHooks = originalHooks
			end
		end)

		it("should prepend single parent to arguments", function()
			hooks.pilotLvlUpSkillChangedHooks[1] = function(pilot, skill, changes)
				table.insert(callLog, {pilot = pilot, skill = skill, changes = changes})
			end

			local mockPilot = mocks.createMockPilot("TestPilot")
			local mockSkill = mocks.createMockSkill({skillId = "TestSkill"})
			mockSkill._parent = {Pilot = mockPilot}
			local changes = {id = {old = "OldSkill", new = "TestSkill"}}

			fireFunc(mockSkill, changes)

			assert.are.equal(1, #callLog)
			assert.is_not_nil(callLog[1].pilot)
			assert.are.equal(mockPilot, callLog[1].pilot)
			assert.are.equal(mockSkill, callLog[1].skill)
			assert.are.same(changes, callLog[1].changes)
		end)

		it("should handle multiple parents", function()
			-- Create a new fire function with multiple parents
			local multiParentFireFunc = hooks.buildBroadcastFunc("pilotLvlUpSkillChangedHooks", hooks, nil, {"Grandparent", "Parent"}, nil)

			local grandparent = {type = "grandparent"}
			local parent = {type = "parent"}

			hooks.pilotLvlUpSkillChangedHooks[1] = function(gp, p, obj, data)
				table.insert(callLog, {gp = gp, p = p, obj = obj, data = data})
			end

			local obj = {
				value = 42,
				_parent = {
					Grandparent = grandparent,
					Parent = parent
				}
			}
			local data = {change = "test"}

			multiParentFireFunc(obj, data)

			assert.are.equal(1, #callLog)
			assert.are.equal(grandparent, callLog[1].gp)
			assert.are.equal(parent, callLog[1].p)
			assert.are.equal(obj, callLog[1].obj)
			assert.are.equal(data, callLog[1].data)
		end)

		it("should pass nil when parent not found and maintain arg count", function()
			local arg1, arg2, arg3
			local argCount = 0
			local hookCalled = false

			hooks.pilotLvlUpSkillChangedHooks[1] = function(...)
				hookCalled = true
				argCount = select('#', ...)
				arg1, arg2, arg3 = ...
			end

			-- Skill without parent (no _parent table at all)
			local mockSkill = {
				id = "TestSkill"
			}
			local changes = {test = true}

			fireFunc(mockSkill, changes)

			-- Verify hook was called
			assert.is_true(hookCalled, "Hook should have been called")

			-- Should have 3 args: nil parent, skill, changes
			assert.are.equal(3, argCount)
			assert.is_nil(arg1)  -- Parent is nil
			assert.are.equal(mockSkill, arg2)
			assert.are.same(changes, arg3)
		end)

		it("should preserve argument order with parent first", function()
			-- Create fire function with single parent
			local parentFireFunc = hooks.buildBroadcastFunc("pilotLvlUpSkillChangedHooks", hooks, nil, {"Parent"}, nil)

			local argOrder = {}

			hooks.pilotLvlUpSkillChangedHooks[1] = function(...)
				local args = {...}
				for i, arg in ipairs(args) do
					if arg then
						table.insert(argOrder, {index = i, type = arg.type})
					end
				end
			end

			local obj = {
				type = "object",
				_parent = {
					Parent = {type = "parent"}
				}
			}

			parentFireFunc(obj, {type = "data"})

			assert.are.equal(3, #argOrder)
			assert.are.equal("parent", argOrder[1].type)
			assert.are.equal("object", argOrder[2].type)
			assert.are.equal("data", argOrder[3].type)
		end)
	end)

	describe("re-entrant hook wrapper", function()
		local originalHooks
		local mockPilot

		before_each(function()
			originalHooks = hooks.pilotChangedHooks
			hooks.pilotChangedHooks = {}

			-- Re-apply re-entrant wrapper
			stateTracker.wrapHooksToUpdateStateTrackers()

			mockPilot = mocks.createMockPilot({pilotId = "TestPilot", level = 1, xp = 10})
		end)

		after_each(function()
			hooks.pilotChangedHooks = originalHooks
		end)

		it("should handle multiple sequential re-entrant calls", function()
			local callCount = 0

			hooks:addPilotChangedHook(function(p, changes)
				callCount = callCount + 1

				if callCount == 1 then
					mockPilot._xp = 20
					hooks.firePilotChangedHooks(mockPilot, {xp = {old = 10, new = 20}})
				elseif callCount == 2 then
					mockPilot._level = 2
					hooks.firePilotChangedHooks(mockPilot, {level = {old = 1, new = 2}})
				end
			end)

			local initialChanges = {xp = {old = 0, new = 10}}
			hooks.firePilotChangedHooks(mockPilot, initialChanges)

			assert.are.equal(3, callCount)
		end)

		it("should prevent infinite loops with max iteration limit", function()
			local callCount = 0

			hooks:addPilotChangedHook(function(p, changes)
				callCount = callCount + 1
				mockPilot._xp = mockPilot._xp + 1
				hooks.firePilotChangedHooks(mockPilot, {xp = {old = mockPilot._xp - 1, new = mockPilot._xp}})
			end)

			mockPilot._xp = 1
			local initialChanges = {xp = {old = 0, new = 1}}

			local success, err = pcall(function()
				hooks.firePilotChangedHooks(mockPilot, initialChanges)
			end)

			assert.is_false(success)
			assert.is_not_nil(err:find("exceeded max iterations"))
			assert.are.equal(20, callCount)
		end)

		it("should complete all hooks before checking for re-entrant changes", function()
			local hook1Calls = {}
			local hook2Calls = {}

			hooks:addPilotChangedHook(function(p, changes)
				table.insert(hook1Calls, changes)

				if #hook1Calls == 1 then
					mockPilot._level = 2
					hooks.firePilotChangedHooks(mockPilot, {level = {old = 1, new = 2}})
				end
			end)

			hooks:addPilotChangedHook(function(p, changes)
				table.insert(hook2Calls, changes)
			end)

			local initialChanges = {xp = {old = 0, new = 10}}
			hooks.firePilotChangedHooks(mockPilot, initialChanges)

			-- Both hooks called twice
			assert.are.equal(2, #hook1Calls)
			assert.are.equal(2, #hook2Calls)

			-- Verify both hooks completed with initial changes before re-firing
			-- Both called first with the original changes
			assert.are.same({xp = {old = 0, new = 10}}, hook1Calls[1])
			assert.are.same({xp = {old = 0, new = 10}}, hook2Calls[1])

			-- Both called second with the updated changes
			assert.are.same({level = {old = 1, new = 2}}, hook1Calls[2])
			assert.are.same({level = {old = 1, new = 2}}, hook2Calls[2])
		end)

		it("should handle two hooks that cancel each other out", function()
			local hook1Called = 0
			local hook2Called = 0

			hooks:addPilotChangedHook(function(p, changes)
				hook1Called = hook1Called + 1
				if hook1Called == 1 then
					mockPilot._xp = 50
					hooks.firePilotChangedHooks(mockPilot, {xp = {old = 10, new = 50}})
				end
			end)

			hooks:addPilotChangedHook(function(p, changes)
				hook2Called = hook2Called + 1
				if hook2Called == 1 then
					mockPilot._xp = 10  -- Revert to original
				end
			end)

			local initialChanges = {xp = {old = 0, new = 10}}
			hooks.firePilotChangedHooks(mockPilot, initialChanges)

			-- Both hooks called once - re-entrant flag was set but final state shows no changes
			assert.are.equal(1, hook1Called)
			assert.are.equal(1, hook2Called)
			-- Final value is 10
			assert.are.equal(10, mockPilot._xp)
		end)

		it("should not fire if changes are nil or empty", function()
			local callCount = 0

			hooks:addPilotChangedHook(function(p, changes)
				callCount = callCount + 1
			end)

			hooks.firePilotChangedHooks(mockPilot, nil)
			hooks.firePilotChangedHooks(mockPilot, {})

			assert.are.equal(0, callCount)
		end)
	end)

	describe("memory leak prevention", function()
		it("should cleanup stale pilot trackers", function()
			-- Setup mock game state
			local mockPilot1 = mocks.createMockPilot({pilotId = "Pilot1", level = 1})
			local mockPilot2 = mocks.createMockPilot({pilotId = "Pilot2", level = 2})

			_G.Game = {
				GetSquadPilots = function()
					return {mockPilot1}  -- Only pilot1 is active
				end
			}

			-- Manually add trackers for both pilots
			stateTracker._pilotTrackers[mockPilot1:getAddress()] = {level = 1}
			stateTracker._pilotTrackers[mockPilot2:getAddress()] = {level = 2}  -- Stale!

			-- Verify both exist before cleanup
			assert.is_not_nil(stateTracker._pilotTrackers[mockPilot1:getAddress()])
			assert.is_not_nil(stateTracker._pilotTrackers[mockPilot2:getAddress()])

			-- Run cleanup
			stateTracker.cleanupStaleTrackers()

			-- Verify only active pilot remains
			assert.is_not_nil(stateTracker._pilotTrackers[mockPilot1:getAddress()])
			assert.is_nil(stateTracker._pilotTrackers[mockPilot2:getAddress()])

			-- Cleanup
			_G.Game = nil
			stateTracker._pilotTrackers = {}
		end)

		it("should cleanup stale skill trackers", function()
			local mockPilot = mocks.createMockPilot({pilotId = "TestPilot", level = 1})
			local skills = mockPilot:getLvlUpSkills()
			local activeSkill = skills:getSkill1()
			local staleSkillAddr = 999999  -- Fake address for non existent skill

			_G.Game = {
				GetSquadPilots = function()
					return {mockPilot}
				end
			}

			-- Add trackers for active and stale skills
			stateTracker._skillTrackers[activeSkill:getAddress()] = {id = "Skill1"}
			stateTracker._skillTrackers[staleSkillAddr] = {id = "StaleSkill"}

			-- Verify both exist
			assert.is_not_nil(stateTracker._skillTrackers[activeSkill:getAddress()])
			assert.is_not_nil(stateTracker._skillTrackers[staleSkillAddr])

			-- Run cleanup
			stateTracker.cleanupStaleTrackers()

			-- Verify only active skill remains
			assert.is_not_nil(stateTracker._skillTrackers[activeSkill:getAddress()])
			assert.is_nil(stateTracker._skillTrackers[staleSkillAddr])

			-- Cleanup
			_G.Game = nil
			stateTracker._skillTrackers = {}
		end)

		it("should clear all trackers when Game is nil", function()
			stateTracker._pilotTrackers[123] = {level = 1}
			stateTracker._skillTrackers[456] = {id = "Skill"}

			_G.Game = nil

			stateTracker.cleanupStaleTrackers()

			-- Verify all cleared
			local pilotCount = 0
			for _ in pairs(stateTracker._pilotTrackers) do pilotCount = pilotCount + 1 end
			local skillCount = 0
			for _ in pairs(stateTracker._skillTrackers) do skillCount = skillCount + 1 end

			assert.are.equal(0, pilotCount)
			assert.are.equal(0, skillCount)
		end)
	end)

	describe("error handling", function()
		it("should catch and log hook errors without stopping execution", function()
			local originalHooks = hooks.pilotChangedHooks
			hooks.pilotChangedHooks = {}

			local hook2Called = false
			hooks.pilotChangedHooks[1] = function()
				error("Test error in hook")
			end
			hooks.pilotChangedHooks[2] = function()
				hook2Called = true
			end

			local fireFunc = hooks.buildBroadcastFunc("pilotChangedHooks", hooks, nil, nil, nil)

			-- Should not throw error - hooks module logs errors instead
			fireFunc()

			-- Second hook should still be called despite first one erroring
			assert.is_true(hook2Called)

			-- Cleanup
			hooks.pilotChangedHooks = originalHooks
		end)
	end)
end)
