--[[
	Structure System for ITB-MemHack

	This module provides a way to define memory structures with typed fields.
	Each field definition includes an offset, type, and optional length.

	Getters and setters are automatically generated for each field, calling
	into the memhack DLL to read/write at the appropriate addresses.

	Structures are automatically registered to memhack.structures[name] table.

--]]

local Structure = {}

-- memhack DLL reference
local _dll = nil

-- handler to defined structures
local _structures = {}

-- Supported data types and their memory operations
local TYPE_HANDLERS = {
	int = {
		read = function(dll, address)
			return dll.memory.readInt(address)
		end,
		write = function(dll, address, value)
			dll.memory.writeInt(address, value)
		end,
		size = 4
	},

	bool = {
		read = function(dll, address)
			return dll.memory.readBool(address)
		end,
		write = function(dll, address, value)
			dll.memory.writeBool(address, value)
		end,
		size = 1
	},

	double = {
		read = function(dll, address)
			return dll.memory.readDouble(address)
		end,
		write = function(dll, address, value)
			dll.memory.writeDouble(address, value)
		end,
		size = 8
	},

	float = {
		read = function(dll, address)
			return dll.memory.readFloat(address)
		end,
		write = function(dll, address, value)
			dll.memory.writeFloat(address, value)
		end,
		size = 4
	},

	string = {
		read = function(dll, address, maxLength)
			local str = dll.memory.readString(address)
			if maxLength and #str > maxLength then
				return str:sub(1, maxLength)
			end
			return str
		end,
		write = function(dll, address, value, maxLength)
			local writeValue = value
			if maxLength and #value > maxLength then
				writeValue = value:sub(1, maxLength)
			end
			dll.memory.writeString(address, writeValue)
		end,
		size = nil  -- Variable size
	},

	pointer = {
		read = function(dll, address)
			return dll.memory.readPointer(address)
		end,
		write = function(dll, address, value)
			dll.memory.writePointer(address, value)
		end,
		size = 4  -- 32-bit pointers
	},

	bytearray = {
		read = function(dll, address, length)
			if not length then
				error("bytearray type requires a 'length' field")
			end
			return dll.memory.readByteArray(address, length)
		end,
		write = function(dll, address, value, length)
			dll.memory.writeByteArray(address, value)
		end,
		size = nil  -- Variable size, specified in field definition
	}
}

-- Initialize the structure system with a DLL instance and structs table
-- dll: The memhack DLL instance
-- structs: The table where structures will be registered (memhack.structs). Optional
-- returns the structs table (passed one or internally generated one)
function Structure.init(dll, structs)
	_dll = dll
	_structures = structs or {}
	return _structures
end

-- Capitalize first letter of a string
local function capitalize(str)
	return str:sub(1, 1):upper() .. str:sub(2)
end

-- Validate field definition
local function validateField(name, field)
	if type(field) ~= "table" then
		error(string.format("Field '%s' must be a table", name))
	end

	if type(field.offset) ~= "number" then
		error(string.format("Field '%s' must have a numeric 'offset'", name))
	end

	if not field.type then
		error(string.format("Field '%s' must have a 'type'", name))
	end

	if not TYPE_HANDLERS[field.type] then
		error(string.format("Field '%s' has unknown type '%s'", name, field.type))
	end

	if field.type == "bytearray" and not field.length then
		error(string.format("Field '%s' with type 'bytearray' must have a 'length'", name))
	end
end

local function generatePointerGetters(StructType, fieldName, fieldDef, handler, capitalizedName)
	-- Raw pointer getter (getXxxPtr)
	local ptrGetterName = "get" .. capitalizedName .. "Ptr"
	StructType[ptrGetterName] = function(self)
		local address = self._address + fieldDef.offset
		return handler.read(_dll, address)
	end

	-- Typed wrapper getter (getXxx) if pointedType specified
	if fieldDef.pointedType then
		local wrapperGetterName = "get" .. capitalizedName
		StructType[wrapperGetterName] = function(self)
			local address = self._address + fieldDef.offset
			local ptrValue = handler.read(_dll, address)

			-- Return nil if pointer is null
			if ptrValue == 0 or ptrValue == nil then
				return nil
			end

			-- Resolve the pointed type (string name to actual structure)
			local pointedStruct = fieldDef.pointedType
			if type(pointedStruct) == "string" then
				pointedStruct = _structures[pointedStruct]
				if not pointedStruct then
					error(string.format("Unknown structure type: %s", fieldDef.pointedType))
				end
			end

			-- Create and return wrapped structure
			return pointedStruct.new(ptrValue)
		end
	end
end

local function generatePointerSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local ptrSetterName = "set" .. capitalizedName .. "Ptr"
	StructType[ptrSetterName] = function(self, value)
		local address = self._address + fieldDef.offset
		handler.write(_dll, address, value)
	end
end

local function generateStandardGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local getterName = "get" .. capitalizedName
	StructType[getterName] = function(self)
		local address = self._address + fieldDef.offset

		if fieldDef.type == "bytearray" then
			return handler.read(_dll, address, fieldDef.length)
		elseif fieldDef.type == "string" and fieldDef.maxLength then
			return handler.read(_dll, address, fieldDef.maxLength)
		else
			return handler.read(_dll, address)
		end
	end
end

