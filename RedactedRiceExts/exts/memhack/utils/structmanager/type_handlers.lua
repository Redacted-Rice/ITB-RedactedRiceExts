-- Type handlers for different data types

-- Supported data types and their memory operations
local typeHandlers = {
	byte = {
		read = function(address)
			return StructManager._dll.memory.readByte(address)
		end,
		write = function(address, value)
			StructManager._dll.memory.writeByte(address, value)
		end,
		size = 1
	},

	int = {
		read = function(address)
			return StructManager._dll.memory.readInt(address)
		end,
		write = function(address, value)
			StructManager._dll.memory.writeInt(address, value)
		end,
		size = 4
	},

	bool = {
		read = function(address)
			return StructManager._dll.memory.readBool(address)
		end,
		write = function(address, value)
			StructManager._dll.memory.writeBool(address, value)
		end,
		size = 1
	},

	double = {
		read = function(address)
			return StructManager._dll.memory.readDouble(address)
		end,
		write = function(address, value)
			StructManager._dll.memory.writeDouble(address, value)
		end,
		size = 8
	},

	float = {
		read = function(address)
			return StructManager._dll.memory.readFloat(address)
		end,
		write = function(address, value)
			StructManager._dll.memory.writeFloat(address, value)
		end,
		size = 4
	},

	string = {
		read = function(address, maxLength)
			if not maxLength then
				error("string type requires a 'maxLength' field (including null terminator)")
			end
			return StructManager._dll.memory.readCString(address, maxLength)
		end,
		write = function(address, value, maxLength)
			if not maxLength then
				error("string type requires a 'maxLength' field (including null terminator)")
			end
			StructManager._dll.memory.writeCString(address, value, maxLength)
		end,
		size = nil  -- Variable size
	},

	pointer = {
		read = function(address)
			return StructManager._dll.memory.readPointer(address)
		end,
		write = function(address, value)
			StructManager._dll.memory.writePointer(address, value)
		end,
		size = 4  -- 32-bit pointers
	},

	bytearray = {
		read = function(address, length)
			if not length then
				error("bytearray type requires a 'length' field")
			end
			return StructManager._dll.memory.readByteArray(address, length)
		end,
		write = function(address, value, length)
			StructManager._dll.memory.writeByteArray(address, value)
		end,
		size = nil  -- Variable size, specified in field definition
	},

	struct = {
		read = function(address, subType)
			-- This function is not directly used; getters handle struct wrapping
			if not subType then
				error("struct type requires a 'subType' field")
			end
			return address  -- Return the address for wrapping
		end,
		write = function(address, value, subType)
			error("Cannot write entire struct directly. Modify individual fields instead.")
		end,
		size = nil  -- Size determined by the struct definition
	}
}

return typeHandlers

