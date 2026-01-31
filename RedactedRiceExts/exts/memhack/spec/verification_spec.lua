-- Tests for structure verification feature

local helper = require("helpers/spec_helper")

describe("Structure Verification", function()
	local memhack
	local structManager

	setup(function()
		-- Initialize memhack with mock DLL
		memhack = helper.initMemhack()
		structManager = memhack.structManager
		
		-- Enhance mock memory for verification tests
		local originalReadPointer = memhack.dll.memory.readPointer
		memhack.dll.memory.readPointer = function(addr)
			-- Mock: return specific vtable addresses
			if addr == 0x1000 then return 0x00400042 end  -- Correct vtable
			if addr == 0x2000 then return 0x12345678 end  -- Wrong vtable
			return originalReadPointer(addr)
		end
		
		local originalReadInt = memhack.dll.memory.readInt
		memhack.dll.memory.readInt = function(addr)
			-- Mock: return specific values for testing
			if addr == 0x1010 then return 42 end
			if addr == 0x2010 then return -1 end
			return originalReadInt(addr)
		end
	end)

	teardown(function()
		-- Clean up test structures
		if structManager then
			for k in pairs(structManager._structures) do
				if k:match("^TestStruct") then
					structManager._structures[k] = nil
				end
			end
		end
	end)

	describe("vtable Verification", function()
		it("should pass verification when vtable matches", function()
			local TestStruct = structManager.define("TestStruct1", {
				value = { offset = 0x10, type = "int" },
			}, 0x00000042)  -- vtable as second parameter

			local instance = TestStruct.new(0x1000)
			local validatedInstance, err = instance:validate()

			assert.is_not_nil(validatedInstance)
			assert.is_nil(err)
		end)

		it("should fail verification when vtable doesn't match", function()
			local TestStruct = structManager.define("TestStruct2", {
				value = { offset = 0x10, type = "int" },
			}, 0x00000042)  -- vtable as second parameter

			local instance = TestStruct.new(0x2000)
			local validatedInstance, err = instance:validate()

			assert.is_nil(validatedInstance)
			assert.is_not_nil(err)
			assert.matches("VTable mismatch", err)
		end)

		it("should automatically add vtable field at offset 0", function()
			local TestStruct = structManager.define("TestStruct3", {
				value = { offset = 0x10, type = "int" },
			}, 0x00000042)  -- vtable as second parameter

			-- Check that vtable field was added
			assert.is_not_nil(TestStruct._layout.vtable)
			assert.equals(0, TestStruct._layout.vtable.offset)
			assert.equals("int", TestStruct._layout.vtable.type)
		end)

		it("should throw error on auto verify failure", function()
			local TestStruct = structManager.define("TestStruct4", {
				value = { offset = 0x10, type = "int" },
			}, 0x00000042)  -- vtable as second parameter

			assert.has_error(function()
				TestStruct.new(0x2000, true)  -- Auto-verify enabled
			end)
		end)
	end)

	describe("Custom Function Verification", function()
		it("should pass verification when function returns true", function()
			local validateFunc = function(self)
				local val = self:getValue()
				if val >= 0 and val <= 100 then
					return true
				end
				return false, "Value out of range"
			end
			
			local TestStruct = structManager.define("TestStruct5", {
				value = { offset = 0x10, type = "int" },
			}, validateFunc)  -- validation function as second parameter

			local instance = TestStruct.new(0x1000)
			local validatedInstance, err = instance:validate()

			assert.is_not_nil(validatedInstance)
			assert.is_nil(err)
		end)

		it("should fail verification when function returns false", function()
			local validateFunc = function(self)
				local val = self:getValue()
				if val >= 0 and val <= 100 then
					return true
				end
				return false, "Value out of range: " .. val
			end
			
			local TestStruct = structManager.define("TestStruct6", {
				value = { offset = 0x10, type = "int" },
			}, validateFunc)  -- validation function as second parameter

			local instance = TestStruct.new(0x2000)
			local validatedInstance, err = instance:validate()

			assert.is_nil(validatedInstance)
			assert.is_not_nil(err)
			assert.matches("Value out of range", err)
		end)
	end)

	describe("Basic Verification Checks", function()
		it("should validate with just an address", function()
			local TestStruct = structManager.define("TestStruct7", {
				value = { offset = 0x10, type = "int" },
			})

			-- Call static validate method
			local validatedInstance, err = TestStruct.validate(0x1000)
			assert.is_not_nil(validatedInstance)
			assert.is_nil(err)
			
			validatedInstance, err = TestStruct:validate(0x1000)
			assert.is_not_nil(validatedInstance)
			assert.is_nil(err)
		end)
		
		it("should fail verification when address is 0", function()
			local TestStruct = structManager.define("TestStruct8", {
				value = { offset = 0x10, type = "int" },
			})

			-- Use static validation since new(0) returns nil
			local validatedInstance, err = TestStruct.validate(0)

			assert.is_nil(validatedInstance)
			assert.matches("nil or 0", err)
		end)

		it("should fail verification when memory is not readable", function()
			local TestStruct = structManager.define("TestStruct9", {
				value = { offset = 0x10, type = "int" },
			})

			-- Address < 0x1000 is not readable in our mock
			local validatedInstance, err = TestStruct.validate(0x100)

			assert.is_nil(validatedInstance)
			assert.matches("not readable", err)
		end)
	end)

	describe("Validation Errors", function()
		it("should error when verify arg is not a number or function", function()
			assert.has_error(function()
				structManager.define("TestStruct10", {
					value = { offset = 0x10, type = "int" },
				}, "not a number or function")
			end)
		end)
	end)
end)
