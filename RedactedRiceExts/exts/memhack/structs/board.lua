local MemhackBoard = memhack.structManager:define("Board", {
	podLandingLoc = { offset = 0x2D70, type = "struct", subType = "Point"},
})

local methodGen = memhack.structManager._methodGeneration

methodGen.makeStructSetWrapper(MemhackBoard, "podLandingLoc")
methodGen.makeStructGetWrapper(MemhackBoard, "podLandingLoc", "getPodLandingAsPoint")