-- This is a union. We hide alot of default getters/setters to
-- ensure safe accessing and setting of values
local ItBString = memhack.structManager.define("ItBString", {
	-- If present in global text table, the text idx to display. Otherwise displays directly.
	-- Can only be used if size < 16. Otherwise it has to be stored with strPtr
	-- May not always be valid - calling getters may be unsafe
	strLocal = { offset = 0x0, type = "string", maxLength = 16, hideSetter = true, hideGetter = true },
	-- Same idea as strLocal but a pointer to the value if its too large to fit locally
	-- May not always be valid - calling getters may be unsafe
	strRemote = { offset = 0x0, type = "pointer", hideSetter = true, hideGetter = true, pointedType = "string", pointedSize = memhack.dll.memory.MAX_CSTRING_LENGTH },
	-- Length of the strLocal/string pointed to by strRemote. This is set the same regardless
	-- of which is used
	strLen = { offset = 0x10, type = "int", hideSetter = true },
	-- Which one is used. If x0F, it will be treated as strLocal in place. If 0x1F, it will
	-- be treated as a pointer (strRemote). Not sure if there are any other valid values
	unionType = { offset = 0x14, type = "int", hideSetter = true },
})

ItBString.LOCAL =  0x0F
ItBString.REMOTE = 0x1F

-- Requires function named <GETTER_PREFIX>
-- TODO: Expose and use method name creators
memhack.structManager.makeItBStringGetterWrapper = function(struct, itbStrName)
	local capitalized = memhack.structManager.capitalize(itbStrName)
	local internalGetterName = memhack.structManager.GETTER_PREFIX .. capitalized
	local getterWrapperName = memhack.structManager.GETTER_PREFIX .. capitalized .. "Str"

	struct[getterWrapperName] = function(self)
	    local obj = self[internalGetterName](self)
		return obj[memhack.structManager.GETTER_PREFIX](obj)
	end
end

function onModsFirstLoaded()
	ItBString.strings = {}
	
	ItBString[memhack.structManager.GETTER_PREFIX] = function(self)
		local uType = self:getUnionType()
		if uType == ItBString.LOCAL then
			return self:_getStrLocal()
		elseif uType == ItBString.REMOTE then
			return self:_getStrRemote()
		end
		error(string.format("UnionType was unexepected value: %d", uType))
		return nil
	end
	
	-- todo make also allow taking ItBString Object
	ItBString[memhack.structManager.SETTER_PREFIX] = function(self, str)
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
		return self[memhack.structManager.GETTER_PREFIX](self)
	end
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)