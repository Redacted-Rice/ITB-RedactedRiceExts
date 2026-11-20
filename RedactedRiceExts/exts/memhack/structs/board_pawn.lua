-- BoardPawn struct for accessing pawn memory offsets
-- This wraps the BoardPawn object to provide access to internal memory structures

local MemhackBoardPawn = memhack.structManager:define("BoardPawn", {
	armedWeaponId = { offset = 0x40, type = "int" },
	selected = { offset = 0x4C, type = "bool", hideGetter = true, hideSetter = true },
	pawnType = { offset = 0x94, type = "struct", subType = "ItBString" },

	-- Pointer to pilot data at 0x980 (use setPilotPtr to repoint, e.g. assembly-line wreck)
	pilot = { offset = 0x980, type = "pointer", subType = "Pilot" },

	-- GetMoveSpeed returns 0 if its <= 0 but I need it to return negative values for mechFORGE
	-- so I include the direct memory access here as well
	moveSpeed = { offset = 0x990, type = "int" },

	-- Std vectors of ints for the upgrade cores (cost and what its powered with)
	moveCores = { offset = 0xC4C, type = "struct", subType = "CoreList", noSetter = true },
	hpCores = { offset = 0xC5C, type = "struct", subType = "CoreList", noSetter = true },

	-- Pawn core info for assigned and unassigned cores of all types
	reactorNormalUnassigned = { offset = 0xF68, type = "int" },
	reactorNormalAssigned = { offset = 0xF6C, type = "int" },
	reactorSkillBonusUnassigned = { offset = 0xF70, type = "int" },
	reactorSkillBonusAssigned = { offset = 0xF74, type = "int" },
	reactorNormalUndoableUnassigned = { offset = 0xF78, type = "int" },
	reactorNormalUndoableAssigned = { offset = 0xF7C, type = "int" },
})

function MemhackBoardPawn:_getReactorCount(coreType, poolType)
	if coreType == nil or coreType == memhack.CORE_TYPE_NONE then
		return 0
	end
	local getterName = "getReactor" .. memhack.CORE_TYPE_NAMES[coreType] .. poolType
	return self[getterName](self)
end

function MemhackBoardPawn:_setReactorCount(coreType, poolType, value)
	if coreType == nil or coreType == memhack.CORE_TYPE_NONE then
		return false
	end
	local setterName = "setReactor" .. memhack.CORE_TYPE_NAMES[coreType] .. poolType
	self[setterName](self, value)
	return true
end

function MemhackBoardPawn:_pickReactorCoreType(poolType)
	for _, coreType in ipairs(memhack.CORE_PULL_ORDER) do
		if self:_getReactorCount(coreType, poolType) > 0 then
			return coreType
		end
	end
	return memhack.CORE_TYPE_NONE
end

-- Internal helper for moving one core between two pools.
function MemhackBoardPawn:_moveCoreBetweenPools(coreType, fromPoolType, toPoolType)
	if coreType == nil then
		coreType = self:_pickReactorCoreType(fromPoolType)
	end
	if coreType == memhack.CORE_TYPE_NONE then
		return memhack.CORE_TYPE_NONE
	end
	local count = self:_getReactorCount(coreType, fromPoolType)
	if count < 1 then
		return memhack.CORE_TYPE_NONE
	end
	self:_setReactorCount(coreType, fromPoolType, count - 1)
	self:_setReactorCount(coreType, toPoolType, self:_getReactorCount(coreType, toPoolType) + 1)
	return coreType
end

-- Tries to move one core from the pawn unassigned to assigned pool.
-- coreType optional. When omitted, picks by CORE_PULL_ORDER.
function MemhackBoardPawn:assignMechReactorCore(coreType)
	return self:_moveCoreBetweenPools(coreType, memhack.CORE_POOL_UNASSIGNED, memhack.CORE_POOL_ASSIGNED)
end

-- Tries to move one core from the pawn assigned to unassigned pool.
-- coreType optional. When omitted, picks by CORE_PULL_ORDER.
function MemhackBoardPawn:unassignMechReactorCore(coreType)
	return self:_moveCoreBetweenPools(nil, memhack.CORE_POOL_ASSIGNED, memhack.CORE_POOL_UNASSIGNED)
end

local genItBStrGetSetWrappers = memhack.structs.ItBString.makeItBStringGetSetWrappers
genItBStrGetSetWrappers(MemhackBoardPawn, "pawnType")

-- Convert back to a vanilla pawn class by searching for the exposed pawn with the
-- expected address
function MemhackBoardPawn:toVanilla()
	local addr = self:getAddress()
	if not addr or addr == 0 then
		return nil
	end

	if Board then
		local pawns = Board:GetPawns(TEAM_ANY)
		for i = 1, pawns:size() do
			local pawn = Board:GetPawn(pawns:index(i))
			if pawn and memhack.dll.memory.getUserdataAddr(pawn) == addr then
				return pawn
			end
		end
	end
	if Game then
		for i = 0, 2 do
			local pawn = Game:GetPawn(i)
			if pawn and memhack.dll.memory.getUserdataAddr(pawn) == addr then
				return pawn
			end
		end
	end

	return nil
end
