-- FWIW I found two ways so far to get GameMap other than Game in lua

local MemhackGameMap = memhack.structManager:define("GameMap", {
	researchControl = { offset = 0x5674, type = "struct", subType = "ResearchControl", --[[structs don't define setters]] },
	-- This could be a memedit scan but instead did here as its more annoying
	-- to calibrate than most scans
	strategySelectedPawn = { offset = 0x56C0, type = "int", noSetter = true},
	reputation = { offset = 0x848C, type = "int" },
	unknownObj1 = { offset = 0x90C8, type = "pointer", subType = "UnknownObj1", noSetter = true },
	gridPower = { offset = 0xC040, type = "int" },
	boardPlayer = { offset = 0xC204, type = "pointer", subType = "BoardPlayer", noSetter = true },
	victoryScreen = { offset = 0xD650, type = "pointer", subType = "VictoryScreen", noSetter = true },
})

-- Converts the memhack object back to the vanilla game object safely
function MemhackGameMap:toVanilla()
	if not Game then
		return nil
	end

	local addr = self:getAddress()
	if not addr or addr == 0 then
		return nil
	end

	if memhack.dll.memory.getUserdataAddr(Game) == addr then
		return Game
	end

	return nil
end