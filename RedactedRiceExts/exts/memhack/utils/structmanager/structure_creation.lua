-- Structure creation and public API functions

local structureCreation = {}

local TYPE_HANDLERS = StructManager.TYPE_HANDLERS

-- Create base structure metatable with layout
function structureCreation.createStructureType(name, layout)
	local StructType = {}
	StructType.__index = StructType
	StructType._layout = layout
	StructType._name = name
	return StructType
end

-- Add instance methods to structure type
function structureCreation.addInstanceMethods(StructType, layout)
	-- Get relative field offset
	function StructType:_getFieldOffset(fieldName)
		local field = layout[fieldName]
		if not field then
			error(string.format("Unknown field: %s", fieldName))
		end
		return field.offset
	end

	-- Get absolute field address
	function StructType:_getFieldAddress(fieldName)
		local field = layout[fieldName]
		if not field then
			error(string.format("Unknown field: %s", fieldName))
		end
		return self._address + field.offset
	end
end

-- Helper: Calculate size for a single field
local function calculateFieldSize(field)
	local handler = TYPE_HANDLERS[field.type]

	if handler.size then
		return handler.size
	elseif field.length then
		return field.length
	elseif field.type == "struct" and field.structType then
		-- Get size from the nested struct
		local structType = field.structType
		if type(structType) == "string" then
			structType = StructManager._structures[structType]
		end
		if structType and structType.StructSize then
			local structSize = structType.StructSize()
			if structSize then
				return structSize
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

-- Helper: Find the field with the maximum offset
local function findMaxOffsetField(layout)
	local maxOffset = 0
	local maxField = nil

	for _, field in pairs(layout) do
		if field.offset > maxOffset then
			maxOffset = field.offset
			maxField = field
		end
	end

	return maxOffset, maxField
end

-- Add static methods to structure type
-- Don't use "get..." to avoid conflicting with defined types
function structureCreation.addStaticMethods(StructType, name, layout)
	-- Constructor
	function StructType.new(address)
		local instance = setmetatable({}, StructType)
		instance.isMemhackObj = true
		instance._address = address
		instance.getAddress = function(self)
			return self._address
		end

		-- If a source table is provided, copy its entries
		if StructType then
			for k, v in pairs(StructType) do
				instance[k] = v
			end
		end

		return instance
	end

	-- Calculate structure size
	function StructType._calcStructSize()
		local maxOffset, maxField = findMaxOffsetField(layout)
		if not maxField then
			return 0
		end

		local maxSize = calculateFieldSize(maxField)
		if not maxSize then
			return nil  -- Cannot determine size
		end

		return maxOffset + maxSize
	end

	-- Generate debug string by calling get on each field
	function StructType:_toDebugString()
		local lines = {}
		table.insert(lines, string.format("%s @ 0x%X", self._name, self._address))

		-- TODO: Can I make this same order as defined?
		-- If not, maybe alphabetical?
		for fieldName, fieldDef in pairs(self._layout) do
			local val = nil
			local valType = fieldDef.type
			if fieldDef.hideGetter then
				val = "<no safe getter>"
			else
				local getterName = StructManager.makeStdGetterName(fieldName, false)
				local ptrGetterName = StructManager.makeStdPtrGetterName(fieldName, false)

				-- Try to call the appropriate getter based on field type
				-- pcall is lua's try/catch equivalent - this protects against
				-- errors in the getters
				local success = pcall(function()
					local customToString = self["toString"]
					if customToString then
						val = customToString(self)
					elseif valType == "pointer" then
						val = self[ptrGetterName](self)
						if fieldDef.pointedType then
							local valObj = self[getterName](self)
							val = objGetter(self) .. "(" .. val .. ")"
						end
					else
						val = self[getterName](self)
					end
				end)

				if not success or val == nil then
					val = "<error reading>"
				end
			end
			if valType == "struct" then
				valType = valType .. " - " .. fieldDef.structType
			elseif valType == "pointer" and fieldDef.pointedType ~= nil then
				valType = valType .. " - " .. fieldDef.pointedType
			end
			table.insert(lines, string.format("%s(%s): {%s}", fieldName, valType, tostring(val)))
		end
		-- LOG doesn't like newlines...
		return table.concat(lines, ", ")
	end

	function StructType:__tostring()
		return self:_toDebugString()
	end
end

-- Register structure to structs table
function structureCreation.registerStructure(name, StructType)
	StructManager._structures[name] = StructType
end

return structureCreation
