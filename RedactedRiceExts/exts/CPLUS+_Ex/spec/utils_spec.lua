-- Tests for utils module

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("Utils Module", function()
	local utils

	before_each(function()
		helper.resetState()
		utils = plus_manager._subobjects.utils
	end)

	describe("deepcopy", function()
		it("should copy primitives, simple tables, and arrays with independence", function()
			-- Primitives
			assert.equals(5, utils.deepcopy(5))
			assert.equals("test", utils.deepcopy("test"))
			assert.equals(true, utils.deepcopy(true))
			assert.is_nil(utils.deepcopy(nil))

			-- Simple table
			local orig = {a = 1, b = 2, c = 3}
			local copy = utils.deepcopy(orig)
			assert.is_not(orig, copy)
			assert.equals(1, copy.a)
			orig.a = 99
			assert.equals(1, copy.a)

			-- Array
			local arr = {1, 2, 3}
			local arrCopy = utils.deepcopy(arr)
			assert.is_not(arr, arrCopy)
			assert.equals(2, arrCopy[2])
		end)

		it("should deep copy nested tables with independence", function()
			local orig = {
				level1 = {
					level2 = {
						level3 = {value = 42}
					}
				}
			}
			local copy = utils.deepcopy(orig)

			assert.is_not(orig.level1, copy.level1)
			assert.is_not(orig.level1.level2, copy.level1.level2)
			assert.equals(42, copy.level1.level2.level3.value)

			orig.level1.level2.level3.value = 99
			assert.equals(42, copy.level1.level2.level3.value)
		end)

		it("should handle circular references and metatables", function()
			-- Circular reference
			local orig = {a = 1}
			orig.self = orig
			local copy = utils.deepcopy(orig)
			assert.equals(copy, copy.self)

			-- Metatable
			local meta = {__index = function() return "meta" end}
			local withMeta = setmetatable({a = 1}, meta)
			local metaCopy = utils.deepcopy(withMeta)
			assert.equals(meta, getmetatable(metaCopy))
		end)
	end)

	describe("deepcopyInPlace", function()
		it("should copy into existing table, clearing old values and handling nested data", function()
			local dest = {old = "value", x = 1}
			local src = {a = 1, b = 2, nested = {value = 42}}

			local result = utils.deepcopyInPlace(dest, src)

			assert.equals(dest, result)
			assert.equals(1, dest.a)
			assert.equals(2, dest.b)
			assert.is_nil(dest.old)
			assert.is_nil(dest.x)
			assert.equals(42, dest.nested.value)
			assert.is_not(src.nested, dest.nested)
		end)
	end)

	describe("setToString", function()
		it("should convert sets to comma separated strings", function()
			assert.equals("", utils.setToString({}))
			assert.equals("skill1", utils.setToString({skill1 = true}))

			local result = utils.setToString({skill1 = true, skill2 = true, skill3 = true})
			assert.is_true(result:find("skill1") ~= nil)
			assert.is_true(result:find("skill2") ~= nil)
			assert.is_true(result:find("skill3") ~= nil)
			assert.is_true(result:find(",") ~= nil)
		end)
	end)

	describe("normalizeReusabilityToInt", function()
		local REUSABILITY

		before_each(function()
			REUSABILITY = cplus_plus_ex.REUSABLILITY
		end)

		it("should normalize valid reusability values", function()
			-- Nil
			assert.is_nil(utils.normalizeReusabilityToInt(nil))

			-- Valid integers
			assert.equals(REUSABILITY.REUSABLE, utils.normalizeReusabilityToInt(REUSABILITY.REUSABLE))
			assert.equals(REUSABILITY.PER_PILOT, utils.normalizeReusabilityToInt(REUSABILITY.PER_PILOT))
			assert.equals(REUSABILITY.PER_RUN, utils.normalizeReusabilityToInt(REUSABILITY.PER_RUN))

			-- String variants
			assert.equals(REUSABILITY.REUSABLE, utils.normalizeReusabilityToInt("REUSABLE"))
			assert.equals(REUSABILITY.REUSABLE, utils.normalizeReusabilityToInt("reusable"))
			assert.equals(REUSABILITY.PER_PILOT, utils.normalizeReusabilityToInt("PER_PILOT"))
			assert.equals(REUSABILITY.PER_PILOT, utils.normalizeReusabilityToInt("per_pilot"))
		end)

		it("should return nil for invalid inputs", function()
			assert.is_nil(utils.normalizeReusabilityToInt(999))
			assert.is_nil(utils.normalizeReusabilityToInt(-1))
			assert.is_nil(utils.normalizeReusabilityToInt("invalid"))
			assert.is_nil(utils.normalizeReusabilityToInt(""))
			assert.is_nil(utils.normalizeReusabilityToInt({}))
			assert.is_nil(utils.normalizeReusabilityToInt(true))
		end)
	end)

	describe("sortByValue", function()
		it("should sort tables by values with optional custom comparator", function()
			-- Numeric ascending (default)
			local t1 = {a = 3, b = 1, c = 2}
			local sorted1 = utils.sortByValue(t1)
			assert.equals("b", sorted1[1])
			assert.equals("c", sorted1[2])
			assert.equals("a", sorted1[3])

			-- Custom comparator (descending)
			local sorted2 = utils.sortByValue(t1, function(a, b) return a > b end)
			assert.equals("a", sorted2[1])
			assert.equals("b", sorted2[3])

			-- String values
			local t2 = {first = "zebra", second = "apple"}
			local sorted3 = utils.sortByValue(t2)
			assert.equals("second", sorted3[1])

			-- Edge cases
			assert.equals(0, #utils.sortByValue({}))
			assert.equals(1, #utils.sortByValue({only = 42}))
		end)
	end)
end)
