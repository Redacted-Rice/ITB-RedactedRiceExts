-- Test for pilot bonus combiner functionality
-- Tests that cores and grid bonuses are properly combined when both skills are active

local helper = require("helpers/plus_manager_helper")

describe("Pilot Bonus Combiner", function()
	local pilot_bonus_combiner
	local mock_owner
	local mock_pilot
	local mock_skill1
	local mock_skill2

	before_each(function()
		-- Create mock skill registry with base bonuses
		local mock_skill_registry = {
			registeredSkills = {
				Grid = { bonuses = { grid = 3 } },
				Reactor = { bonuses = { cores = 1 } },
				Health = { bonuses = { health = 2 } },
				Move = { bonuses = { move = 1 } },
				Both = { bonuses = { grid = 3, cores = 1 } }
			}
		}

		-- Create mock owner
		mock_owner = {
			PLUS_DEBUG = false,
			_modules = {
				skill_registry = mock_skill_registry
			}
		}

		-- Create mock skills using helper
		mock_skill1 = helper.createMockSkill({skillId = "", gridBonus = 0, coresBonus = 0})
		mock_skill2 = helper.createMockSkill({skillId = "", gridBonus = 0, coresBonus = 0})

		-- Create mock pilot using helper with our skills
		local mockLvlUpSkills = helper.createMockLvlUpSkills(mock_skill1, mock_skill2)
		mock_pilot = helper.createMockPilot({pilotId = "TestPilot", level = 0, lvlUpSkills = mockLvlUpSkills})

		-- Load the module
		pilot_bonus_combiner = require("scripts/pilot_bonus_combiner")
		pilot_bonus_combiner.init(mock_owner)
	end)

	it("should combine grid bonuses when both skills have grid at level 2", function()
		-- Both skills have grid bonuses
		mock_skill1._grid_bonus = 3
		mock_skill1._id = "Grid"
		mock_skill2._grid_bonus = 3
		mock_skill2._id = "Grid"
		mock_pilot._level = 2

		pilot_bonus_combiner.combinePilotBonuses(mock_pilot)
		assert.are.equal(6, mock_skill1:getGridBonus())
		assert.are.equal(0, mock_skill2:getGridBonus())
	end)

	it("should combine cores bonuses when both skills have cores at level 2", function()
		-- Both skills have cores bonuses
		mock_skill1._cores_bonus = 1
		mock_skill1._id = "Reactor"
		mock_skill2._cores_bonus = 1
		mock_skill2._id = "Reactor"
		mock_pilot._level = 2

		pilot_bonus_combiner.combinePilotBonuses(mock_pilot)
		assert.are.equal(2, mock_skill1:getCoresBonus())
		assert.are.equal(0, mock_skill2:getCoresBonus())
	end)

	it("should NOT combine when only one skill has a bonus at level 2", function()
		-- Skill1 has grid 3 and Skill2 has cores 1. Should not combine
		mock_skill1._grid_bonus = 3
		mock_skill1._id = "Grid"
		mock_skill2._cores_bonus = 1
		mock_skill2._id = "Reactor"
		mock_pilot._level = 2

		pilot_bonus_combiner.combinePilotBonuses(mock_pilot)
		assert.are.equal(3, mock_skill1:getGridBonus())
		assert.are.equal(0, mock_skill1:getCoresBonus())
		assert.are.equal(0, mock_skill2:getGridBonus())
		assert.are.equal(1, mock_skill2:getCoresBonus())
	end)

	it("should combine cores but not grid when only cores overlap at level 2", function()
		-- Both have cores 1 but only skill2 has grid 3. Only cores should combine
		mock_skill1._cores_bonus = 1
		mock_skill1._id = "Reactor"
		mock_skill2._grid_bonus = 3
		mock_skill2._cores_bonus = 1
		mock_skill2._id = "Both"
		mock_pilot._level = 2

		pilot_bonus_combiner.combinePilotBonuses(mock_pilot)
		assert.are.equal(0, mock_skill1:getGridBonus())
		assert.are.equal(2, mock_skill1:getCoresBonus())
		assert.are.equal(3, mock_skill2:getGridBonus())
		assert.are.equal(0, mock_skill2:getCoresBonus())
	end)

	it("should restore base values at level 1 regardless of current state", function()
		-- Pilot downleveled to 1 with modified bonuses
		mock_skill1._grid_bonus = 6  -- Had been combined
		mock_skill1._cores_bonus = 0
		mock_skill1._id = "Grid"
		mock_skill2._grid_bonus = 0  -- Had been cleared
		mock_skill2._cores_bonus = 1
		mock_skill2._id = "Both"
		mock_pilot._level = 1

		pilot_bonus_combiner.combinePilotBonuses(mock_pilot)

		-- Skill1 (Grid) should restore to base: grid=3, cores=0
		assert.are.equal(3, mock_skill1:getGridBonus())
		assert.are.equal(0, mock_skill1:getCoresBonus())
		-- Skill2 (Both) should restore to base: grid=3, cores=1
		assert.are.equal(3, mock_skill2:getGridBonus())
		assert.are.equal(1, mock_skill2:getCoresBonus())
	end)

	it("should restore base values at level 1", function()
		-- Pilot at level 1 (or lower) should set to defaults
		mock_skill1._grid_bonus = 42  -- Arbitrary wrong value
		mock_skill1._cores_bonus = 42
		mock_skill1._id = "Grid"
		mock_skill2._grid_bonus = 42
		mock_skill2._cores_bonus = 42
		mock_skill2._id = "Reactor"
		mock_pilot._level = 1

		pilot_bonus_combiner.combinePilotBonuses(mock_pilot)
		assert.are.equal(3, mock_skill1:getGridBonus())
		assert.are.equal(0, mock_skill1:getCoresBonus())
		assert.are.equal(0, mock_skill2:getGridBonus())
		assert.are.equal(1, mock_skill2:getCoresBonus())
	end)

	it("should handle skills with no bonuses", function()
		-- Skills with no cores or grid bonuses
		mock_skill1._id = "Health"
		mock_skill2._id = "Move"
		mock_pilot._level = 2

		pilot_bonus_combiner.combinePilotBonuses(mock_pilot)
		assert.are.equal(0, mock_skill1:getGridBonus())
		assert.are.equal(0, mock_skill1:getCoresBonus())
		assert.are.equal(0, mock_skill2:getGridBonus())
		assert.are.equal(0, mock_skill2:getCoresBonus())
	end)
end)
