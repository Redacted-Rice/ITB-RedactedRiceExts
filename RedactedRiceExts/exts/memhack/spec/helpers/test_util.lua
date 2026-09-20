-- Generic save/restore helpers for busted specs

local M = {}

local savedGlobals = {}
local savedFns = {}

function M.saveGlobal(name)
	savedGlobals[name] = _G[name]
end

function M.restoreGlobals()
	for name, value in pairs(savedGlobals) do
		_G[name] = value
	end
	savedGlobals = {}
end

function M.saveFn(tbl, key)
	table.insert(savedFns, { tbl = tbl, key = key, fn = tbl[key] })
end

function M.restoreFns()
	for i = #savedFns, 1, -1 do
		local entry = savedFns[i]
		entry.tbl[entry.key] = entry.fn
	end
	savedFns = {}
end

-- Mock PilotLvlUpSkill with hidden getters used by state_tracker getSkillSetValue
function M.makeMockLvlUpSkill(address, opts)
	opts = opts or {}
	return {
		_address = address,
		_healthBonus = opts.healthBonus or 0,
		_moveBonus = opts.moveBonus or 0,
		_coresBonus = opts.coresBonus or 0,
		_gridBonus = opts.gridBonus or 0,

		getAddress = function(self)
			return self._address
		end,
		_getHealthBonus = function(self)
			return self._healthBonus
		end,
		_setHealthBonus = function(self, value)
			self._healthBonus = value
		end,
		_getMoveBonus = function(self)
			return self._moveBonus
		end,
		_setMoveBonus = function(self, value)
			self._moveBonus = value
		end,
		_getCoresBonus = function(self)
			return self._coresBonus
		end,
		_setCoresBonus = function(self, value)
			self._coresBonus = value
		end,
		_getGridBonus = function(self)
			return self._gridBonus
		end,
		_setGridBonus = function(self, value)
			self._gridBonus = value
		end,
	}
end

return M