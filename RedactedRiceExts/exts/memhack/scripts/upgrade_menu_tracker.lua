-- Detects mech / pilot changes on the upgrade menu and fires memhack hooks.

local upgradeMenuTracker = {}

local logger = memhack.logger
local SUBMODULE = logger.register("Memhack", "UpgradeMenuTracker", memhack.DEBUG.ENABLED)

upgradeMenuTracker._lastPawnId = nil
upgradeMenuTracker._lastPawn = nil
upgradeMenuTracker._lastPilot = nil

function upgradeMenuTracker:_reset()
	if self._lastPawnId == nil and self._lastPawn == nil and self._lastPilot == nil then
		return
	end
	local oldPawn = self._lastPawn
	local oldPilot = self._lastPilot
	self._lastPawnId = nil
	self._lastPawn = nil
	self._lastPilot = nil
	memhack.hooks.fireUpgradeSelectedPawnChangedHooks(nil, oldPawn)
	memhack.hooks.fireUpgradeSelectedPilotChangedHooks(nil, nil, oldPilot)
end

function upgradeMenuTracker:_checkForChanges()
	if GetCurrentMission and GetCurrentMission() then
		self:_reset()
		return
	end

	if not Game then
		self:_reset()
		return
	end

	local pawnId = Game:GetUpgradeSelectedPawnId()
	if pawnId == nil then
		if self._lastPawnId ~= nil then
			self:_reset()
		end
		return
	end

	local pawn = Game:GetUpgradeSelectedPawn()
	local pilot = pawn and pawn:GetPilot() or nil

	if pawnId ~= self._lastPawnId then
		local oldPawn = self._lastPawn
		local oldPilot = self._lastPilot
		self._lastPawnId = pawnId
		self._lastPawn = pawn
		self._lastPilot = pilot
		memhack.hooks.fireUpgradeSelectedPawnChangedHooks(pawn, oldPawn)
		memhack.hooks.fireUpgradeSelectedPilotChangedHooks(pawn, pilot, oldPilot)
		return
	end

	if pilot ~= self._lastPilot then
		local oldPilot = self._lastPilot
		self._lastPilot = pilot
		memhack.hooks.fireUpgradeSelectedPilotChangedHooks(pawn, pilot, oldPilot)
	end
end

return upgradeMenuTracker
