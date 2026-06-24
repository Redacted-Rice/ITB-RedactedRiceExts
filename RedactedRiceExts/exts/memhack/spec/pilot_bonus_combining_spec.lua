-- Tests for pilot bonus combining functionality
-- Verifies that cores and grid bonuses are properly combined based on pilot level

local specHelper = require("helpers/spec_helper")

-- Initialize the extension with mock DLL
local memhack = specHelper.initMemhack()
local Pilot = memhack.structs.Pilot
local stateTracker = memhack.stateTracker

describe("Pilot Bonus Combining", function()
	local mockPilot, mockSkill1, mockSkill2, mockLvlUpSkills

	before_each(function()
		-- Reset state tracker
		stateTracker._skillSetValues = {}

		-- Create mock skills with memory and set values
		mockSkill1 = {
			_address = 0x1000,
			_coresBonus = 0,
			_gridBonus = 0,

			getAddress = function(self) return self._address end,
			_getCoresBonus = function(self) return self._coresBonus end,
			_setCoresBonus = function(self, value) self._coresBonus = value end,
			_getGridBonus = function(self) return self._gridBonus end,
			_setGridBonus = function(self, value) self._gridBonus = value end,
		}

		mockSkill2 = {
			_address = 0x2000,
			_coresBonus = 0,
			_gridBonus = 0,

			getAddress = function(self) return self._address end,
			_getCoresBonus = function(self) return self._coresBonus end,
			_setCoresBonus = function(self, value) self._coresBonus = value end,
			_getGridBonus = function(self) return self._gridBonus end,
			_setGridBonus = function(self, value) self._gridBonus = value end,
		}

		mockLvlUpSkills = {
			getSkill1 = function(self) return mockSkill1 end,
			getSkill2 = function(self) return mockSkill2 end,
		}

		mockPilot = {
			_level = 0,

			getLevel = function(self) return self._level end,
			getLvlUpSkills = function(self) return mockLvlUpSkills end,
			getLvlUpSkill = function(self, index)
				if index == 1 then return mockSkill1
				elseif index == 2 then return mockSkill2
				else error("Invalid index") end
			end,
		}

		-- Use the ACTUAL _combineBonuses function from pilot.lua
		mockPilot._combineBonuses = Pilot._combineBonuses
	end)

	describe("Level 0 (no combining)", function()
		before_each(function()
			mockPilot._level = 0
		end)

		it("should not combine when both skills have cores bonuses", function()
			memhack.stateTracker:setSkillSetValue(mockSkill1, "coresBonus", 2)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "coresBonus", 3)

			mockPilot:_combineBonuses()

			assert.are.equal(2, mockSkill1._coresBonus)
			assert.are.equal(3, mockSkill2._coresBonus)
		end)

		it("should not combine when both skills have grid bonuses", function()
			memhack.stateTracker:setSkillSetValue(mockSkill1, "gridBonus", 1)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "gridBonus", 2)

			mockPilot:_combineBonuses()

			assert.are.equal(1, mockSkill1._gridBonus)
			assert.are.equal(2, mockSkill2._gridBonus)
		end)
	end)

	describe("Level 1 (no combining)", function()
		before_each(function()
			mockPilot._level = 1
		end)

		it("should not combine when both skills have cores bonuses", function()
			memhack.stateTracker:setSkillSetValue(mockSkill1, "coresBonus", 2)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "coresBonus", 3)

			mockPilot:_combineBonuses()

			assert.are.equal(2, mockSkill1._coresBonus)
			assert.are.equal(3, mockSkill2._coresBonus)
		end)

		it("should not combine when both skills have grid bonuses", function()
			memhack.stateTracker:setSkillSetValue(mockSkill1, "gridBonus", 1)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "gridBonus", 2)

			mockPilot:_combineBonuses()

			assert.are.equal(1, mockSkill1._gridBonus)
			assert.are.equal(2, mockSkill2._gridBonus)
		end)
	end)

	describe("Level 2 (combining enabled)", function()
		before_each(function()
			mockPilot._level = 2
		end)

		it("should combine cores when both skills have non-zero cores", function()
			memhack.stateTracker:setSkillSetValue(mockSkill1, "coresBonus", 2)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "coresBonus", 3)

			mockPilot:_combineBonuses()

			assert.are.equal(5, mockSkill1._coresBonus)
			assert.are.equal(0, mockSkill2._coresBonus)
		end)

		it("should combine grid when both skills have non-zero grid", function()
			memhack.stateTracker:setSkillSetValue(mockSkill1, "gridBonus", 1)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "gridBonus", 2)

			mockPilot:_combineBonuses()

			assert.are.equal(3, mockSkill1._gridBonus)
			assert.are.equal(0, mockSkill2._gridBonus)
		end)

		it("should not combine cores when skill1 has zero cores", function()
			memhack.stateTracker:setSkillSetValue(mockSkill1, "coresBonus", 0)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "coresBonus", 3)

			mockPilot:_combineBonuses()

			assert.are.equal(0, mockSkill1._coresBonus)
			assert.are.equal(3, mockSkill2._coresBonus)
		end)

		it("should not combine grid when skill1 has zero grid", function()
			memhack.stateTracker:setSkillSetValue(mockSkill1, "gridBonus", 0)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "gridBonus", 2)

			mockPilot:_combineBonuses()

			assert.are.equal(0, mockSkill1._gridBonus)
			assert.are.equal(2, mockSkill2._gridBonus)
		end)

	it("should handle combining cores and grid independently", function()
		-- Both have cores (should combine)
		memhack.stateTracker:setSkillSetValue(mockSkill1, "coresBonus", 2)
		memhack.stateTracker:setSkillSetValue(mockSkill2, "coresBonus", 3)

		-- Only skill2 has grid (should not combine - set to individual values)
		memhack.stateTracker:setSkillSetValue(mockSkill1, "gridBonus", 0)
		memhack.stateTracker:setSkillSetValue(mockSkill2, "gridBonus", 1)

		mockPilot:_combineBonuses()

		-- Cores combined into skill1
		assert.are.equal(5, mockSkill1._coresBonus)
		assert.are.equal(0, mockSkill2._coresBonus)

		-- Grid not combined - each skill keeps its set value
		assert.are.equal(0, mockSkill1._gridBonus)
		assert.are.equal(1, mockSkill2._gridBonus)
	end)

	it("should preserve set values when memory changes", function()
		memhack.stateTracker:setSkillSetValue(mockSkill1, "coresBonus", 2)
		memhack.stateTracker:setSkillSetValue(mockSkill2, "coresBonus", 3)

		memhack.stateTracker:setSkillSetValue(mockSkill1, "gridBonus", 1)
		memhack.stateTracker:setSkillSetValue(mockSkill2, "gridBonus", 2)

		mockPilot:_combineBonuses()

		-- Memory shows combined values (both skills have bonuses, so they combine)
		assert.are.equal(5, mockSkill1._coresBonus)
		assert.are.equal(0, mockSkill2._coresBonus)  -- Zeroed when combined
		assert.are.equal(3, mockSkill1._gridBonus)
		assert.are.equal(0, mockSkill2._gridBonus)  -- Zeroed when combined

		-- Set values remain unchanged (stateTracker preserves what was set)
		assert.are.equal(2, memhack.stateTracker:getSkillSetValue(mockSkill1, "coresBonus"))
		assert.are.equal(3, memhack.stateTracker:getSkillSetValue(mockSkill2, "coresBonus"))
		assert.are.equal(1, memhack.stateTracker:getSkillSetValue(mockSkill1, "gridBonus"))
		assert.are.equal(2, memhack.stateTracker:getSkillSetValue(mockSkill2, "gridBonus"))
	end)
	end)

	describe("Level transitions", function()
		it("should uncombine when leveling down from 2 to 1", function()
			mockPilot._level = 2
			memhack.stateTracker:setSkillSetValue(mockSkill1, "coresBonus", 2)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "coresBonus", 3)

			memhack.stateTracker:setSkillSetValue(mockSkill1, "gridBonus", 1)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "gridBonus", 2)

			mockPilot:_combineBonuses()
			assert.are.equal(5, mockSkill1._coresBonus)
			assert.are.equal(0, mockSkill2._coresBonus)
			assert.are.equal(3, mockSkill1._gridBonus)
			assert.are.equal(0, mockSkill2._gridBonus)

			-- Level down
			mockPilot._level = 1
			mockPilot:_combineBonuses()

			-- Should restore to set values
			assert.are.equal(2, mockSkill1._coresBonus)
			assert.are.equal(3, mockSkill2._coresBonus)
			assert.are.equal(1, mockSkill1._gridBonus)
			assert.are.equal(2, mockSkill2._gridBonus)
		end)

		it("should combine when leveling up from 1 to 2", function()
			mockPilot._level = 1
			memhack.stateTracker:setSkillSetValue(mockSkill1, "coresBonus", 2)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "coresBonus", 3)

			memhack.stateTracker:setSkillSetValue(mockSkill1, "gridBonus", 1)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "gridBonus", 2)

			mockPilot:_combineBonuses()
			assert.are.equal(2, mockSkill1._coresBonus)
			assert.are.equal(3, mockSkill2._coresBonus)
			assert.are.equal(1, mockSkill1._gridBonus)
			assert.are.equal(2, mockSkill2._gridBonus)

			-- Level up
			mockPilot._level = 2
			mockPilot:_combineBonuses()

			-- Should combine
			assert.are.equal(5, mockSkill1._coresBonus)
			assert.are.equal(0, mockSkill2._coresBonus)
			assert.are.equal(3, mockSkill1._gridBonus)
			assert.are.equal(0, mockSkill2._gridBonus)
		end)
	end)

	describe("Pawn health sync", function()
		local mockPawn

		before_each(function()
			mockPawn = {
				_maxHealth = 10,
				_health = 10,
				_dead = false,
				GetMaxHealth = function(self) return self._maxHealth end,
				GetHealth = function(self) return self._health end,
				SetMaxHealth = function(self, value) self._maxHealth = value end,
				SetHealth = function(self, value) self._health = value end,
				IsDead = function(self) return self._dead end,
			}

			for _, skill in ipairs({mockSkill1, mockSkill2}) do
				skill._healthBonus = 0
				skill._moveBonus = 0
				skill._setHealthBonus = function(self, value) self._healthBonus = value end
				skill._getHealthBonus = function(self) return self._healthBonus end
				skill._setMoveBonus = function(self, value) self._moveBonus = value end
				skill._getMoveBonus = function(self) return self._moveBonus end
			end

			mockPilot._address = 0x5000
			mockPilot.getAddress = function(self) return self._address end
			mockPilot.getIdStr = function(self) return "TestPilot" end
			mockPilot.getPawnId = function(self) return 0 end
			mockPilot.isPiloting = function(self) return true end
			mockPilot._combineBonuses = Pilot._combineBonuses
			mockPilot._getExpectedHealthBonus = Pilot._getExpectedHealthBonus
			mockPilot._syncPawnHealthBonus = Pilot._syncPawnHealthBonus

			_G.Game = {
				GetPawn = function(pawnId)
					if pawnId == 0 then return mockPawn end
					return nil
				end,
			}

			stateTracker._pawnHealthBonusSynced = {}
		end)

		after_each(function()
			_G.Game = nil
		end)

		it("should add pawn HP when skill health bonus increases after combine", function()
			mockPilot._level = 1
			memhack.stateTracker:setSkillSetValue(mockSkill1, "healthBonus", 2)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "healthBonus", 0)

			mockPilot:_combineBonuses()

			assert.are.equal(12, mockPawn._maxHealth)
			assert.are.equal(12, mockPawn._health)
		end)

		it("should remove pawn HP when skill health bonus decreases after combine", function()
			mockPilot._level = 1
			memhack.stateTracker:setPawnHealthBonusSynced(mockPilot._address, 2)
			memhack.stateTracker:setSkillSetValue(mockSkill1, "healthBonus", 0)
			memhack.stateTracker:setSkillSetValue(mockSkill2, "healthBonus", 0)

			mockPilot:_combineBonuses()

			assert.are.equal(10, mockPawn._maxHealth)
			assert.are.equal(10, mockPawn._health)
		end)
	end)
end)
