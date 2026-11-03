-- BoardPawn struct for accessing pawn memory offsets
-- This wraps the BoardPawn object to provide access to internal memory structures

local MemhackBoardPawn = memhack.structManager:define("BoardPawn", {
	armedWeaponId = { offset = 0x40, type = "int" },
	selected = { offset = 0x4C, type = "bool", hideGetter = true, hideSetter = true },
	pawnType = { offset = 0x94, type = "struct", subType = "ItBString" },

	-- Smart "double" pointer to pilot data at 0x980
	pilot = { offset = 0x980, type = "pointer", subType = "Pilot", noSetter = true },

	-- GetMoveSpeed returns 0 if its <= 0 but I need it to return negative values for mechFORGE
	-- so I include the direct memory access here as well
	moveSpeed = { offset = 0x990, type = "int" },

	-- Pointers to mech hp / move core ints for the innate mech upgrades
	moveCore = { offset = 0xC4C, type = "pointer", noSetter = true },
	hpCore = { offset = 0xC5C, type = "pointer", noSetter = true },
})

local function readPointedInt(ptr)
	if not ptr or ptr == 0 then
		return nil
	end
	return memhack.dll.memory.readInt(ptr)
end

local function writePointedInt(ptr, value)
	if not ptr or ptr == 0 then
		return false
	end
	memhack.dll.memory.writeInt(ptr, value)
	return true
end

local genItBStrGetSetWrappers = memhack.structs.ItBString.makeItBStringGetSetWrappers
genItBStrGetSetWrappers(MemhackBoardPawn, "pawnType")

-- Returns memhack.CORE_TYPE_* values.
function MemhackBoardPawn:getMoveCore()
	return readPointedInt(self:getMoveCorePtr())
end

-- value: memhack.CORE_TYPE_NORMAL, CORE_TYPE_SKILL_BONUS, or CORE_TYPE_UNDOABLE.
function MemhackBoardPawn:setMoveCore(value)
	return writePointedInt(self:getMoveCorePtr(), value)
end

-- Returns memhack.CORE_TYPE_* values.
function MemhackBoardPawn:getHpCore()
	return readPointedInt(self:getHpCorePtr())
end

-- value: memhack.CORE_TYPE_NORMAL, CORE_TYPE_SKILL_BONUS, or CORE_TYPE_UNDOABLE.
function MemhackBoardPawn:setHpCore(value)
	return writePointedInt(self:getHpCorePtr(), value)
end

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
