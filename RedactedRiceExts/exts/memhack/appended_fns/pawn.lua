local function onPawnClassInitialized(BoardPawn, pawn)
	BoardPawn.GetMemhackObj = function(self)
		if not self.memhackObj or memhack.dll.memory.getUserdataAddr(self) ~= self.memhackObj._address then
			self.memhackObj = memhack.structs.BoardPawn.new(memhack.dll.memory.getUserdataAddr(self), true)
		end
		return self.memhackObj
	end

	BoardPawn.GetPilot = function(self)
		local pilot = self:GetMemhackObj():getPilot()
		return pilot
	end

	-- Returns memhack.CORE_TYPE_* values
	BoardPawn.GetHpCore = function(self)
		local hpCore = self:GetMemhackObj():getHpCore()
		return hpCore
	end

	-- value: memhack.CORE_TYPE_* values
	BoardPawn.SetHpCore = function(self, value)
		local hpCore = self:GetMemhackObj():setHpCore(value)
		return hpCore
	end

	-- Returns memhack.CORE_TYPE_* values
	BoardPawn.GetMoveCore = function(self)
		local moveCore = self:GetMemhackObj():getMoveCore()
		return moveCore
	end

	-- value: memhack.CORE_TYPE_* values
	BoardPawn.SetMoveCore = function(self, value)
		local moveCore = self:GetMemhackObj():setMoveCore(value)
		return moveCore
	end
end

modApi.events.onPawnClassInitialized:subscribe(onPawnClassInitialized)
