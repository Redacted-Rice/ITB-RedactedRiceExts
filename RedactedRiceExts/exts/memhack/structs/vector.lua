-- A std C++ vector
-- not really sure how writing would work but I don't need it for
-- now so just make it read only. I imagine up to capacity it would
-- work fine but not sure how to reallocate or if it would do it
-- automatically or not
local MemhackVector = memhack.structManager.define("Vector", {
	-- These point to pointer of a type. They are type "pointer" themselves
	-- which is currently not allowed
	head = { offset = 0x0, type = "pointer", hideSetter = true },
	next = { offset = 0x4, type = "pointer", hideSetter = true },
	-- No type on capacity
	capacity = { offset = 0x8, type = "pointer", hideSetter = true },
})
-- TODO: have a way to create templated type?

function onModsFirstLoaded()
	MemhackVector.PTR_SIZE = 4
	
	MemhackVector.getSize = function(self)
		return (self:getNextPtr() - self:getHeadPtr()) / self.PTR_SIZE
	end
	
	-- 1 indexed
	MemhackVector.getPtrAt = function(self, idx)
		return memhack.dll.memory.readPointer(self:getHeadPtr() + (idx - 1) * self.PTR_SIZE)
	end
	
	-- 1 indexed
	MemhackVector.getPtrsRange = function(self, startIdx, endIdx)
		local ptrs = {}
		for idx = startIdx, endIdx do
			table.insert(ptrs, self:getPtrAt(idx))
		end
		return ptrs
	end
	
	MemhackVector.getPtrsAll = function(self)
		return self:getPtrsRange(1, self:getSize())
	end
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)