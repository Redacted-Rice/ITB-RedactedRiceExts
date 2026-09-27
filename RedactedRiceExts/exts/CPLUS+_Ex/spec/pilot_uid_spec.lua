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

	it("same id+saveVals yield the same uid across wrappers", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 13})
		local p2 = helper.createMockPilot({pilotId = "Pilot_Cyborg", address = 14})
		p1:getLvlUpSkill(1):setSaveVal(0)
		p1:getLvlUpSkill(2):setSaveVal(1)
		p2:getLvlUpSkill(1):setSaveVal(0)
		p2:getLvlUpSkill(2):setSaveVal(1)

		assert.equals("Pilot_Cyborg:0:1", pilot_uid:_ensurePilotUid(p1))
		assert.equals("Pilot_Cyborg:0:1", pilot_uid:_ensurePilotUid(p2))
		assert.equals(0, p2:getLvlUpSkill(1):getSaveVal())
		assert.equals(1, p2:getLvlUpSkill(2):getSaveVal())
	end)

	it("different pilot ids with the same saveVals keep distinct uids", function()
		local p1 = helper.createMockPilot({pilotId = "Pilot_A", address = 71})
		local p2 = helper.createMockPilot({pilotId = "Pilot_B", address = 72})
		p1:getLvlUpSkill(1):setSaveVal(0)
		p1:getLvlUpSkill(2):setSaveVal(1)
		p2:getLvlUpSkill(1):setSaveVal(0)
		p2:getLvlUpSkill(2):setSaveVal(1)

		assert.equals("Pilot_A:0:1", pilot_uid:_ensurePilotUid(p1))
		assert.equals("Pilot_B:0:1", pilot_uid:_ensurePilotUid(p2))
		assert.equals(0, p2:getLvlUpSkill(1):getSaveVal())
		assert.equals(1, p2:getLvlUpSkill(2):getSaveVal())
	end)

	it("recreated wrappers keep the same uid without rewriting saveVals", function()
		local first = helper.createMockPilot({pilotId = "Pilot_BeetleMech", address = 80})
		first:getLvlUpSkill(1):setSaveVal(11)
		first:getLvlUpSkill(2):setSaveVal(8)

		assert.equals("Pilot_BeetleMech:11:8", first:getUidStr())

		local second = helper.createMockPilot({pilotId = "Pilot_BeetleMech", address = 99})
		second:getLvlUpSkill(1):setSaveVal(11)
		second:getLvlUpSkill(2):setSaveVal(8)

		assert.equals("Pilot_BeetleMech:11:8", second:getUidStr())
		assert.equals(11, second:getLvlUpSkill(1):getSaveVal())
		assert.equals(8, second:getLvlUpSkill(2):getSaveVal())
	end)
end)
