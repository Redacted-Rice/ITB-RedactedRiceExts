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
	elseif field.type == "struct" and field.subType then
		-- Get size from the nested struct
		local structType = field.subType
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
	local maxOffset = -1
	local maxField = nil

	for _, field in pairs(layout) do
		if field.offset and field.offset > maxOffset then
			maxOffset = field.offset
			maxField = field
		end
	end

	return maxOffset, maxField
end

-- Add static methods to structure type
-- Don't use "get..." to avoid conflicting with defined types
function structureCreation.addStaticMethods(StructType, name, layout, vtableAddr, validateFn)
	-- Store validation info on the StructType for use by validate()
	StructType._vtableAddr = vtableAddr
	StructType._validateFn = validateFn

	-- Constructor
	function StructType.new(address, doValidate)
		if not address or address == 0 then
			-- Can't use logger here as it's not available, just return nil
			error(string.format("Invalid nil address 0 for %s", name))
			return nil
		end

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

		-- Auto-validate if requested
		if doValidate then
			local success, err = instance:validate()
			if not success then
				error(string.format("Structure validation failed for %s at 0x%X: %s", name, address, err))
				return nil
			end
		end

		return instance
	end

	-- Validate structure validity
	-- Can be called as instance method: instance:validate()
	-- Or as static method with address: StructType.validate(address)
	-- Returns: struct or nil (if invalid), errorMessage (string or nil)
	function StructType:validate(addressArg)
		-- Determine the address and whether to use an instance
		local addr, instance

		-- Check if this is a static call (self is a number, the address)
		-- or instance call (self has _address field)
		if type(self) == "number" then
			-- Static call: StructType.validate(address) - self IS the address
			addr = self
		elseif addressArg then
			-- Called with explicit address parameter
			addr = addressArg
		else
			-- Instance call: instance:validate()
			addr = self._address
			instance = self
		end

		-- Check if address is nil or 0
		if not addr or addr == 0 then
			return nil, "Address is nil or 0"
		end

		-- Calculate struct size
		local structSize = StructType.StructSize()
		if not structSize then
			return nil, "Cannot determine structure size"
		end

		-- Check if memory is readable
		if not StructManager._dll.memory.isReadable(addr, structSize) then
			return nil, string.format("Memory at address 0x%X (size %d) is not readable", addr, structSize)
		end

		-- VTable verification if specified
		if StructType._vtableAddr then
			local vtable = StructManager._dll.memory.readPointer(addr)
			if vtable ~= StructType._vtableAddr then
				return nil, string.format("VTable mismatch: expected 0x%X, got 0x%X", StructType._vtableAddr, vtable)
			end
		end

		-- create an instance if not already provided
		if not instance then
			-- don't validate it.. we already are doing that
			instance =  StructType.new(addr, false)
		end

		-- Custom validation function if specified
		if StructType._validateFn then
			local success, err = StructType._validateFn(instance)
			if not success then
				return nil, err or "Custom validation function failed for unspecified reason"
			end
		end

		return instance, nil
	end


	-- Calculate structure size
	function StructType.StructSize()
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
					if fieldDef.subType then
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
				valType = valType .. " - " .. fieldDef.subType
			elseif valType == "pointer" and fieldDef.subType ~= nil then
				valType = valType .. " - " .. fieldDef.subType
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
