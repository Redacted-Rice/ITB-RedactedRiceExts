-- Constants for union types
local ITB_STRING_LOCAL = 0x0F
local ITB_STRING_REMOTE = 0x1F

-- Validation function for ItBString structures
local function validateItBString(itbStr)
	-- Check that unionType is valid
	local unionType = itbStr:getUnionType()
	if unionType ~= ITB_STRING_LOCAL and unionType ~= ITB_STRING_REMOTE then
		return false, string.format("Invalid unionType: expected 0x0F or 0x1F, got 0x%X", unionType)
	end

	-- Check that string length is reasonable
	local len = itbStr:getStrLen()
	if len < 0 or len >= memhack.dll.memory.MAX_CSTRING_LENGTH then
		return false, string.format("Invalid ItB string length: %d (must be 0-%d)", len, memhack.dll.memory.MAX_CSTRING_LENGTH)
	end

	return true
end

-- This is a union. We hide alot of default getters/setters to
-- ensure safe accessing and setting of values
local ItBString = memhack.structManager.define("ItBString", {
	-- If present in global text table, the text idx to display. Otherwise displays directly.
	-- Can only be used if size < 16. Otherwise it has to be stored with strPtr
	-- May not always be valid - calling getters may be unsafe
	strLocal = { offset = 0x0, type = "string", maxLength = 16, hideSetter = true, hideGetter = true },
	-- Same idea as strLocal but a pointer to the value if its too large to fit locally
	-- May not always be valid - calling getters may be unsafe
	strRemote = { offset = 0x0, type = "pointer", hideSetter = true, hideGetter = true, subType = "string", pointedSize = memhack.dll.memory.MAX_CSTRING_LENGTH },
	-- Length of the strLocal/string pointed to by strRemote. This is set the same regardless
	-- of which is used
	strLen = { offset = 0x10, type = "int", hideSetter = true },
	-- Which one is used. If x0F, it will be treated as strLocal in place. If 0x1F, it will
	-- be treated as a pointer (strRemote). Not sure if there are any other valid values
	unionType = { offset = 0x14, type = "int", hideSetter = true },
}, validateItBString)

-- Set constants on ItBString after it's defined
ItBString.LOCAL = ITB_STRING_LOCAL
ItBString.REMOTE = ITB_STRING_REMOTE

local selfGetter = memhack.structManager.makeStdSelfGetterName()
local selfSetter = memhack.structManager.makeStdSelfSetterName()

-- Custom getter for getting the string value from the struct
function ItBString.makeItBStringGetterName(itbStrName)
	-- Don't override default struct getter
	return StructManager.makeStdGetterName(itbStrName) .. "Str"
end

-- Custom setter taking string value or ItBString struct
function ItBString.makeItBStringSetterName(itbStrName)
	-- No default setter for struct and this handles both struct and string args
	-- so use the std setter name
	return StructManager.makeStdSetterName(itbStrName)
end

-- Creates both the setter and getter wrappers for the ItBString struct
function ItBString.makeItBStringGetSetWrappers(struct, itbStrName)
	memhack.structManager._methodGeneration.makeStructGetWrapper(
			struct, itbStrName, ItBString.makeItBStringGetterName(itbStrName), selfGetter)
	memhack.structManager._methodGeneration.makeStructSetWrapper(
			struct, itbStrName, ItBString.makeItBStringSetterName(itbStrName), selfSetter)
end

function onModsFirstLoaded()
	ItBString.strings = {}

	ItBString[selfGetter] = function(self)
		local uType = self:getUnionType()
		if uType == ItBString.LOCAL then
			return self:_getStrLocal()
		elseif uType == ItBString.REMOTE then
			return self:_getStrRemote()
		end
		error(string.format("UnionType was unexepected value: %d", uType))
		return nil
	end

	ItBString[selfSetter] = function(self, strOrStruct)
		local str = strOrStruct
		if type(strOrStruct) == "table" and getmetatable(strOrStruct) == ItBString then
			-- for simplicity and to prevent coupling, just get the current string
			-- value and use that
			str = strOrStruct:get()
		end

		local length = #str
		if length < 16 then -- < 16 for room for null term
			-- If its less than 16, we can store it locally
			self:_setStrLocal(str)
			self:_setUnionType(ItBString.LOCAL)
		else
			-- if we don't have a str idx already, create one
			if ItBString.strings[str] == nil then
				ItBString.strings[str] = memhack.dll.memory.allocCString(str)
			end
			self:_setStrRemotePtr(memhack.dll.memory.getUserdataAddr(ItBString.strings[str]))
			self:_setUnionType(ItBString.REMOTE)
		end
		self:_setStrLen(length)
	end

	-- Override tostring as pointer may not always be valid
	ItBString.__tostring = function(self)
		return self[selfGetter](self)
	end
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)