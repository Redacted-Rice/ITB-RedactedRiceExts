-- Tests for method_generation.lua functionality
-- Verifies automatic method generation for struct access and parent reference preservation

local specHelper = require("helpers/spec_helper")

-- Initialize the extension with mock DLL
local memhack = specHelper.initMemhack()
local methodGeneration = memhack.structManager._methodGeneration

describe("Method Generation Module", function()

	describe("wrapGetterToPreserveParent", function()
		local parentStruct, childStruct

		before_each(function()
			-- Create a mock child struct
			childStruct = {
				_name = "ChildStruct",
				_value = 42,
				getValue = function(self) return self._value end
			}

			-- Create a mock parent struct with getter
			parentStruct = {
				_name = "ParentStruct",
				_child = childStruct,
				getChild = function(self)
					return self._child
				end
			}
		end)

		it("should wrap getter to inject parent reference", function()
			-- Wrap the getter
			methodGeneration.wrapGetterToPreserveParent(parentStruct, "getChild")

			-- Call wrapped getter
			local retrievedChild = parentStruct:getChild()

			-- Verify child has parent reference
			assert.is_not_nil(retrievedChild._parent)
			assert.are.equal(parentStruct, retrievedChild._parent["ParentStruct"])
		end)

		it("should preserve existing parent references", function()
			-- Give parent struct its own parent
			local grandparent = {_name = "Grandparent"}
			parentStruct._parent = {Grandparent = grandparent}

			-- Wrap and call
			methodGeneration.wrapGetterToPreserveParent(parentStruct, "getChild")
			local retrievedChild = parentStruct:getChild()

			-- Child should have both parent and grandparent
			assert.are.equal(grandparent, retrievedChild._parent["Grandparent"])
			assert.are.equal(parentStruct, retrievedChild._parent["ParentStruct"])
		end)

		it("should maintain original getter functionality", function()
			methodGeneration.wrapGetterToPreserveParent(parentStruct, "getChild")

			local retrievedChild = parentStruct:getChild()

			-- Original fields should still work
			assert.are.equal(42, retrievedChild:getValue())
		end)

		it("should error if getter not found", function()
			assert.has_error(function()
				methodGeneration.wrapGetterToPreserveParent(parentStruct, "nonexistentGetter")
			end)
		end)

		it("should error if struct has no _name", function()
			parentStruct._name = nil

			assert.has_error(function()
				methodGeneration.wrapGetterToPreserveParent(parentStruct, "getChild")
			end)
		end)
	end)

	describe("makeParentGetterWrapper", function()
		it("should create parent getter method", function()
			local childStruct = {
				_name = "Child",
				_parent = {
					Parent = {_name = "Parent", _id = "parent42"}
				}
			}

			-- Create wrapper method
			methodGeneration.makeParentGetterWrapper(childStruct, "Parent")

			-- Verify method was created
			assert.is_function(childStruct.getParentParent)

			-- Call and verify
			local parent = childStruct:getParentParent()
			assert.are.equal("parent42", parent._id)
		end)

		it("should return nil when parent not found", function()
			local childStruct = {
				_name = "Child",
				_parent = {}
			}

			methodGeneration.makeParentGetterWrapper(childStruct, "Parent")

			local parent = childStruct:getParentParent()
			assert.is_nil(parent)
		end)

		it("should return nil when no parent table", function()
			local childStruct = {
				_name = "Child"
			}

			methodGeneration.makeParentGetterWrapper(childStruct, "Parent")

			local parent = childStruct:getParentParent()
			assert.is_nil(parent)
		end)
	end)

	describe("makeStructGetWrapper", function()
		it("should create wrapper getter", function()
			local struct = {
				_childObj = {
					_value = 100,
					get = function(self) return self._value end
				},
				getChildObj = function(self) return self._childObj end
			}

			-- Create wrapper
			methodGeneration.makeStructGetWrapper(struct, "childObj", "getChildValue")

			-- Verify method created
			assert.is_function(struct.getChildValue)

			-- Call and verify
			local value = struct:getChildValue()
			assert.are.equal(100, value)
		end)

		it("should use custom self getter name", function()
			local struct = {
				_childObj = {
					_data = "test",
					getData = function(self) return self._data end
				},
				getChildObj = function(self) return self._childObj end
			}

			methodGeneration.makeStructGetWrapper(struct, "childObj", "getChildData", "getData")

			local data = struct:getChildData()
			assert.are.equal("test", data)
		end)
	end)

	describe("makeStructSetWrapper", function()
		it("should create wrapper setter", function()
			local struct = {
				_childObj = {
					_value = 100,
					set = function(self, val) self._value = val end,
					get = function(self) return self._value end
				},
				getChildObj = function(self) return self._childObj end
			}

			-- Create wrapper
			methodGeneration.makeStructSetWrapper(struct, "childObj", "setChildValue")

			-- Verify method created
			assert.is_function(struct.setChildValue)

			-- Call and verify
			struct:setChildValue(200)
			assert.are.equal(200, struct._childObj:get())
		end)

		it("should use custom self setter name", function()
			local struct = {
				_childObj = {
					_data = "initial",
					setData = function(self, val) self._data = val end,
					getData = function(self) return self._data end
				},
				getChildObj = function(self) return self._childObj end
			}

			methodGeneration.makeStructSetWrapper(struct, "childObj", "setChildData", "setData")

			struct:setChildData("updated")
			assert.are.equal("updated", struct._childObj:getData())
		end)

		it("should handle multiple arguments", function()
			local struct = {
				_childObj = {
					_vals = {},
					setMulti = function(self, a, b, c)
						self._vals = {a, b, c}
					end
				},
				getChildObj = function(self) return self._childObj end
			}

			methodGeneration.makeStructSetWrapper(struct, "childObj", "setChildMulti", "setMulti")

			struct:setChildMulti(1, 2, 3)
			assert.are.same({1, 2, 3}, struct._childObj._vals)
		end)
	end)

	describe("wrapSetterToFireOnValueChange", function()
		it("should work with custom getter name", function()

			local struct = {
				_value = 10,
				customGetValue = function(self) return self._value end,
				setValue = function(self, val) self._value = val end  -- Setter must exist first
			}

			local fireCalls = {}
			local fireFn = function(obj, changes)
				table.insert(fireCalls, changes)
			end

			-- Create wrapper with custom getter
			methodGeneration.wrapSetterToFireOnValueChange(
				struct, "value", fireFn, nil, "customGetValue")

			-- setValue should now be wrapped
			assert.is_function(struct.setValue)

			-- Call the wrapped setter
			struct:setValue(20)

			-- Verify value changed
			assert.are.equal(20, struct._value)

			-- Verify hook was fired with correct change format
			assert.are.equal(1, #fireCalls)
			assert.is_not_nil(fireCalls[1].value)
			assert.are.equal(10, fireCalls[1].value.old)
			assert.are.equal(20, fireCalls[1].value.new)
		end)

		it("should not fire hook when value doesn't change", function()
			local struct = {
				_value = 10,
				getValue = function(self) return self._value end,
				setValue = function(self, val) self._value = val end
			}

			local fireCalls = {}
			local fireFn = function(obj, changes)
				table.insert(fireCalls, changes)
			end

			methodGeneration.wrapSetterToFireOnValueChange(
				struct, "value", fireFn)

			-- Set to same value
			struct:setValue(10)

			-- Verify hook was not fired
			assert.are.equal(0, #fireCalls)
		end)

		it("should error if setter not found", function()
			local struct = {}
			local fireFn = function() end

			local success, err = pcall(function()
				methodGeneration.wrapSetterToFireOnValueChange(
					struct, "value", fireFn, "nonexistentSetter", "value")
			end)

			assert.is_false(success)
			assert.is_not_nil(err:match("Setter 'nonexistentSetter' not found"))
		end)
	end)

	describe("generateStructSetterToFireOnAnyValueChange", function()

		it("should detect memhack structs by isMemhackObj field", function()
			local fireCalls = {}
			local fireFn = function(self, changedNew, changedOld)
				table.insert(fireCalls, {changedNew = changedNew, changedOld = changedOld})
			end

			local stateDefinition = {"field1", "field2"}
			local setter = methodGeneration.generateStructSetterToFireOnAnyValueChange(
				fireFn, stateDefinition, nil)

			-- Create a source struct with isMemhackObj (like a real memhack struct)
			local sourceStruct = {
				isMemhackObj = true,
				field1 = 100,
				field2 = 200,
				getField1 = function(self) return self.field1 end,
				getField2 = function(self) return self.field2 end
			}

			-- Create target struct
			local targetStruct = {
				field1 = 0,
				field2 = 0,
				getField1 = function(self) return self.field1 end,
				getField2 = function(self) return self.field2 end,
				setField1 = function(self, val) self.field1 = val end,
				setField2 = function(self, val) self.field2 = val end
			}

			-- Call setter with struct (should detect it's a struct by _name)
			setter(targetStruct, sourceStruct)

			-- Verify values were copied
			assert.are.equal(100, targetStruct.field1)
			assert.are.equal(200, targetStruct.field2)

			-- Verify hook was fired
			assert.are.equal(1, #fireCalls)
		end)

		it("should work with plain tables without isMemhackObj", function()
			local fireCalls = {}
			local fireFn = function(self, changedNew, changedOld)
				table.insert(fireCalls, {changedNew = changedNew, changedOld = changedOld})
			end

			local stateDefinition = {"field1"}
			local setter = methodGeneration.generateStructSetterToFireOnAnyValueChange(
				fireFn, stateDefinition, nil)

			local targetStruct = {
				field1 = 0,
				getField1 = function(self) return self.field1 end,
				setField1 = function(self, val) self.field1 = val end
			}

			-- Call with plain table (no isMemhackObj field)
			setter(targetStruct, {field1 = 50})

			assert.are.equal(50, targetStruct.field1)
			assert.are.equal(1, #fireCalls)
		end)

		it("should distinguish memhack structs from plain tables", function()
			local captureStateCallCount = 0
			local originalCaptureState = memhack.stateTracker.captureState

			-- Spy on captureState to count calls
			memhack.stateTracker.captureState = function(...)
				captureStateCallCount = captureStateCallCount + 1
				return originalCaptureState(...)
			end

			local fireFn = function() end
			local stateDefinition = {"field1"}
			local setter = methodGeneration.generateStructSetterToFireOnAnyValueChange(
				fireFn, stateDefinition, nil)

			local targetStruct = {
				field1 = 0,
				getField1 = function(self) return self.field1 end,
				setField1 = function(self, val) self.field1 = val end
			}

			-- Test 1: Plain table (no isMemhackObj)
			setter(targetStruct, {field1 = 10})
			local plainTableCalls = captureStateCallCount

			-- Test 2: Memhack struct (has isMemhackObj)
			captureStateCallCount = 0
			local memhackStruct = {
				isMemhackObj = true,
				field1 = 20,
				getField1 = function(self) return self.field1 end
			}
			setter(targetStruct, memhackStruct)
			local memhackStructCalls = captureStateCallCount

			-- Plain table should call captureState only once (for target state check)
			-- Memhack struct should call it twice (once to convert source, once for target)
			assert.are.equal(1, plainTableCalls)
			assert.are.equal(2, memhackStructCalls)

			-- Restore original
			memhack.stateTracker.captureState = originalCaptureState
		end)
	end)

	describe("Nested parent references", function()
		it("should properly chain parent references through multiple levels", function()
			-- Create grandparent -> parent -> child hierarchy
			local child = {
				_name = "Child",
				_value = 1,
				getValue = function(self) return self._value end
			}

			local parent = {
				_name = "Parent",
				_child = child,
				getChild = function(self) return self._child end
			}

			local grandparent = {
				_name = "Grandparent",
				_parent = parent,
				getParent = function(self) return self._parent end
			}

			-- Wrap both getters
			methodGeneration.wrapGetterToPreserveParent(grandparent, "getParent")
			methodGeneration.wrapGetterToPreserveParent(parent, "getChild")

			-- Navigate down
			local retrievedParent = grandparent:getParent()
			local retrievedChild = retrievedParent:getChild()

			-- Child should have both parent and grandparent references
			assert.are.equal(parent, retrievedChild._parent["Parent"])
			assert.are.equal(grandparent, retrievedChild._parent["Grandparent"])

			-- Add parent getter wrappers
			methodGeneration.makeParentGetterWrapper(retrievedChild, "Parent")
			methodGeneration.makeParentGetterWrapper(retrievedChild, "Grandparent")

			-- Verify we can navigate back up
			assert.are.equal(parent, retrievedChild:getParentParent())
			assert.are.equal(grandparent, retrievedChild:getParentGrandparent())
		end)
	end)
end)
