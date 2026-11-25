-- BoardPawn API mocks and modapiext save-data stubs for integration specs

local M = {}

M.pawns = {}

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

local function makeCoreListMock(storageRef)
	local mock = {}
	function mock:getIntList()
		local out = {}
		for i, v in ipairs(storageRef) do
			out[i] = v
		end
		return out
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
	return mock
end

function M.makeMockPawn(initialTypes, opts)
	opts = opts or {}
	local pawn = {
		_weapons = {},
		_removeLog = {},
		_addLog = {},
		_addForceLog = {},
		_hpCores = opts.hpCores or { 0 },
		_moveCores = opts.moveCores or { 0 },
		_weaponLimitedUses = opts.weaponLimitedUses or {},
		_weaponLimitedRemaining = opts.weaponLimitedRemaining or {},
	}

	for _, typeId in ipairs(initialTypes or {}) do
		table.insert(pawn._weapons, typeId)
	end

	local pilotPower = {}
	if opts.pilotPower then
		for i, v in ipairs(opts.pilotPower) do
			pilotPower[i] = v
		end
	end

	local pilot = {}
	function pilot:getPowerList()
		return pilotPower
	end

	function pilot:setPowerList(values)
		pilotPower = {}
		for i, v in ipairs(values) do
			pilotPower[i] = v
		end
		return true
	end

	function pawn:GetPilot()
		return pilot
	end

	function pawn:GetHpCores()
		local out = {}
		for i, v in ipairs(self._hpCores) do
			out[i] = v
		end
		return out
	end

	function pawn:SetHpCores(values)
		self._hpCores = {}
		for i, v in ipairs(values) do
			self._hpCores[i] = v
		end
	end

	function pawn:GetMoveCores()
		local out = {}
		for i, v in ipairs(self._moveCores) do
			out[i] = v
		end
		return out
	end

	function pawn:SetMoveCores(values)
		self._moveCores = {}
		for i, v in ipairs(values) do
			self._moveCores[i] = v
		end
	end

	pawn._memhackBoardPawn = {
		getHpCores = function()
			return makeCoreListMock(pawn._hpCores)
		end,
		getMoveCores = function()
			return makeCoreListMock(pawn._moveCores)
		end,
	}

	function pawn:GetMemhackObj()
		return self._memhackBoardPawn
	end

	function pawn:GetId()
		return opts.id or 0
	end

	function pawn:GetWeaponCount()
		return #self._weapons
	end

	function pawn:GetWeaponType(index)
		return self._weapons[index]
	end

	function pawn:RemoveWeapon(index)
		table.insert(self._removeLog, index)
		table.remove(self._weapons, index)
		table.remove(self._weaponLimitedUses, index)
		table.remove(self._weaponLimitedRemaining, index)
	end

	function pawn:GetWeaponLimitedUses(index)
		return self._weaponLimitedUses[index]
	end

	function pawn:GetWeaponLimitedRemaining(index)
		return self._weaponLimitedRemaining[index]
	end

	function pawn:SetWeaponLimitedRemaining(index, remaining)
		self._weaponLimitedRemaining[index] = remaining
	end

	function pawn:AddWeapon(typeId, forceEnable)
		table.insert(self._addLog, typeId)
		table.insert(self._addForceLog, forceEnable)
		table.insert(self._weapons, typeId)
		local uses = (opts.addWeaponLimitedUses or {})[typeId]
		if uses and uses > 0 then
			table.insert(self._weaponLimitedUses, uses)
			table.insert(self._weaponLimitedRemaining, uses)
		else
			table.insert(self._weaponLimitedUses, 0)
			table.insert(self._weaponLimitedRemaining, 0)
		end
	end

	return pawn
end

function M.makeSavePtable(opts)
	opts = opts or {}
	local ptable = {
		healthPower = { 1 },
		movePower = { 2 },
		pilot = { power = opts.pilotPower or { 3 } },
	}
	if opts.primary ~= false then
		ptable.primary = opts.primary or {
			id = opts.primaryId or "Weapon_Primary",
			power = { 1 },
			upgrade1 = { 0 },
			upgrade2 = { 0 },
		}
	end
	if opts.secondary ~= false then
		ptable.secondary = opts.secondary or {
			id = "Weapon_Secondary",
			power = { 2 },
			upgrade1 = { 0 },
			upgrade2 = { 0 },
		}
	end
	return ptable
end

function M.installModApiExt(config)
	_G.modapiext = _G.modapiext or {}
	_G.modapiext.pawn = _G.modapiext.pawn or {}
	_G.modapiext.board = _G.modapiext.board or {}

	_G.modapiext.pawn.getSavedataTable = function(a, b, c)
		local pawnId, sourceTable
		if c ~= nil then
			pawnId, sourceTable = b, c
		else
			pawnId, sourceTable = a, b
		end
		if config and config.byPawnId and config.byPawnId[pawnId] then
			return config.byPawnId[pawnId]
		end
		if config and config.bySource and config.bySource[sourceTable] then
			return config.bySource[sourceTable][pawnId]
		end
		return nil
	end

	_G.modapiext.pawn.getWeaponData = function(a, b, c)
		local ptable, field
		if c ~= nil then
			ptable, field = b, c
		else
			ptable, field = a, b
		end
		if not ptable then
			return nil
		end
		return ptable[field]
	end

	_G.modapiext.board.getCurrentRegion = function()
		return config and config.region or nil
	end
end

function M.installGameGetPawn()
	_G.Game = _G.Game or {}
	function _G.Game:GetPawn(pawnId)
		return M.pawns[pawnId]
	end
end

return M
