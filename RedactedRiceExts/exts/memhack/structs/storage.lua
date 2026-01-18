-- A std C++ vector but with a particularity so I made it its own class
-- For some reason it always has at least 3 entries
local MemhackStorage = memhack.structManager.define("Storage", {
	-- hide getter because we are just custom wrapping the vector to account for the
	-- extra objects
	vector = { offset = 0x0, type = "struct", structType = "Vector", hideGetter = true, --[[structs don't define setters]] },
})

function onModsFirstLoaded()
	MemhackStorage.UNUSABLE_ENTRIES = 3
	
	MemhackStorage.getSize = function(self)
		return self:_getVector():getSize() - self.UNUSABLE_ENTRIES
	end
	
	-- 1 indexed
	MemhackStorage.getAt = function(self, idx)
		local idxAddress = self:_getVector():getPtrAt(idx + self.UNUSABLE_ENTRIES)
		return memhack.structs.StorageObject.new(idxAddress)
	end
	
	-- 1 indexed
	MemhackStorage.getRange = function(self, startIdx, endIdx)
		local addresses = self:_getVector():getPtrsRange(
				startIdx + self.UNUSABLE_ENTRIES, endIdx + self.UNUSABLE_ENTRIES)
		local objects = {}
		for _, address in ipairs(addresses) do
			table.insert(objects, memhack.structs.StorageObject.new(address))
		end
	end
	
	MemhackStorage.getAll = function(self)
		return self:getRange(1, self:getSize())
	end
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)