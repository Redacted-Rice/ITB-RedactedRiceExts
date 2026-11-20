--[[
	Mech upgrade state tracking for MechFORGE

	Tracks hp/move core power lists per squad mech (pawn 0-2). Any list change (values
	or length) fires mechUpgradeCoreChanged.
]]

local mf_state_tracker = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "StateTracker",
		mech_forge.DEBUG.STATE_TRACKER and mech_forge.DEBUG.ENABLED)

-- Local references to other submodules (set during init)
local hooks = nil
local utils = nil
local manager = nil

-- Creates and empty pawn state with both upgrade slots empty for tracking
function mf_state_tracker:_emptyPawnState()
	return {
		[mech_forge.VANILLA_UPGRADES.HEALTH] = nil,
		[mech_forge.VANILLA_UPGRADES.MOVE] = nil,
	}
end

-- Resets all trackers to empty states
function mf_state_tracker:_resetAllTrackers()
	self._tracked = {
		[0] = self:_emptyPawnState(),
		[1] = self:_emptyPawnState(),
		[2] = self:_emptyPawnState(),
	}
end

function mf_state_tracker:init()
	hooks = mech_forge._subobjects.hooks
	utils = mech_forge._subobjects.utils
	manager = mech_forge._subobjects.manager

	return self
end

-------------------- Hook dispatch --------------------

function mf_state_tracker:_fireSlotHooks(pawn, pawnId, slot, oldList, newList)
	if not Game then
		logger.logWarn(SUBMODULE,
			"skipped mech upgrade hooks for pawn %d slot %s (Game unavailable)",
			pawnId, slot)
		return
	end

	local mechType = utils.getMechType(pawn)
	local wasPowered = utils.isMechUpgradeCoresPowered(oldList)
	local isPowered = utils.isMechUpgradeCoresPowered(newList)

	-- Should only be called when its changed
	logger.logDebug(SUBMODULE,
			"core changed pawn %d slot %s powered %s->%s",
			pawnId, slot, tostring(wasPowered), tostring(isPowered))


	hooks.fireMechUpgradeCoreChangedHooks(slot, pawn, pawnId, mechType, oldList, newList)
	-- If it transitioned from powered to unpowered or vice versa, fire the appropriate hook
	if not wasPowered and isPowered then
		hooks.fireMechUpgradePoweredHooks(slot, pawn, pawnId, mechType, newList)
	elseif wasPowered and not isPowered then
		hooks.fireMechUpgradeUnpoweredHooks(slot, pawn, pawnId, mechType, oldList)
	end
end

-------------------- State update orchestration --------------------

function mf_state_tracker:_coresMatchTracked(pawn, slot, trackedList)
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
		return pawn:GetMemhackObj():getHpCores():intListMatches(trackedList)
	elseif slot == mech_forge.VANILLA_UPGRADES.MOVE then
		return pawn:GetMemhackObj():getMoveCores():intListMatches(trackedList)
	end
	return false
end

function mf_state_tracker:_getVanillaCores(vPawn, slot)
	local mhCores = utils.getMechUpgradeMemhackCores(vPawn, slot)
	if not mhCores then
		return nil
	end
	return mhCores:getIntList()
end

function mf_state_tracker:_updatePawnUpgradeState(pawn, pawnId)
	if not pawn then
		return
	end

	local tracked = self._tracked[pawnId]
	if not tracked then
		tracked = self:_emptyPawnState()
		self._tracked[pawnId] = tracked
	end

	for _, slot in pairs(mech_forge.VANILLA_UPGRADES) do
		local trackedList = tracked[slot]
		-- Fire on any change INCLUDING the first one so we trigger when we load
		-- into a game so we can adjust it there too
		if not self:_coresMatchTracked(pawn, slot, trackedList) then
			manager:reconcilePartialMultiCoreUpgrade(pawn, slot)
			local newList = self:_getVanillaCores(pawn, slot)
			self:_fireSlotHooks(pawn, pawnId, slot, trackedList, newList)
			tracked[slot] = newList
		end
	end
end

function mf_state_tracker:_updateSquadUpgradeStates()
	if not Game then
		return
	end

	for pawnId = 0, 2 do
		local pawn = Game:GetPawn(pawnId)
		self:_updatePawnUpgradeState(pawn, pawnId)
	end
end

function mf_state_tracker:_updateAllStates()
	self:_updateSquadUpgradeStates()
end

-------------------- State Queries --------------------

function mf_state_tracker:_getTrackedCores(pawnId, slot)
	local tracked = self._tracked[pawnId]
	if not tracked then
		return nil
	end
	return tracked[slot]
end

-- pawnId -> slot -> core power list (tracked, not live)
function mf_state_tracker:_getTrackedSquadState()
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

mf_state_tracker:_resetAllTrackers()
return mf_state_tracker
