local mocks = require("helpers/mocks")
local M = {}

function M.setupGlobals()
	_G.LOG = _G.LOG or function() end

	_G.Point = _G.Point or function(x, y)
		return { x = x, y = y }
	end
	_G.Boxes = _G.Boxes or {}
	_G.Rect2D = _G.Rect2D or function(origin, size)
		return { origin = origin, size = size }
	end
	_G.Location = _G.Location or {}
	_G.GetCurrentMission = _G.GetCurrentMission or function()
		return nil
	end

	_G.mod_loader = _G.mod_loader or {
		logger = { log = function() end },
		mods = {
			redactedrice_exts = {
				resourcePath = "../../",
			},
			redactedrice_mech_forge = {
				resourcePath = "",
				parent = "redactedrice_exts",
			},
		},
	}

	_G.GetParentPath = _G.GetParentPath or function()
		return ""
	end

	_G.modApi = _G.modApi or {}
	_G.modApi.currentMod = "redactedrice_mech_forge"
	_G.modApi.getCurrentMod = _G.modApi.getCurrentMod or function(self)
		return _G.mod_loader.mods[self.currentMod]
	end
	_G.modApi.isVersionAbove = _G.modApi.isVersionAbove or function(_, a, b)
		return a > b
	end
	_G.modApi.dictionary = _G.modApi.dictionary or {}
	_G.modApi.setText = function(self, id, text)
		self.dictionary[id] = text
	end
	_G.modApi.events = _G.modApi.events or {}
	setmetatable(_G.modApi.events, {
		__index = function(t, k)
			local ev = { subscribe = function() end, dispatch = function() end }
			rawset(t, k, ev)
			return ev
		end,
	})

	_G.Event = _G.Event or setmetatable({
		buildErrorMessage = function(prefix, errorMsg)
			return prefix .. tostring(errorMsg)
		end,
		isStackOverflowError = function(errorMsg)
			return type(errorMsg) == "string" and errorMsg:match("stack overflow")
		end,
	}, {
		__call = function(_, config)
			local event = {
				subscribers = {},
				subscribe = function(eventSelf, fn)
					local sub = {
						listenerFn = fn,
						event = eventSelf,
						isClosed = function()
							return sub.event == nil
						end,
					}
					table.insert(eventSelf.subscribers, sub)
					return sub
				end,
				unsubscribe = function(eventSelf, subscription)
					for i, sub in ipairs(eventSelf.subscribers) do
						if sub == subscription or sub.listenerFn == subscription then
							table.remove(eventSelf.subscribers, i)
							sub.event = nil
							return true
						end
					end
					return false
				end,
				dispatch = function(eventSelf, ...)
					for _, sub in ipairs(eventSelf.subscribers) do
						sub.listenerFn(...)
					end
				end,
			}
			return event
		end,
	})

	_G.Game = _G.Game or {
		GetPawn = function(self, pawnId)
			return nil
		end,
		GetStrategySelectedPawn = function(self)
			return nil
		end,
		GetUpgradeSelectedPawnId = function()
			return nil
		end,
		GetUpgradeSelectedPawn = function()
			return nil
		end,
		GetSelectedPawn = function()
			return nil
		end,
		IsUpgradeMenuOpen = function()
			return false
		end,
	}
end

function M.initMemhackHooks()
	_G.memhack = _G.memhack or {}
	_G.memhack.DEBUG = {
		ENABLED = false,
		HOOKS = false,
		STRUCTS = false,
		STATE_TRACKER = false,
		SCANNER = false,
		SKILL_CORE_SYNC = false,
	}

	for name, value in pairs(dofile("../memhack/utils/constants.lua")) do
		memhack[name] = value
	end

	local loggerFunc, loggerErr = loadfile("../memhack/utils/logger.lua")
	if not loggerFunc then
		error("Failed to load memhack logger: " .. tostring(loggerErr))
	end
	memhack.logger = loggerFunc()

	local hooksMod, hooksErr = loadfile("../memhack/scripts/hooks.lua")
	if not hooksMod then
		error("Failed to load memhack hooks: " .. tostring(hooksErr))
	end
	memhack.hooks = hooksMod()
	memhack.hooks:init()

	local getTextWrappers = dofile("../memhack/utils/get_text_wrappers.lua")
	memhack.getTextWrappers = getTextWrappers
end

M.setupGlobals()
M.initMemhackHooks()

_G.GetText = function(id, r1, r2, r3)
	if modApi and modApi.dictionary and modApi.dictionary[id] then
		local text = modApi.dictionary[id]
		if type(text) == "function" then
			return text(r1, r2, r3)
		end
		return text
	end
	return "TEXT:" .. tostring(id)
end

-- mech_forge requires parent libs/inGameToolTip (no game UI in busted)
package.preload["../../libs/inGameToolTip"] = function()
	local tooltipStub = {
		version = "0.0.0-test",
		_boxUiByName = {},
		_boxSpecs = {},
	}

	function tooltipStub.registerBox(_, boxName, origin, size)
		if not boxName or not origin or not size then
			return false
		end
		if _G.Boxes[boxName] ~= nil then
			return false
		end
		_G.Boxes[boxName] = _G.Rect2D(origin, size)
		return true
	end

	function tooltipStub.forBox(box, loc, options)
		table.insert(tooltipStub._boxSpecs, {
			box = box,
			loc = loc,
			options = options or {},
		})
	end

	function tooltipStub.updateTipContent()
		return true
	end

	function tooltipStub.forUiElement() end

	_G.InGameToolTip = tooltipStub
	return tooltipStub
end

require("mech_forge")
mech_forge.DEBUG.ENABLED = false
mech_forge.DEBUG.MANAGER = false
mech_forge.DEBUG.STATE_TRACKER = false
mech_forge.DEBUG.HOOKS = false
mech_forge.DEBUG.REGISTRY = false

local sub = mech_forge._subobjects
sub.hooks:init()
sub.manager:init()
sub.state_tracker:init()
-- texts pulls in hangar UI; call M.initTexts() from specs that need GetText overrides
mech_forge:exposeAPI()
mech_forge:load({})

function M.initTexts()
	if not M._textsInitialized then
		sub.texts:init()
		M._textsInitialized = true
	else
		sub.texts:_registerTexts()
	end
end

M.forge = mech_forge

function M.resetState()
	M._upgradeMenuOpen = false
	_G.modApi.dictionary = {}
	_G.Game = {
		GetPawn = function(self, pawnId)
			return nil
		end,
		GetStrategySelectedPawn = function(self)
			return nil
		end,
		GetUpgradeSelectedPawnId = function()
			return M._upgradeMenuOpen and 0 or nil
		end,
		GetUpgradeSelectedPawn = function()
			if not M._upgradeMenuOpen then
				return nil
			end
			return Game:GetPawn(0)
		end,
		GetSelectedPawn = function()
			return nil
		end,
		IsUpgradeMenuOpen = function()
			return M._upgradeMenuOpen
		end,
	}

	local registry = M.forge._subobjects.registry
	registry._byMechType = {}

	local stateTracker = M.forge._subobjects.state_tracker
	stateTracker:_resetAllTrackers()

	local hooksMod = M.forge.hooks
	hooksMod:clearHooks(hooksMod)
	hooksMod:initBroadcastHooks()
	M.forge:load({})
end

function M.setupSquadPawns(pawnById)
	_G.Game.GetPawn = function(self, pawnId)
		return pawnById[pawnId]
	end
end

function M.setUpgradeMenuOpen(open)
	M._upgradeMenuOpen = open
end

M.createMockPawn = mocks.createMockPawn

return M
