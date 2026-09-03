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

return M