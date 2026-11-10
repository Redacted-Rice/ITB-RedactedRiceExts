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

function mf_texts:_getUpgradeLabelForSlot(pawn, slot)
	if not pawn then return nil end
	local mechType = utils.getMechType(pawn)
	local config = registry:getCustomMechUpgradeConfig(mechType, slot)
	if config then
		return utils.resolveText(config.label, pawn)
	end
	return nil
end

local DEFAULT_CUSTOM_TOOLTIP = "Custom upgrade without a description. Usual bonus for this upgrade do not apply."
function mf_texts:_getUpgradeTooltipForSlot(pawn, slot, default)
	if not pawn then return default end
	local mechType = utils.getMechType(pawn)
	local config = registry:getCustomMechUpgradeConfig(mechType, slot)

	if config then
		if config.tooltip then
			return self._utils.resolveText(config.tooltip, pawn)
		else
			return DEFAULT_CUSTOM_TOOLTIP
		end
	end
	return default
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
		getContent = function()
			return "Upgrade_HealthLabel", "MechFORGE_Tooltip_Health"
		end,
	})
	InGameToolTip.forBox("upgrade_movement_button", "upgrade_movement_loc", {
		static = true,
		getContent = function()
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
