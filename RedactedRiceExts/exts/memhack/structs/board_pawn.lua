-- BoardPawn struct for accessing pawn memory offsets
-- This wraps the BoardPawn object to provide access to internal memory structures

local MemhackBoardPawn = memhack.structManager:define("BoardPawn", {
	-- Smart "double" pointer to pilot data at 0x980
	pilot = { offset = 0x980, type = "pointer", subType = "Pilot", noSetter = true },
})
