-- Pilot UID specs

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("pilot_uid", function()
	local pilot_uid

	before_each(function()
		helper.resetState()
		pilot_uid = plus_manager._subobjects.pilot_uid
	end)

	after_each(function()
		helper.restoreMathRandom()
	end)

	it("builds pilot UIDs from id and saveVals", function()
		assert.equals("Pilot_A:3:5", pilot_uid:_makePilotUid("Pilot_A", 3, 5))
	end)

	it("reads UID from pilot saveVals without reminting", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_A", address = 21})
		p1:getLvlUpSkill(1):setSaveVal(4)
		p1:getLvlUpSkill(2):setSaveVal(6)

		assert.equals("Pilot_A:4:6", p1:getUidStr())
		assert.equals("Pilot_A:4:6", pilot_uid:_readUid(p1))
	end)

	it("same id+saveVals yield the same uid across wrappers without reminting", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 13})
		local p2 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 14})
		p1:getLvlUpSkill(1):setSaveVal(0)
		p1:getLvlUpSkill(2):setSaveVal(1)
		p2:getLvlUpSkill(1):setSaveVal(0)
		p2:getLvlUpSkill(2):setSaveVal(1)

		assert.equals("Pilot_Cyborg:0:1", p1:getUidStr())
		assert.equals("Pilot_Cyborg:0:1", p2:getUidStr())
		assert.equals(0, p2:getLvlUpSkill(1):getSaveVal())
		assert.equals(1, p2:getLvlUpSkill(2):getSaveVal())
	end)

	it("getAvailablePilotsWithUids remints duplicate UIDs", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 101})
		local p2 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 102})
		p1:getLvlUpSkill(1):setSaveVal(0)
		p1:getLvlUpSkill(2):setSaveVal(1)
		p2:getLvlUpSkill(1):setSaveVal(0)
		p2:getLvlUpSkill(2):setSaveVal(1)

		_G.Game.GetAvailablePilots = function() return {p1, p2} end

		helper.mockMathRandomInt({14, 14})
		local entries = pilot_uid:getAvailablePilotsWithUids()

		assert.equals(2, #entries)
		assert.equals("Pilot_Cyborg:0:1", entries[1].uid)
		-- math.random(14) mocked to 14 → sv = 13
		assert.equals("Pilot_Cyborg:13:13", entries[2].uid)
	end)

	it("ensureUniqueAmongAvailable remints when colliding with available pilots", function()
		local existing = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 201})
		existing:getLvlUpSkill(1):setSaveVal(0)
		existing:getLvlUpSkill(2):setSaveVal(1)
		_G.Game.GetAvailablePilots = function() return {existing} end

		local reward = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 202})
		reward:getLvlUpSkill(1):setSaveVal(0)
		reward:getLvlUpSkill(2):setSaveVal(1)

		helper.mockMathRandomInt({6, 8})
		local uid = pilot_uid:ensureUniqueAmongAvailable(reward)

		assert.equals("Pilot_Cyborg:5:7", uid)
		assert.equals(5, reward:getLvlUpSkill(1):getSaveVal())
		assert.equals(7, reward:getLvlUpSkill(2):getSaveVal())
	end)

	it("ensureUniqueAmongAvailable keeps UID when free", function()
		_G.Game.GetAvailablePilots = function() return {} end

		local reward = helper.createMockPilot({pilotId = "Pilot_Pod", address = 301})
		reward:getLvlUpSkill(1):setSaveVal(2)
		reward:getLvlUpSkill(2):setSaveVal(3)

		assert.equals("Pilot_Pod:2:3", pilot_uid:ensureUniqueAmongAvailable(reward))
	end)

	it("getAvailablePilotsWithUids does not expose claimed set", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_A", address = 401})
		p1:getLvlUpSkill(1):setSaveVal(1)
		p1:getLvlUpSkill(2):setSaveVal(2)
		_G.Game.GetAvailablePilots = function() return {p1} end

		local a, b = pilot_uid:getAvailablePilotsWithUids()
		assert.equals(1, #a)
		assert.is_nil(b)
	end)
end)
