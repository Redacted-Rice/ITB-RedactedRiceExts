-- Validation functions for fields and structures

local validation = {}

local TYPE_HANDLERS = StructManager.TYPE_HANDLERS

-- Validate field definition
function validation.validateField(name, field)
	if type(field) ~= "table" then
		error(string.format("Field '%s' must be a table", name))
		return false
	end

	if type(field.offset) ~= "number" then
		error(string.format("Field '%s' must have a numeric 'offset'", name))
		return false
	end

	if not field.type then
		error(string.format("Field '%s' must have a 'type'", name))
		return false
	end

	if not TYPE_HANDLERS[field.type] then
		error(string.format("Field '%s' has unknown type '%s'", name, field.type))
		return false
	end

	if field.type == "bytearray" and not field.length then
		error(string.format("Field '%s' with type 'bytearray' must have a 'length'", name))
		return false
	end

	if field.type == "string" and not field.maxLength then
		error(string.format("Field '%s' with type 'string' must have a 'maxLength' (including null terminator)", name))
		return false
	end

	if field.type == "struct" and not field.subType then
		error(string.format("Field '%s' with type 'struct' must have a 'subType'", name))
		return false
	end
	return true
end

-- Validate structure name and all fields
function validation.validateStructureDefinition(name, layout)
	if type(name) ~= "string" then
		error("Structure name must be a string")
		return false
	end

	-- Validate all fields
	for fieldName, field in pairs(layout) do
		-- Skip if not a table
		if type(field) ~= "table" then
			error(string.format("Field '%s' must be a table, got %s", fieldName, type(field)))
			return false
		end
		
		-- Validate the field definition
		if not validation.validateField(fieldName, field) then
			return false
		end
		
		-- Check if vtable field would overlap with other fields
		if fieldName == "vtable" then
			-- This is the vtable field we added, make sure no other fields overlap with offset 0-3
			for otherFieldName, otherField in pairs(layout) do
				if otherFieldName ~= "vtable" and otherField.offset ~= nil and otherField.offset < 4 then
					error(string.format("VTable field at offset 0 conflicts with field '%s' at offset %d", otherFieldName, otherField.offset))
					return false
				end
			end
		end		
	end
	return true
end

-- Validate additional fields for extension
function validation.validateAndMergeExtensionFields(name, existingLayout, additionalFields)
	-- Validate new fields
	for fieldName, field in pairs(additionalFields) do
		if not validation.validateField(fieldName, field) then
			return false
		end
	end

	-- Check for duplicate field names
	for fieldName, _ in pairs(additionalFields) do
		if existingLayout[fieldName] then
			error(string.format("Field '%s' already exists in structure '%s'", fieldName, name))
			return false
		end
		existingLayout[fieldName] = field
	end
	return true
end

return validation

