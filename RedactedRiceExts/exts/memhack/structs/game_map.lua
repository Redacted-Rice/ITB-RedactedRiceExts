-- FWIW I found two ways so far to get GameMap other than Game in lua

local MemhackGameMap = memhack.structManager.define("GameMap", {
	researchControl = { offset = 0x5674, type = "struct", subType = "ResearchControl", --[[structs don't define setters]] },
	-- This could be a memedit scan but instead did here as its more annoying
	-- to calibrate than most scans
	reputation = { offset = 0x848C, type = "int" },
	unknownObj1 = { offset = 0x90C8, type = "pointer", subType = "UnknownObj1" },
	victoryScreen = { offset = 0xD650, type = "pointer", subType = "VictoryScreen" },
})