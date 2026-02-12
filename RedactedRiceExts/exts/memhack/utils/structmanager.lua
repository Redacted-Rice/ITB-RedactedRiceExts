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
	  - getXxx() - get wrapped object at pointed address (if subType specified)
	- struct: Inline struct (not a pointer)
	  - getXxx() - get wrapped struct at this field's address
	  - No setter - modify individual fields on the returned object instead

	Supported Types:
	- int, bool, double, float, byte: Basic types, no additional params
	- pointer: 32 bit pointer
	  - optional: subType for automatic wrapping of the pointed type
	- struct: Inline struct (not a pointer)
	  - required: subType
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

	Structure Verification:
	Structures can optionally include verification to validate memory addresses.
	Pass a third parameter to define():

	- define(name, layout, vtableAddress)
	  Verifies that a vtable pointer at offset 0 matches the expected address.
	  Automatically adds a hidden _vtable field at offset 0
	  See Pilot for an example

	- define(name, layout, validationFunction)
	  Custom verification function. Must return (success, errorMessage).
	  See ItBString for an example

	All verification automatically checks:
	1. Address is not nil or 0
	2. Memory at address for full struct size is readable
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
function StructManager:init(dll, structs)
	self._dll = dll
	self._structures = structs or {}
	return self._structures
end

-- Capitalize first letter of a string
function StructManager:capitalize(str)
	return str:sub(1, 1):upper() .. str:sub(2)
end

-- Helper functions for creating method names
-- These ensure consistent naming across the codebase

-- Create a standard getter name: "getXxx" or "_getXxx"
function StructManager:makeStdGetterName(fieldName, hideGetter)
	local capitalized = self:capitalize(fieldName)
	local prefix = hideGetter and self.HIDE_PREFIX .. self.GETTER_PREFIX or self.GETTER_PREFIX
	return prefix .. capitalized
end

-- Create a standard setter name: "setXxx" or "_setXxx"
function StructManager:makeStdSetterName(fieldName, hideSetter)
	local capitalized = self:capitalize(fieldName)
	local prefix = hideSetter and self.HIDE_PREFIX .. self.SETTER_PREFIX or self.SETTER_PREFIX
	return prefix .. capitalized
end

-- Create a pointer getter name: "getXxxPtr" or "_getXxxPtr"
function StructManager:makeStdPtrGetterName(fieldName, hideGetter)
	return self:makeStdGetterName(fieldName, hideGetter) .. "Ptr"
end

-- Create a pointer setter name: "setXxxPtr" or "_setXxxPtr"
function StructManager:makeStdPtrSetterName(fieldName, hideSetter)
	return self:makeStdSetterName(fieldName, hideSetter) .. "Ptr"
end

-- Create the name for a setter for an object: "get"
function StructManager:makeStdSelfGetterName()
	return self.GETTER_PREFIX
end

-- Create the name for a setter for an object: "set"
function StructManager:makeStdSelfSetterName()
	return self.SETTER_PREFIX
end

-- Define a new structure type
-- validateArg: optional vtable address (number) or validation function (function)
function StructManager:define(name, layout, validateArg)
	if not self._dll then
		error("Structure system not initialized. Call StructManager.init() first (should be done by memhack.init())")
		return nil
	end

	-- Store the validation info for later use
	local vtableAddr = nil
	local validateFn = nil

	if validateArg ~= nil then
		if type(validateArg) == "number" then
			-- VTable validation
			vtableAddr = validateArg + self._dll.process.getExeBase()
			layout.vtable = { offset = 0, type = "int", hideSetter = true }
		elseif type(validateArg) == "function" then
			-- Custom validation function
			validateFn = validateArg
		else
			error(string.format("Third parameter to define() must be a number (vtable) or function (validator), got %s", type(validateArg)))
			return nil
		end
	end

	if not self._validation.validateStructureDefinition(name, layout) then
		return nil
	end

	local StructType = self._structureCreation.createStructureType(name, layout)
	self._methodGeneration.buildStructureMethods(StructType, layout)
	self._structureCreation.addInstanceMethods(StructType, layout)
	self._structureCreation.addStaticMethods(StructType, name, layout, vtableAddr, validateFn)
	self._structureCreation.registerStructure(name, StructType)

	return StructType
end

-- Extend an existing structure with additional fields
function StructManager:extend(name, additionalFields)
	if not self._dll then
		error("Structure system not initialized. Call StructManager.init() first (should be done by memhack.init())")
	end

	local existingStruct = self._structures[name]
	if not existingStruct then
		error(string.format("Cannot extend unknown structure: %s", name))
		return nil
	end

	local layout = existingStruct._layout
	if not self._validation.validateAndMergeExtensionFields(name, layout, additionalFields) then
		return nil
	end
	self._methodGeneration.buildStructureMethods(existingStruct, layout)

	return existingStruct
end

-- Helper function to create an array of structures
function StructManager:array(structType, baseAddress, count, stride)
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

-- Helper to get parent of specific type from _parent map
-- structTypeName: The struct type name to look up (e.g., "Pilot", "PilotLvlUpSkillsArray")
-- Returns the parent of that type, or nil if not found
function StructManager:getParentOfType(struct, structTypeName)
	if not struct._parent then
		return nil
	end

	return struct._parent[structTypeName]
end

return StructManager
