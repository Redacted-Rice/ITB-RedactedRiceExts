-- Create global memhack object
memhack = memhack or {}

local path = GetParentPath(...)

function memhack:init(mockDll)
	-- Allow injecting a mock DLL for testing
	if mockDll then
		self.dll = mockDll
		LOG("Loaded mock memhack dll")
	else
		try(function()
			package.loadlib(path.."memhack.dll", "luaopen_memhack")(options)
			self.dll = memhackdll
			memhackdll = nil
			LOG("Loaded memhack dll")
		end)
		:catch(function(err)
			error(string.format(
					"Memhack - Failed to load memhack.dll: %s",
					tostring(err)
			))
		end)
	end

	-- Initialize utility modules
	self.debug = require(path.."utils/debug").init(self.dll)

	-- Initialize structure system
	self.structManager = require(path.."utils/structmanager")
	self.structs = self.structManager.init(self.dll)

	-- Load structs
	require(path.."structs/itb_string")
	require(path.."structs/vector")

	-- Pilot-related structs (order matters - dependencies must be loaded first)
	require(path.."structs/pilot_lvl_up_skill")
	require(path.."structs/pilot_lvl_up_skills_array")
	require(path.."structs/pilot")

	require(path.."structs/storage_object")
	require(path.."structs/storage")
	require(path.."structs/research_control")
	require(path.."structs/victory_screen")
	require(path.."structs/unknown_obj_1")
	require(path.."structs/game_map")

	-- Load added functions to existing game classes
	require(path.."appended_fns/game")
	require(path.."appended_fns/pawn")

	-- Require all submodules before initializing
	self._subobjects = {}
	self._subobjects.hooks = require(path.."scripts/hooks")
	self._subobjects.stateTracker = require(path.."scripts/state_tracker")

	-- Initialize submodules (they will set their local references here)
	self._subobjects.hooks:init()
	self._subobjects.stateTracker:init()

	-- Expose commonly used submodules at root level
	self.hooks = self._subobjects.hooks
	self.stateTracker = self._subobjects.stateTracker

	-- Wrap hooks to update state trackers to prevent double firing from state tracking
	self._subobjects.stateTracker:wrapHooksToUpdateStateTrackers()
end

function memhack:load()
	self._subobjects.hooks:load()
	self._subobjects.stateTracker:load()
end