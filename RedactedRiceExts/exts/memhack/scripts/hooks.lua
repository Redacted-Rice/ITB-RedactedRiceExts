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
	self:addTo(memhack, SUBMODULE)
	self:initBroadcastHooks()
	return self
end

function hooks:load()
	self:reload(SUBMODULE)
	return self
end

function hooks:initBroadcastHooks()
	self["firePilotChangedHooks"] = self:buildBroadcastFunc("pilotChangedHooks", nil, nil, SUBMODULE)
	self["firePilotLvlUpSkillChangedHooks"] = self:buildBroadcastFunc("pilotLvlUpSkillChangedHooks", nil, {"Pilot"}, SUBMODULE)
end

-- Reloads hooks by clearing and re-adding event dispatchers
function hooks:reload(debugId)
	-- clear out previously registered hooks, since we're reloading.
	self:clearHooks(debugId)

	-- add hooks to dispatch events of same name
	for eventId, event in pairs(self.events) do
		local addHook = "add"..eventId:match("on(.+)").."Hook"
		self[addHook](self, function(...)
			event:dispatch(...)
		end)
	end
end

-- Reusable: Add hook registration functions to a table
-- self is the hooks object to add hooks to
-- owner: optional owner object to also add hooks to
-- debugId: debug SUBMODULE ID from logger.register() for logging
function hooks:addTo(owner, debugId)
	if self.events == nil then
		self.events = {}
	end

	local events = self.events

	for _, name in ipairs(self) do
		local Name = name:gsub("^.", string.upper) -- capitalize first letter
		local name = name:gsub("^.", string.lower) -- lower case first letter

		local hookId = name.."Hooks"
		local eventId = "on"..Name
		local addHook = "add"..Name.."Hook"

		events[eventId] = Event({ eventName = eventId })

		self[hookId] = {}
		self[addHook] = function(hookSelf, fn)
			assert(type(fn) == "function")
			table.insert(hookSelf[hookId], {
				fn = fn,
				creator = debug.traceback("", 3)
			})
		end
		-- Add the add hook function to the owner if provided
		if owner then
			owner[addHook] = function(ownerSelf, fn)
				local result = self[addHook](self, fn)
				return result
			end
			owner.events = events
		end
		logger.logDebug(debugId, "Added functions for hook %s", name)
	end
end

-- Reusable: Clear all registered hooks
-- self is the table containing the hooks
-- debugId: debug SUBMODULE ID from logger.register() for logging
function hooks:clearHooks(debugId)
	for _, name in ipairs(self) do
		local hookId = name.."Hooks"
		self[hookId] = {}
		logger.logDebug(debugId, "Cleared hook %s", name)
	end
end

function hooks:handleFailure(errorOrResult, creator, caller)
	errorOrResult = errorOrResult or "<unspecified error>"
	local message = Event.buildErrorMessage("An event callback failed: ", errorOrResult,
			nil, creator, caller)
	if Event.isStackOverflowError(errorOrResult) then
		error(message)
	else
		LOG(message)
	end
end

-- Reusable: Build a broadcast function that fires all registered hooks
-- hooksField: name of the hooks field (e.g., "pilotChangedHooks")
-- argsFunc: optional function that provides arguments when none are passed
-- parentsToPrepend: optional array of parent type names for memhack structs
-- debugId: debug SUBMODULE ID from logger.register() for logging
function hooks:buildBroadcastFunc(hooksField, argsFunc, parentsToPrepend, debugId)
	local tbl = self  -- Capture self for the closure
	local errfunc = function(e)
		-- Capture and return the stack trace of the xpcall
		-- 2 makes it start a frame higher so it doesn't include
		-- this error handling fn
		local trace = debug.traceback(tostring(e), 2)
		return trace
	end

	logger.logDebug(debugId, "Build fire...Hooks Fn for hook %s", hooksField)
	return function(...)
		local args = {...}
		local argCount = select('#', ...)
		local caller = debug.traceback("")

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
				argsPrepended[i] = memhack.structManager:getParentOfType(obj, parentName)
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
		for j, hookTbl in ipairs(tbl[hooksField] or {}) do
			-- invoke the hook in a xpcall for proper error reporting
			local ok, errorOrResult = xpcall(
				function()
					if argCount > 0 then
						hookTbl.fn(unpack(argsPrepended, 1, argCount))
					else
						hookTbl.fn()
					end
				end,
				errfunc
			)

			if not ok then
				tbl:handleFailure(errorOrResult, hookTbl.creator, caller)
			end
		end
	end
end

return hooks