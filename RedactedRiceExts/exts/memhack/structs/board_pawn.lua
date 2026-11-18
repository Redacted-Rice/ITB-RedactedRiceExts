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
	moveCoreList = { offset = 0xC4C, type = "struct", subType = "Vector", noSetter = true },
	hpCoreList = { offset = 0xC5C, type = "struct", subType = "Vector", noSetter = true },

	-- Pawn core info for assigned and unassigned cores of all types
	reactorNormalUnassigned = { offset = 0xF68, type = "int" },
	reactorNormalAssigned = { offset = 0xF6C, type = "int" },
	reactorSkillBonusUnassigned = { offset = 0xF70, type = "int" },
	reactorSkillBonusAssigned = { offset = 0xF74, type = "int" },
	reactorNormalUndoableUnassigned = { offset = 0xF78, type = "int" },
	reactorNormalUndoableAssigned = { offset = 0xF7C, type = "int" },
})

MemhackBoardPawn._INNATE_CORE_HP = "hp"
MemhackBoardPawn._INNATE_CORE_MOVE = "move"

function MemhackBoardPawn:_innateCoreVector(which)
	if which == MemhackBoardPawn._INNATE_CORE_HP then
		return self:getHpCoreList()
	end
	return self:getMoveCoreList()
end

function MemhackBoardPawn:_isInnateCorePowered(which)
	local vec = self:_innateCoreVector(which)
	local list = vec:getIntList()
	for i = 1, #list do
		local core = list[i]
		if core == nil or core == memhack.CORE_TYPE_NONE then
			return false
		end
	end
	return true
end

function MemhackBoardPawn:isHpPowered()
	return self:_isInnateCorePowered(MemhackBoardPawn._INNATE_CORE_HP)
end

function MemhackBoardPawn:isMovePowered()
	return self:_isInnateCorePowered(MemhackBoardPawn._INNATE_CORE_MOVE)
end

function MemhackBoardPawn:getHpCorePowerList()
	return self:_innateCoreVector(MemhackBoardPawn._INNATE_CORE_HP):getIntList()
end

function MemhackBoardPawn:getMoveCorePowerList()
	return self:_innateCoreVector(MemhackBoardPawn._INNATE_CORE_MOVE):getIntList()
end

function MemhackBoardPawn:hpCorePowerListMatches(values)
	return self:_innateCoreVector(MemhackBoardPawn._INNATE_CORE_HP):intListMatches(values)
end

function MemhackBoardPawn:moveCorePowerListMatches(values)
	return self:_innateCoreVector(MemhackBoardPawn._INNATE_CORE_MOVE):intListMatches(values)
end

function MemhackBoardPawn:_setInnateCorePowerList(which, values)
	if type(values) ~= "table" or #values < 1 then
		return false
	end
	local vec = self:_innateCoreVector(which)
	return vec:setIntListResizingIfNeeded(values)
end

function MemhackBoardPawn:setHpCorePowerList(values)
	return self:_setInnateCorePowerList(MemhackBoardPawn._INNATE_CORE_HP, values)
end

function MemhackBoardPawn:setMoveCorePowerList(values)
	return self:_setInnateCorePowerList(MemhackBoardPawn._INNATE_CORE_MOVE, values)
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