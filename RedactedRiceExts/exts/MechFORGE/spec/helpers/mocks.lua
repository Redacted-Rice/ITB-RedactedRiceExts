local M = {}

local function copyList(list)
	local out = {}
	for i, v in ipairs(list or {}) do
		out[i] = v
	end
	return out
end

local function listMatchesTracked(stored, tracked)
	if type(tracked) ~= "table" then
		return #stored == 0
	end
	if #tracked ~= #stored then
		return false
	end
	for i = 1, #stored do
		if tracked[i] ~= stored[i] then
			return false
		end
	end
	return true
end

function M.createMockPawn(params)
	params = params or {}

	local pawn = {
		_type = params.mechType or "TestMech",
		_hpCores = params.hpCores or { memhack.CORE_TYPE_NONE },
		_moveCores = params.moveCores or { memhack.CORE_TYPE_NONE },
		_maxBaseHealth = params.maxBaseHealth or 3,
		_maxHealth = params.maxHealth or 3,
		_health = params.health or 3,
		_rawMoveSpeed = params.rawMoveSpeed or 3,
	}

	pawn.GetType = function(self)
		return self._type
	end

	pawn._memhackBoardPawn = {
		getHpCores = function()
			return copyList(pawn._hpCores)
		end,
		getMoveCores = function()
			return copyList(pawn._moveCores)
		end,
		hpCoresMatch = function(_, tracked)
			return listMatchesTracked(pawn._hpCores, tracked)
		end,
		moveCoresMatch = function(_, tracked)
			return listMatchesTracked(pawn._moveCores, tracked)
		end,
		setHpCores = function(_, values)
			pawn._hpCores = copyList(values)
			return true
		end,
		setMoveCores = function(_, values)
			pawn._moveCores = copyList(values)
			return true
		end,
		isHpPowered = function()
			return pawn:IsHpPowered()
		end,
		isMovePowered = function()
			return pawn:IsMovePowered()
		end,
	}

	pawn.GetMemhackObj = function(self)
		return self._memhackBoardPawn
	end

	pawn.GetHpCores = function(self)
		return self:GetMemhackObj():getHpCores()
	end

	pawn.SetHpCores = function(self, values)
		return self:GetMemhackObj():setHpCores(values)
	end

	pawn.IsHpPowered = function(self)
		if #self._hpCores < 1 then
			return false
		end
		for i = 1, #self._hpCores do
			if self._hpCores[i] == nil or self._hpCores[i] == memhack.CORE_TYPE_NONE then
				return false
			end
		end
		return true
	end

	pawn.GetMoveCores = function(self)
		return self:GetMemhackObj():getMoveCores()
	end

	pawn.SetMoveCores = function(self, values)
		return self:GetMemhackObj():setMoveCores(values)
	end

	pawn.IsMovePowered = function(self)
		if #self._moveCores < 1 then
			return false
		end
		for i = 1, #self._moveCores do
			if self._moveCores[i] == nil or self._moveCores[i] == memhack.CORE_TYPE_NONE then
				return false
			end
		end
		return true
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