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

	BoardPawn.GetHpCore = function(self)
		local hpCore = self:GetMemhackObj():getHpCore()
		return hpCore
	end

	BoardPawn.SetHpCore = function(self, value)
		local hpCore = self:GetMemhackObj():setHpCore(value)
		return hpCore
	end

	BoardPawn.GetMoveCore = function(self)
		local moveCore = self:GetMemhackObj():getMoveCore()
		return moveCore
	end

	BoardPawn.SetMoveCore = function(self, value)
		local moveCore = self:GetMemhackObj():setMoveCore(value)
		return moveCore
	end

	BoardPawn.GetPilotPowerList = function(self)
		local pilot = self:GetPilot()
		if not pilot then
			return nil
		end
		return pilot:getPowerList()
	end

	BoardPawn.SetPilotPowerList = function(self, values)
		local pilot = self:GetPilot()
		if not pilot then
			return false
		end
		return pilot:setPowerList(values)
	end
end

modApi.events.onPawnClassInitialized:subscribe(onPawnClassInitialized)
