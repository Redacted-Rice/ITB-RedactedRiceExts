memhack = {}

local path = GetParentPath(...)

function memhack:init()
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

	-- Initialize utility modules
	self.debug = require(path.."utils/debug").init(self.dll)

	-- Initialize structure system
	self.structManager = require(path.."utils/structmanager")
	self.structs = self.structManager.init(self.dll)
	
	
	require(path.."structs/vector")
	require(path.."structs/storage_object")
	require(path.."structs/storage")
	require(path.."structs/research_control")
	require(path.."structs/game_map")
end
