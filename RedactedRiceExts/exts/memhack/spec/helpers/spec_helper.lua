-- Sets up the globals and memhack extension for testing
local M = {}

-- Create a mock DLL
local function createMockDll()
	local mockMemory = {}
	local nextAddr = 0x10000000

	return {
		memory = {
			MAX_CSTRING_LENGTH = 1024,

			-- Allocate a mock C string and return userdata-like object
			allocCString = function(str)
				local addr = nextAddr
				nextAddr = nextAddr + #str + 1
				mockMemory[addr] = str
				return {_addr = addr, _type = "cstring"}
			end,

			-- Get address from userdata
			getUserdataAddr = function(obj)
				if type(obj) == "table" and obj._addr then
					return obj._addr
				end
				-- For real game objects, return a mock address
				return nextAddr
			end,

			-- Read pointer at address
			readPointer = function(addr)
				return mockMemory[addr] or 0
			end,

			-- Write pointer at address
			writePointer = function(addr, value)
				mockMemory[addr] = value
			end,

			-- Read int at address
			readInt = function(addr)
				return mockMemory[addr] or 0
			end,

			-- Write int at address
			writeInt = function(addr, value)
				mockMemory[addr] = value
			end,

			-- Read string at address
			readNullTermString = function(addr, maxLen)
				return mockMemory[addr] or ""
			end,

			-- Additional mock functions for struct system
			readBool = function(addr) return mockMemory[addr] or false end,
			writeBool = function(addr, value) mockMemory[addr] = value end,
			readDouble = function(addr) return mockMemory[addr] or 0.0 end,
			writeDouble = function(addr, value) mockMemory[addr] = value end,
			readFloat = function(addr) return mockMemory[addr] or 0.0 end,
			writeFloat = function(addr, value) mockMemory[addr] = value end,
			readByte = function(addr) return mockMemory[addr] or 0 end,
			writeByte = function(addr, value) mockMemory[addr] = value end,
			readByteArray = function(addr, len) return mockMemory[addr] or string.rep("\0", len) end,
			writeByteArray = function(addr, value) mockMemory[addr] = value end,

			-- Memory verification
			isAccessAllowed = function(addr, size, write)
				-- Mock: addresses >= 0x1000 are readable
				return addr >= 0x1000 and size > 0
			end,
		},

		process = {
			-- Get mock exe base address
			getExeBase = function()
				return 0x00400000
			end
		}
	}
end

-- Setup globals needed by the extension
function M.setupGlobals()
	_G.LOG = _G.LOG or function(msg) end

	_G.GetParentPath = _G.GetParentPath or function(modPath)
		return ""
	end

	_G.try = _G.try or function(fn)
		return {
			catch = function(self, catchFn)
				local success, err = pcall(fn)
				if not success then
					catchFn(err)
				end
			end
		}
	end

	-- Mock modApi events
	_G.modApi = _G.modApi or {}
	_G.modApi.events = _G.modApi.events or {}
	_G.modApi.events.onConsoleToggled = { subscribe = function() end }
	_G.modApi.events.onGameEntered = { subscribe = function() end }
	_G.modApi.events.onGameExited = { subscribe = function() end }
	_G.modApi.events.onGameVictory = { subscribe = function() end }
	_G.modApi.events.onGameClassInitialized = { subscribe = function() end }
	_G.modApi.events.onPawnClassInitialized = { subscribe = function() end }
	-- onModsFirstLoaded fires immediately to initialize structs
	_G.modApi.events.onModsFirstLoaded = { subscribe = function(self, fn) if fn then fn() end end }
	_G.modApi.addSaveGameHook = function() end

	_G.Event = _G.Event or setmetatable({
		buildErrorMessage = function(prefix, error, ...)
			return prefix .. tostring(error)
		end,
		isStackOverflowError = function(error)
			return type(error) == "string" and error:match("stack overflow")
		end
	}, {
		__call = function(self, config)
			return {
				dispatch = function() end
			}
		end
	})
	_G.Game = _G.Game or {}
end

-- Initialize the memhack extension with mock DLL
function M.initMemhack()
	-- Preinitialize memhack hooks stub BEFORE setupGlobals
	-- This is needed because pilot.lua references memhack.hooks when onModsFirstLoaded fires
	_G.memhack = _G.memhack or {}
	_G.memhack.hooks = {
		firePilotChangedHooks = function() end,
		firePilotLvlUpSkillChangedHooks = function() end,
	}

	M.setupGlobals()

	-- Load memhack module
	require("memhack")

	-- Initialize with mock DLL
	local mockDll = createMockDll()
	memhack:init(mockDll)

	-- Load memhack as well
	memhack:load()

	return memhack
end

return M
