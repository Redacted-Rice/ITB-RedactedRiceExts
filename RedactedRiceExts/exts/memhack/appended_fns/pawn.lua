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

	BoardPawn.GetHpCorePowerList = function(self)
		return self:GetMemhackObj():getHpCorePowerList()
	end

	BoardPawn.SetHpCorePowerList = function(self, values)
		return self:GetMemhackObj():setHpCorePowerList(values)
	end

	BoardPawn.GetMoveCorePowerList = function(self)
		return self:GetMemhackObj():getMoveCorePowerList()
	end

	BoardPawn.SetMoveCorePowerList = function(self, values)
		return self:GetMemhackObj():setMoveCorePowerList(values)
	end

	BoardPawn.IsHpPowered = function(self)
		return self:GetMemhackObj():isHpPowered()
	end

	BoardPawn.IsMovePowered = function(self)
		return self:GetMemhackObj():isMovePowered()
	end

	BoardPawn.GetRawMoveSpeed = function(self)
		Assert.Equals("userdata", type(self), "Argument #0")
		return self:GetMemhackObj():getMoveSpeed()
	end

	BoardPawn.SetRawMoveSpeed = function(self, moveSpeed)
		Assert.Equals("userdata", type(self), "Argument #0")
		Assert.Equals("number", type(moveSpeed), "Argument #1")
		self:GetMemhackObj():setMoveSpeed(moveSpeed)
	end

	-- Only a set fn and not a get because the get is defined by the game already
	-- This function seems to only work if the pawn doesn't have movement available. Not sure why but
	-- its good enough for my needs ATM so not investigating further
	BoardPawn.SetArmedWeaponId = function(self, value)
		self:GetMemhackObj():setArmedWeaponId(value)
	end

	-- Only a setter. Use vanilla GetType if you need the value. This mirrors that API
	BoardPawn.SetType = function(self, pawnType)
		Assert.Equals("userdata", type(self), "Argument #0")
		Assert.Equals("string", type(pawnType), "Argument #1")
		self:GetMemhackObj():setPawnType(pawnType)
	end
end

modApi.events.onPawnClassInitialized:subscribe(onPawnClassInitialized)
