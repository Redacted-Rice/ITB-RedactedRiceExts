-- Mostly stolen from ModApiExt

local hooks = {
	"pilotLevelChanged",
}

function hooks:init()
	self:addTo(self)
	self:initBroadcastHooks(self)
end

function hooks:load()
	-- clear out previously registered hooks, since we're reloading.
	self:clearHooks()
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

		-- functions to fire the hooks are built in internal.lua
	end
end

function hooks:clearHooks()
	-- too lazy to update this function with new hooks every time
	for k, v in pairs(self) do
		if type(v) == "table" and modApi:stringEndsWith(k, "Hooks") then
			self[k] = {}
		end
	end
end

--[[
	Creates a broadcast function for the specified hooks field, allowing
	to trigger the hook callbacks on all registered modApiExt objects.

	The second argument is a function that provides arguments the hooks
	will be invoked with, used only if the broadcast function was invoked
	without any arguments. Can be nil to invoke argument-less hooks.
--]]
function hooks:buildBroadcastFunc(hooksField, argsFunc)
	local errfunc = function(e)
		return string.format(
			"A '%s' callback has failed:\n%s",
			hooksField, e
		)
	end

	return function(...)
		local args = {...}

		if #args == 0 then
			-- We didn't receive arguments directly. Fall back to
			-- the argument function.
			-- Make sure that all hooks receive the same arguments.
			args = argsFunc and {argsFunc()} or nil
		end

		for i, extObj in ipairs(modApiExt_internal.extObjects) do
			if extObj[hooksField] then
				for j, hook in ipairs(extObj[hooksField]) do
					-- invoke the hook in a xpcall, since errors in SkillEffect
					-- scripts fail silently, making debugging a nightmare.
					local ok, err = xpcall(
						args
							and function() hook(unpack(args)) end
							or  function() hook() end,
						errfunc
					)

					if not ok then
						local owner = extObj.owner and extObj.owner.id or "<unknown>"
						LOG("In mod id '" .. owner .. "', ", err)
					end
				end
			end
		end
	end
end

function hooks:initBroadcastHooks(tbl)
	tbl.firePilotLevelChangedHooks = self:buildBroadcastFunc("pilotLevelChangedHooks")
end

return hooks