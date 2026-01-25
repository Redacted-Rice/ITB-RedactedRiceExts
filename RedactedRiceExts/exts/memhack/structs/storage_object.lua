-- A std C++ vector but with a particularity so I made it its own class
-- For some reason it always has at least 3 entries
local MemhackStorageObj = memhack.structManager.define("StorageObject", {
	-- Changing/setting these doesn't work well. Probably some more data that
	-- needs ot be changed also if setting pilot/weapon but I only care about
	-- reading ATM so I leave it at that
	
	-- Smart pointer ("double" reference - dont try to set)
	-- Its a Skill but haven't had a reason to define Skill yet so leave it untyped
	skill = { offset = 0x114, type = "pointer", hideSetter = true },
	-- Smart pointer ("double" reference - dont try to set)
	pilot = { offset = 0x11C, type = "pointer", pointedType = "Pilot", hideSetter = true },
})


function onModsFirstLoaded()
	MemhackStorageObj.TYPE_PILOT = "Pilot"
	MemhackStorageObj.TYPE_SKILL = "Skill"

	MemhackStorageObj.isPilot = function(self)
		return self:getPilotPtr() ~= 0
	end
	
	MemhackStorageObj.isSkill = function(self)
		return self:getSkillPtr() ~= 0
	end
	
	MemhackStorageObj.isType = function(self, objType)
		return self:getType() == objType
	end

	MemhackStorageObj.getType = function(self)
		if self:isPilot() then
			return MemhackStorageObj.TYPE_PILOT
		elseif self:isSkill() then
			return MemhackStorageObj.TYPE_SKILL
		end
		-- There shouldn't be anything else...
		return "Unknown"
	end
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)