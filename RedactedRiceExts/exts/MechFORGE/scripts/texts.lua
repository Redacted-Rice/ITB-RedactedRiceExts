-- Hover tooltips for innate Health/Move reactor slots on the mech upgrade screen.

local mf_texts = {}

mf_texts._logger = memhack.logger
mf_texts._submodule = mf_texts._logger.register(
	"MechFORGE",
	"Texts",
	mech_forge.DEBUG.TEXTS and mech_forge.DEBUG.ENABLED
)

mf_texts.SLOT_TO_TEXT_ID = {
	[mech_forge.VANILLA_UPGRADES.HEALTH] = "Upgrade_HealthLabel",
	[mech_forge.VANILLA_UPGRADES.MOVE] = "Upgrade_MoveLabel",
}

mf_texts.TEXT_ID_TO_SLOT = {
	Upgrade_HealthLabel = mech_forge.VANILLA_UPGRADES.HEALTH,
	Upgrade_MoveLabel = mech_forge.VANILLA_UPGRADES.MOVE,
}

mf_texts.STATS_BASE_TEXT = {
	Stats_Base_Health = mech_forge.VANILLA_UPGRADES.HEALTH,
	Stats_Base_Move = mech_forge.VANILLA_UPGRADES.MOVE,
}

mf_texts.STATS_UPGRADE_TEXT = {
	Stats_Health_Upgrade = mech_forge.VANILLA_UPGRADES.HEALTH,
	Stats_Move_Upgrade = mech_forge.VANILLA_UPGRADES.MOVE,
}

mf_texts.SLOT_REACTOR_BOX = {
	[mech_forge.VANILLA_UPGRADES.HEALTH] = "upgrade_health_button",
	[mech_forge.VANILLA_UPGRADES.MOVE] = "upgrade_movement_button",
}

mf_texts.SLOT_REACTOR_LOC = {
	[mech_forge.VANILLA_UPGRADES.HEALTH] = "upgrade_health_loc",
	[mech_forge.VANILLA_UPGRADES.MOVE] = "upgrade_movement_loc",
}

-- Cache on pawn selection changes
mf_texts._selectedPawn = nil
mf_texts._customConfigBySlot = {}
mf_texts._gettextOverrideCache = {}

function mf_texts:_rebuildSelectionCache(pawn)
	self._selectedPawn = nil
	self._customConfigBySlot = {}
	self._gettextOverrideCache = {}

	if GetCurrentMission() or not pawn then
		return
	end

	local mechType = self._utils.getMechType(pawn)
	if not mechType then
		return
	end

	self._selectedPawn = pawn
	for slot, textId in pairs(self.SLOT_TO_TEXT_ID) do
		local config = self._registry:getCustomMechUpgradeConfig(mechType, slot)
		if config then
			self._customConfigBySlot[slot] = config
			self._gettextOverrideCache[textId] = self._utils.resolveText(config.label, pawn)
		end
	end

	for id, slot in pairs(self.STATS_UPGRADE_TEXT) do
		if self._customConfigBySlot[slot] then
			self._gettextOverrideCache[id] = ""
		end
	end
end

function mf_texts:_vanillaBonusForSlot(slot)
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		return mech_forge.VANILLA_BONUSES.MOVE
	end
	return mech_forge.VANILLA_BONUSES.HEALTH
end

function mf_texts:_upgradeCombinedStatForSlot(pawn, slot)
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

function mf_texts:_getSelectedMechUpgradeInfo(slot)
	return self._selectedPawn, self._customConfigBySlot[slot]
end

function mf_texts:_customStatsLabelForTextId(id, r1, r2, r3)
	if self._gettextOverrideCache[id] ~= nil then
		return self._gettextOverrideCache[id]
	end

	local slot = self.STATS_BASE_TEXT[id]
	if not slot then
		return nil
	end

	local pawn, config = self:_getSelectedMechUpgradeInfo(slot)
	if not pawn or not config then
		return nil
	end

	local value = self:_upgradeCombinedStatForSlot(pawn, slot)
	return mf_texts._origGetText(id, value, r2, r3)
end

function mf_texts:_customUpgradeLabelForTextId(id)
	if self._gettextOverrideCache[id] ~= nil then
		return self._gettextOverrideCache[id]
	end
	return nil
end

function mf_texts:_installGetTextOverride()
	mf_texts._origGetText = GetText
	function GetText(id, r1, r2, r3)
		if type(id) == "string" then
			-- Check each of our custom override cases. If one matches and returns a label
			-- use that. Otherwise, it falls through to the original fn
			local label = mf_texts:_customStatsLabelForTextId(id, r1, r2, r3)
			if label ~= nil then
				return label
			end

			label = mf_texts:_customUpgradeLabelForTextId(id)
			if label ~= nil then
				return label
			end
		end
		return mf_texts._origGetText(id, r1, r2, r3)
	end
end

function mf_texts:_registerDefaultText()
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

function mf_texts:_upgradeLabelTitleForSlot(slot)
	local textId = self.SLOT_TO_TEXT_ID[slot]
	if not textId then
		return nil
	end
	return GetText(textId)
end

function mf_texts:_getUpgradeTooltipForSlot(slot, pawn)
	if not self._utils.isValidUpgradeSlot(slot) or not pawn then
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

function mf_texts:_registerReactorBoxDefs()
	-- vanilla images.lua has these boxes commented out for some reason
	-- Add them back in for the tooltips box api
	local slotSize = Point(122, 32)
	for _, boxName in pairs(self.SLOT_REACTOR_BOX) do
		InGameToolTip.registerBox(boxName, Point(0, 0), slotSize)
	end
end

function mf_texts:_registerReactorSlotTooltips()
	for _, slot in pairs(mech_forge.VANILLA_UPGRADES) do
		InGameToolTip.forBox(self.SLOT_REACTOR_BOX[slot], self.SLOT_REACTOR_LOC[slot], {
			static = true,
		})
	end
end

function mf_texts:_updateToolTips(pawn)
	for _, slot in pairs(mech_forge.VANILLA_UPGRADES) do
		local title, body = self:_getUpgradeTooltipForSlot(slot, pawn)
		InGameToolTip.updateTipContent(self.SLOT_REACTOR_BOX[slot], body, title)
	end
end

function mf_texts:_onUpgradeSelectedPawnChanged(pawn, oldPawn)
	self:_rebuildSelectionCache(pawn)
	self:_updateToolTips(pawn)
end

function mf_texts:_subscribeUpgradeSelectedPawnChanged()
	memhack.hooks.events.onUpgradeSelectedPawnChanged:subscribe(function(pawn, oldPawn)
		mf_texts:_onUpgradeSelectedPawnChanged(pawn, oldPawn)
	end)
end

function mf_texts:init()
	self._logger.logInfo(self._submodule, "init")
	self._registry = mech_forge._subobjects.registry
	self._utils = mech_forge._subobjects.utils
	self:_rebuildSelectionCache(nil)

	self:_registerDefaultText()
	self:_installGetTextOverride()
	self:_registerReactorBoxDefs()
	self:_registerReactorSlotTooltips()
	self:_subscribeUpgradeSelectedPawnChanged()
end

return mf_texts
