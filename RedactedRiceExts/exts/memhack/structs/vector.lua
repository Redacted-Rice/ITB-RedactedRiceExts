-- A std C++ vector
-- not really sure how writing would work but I don't need it for
-- now so just make it read only. I imagine up to capacity it would
-- work fine but not sure how to reallocate or if it would do it
-- automatically or not
local MemhackVector = memhack.structManager:define("Vector", {
	-- These point to pointer of a type. They are type "pointer" themselves
	-- which is currently not allowed
	head = { offset = 0x0, type = "pointer", hideSetter = true },
	next = { offset = 0x4, type = "pointer", hideSetter = true },
	-- No type on capacity
	capacity = { offset = 0x8, type = "pointer", hideSetter = true },
})
-- TODO: have a way to create templated type?

MemhackVector.PTR_SIZE = 4
MemhackVector.INT_SIZE = 4
-- Data allocated by memhack for growing vectors
MemhackVector._allocByteArray = {}

function MemhackVector:getSize()
	local head = self:getHeadPtr()
	if head == 0 then
		return 0
	end
	local nextPtr = self:getNextPtr()
	if nextPtr < head then
		return 0
	end
	return (nextPtr - head) / self.PTR_SIZE
end

-- 1 indexed
function MemhackVector:getPtrAt(idx)
	local head = self:getHeadPtr()
	if head == 0 then
		return nil
	end
	local size = self:getSize()
	if type(idx) ~= "number" or idx < 1 or idx > size then
		return nil
	end
	return memhack.dll.memory.readPointer(head + (idx - 1) * self.PTR_SIZE)
end

-- 1 indexed
function MemhackVector:getPtrsRange(startIdx, endIdx)
	local size = self:getSize()
	if size < 1 then
		return {}
	end
	if type(startIdx) ~= "number" or type(endIdx) ~= "number" then
		return {}
	end
	if startIdx < 1 or endIdx > size or startIdx > endIdx then
		return {}
	end
	local ptrs = {}
	for idx = startIdx, endIdx do
		table.insert(ptrs, self:getPtrAt(idx))
	end
	return ptrs
end

function MemhackVector:getPtrsAll()
	return self:getPtrsRange(1, self:getSize())
end

-- Int-element helpers (e.g. pilot innate skill power list). Size uses the same
-- 4-byte stride as PTR_SIZE on this build.
function MemhackVector:getIntSize()
	local head = self:getHeadPtr()
	if head == 0 then
		return 0
	end
	local nextPtr = self:getNextPtr()
	if nextPtr < head then
		return 0
	end
	return (nextPtr - head) / self.INT_SIZE
end

-- Int-element capacity of the vector
function MemhackVector:getIntCapacity()
	local head = self:getHeadPtr()
	if head == 0 then
		return 0
	end
	local capPtr = self:getCapacityPtr()
	if capPtr < head then
		return 0
	end
	return (capPtr - head) / self.INT_SIZE
end

-- 1 indexed
function MemhackVector:getIntAt(idx)
	local size = self:getIntSize()
	if type(idx) ~= "number" or idx < 1 or idx > size then
		return nil
	end
	return memhack.dll.memory.readInt(self:getHeadPtr() + (idx - 1) * self.INT_SIZE)
end

-- 1 indexed. Does not grow the vector.
function MemhackVector:setIntAt(idx, value)
	local size = self:getIntSize()
	if type(idx) ~= "number" or idx < 1 or idx > size then
		return false
	end
	memhack.dll.memory.writeInt(self:getHeadPtr() + (idx - 1) * self.INT_SIZE, value)
	return true
end

-- Compare live vector ints to a lua table without building a full int list.
function MemhackVector:intListMatches(values)
	if type(values) ~= "table" then
		return self:getIntSize() == 0
	end
	local size = self:getIntSize()
	if #values ~= size then
		return false
	end
	for i = 1, size do
		if self:getIntAt(i) ~= values[i] then
			return false
		end
	end
	return true
end

function MemhackVector:getIntList()
	local values = {}
	for i = 1, self:getIntSize() do
		values[i] = self:getIntAt(i)
	end
	return values
end

-- Requires #values to match current vector size. Does not grow or shrink.
function MemhackVector:setIntList(values)
	if type(values) ~= "table" then
		return false
	end
	local size = self:getIntSize()
	if #values ~= size then
		return false
	end
	if size < 1 then
		return true
	end
	for i, value in ipairs(values) do
		if not self:setIntAt(i, value) then
			return false
		end
	end
	return true
end

-- Determine capacity for the vector based on size to have some extra space
function MemhackVector:_intCapacityForSize(size)
	-- Use a simple power of 2 capacity. This is fairly common approach
	local cap = 1
	while cap < size do
		cap = cap * 2
	end
	return cap
end

-- Initializes vector data for the new allocated memory
function MemhackVector:_setNewAllocData(head, size, capacity)
	self:_setHeadPtr(head)
	self:_setNextPtr(head + size * self.INT_SIZE)
	self:_setCapacityPtr(head + capacity * self.INT_SIZE)
end

-- Writes the int list to the vector and sets the next pointer based on the size
function MemhackVector:_writeIntListAndSetNextPtr(values)
	local head = self:getHeadPtr()
	local size = #values
	for i = 1, size do
		memhack.dll.memory.writeInt(head + (i - 1) * self.INT_SIZE, values[i])
	end
	self:_setNextPtr(head + size * self.INT_SIZE)
	return true
end

function MemhackVector:_freeMemhackHead(head)
	if head == 0 or not MemhackVector._allocByteArray[head] then
		return
	end
	memhack.dll.memory.freeByteArray(head)
	MemhackVector._allocByteArray[head] = nil
end

-- Grow or shrink logical size. #values is the new logical size.
function MemhackVector:setIntListResizingIfNeeded(values)
	if type(values) ~= "table" then
		return false
	end
	local newSize = #values
	local head = self:getHeadPtr()
	local capacity = self:getIntCapacity()

	-- Allow a non-allocated vector if newSize is 0
	if newSize == 0 and not head then
		return true
	end

	-- As long as the size fits capacity, just write the values and update the next ptr
	if head and newSize <= capacity then
		return self:_writeIntListAndSetNextPtr(values)
	end

	-- Need a new allocation
	local oldHead = self:getHeadPtr()
	local newCapacity = self:_intCapacityForSize(newSize)
	local newHead = memhack.dll.memory.allocByteArray(newCapacity * self.INT_SIZE)
	if not newHead or newHead == 0 then
		return false
	end
	self:_setNewAllocData(newHead, newSize, newCapacity)
	MemhackVector._allocByteArray[newHead] = true
	if not self:_writeIntListAndSetNextPtr(values) then
		return false
	end
	self:_freeMemhackHead(oldHead)
	return true
end