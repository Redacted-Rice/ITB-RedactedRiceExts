-- Hover tooltips for innate Health/Move reactor slots on the mech upgrade screen.

local mf_texts = {}

local registry = mech_forge._subobjects.registry
local utils = mech_forge._subobjects.utils

mf_texts._logger = memhack.logger
mf_texts._submodule = mf_texts._logger.register(
	"MechFORGE",
	"Texts",
	mech_forge.DEBUG.TEXTS and mech_forge.DEBUG.ENABLED
)
mf_texts._notEnoughPowerDefaultText = "Requires $1 power!"

mf_texts.STATS_BASE_TEXT = {
	Stats_Base_Health = mech_forge.VANILLA_UPGRADES.HEALTH,
	Stats_Base_Move = mech_forge.VANILLA_UPGRADES.MOVE,
}

mf_texts.STATS_UPGRADE_TEXT = {
	Stats_Health_Upgrade = mech_forge.VANILLA_UPGRADES.HEALTH,
	Stats_Move_Upgrade = mech_forge.VANILLA_UPGRADES.MOVE,
}

-- Tracks last hovered upgrade slot so we can tell which it was clicked on for the
-- not enough power text
mf_texts._trackedInnateSlot = {}

function mf_texts:_vanillaBonusForSlot(slot)
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		return mech_forge.VANILLA_BONUSES.MOVE
	end
	return mech_forge.VANILLA_BONUSES.HEALTH
end

-- Shown when hovering over stat upgrade to hide the hacking we do under
-- the hood to remove the vanilla bonus
function mf_texts:_upgradeCombinedStatForSlot(pawn, slot)
	local value
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		value = pawn:GetRawMoveSpeed()
	else
		value = pawn:GetMaxBaseHealth()
	end

	if utils.isMechUpgradePowered(pawn, slot) then
		value = value + self:_vanillaBonusForSlot(slot)
	end
	return value
end

function mf_texts:_getCustomUpgradeConfig(pawn, slot)
	if not pawn then
		return nil
	end
	return registry:getCustomMechUpgradeConfig(utils.getMechType(pawn), slot)
end

function mf_texts:_getUpgradeLabelForSlot(pawn, slot)
	if not pawn then return nil end
	local config = self:_getCustomUpgradeConfig(pawn, slot)
	if config then
		return utils.resolveText(config.label, pawn)
	end
	return nil
end

local DEFAULT_CUSTOM_TOOLTIP = "Custom upgrade without a description. Usual bonus for this upgrade do not apply."
function mf_texts:_getUpgradeTooltipForSlot(pawn, slot, default)
	if not pawn then return default end
	local config = self:_getCustomUpgradeConfig(pawn, slot)

	if config then
		if config.tooltip then
			return self._utils.resolveText(config.tooltip, pawn)
		else
			return DEFAULT_CUSTOM_TOOLTIP
		end
	end
	return default
end

function mf_texts:_trackInnateSlotFromTooltip(boxName, slot)
	local hitbox = InGameToolTip.getUiBox(boxName)
	if hitbox and hitbox.hovered then
		self._trackedInnateSlot[slot] = true
	else
		self._trackedInnateSlot[slot] = nil
	end
end

function mf_texts._isUpgradeMenuOpen()
	return Game and Game:IsUpgradeMenuOpen()
end

function mf_texts:_getNoPowerTextForTrackedInnateSlot(pawn, r1)
	if not pawn then
		return GetVanillaText(self._notEnoughPowerDefaultText, r1)
	end

	local mechType = utils.getMechType(pawn)
	for slot, _ in pairs(self._trackedInnateSlot) do
		local config = registry:getCustomMechUpgradeConfig(mechType, slot)
		if config then
			return GetVanillaText(self._notEnoughPowerDefaultText, tostring(config.coreSlots))
		end
	end
	return GetVanillaText(self._notEnoughPowerDefaultText, r1)
end

function mf_texts:_blankStatUpgradeText(pawn, slot, text, r1, r2, r3)
	-- If we aren't overrriding this slot, return original text
	if not pawn or not self:_getCustomUpgradeConfig(pawn, slot) then
		return GetVanillaText(text, r1, r2, r3)
	end
	return ""
