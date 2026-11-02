-- Hook system for MechFORGE state events
-- Uses shared utility functions from memhack hooks

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "Hooks", mech_forge.DEBUG.HOOKS and mech_forge.DEBUG.ENABLED)

-- Create hooks object
local hooks = {
	-- args: TBD
	"reactorCoreChanged",

	-- args: TBD
	"upgradePowered",

	-- args: TBD
	"upgradeUnpowered",
}

hooks.DEFAULT_PRIORITY = memhack.hooks.DEFAULT_PRIORITY
hooks.INTERNAL_PRIORITY = memhack.hooks.INTERNAL_PRIORITY
hooks.addTo = memhack.hooks.addTo
hooks.clearHooks = memhack.hooks.clearHooks
hooks.handleFailure = memhack.hooks.handleFailure
hooks.buildBroadcastFunc = memhack.hooks.buildBroadcastFunc
hooks.reload = memhack.hooks.reload

function hooks:init()
	self:addTo(mech_forge, SUBMODULE)
	self:initBroadcastHooks()
	return self
end

function hooks:load()
	self:reload(SUBMODULE)
	return self
end

function hooks:initBroadcastHooks()
	self["fireReactorCoreChangedHooks"] = self:buildBroadcastFunc("reactorCoreChangedHooks", nil, nil, SUBMODULE)
	self["fireUpgradePoweredHooks"] = self:buildBroadcastFunc("upgradePoweredHooks", nil, nil, SUBMODULE)
	self["fireUpgradeUnpoweredHooks"] = self:buildBroadcastFunc("upgradeUnpoweredHooks", nil, nil, SUBMODULE)
end

return hooks
