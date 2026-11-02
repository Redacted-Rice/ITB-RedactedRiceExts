-- Need to try and find what this is still. May not be virtual in which case it will remain unknown
local MemhackUO2 = memhack.structManager:define("UnknownObj2", {
	selectedPawn = { offset = 0x148, type = "pointer", subType = "BoardPawn", hideGetter = true, hideSetter = true, },
})
