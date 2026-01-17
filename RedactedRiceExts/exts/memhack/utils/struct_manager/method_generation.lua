-- Method generation functions for structure types

local methodGeneration = {}

local GETTER_PREFIX = StructManager.GETTER_PREFIX
local SETTER_PREFIX = StructManager.SETTER_PREFIX
local HIDE_PREFIX = StructManager.HIDE_PREFIX
local TYPE_HANDLERS = StructManager.TYPE_HANDLERS

-- Helper: Resolve sub type and read value
-- Supports table subType format: { type = "string", maxLength = X, lengthFn = fn }
-- For non-string/bytearray types, subType can be a string (struct name or native type)
function methodGeneration:_resolveSubType(subType, ptrValue, fieldDef)
	local actualSubType = subType
	local lengthFn = nil
	local sizeToRead = nil

	if type(subType) == "table" then
		-- Table format for string/bytearray with size/length info
		actualSubType = subType.type
		lengthFn = subType.lengthFn
		sizeToRead = subType.maxLength
	elseif type(subType) == "string" then
		-- String subType is valid for struct names and native types (not string/bytearray)
		actualSubType = subType
	else
		error(string.format("Unknown structure type: %s", tostring(fieldDef.subType)))
	end

	-- Check for unsupported types
	if actualSubType == "pointer" or actualSubType == "struct" then
		error(string.format("structure type '%s' not supported", actualSubType))
	end

	-- Types that need size - must use table format with maxLength
	if actualSubType == "string" or actualSubType == "bytearray" then
		if sizeToRead == nil then
			error(string.format("subType '%s' requires table format with maxLength: { type = '%s', maxLength = <size> }",
				actualSubType, actualSubType))
		end

		-- Use lengthFn if provided, otherwise use sizeToRead
		local actualLength = sizeToRead
		if lengthFn then
			actualLength = lengthFn(self)
			-- Add 1 for null terminator if reading a string
			if actualSubType == "string" then
				actualLength = actualLength + 1
			end
		end

		local result = TYPE_HANDLERS[actualSubType].read(ptrValue, actualLength)
		return result
	end

	-- Native types like int, bool, etc
	if TYPE_HANDLERS[actualSubType] ~= nil then
		local result = TYPE_HANDLERS[actualSubType].read(ptrValue)
		return result
	end

	-- Defined struct
	local structType = StructManager._structures[actualSubType]
	if not structType then
		error(string.format("Unknown structure type: %s", tostring(fieldDef.subType)))
	end
	-- validate returned type
	local result = structType.new(ptrValue, true)
	return result
end

-- Helper: Clear method names for a field
function methodGeneration._clearFieldMethods(StructType, fieldName)
	-- Clear exposed prefixes
	StructType[StructManager:makeStdGetterName(fieldName, false)] = nil
	StructType[StructManager:makeStdSetterName(fieldName, false)] = nil
	StructType[StructManager:makeStdPtrGetterName(fieldName, false)] = nil
	StructType[StructManager:makeStdPtrSetterName(fieldName, false)] = nil

	-- Clear hidden prefixes
	StructType[StructManager:makeStdGetterName(fieldName, true)] = nil
	StructType[StructManager:makeStdSetterName(fieldName, true)] = nil
	StructType[StructManager:makeStdPtrGetterName(fieldName, true)] = nil
	StructType[StructManager:makeStdPtrSetterName(fieldName, true)] = nil
end

function methodGeneration.generatePointerGetters(StructType, fieldName, fieldDef, handler, capitalizedName)
	-- Raw pointer getter (getXxxPtr or _getXxxPtr)
	local ptrGetterName = StructManager:makeStdPtrGetterName(fieldName, fieldDef.hideGetter)
	StructType[ptrGetterName] = function(self)
		local address = self._address + fieldDef.offset
		local result = handler.read(address)
		return result
	end

	-- Typed wrapper getter (getXxx or _getXxx) if subType specified
	if fieldDef.subType then
		local wrapperGetterName = StructManager:makeStdGetterName(fieldName, fieldDef.hideGetter)
		StructType[wrapperGetterName] = function(self)
			local address = self._address + fieldDef.offset
			local ptrValue = handler.read(address)

			-- Return nil if pointer is null
			if ptrValue == 0 or ptrValue == nil then
				return nil
			end

			-- Pass self (parent struct) for lengthFn support
			local result = methodGeneration._resolveSubType(self, fieldDef.subType, ptrValue, fieldDef)
			return result
		end
	end
