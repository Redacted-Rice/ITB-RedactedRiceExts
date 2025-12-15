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
	  - getXxx() / setXxx() - read/write the value
	- pointer: 32 bit pointer
	  - getXxxPtr() / setXxxPtr() - read/write the raw pointer value
	  - getXxx() - get wrapped object at pointed address (if pointedType specified)
	- struct: Inline struct (not a pointer)
	  - getXxx() - get wrapped struct at this field's address
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

StructManager = {}

-- Constants
StructManager.GETTER_PREFIX = "get"
StructManager.SETTER_PREFIX = "set"
StructManager.HIDE_PREFIX = "_"

-- Module state set by init
StructManager._dll = nil
StructManager._structures = nil

-- Load subcomponents
local path = GetParentPath(...)

StructManager.TYPE_HANDLERS = require(path.."structmanager/type_handlers")

StructManager._validation = require(path.."structmanager/validation")
StructManager._methodGeneration = require(path.."structmanager/method_generation")
StructManager._structureCreation = require(path.."structmanager/structure_creation")

-- Initialize the structure system with a DLL instance and structs table
-- dll: The memhack DLL instance
-- structs: The table where structures will be registered (memhack.structs). Optional
-- returns the structs table (passed one or internally generated one)
function StructManager.init(dll, structs)
	StructManager._dll = dll
	StructManager._structures = structs or {}
	return StructManager._structures
end

-- Capitalize first letter of a string
function StructManager.capitalize(str)
	return str:sub(1, 1):upper() .. str:sub(2)
end

-- Helper functions for creating method names
-- These ensure consistent naming across the codebase

-- Create a standard getter name: "getXxx" or "_getXxx"
function StructManager.makeStdGetterName(fieldName, hideGetter)
	local capitalized = StructManager.capitalize(fieldName)
	local prefix = hideGetter and StructManager.HIDE_PREFIX .. StructManager.GETTER_PREFIX or StructManager.GETTER_PREFIX
	return prefix .. capitalized
end

-- Create a standard setter name: "setXxx" or "_setXxx"
function StructManager.makeStdSetterName(fieldName, hideSetter)
	local capitalized = StructManager.capitalize(fieldName)
	local prefix = hideSetter and StructManager.HIDE_PREFIX .. StructManager.SETTER_PREFIX or StructManager.SETTER_PREFIX
	return prefix .. capitalized
end

-- Create a pointer getter name: "getXxxPtr" or "_getXxxPtr"
function StructManager.makeStdPtrGetterName(fieldName, hideGetter)
	return StructManager.makeStdGetterName(fieldName, hideGetter) .. "Ptr"
end

-- Create a pointer setter name: "setXxxPtr" or "_setXxxPtr"
function StructManager.makeStdPtrSetterName(fieldName, hideSetter)
	return StructManager.makeStdSetterName(fieldName, hideSetter) .. "Ptr"
end

-- Create the name for a setter for an object: "get"
function StructManager.makeStdSelfGetterName()
	return StructManager.GETTER_PREFIX
end

-- Create the name for a setter for an object: "set"
function StructManager.makeStdSelfSetterName()
	return StructManager.SETTER_PREFIX
end

-- Define a new structure type
function StructManager.define(name, layout)
	if not StructManager._dll then
		error("Structure system not initialized. Call StructManager.init() first (should be done by memhack.init())")
	end

	StructManager._validation.validateStructureDefinition(name, layout)

	local StructType = StructManager._structureCreation.createStructureType(name, layout)
	StructManager._methodGeneration.buildStructureMethods(StructType, layout)
	StructManager._structureCreation.addInstanceMethods(StructType, layout)
	StructManager._structureCreation.addStaticMethods(StructType, name, layout)
	StructManager._structureCreation.registerStructure(name, StructType)

	return StructType
end

-- Extend an existing structure with additional fields
function StructManager.extend(name, additionalFields)
	if not StructManager._dll then
		error("Structure system not initialized. Call StructManager.init() first (should be done by memhack.init())")
	end

	local existingStruct = StructManager._structures[name]
	if not existingStruct then
		error(string.format("Cannot extend unknown structure: %s", name))
	end

	local layout = existingStruct._layout
	validation.validateAndMergeExtensionFields(name, layout, additionalFields)
	StructManager._methodGeneration.buildStructureMethods(existingStruct, layout)

	return existingStruct
end

-- Helper function to create an array of structures
function StructManager.array(structType, baseAddress, count, stride)
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

-- Defines a <STD_SETTER> function that
-- wraps a <STD_GETTER>:<STD_SELF_SETTER>(...) fn.
-- FieldName must be a struct type that defines a set function
-- fieldName does not need to be capitalized
function StructManager.makeSetterWrapper(struct, fieldName)
	local funcName = StructManager.makeStdSetterName(fieldName)
	local getterName = StructManager.makeStdGetterName(fieldName)

	struct[funcName] = function(self, ...)
	    local obj = self[getterName](self)
		return obj[StructManager.makeStdSelfSetterName()](obj, ...)
	end
end

return StructManager
