local MemhackBoardPlayer = memhack.structManager:define("BoardPlayer", {
	selectedPawn = { offset = 0x148, type = "pointer", subType = "BoardPawn", hideGetter = true, hideSetter = true, },
})
