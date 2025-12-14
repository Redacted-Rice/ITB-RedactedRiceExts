--[[
	Structure System for ITB-MemHack

	This module provides a way to define memory structures with typed fields.
	Each field definition includes an offset, type, and potentially additional
	parameters based on the type.

	Getters and setters are automatically generated for each field, calling
	into the memhack DLL to read/write at the appropriate addresses.

	Structures are automatically registered to memhack.structs[name] table.

	Generated Methods:
	- Basic types (int, bool, double, float, byte, string, bytearray):
	  - GetXxx() / SetXxx() - read/write the value
	- pointer: 32 bit pointer
	  - GetXxxPtr() / SetXxxPtr() - read/write the raw pointer value
	  - GetXxxObj() - get wrapped object at pointed address (if pointedType specified)
	- struct: Inline struct (not a pointer)
	  - GetXxxObj() - get wrapped struct at this field's address
	  - No setter - modify individual fields on the returned object instead

	Supported Types:
	- int, bool, double, float, byte: Basic types, no additional params
	- pointer: 32 bit pointer
	  - optional: pointedType for automatic wrapping of the pointed type
	- struct: Inline struct (not a pointer)
	  - required: structType
	- string: C style null terminated string
	  - required: maxLength (including null terminator)
	- bytearray: Array of bytes
	  - required: length

	Per-field optional parameters:
	- hideGetter/Setter: boolean value that prepends "_" to getter/setter method names (default: false).
	  Can be used to "hide" methods for values that should not be accessed in
	  isolation. For example, use hideSetter = true to make it clear the setter
	  should only be used internally and wrapped in other functions.
	  Use case: pilot exp and level where you would want to increase the level
	  if the exp crosses a threshold, or to limit it to 0-2.

	See functions/pilot.lua for examples
--]]

local Structure = {}

local GETTER_PREFIX = "Get"
local SETTER_PREFIX = "Set"
local HIDE_PREFIX = "_"

-- memhack DLL reference
local _dll = nil

-- handler to defined structures
local _structures = {}

