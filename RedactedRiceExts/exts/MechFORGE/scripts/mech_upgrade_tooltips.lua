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

mech_upgrade_tooltips.TEXT_ID_TO_SLOT = {
	Upgrade_HealthLabel = mech_forge.VANILLA_UPGRADES.HEALTH,
	Upgrade_MoveLabel = mech_forge.VANILLA_UPGRADES.MOVE,
}

mech_upgrade_tooltips.STATS_BASE_TEXT = {
	Stats_Base_Health = mech_forge.VANILLA_UPGRADES.HEALTH,
	Stats_Base_Move = mech_forge.VANILLA_UPGRADES.MOVE,
}

mech_upgrade_tooltips.STATS_UPGRADE_TEXT = {
	Stats_Health_Upgrade = mech_forge.VANILLA_UPGRADES.HEALTH,
	Stats_Move_Upgrade = mech_forge.VANILLA_UPGRADES.MOVE,
}

mech_upgrade_tooltips.SLOT_REACTOR_BOX = {
	[mech_forge.VANILLA_UPGRADES.HEALTH] = "upgrade_health_button",
	[mech_forge.VANILLA_UPGRADES.MOVE] = "upgrade_movement_button",
}

mech_upgrade_tooltips.SLOT_REACTOR_LOC = {
	[mech_forge.VANILLA_UPGRADES.HEALTH] = "upgrade_health_loc",
	[mech_forge.VANILLA_UPGRADES.MOVE] = "upgrade_movement_loc",
}

function mech_upgrade_tooltips:_vanillaBonusForSlot(slot)
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		return mech_forge.VANILLA_BONUSES.MOVE
	end
	return mech_forge.VANILLA_BONUSES.HEALTH
end

function mech_upgrade_tooltips:_upgradeCombinedStatForSlot(pawn, slot)
	local value
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		value = pawn:GetRawMoveSpeed()
	else
		value = pawn:GetMaxBaseHealth()
	end

	if self._utils.isMechUpgradePowered(pawn, slot) then
		value = value + self:_vanillaBonusForSlot(slot)
	end

	return value
end

function mech_upgrade_tooltips:_getSelectedPawn()
	if not Game then
		return nil
	end

	local pawnId = Game:GetStrategySelectedPawn()
	if pawnId == nil then
		return nil
	end

	return Game:GetPawn(pawnId)
end

function mech_upgrade_tooltips:_getSelectedMechUpgradeInfo(slot)
	-- Get the currently selected pawn in the strategy menu
	local pawn = self:_getSelectedPawn()
	if not pawn then
		return nil, nil
	end

	-- Get the mechtype of the pawn
	local mechType = self._utils.getMechType(pawn)
	if not mechType then
		return nil, nil
	end

	-- See if it has a custom upgrade config for this text
	local config = self._registry:getCustomMechUpgradeConfig(mechType, slot)
	if not config then
		return nil, nil
	end

	return pawn, config
end

function mech_upgrade_tooltips:_customStatsLabelForTextId(id, r1, r2, r3)
	-- If its not one of the labels we override return
	local slot = self.STATS_BASE_TEXT[id] or self.STATS_UPGRADE_TEXT[id]
	if not slot then
		return nil
	end

	-- Get the mech upgrade info for the selected pawn
	local pawn, config = self:_getSelectedMechUpgradeInfo(slot)
	if not config then
		return nil
	end

	-- If its the upgrade text, we return empty. We will combine for the
	-- the base text
	if self.STATS_UPGRADE_TEXT[id] then
		return ""
	end

	-- Its the base text, get the current combine stats and return that
	local value = self:_upgradeCombinedStatForSlot(pawn, slot)
	return mech_upgrade_tooltips._origGetText(id, value, r2, r3)
end

function mech_upgrade_tooltips:_customUpgradeLabelForTextId(id)
	-- If its not one of the labels we override return
	local slot = self.TEXT_ID_TO_SLOT[id]
	if not slot then
		return nil
	end

	-- Get the mech upgrade info for the selected pawn
	local pawn, config = self:_getSelectedMechUpgradeInfo(slot)
	if not config then
		return nil
	end

	-- Resolve the custom text
	return self._utils.resolveText(config.label, pawn)
end

function mech_upgrade_tooltips:_installGetTextOverride()
	mech_upgrade_tooltips._origGetText = GetText
	function GetText(id, r1, r2, r3)
		if type(id) == "string" then
			-- Check each of our custom override cases. If one matches and returns a label
			-- use that. Otherwise, it falls through to the original fn
			local label = mech_upgrade_tooltips:_customStatsLabelForTextId(id, r1, r2, r3)
			if label ~= nil then
				return label
			end

			label = mech_upgrade_tooltips:_customUpgradeLabelForTextId(id)
			if label ~= nil then
				return label
			end
		end
		return mech_upgrade_tooltips._origGetText(id, r1, r2, r3)
	end
end

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
	if not self._utils.isValidUpgradeSlot(slot) then
		return nil, nil
	end

	local pawn = self:_getSelectedPawn()
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
	self:_installGetTextOverride()
	self:_registerReactorBoxDefs()
	self:_registerReactorSlotTooltips()

	modApi.events.onFrameDrawStart:subscribe(function()
		mech_upgrade_tooltips:_updateToolTipTextIfPawnChanged()
	end)
end

return mech_upgrade_tooltips
