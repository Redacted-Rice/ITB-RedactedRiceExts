local function onPawnClassInitialized(BoardPawn, pawn)
	BoardPawn.GetMemhackObj = function(self)
		if not self.memhackObj or memhack.dll.memory.getUserdataAddr(self) ~= self.memhackObj._address then
			self.memhackObj = memhack.structs.BoardPawn.new(memhack.dll.memory.getUserdataAddr(self), true)
		end
		return self.memhackObj
	end

	-- Upper case to align with BoardPawn conventions
	BoardPawn.GetPilot = function(self)
		local pilot = self:GetMemhackObj():getPilot()
		return pilot
	end
end

modApi.events.onPawnClassInitialized:subscribe(onPawnClassInitialized)
