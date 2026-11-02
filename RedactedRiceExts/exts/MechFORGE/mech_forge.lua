-- MechFORGE Extension Main Module
-- Coordinates and allows customized mech upgrades

-- Create global object
mech_forge = mech_forge or {}

local path = GetParentPath(...)

-- Debugging configuration to enable debugging for modules
mech_forge.DEBUG = {
	ENABLED = true,  -- Disable/enable all debug logging
	TRIGGER_EVENTS = false,
	HOOKS = false,
	REGISTRY = false,
	STATE_TRACKER = false,
	EFFECTS = false,
	LABELS = false,
	UTILS = false,
}

mech_forge.VANILLA_UPGRADES = {
	HEALTH = "health",
	MOVE = "move",
}

mech_forge.VANILLA_BONUSES = {
	HEALTH = 2,
	MOVE = 1,
}

mech_forge._subobjects = {}
mech_forge._subobjects.hooks = require(path.."scripts/hooks")

local hooks = mech_forge._subobjects.hooks

function mech_forge:initModules()
	hooks:init()
end

function mech_forge:exposeAPI()
	self.hooks = hooks
	self.events = hooks.events
end

function mech_forge:init()
	self:initModules()
	self:exposeAPI()
	self:addEvents()
end

function mech_forge:load(options)
	self.options = options or {}
	hooks:load()
end

function mech_forge:addEvents()
	-- Empty for now
end
