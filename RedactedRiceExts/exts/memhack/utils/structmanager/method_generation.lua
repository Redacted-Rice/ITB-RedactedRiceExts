-- Method generation functions for structure types

local methodGeneration = {}

local GETTER_PREFIX = StructManager.GETTER_PREFIX
local SETTER_PREFIX = StructManager.SETTER_PREFIX
local HIDE_PREFIX = StructManager.HIDE_PREFIX
local TYPE_HANDLERS = StructManager.TYPE_HANDLERS

-- Helper: Resolve sub type and read value
local function resolveSubType(subType, ptrValue, fieldDef)
	if type(subType) ~= "string" then
		error(string.format("Unknown structure type: %s", fieldDef.subType))
	end

	-- Check for unsupported types
	if subType == "pointer" or subType == "struct" then
		error(string.format("structure type '%s' not supported", subType))
	end

	-- Types that need size
	if subType == "string" or subType == "bytearray" then
		if fieldDef.pointedSize == nil then
			error(string.format("subType '%s' requires pointedSize", subType))
		end
		local result = TYPE_HANDLERS[subType].read(ptrValue, fieldDef.pointedSize)
		return result
	end

	-- Native types like int, bool, etc
	if TYPE_HANDLERS[subType] ~= nil then
		local result = TYPE_HANDLERS[subType].read(ptrValue)
		return result
	end

	-- Defined struct
	local structType = StructManager._structures[subType]
	if not structType then
		error(string.format("Unknown structure type: %s", fieldDef.subType))
	end
	-- validate returned type
	local result = structType.new(ptrValue, true)
	return result
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
		local result = handler.read(address)
		return result
	end

	-- Typed wrapper getter (getXxx or _getXxx) if subType specified
	if fieldDef.subType then
		local wrapperGetterName = StructManager.makeStdGetterName(fieldName, fieldDef.hideGetter)
		StructType[wrapperGetterName] = function(self)
			local address = self._address + fieldDef.offset
			local ptrValue = handler.read(address)

			-- Return nil if pointer is null
			if ptrValue == 0 or ptrValue == nil then
				return nil
			end

			local result = resolveSubType(fieldDef.subType, ptrValue, fieldDef)
			return result
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

-- TODO: Maybe check if there is a length function defined and if so use that instead
-- of max?

function methodGeneration.generateStandardGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local getterName = StructManager.makeStdGetterName(fieldName, fieldDef.hideGetter)

	StructType[getterName] = function(self)
		local address = self._address + fieldDef.offset

		if fieldDef.type == "bytearray" then
			local result = handler.read(address, fieldDef.length)
			return result
		elseif fieldDef.type == "string" and fieldDef.maxLength then
			local result = handler.read(address, fieldDef.maxLength)
			return result
		else
			local result = handler.read(address)
			return result
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
local function resolveStructType(subType)
	if type(subType) == "string" then
		local resolved = StructManager._structures[subType]
		if not resolved then
			error(string.format("Unknown structure type: %s", subType))
		end
		return resolved
	end
	return subType
end

function methodGeneration.generateStructGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local getterName = StructManager.makeStdGetterName(fieldName, fieldDef.hideGetter)

	StructType[getterName] = function(self)
		local address = self._address + fieldDef.offset
		local structType = resolveStructType(fieldDef.subType)
		-- validate returned type
		local result = structType.new(address, true)
		return result
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

-- Create a convenience wrapper method on a struct to get parent by type name
-- Creates a function named getParent<StructTypeName> that calls getParentOfType
function methodGeneration.makeParentGetterWrapper(struct, parentStructTypeName)
	local methodName = "getParent" .. parentStructTypeName

	struct[methodName] = function(self)
		return StructManager.getParentOfType(self, parentStructTypeName)
	end
end

-- Defines a <newGetterName> function that wraps a <STD_GETTER>:<STD_SELF_GETTER>(...) fn.
-- FieldName must be a struct type that defines a set function
-- fieldName does not need to be capitalized
-- newGetterName: The name of the getter to add to the struct
-- selfGetterName: The name of getter to call on the retrieved object or nil for <STD_SELF_GETTER>
function methodGeneration.makeStructGetWrapper(struct, fieldName, newGetterName, selfGetterName)
	local getterName = StructManager.makeStdGetterName(fieldName)
	selfGetterName = selfGetterName or StructManager.makeStdSelfGetterName()

	struct[newGetterName] = function(self)
		local obj = self[getterName](self)
		local result = obj[selfGetterName](obj)
		return result
	end
end

