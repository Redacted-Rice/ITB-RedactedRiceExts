--[[
	Mech upgrade state tracking for MechFORGE

	Tracks hp/move core ints per squad mech (pawn 0-2). Any core change fires
	mechUpgradeCoreChanged. Powered vs unpowered comes from memhack.CORE_TYPE_NONE.
]]

local mech_upgrade_state_tracker = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "StateTracker", mech_forge.DEBUG.STATE_TRACKER and mech_forge.DEBUG.ENABLED)

-- Local references to other submodules (set during init)
local hooks = nil
local utils = nil

-- Creates and empty pawn state with both upgrade slots empty for tracking
function mech_upgrade_state_tracker:_emptyPawnState()
	return {
		[mech_forge.VANILLA_UPGRADES.HEALTH] = nil,
		[mech_forge.VANILLA_UPGRADES.MOVE] = nil,
	}
end

-- Resets all trackers to empty states
function mech_upgrade_state_tracker:_resetAllTrackers()
	self._tracked = {
		[0] = self:_emptyPawnState(),
		[1] = self:_emptyPawnState(),
		[2] = self:_emptyPawnState(),
	}
end

function mech_upgrade_state_tracker:init()
	hooks = mech_forge._subobjects.hooks
	utils = mech_forge._subobjects.utils

	return self
end

-------------------- Hook dispatch --------------------

-- cehck for and fire hooks if the state changed for the pawn
function mech_upgrade_state_tracker:_fireSlotHooks(pawn, pawnId, slot, oldCore, newCore)
	if not Game then
		logger.logWarn(SUBMODULE,
			"skipped mech upgrade hooks for pawn %d slot %s (Game unavailable)",
			pawnId, slot)
		return
	end

	local mechType = utils.getMechType(pawn)
	local wasPowered = utils.isCorePowered(oldCore)
	local isPowered = utils.isCorePowered(newCore)

	-- Should only be called when its changed
	logger.logDebug(SUBMODULE,
			"core changed pawn %d slot %s core %s->%s powered %s->%s",
			pawnId, slot, tostring(oldCore), tostring(newCore),
			tostring(wasPowered), tostring(isPowered))
	hooks.fireMechUpgradeCoreChangedHooks(
			slot, pawn, pawnId, mechType, oldCore, newCore)

	 -- If it transitioned from powered to unpowered or vice versa, fire the appropriate hook
	if not wasPowered and isPowered then
		hooks.fireMechUpgradePoweredHooks(slot, pawn, pawnId, mechType, newCore)
	elseif wasPowered and not isPowered then
		hooks.fireMechUpgradeUnpoweredHooks(slot, pawn, pawnId, mechType, oldCore)
	end
end

-------------------- State update orchestration --------------------

function mech_upgrade_state_tracker:_updatePawnUpgradeState(pawn, pawnId)
	if not pawn then
		return
	end

	local tracked = self._tracked[pawnId]
	if not tracked then
		tracked = self:_emptyPawnState()
		self._tracked[pawnId] = tracked
	end

	for _, slot in pairs(mech_forge.VANILLA_UPGRADES) do
		local newCore = utils.getMechUpgradeCore(pawn, slot)
		local oldCore = tracked[slot]
		if oldCore ~= newCore then
			self:_fireSlotHooks(pawn, pawnId, slot, oldCore, newCore)
			tracked[slot] = newCore
		end
	end
end

function mech_upgrade_state_tracker:_updateSquadUpgradeStates()
	if not Game then
		logger.logWarn(SUBMODULE, "skipped squad upgrade state update (Game unavailable)")
		return
	end

	for pawnId = 0, 2 do
		local pawn = Game:GetPawn(pawnId)
		self:_updatePawnUpgradeState(pawn, pawnId)
	end
end

function mech_upgrade_state_tracker:_updateAllStates()
	self:_updateSquadUpgradeStates()
end

-------------------- State Queries --------------------

function mech_upgrade_state_tracker:_getTrackedCore(pawnId, slot)
	local tracked = self._tracked[pawnId]
	if not tracked then
		return nil
	end
	return tracked[slot]
end

-- pawnId -> slot -> core int (tracked, not live)
function mech_upgrade_state_tracker:_getTrackedSquadState()
	local result = {}
	for pawnId = 0, 2 do
		local pawnState = self._tracked[pawnId]
		if pawnState then
			result[pawnId] = {}
			for _, slot in pairs(mech_forge.VANILLA_UPGRADES) do
				result[pawnId][slot] = pawnState[slot]
			end
		end
	end
	return result
end

return mech_upgrade_state_tracker
