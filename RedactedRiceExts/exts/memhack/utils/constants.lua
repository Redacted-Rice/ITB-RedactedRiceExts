-- ITB-wide core slot values stored in mech hp/move core ints, weapon
-- power/upgrade lists, and pilot innate power lists.
return {
	CORE_TYPE_NONE = 0, -- unpowered / empty reactor gear slot
	CORE_TYPE_NORMAL = 1,
	CORE_TYPE_SKILL_BONUS = 2,
	CORE_TYPE_UNDOABLE = 3, -- transient state before a core slot is locked in

	-- BoardPawn armedWeaponId at memhack offset 0x40 (matches GetArmedWeaponId / GetArmedWeapon)
	ARMED_WEAPON_ID_NONE = -1,
	ARMED_WEAPON_ID_MOVE = 0,
	ARMED_WEAPON_ID_PRIMARY = 1,
	ARMED_WEAPON_ID_SECONDARY = 2,
	ARMED_WEAPON_ID_SKILL_REPAIR = 50,
}