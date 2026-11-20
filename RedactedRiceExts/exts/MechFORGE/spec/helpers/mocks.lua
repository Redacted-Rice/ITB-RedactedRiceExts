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

local function isCorePowered(core)
	return core ~= nil and core ~= memhack.CORE_TYPE_NONE
end

local function makeCoreListMock(storageRef)
	local mock = {}
	function mock:getIntSize()
		return #storageRef
	end
	function mock:getIntList()
		return copyList(storageRef)
	end
	function mock:getIntAt(idx)
		return storageRef[idx]
	end
	function mock:intListMatches(tracked)
		return listMatchesTracked(storageRef, tracked)
	end
	function mock:setIntList(values)
		if type(values) ~= "table" or #values ~= #storageRef then
			return false
		end
		for i, v in ipairs(values) do
			storageRef[i] = v
		end
		return true
	end
	function mock:setIntListResizingIfNeeded(values)
		if type(values) ~= "table" then
			return false
		end
		for i = #storageRef, 1, -1 do
			storageRef[i] = nil
		end
		for i, v in ipairs(values) do
			storageRef[i] = v
		end
		return true
	end
	function mock:isCorePoweredAt(idx)
		return isCorePowered(storageRef[idx])
	end
	function mock:isPartiallyPowered()
		local foundPowered = false
		local foundUnpowered = false
		for i = 1, #storageRef do
			if isCorePowered(storageRef[i]) then
				foundPowered = true
			else
				foundUnpowered = true
			end
		end
		return foundPowered and foundUnpowered
	end
	function mock:isFullyPowered()
		if #storageRef < 1 then
			return true
		end
		for i = 1, #storageRef do
			if not isCorePowered(storageRef[i]) then
				return false
			end
		end
		return true
	end
	function mock:_uncheckedGetIntAt(idx)
		return storageRef[idx]
	end
	return mock
end

function M.createMockPawn(params)
	params = params or {}

	local pawn = {
		_type = params.mechType or "TestMech",
		_hpCores = copyList(params.hpCores or { memhack.CORE_TYPE_NONE }),
		_moveCores = copyList(params.moveCores or { memhack.CORE_TYPE_NONE }),
		_maxBaseHealth = params.maxBaseHealth or 3,
		_maxHealth = params.maxHealth or 3,
		_health = params.health or 3,
		_rawMoveSpeed = params.rawMoveSpeed or 3,
	}

	pawn.GetType = function(self)
		return self._type
	end

	pawn._hpCoreList = makeCoreListMock(pawn._hpCores)
	pawn._moveCoreList = makeCoreListMock(pawn._moveCores)

	pawn._memhackBoardPawn = {
		getHpCores = function()
			return pawn._hpCoreList
		end,
		getMoveCores = function()
			return pawn._moveCoreList
		end,
		assignMechCore = function()
			if params.assignMechCore then
				return params.assignMechCore(pawn)
			end
			return memhack.CORE_TYPE_NORMAL
		end,
		unassignMechCore = function(_, coreType)
			if params.unassignMechCore then
				return params.unassignMechCore(pawn, coreType)
			end
			return coreType or memhack.CORE_TYPE_NORMAL
		end,
	}

	pawn.GetMemhackObj = function(self)
		return self._memhackBoardPawn
	end

	pawn.GetHpCores = function(self)
		return self:GetMemhackObj():getHpCores():getIntList()
	end

	pawn.SetHpCores = function(self, values)
		return self:GetMemhackObj():getHpCores():setIntListResizingIfNeeded(values)
	end

	pawn.IsHpPowered = function(self)
		return self:GetMemhackObj():getHpCores():isFullyPowered()
	end

	pawn.GetMoveCores = function(self)
		return self:GetMemhackObj():getMoveCores():getIntList()
	end

	pawn.SetMoveCores = function(self, values)
		return self:GetMemhackObj():getMoveCores():setIntListResizingIfNeeded(values)
	end

	pawn.IsMovePowered = function(self)
		return self:GetMemhackObj():getMoveCores():isFullyPowered()
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