-- BoardPawn struct for accessing pawn memory offsets
-- This wraps the BoardPawn object to provide access to internal memory structures

local MemhackBoardPawn = memhack.structManager:define("BoardPawn", {
	-- Smart "double" pointer to pilot data at 0x980
	pilot = { offset = 0x980, type = "pointer", subType = "Pilot", noSetter = true },

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
