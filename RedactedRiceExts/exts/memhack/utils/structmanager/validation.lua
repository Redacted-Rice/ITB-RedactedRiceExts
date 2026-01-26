-- Validation functions for fields and structures

local validation = {}

local TYPE_HANDLERS = StructManager.TYPE_HANDLERS

-- Validate field definition
function validation.validateField(name, field)
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

	if field.type == "struct" and not field.subType then
		error(string.format("Field '%s' with type 'struct' must have a 'subType'", name))
	end
end

-- Validate structure name and all fields
function validation.validateStructureDefinition(name, layout)
	if type(name) ~= "string" then
		error("Structure name must be a string")
	end

	for fieldName, field in pairs(layout) do
		validation.validateField(fieldName, field)
	end
end

-- Validate additional fields for extension
function validation.validateAndMergeExtensionFields(name, existingLayout, additionalFields)
	-- Validate new fields
	for fieldName, field in pairs(additionalFields) do
		validation.validateField(fieldName, field)
	end

	-- Check for duplicate field names
	for fieldName, _ in pairs(additionalFields) do
		if existingLayout[fieldName] then
			error(string.format("Field '%s' already exists in structure '%s'", fieldName, name))
		end
		existingLayout[fieldName] = field
	end
end

return validation

