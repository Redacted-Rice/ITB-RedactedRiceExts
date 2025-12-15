-- Type handlers for different data types

local typeHandlers = {}

-- Supported data types and their memory operations
typeHandlers.TYPE_HANDLERS = {
	byte = {
		read = function(address)
			return StructureManager._dll.memory.readByte(address)
		end,
		write = function(address, value)
			StructureManager._dll.memory.writeByte(address, value)
		end,
		size = 1
	},

	int = {
		read = function(address)
			return StructureManager._dll.memory.readInt(address)
		end,
		write = function(address, value)
			StructureManager._dll.memory.writeInt(address, value)
		end,
		size = 4
	},

	bool = {
		read = function(address)
			return StructureManager._dll.memory.readBool(address)
		end,
		write = function(address, value)
			StructureManager._dll.memory.writeBool(address, value)
		end,
		size = 1
	},

	double = {
		read = function(address)
			return StructureManager._dll.memory.readDouble(address)
		end,
		write = function(address, value)
			StructureManager._dll.memory.writeDouble(address, value)
		end,
		size = 8
	},

	float = {
		read = function(address)
			return StructureManager._dll.memory.readFloat(address)
		end,
		write = function(address, value)
			StructureManager._dll.memory.writeFloat(address, value)
		end,
		size = 4
	},

	string = {
		read = function(address, maxLength)
			if not maxLength then
				error("string type requires a 'maxLength' field (including null terminator)")
			end
			return StructureManager._dll.memory.readCString(address, maxLength)
		end,
		write = function(address, value, maxLength)
			if not maxLength then
				error("string type requires a 'maxLength' field (including null terminator)")
			end
			StructureManager._dll.memory.writeCString(address, value, maxLength)
		end,
		size = nil  -- Variable size
	},

	pointer = {
		read = function(address)
			return StructureManager._dll.memory.readPointer(address)
		end,
		write = function(address, value)
			StructureManager._dll.memory.writePointer(address, value)
		end,
		size = 4  -- 32-bit pointers
	},

	bytearray = {
		read = function(address, length)
			if not length then
				error("bytearray type requires a 'length' field")
			end
			return StructureManager._dll.memory.readByteArray(address, length)
		end,
		write = function(address, value, length)
			StructureManager._dll.memory.writeByteArray(address, value)
		end,
		size = nil  -- Variable size, specified in field definition
	},

	struct = {
		read = function(address, structType)
			-- This function is not directly used; getters handle struct wrapping
			if not structType then
				error("struct type requires a 'structType' field")
			end
			return address  -- Return the address for wrapping
		end,
		write = function(address, value, structType)
			error("Cannot write entire struct directly. Modify individual fields instead.")
		end,
		size = nil  -- Size determined by the struct definition
	}
}

return typeHandlers

