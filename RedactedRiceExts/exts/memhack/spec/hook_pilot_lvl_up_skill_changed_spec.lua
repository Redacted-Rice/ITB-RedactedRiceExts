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
		-- Initialize hooks
		hooks:addTo(hooks)
		hooks:initBroadcastHooks(hooks)
		hooks:load()  -- This adds the event dispatcher hooks

		-- Save and clear hooks array
		originalHooks = hooks.pilotLvlUpSkillChangedHooks
		hooks.pilotLvlUpSkillChangedHooks = {}
		-- Rebuild broadcast function to point to the new empty array
		hooks:initBroadcastHooks(hooks)

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

			hooks.firePilotLvlUpSkillChangedHooks(skill1, {})
			assert.is_true(called)
		end)

		it("should allow adding multiple hooks", function()
			local count = 0

			hooks:addPilotLvlUpSkillChangedHook(function() count = count + 1 end)
			hooks:addPilotLvlUpSkillChangedHook(function() count = count + 10 end)

			assert.are.equal(2, #hooks.pilotLvlUpSkillChangedHooks)

			hooks.firePilotLvlUpSkillChangedHooks(skill1, {})
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

			hooks.firePilotLvlUpSkillChangedHooks(orphanSkill, {})

			-- Pilot should be nil (not omitted)
			assert.is_nil(capturedPilot)
			assert.are.equal(orphanSkill, capturedSkill)
			assert.are.same({}, capturedChanges)
		end)

		it("should prepend correct pilot for skill1", function()
			local capturedPilot

			hooks:addPilotLvlUpSkillChangedHook(function(p, s, c)
				capturedPilot = p
			end)

			hooks.firePilotLvlUpSkillChangedHooks(skill1, {})

			assert.are.equal(pilot, capturedPilot)
			assert.are.equal("TestPilot", capturedPilot:getIdStr())
		end)

		it("should prepend correct pilot for skill2", function()
			local capturedPilot

			hooks:addPilotLvlUpSkillChangedHook(function(p, s, c)
				capturedPilot = p
			end)

			hooks.firePilotLvlUpSkillChangedHooks(skill2, {})

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

			hooks.firePilotLvlUpSkillChangedHooks(skill1, {})

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
			hooks.firePilotLvlUpSkillChangedHooks(skill1, {})

			-- Second hook should still be called
			assert.is_true(hook2Called)
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
		-- Restore original hooks (contains event dispatcher) and rebuild broadcast function
		hooks.pilotLvlUpSkillChangedHooks = originalHooks
		hooks:initBroadcastHooks(hooks)

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
