-- Method generation functions for structure types

local methodGeneration = {}

local GETTER_PREFIX = StructManager.GETTER_PREFIX
local SETTER_PREFIX = StructManager.SETTER_PREFIX
local HIDE_PREFIX = StructManager.HIDE_PREFIX
local TYPE_HANDLERS = StructManager.TYPE_HANDLERS

-- Helper: Resolve pointed type and read value
local function resolvePointedType(pointedType, ptrValue, fieldDef)
	if type(pointedType) ~= "string" then
		error(string.format("Unknown structure type: %s", fieldDef.pointedType))
	end

	-- Check for unsupported types
	if pointedType == "pointer" or pointedType == "struct" then
		error(string.format("structure type '%s' not supported", pointedType))
	end

	-- Types that need size
	if pointedType == "string" or pointedType == "bytearray" then
		if fieldDef.pointedSize == nil then
			error(string.format("pointedType '%s' requires pointedSize", pointedType))
		end
		return TYPE_HANDLERS[pointedType].read(ptrValue, fieldDef.pointedSize)
	end

	-- Native types like int, bool, etc
	if TYPE_HANDLERS[pointedType] ~= nil then
		return TYPE_HANDLERS[pointedType].read(ptrValue)
	end

	-- Defined struct
	local structType = StructManager._structures[pointedType]
	if not structType then
		error(string.format("Unknown structure type: %s", fieldDef.pointedType))
	end
	return structType.new(ptrValue)
end

-- Helper: Clear method names for a field
local function clearFieldMethods(StructType, fieldName)
	-- Clear exposed prefixes
	StructType[StructManager.makeStdGetterName(fieldName, false)] = nil
	StructType[StructManager.makeStdSetterName(fieldName, false)] = nil
	StructType[StructManager.makeStdPtrGetterName(fieldName, false)] = nil
	StructType[StructManager.makeStdPtrSetterName(fieldName, false)] = nil

	-- Clear hidden prefixes
	StructType[StructManager.makeStdGetterName(fieldName, true)] = nil
	StructType[StructManager.makeStdSetterName(fieldName, true)] = nil
	StructType[StructManager.makeStdPtrGetterName(fieldName, true)] = nil
	StructType[StructManager.makeStdPtrSetterName(fieldName, true)] = nil
end

function methodGeneration.generatePointerGetters(StructType, fieldName, fieldDef, handler, capitalizedName)
	-- Raw pointer getter (getXxxPtr or _getXxxPtr)
	local ptrGetterName = StructManager.makeStdPtrGetterName(fieldName, fieldDef.hideGetter)
	StructType[ptrGetterName] = function(self)
		local address = self._address + fieldDef.offset
		return handler.read(address)
	end

	-- Typed wrapper getter (getXxx or _getXxx) if pointedType specified
	if fieldDef.pointedType then
		local wrapperGetterName = StructManager.makeStdGetterName(fieldName, fieldDef.hideGetter)
		StructType[wrapperGetterName] = function(self)
			local address = self._address + fieldDef.offset
			local ptrValue = handler.read(address)

			-- Return nil if pointer is null
			if ptrValue == 0 or ptrValue == nil then
				return nil
			end

			return resolvePointedType(fieldDef.pointedType, ptrValue, fieldDef)
		end
	end
end

function methodGeneration.generatePointerSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local ptrSetterName = StructManager.makeStdPtrSetterName(fieldName, fieldDef.hideSetter)
	StructType[ptrSetterName] = function(self, value)
		local address = self._address + fieldDef.offset
		handler.write(address, value)
	end
end

function methodGeneration.generateStandardGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local getterName = StructManager.makeStdGetterName(fieldName, fieldDef.hideGetter)

	StructType[getterName] = function(self)
		local address = self._address + fieldDef.offset

		if fieldDef.type == "bytearray" then
			return handler.read(address, fieldDef.length)
		elseif fieldDef.type == "string" and fieldDef.maxLength then
			return handler.read(address, fieldDef.maxLength)
		else
			return handler.read(address)
		end
	end
end

function methodGeneration.generateStandardSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local setterName = StructManager.makeStdSetterName(fieldName, fieldDef.hideSetter)

	StructType[setterName] = function(self, value)
		local address = self._address + fieldDef.offset

		if fieldDef.type == "bytearray" then
			handler.write(address, value, fieldDef.length)
		elseif fieldDef.type == "string" and fieldDef.maxLength then
			handler.write(address, value, fieldDef.maxLength)
		else
			handler.write(address, value)
		end
	end
end

-- Helper: Resolve struct type from string or return as-is
local function resolveStructType(structType)
	if type(structType) == "string" then
		local resolved = StructManager._structures[structType]
		if not resolved then
			error(string.format("Unknown structure type: %s", structType))
		end
		return resolved
	end
	return structType
end

function methodGeneration.generateStructGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local getterName = StructManager.makeStdGetterName(fieldName, fieldDef.hideGetter)

	StructType[getterName] = function(self)
		local address = self._address + fieldDef.offset
		local structType = resolveStructType(fieldDef.structType)
		return structType.new(address)
	end
end

-- Build all structure methods from a layout
function methodGeneration.buildStructureMethods(StructType, layout)
	-- Clear existing generated methods
	for fieldName, fieldDef in pairs(layout) do
		clearFieldMethods(StructType, fieldName)
	end

	-- Generate getter and setter methods for each field
	for fieldName, fieldDef in pairs(layout) do
		local capitalizedName = StructManager.capitalize(fieldName)
		local handler = TYPE_HANDLERS[fieldDef.type]

		if fieldDef.type == "pointer" then
			methodGeneration.generatePointerGetters(StructType, fieldName, fieldDef, handler, capitalizedName)
			methodGeneration.generatePointerSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
		elseif fieldDef.type == "struct" then
			methodGeneration.generateStructGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
			-- No setter for struct fields - modify individual fields instead
		else
			methodGeneration.generateStandardGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
			methodGeneration.generateStandardSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
		end
	end
end

return methodGeneration
