-- This is a union... how to handle in struct?
-- Maybe just have overlap here and let modders add functions as needed
-- Add a disable all setters option?
local ItBString = memhack.structManager.define("ItBString", {
	-- If present in global text table, the text idx to display. Otherwise displays directly.
	-- Can only be used if size < 16. Otherwise it has to be stored with strPtr
	strLocal = { offset = 0x0, type = "string", maxLength = 16, hideSetter = true },
	-- Same idea as strLocal but a pointer to the value if its too large to fit locally
	strRemote = { offset = 0x0, type = "pointer", hideSetter = true, pointedType = "string", pointedSize = memhack.dll.memory.MAX_CSTRING_LENGTH },
	-- Length of the strLocal/string pointed to by strRemote. This is set the same regardless
	-- of which is used
	strLen = { offset = 0x10, type = "int", hideSetter = true },
	-- Which one is used. If x0F, it will be treated as strLocal in place. If 0x1F, it will
	-- be treated as a pointer (strRemote). Not sure if there are any other valid values
	unionType = { offset = 0x14, type = "int", hideSetter = true },
})

ItBString.LOCAL =  0x0F
ItBString.REMOTE = 0x1F

-- TODO add to structManager instead?
function ItBString._makeDirectGetterWrapper(struct, itbStrName)
	local capitailized = memhack.structManager.capitalize(itbStrName)
	local intGetterName = "Get" .. capitailized .. "Obj"
	local getterWrapperName = "Get" .. capitailized .. "Str"

	struct[getterWrapperName] = function(self)
		return self[intGetterName](self):Get()
	end
end

function onModsFirstLoaded()
	ItBString.strings = {}
	
	ItBString.Get = function(self)
		local uType = self:GetUnionType()
		if uType == ItBString.LOCAL then
			return self:GetStrLocal()
		elseif uType == ItBString.REMOTE then
			return self:GetStrRemoteObj()
		end
		error(string.format("UnionType was unexepected value: %d", uType))
		return nil
	end
	
	ItBString.Set = function(self, str)
		local length = #str
		if length < 16 then -- < 16 for room for null term
			-- If its less than 16, we can store it locally
			self:_SetStrLocal(str)
			self:_SetUnionType(ItBString.LOCAL)
		else 
			-- if we don't have a str idx already, create one
			if ItBString.strings[str] == nil then
				ItBString.strings[str] = memhack.dll.memory.allocCString(str)
			end
			self:_SetStrRemotePtr(memhack.dll.memory.getUserdataAddr(ItBString.strings[str]))
			self:_SetUnionType(ItBString.REMOTE)
		end
		self:_SetStrLen(length)
	end
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)