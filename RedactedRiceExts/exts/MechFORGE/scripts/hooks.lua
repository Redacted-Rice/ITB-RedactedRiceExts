-- Hook system for MechFORGE state events
-- Uses shared utility functions from memhack hooks

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "Hooks", mech_forge.DEBUG.HOOKS and mech_forge.DEBUG.ENABLED)

-- Create hooks object
local hooks = {
	-- args:
	--  slot (string) - the slot that changed (mech_forge.VANILLA_UPGRADES.HEALTH or .MOVE)
	--  pawn (Pawn) - the pawn
	--  pawnId (number) - the pawn ID
	--  mechType (string) - the mech type
	--  oldCore (number) - the old core value (e.g. memhack.CORE_TYPE_NONE)
	--  newCore (number) - the new core value (e.g. memhack.CORE_TYPE_NORMAL)
	"mechUpgradeCoreChanged",

	-- args:
	--  slot (string) - the slot that changed (mech_forge.VANILLA_UPGRADES.HEALTH or .MOVE)
	--  pawn (Pawn) - the pawn
	--  pawnId (number) - the pawn ID
	--  mechType (string) - the mech type
	--  newCore (number) - the new core value (e.g. memhack.CORE_TYPE_NORMAL)
	"mechUpgradePowered",

	-- args:
	--  slot (string) - the slot that changed (mech_forge.VANILLA_UPGRADES.HEALTH or .MOVE)
	--  pawn (Pawn) - the pawn
	--  pawnId (number) - the pawn ID
	--  mechType (string) - the mech type
	--  oldCore (number) - the old core value (e.g. memhack.CORE_TYPE_NORMAL)
	"mechUpgradeUnpowered",
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
	self["fireMechUpgradeCoreChangedHooks"] = self:buildBroadcastFunc("mechUpgradeCoreChangedHooks", nil, nil, SUBMODULE)
	self["fireMechUpgradePoweredHooks"] = self:buildBroadcastFunc("mechUpgradePoweredHooks", nil, nil, SUBMODULE)
	self["fireMechUpgradeUnpoweredHooks"] = self:buildBroadcastFunc("mechUpgradeUnpoweredHooks", nil, nil, SUBMODULE)
end

return hooks
