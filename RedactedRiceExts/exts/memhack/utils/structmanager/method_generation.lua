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

-- Get prefix for getter/setter based on hide flag
local function getPrefix(hide, basePrefix)
	return hide and HIDE_PREFIX .. basePrefix or basePrefix
end

-- Helper: Clear method names for a field
local function clearFieldMethods(StructType, capitalizedName)
	-- Clear exposed prefixes
	StructType[GETTER_PREFIX .. capitalizedName] = nil
	StructType[SETTER_PREFIX .. capitalizedName] = nil
	StructType[GETTER_PREFIX .. capitalizedName .. "Ptr"] = nil
	StructType[SETTER_PREFIX .. capitalizedName .. "Ptr"] = nil

	-- Clear hidden prefixes
	StructType[HIDE_PREFIX .. GETTER_PREFIX .. capitalizedName] = nil
	StructType[HIDE_PREFIX .. SETTER_PREFIX .. capitalizedName] = nil
	StructType[HIDE_PREFIX .. GETTER_PREFIX .. capitalizedName .. "Ptr"] = nil
	StructType[HIDE_PREFIX .. SETTER_PREFIX .. capitalizedName .. "Ptr"] = nil
end

function methodGeneration.generatePointerGetters(StructType, fieldName, fieldDef, handler, capitalizedName)
	local getterPrefix = getPrefix(fieldDef.hideGetter, GETTER_PREFIX)

	-- Raw pointer getter (getXxxPtr)
	local ptrGetterName = getterPrefix .. capitalizedName .. "Ptr"
	StructType[ptrGetterName] = function(self)
		local address = self._address + fieldDef.offset
		return handler.read(address)
	end

	-- Typed wrapper getter (getXxx) if pointedType specified
	if fieldDef.pointedType then
		local wrapperGetterName = getterPrefix .. capitalizedName
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
	local setterPrefix = getPrefix(fieldDef.hideSetter, SETTER_PREFIX)

	local ptrSetterName = setterPrefix .. capitalizedName .. "Ptr"
	StructType[ptrSetterName] = function(self, value)
		local address = self._address + fieldDef.offset
		handler.write(address, value)
	end
end

function methodGeneration.generateStandardGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local getterPrefix = getPrefix(fieldDef.hideGetter, GETTER_PREFIX)
	local getterName = getterPrefix .. capitalizedName

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
	local setterPrefix = getPrefix(fieldDef.hideSetter, SETTER_PREFIX)
	local setterName = setterPrefix .. capitalizedName

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
	local getterPrefix = getPrefix(fieldDef.hideGetter, GETTER_PREFIX)
	local getterName = getterPrefix .. capitalizedName

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
		local capitalizedName = StructManager.capitalize(fieldName)
		clearFieldMethods(StructType, capitalizedName)
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
