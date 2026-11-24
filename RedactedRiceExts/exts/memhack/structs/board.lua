local MemhackBoard = memhack.structManager:define("Board", {
	podLandingLoc = { offset = 0x2D70, type = "struct", subType = "Point"},
})

local methodGen = memhack.structManager._methodGeneration

methodGen.makeStructSetWrapper(MemhackBoard, "podLandingLoc")
methodGen.makeStructGetWrapper(MemhackBoard, "podLandingLoc", "getPodLandingAsPoint")

-- Converts the memhack object back to the vanilla game object safely
function MemhackBoard:toVanilla()
	if not Board then
		return nil
	end

	local addr = self:getAddress()
	if not addr or addr == 0 then
		return nil
	end

	if memhack.dll.memory.getUserdataAddr(Board) == addr then
		return Board
	end

	return nil
end