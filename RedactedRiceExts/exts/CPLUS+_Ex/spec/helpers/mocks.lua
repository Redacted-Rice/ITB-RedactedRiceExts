package.path = package.path .. ";../memhack/spec/?.lua;../memhack/spec/?/init.lua"
local memhackMocks = dofile("../memhack/spec/helpers/mocks.lua")
local M = {}

M.createMockSkill = memhackMocks.createMockSkill
M.createMockLvlUpSkills = memhackMocks.createMockLvlUpSkills

-- Wrap memhack's createMockPilot to add getPawnId/isPiloting methods
-- and ensure address is always set (in case math.random is mocked and returns nil)
M.createMockPilot = function(params)
	-- Handle string argument (just pilot ID)
	if type(params) == "string" then
		params = {pilotId = params}
	end
	params = params or {}
	
	-- Ensure address is explicitly set to avoid nil from mocked math.random
	if not params.address then
		-- Generate a simple sequential address for testing
		M._nextAddress = (M._nextAddress or 1000000) + 1
		params.address = M._nextAddress
	end
	
	local mockPilot = memhackMocks.createMockPilot(params)
	
	-- Add getPawnId method (returns pawnId if piloting, nil otherwise)
	mockPilot.getPawnId = function(self)
		if not _G.Game or not _G.Board then return nil end
		
		local pilotAddr = self:getAddress()
		for pawnId = 0, 2 do
			local pawn = _G.Board.GetPawn and _G.Board.GetPawn(pawnId) or nil
			if pawn then
				local pawnPilot = pawn.GetPilot and pawn.GetPilot() or nil
				if pawnPilot and pawnPilot:getAddress() == pilotAddr then
					return pawnId
				end
			end
		end
		return nil
	end
	
	-- Add isPiloting method
	mockPilot.isPiloting = function(self)
		return self:getPawnId() ~= nil
	end
	
	return mockPilot
end

function M.createMockPilotWithTracking(pilotId)
	pilotId = pilotId or "TestPilot"

	local tracking = {
		skill1SaveVal = nil,
		skill2SaveVal = nil,
		skill1 = nil,
		skill2 = nil,
	}

	-- Create skills for tracking
	local mockSkill1 = memhackMocks.createMockSkill()
	local mockSkill2 = memhackMocks.createMockSkill()

	tracking.skill1 = mockSkill1
	tracking.skill2 = mockSkill2

	mockSkill1.getSaveVal = function(self) return self._save_val or tracking.skill1SaveVal or 0 end
	mockSkill2.getSaveVal = function(self) return self._save_val or tracking.skill2SaveVal or 1 end
	mockSkill1.setSaveVal = function(self, value)
		self._save_val = value
		tracking.skill1SaveVal = value
	end
	mockSkill2.setSaveVal = function(self, value)
		self._save_val = value
		tracking.skill2SaveVal = value
	end

	local mockLvlUpSkills = M.createMockLvlUpSkills(mockSkill1, mockSkill2)

	local mockPilot = M.createMockPilot({
		pilotId = pilotId,
		level = 0,
		lvlUpSkills = mockLvlUpSkills
	})

	-- Updated to match new simplified Pilot.setLvlUpSkill signature
	mockPilot.setLvlUpSkill = function(self, index, structOrNewVals)
		local skill = (index == 1) and mockSkill1 or mockSkill2

		-- structOrNewVals should be a table with skill properties
		if type(structOrNewVals) == "table" then
			skill._id = structOrNewVals.id
			skill._save_val = structOrNewVals.saveVal
			if structOrNewVals.coresBonus or structOrNewVals.gridBonus or structOrNewVals.healthBonus or structOrNewVals.moveBonus then
				skill._cores_bonus = structOrNewVals.coresBonus or 0
				skill._grid_bonus = structOrNewVals.gridBonus or 0
				skill._health_bonus = structOrNewVals.healthBonus or 0
				skill._move_bonus = structOrNewVals.moveBonus or 0
			end

			if index == 1 then
				tracking.skill1SaveVal = structOrNewVals.saveVal
			else
				tracking.skill2SaveVal = structOrNewVals.saveVal
			end
		else
			error("setLvlUpSkill expects a table parameter")
		end
	end

	return mockPilot, tracking
end

return M
