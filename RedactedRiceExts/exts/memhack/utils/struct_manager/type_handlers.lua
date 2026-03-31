-- Type handlers for different data types

local logger = require(memhack.scriptPath .."utils/logger")
local SUBMODULE = logger.register("Memhack", "StructManager", memhack.DEBUG.ENABLED)

-- Supported data types and their memory operations
local typeHandlers = {
	byte = {
		read = function(address)
			local result = StructManager._dll.memory.readByte(address)
			return result
		end,
		write = function(address, value)
			StructManager._dll.memory.writeByte(address, value)
		end,
		size = 1
	},

	int = {
		read = function(address)
			local result = StructManager._dll.memory.readInt(address)
			return result
		end,
		write = function(address, value)
			StructManager._dll.memory.writeInt(address, value)
		end,
		size = 4
	},

	bool = {
		read = function(address)
			local result = StructManager._dll.memory.readBool(address)
			return result
		end,
		write = function(address, value)
			StructManager._dll.memory.writeBool(address, value)
		end,
		size = 1
	},

	double = {
		read = function(address)
			local result = StructManager._dll.memory.readDouble(address)
			return result
		end,
		write = function(address, value)
			StructManager._dll.memory.writeDouble(address, value)
		end,
		size = 8
	},

	float = {
		read = function(address)
			local result = StructManager._dll.memory.readFloat(address)
			return result
		end,
		write = function(address, value)
			StructManager._dll.memory.writeFloat(address, value)
		end,
		size = 4
	},

	string = {
		read = function(address, maxLength)
			if not maxLength then
				logger.logError(SUBMODULE, "string type requires a 'maxLength' field (including null terminator)")
				return nil
			end
			local result = StructManager._dll.memory.readNullTermString(address, maxLength)
			return result
		end,
		write = function(address, value, maxLength)
			if not maxLength then
				logger.logError(SUBMODULE, "string type requires a 'maxLength' field (including null terminator)")
				return
			end
			StructManager._dll.memory.writeNullTermString(address, value, maxLength)
		end,
		size = nil  -- Variable size
	},

	pointer = {
		read = function(address)
			local result = StructManager._dll.memory.readPointer(address)
			return result
		end,
		write = function(address, value)
			StructManager._dll.memory.writePointer(address, value)
		end,
		size = 4  -- 32-bit pointers
	},

	bytearray = {
		read = function(address, length)
			if not length then
				logger.logError(SUBMODULE, "bytearray type requires a 'length' field")
				return nil
			end
			local result = StructManager._dll.memory.readByteArray(address, length)
			return result
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
				logger.logError(SUBMODULE, "struct type requires a 'subType' field")
				return nil
			end
			return address  -- Return the address for wrapping
		end,
		write = function(address, value, subType)
			logger.logError(SUBMODULE, "Cannot write entire struct directly. Modify individual fields instead.")
		end,
		size = nil  -- Size determined by the struct definition
	}
}

return typeHandlers

