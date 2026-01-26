-- Tests for state_tracker.lua functionality
-- Verifies state capturing, comparison, and tracking

local specHelper = require("helpers/spec_helper")

-- Initialize the extension with mock DLL
local memhack = specHelper.initMemhack()
local stateTracker = memhack.stateTracker

describe("State Tracker Module", function()
	describe("captureValue", function()
		it("should capture value using standard getter", function()
			local obj = {
				_value = 42,
				getValue = function(self) return self._value end
			}

			local captured = stateTracker.captureValue(obj, "value")
			assert.are.equal(42, captured)
		end)

		it("should capture value using custom getter function name", function()
			local obj = {
				_data = "test",
				customGetData = function(self) return self._data end
			}

			local captured = stateTracker.captureValue(obj, "customGetData")
			assert.are.equal("test", captured)
		end)
	end)

	describe("captureState", function()
		local mockObj

		before_each(function()
			mockObj = {
				_name = "TestName",
				_level = 5,
				_xp = 100,
				_score = 500,
				getName = function(self) return self._name end,
				getLevel = function(self) return self._level end,
				getXp = function(self) return self._xp end,
				getScore = function(self) return self._score end,
				customNameGetter = function(self) return "Custom: " .. self._name end
			}
		end)

		it("should capture state using array style field names", function()
			local stateDefinition = {"name", "level", "xp"}

			local capturedState = stateTracker.captureState(mockObj, stateDefinition)

			assert.are.equal("TestName", capturedState.name)
			assert.are.equal(5, capturedState.level)
			assert.are.equal(100, capturedState.xp)
			-- Not in definition
			assert.is_nil(capturedState.score)
		end)

		it("should capture state using custom getter names", function()
			local stateDefinition = {
				name = "customNameGetter",
				level = "getLevel"
			}

			local capturedState = stateTracker.captureState(mockObj, stateDefinition)

			assert.are.equal("Custom: TestName", capturedState.name)
			assert.are.equal(5, capturedState.level)
			-- Not in definition
			assert.is_nil(capturedState.xp)
			assert.is_nil(capturedState.score)
		end)

		it("should support mixed definition styles", function()
			local stateDefinition = {
				name = "customNameGetter",
				"level",
				xp = "getXp",
				"score"
			}

			local capturedState = stateTracker.captureState(mockObj, stateDefinition)

			assert.are.equal("Custom: TestName", capturedState.name)
			assert.are.equal(5, capturedState.level)
			assert.are.equal(100, capturedState.xp)
			assert.are.equal(500, capturedState.score)
		end)

		it("should only capture specified fields when valsToCheck provided", function()
			local stateDefinition = {"name", "level", "xp", "score"}
			local valsToCheck = {name = true, xp = true}

			local capturedState = stateTracker.captureState(mockObj, stateDefinition, valsToCheck)

			assert.are.equal("TestName", capturedState.name)
			assert.are.equal(100, capturedState.xp)
			-- not in vals to check
			assert.is_nil(capturedState.level)
			assert.is_nil(capturedState.score)
		end)
	end)

	describe("compareStates", function()
		it("should detect changed values", function()
			local oldState = {
				name = "OldName",
				level = 1,
				xp = 50
			}

			local newState = {
				name = "NewName",
				level = 2,
				xp = 50
			}

			local changes = stateTracker.compareStates(oldState, newState)

			assert.is_not_nil(changes.name)
			assert.are.equal("OldName", changes.name.old)
			assert.are.equal("NewName", changes.name.new)

			assert.is_not_nil(changes.level)
			assert.are.equal(1, changes.level.old)
			assert.are.equal(2, changes.level.new)

			assert.is_nil(changes.xp) -- Unchanged
		end)

		it("should return empty table when no changes", function()
			local state1 = {
				name = "SameName",
				level = 5,
				xp = 100
			}

			local state2 = {
				name = "SameName",
				level = 5,
				xp = 100
			}

			local changes = stateTracker.compareStates(state1, state2)

			-- Not an array return so we have to iterate to count...
			assert.is_table(changes)
			local count = 0
			for _ in pairs(changes) do count = count + 1 end
			assert.are.equal(0, count)
		end)

		it("should detect all types of value changes", function()
			local oldState = {
				str = "old",
				num = 10,
				bool = true,
				tbl = {a = 1}
			}

			local newState = {
				str = "new",
				num = 20,
				bool = false,
				tbl = {a = 2}
			}

			local changes = stateTracker.compareStates(oldState, newState)
			-- All should report changes
			assert.is_not_nil(changes.str)
			assert.is_not_nil(changes.num)
			assert.is_not_nil(changes.bool)
			assert.is_not_nil(changes.tbl)
		end)

		it("should detect table changes by reference, not by content", function()
			-- Tables are compared by reference in Lua, so even identical
			-- content will be detected as changed if it's a different table instance
			local tbl1 = {a = 1}
			local oldState = {
				tbl = tbl1
			}

			local newState = {
				tbl = {a = 1}  -- Same content, different table instance
			}

			local changes = stateTracker.compareStates(oldState, newState)

			-- Should detect change because it's a different table reference
			assert.is_not_nil(changes.tbl)
			assert.are.equal(tbl1, changes.tbl.old)
			assert.are.not_equal(tbl1, changes.tbl.new)
		end)

		it("should not detect changes for same table reference", function()
			local tbl = {a = 1}
			local oldState = {
				tbl = tbl
			}

			local newState = {
				tbl = tbl  -- Same table reference
			}

			local changes = stateTracker.compareStates(oldState, newState)

			-- Should not detect change because it's the same table reference
			assert.is_nil(changes.tbl)
		end)

		it("should handle nil values correctly", function()
			local oldState = {
				value = nil
			}

			local newState = {
				value = 42
			}

			local changes = stateTracker.compareStates(oldState, newState)

			assert.is_not_nil(changes.value)
			assert.is_nil(changes.value.old)
			assert.are.equal(42, changes.value.new)
		end)

		it("should detect removed fields by default", function()
			local oldState = {field1 = 10, field2 = "old", field3 = 30}
			local newState = {field1 = 10, field2 = "old"}

			local changes = stateTracker.compareStates(oldState, newState)

			-- field3 was removed and should be in changes (default behavior)
			assert.is_not_nil(changes.field3)
			assert.are.equal(30, changes.field3.old)
			assert.is_nil(changes.field3.new)
		end)

		it("should detect removed fields when set to explicitly", function()
			local oldState = {field1 = 10, field2 = "old", field3 = 30}
			local newState = {field1 = 10, field2 = "old"}

			local changes = stateTracker.compareStates(oldState, newState, true)

			-- field3 was removed and should be in changes
			assert.is_not_nil(changes.field3)
			assert.are.equal(30, changes.field3.old)
			assert.is_nil(changes.field3.new)
		end)

		it("should detect both changed and removed fields when set to check removed", function()
			local oldState = {field1 = 10, field2 = "old", field3 = 30}
			local newState = {field1 = 20, field2 = "old"}

			local changes = stateTracker.compareStates(oldState, newState, true)

			-- field1 changed
			assert.is_not_nil(changes.field1)
			assert.are.equal(10, changes.field1.old)
			assert.are.equal(20, changes.field1.new)

			-- field3 removed
			assert.is_not_nil(changes.field3)
			assert.are.equal(30, changes.field3.old)
			assert.is_nil(changes.field3.new)

			-- field2 unchanged
			assert.is_nil(changes.field2)
		end)

		it("should not detect removed fields when set to not check removed", function()
			local oldState = {field1 = 10, field2 = "removed"}
			local newState = {field1 = 10}

			local changes = stateTracker.compareStates(oldState, newState, false)

			-- field2 removed but checkRemoved=false so shouldn't be detected
			assert.is_nil(changes.field2)
			assert.is_true(next(changes) == nil)
		end)

		it("should handle multiple removed fields when checkRemoved=true", function()
			local oldState = {f1 = 1, f2 = 2, f3 = 3, f4 = 4}
			local newState = {f1 = 1}

			local changes = stateTracker.compareStates(oldState, newState, true)

			-- f2, f3, f4 all removed
			assert.is_not_nil(changes.f2)
			assert.is_not_nil(changes.f3)
			assert.is_not_nil(changes.f4)
			assert.are.equal(2, changes.f2.old)
			assert.are.equal(3, changes.f3.old)
			assert.are.equal(4, changes.f4.old)
			assert.is_nil(changes.f2.new)
			assert.is_nil(changes.f3.new)
			assert.is_nil(changes.f4.new)
		end)
	end)
end)