end

function methodGeneration.generatePointerSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local ptrSetterName = StructManager:makeStdPtrSetterName(fieldName, fieldDef.hideSetter)
	StructType[ptrSetterName] = function(self, value)
		local address = self._address + fieldDef.offset
		handler.write(address, value)
	end
end

function methodGeneration.generateStandardGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local getterName = StructManager:makeStdGetterName(fieldName, fieldDef.hideGetter)

	StructType[getterName] = function(self)
		local address = self._address + fieldDef.offset

		if fieldDef.type == "bytearray" then
			local length = fieldDef.length
			-- Use lengthFn if provided
			if fieldDef.lengthFn then
				length = fieldDef.lengthFn(self)
			end
			local result = handler.read(address, length)
			return result
		elseif fieldDef.type == "string" and fieldDef.maxLength then
			local maxLen = fieldDef.maxLength
			-- Use lengthFn if provided (add 1 for null terminator)
			if fieldDef.lengthFn then
				maxLen = fieldDef.lengthFn(self) + 1
			end
			local result = handler.read(address, maxLen)
			return result
		else
			local result = handler.read(address)
			return result
		end
	end
end

function methodGeneration.generateStandardSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
	local setterName = StructManager:makeStdSetterName(fieldName, fieldDef.hideSetter)

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
function methodGeneration._resolveStructType(subType)
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
	local getterName = StructManager:makeStdGetterName(fieldName, fieldDef.hideGetter)

	StructType[getterName] = function(self)
		local address = self._address + fieldDef.offset
		local structType = methodGeneration._resolveStructType(fieldDef.subType)
		-- validate returned type
		local result = structType.new(address, true)
		return result
	end
end

-- Build all structure methods from a layout
function methodGeneration.buildStructureMethods(StructType, layout)
	-- Clear existing generated methods
	for fieldName, fieldDef in pairs(layout) do
		methodGeneration._clearFieldMethods(StructType, fieldName)
	end

	-- Generate getter and setter methods for each field
	for fieldName, fieldDef in pairs(layout) do
		local capitalizedName = StructManager:capitalize(fieldName)
		local handler = TYPE_HANDLERS[fieldDef.type]

		if fieldDef.type == "pointer" then
			methodGeneration.generatePointerGetters(StructType, fieldName, fieldDef, handler, capitalizedName)
			-- Only generate setter if noSetter is not true
			if not fieldDef.noSetter then
				methodGeneration.generatePointerSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
			end
		elseif fieldDef.type == "struct" then
			methodGeneration.generateStructGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
			-- No setter for struct fields - modify individual fields instead
		else
			methodGeneration.generateStandardGetter(StructType, fieldName, fieldDef, handler, capitalizedName)
			-- Only generate setter if noSetter is not true
			if not fieldDef.noSetter then
				methodGeneration.generateStandardSetter(StructType, fieldName, fieldDef, handler, capitalizedName)
			end
		end
	end
end

-- Create a convenience wrapper method on a struct to get parent by type name
-- Creates a function named getParent<StructTypeName> that calls getParentOfType
function methodGeneration.makeParentGetterWrapper(struct, parentStructTypeName)
	local methodName = "getParent" .. parentStructTypeName

	struct[methodName] = function(self)
		return StructManager:getParentOfType(self, parentStructTypeName)
	end
end