end

function mf_texts:_getCombinedStatText(pawn, slot, text, r1, r2, r3)
	if not self:_getCustomUpgradeConfig(pawn, slot) then
		return GetVanillaText(text, r1, r2, r3)
	end
	local value = self:_upgradeCombinedStatForSlot(pawn, slot)
	-- Use vanilla version to avoid infinite recursion
	return GetVanillaText(text, value)
end

function mf_texts:_registerTexts()
	modApi:setText("Upgrade_HealthLabel", memhack.getTextWrappers.basedOnSelectedPawn(function(pawn)
		return self:_getUpgradeLabelForSlot(pawn, mech_forge.VANILLA_UPGRADES.HEALTH)
	end))

	modApi:setText("Upgrade_MoveLabel", memhack.getTextWrappers.basedOnSelectedPawn(function(pawn)
		return self:_getUpgradeLabelForSlot(pawn, mech_forge.VANILLA_UPGRADES.MOVE)
	end))

	modApi:setText(
		"MechFORGE_Tooltip_Health", memhack.getTextWrappers.basedOnSelectedPawn(function(pawn)
			return self:_getUpgradeTooltipForSlot(pawn, mech_forge.VANILLA_UPGRADES.HEALTH,
					"When powered, mech gains +2 max health.")
	end))

	modApi:setText(
		"MechFORGE_Tooltip_Move", memhack.getTextWrappers.basedOnSelectedPawn(function(pawn)
			return self:_getUpgradeTooltipForSlot(pawn, mech_forge.VANILLA_UPGRADES.MOVE,
					"When powered, mech gains +1 move speed.")
	end))

	-- There are two versions but this is the one called for the mech upgrades. I think
	-- the other one might not be used?
	modApi:setText("Upgrade_NoPower", memhack.getTextWrappers.basedOnSelectedPawn(function(pawn, id, r1)
		return self:_getNoPowerTextForTrackedInnateSlot(pawn, r1)
	end))

	for textId, slot in pairs(self.STATS_UPGRADE_TEXT) do
		modApi:setText(textId, memhack.getTextWrappers.basedOnSelectedPawn(function(pawn, id, r1, r2, r3)
			return self:_blankStatUpgradeText(pawn, slot, id, r1, r2, r3)
		end))
	end

	for textId, slot in pairs(self.STATS_BASE_TEXT) do
		modApi:setText(textId, memhack.getTextWrappers.basedOnSelectedPawn(function(pawn, id, r1, r2, r3)
			return self:_getCombinedStatText(pawn, slot, id, r1, r2, r3)
		end))
	end
end

function mf_texts:_registerReactorBoxDefs()
	-- vanilla images.lua has these boxes commented out for some reason
	-- Add them back in for the tooltips box api
	local slotSize = Point(122, 32)
	InGameToolTip.registerBox("upgrade_health_button", Point(0, 0), slotSize)
	InGameToolTip.registerBox("upgrade_movement_button", Point(0, 0), slotSize)
end

function mf_texts:_registerReactorSlotTooltips()
	InGameToolTip.forBox("upgrade_health_button", "upgrade_health_loc", {
		static = true,
		isActive = self._isUpgradeMenuOpen,
		getContent = function()
			self:_trackInnateSlotFromTooltip("upgrade_health_button", mech_forge.VANILLA_UPGRADES.HEALTH)
			return "Upgrade_HealthLabel", "MechFORGE_Tooltip_Health"
		end,
	})
	InGameToolTip.forBox("upgrade_movement_button", "upgrade_movement_loc", {
		static = true,
		isActive = self._isUpgradeMenuOpen,
		getContent = function()
			self:_trackInnateSlotFromTooltip("upgrade_movement_button", mech_forge.VANILLA_UPGRADES.MOVE)
			return "Upgrade_MoveLabel", "MechFORGE_Tooltip_Move"
		end,
	})
end

function mf_texts:init()
	self._logger.logInfo(self._submodule, "init")
	self._registry = mech_forge._subobjects.registry
	self._utils = mech_forge._subobjects.utils

	self:_registerTexts()
	self:_registerReactorBoxDefs()
	self:_registerReactorSlotTooltips()
end

return mf_texts
