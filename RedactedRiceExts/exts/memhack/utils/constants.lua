-- ITB-wide core slot values stored in mech hp/move core ints, weapon
-- power/upgrade lists, and pilot innate power lists.
return {
	CORE_TYPE_NORMAL = 1,
	CORE_TYPE_SKILL_BONUS = 2,
	CORE_TYPE_UNDOABLE = 3, -- transient state before a core slot is locked in
}