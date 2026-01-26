-- Tests for skill set value tracking functionality
-- Verifies that set values are properly tracked separately from memory values

local specHelper = require("helpers/spec_helper")

-- Initialize the extension with mock DLL
local memhack = specHelper.initMemhack()
local stateTracker = memhack.stateTracker

describe("Skill Set Value Tracking", function()
	local mockSkill

	before_each(function()
		-- Reset the tracker
		stateTracker._skillSetValues = {}

		-- Create a mock skill with address and hidden getters
		mockSkill = {
			_address = 0x12345,
			_coresBonus = 2,
			_gridBonus = 3,

			getAddress = function(self) return self._address end,
			_getCoresBonus = function(self) return self._coresBonus end,
			_setCoresBonus = function(self, value) self._coresBonus = value end,
			_getGridBonus = function(self) return self._gridBonus end,
			_setGridBonus = function(self, value) self._gridBonus = value end,
		}
	end)

	describe("getSkillSetValue", function()
		it("should initialize from memory on first access", function()
			local value = stateTracker.getSkillSetValue(mockSkill, "coresBonus")

			assert.are.equal(2, value)
			-- Verify it was tracked
			assert.are.equal(2, stateTracker._skillSetValues[mockSkill:getAddress()].coresBonus)
		end)

		it("should return tracked value instead of memory value after being set", function()
			-- Set a tracked value
			stateTracker.setSkillSetValue(mockSkill, "coresBonus", 5)

			-- Change memory value
			mockSkill._coresBonus = 10

			-- Should return tracked value, not memory
			local value = stateTracker.getSkillSetValue(mockSkill, "coresBonus")
			assert.are.equal(5, value)
		end)

		it("should track different fields independently", function()
			stateTracker.setSkillSetValue(mockSkill, "coresBonus", 5)
			stateTracker.setSkillSetValue(mockSkill, "gridBonus", 7)

			assert.are.equal(5, stateTracker.getSkillSetValue(mockSkill, "coresBonus"))
			assert.are.equal(7, stateTracker.getSkillSetValue(mockSkill, "gridBonus"))
		end)
	end)

	describe("setSkillSetValue", function()
		it("should create tracker entry for new skill", function()
			assert.is_nil(stateTracker._skillSetValues[mockSkill:getAddress()])

			stateTracker.setSkillSetValue(mockSkill, "coresBonus", 5)

			assert.is_not_nil(stateTracker._skillSetValues[mockSkill:getAddress()])
			assert.are.equal(5, stateTracker._skillSetValues[mockSkill:getAddress()].coresBonus)
		end)

		it("should update existing tracker entry", function()
			stateTracker.setSkillSetValue(mockSkill, "coresBonus", 5)
			assert.are.equal(5, stateTracker._skillSetValues[mockSkill:getAddress()].coresBonus)

			stateTracker.setSkillSetValue(mockSkill, "coresBonus", 8)
			assert.are.equal(8, stateTracker._skillSetValues[mockSkill:getAddress()].coresBonus)
		end)

		it("should allow setting zero values", function()
			stateTracker.setSkillSetValue(mockSkill, "coresBonus", 0)
			assert.are.equal(0, stateTracker.getSkillSetValue(mockSkill, "coresBonus"))
		end)
	end)

	describe("getSkillSetValues", function()
		it("should return both cores and grid values", function()
			stateTracker.setSkillSetValue(mockSkill, "coresBonus", 5)
			stateTracker.setSkillSetValue(mockSkill, "gridBonus", 7)

			local values = stateTracker.getSkillSetValues(mockSkill)

			assert.are.equal(5, values.coresBonus)
			assert.are.equal(7, values.gridBonus)
		end)

		it("should initialize from memory if not tracked", function()
			mockSkill._coresBonus = 3
			mockSkill._gridBonus = 4

			local values = stateTracker.getSkillSetValues(mockSkill)

			assert.are.equal(3, values.coresBonus)
			assert.are.equal(4, values.gridBonus)
		end)
	end)

	describe("cleanupStaleSkillSetValues", function()
		it("should remove tracker for skills not in active set", function()
			local skill1Addr = 0x1000
			local skill2Addr = 0x2000
			local skill3Addr = 0x3000

			stateTracker._skillSetValues[skill1Addr] = {coresBonus = 1}
			stateTracker._skillSetValues[skill2Addr] = {coresBonus = 2}
			stateTracker._skillSetValues[skill3Addr] = {coresBonus = 3}

			local activeSkills = {
				[skill1Addr] = true,
				[skill3Addr] = true
			}

			stateTracker.cleanupStaleSkillSetValues(activeSkills)

			assert.is_not_nil(stateTracker._skillSetValues[skill1Addr])
			assert.is_nil(stateTracker._skillSetValues[skill2Addr])
			assert.is_not_nil(stateTracker._skillSetValues[skill3Addr])
		end)

		it("should clear all trackers when given empty active set", function()
			stateTracker._skillSetValues[0x1000] = {coresBonus = 1}
			stateTracker._skillSetValues[0x2000] = {coresBonus = 2}

			stateTracker.cleanupStaleSkillSetValues({})

			assert.is_nil(next(stateTracker._skillSetValues))
		end)
	end)

	describe("Multiple skills", function()
		it("should track values independently for different skills", function()
			local skill2 = {
				_address = 0x99999,
				_coresBonus = 10,
				_gridBonus = 20,

				getAddress = function(self) return self._address end,
				_getCoresBonus = function(self) return self._coresBonus end,
				_getGridBonus = function(self) return self._gridBonus end,
			}

			stateTracker.setSkillSetValue(mockSkill, "coresBonus", 5)
			stateTracker.setSkillSetValue(skill2, "coresBonus", 15)

			assert.are.equal(5, stateTracker.getSkillSetValue(mockSkill, "coresBonus"))
			assert.are.equal(15, stateTracker.getSkillSetValue(skill2, "coresBonus"))
		end)
	end)
end)
