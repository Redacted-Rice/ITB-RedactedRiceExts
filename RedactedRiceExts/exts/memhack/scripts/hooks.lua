-- Mostly stolen and then reworked from ModApiExt

-- Lua 5.1 compatibility: unpack is global in 5.1, table.unpack in 5.2+
local unpack = unpack or table.unpack

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
	DEBUG = true,
}

function hooks:init()
	self:addTo(self)
	self:initBroadcastHooks(self)
	return hooks
end

function hooks:load()
	-- clear out previously registered hooks, since we're reloading.
	self:clearHooks()

	-- add hooks to dispatch events of same name
	for eventId, event in pairs(self.events) do
		local addHook = "add"..eventId:match("on(.+)").."Hook"
		self[addHook](self, function(...)
			event:dispatch(...)
		end)
	end
	return hooks
end

function hooks:addTo(tbl)
	if tbl.events == nil then
		tbl.events = {}
	end

	local events = tbl.events

	for _, name in ipairs(self) do
		local Name = name:gsub("^.", string.upper) -- capitalize first letter
		local name = name:gsub("^.", string.lower) -- lower case first letter

		local hookId = name.."Hooks"
		local eventId = "on"..Name
		local addHook = "add"..Name.."Hook"

		events[eventId] = Event()

		tbl[hookId] = {}
		tbl[addHook] = function(self, fn)
			assert(type(fn) == "function")
			table.insert(self[hookId], fn)
		end
		if self.DEBUG then LOG("Added functions for hook "..name) end
	end
end

function hooks:clearHooks()
	-- too lazy to update this function with new hooks every time
	for _, name in ipairs(self) do
		local hookId = name.."Hooks"
		self[hookId] = {}
		if self.DEBUG then LOG("Cleared hook "..name) end
	end
end

--[[
	Creates a broadcast function for the specified hooks field, allowing
	to trigger the hook callbacks on all registered modApiExt objects.

	hooksField: Name of the hooks field to broadcast to
	argsFunc: Optional function that provides arguments when none are passed
	memhackStructParentsToPrepend: Optional array of parent type names (e.g., {"Pilot"})
	   	that will be retrieved from the first argument and prepended to args. Nil
		parents are still passed for consistent argument format.
--]]
function hooks:buildBroadcastFunc(hooksField, argsFunc, memhackStructParentsToPrepend)
	--[[local errfunc = function(e)
		return string.format(
			"A '%s' callback has failed:\n%s",
			hooksField, e
		)
	end]]
	-- TODO: Test this
	local errfunc = function(e)
		return debug.traceback(
			string.format("A '%s' callback has failed:\n%s", hooksField, tostring(e)),
			2
		)
	end


	if self.DEBUG then LOG("Build fire...Hooks Fn for hook ".. hooksField) end
	return function(...)
		local args = {...}
		local argCount = select('#', ...)

		if argCount == 0 then
			-- We didn't receive arguments directly. Fall back to
			-- the argument function.
			-- Make sure that all hooks receive the same arguments.
			args = argsFunc and {argsFunc()} or nil
			argCount = args and #args or 0
		end

		-- Prepend parent args if specified
		-- Use direct indexing instead of table.insert to preserve nil values
		local argsPrepended = {}
		local prependCount = 0
		if memhackStructParentsToPrepend and #memhackStructParentsToPrepend > 0 and args and argCount > 0 then
			local obj = args[1]  -- First argument is the object
			for i, parentName in ipairs(memhackStructParentsToPrepend) do
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

		if self.DEBUG then LOG("Executing hooks for ".. hooksField) end
		for j, hook in ipairs(self[hooksField] or {}) do
			-- invoke the hook in a xpcall, since errors in SkillEffect
			-- scripts fail silently, making debugging a nightmare.
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
				LOG(err)
			end
		end
	end
end

function hooks:initBroadcastHooks(tbl)
	tbl["firePilotChangedHooks"] = self:buildBroadcastFunc("pilotChangedHooks")
	tbl["firePilotLvlUpSkillChangedHooks"] = self:buildBroadcastFunc("pilotLvlUpSkillChangedHooks", nil, {"Pilot"})
end

return hooks