-- Supported data types and their memory operations
local TYPE_HANDLERS = {
	byte = {
		read = function(dll, address)
			return dll.memory.readByte(address)
		end,
		write = function(dll, address, value)
			dll.memory.writeByte(address, value)
		end,
		size = 1
	},

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
			if not maxLength then
				error("string type requires a 'maxLength' field (including null terminator)")
			end
			return dll.memory.readCString(address, maxLength)
		end,
		write = function(dll, address, value, maxLength)
			if not maxLength then
				error("string type requires a 'maxLength' field (including null terminator)")
			end
			dll.memory.writeCString(address, value, maxLength)
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
	},

	struct = {
		read = function(dll, address, structType)
			-- This function is not directly used; getters handle struct wrapping
			if not structType then
				error("struct type requires a 'structType' field")
			end
			return address  -- Return the address for wrapping
		end,
		write = function(dll, address, value, structType)
			error("Cannot write entire struct directly. Modify individual fields instead.")
		end,
		size = nil  -- Size determined by the struct definition
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
function Structure.capitalize(str)
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

	if field.type == "string" and not field.maxLength then
		error(string.format("Field '%s' with type 'string' must have a 'maxLength' (including null terminator)", name))
	end

	if field.type == "struct" and not field.structType then
		error(string.format("Field '%s' with type 'struct' must have a 'structType'", name))
	end
end

local function generatePointerGetters(StructType, fieldName, fieldDef, handler, capitalizedName)
	-- Get the prefix
	local getterPrefix = fieldDef.hideGetter and HIDE_PREFIX .. GETTER_PREFIX or GETTER_PREFIX

	-- Raw pointer getter (GetXxxPtr)
	local ptrGetterName = getterPrefix .. capitalizedName .. "Ptr"
	StructType[ptrGetterName] = function(self)
		local address = self._address + fieldDef.offset
		return handler.read(_dll, address)
	end

	-- Typed wrapper getter (GetXxxObj) if pointedType specified
	if fieldDef.pointedType then
		local wrapperGetterName = getterPrefix .. capitalizedName .. "Obj"
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
				-- support pointers to native types where appropriate
				if pointedStruct == "pointer" or pointedStruct == "struct" then
					error(string.format("structure type '%s' not supported", pointedStruct))
				-- Types that need size
				elseif pointedStruct == "string" or pointedStruct == "bytearray" then
					if fieldDef.pointedSize == nil then
						error(string.format("pointedType '%s' requires pointedSize", pointedStruct))
					end
					return TYPE_HANDLERS[pointedStruct].read(_dll, ptrValue, fieldDef.pointedSize)
				-- unsupported types
				-- native types like int, bool, etc
				elseif TYPE_HANDLERS[pointedStruct] ~= nil then
					return TYPE_HANDLERS[pointedStruct].read(_dll, ptrValue)
				-- defined struct
				else
					pointedStruct = _structures[pointedStruct]
					if not pointedStruct then
						error(string.format("Unknown structure type: %s", fieldDef.pointedType))
					end
					-- Create and return wrapped structure
					return pointedStruct.new(ptrValue)
				end
			end

			error(string.format("Unknown structure type: %s", fieldDef.pointedType))
			return nil
		end
	end
end

local function generatePointerSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	-- Get the prefix
	local setterPrefix = fieldDef.hideSetter and HIDE_PREFIX .. SETTER_PREFIX or SETTER_PREFIX

	local ptrSetterName = setterPrefix .. capitalizedName .. "Ptr"
	StructType[ptrSetterName] = function(self, value)
		local address = self._address + fieldDef.offset
		handler.write(_dll, address, value)
	end
end

local function generateStandardGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	-- Get the prefix
	local getterPrefix = fieldDef.hideGetter and HIDE_PREFIX .. GETTER_PREFIX or GETTER_PREFIX

	local getterName = getterPrefix .. capitalizedName
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
	-- Get the prefix
	local setterPrefix = fieldDef.hideSetter and HIDE_PREFIX .. SETTER_PREFIX or SETTER_PREFIX

	local setterName = setterPrefix .. capitalizedName
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

local function generateStructGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	-- Get the prefix
	local getterPrefix = fieldDef.hideGetter and HIDE_PREFIX .. GETTER_PREFIX or GETTER_PREFIX

	local getterName = getterPrefix .. capitalizedName .. "Obj"
	StructType[getterName] = function(self)
		local address = self._address + fieldDef.offset

		-- Resolve the struct type (string name to actual structure)
		local structType = fieldDef.structType
		if type(structType) == "string" then
			structType = _structures[structType]
			if not structType then
				error(string.format("Unknown structure type: %s", fieldDef.structType))
			end
		end

		-- Create and return wrapped structure at this address
		return structType.new(address)
	end
end

-- Build all structure methods from a layout
local function buildStructureMethods(StructType, layout)
	-- Clear existing generated methods with any possible prefix
	for fieldName, fieldDef in pairs(layout) do
		local capitalizedName = Structure.capitalize(fieldName)

		-- Clear exposed prefixes
		StructType[GETTER_PREFIX .. capitalizedName] = nil
		StructType[SETTER_PREFIX .. capitalizedName] = nil
		StructType[GETTER_PREFIX .. capitalizedName .. "Ptr"] = nil
		StructType[SETTER_PREFIX .. capitalizedName .. "Ptr"] = nil
		StructType[GETTER_PREFIX .. capitalizedName .. "Obj"] = nil

		-- And "hidden" prefixes
		StructType[HIDE_PREFIX .. GETTER_PREFIX .. capitalizedName] = nil
		StructType[HIDE_PREFIX .. SETTER_PREFIX .. capitalizedName] = nil
		StructType[HIDE_PREFIX .. GETTER_PREFIX .. capitalizedName .. "Ptr"] = nil
		StructType[HIDE_PREFIX .. SETTER_PREFIX .. capitalizedName .. "Ptr"] = nil
		StructType[HIDE_PREFIX .. GETTER_PREFIX .. capitalizedName .. "Obj"] = nil
	end

	-- Generate getter and setter methods for each field
	for fieldName, fieldDef in pairs(layout) do
		local capitalizedName = Structure.capitalize(fieldName)
		local handler = TYPE_HANDLERS[fieldDef.type]

		if fieldDef.type == "pointer" then
			generatePointerGetters(StructType, fieldName, fieldDef, handler, capitalizedName)
			generatePointerSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
		elseif fieldDef.type == "struct" then
			generateStructGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
			-- No setter for struct fields - modify individual fields instead
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
-- Don't use "Get..." to avoid conflicting with defined types
local function addStaticMethods(StructType, name, layout)
	-- Constructor
	function StructType.new(address)
		local instance = setmetatable({}, StructType)
		instance._address = address

		-- If a source table is provided, copy its entries
		if StructType then
			for k, v in pairs(StructType) do
				instance[k] = v
			end
		end

		return instance
	end

	-- Calculate structure size
	-- TODO move to var
	function StructType.StructSize()
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
				elseif field.type == "struct" and field.structType then
					-- Get size from the nested struct
					local structType = field.structType
					if type(structType) == "string" then
						structType = _structures[structType]
					end
					if structType and structType.StructSize then
						local structSize = structType.StructSize()
						if structSize then
							maxSize = structSize
						else
							return nil  -- Cannot determine nested struct size
						end
					else
						return nil  -- Struct type not found or has no size
					end
				else
					return nil  -- Cannot determine size
				end
			end
		end

		return maxOffset + maxSize
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

	local structSize = stride or structType.StructSize()
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

-- Defines a Set<FieldName> function that
-- wraps a Get<FieldName>:Set() fn.
-- FieldName must be a struct type that defines
-- a Set function
-- fieldName does not need to be captialized
function Structure.makeSetterWrapper(struct, fieldName)
	local capitailized = Structure.capitalize(fieldName)
	local funcName = "Set" .. capitailized
	local getterName = "Get" .. capitailized

	struct[funcName] = function(self, ...)
		self[getterName](self):Set(...)
	end
end

function Structure.makeStructSetterWrapper(struct, fieldName)
	local capitailized = Structure.capitalize(fieldName)
	local funcName = "Set" .. capitailized .. "Obj"
	local getterName = "Get" .. capitailized .. "Obj"

	struct[funcName] = function(self, ...)
		self[getterName](self):Set(...)
	end
end

return Structure
