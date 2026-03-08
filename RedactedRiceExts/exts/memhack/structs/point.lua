-- Point used by ItB. Seems to just be two ints
local MemhackPoint = memhack.structManager:define("Point", {
	x = { offset = 0x0, type = "int"},
	y = { offset = 0x4, type = "int"},
})

local selfSetter = memhack.structManager:makeStdSelfSetterName()
local selfGetter = memhack.structManager:makeStdSelfGetterName()

MemhackPoint[selfSetter] = function(self, objOrStructOrPoint)
	local vals = objOrStructOrPoint
	if type(objOrStructOrPoint) == "table" and getmetatable(objOrStructOrPoint) == MemhackPoint then
		-- for simplicity and to prevent coupling, just get the current string
		-- value and use that

		vals = {		
			x = objOrStructOrPoint:getX(),
			y = objOrStructOrPoint:getY(),
		}
	elseif type(v) == "userdata" and getmetatable(v) == Point then
		vals = {		
			x = objOrStructOrPoint:x(),
			y = objOrStructOrPoint:y(),
		}
    end
	self:setX(vals.x)
	self:setY(vals.y)
end

MemhackPoint[selfGetter] = function(self)
	local point = Point(self:getX(), self:getY())
	return point
end