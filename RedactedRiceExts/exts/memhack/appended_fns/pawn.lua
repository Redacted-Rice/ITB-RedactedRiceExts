function addPawnGetPilotFunc(BoardPawn, pawn)
	-- Upper case to align with BoardPawn conventions
	BoardPawn.GetPilot = function(self)
		-- Pawn contains a smart pointer at 0x980 which consists of a
		-- pointer to the data (0x980) and a pointer to the mem management
		-- (0x984). We only care about the data so use that one
		local pilotPtr = memhack.dll.memory.readPointer(memhack.dll.memory.getUserdataAddr(self) + 0x980)
		-- If no pilot, address will be set to 0
		if pilotPtr == nil or pilotPtr == 0 then
			return nil
		end
		return memhack.structs.Pilot.new(pilotPtr)
	end
end

modApi.events.onPawnClassInitialized:subscribe(addPawnGetPilotFunc)
