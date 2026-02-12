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
	if len < 0 or len >= memhack.dll.memory.MAX_NULL_TERM_STRING_LENGTH then
		return false, string.format("Invalid ItB string length: %d (must be 0-%d)", len, memhack.dll.memory.MAX_NULL_TERM_STRING_LENGTH)
	end

	return true
end

-- This is a union. We hide alot of default getters/setters to
-- ensure safe accessing and setting of values
local ItBString = memhack.structManager:define("ItBString", {
	-- If present in global text table, the text idx to display. Otherwise displays directly.
	-- Can only be used if size < 16. Otherwise it has to be stored with strPtr
	-- May not always be valid - calling getters may be unsafe
	-- Uses lengthFn to read only the actual string length instead of max buffer size
	strLocal = { offset = 0x0, type = "string", maxLength = 16,
		lengthFn = function(self) return self:getStrLen() end,
		hideSetter = true, hideGetter = true },
	-- Same idea as strLocal but a pointer to the value if its too large to fit locally
	-- May not always be valid - calling getters may be unsafe
	-- Uses lengthFn to get actual string length instead of max length
	strRemote = { offset = 0x0, type = "pointer", hideSetter = true, hideGetter = true,
		subType = {
			type = "string",
			maxLength = memhack.dll.memory.MAX_NULL_TERM_STRING_LENGTH,
			lengthFn = function(self) return self:getStrLen() end
		}
	},
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

local selfGetter = memhack.structManager:makeStdSelfGetterName()
local selfSetter = memhack.structManager:makeStdSelfSetterName()

-- Custom getter for getting the string value from the struct
function ItBString.makeItBStringGetterName(itbStrName)
	-- Don't override default struct getter
	local result = StructManager:makeStdGetterName(itbStrName) .. "Str"
	return result
end

-- Custom setter taking string value or ItBString struct
function ItBString.makeItBStringSetterName(itbStrName)
	-- No default setter for struct and this handles both struct and string args
	-- so use the std setter name
	local result = StructManager:makeStdSetterName(itbStrName)
	return result
end

-- Creates both the setter and getter wrappers for the ItBString struct
function ItBString.makeItBStringGetSetWrappers(struct, itbStrName)
	memhack.structManager._methodGeneration.makeStructGetWrapper(
			struct, itbStrName, ItBString.makeItBStringGetterName(itbStrName), selfGetter)
	memhack.structManager._methodGeneration.makeStructSetWrapper(
			struct, itbStrName, ItBString.makeItBStringSetterName(itbStrName), selfSetter)
end

ItBString[selfGetter] = function(self)
	local uType = self:getUnionType()
	if uType == ItBString.LOCAL then
		local result = self:_getStrLocal()
		return result
	elseif uType == ItBString.REMOTE then
		local result = self:_getStrRemote()
		return result
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
		-- We create the memory and pass it to the Game's struct
		-- it will then manage its lifecyle (i.e. deleting it)
		-- Originally I tried to make and maintain the lifecycle
		-- in Lua but the game thought it was its memory and would
		-- deallocate it on going to the main menu
		self:_setStrRemotePtr(memhack.dll.memory.allocNullTermString(str))
		self:_setUnionType(ItBString.REMOTE)
	end
	self:_setStrLen(length)
end

-- Override tostring as pointer may not always be valid
ItBString.__tostring = function(self)
	local result = self[selfGetter](self)
	return result
end