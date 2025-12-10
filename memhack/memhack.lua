memhack = {}

local path = GetParentPath(...)

function memhack:init() 
	self.hex = require(path.."utils/hex")
	
	try(function()
		package.loadlib(path.."memhack.dll", "luaopen_memhack")(options)
		self.dll = memhackdll
		memhackdll = nil
		LOG("Loaded memhack dll")
	end)
	:catch(function(err)
		error(string.format(
				"Memdit - Failed to load memhack.dll: %s",
				tostring(err)
		))
	end)
end