-- Defines a <newGetterName> function that wraps a <STD_GETTER>:<STD_SELF_GETTER>(...) fn.
-- FieldName must be a struct type that defines a set function
-- fieldName does not need to be capitalized
-- newGetterName: The name of the getter to add to the struct
-- selfGetterName: The name of getter to call on the retrieved object or nil for <STD_SELF_GETTER>
function methodGeneration.makeStructGetWrapper(struct, fieldName, newGetterName, selfGetterName)
	local getterName = StructManager:makeStdGetterName(fieldName)
	selfGetterName = selfGetterName or StructManager:makeStdSelfGetterName()

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
	local newSetterName = newSetterName or StructManager:makeStdSetterName(fieldName)
	local getterName = StructManager:makeStdGetterName(fieldName)
	selfSetterName = selfSetterName or StructManager:makeStdSelfSetterName()

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
-- hooksObj - the hooks object (e.g., memhack.hooks) that contains the fire function
-- fireFnName - name of the fire function on hooksObj (e.g., "firePilotChangedHooks")
-- selfSetterName - name of setter to wrap. If nil uses standard setter name for <field>
-- selfGetterName - name of Getter to use to get initial state. If nil uses standard getter name for <field>
function methodGeneration.wrapSetterToFireOnValueChange(struct, field, hooksObj, fireFnName, setterName, getterName)
	if not setterName then
		setterName = StructManager:makeStdSetterName(field)
	end
	local originalSetter = struct[setterName]
	if not originalSetter then
		error(string.format("Setter '%s' not found on struct", setterName))
	end

	local fieldOrGetter = getterName or field

	-- Preserve original as _noFire version so we can use it internally like for
	-- a set all fields setter without extra triggers of the hook. E.g. in
	-- generateStructSetterToFireOnAnyValueChange generate functions
	-- Make it private by prefixing with _
	local noFireName = "_" .. setterName .. "_noFire"
	struct[noFireName] = originalSetter

	struct[setterName] = function(self, newVal)
		local prevVal = memhack.stateTracker:captureValue(self, fieldOrGetter)
		originalSetter(self, newVal)
		if newVal ~= prevVal then
			local changes = {}
			changes[field] = {old = prevVal, new = newVal}
			-- Dynamic lookup of fire function. We do this instead of passing a function reference because we
			-- may wrap the function in a re-entrant wrapper and we don't want a stale reference
			hooksObj[fireFnName](self, changes)
		end
	end
end

-- Generates a setter fn that takes struct or table of vals to detect changes and fire hook if any changed
-- hooksObj: the hooks object (e.g., memhack.hooks) that contains the fire function
-- fireFnName: name of the fire function on hooksObj (e.g., "firePilotLvlUpSkillChangedHooks")
-- fullStateTable: table that defines what consititues the state for this setter -
-- 			i.e. what to check for changes
--			Array like entries (num -> field) will use default getters
--			Map entries (field -> getter) will use the passed getter name instead
-- settersTable: table that defines setters for the values in the state table. Use
--     		default setters table or value for field in table is nil
function methodGeneration.generateStructSetterToFireOnAnyValueChange(hooksObj, fireFnName, fullStateTable, settersTable)
	-- if struct, others are not used
	-- Otherwise sets only the vals in the table (nils skipped)
	return function(self, structOrNewVals)
		local newVals = structOrNewVals
		-- Check if it's a memhack struct by presence of isMemhackObj field (all structs have this)
		if type(structOrNewVals) == "table" and structOrNewVals.isMemhackObj then
			newVals = memhack.stateTracker:captureState(structOrNewVals, fullStateTable)
		end
		-- Only check & capture new values
		local currentState = memhack.stateTracker:captureState(self, fullStateTable, newVals)

		local anyChanged = false
		local changes = {}
		for field, newVal in pairs(newVals) do
			if newVal ~= currentState[field] then
				if settersTable and settersTable[field] then
					settersTable[field](self, newVal)
				else
					local setter = StructManager:makeStdSetterName(field)
					-- Use private _noFire version if available to avoid double firing hooks
					local noFireSetter = "_" .. setter .. "_noFire"
					if self[noFireSetter] then
						self[noFireSetter](self, newVal)
					else
						self[setter](self, newVal)
					end
				end
				-- Build changes table with old and new values
				changes[field] = {old = currentState[field], new = newVal}
				anyChanged = true
			end
		end

		if anyChanged then
			-- Dynamic lookup of fire function
			hooksObj[fireFnName](self, changes)
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
