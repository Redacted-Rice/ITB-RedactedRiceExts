-- BoardPawn API mocks and modapiext save-data stubs for integration specs

local M = {}

M.pawns = {}

function M.makeMockPawn(initialTypes, opts)
	opts = opts or {}
	local pawn = {
		_weapons = {},
		_removeLog = {},
		_addLog = {},
		_hpCore = opts.hpCore or 0,
		_moveCore = opts.moveCore or 0,
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

	function pawn:GetHpCore()
		return self._hpCore
	end

	function pawn:SetHpCore(value)
		self._hpCore = value
	end

	function pawn:GetMoveCore()
		return self._moveCore
	end

	function pawn:SetMoveCore(value)
		self._moveCore = value
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
	end

	function pawn:AddWeapon(typeId, _ignored)
		table.insert(self._addLog, typeId)
		table.insert(self._weapons, typeId)
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