local MemhackBoard = memhack.structManager:define("Board", {
	podLandingPoint = { offset = 0x2D70, type = "struct", subType = "Point"},
})

local methodGen = memhack.structManager._methodGeneration

methodGen.makeStructSetWrapper(MemhackBoard, "podLandingPoint")
methodGen.makeStructGetWrapper(MemhackBoard, "podLandingPoint", "getPodLandingPointAsPoint")