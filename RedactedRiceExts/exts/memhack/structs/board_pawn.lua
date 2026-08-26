-- BoardPawn struct for accessing pawn memory offsets
-- This wraps the BoardPawn object to provide access to internal memory structures

local MemhackBoardPawn = memhack.structManager:define("BoardPawn", {
	-- Smart "double" pointer to pilot data at 0x980
	pilot = { offset = 0x980, type = "pointer", subType = "Pilot", noSetter = true },

	-- Pointers to mech hp / move core ints for the innate mech upgrades
	moveCore = { offset = 0xC4C, type = "pointer", noSetter = true },
	hpCore = { offset = 0xC5C, type = "pointer", noSetter = true },
})

-- Values stored at hpCore / moveCore pointed ints
MemhackBoardPawn.CORE_TYPE_NORMAL = 1
MemhackBoardPawn.CORE_TYPE_SKILL_BONUS = 2
MemhackBoardPawn.CORE_TYPE_UNDOABLE = 3 -- transient state before a core slot is locked in

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

function MemhackBoardPawn:getMoveCore()
	return readPointedInt(self:getMoveCorePtr())
end

function MemhackBoardPawn:setMoveCore(value)
	return writePointedInt(self:getMoveCorePtr(), value)
end

function MemhackBoardPawn:getHpCore()
	return readPointedInt(self:getHpCorePtr())
end

function MemhackBoardPawn:setHpCore(value)
	return writePointedInt(self:getHpCorePtr(), value)
end
