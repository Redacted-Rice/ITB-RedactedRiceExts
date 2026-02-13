-- A std C++ vector but with a particularity so I made it its own class
-- For some reason it always has at least 3 entries
local MemhackStorageObj = memhack.structManager:define("StorageObject", {
	-- Changing/setting these doesn't work well. Probably some more data that
	-- needs ot be changed also if setting pilot/weapon but I only care about
	-- reading ATM so I leave it at that

	-- Smart pointer ("double" reference - dont try to set)
	-- Its a Skill but haven't had a reason to define Skill yet so leave it untyped
	skill = { offset = 0x114, type = "pointer", noSetter = true },
	-- Smart pointer ("double" reference - dont try to set)
	pilot = { offset = 0x11C, type = "pointer", subType = "Pilot", noSetter = true },
})

MemhackStorageObj.TYPE_PILOT = "Pilot"
MemhackStorageObj.TYPE_SKILL = "Skill"

function MemhackStorageObj:isPilot()
	return self:getPilotPtr() ~= 0
end

function MemhackStorageObj:isSkill()
	return self:getSkillPtr() ~= 0
end

function MemhackStorageObj:isType(objType)
	return self:getType() == objType
end

function MemhackStorageObj:getType()
	if self:isPilot() then
		return MemhackStorageObj.TYPE_PILOT
	elseif self:isSkill() then
		return MemhackStorageObj.TYPE_SKILL
	end
	-- There shouldn't be anything else...
	return "Unknown"
end