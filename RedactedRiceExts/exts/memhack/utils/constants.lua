-- ITB-wide core slot values stored in mech hp/move core ints, weapon
-- power/upgrade lists, and pilot innate power lists.
local constants = {
	CORE_TYPE_NONE = 0, -- unpowered / empty core
	CORE_TYPE_NORMAL = 1,
	CORE_TYPE_SKILL_BONUS = 2,
	CORE_TYPE_UNDOABLE = 3, -- transient state before a core slot is locked in

	CORE_POOL_ASSIGNED = "Assigned",
	CORE_POOL_UNASSIGNED = "Unassigned",

	-- BoardPawn armedWeaponId at memhack offset 0x40 (matches GetArmedWeaponId / GetArmedWeapon)
	ARMED_WEAPON_ID_NONE = -1,
	ARMED_WEAPON_ID_MOVE = 0,
	ARMED_WEAPON_ID_PRIMARY = 1,
	ARMED_WEAPON_ID_SECONDARY = 2,
	ARMED_WEAPON_ID_SKILL_REPAIR = 50,
}

-- Additional constants that depend on the other constants
constants.CORE_PULL_ORDER = {
	constants.CORE_TYPE_NORMAL,
	constants.CORE_TYPE_UNDOABLE,
	constants.CORE_TYPE_SKILL_BONUS,
}

constants.CORE_TYPE_NAMES = {
	[constants.CORE_TYPE_NONE] = "None",
	[constants.CORE_TYPE_NORMAL] = "Normal",
	[constants.CORE_TYPE_UNDOABLE] = "NormalUndoable",
	[constants.CORE_TYPE_SKILL_BONUS] = "SkillBonus",
}

return constants
