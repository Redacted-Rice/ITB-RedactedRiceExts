-- Time traveler persistent data specs

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("time_traveler", function()
	local time_traveler

	before_each(function()
		helper.resetState()
		time_traveler = plus_manager._subobjects.time_traveler
		time_traveler.lastSavedPersistentData = {}
	end)

	it("gets scan id from persistent entry pilotId or legacy storage key", function()
		assert.equals("Pilot_A", time_traveler:_getScanIdFromPersistentEntry("Pilot_A:4:6", {pilotId = "Pilot_A"}))
		assert.equals("Pilot_Legacy", time_traveler:_getScanIdFromPersistentEntry("Pilot_Legacy", {}))
	end)

	it("looks up persistent data by pilot UID", function()
		local mockPilot = helper.createMockPilot({pilotId = "Pilot_A", address = 5001})
		mockPilot:getLvlUpSkill(1):setSaveVal(2)
		mockPilot:getLvlUpSkill(2):setSaveVal(5)

		time_traveler.lastSavedPersistentData["Pilot_A:2:5"] = {skill1 = "Health", skill2 = "Move"}

		local data, key = time_traveler:_lookupPersistentData(mockPilot)
		assert.equals("Health", data.skill1)
		assert.equals("Pilot_A:2:5", key)
	end)

	it("falls back to legacy pilot type id keys on load", function()
		time_traveler.lastSavedPersistentData.Pilot_A = {
			skill1 = "Health",
			skill2 = "Move",
			virtualSkills = {{id = "Bonus", source = "test"}},
		}

		local mockPilot = helper.createMockPilot({pilotId = "Pilot_A", address = 5002})
		mockPilot:getLvlUpSkill(1):setSaveVal(2)
		mockPilot:getLvlUpSkill(2):setSaveVal(5)

		local data, key = time_traveler:_lookupPersistentData(mockPilot)
		assert.equals("Health", data.skill1)
		assert.equals("Pilot_A", key)

		local virtualSkills = time_traveler:refreshTimeTravlerDataAndGetVirtSkills(mockPilot)
		assert.equals(1, #virtualSkills)
		assert.equals("Bonus", virtualSkills[1].id)
	end)

	it("stores pilotId when refreshing persistent data", function()
		local mockPilot = helper.createMockPilot({pilotId = "Pilot_A", address = 6001})
		mockPilot:getLvlUpSkill(1):setSaveVal(2)
		mockPilot:getLvlUpSkill(2):setSaveVal(5)

		_G.Game = _G.Game or {}
		_G.Game.GetAvailablePilots = function() return {mockPilot} end

		assert.is_true(time_traveler:_refreshLastSavedPersistentData())
		assert.equals("Pilot_A", time_traveler.lastSavedPersistentData["Pilot_A:2:5"].pilotId)
	end)

	it("passes pilot struct to custom save and restore callbacks", function()
		local savedPilot = nil
		local restoredPilot = nil

		time_traveler:registerTimeTravelerData("test_mod", "counter",
			function(pilot)
				savedPilot = pilot
				return 3
			end,
			function(pilot, value)
				restoredPilot = pilot
			end)

		local mockPilot = helper.createMockPilot({pilotId = "Pilot_A", address = 6001})
		mockPilot:getLvlUpSkill(1):setSaveVal(2)
		mockPilot:getLvlUpSkill(2):setSaveVal(5)

		_G.Game = _G.Game or {}
		_G.Game.GetAvailablePilots = function() return {mockPilot} end

		assert.is_true(time_traveler:_refreshLastSavedPersistentData())
		assert.equals(mockPilot, savedPilot)
		assert.equals("Pilot_A", time_traveler.lastSavedPersistentData["Pilot_A:2:5"].pilotId)
		assert.equals(3, time_traveler.lastSavedPersistentData["Pilot_A:2:5"].customData.test_mod.counter)

		time_traveler:_restoreCustomData(mockPilot, time_traveler.lastSavedPersistentData["Pilot_A:2:5"])
		assert.equals(mockPilot, restoredPilot)
	end)
end)
