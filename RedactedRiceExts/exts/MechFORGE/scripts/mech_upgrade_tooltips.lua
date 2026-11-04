-- Hover tooltips for innate Health/Move reactor slots on the mech upgrade screen.

local mech_upgrade_tooltips = {}

require(GetParentPath(modApi:getCurrentMod().resourcePath) .. "libs/InGameToolTip")

mech_upgrade_tooltips._logger = memhack.logger
mech_upgrade_tooltips._submodule = mech_upgrade_tooltips._logger.register(
	"MechFORGE",
	"UpgradeTooltips",
	mech_forge.DEBUG.TOOLTIPS and mech_forge.DEBUG.ENABLED
)

mech_upgrade_tooltips.SLOT_TO_TEXT_ID = {
	[mech_forge.VANILLA_UPGRADES.HEALTH] = "Upgrade_HealthLabel",
	[mech_forge.VANILLA_UPGRADES.MOVE] = "Upgrade_MoveLabel",
}

mech_upgrade_tooltips.SLOT_REACTOR_BOX = {
	[mech_forge.VANILLA_UPGRADES.HEALTH] = "upgrade_health_button",
	[mech_forge.VANILLA_UPGRADES.MOVE] = "upgrade_movement_button",
}

mech_upgrade_tooltips.SLOT_REACTOR_LOC = {
	[mech_forge.VANILLA_UPGRADES.HEALTH] = "upgrade_health_loc",
	[mech_forge.VANILLA_UPGRADES.MOVE] = "upgrade_movement_loc",
}

function mech_upgrade_tooltips:_registerDefaultText()
	modApi:setText(
		"MechFORGE_Tooltip_Health_Vanilla",
		"When powered, mech gains +2 max health."
	)
	modApi:setText(
		"MechFORGE_Tooltip_Move_Vanilla",
		"When powered, mech gains +1 move speed."
	)
	modApi:setText(
		"MechFORGE_Tooltip_Custom_Default",
		"Custom upgrade without a description. Usual bonus for this upgrade do not apply."
	)
end

function mech_upgrade_tooltips:_upgradeLabelTitleForSlot(slot)
	local textId = self.SLOT_TO_TEXT_ID[slot]
	if not textId then
		return nil
	end
	return GetText(textId)
end

function mech_upgrade_tooltips:_getUpgradeTooltipForSlot(slot)
	if not self._utils.isValidUpgradeSlot(slot) or not Game then
		return nil, nil
	end

	local pawnId = Game:GetStrategySelectedPawn()
	if pawnId == nil then
		return nil, nil
	end

	local pawn = Game:GetPawn(pawnId)
	if not pawn then
		return nil, nil
	end

	local mechType = self._utils.getMechType(pawn)
	local config = mechType and self._registry:getCustomMechUpgradeConfig(mechType, slot) or nil
	local title = self:_upgradeLabelTitleForSlot(slot)

	local body
	if config then
		if config.tooltip then
			body = self._utils.resolveText(config.tooltip, pawn)
		else
			body = GetText("MechFORGE_Tooltip_Custom_Default")
		end
	else
		if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
			body = GetText("MechFORGE_Tooltip_Health_Vanilla")
		else
			body = GetText("MechFORGE_Tooltip_Move_Vanilla")
		end
	end

	return title, body
end

function mech_upgrade_tooltips:_registerReactorBoxDefs()
	-- vanilla images.lua has these boxes commented out for some reason
	-- Add them back in for the tooltips box api
	local slotSize = Point(122, 32)
	for _, boxName in pairs(self.SLOT_REACTOR_BOX) do
		InGameToolTip.registerBox(boxName, Point(0, 0), slotSize)
	end
end

function mech_upgrade_tooltips:_registerReactorSlotTooltips()
	for _, slot in pairs(mech_forge.VANILLA_UPGRADES) do
		InGameToolTip.forBox(self.SLOT_REACTOR_BOX[slot], self.SLOT_REACTOR_LOC[slot])
	end
end

function mech_upgrade_tooltips:_updateToolTips()
	for _, slot in pairs(mech_forge.VANILLA_UPGRADES) do
		local title, body = self:_getUpgradeTooltipForSlot(slot)
		InGameToolTip.updateTipContent(self.SLOT_REACTOR_BOX[slot], body, title)
	end
end

-- TODO later: Make this an event in memhack? I think we do this a few places now
function mech_upgrade_tooltips:_updateToolTipTextIfPawnChanged()
	if GetCurrentMission() then
		self._lastStrategyPawnId = nil
		return
	end
	if not Game then
		return
	end

	local pawnId = Game:GetStrategySelectedPawn()
	if pawnId == self._lastStrategyPawnId then
		return
	end
	self._lastStrategyPawnId = pawnId

	self:_updateToolTips()
end

function mech_upgrade_tooltips:init()
	self._logger.logInfo(self._submodule, "init")
	self._registry = mech_forge._subobjects.mech_upgrade_registry
	self._utils = mech_forge._subobjects.utils

	self:_registerDefaultText()
	self:_registerReactorBoxDefs()
	self:_registerReactorSlotTooltips()

	modApi.events.onFrameDrawStart:subscribe(function()
		mech_upgrade_tooltips:_updateToolTipTextIfPawnChanged()
	end)
end

return mech_upgrade_tooltips
