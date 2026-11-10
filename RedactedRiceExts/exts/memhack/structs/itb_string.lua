-- Turns out these are just normal C++ strings
local logger = memhack.logger
local SUBMODULE = logger.register("Memhack", "ItBString", memhack.DEBUG.ENABLED)

-- Max length to be stored locally (not including null term)
local BUF_SEG_SIZE = memhack.dll.memory.STRING_BUFFER_SEGMENT_SIZE
local LOCAL_STR_MAX_LEN = BUF_SEG_SIZE - 1
local MAX_STR_LEN = memhack.dll.memory.MAX_NULL_TERM_STRING_LENGTH - 1


-- Validation function for ItBString structures
-- Note this has to be local as we don't have the ItBString table yet. We can access it later
-- via validate as well
local function validateItBString(itbStr)
	-- Ensure alloc size is at least the max local length and less than the max size
	local allocMaxLen = itbStr:getAllocMaxLen()
	if allocMaxLen < LOCAL_STR_MAX_LEN or allocMaxLen > MAX_STR_LEN then
		return false, string.format("Invalid allocMaxLen: %d (must be %d..%d)",
				allocMaxLen, LOCAL_STR_MAX_LEN, MAX_STR_LEN)
	end

	-- Ensure the string size is valid and less than the max alloc
	local len = itbStr:getStrLen()
	if len < 0 or len > MAX_STR_LEN then
		return false, string.format("Invalid ItB string length: %d (must be 0-%d)",
				len, MAX_STR_LEN)
	end
	if len > allocMaxLen then
		return false, string.format("strLen %d exceeds allocMaxLen %d", len, allocMaxLen)
	end

	-- Get the location of the ending null byte and make sure its null
	local dataAddr = itbStr:getAddress()
	-- If its not local, get the pointer, ensure non-null
	if allocMaxLen > LOCAL_STR_MAX_LEN then
		dataAddr = itbStr:_getStrRemotePtr()
		if not dataAddr or dataAddr == 0 then
			return false, "heap string pointer is null"
		end
	end

	local nullAddr = dataAddr + len
	-- If its non-local ensure its accessible (local we already know is)
	if allocMaxLen > LOCAL_STR_MAX_LEN then
		if not memhack.dll.memory.isAccessAllowed(nullAddr, 1, false) then
			return false, string.format("cannot read null terminator at 0x%X (strLen %d)",
					nullAddr, len)
		end
	end

	-- Now actually read the byte and make sure its null
	local nullByte = memhack.dll.memory.readByte(nullAddr)
	if nullByte ~= 0 then
		return false, string.format("missing null terminator at index %d (got 0x%02X)",
				len, nullByte)
	end

	return true
end

-- This is a standard 24 byte c++ string structure. We hide alot of default getters/setters to
-- ensure safe accessing and setting of values
local ItBString = memhack.structManager:define("ItBString", {
	-- Inline string data used if allocated size < 16. Otherwise it has to be stored with strRemote
	strLocal = { offset = 0x0, type = "string", maxLength = BUF_SEG_SIZE,
		lengthFn = function(self) return self:getStrLen() end,
		hideSetter = true, hideGetter = true },
	-- Same idea as strLocal but a pointer to the value if its too large to fit locally
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
	-- Allocates potentially more memory than needed for the string. If using standard
	-- behavior, this is a value of BUFFER_SEGMENT_SIZE * x - 1
	allocMaxLen = { offset = 0x14, type = "int", hideSetter = true },
}, validateItBString)

-- Set constants on ItBString after it's defined
ItBString.AutoUndictionary = true
ItBString.MAX_LOCAL_STRING_LENGTH = LOCAL_STR_MAX_LEN

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
	local allocMaxLen = self:getAllocMaxLen()
	if allocMaxLen < BUF_SEG_SIZE then
		local result = self:_getStrLocal()
		return result
	else
		local result = self:_getStrRemote()
		return result
	end
end

ItBString[selfSetter] = function(self, strOrStruct, skipUndictionary)
	local str = strOrStruct
	if type(strOrStruct) == "table" and getmetatable(strOrStruct) == ItBString then
		-- for simplicity and to prevent coupling, just get the current string
		-- value and use that
		str = strOrStruct:get()
	end

	-- Some menus (e.g. the post mission, level up skill notification window) don't use
	-- the lua dictionary/GetText function... For simplicity and consistency, by default
	-- just un-dictionary-ificate strings. This may cause oddities if you try to replace
	-- them dynamically where some are the old one. Most notable would be switching
	-- language but mods really only are in english and don't have translations so
	-- it shouldn't be a big deal
	if ItBString.AutoUndictionary and not skipUndictionary and IsText(str) then
		oldStr = str
		str = GetText(str)
		logger.logDebug(SUBMODULE, "Un-dictionary text %s to %s", oldStr, str)
	end

	local length = #str
	-- plus 1 for null term
	local buffSegments = math.ceil((length + 1.0) / BUF_SEG_SIZE)
	-- minus 1 for null term
	local allocMaxLen = buffSegments * BUF_SEG_SIZE - 1
	if allocMaxLen < BUF_SEG_SIZE then
		self:_setStrLocal(str)
	else
		-- We create the memory and pass it to the Game's struct
		-- it will then manage its lifecyle (i.e. deleting it)
		-- Originally I tried to make and maintain the lifecycle
		-- in Lua but the game thought it was its memory and would
		-- deallocate it on going to the main menu
		-- + 1 for null term
		self:_setStrRemotePtr(memhack.dll.memory.allocNullTermString(str, allocMaxLen + 1))
	end
	self:_setAllocMaxLen(allocMaxLen)
	self:_setStrLen(length)
end

-- Override tostring as pointer may not always be valid
ItBString.__tostring = function(self)
	local result = self[selfGetter](self)
	return result
end