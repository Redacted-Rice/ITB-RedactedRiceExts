local M = {}

function M.createMockPawn(params)
	params = params or {}

	local pawn = {
		_type = params.mechType or "TestMech",
		_hpCore = params.hpCore,
		_moveCore = params.moveCore,
		_maxBaseHealth = params.maxBaseHealth or 3,
		_maxHealth = params.maxHealth or 3,
		_health = params.health or 3,
		_rawMoveSpeed = params.rawMoveSpeed or 3,
	}

	pawn.GetType = function(self)
		return self._type
	end
	pawn.GetHpCore = function(self)
		return self._hpCore
	end
	pawn.SetHpCore = function(self, value)
		self._hpCore = value
	end
	pawn.GetMoveCore = function(self)
		return self._moveCore
	end
	pawn.GetMaxBaseHealth = function(self)
		return self._maxBaseHealth
	end
	pawn.SetMaxBaseHealth = function(self, value)
		self._maxBaseHealth = value
	end
	pawn.GetMaxHealth = function(self)
		return self._maxHealth
	end
	pawn.SetMaxHealth = function(self, value)
		self._maxHealth = value
	end
	pawn.GetHealth = function(self)
		return self._health
	end
	pawn.SetHealth = function(self, value)
		self._health = value
	end
	pawn.GetRawMoveSpeed = function(self)
		return self._rawMoveSpeed
	end
	pawn.SetRawMoveSpeed = function(self, value)
		self._rawMoveSpeed = value
	end

	return pawn
end

return M
