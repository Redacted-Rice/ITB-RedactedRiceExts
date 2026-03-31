-- Tests for memory_analyzer functionality
-- Focuses on happy path flows for capturing, comparing, and analyzing memory

local specHelper = require("helpers/spec_helper")

-- Initialize the extension with mock DLL
local memhack = specHelper.initMemhack()

-- Load memory analyzer directly (not exposed on memhack by default)
local MemoryAnalyzer = require("utils/memory_analyzer/init")

-- Helper functions for creating common memory patterns
local function bytes4(b1, b2, b3, b4)
	return string.char(b1 or 0x00, b2 or 0x00, b3 or 0x00, b4 or 0x00)
end

local function zeros(count)
	return string.rep("\0", count)
end

local function int32(value)
	-- Little endian 32 bit integer
	return string.char(
		value % 256,
		math.floor(value / 256) % 256,
		math.floor(value / 65536) % 256,
		math.floor(value / 16777216) % 256
	)
end

describe("Memory Analyzer Module", function()
	local analyzer
	local mockMemory

	before_each(function()
		-- Initialize memory analyzer with the mock DLL
		MemoryAnalyzer.init(memhack.dll)

		-- Clear any existing analyzers
		MemoryAnalyzer._memoryAnalyzers = {}

		-- Setup mock memory that we can control
		mockMemory = {}
		memhack.dll.memory.readByteArray = function(addr, size)
			return mockMemory[addr] or string.rep("\0", size)
		end

		-- Setup mock pointer reading for pointer chain tests
		memhack.dll.memory.readPointer = function(addr)
			if addr == 0x1000 then return 0x2000 end
			if addr == 0x2000 then return 0x3000 end
			return 0
		end
	end)

	after_each(function()
		if analyzer then
			MemoryAnalyzer.remove(analyzer.id)
		end
	end)

	describe("Analyzer Creation and Management", function()
		it("should create a new analyzer", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 16, {
				baseAddress = 0x1000
			})

			assert.is_not_nil(analyzer)
			assert.equals("test_analyzer", analyzer.id)
			assert.equals(16, analyzer.size)
			assert.equals(0x1000, analyzer.baseAddress)
			assert.is_true(analyzer.enabled)
		end)

		it("should retrieve analyzer by ID", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 16, {baseAddress = 0x1000})

			local retrieved = MemoryAnalyzer.get("test_analyzer")
			assert.equals(analyzer, retrieved)
		end)

		it("should list all analyzer IDs", function()
			MemoryAnalyzer.new("analyzer1", 16, {baseAddress = 0x1000})
			MemoryAnalyzer.new("analyzer2", 16, {baseAddress = 0x2000})

			local ids = MemoryAnalyzer.list()
			assert.equals(2, #ids)
			assert.is_true(ids[1] == "analyzer1" or ids[1] == "analyzer2")
		end)

		it("should remove analyzer by ID", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 16, {baseAddress = 0x1000})

			MemoryAnalyzer.remove("test_analyzer")
			local retrieved = MemoryAnalyzer.get("test_analyzer")
			assert.is_nil(retrieved)
		end)

		it("should enable and disable analyzer", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 16, {
				baseAddress = 0x1000,
				enabled = false
			})

			assert.is_false(analyzer.enabled)

			analyzer:enable()
			assert.is_true(analyzer.enabled)

			analyzer:disable()
			assert.is_false(analyzer.enabled)
		end)
	end)

	describe("Memory Capture Flow", function()
		it("should capture memory snapshot", function()
			mockMemory[0x1000] = string.char(0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)

			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000})

			local captureIdx = analyzer:capture()
			assert.equals(1, captureIdx)
			assert.equals(1, analyzer:getCaptureCount())
		end)

		it("should capture multiple snapshots", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000})

			mockMemory[0x1000] = string.char(0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)
			analyzer:capture()

			mockMemory[0x1000] = string.char(0x01, 0x02, 0xFF, 0x04, 0x05, 0x06, 0x07, 0x08)
			analyzer:capture()

			mockMemory[0x1000] = string.char(0x01, 0x02, 0xAA, 0x04, 0x05, 0x06, 0x07, 0x08)
			analyzer:capture()

			assert.equals(3, analyzer:getCaptureCount())
		end)

		it("should retrieve capture by index", function()
			mockMemory[0x1000] = string.char(0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000})
			analyzer:capture()

			local capture = analyzer:getCapture(1)
			assert.is_not_nil(capture)
			assert.equals(0x1000, capture.address)
			assert.equals(8, #capture.data)
		end)

		it("should clear all captures", function()
			mockMemory[0x1000] = string.char(0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000})
			analyzer:capture()
			analyzer:capture()

			analyzer:clear()
			assert.equals(0, analyzer:getCaptureCount())
		end)

		it("should not capture when disabled", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {
				baseAddress = 0x1000,
				enabled = false
			})

			local captureIdx = analyzer:capture()
			assert.is_nil(captureIdx)
			assert.equals(0, analyzer:getCaptureCount())
		end)
	end)

	describe("Change Detection - getChangedOnce", function()
		it("should detect changed and unchanged bytes", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 16, {baseAddress = 0x1000, alignment = 4})

			-- Capture 1: Mixed values
			mockMemory[0x1000] = bytes4(0xAA, 0xAA, 0xAA, 0xAA) .. zeros(4) ..
			                     bytes4(0xBB, 0xBB, 0xBB, 0xBB) .. zeros(4)
			analyzer:capture()

			-- Capture 2: First 4 bytes stay same, rest changes
			mockMemory[0x1000] = bytes4(0xAA, 0xAA, 0xAA, 0xAA) .. bytes4(0xFF, 0xFF, 0xFF, 0xFF) ..
			                     bytes4(0xCC, 0xCC, 0xCC, 0xCC) .. bytes4(0xFF, 0xFF, 0xFF, 0xFF)
			analyzer:capture()

			-- Capture 3: First 4 bytes still same, middle changes again
			mockMemory[0x1000] = bytes4(0xAA, 0xAA, 0xAA, 0xAA) .. bytes4(0x11, 0x11, 0x11, 0x11) ..
			                     bytes4(0xCC, 0xCC, 0xCC, 0xCC) .. bytes4(0x22, 0x22, 0x22, 0x22)
			analyzer:capture()

			local result = analyzer:getChangedOnce()

			-- filtered should contain the changed ranges (offsets 4-15)
			assert.is_not_nil(result.filtered)
			assert.equals(1, #result.filtered, "Should find exactly 1 changed range")
			assert.equals(4, result.filtered[1].start, "Changed range should start at offset 4")
			assert.equals(15, result.filtered[1].endOffset, "Changed range should end at offset 15")

			-- unfiltered should contain the unchanged range (offset 0-3)
			assert.is_not_nil(result.unfiltered)
			assert.equals(1, #result.unfiltered, "Should find exactly 1 unchanged range")
			assert.equals(0, result.unfiltered[1].start, "Unchanged range should start at offset 0")
			assert.equals(3, result.unfiltered[1].endOffset, "Unchanged range should end at offset 3")
		end)
	end)

	describe("Change Detection - getUnchanged", function()
		it("should detect bytes that never changed", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 12, {baseAddress = 0x1000, alignment = 4})

			-- Capture 1
			mockMemory[0x1000] = bytes4(0xAA, 0xAA, 0xAA, 0xAA) .. zeros(4) ..
			                     bytes4(0xBB, 0xBB, 0xBB, 0xBB)
			analyzer:capture()

			-- Capture 2: Change middle 4 bytes
			mockMemory[0x1000] = bytes4(0xAA, 0xAA, 0xAA, 0xAA) .. bytes4(0xFF, 0xFF, 0xFF, 0xFF) ..
			                     bytes4(0xBB, 0xBB, 0xBB, 0xBB)
			analyzer:capture()

			-- Capture 3: Change middle 4 bytes again
			mockMemory[0x1000] = bytes4(0xAA, 0xAA, 0xAA, 0xAA) .. bytes4(0x11, 0x11, 0x11, 0x11) ..
			                     bytes4(0xBB, 0xBB, 0xBB, 0xBB)
			analyzer:capture()

			local result = analyzer:getUnchanged()

			-- Should have ranges for first and last 4 bytes (offsets 0-3 and 8-11)
			assert.is_not_nil(result.filtered)
			assert.equals(2, #result.filtered, "Should find exactly 2 unchanged ranges")

			-- Verify the correct offsets were detected
			local foundOffset0 = false
			local foundOffset8 = false
			for _, range in ipairs(result.filtered) do
				if range.start == 0 and range.endOffset == 3 then foundOffset0 = true end
				if range.start == 8 and range.endOffset == 11 then foundOffset8 = true end
			end
			assert.is_true(foundOffset0, "Should detect unchanged bytes at offset 0-3")
			assert.is_true(foundOffset8, "Should detect unchanged bytes at offset 8-11")

			-- unfiltered should contain the changed range (offset 4-7)
			assert.is_not_nil(result.unfiltered)
			assert.equals(1, #result.unfiltered, "Should find exactly 1 changed range")
			assert.equals(4, result.unfiltered[1].start, "Changed range should be at offset 4-7")
		end)
	end)

	describe("Change Detection - getChangedEvery", function()
		it("should detect bytes changed in every capture comparison", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000, alignment = 1})

			-- Byte 0: changes every time (0x10 -> 0x20 -> 0x30)
			-- Byte 1: changes every time (0x11 -> 0x21 -> 0x31)
			-- Byte 2: stays same until last (0x12 -> 0x12 -> 0x33)
			-- Rest stay same
			mockMemory[0x1000] = string.char(0x10, 0x11, 0x12, 0x00, 0x00, 0x00, 0x00, 0x00)
			analyzer:capture()
			mockMemory[0x1000] = string.char(0x20, 0x21, 0x12, 0x00, 0x00, 0x00, 0x00, 0x00)
			analyzer:capture()
			mockMemory[0x1000] = string.char(0x30, 0x31, 0x33, 0x00, 0x00, 0x00, 0x00, 0x00)
			analyzer:capture()

			local result = analyzer:getChangedEvery()

			assert.is_not_nil(result)
			assert.is_table(result.filtered)
			assert.is_true(#result.filtered > 0)

			-- Bytes 0 and 1 should be in filtered (changed every time)
			local foundByte0 = false
			local foundByte1 = false
			for _, range in ipairs(result.filtered) do
				if range.start <= 0 and range.endOffset >= 0 then foundByte0 = true end
				if range.start <= 1 and range.endOffset >= 1 then foundByte1 = true end
			end
			assert.is_true(foundByte0, "Should detect byte 0 changed every time")
			assert.is_true(foundByte1, "Should detect byte 1 changed every time")
		end)
	end)

	describe("Change Detection - getCustomChanges", function()
		it("should apply custom comparator function", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000, alignment = 1})

			mockMemory[0x1000] = string.char(0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80)
			analyzer:capture()
			mockMemory[0x1000] = string.char(0x11, 0x21, 0x31, 0x41, 0x51, 0x61, 0x71, 0x81)
			analyzer:capture()

			-- Custom comparator: find bytes where value is >= 0x40 in all captures
			local customFunc = function(selectedCaptures, byteIdx)
				for _, capture in ipairs(selectedCaptures) do
					local byte = string.byte(capture.data, byteIdx)
					if not byte or byte < 0x40 then
						return false
					end
				end
				return true
			end

			local result = analyzer:getCustomChanges(nil, customFunc)

			assert.is_not_nil(result)
			assert.is_table(result.filtered)
			assert.is_true(#result.filtered > 0)

			-- Should find bytes at offsets 3-7 (values >= 0x40)
			for _, range in ipairs(result.filtered) do
				assert.is_true(range.start >= 3, "All filtered ranges should start at offset 3 or later")
			end
		end)
	end)

	describe("Pattern Matching", function()
		it("should find offsets matching exact value pattern across captures", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 16, {baseAddress = 0x1000, alignment = 4})

			-- We're looking for a 4-byte value that progresses as 100 -> 200 -> 300

			-- Capture 1: offset 0 has value 100, offset 4 has value 999, offset 8 has junk
			mockMemory[0x1000] = int32(100) .. int32(999) .. bytes4(0xFF, 0xFF, 0xFF, 0xFF) .. int32(0)
			analyzer:capture()

			-- Capture 2: offset 0 has value 200, offset 4 has value 888, offset 8 has junk
			mockMemory[0x1000] = int32(200) .. int32(888) .. bytes4(0xAA, 0xAA, 0xAA, 0xAA) .. int32(0)
			analyzer:capture()

			-- Capture 3: offset 0 has value 300, offset 4 has value 777, offset 8 has junk
			mockMemory[0x1000] = int32(300) .. int32(777) .. bytes4(0xBB, 0xBB, 0xBB, 0xBB) .. int32(0)
			analyzer:capture()

			-- Search for pattern: 100 -> 200 -> 300 at the same offset
			local result = analyzer:getMatchingPattern({100, 200, 300})

			assert.is_not_nil(result)
			assert.is_not_nil(result.filtered)
			assert.equals(1, #result.filtered, "Should find exactly 1 matching range")

			-- Verify offset 0 was found (the only offset with pattern 100->200->300)
			local range = result.filtered[1]
			assert.equals(0, range.start, "Pattern should match at offset 0")
			assert.is_true(range.endOffset >= 0, "Range should include offset 0")
		end)

		it("should handle nil wildcard patterns correctly", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 12, {baseAddress = 0x1000, alignment = 4})

			-- Pattern: 50 -> anything -> 150
			-- Should match offset 0: 50 -> 100 -> 150
			-- Should NOT match offset 4 or 8

			mockMemory[0x1000] = int32(50) .. int32(255) .. int32(0)
			analyzer:capture()

			mockMemory[0x1000] = int32(100) .. int32(256) .. int32(0)
			analyzer:capture()

			mockMemory[0x1000] = int32(150) .. int32(257) .. int32(0)
			analyzer:capture()

			-- Pattern: 50, wildcard, 150
			local result = analyzer:getMatchingPattern({50, nil, 150})

			assert.is_not_nil(result)
			assert.is_not_nil(result.filtered)
			assert.equals(1, #result.filtered, "Should find exactly 1 matching range")
			assert.equals(0, result.filtered[1].start, "Pattern should match at offset 0")
		end)

		it("should handle named wildcard patterns with same value constraint", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 16, {baseAddress = 0x1000, alignment = 4})

			-- Pattern: $x -> $x -> $y -> $y
			-- This means captures 1 and 2 must have same value, captures 3 and 4 must have same value
			-- At offset 0: 42 -> 42 -> 100 -> 100 (MATCH)
			-- At offset 4: 1 -> 2 -> 3 -> 4 (NO MATCH - all different)
			-- At offset 8: 50 -> 50 -> 50 -> 50 (MATCH - but $x=50 and $y=50, still valid)

			mockMemory[0x1000] = int32(42) .. int32(1) .. int32(50) .. int32(0)
			analyzer:capture()

			mockMemory[0x1000] = int32(42) .. int32(2) .. int32(50) .. int32(0)
			analyzer:capture()

			mockMemory[0x1000] = int32(100) .. int32(3) .. int32(50) .. int32(0)
			analyzer:capture()

			mockMemory[0x1000] = int32(100) .. int32(4) .. int32(50) .. int32(0)
			analyzer:capture()

			-- Pattern: same value in captures 1&2, same value in captures 3&4
			local result = analyzer:getMatchingPattern({"$x", "$x", "$y", "$y"})

			assert.is_not_nil(result)
			assert.is_not_nil(result.filtered)
			assert.equals(2, #result.filtered, "Should find 2 matching ranges (offsets 0 and 8)")

			-- Verify offsets 0 and 8 were found
			local foundOffset0 = false
			local foundOffset8 = false
			for _, range in ipairs(result.filtered) do
				if range.start == 0 then foundOffset0 = true end
				if range.start == 8 then foundOffset8 = true end
			end
			assert.is_true(foundOffset0, "Should match at offset 0")
			assert.is_true(foundOffset8, "Should match at offset 8")
		end)
	end)

	describe("Result Storage and Retrieval", function()
		it("should store and retrieve results by ID", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000, alignment = 4})

			mockMemory[0x1000] = int32(0) .. bytes4(0xFF, 0xFF, 0xFF, 0xFF)
			analyzer:capture()

			mockMemory[0x1000] = bytes4(0xFF, 0xFF, 0xFF, 0xFF) .. bytes4(0xFF, 0xFF, 0xFF, 0xFF)
			analyzer:capture()

			-- Store result with ID
			local originalResult = analyzer:getChangedOnce(nil, "changes")

			-- Retrieve and verify it's the same result object
			local result = analyzer:getResult("changes")
			assert.is_not_nil(result)
			assert.equals(originalResult, result, "Retrieved result should be same object")
			assert.is_not_nil(result.filtered)
			assert.equals(1, #result.filtered, "Should have 1 changed range")
			assert.equals(0, result.filtered[1].start, "Changed range should start at offset 0")
		end)

		it("should list all result IDs", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000, alignment = 4})

			mockMemory[0x1000] = int32(0) .. bytes4(0xFF, 0xFF, 0xFF, 0xFF)
			analyzer:capture()
			analyzer:capture()

			analyzer:getChangedOnce(nil, "result1")
			analyzer:getUnchanged(nil, "result2")

			local ids = analyzer:listResults()
			assert.equals(2, #ids)
		end)

		it("should remove result by ID", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000, alignment = 4})

			mockMemory[0x1000] = int32(0) .. bytes4(0xFF, 0xFF, 0xFF, 0xFF)
			analyzer:capture()
			analyzer:capture()

			analyzer:getChangedOnce(nil, "changes")
			analyzer:removeResult("changes")

			local result = analyzer:getResult("changes")
			assert.is_nil(result)
		end)
	end)

	describe("Utility Functions - Aligned Value Reading", function()
		local utils

		before_each(function()
			-- Access utils module
			utils = require("utils/memory_analyzer/utils")
		end)

		it("should read byte-aligned values", function()
			local data = string.char(0x01, 0x02, 0x03, 0x04)

			assert.equals(0x01, utils.readAlignedValue(data, 0, 1))
			assert.equals(0x02, utils.readAlignedValue(data, 1, 1))
			assert.equals(0x03, utils.readAlignedValue(data, 2, 1))
		end)

		it("should read 2-byte aligned values (short)", function()
			-- Little endian: 0x0201 = 0x01 + 0x02*256 = 513
			local data = string.char(0x01, 0x02, 0x03, 0x04)

			assert.equals(0x0201, utils.readAlignedValue(data, 0, 2))
			assert.equals(0x0403, utils.readAlignedValue(data, 2, 2))
		end)

		it("should read 4-byte aligned values (int/pointer)", function()
			-- Little endian: 0x04030201
			local data = string.char(0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)

			local value1 = utils.readAlignedValue(data, 0, 4)
			assert.equals(0x04030201, value1)

			local value2 = utils.readAlignedValue(data, 4, 4)
			assert.equals(0x08070605, value2)
		end)
	end)

	describe("Utility Functions - Capture Index Parsing", function()
		local utils

		before_each(function()
			utils = require("utils/memory_analyzer/utils")
		end)

		it("should parse nil as all captures", function()
			local indices = utils.parseCaptureIndices(nil, 5)
			assert.equals(5, #indices)
			assert.equals(1, indices[1])
			assert.equals(5, indices[5])
		end)

		it("should parse number as last N captures", function()
			local indices = utils.parseCaptureIndices(3, 10)
			assert.equals(3, #indices)
			assert.equals(8, indices[1])
			assert.equals(9, indices[2])
			assert.equals(10, indices[3])
		end)

		it("should parse array as specific indices", function()
			local indices = utils.parseCaptureIndices({2, 5, 7}, 10)
			assert.equals(3, #indices)
			assert.equals(2, indices[1])
			assert.equals(5, indices[2])
			assert.equals(7, indices[3])
		end)
	end)

	describe("Value Enrichment Flow", function()
		it("should add value progressions to results", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000, alignment = 4})

			-- Capture 1: offset 4-7 has value 1
			mockMemory[0x1000] = int32(0) .. int32(1)
			analyzer:capture()

			-- Capture 2: offset 4-7 has value 2
			mockMemory[0x1000] = int32(0) .. int32(2)
			analyzer:capture()

			-- Capture 3: offset 4-7 has value 3
			mockMemory[0x1000] = int32(0) .. int32(3)
			analyzer:capture()

			-- Get changes and add value data
			local result = analyzer:getChangedOnce()
			analyzer:addAllCapturesValues(result)

			-- Check that values were added with correct progression
			assert.is_not_nil(result.filtered)
			assert.equals(1, #result.filtered, "Should find exactly 1 changed range")

			local range = result.filtered[1]
			assert.equals(4, range.start, "Changed range should be at offset 4")
			assert.is_not_nil(range.values)
			assert.equals(1, #range.values, "Should have 1 progression (for offset 4)")

			local progression = range.values[1]
			assert.equals(3, #progression, "Should have 3 values in progression")
			assert.equals(1, progression[1].value, "First value should be 1")
			assert.equals(2, progression[2].value, "Second value should be 2")
			assert.equals(3, progression[3].value, "Third value should be 3")
		end)

		it("should add unique value counts to results", function()
			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {baseAddress = 0x1000, alignment = 4})

			-- Capture same pattern multiple times at offset 0-3
			-- Value 0xFFFFFFFF = 4294967295 appears twice
			-- Value 0xAAAAAAAA = 2863311530 appears once
			mockMemory[0x1000] = bytes4(0xFF, 0xFF, 0xFF, 0xFF) .. int32(0)
			analyzer:capture()
			analyzer:capture()

			mockMemory[0x1000] = bytes4(0xAA, 0xAA, 0xAA, 0xAA) .. int32(0)
			analyzer:capture()

			local result = analyzer:getChangedOnce()
			analyzer:addUniqueCapturesValues(result)

			assert.is_not_nil(result.filtered)
			assert.equals(1, #result.filtered, "Should find exactly 1 changed range")

			local range = result.filtered[1]
			assert.equals(0, range.start, "Changed range should be at offset 0")
			assert.is_not_nil(range.uniqueValues)
			assert.equals(1, #range.uniqueValues, "Should have 1 offset with unique values")
			assert.equals(2, #range.uniqueValues[1].values, "Should have 2 unique values at this offset")
		end)
	end)

	describe("Complete Analysis Workflow", function()
		it("should support full workflow", function()
			analyzer = MemoryAnalyzer.new("test_tracker", 16, {
				baseAddress = 0x1000,
				alignment = 4
			})

			-- Simulate tracking variable changes: starts at 100, then 75, then 50
			-- Variable at offset 4-7 (as int)
			mockMemory[0x1000] = int32(0) .. int32(100) .. zeros(8)
			analyzer:capture()
			mockMemory[0x1000] = int32(0) .. int32(75) .. zeros(8)
			analyzer:capture()
			mockMemory[0x1000] = int32(0) .. int32(50) .. zeros(8)
			analyzer:capture()

			-- Find what changed
			local result = analyzer:getChangedOnce(nil, "value_changes")

			assert.is_not_nil(result)
			assert.is_not_nil(result.filtered)
			assert.equals(3, analyzer:getCaptureCount())

			-- Verify only the variable offset changed (4-7)
			assert.equals(1, #result.filtered, "Should find exactly 1 changed range")
			assert.equals(4, result.filtered[1].start, "Changed range should be at offset 4")
			assert.equals(7, result.filtered[1].endOffset, "Changed range should end at offset 7")

			-- Verify result was stored
			local storedResult = analyzer:getResult("value_changes")
			assert.equals(result, storedResult)

			-- Enrich with value progression
			analyzer:addChangedCapturesValues(result)

			-- Verify value progressions showing 100 -> 75 -> 50
			assert.is_not_nil(result.filtered[1].values)
			assert.equals(1, #result.filtered[1].values, "Should have 1 progression (for offset 4)")

			local progression = result.filtered[1].values[1]
			assert.equals(3, #progression, "Should have 3 values in progression")
			assert.equals(100, progression[1].value, "Initial value should be 100")
			assert.equals(75, progression[2].value, "Value after first change should be 75")
			assert.equals(50, progression[3].value, "Value after second change should be 50")
		end)
	end)

	describe("Capture Management Functions", function()
		it("should resolve pointer chains to find final address", function()
			-- Update pointer mock to handle the chain properly
			memhack.dll.memory.readPointer = function(addr)
				if addr == 0x1000 then return 0x2000 end
				if addr == 0x2010 then return 0x3000 end  -- 0x2000 + 0x10
				return 0
			end

			analyzer = MemoryAnalyzer.new("test_analyzer", 8, {
				baseAddress = 0x1000,
				pointerChain = {0x10, 0x20}  -- Follow pointer + offset twice
			})

			-- Mock pointer chain 0x1000 -> 0x2000+0x10=0x2010 -> 0x3000+0x20 = 0x3020
			-- Final address should be 0x3020
			mockMemory[0x3020] = string.char(0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xBB, 0xBB, 0xBB)

			analyzer:capture()

			local capture = analyzer:getCapture(1)
			assert.equals(0x3020, capture.address, "Should resolve pointer chain to final address")
		end)

		it("should remove a specific capture", function()
			local analyzer = MemoryAnalyzer.new("test", 4, {baseAddress = 0x1000})

			mockMemory[0x1000] = string.char(0x01, 0x02, 0x03, 0x04)
			analyzer:capture()
			mockMemory[0x1000] = string.char(0x05, 0x06, 0x07, 0x08)
			analyzer:capture()
			mockMemory[0x1000] = string.char(0x09, 0x0A, 0x0B, 0x0C)
			analyzer:capture()

			assert.equals(3, analyzer:getCaptureCount())

			analyzer:removeCapture(2)
			assert.equals(2, analyzer:getCaptureCount())

			local capture1 = analyzer:getCapture(1)
			local capture2 = analyzer:getCapture(2)

			assert.equals(0x01, string.byte(capture1.data, 1))
			assert.equals(0x09, string.byte(capture2.data, 1))
		end)

		it("should list all captures with metadata", function()
			local analyzer = MemoryAnalyzer.new("test", 4, {baseAddress = 0x1000})

			mockMemory[0x1000] = string.char(0x01, 0x02, 0x03, 0x04)
			analyzer:capture()
			mockMemory[0x1000] = string.char(0x05, 0x06, 0x07, 0x08)
			analyzer:capture()

			local captureList = analyzer:listCaptures()

			assert.equals(2, #captureList)
			assert.equals(1, captureList[1].index)
			assert.equals(2, captureList[2].index)
			assert.equals(0x1000, captureList[1].address)
			assert.equals(0x1000, captureList[2].address)
			assert.is_not_nil(captureList[1].timestamp)
			assert.is_not_nil(captureList[2].timestamp)
		end)
	end)


	describe("Result Filtering Function", function()
		it("should filter result by address range", function()
			local analyzer = MemoryAnalyzer.new("test", 16, {baseAddress = 0x1000, alignment = 1})

			-- Create changing pattern
			mockMemory[0x1000] = string.char(0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF,
			                                  0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF)
			analyzer:capture()
			mockMemory[0x1000] = string.char(0x01, 0x01, 0xFF, 0xFF, 0x02, 0x02, 0xFF, 0xFF,
			                                  0x03, 0x03, 0xFF, 0xFF, 0x04, 0x04, 0xFF, 0xFF)
			analyzer:capture()

			local result = analyzer:getChangedOnce()

			-- Filter to only addresses 0x1000-0x1007 using a filter function
			local filterFunc = function(range, captures)
				local baseAddr = 0x1000
				local rangeStartAddr = baseAddr + range.start
				local rangeEndAddr = baseAddr + range.endOffset
				return rangeEndAddr >= 0x1000 and rangeStartAddr <= 0x1007
			end
			local filtered = analyzer:filterResult(result, filterFunc)

			assert.is_not_nil(filtered)
			assert.is_table(filtered.filtered)

			-- All filtered ranges should be within the address range
			for _, range in ipairs(filtered.filtered) do
				local rangeStartAddr = 0x1000 + range.start
				local rangeEndAddr = 0x1000 + range.endOffset
				assert.is_true(rangeEndAddr >= 0x1000 and rangeStartAddr <= 0x1007)
			end
		end)

		it("should filter result by value range", function()
			local analyzer = MemoryAnalyzer.new("test", 8, {baseAddress = 0x1000, alignment = 1})

			mockMemory[0x1000] = string.char(0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80)
			analyzer:capture()
			mockMemory[0x1000] = string.char(0x11, 0x21, 0x31, 0x41, 0x51, 0x61, 0x71, 0x81)
			analyzer:capture()

			local result = analyzer:getChangedOnce()
			result = analyzer:addAllCapturesValues(result)

			-- Filter to only values >= 0x40 in last capture using a filter function
			local filterFunc = function(range, captures)
				if range.values and range.values.all then
					local lastValue = range.values.all[#range.values.all]
					return lastValue >= 0x40
				end
				return false
			end
			local filtered = analyzer:filterResult(result, filterFunc)

			assert.is_not_nil(filtered)
			assert.is_table(filtered.filtered)

			-- All filtered ranges should have values >= 0x40 in last capture
			for _, range in ipairs(filtered.filtered) do
				if range.values and range.values.all then
					local lastValue = range.values.all[#range.values.all]
					assert.is_true(lastValue >= 0x40)
				end
			end
		end)

		it("should filter result by stored result ID", function()
			local analyzer = MemoryAnalyzer.new("test", 8, {baseAddress = 0x1000, alignment = 1})

			mockMemory[0x1000] = string.char(0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80)
			analyzer:capture()
			mockMemory[0x1000] = string.char(0x11, 0x21, 0x31, 0x41, 0x51, 0x61, 0x71, 0x81)
			analyzer:capture()

			-- Store result with ID
			analyzer:getChangedOnce(nil, "stored_result")

			-- Filter by ID using a filter function
			local filterFunc = function(range, captures)
				local baseAddr = 0x1000
				local rangeStartAddr = baseAddr + range.start
				local rangeEndAddr = baseAddr + range.endOffset
				return rangeEndAddr >= 0x1000 and rangeStartAddr <= 0x1003
			end
			local filtered = analyzer:filterResult("stored_result", filterFunc, "filtered_result")

			assert.is_not_nil(filtered)
			assert.is_not_nil(analyzer:getResult("filtered_result"))
		end)
	end)
end)
