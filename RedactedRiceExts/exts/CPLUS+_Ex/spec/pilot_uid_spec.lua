-- Pilot UID specs

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("pilot_uid", function()
	local pilot_uid

	before_each(function()
		helper.resetState()
		pilot_uid = plus_manager._subobjects.pilot_uid
	end)

	it("builds pilot UIDs from id and saveVals", function()
		assert.equals("Pilot_A:3:5", pilot_uid:_makePilotUid("Pilot_A", 3, 5))
	end)

	it("reads UID from pilot saveVals", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_A", address = 21})
		p1:getLvlUpSkill(1):setSaveVal(4)
		p1:getLvlUpSkill(2):setSaveVal(6)

		assert.equals("Pilot_A:4:6", p1:getUidStr())
		assert.equals("Pilot_A:4:6", pilot_uid:_ensurePilotUid(p1))
		assert.equals("Pilot_A:4:6", p1:getUidStr())
	end)

	it("getUidStr uses saveVals as is", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_A", address = 22})
		p1:getLvlUpSkill(1):setSaveVal(3)
		p1:getLvlUpSkill(2):setSaveVal(3)

		assert.equals("Pilot_A:3:3", p1:getUidStr())
	end)

	it("mints a random unused saveVal pair", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 13})
		local p2 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 14})
		p1:getLvlUpSkill(1):setSaveVal(0)
		p1:getLvlUpSkill(2):setSaveVal(1)
		p2:getLvlUpSkill(1):setSaveVal(0)
		p2:getLvlUpSkill(2):setSaveVal(1)

		pilot_uid:_ensurePilotUid(p1)

		-- 195 unused keys after 0+1*14=14 is taken. Pick the last key -> 13:13.
		helper.mockMathRandomInt({195})
		local uid = pilot_uid:_ensurePilotUid(p2)

		assert.equals("Pilot_Cyborg:13:13", uid)
	end)

	it("mints unique UIDs for duplicate pilot ids during a run", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 11})
		local p2 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 12})
		p1:getLvlUpSkill(1):setSaveVal(0)
		p1:getLvlUpSkill(2):setSaveVal(1)
		p2:getLvlUpSkill(1):setSaveVal(0)
		p2:getLvlUpSkill(2):setSaveVal(1)

		local k1 = pilot_uid:_ensurePilotUid(p1)
		local k2 = pilot_uid:_ensurePilotUid(p2)
		assert.is_not_nil(k1)
		assert.is_not_nil(k2)
		assert.is_not.equals(k1, k2)
	end)

	it("encodes saveVal pairs as global keys", function()
		assert.equals(88, pilot_uid:_saveValPairToKey(4, 6))
		local sv1, sv2 = pilot_uid:_keyToSaveValPair(88)
		assert.equals(4, sv1)
		assert.equals(6, sv2)
	end)

	it("resetTracking clears used saveVal keys", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_A", address = 61})
		p1:getLvlUpSkill(1):setSaveVal(4)
		p1:getLvlUpSkill(2):setSaveVal(6)

		pilot_uid:_ensurePilotUid(p1)
		assert.equals(1, pilot_uid._usedSaveValKeyCount)
		assert.equals(p1, pilot_uid._usedSaveValKeys[88])

		pilot_uid:resetTracking()
		assert.equals(0, pilot_uid._usedSaveValKeyCount)
		assert.is_nil(pilot_uid._usedSaveValKeys[88])
	end)
end)