local function generateStandardSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local setterName = "set" .. capitalizedName
	StructType[setterName] = function(self, value)
		local address = self._address + fieldDef.offset

		if fieldDef.type == "bytearray" then
			handler.write(_dll, address, value, fieldDef.length)
		elseif fieldDef.type == "string" and fieldDef.maxLength then
			handler.write(_dll, address, value, fieldDef.maxLength)
		else
			handler.write(_dll, address, value)
		end
	end
end

-- Build all structure methods from a layout
local function buildStructureMethods(StructType, layout)
	-- Clear existing generated methods
	for fieldName, _ in pairs(layout) do
        local capitalizedName = capitalize(fieldName)
        StructType["get" .. capitalizedName] = nil
        StructType["set" .. capitalizedName] = nil
        StructType["get" .. capitalizedName .. "Ptr"] = nil
        StructType["set" .. capitalizedName .. "Ptr"] = nil
	end

	-- Generate getter and setter methods for each field
	for fieldName, fieldDef in pairs(layout) do
        local capitalizedName = capitalize(fieldName)
        local handler = TYPE_HANDLERS[fieldDef.type]

        if fieldDef.type == "pointer" then
            generatePointerGetters(StructType, fieldName, fieldDef, handler, capitalizedName)
            generatePointerSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
        else
            generateStandardGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
            generateStandardSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
        end
	end
end

-- Validate structure name and all fields
local function validateStructureDefinition(name, layout)
	if type(name) ~= "string" then
		error("Structure name must be a string")
	end

	for fieldName, field in pairs(layout) do
		validateField(fieldName, field)
	end
end

-- Create base structure metatable with layout
local function createStructureType(name, layout)
	local StructType = {}
	StructType.__index = StructType
	StructType._layout = layout
	StructType._name = name
	return StructType
end

-- Add instance methods to structure type
local function addInstanceMethods(StructType, layout)
	-- Get base address
	function StructType:getBaseAddress()
		return self._address
	end

	-- Set base address
	function StructType:setBaseAddress(address)
		self._address = address
	end

	-- Get field offset (relative)
	function StructType:getFieldOffset(fieldName)
		local field = layout[fieldName]
		if not field then
			error(string.format("Unknown field: %s", fieldName))
		end
		return field.offset
	end

	-- Get field address (absolute)
	function StructType:getFieldAddress(fieldName)
		local field = layout[fieldName]
		if not field then
			error(string.format("Unknown field: %s", fieldName))
		end
		return self._address + field.offset
	end
end

-- Add static methods to structure type
local function addStaticMethods(StructType, name, layout)
	-- Constructor
	function StructType.new(address)
		local instance = setmetatable({}, StructType)
		instance._address = address
		return instance
	end

	-- Calculate structure size
	function StructType.getSize()
		local maxOffset = 0
		local maxSize = 0

		for _, field in pairs(layout) do
			if field.offset > maxOffset then
				maxOffset = field.offset
				local handler = TYPE_HANDLERS[field.type]
				if handler.size then
					maxSize = handler.size
				elseif field.length then
					maxSize = field.length
				else
					return nil  -- Cannot determine size
				end
			end
		end

		return maxOffset + maxSize
	end

	-- Get layout definition
	function StructType.getLayout()
		return layout
	end

	-- Get structure name
	function StructType.getName()
		return name
	end
end

-- Register structure to structs table
local function registerStructure(name, StructType)
	_structures[name] = StructType
end

-- Define a new structure type
function Structure.define(name, layout)
	if not _dll then
		error("Structure system not initialized. Call Structure.init() first (should be done by memhack.init())")
	end

	validateStructureDefinition(name, layout)

	local StructType = createStructureType(name, layout)
	buildStructureMethods(StructType, layout)
	addInstanceMethods(StructType, layout)
	addStaticMethods(StructType, name, layout)
	registerStructure(name, StructType)

	return StructType
end

-- Validate additional fields for extension
local function validateAndMergeExtensionFields(name, existingLayout, additionalFields)
	-- Validate new fields
	for fieldName, field in pairs(additionalFields) do
		validateField(fieldName, field)
	end

	-- Check for duplicate field names
	for fieldName, _ in pairs(additionalFields) do
		if existingLayout[fieldName] then
			error(string.format("Field '%s' already exists in structure '%s'", fieldName, name))
		end
		existingLayout[fieldName] = field
	end
end

-- Extend an existing structure with additional fields
function Structure.extend(name, additionalFields)
	if not _dll then
		error("Structure system not initialized. Call Structure.init() first (should be done by memhack.init())")
	end

	local existingStruct = _structures[name]
	if not existingStruct then
		error(string.format("Cannot extend unknown structure: %s", name))
	end

	local layout = existingStruct._layout
	validateAndMergeExtensionFields(name, layout, additionalFields)
	buildStructureMethods(existingStruct, layout)

	return existingStruct
end

-- Helper function to create an array of structures
function Structure.array(structType, baseAddress, count, stride)
	local arr = {}

	local structSize = stride or structType.getSize()
	if not structSize then
		error("Cannot create array: structure size unknown. Provide 'stride' parameter.")
	end

	for i = 0, count - 1 do
		local address = baseAddress + (i * structSize)
		arr[i + 1] = structType.new(address)  -- Lua uses 1-based indexing
	end

	arr.count = count
	arr.stride = structSize
	arr.baseAddress = baseAddress

	return arr
end

return Structure
