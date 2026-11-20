-- Std vector of memhack.CORE_TYPE_* used by the game for pretty much anything that needs cores

local MemhackCoreList = memhack.structManager:derive("CoreList", "Vector")

function MemhackCoreList.isCorePowered(core)
	return core ~= nil and core ~= memhack.CORE_TYPE_NONE
end

function MemhackCoreList:isCorePoweredAt(idx)
	return MemhackCoreList.isCorePowered(self:getIntAt(idx))
end

function MemhackCoreList:isPartiallyPowered()
	local size = self:getIntSize()
	local foundPowered = false
	local foundUnpowered = false
	for i = 1, size do
		if MemhackCoreList.isCorePowered(self:_uncheckedGetIntAt(i)) then
			foundPowered = true
		else
			foundUnpowered = true
		end
	end
	return foundPowered and foundUnpowered
end

function MemhackCoreList:isFullyPowered()
	local size = self:getIntSize()
	for i = 1, size do
		if not MemhackCoreList.isCorePowered(self:_uncheckedGetIntAt(i)) then
			return false
		end
	end
	return true
end