-- Defines a <newSetterName> function that wraps a <STD_GETTER>:<STD_SELF_SETTER>(...) fn.
-- FieldName must be a struct type that defines a set function
-- fieldName does not need to be capitalized
-- newSetterName: The name of the getter to add to the struct or nil for STD_SETTER
-- selfSetterName: The name of setter to call on the retrieved object or nil for <STD_SELF_SETTER>
function methodGeneration.makeStructSetWrapper(struct, fieldName, newSetterName, selfSetterName)
	local newSetterName = newSetterName or StructManager.makeStdSetterName(fieldName)
	local getterName = StructManager.makeStdGetterName(fieldName)
	selfSetterName = selfSetterName or StructManager.makeStdSelfSetterName()

	struct[newSetterName] = function(self, ...)
		local obj = self[getterName](self)
		local result = obj[selfSetterName](obj, ...)
		return result
	end
end

-- Wrap an existing setter to fire the hook when the value is changed
-- using that setter
-- struct - self object
-- field - fieldName used to generate setters/getters not passed and for the fire hook structure
-- fireFn - broadcast hook/fire hook function to call on change
-- selfSetterName - name of setter to wrap. If nil uses standard setter name for <field>
-- selfGetterName - name of Getter to use to get initial state. If nil uses standard getter name for <field>
function methodGeneration.wrapSetterToFireOnValueChange(struct, field, fireFn, setterName, getterName)
	if not setterName then
		setterName = StructManager.makeStdSetterName(field)
	end
	local originalSetter = struct[setterName]
	if not originalSetter then
		error(string.format("Setter '%s' not found on struct", setterName))
	end

	local fieldOrGetter = getterName or field

	struct[setterName] = function(self, newVal)
		local prevVal = memhack.stateTracker.captureValue(self, fieldOrGetter)
		originalSetter(self, newVal)
		if newVal ~= prevVal then
			local changes = {}
			changes[field] = {old = prevVal, new = newVal}
			fireFn(self, changes)
		end
	end
end

-- Generates a setter fn that takes struct or table of vals to detect changes and fire hook if any changed
-- fireFn: hook to fire on change
-- fullStateTable: table that defines what consititues the state for this setter -
-- 			i.e. what to check for changes
--			Array like entries (num -> field) will use default getters
--			Map entries (field -> getter) will use the passed getter name instead
-- settersTable: table that defines setters for the values in the state table. Use
--     		default setters table or value for field in table is nil
function methodGeneration.generateStructSetterToFireOnAnyValueChange(fireFn, fullStateTable, settersTable)
	-- if struct, others are not used
	-- Otherwise sets only the vals in the table (nils skipped)
	return function(self, structOrNewVals)
		local newVals = structOrNewVals
		-- Check if it's a memhack struct by presence of isMemhackObj field (all structs have this)
		if type(structOrNewVals) == "table" and structOrNewVals.isMemhackObj then
			newVals = memhack.stateTracker.captureState(structOrNewVals, fullStateTable)
		end
		-- Only check & capture new values
		local currentState = memhack.stateTracker.captureState(self, fullStateTable, newVals)

		local anyChanged = false
		local changedNew = {}
		for field, newVal in pairs(newVals) do
			if newVal ~= currentState[field] then
				if settersTable and settersTable[field] then
					settersTable[field](self, newVal)
				else
					local setter = StructManager.makeStdSetterName(field)
					self[setter](self, newVal)
				end
				-- Lua doesn't make any gaurantees about removing while iterating
				-- so instead make a new table for changed new fields
				changedNew[field] = newVal
				anyChanged = true
			else
				-- Remove any non-changed current values
				currentState[field] = nil
			end
		end

		if anyChanged then
			fireFn(self, changedNew, currentState)
		end
	end
end

-- Wraps a getter method to inject parent references into the returned object
-- This allows child structs to maintain references to their parents by type
--
-- struct: "self" struct to wrap the fn of
-- getterName: The name of the getter method to wrap 
--
-- The wrapped getter will:
-- 1. Call the original getter to get the child object
-- 2. Copy the parent references from self._parent (if it exists)
-- 3. Add self to the parent map using self._name as the key
-- 4. Inject the parent map into the child as child._parent
function methodGeneration.wrapGetterToPreserveParent(struct, getterName)
	-- Store the original getter
	local originalGetter = struct[getterName]
	if not originalGetter then
		error(string.format("Getter '%s' not found on struct", getterName))
	end

	-- Get the struct type name for keying
	local structTypeName = struct._name
	if not structTypeName then
		error(string.format("Struct type must have _name field for parent preservation"))
	end

	-- Create wrapped version
	struct[getterName] = function(self)
		-- Call original getter to get child object
		local child = originalGetter(self)

		-- Don't inject if child is nil
		if child == nil then
			return nil
		end

		-- Build parent map: copy existing parents from self and add self
		local parentMap = {}
		if self._parent then
			-- Copy existing parent references
			for typeName, parent in pairs(self._parent) do
				parentMap[typeName] = parent
			end
		end
		-- Add self to parent map using struct type name as key
		parentMap[structTypeName] = self

		-- Inject parent map into child
		child._parent = parentMap

		return child
	end
end

return methodGeneration
