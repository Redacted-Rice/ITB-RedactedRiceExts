-- Memhack hooks system
-- Taken originally from ModApiExt hooks and then modified
-- to be more reusable and to support auto parent getting for
-- memhack structs

-- Lua 5.1 compatibility: unpack is global in 5.1, table.unpack in 5.2+
local unpack = unpack or table.unpack

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("Memhack", "Hooks", memhack.DEBUG.HOOKS and memhack.DEBUG.ENABLED)

local hooks = {
	-- args:
	--  Pilot
	--  changes - map of fields and value changes. e.g. {field = {old = oldVal, new = newVal}}
	"pilotChanged",
	-- args:
	--  Pilot - owning pilot struct of the skill. May be nil if PilotLvlUpSkill was
	--	 	directly accessed via address
	--  PilotLvlUpSkill
	--  changes - map of fields and value changes. e.g. {field = {old = oldVal, new = newVal}}
	"pilotLvlUpSkillChanged",
}

function hooks:init()
	hooks.addTo(self, memhack, SUBMODULE)
	self:initBroadcastHooks(self)
	return hooks
end

-- Reloads hooks by clearing and re-adding event dispatchers
function hooks.reload(hookTbl, debugId)
	-- clear out previously registered hooks, since we're reloading.
	hooks.clearHooks(hookTbl, debugId)

	-- add hooks to dispatch events of same name
	for eventId, event in pairs(hookTbl.events) do
		local addHook = "add"..eventId:match("on(.+)").."Hook"
		hookTbl[addHook](hookTbl, function(...)
			event:dispatch(...)
		end)
	end
end

function hooks:load()
	hooks.reload(self, SUBMODULE)
	return hooks
end

-- Reusable: Add hook registration functions to a table
-- hookNames: array of hook names (e.g., {"pilotChanged", "skillChanged"})
-- tbl: table to add hooks to (the hooks object itself)
-- debugId: debug SUBMODULE ID from logger.register() for logging
function hooks.addTo(hookTbl, owner, debugId)
	if hookTbl.events == nil then
		hookTbl.events = {}
	end

	local events = hookTbl.events

	for _, name in ipairs(hookTbl) do
		local Name = name:gsub("^.", string.upper) -- capitalize first letter
		local name = name:gsub("^.", string.lower) -- lower case first letter

		local hookId = name.."Hooks"
		local eventId = "on"..Name
		local addHook = "add"..Name.."Hook"

		events[eventId] = Event()

		hookTbl[hookId] = {}
		hookTbl[addHook] = function(self, fn)
			assert(type(fn) == "function")
			table.insert(self[hookId], fn)
		end
		-- Add the add hook function to the owner if provided
		if owner then
			owner[addHook] = function(self, fn)
				return hookTbl[addHook](hookTbl, fn)
			end
		end
		logger.logDebug(debugId, "Added functions for hook %s", name)
	end
end

-- Reusable: Clear all registered hooks
-- hookNames: array of hook names
-- tbl: table containing the hooks
-- debugId: debug SUBMODULE ID from logger.register() for logging
function hooks.clearHooks(hookTbl, debugId)
	for _, name in ipairs(hookTbl) do
		local hookId = name.."Hooks"
		hookTbl[hookId] = {}
		logger.logDebug(debugId, "Cleared hook %s", name)
	end
end

-- Reusable: Build a broadcast function that fires all registered hooks
-- hooksField: name of the hooks field (e.g., "pilotChangedHooks")
-- tbl: table containing the hooks
-- argsFunc: optional function that provides arguments when none are passed
-- parentsToPrepend: optional array of parent type names for memhack structs
-- debugId: debug SUBMODULE ID from logger.register() for logging
function hooks.buildBroadcastFunc(hooksField, tbl, argsFunc, parentsToPrepend, debugId)
	local errfunc = function(e)
		return debug.traceback(
			string.format("A '%s' callback has failed:\n%s", hooksField, tostring(e)),
			2
		)
	end

	logger.logDebug(debugId, "Build fire...Hooks Fn for hook %s", hooksField)
	return function(...)
		local args = {...}
		local argCount = select('#', ...)

		if argCount == 0 then
			-- We didn't receive arguments directly. Fall back to the argument function.
			args = argsFunc and {argsFunc()} or nil
			argCount = args and #args or 0
		end

		-- Prepend parent args if specified
		local argsPrepended = {}
		local prependCount = 0
		if parentsToPrepend and #parentsToPrepend > 0 and args and argCount > 0 then
			local obj = args[1]  -- First argument is the object
			for i, parentName in ipairs(parentsToPrepend) do
				argsPrepended[i] = memhack.structManager.getParentOfType(obj, parentName)
				prependCount = prependCount + 1
			end
		end

		-- Add original args after parents (use direct indexing to preserve nil)
		if args then
			for i = 1, argCount do
				argsPrepended[prependCount + i] = args[i]
			end
		end

		-- Update arg count to include prepended parents
		argCount = prependCount + argCount

		logger.logDebug(debugId, "Executing hooks for %s", hooksField)
		for j, hook in ipairs(tbl[hooksField] or {}) do
			-- invoke the hook in a xpcall for proper error reporting
			local ok, err = xpcall(
				function()
					if argCount > 0 then
						hook(unpack(argsPrepended, 1, argCount))
					else
						hook()
					end
				end,
				errfunc
			)

			if not ok then
				logger.logError(debugId, err)
			end
		end
	end
end

function hooks:initBroadcastHooks(tbl)
	tbl["firePilotChangedHooks"] = hooks.buildBroadcastFunc("pilotChangedHooks", tbl, nil, nil, SUBMODULE)
	tbl["firePilotLvlUpSkillChangedHooks"] = hooks.buildBroadcastFunc("pilotLvlUpSkillChangedHooks", tbl, nil, {"Pilot"}, SUBMODULE)
end

return hooks