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
			local TestStruct = structManager:define("TestStruct1", {
				value = { offset = 0x10, type = "int" },
			}, 0x00000042)  -- vtable as second parameter

			local instance = TestStruct.new(0x1000)
			local validatedInstance, err = instance:validate()

			assert.is_not_nil(validatedInstance)
			assert.is_nil(err)
		end)

		it("should fail verification when vtable doesn't match", function()
			local TestStruct = structManager:define("TestStruct2", {
				value = { offset = 0x10, type = "int" },
			}, 0x00000042)  -- vtable as second parameter

			local instance = TestStruct.new(0x2000)
			local validatedInstance, err = instance:validate()

			assert.is_nil(validatedInstance)
			assert.is_not_nil(err)
			assert.matches("VTable mismatch", err)
		end)

		it("should automatically add vtable field at offset 0", function()
			local TestStruct = structManager:define("TestStruct3", {
				value = { offset = 0x10, type = "int" },
			}, 0x00000042)  -- vtable as second parameter

			-- Check that vtable field was added
			assert.is_not_nil(TestStruct._layout.vtable)
			assert.equals(0, TestStruct._layout.vtable.offset)
			assert.equals("int", TestStruct._layout.vtable.type)
		end)

		it("should return nil and log error on auto verify failure", function()
			local TestStruct = structManager:define("TestStruct4", {
				value = { offset = 0x10, type = "int" },
			}, 0x00000042)  -- vtable as second parameter

			local result = TestStruct.new(0x2000, true)  -- Auto-verify enabled
			assert.is_nil(result)
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

			local TestStruct = structManager:define("TestStruct5", {
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

			local TestStruct = structManager:define("TestStruct6", {
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
			local TestStruct = structManager:define("TestStruct7", {
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
			local TestStruct = structManager:define("TestStruct8", {
				value = { offset = 0x10, type = "int" },
			})

			-- Use static validation since new(0) returns nil
			local validatedInstance, err = TestStruct.validate(0)

			assert.is_nil(validatedInstance)
			assert.matches("nil or 0", err)
		end)

		it("should fail verification when memory is not readable", function()
			local TestStruct = structManager:define("TestStruct9", {
				value = { offset = 0x10, type = "int" },
			})

			-- Address < 0x1000 is not readable in our mock
			local validatedInstance, err = TestStruct.validate(0x100)

			assert.is_nil(validatedInstance)
			assert.matches("not readable", err)
		end)
	end)

	describe("Validation Errors", function()
		it("should return nil and log error when verify arg is not a number or function", function()
			local result = structManager:define("TestStruct10", {
				value = { offset = 0x10, type = "int" },
			}, "not a number or function")
			assert.is_nil(result)
		end)
	end)

	describe("BoardPawn innate cores", function()
		local BoardPawn
		local CORE_NONE
		local CORE_NORMAL
		local CORE_BONUS
		local nextChunk = 0x50000000

		local function installByteArrayAlloc()
			memhack.dll.memory.allocByteArray = function(byteLen)
				local addr = nextChunk
				nextChunk = nextChunk + byteLen + 64
				return addr
			end
			memhack.dll.memory.freeByteArray = function() end
		end

		local function wireIntVector(vec, values)
			local capBytes = math.max(16, #values * 4 * 2)
			local head = memhack.dll.memory.allocByteArray(capBytes)
			for i, v in ipairs(values) do
				memhack.dll.memory.writeInt(head + (i - 1) * 4, v)
			end
			vec:_setHeadPtr(head)
			vec:_setNextPtr(head + #values * 4)
			vec:_setCapacityPtr(head + capBytes)
		end

		setup(function()
			installByteArrayAlloc()
			BoardPawn = memhack.structs.BoardPawn
			CORE_NONE = memhack.CORE_TYPE_NONE
			CORE_NORMAL = memhack.CORE_TYPE_NORMAL
			CORE_BONUS = memhack.CORE_TYPE_SKILL_BONUS
		end)

		it("reads every slot from a multi-entry hp vector", function()
			local pawn = BoardPawn.new(0x20000000, false)
			wireIntVector(pawn:getHpCores(), { CORE_NORMAL, CORE_BONUS })

			assert.are.same({ CORE_NORMAL, CORE_BONUS }, pawn:getHpCores():getIntList())
			assert.is_true(pawn:getHpCores():intListMatches({ CORE_NORMAL, CORE_BONUS }))
			assert.is_false(pawn:getHpCores():intListMatches({ CORE_NORMAL }))
		end)

		it("grows and shrinks hp cores via setIntListResizingIfNeeded", function()
			local pawn = BoardPawn.new(0x21000000, false)
			wireIntVector(pawn:getHpCores(), { CORE_NONE })
			local hpCores = pawn:getHpCores()

			assert.is_true(hpCores:setIntListResizingIfNeeded({ CORE_NORMAL, CORE_BONUS, CORE_NONE }))
			assert.are.same({
				CORE_NORMAL,
				CORE_BONUS,
				CORE_NONE,
			}, hpCores:getIntList())

			assert.is_true(hpCores:setIntListResizingIfNeeded({ CORE_NORMAL }))
			assert.are.same({ CORE_NORMAL }, hpCores:getIntList())
		end)

		it("treats partial multi-slot power as unpowered", function()
			local pawn = BoardPawn.new(0x22000000, false)
			wireIntVector(pawn:getHpCores(), { CORE_NORMAL, CORE_NONE })
			wireIntVector(pawn:getMoveCores(), { CORE_NORMAL, CORE_NORMAL })

			assert.is_false(pawn:getHpCores():isFullyPowered())
			assert.is_true(pawn:getMoveCores():isFullyPowered())
		end)

		it("matches move lists with different lengths as unequal", function()
			local pawn = BoardPawn.new(0x23000000, false)
			wireIntVector(pawn:getMoveCores(), { CORE_NORMAL, CORE_NORMAL })
			local moveCores = pawn:getMoveCores()

			assert.is_false(moveCores:intListMatches({ CORE_NORMAL }))
			assert.is_true(moveCores:intListMatches({ CORE_NORMAL, CORE_NORMAL }))
		end)
	end)
end)
