-- Logging utility for Extensions
-- Shared by both CPLUS+ and Memhack extensions

local logger = {}

-- Dynamic submodule registry - modules register themselves at load time
local SUBMODULE_INFO = {}
local nextSubmoduleId = 1

-- Register a submodule for logging
-- Returns: submodule ID to use in log calls
-- Usage: local SUBMODULE = logger.register("CPLUS+", "SkillConfig", cplus_plus_ex.DEBUG.CONFIG and cplus_plus_ex.DEBUG.ENABLED)
function logger.register(extensionName, moduleName, enabled)
	local id = nextSubmoduleId
	nextSubmoduleId = nextSubmoduleId + 1
	SUBMODULE_INFO[id] = enabled
	return id
end

-- Helper to get submodule info
function logger.isSubmoduleEnabled(submodule)
	return SUBMODULE_INFO[submodule]
end

function logger.getCurrentDate()
	return os.date("%Y-%m-%d %H:%M:%S")
end

function logger.buildCallerMessage(callerOffset, level)
	callerOffset = callerOffset or 0
	assert(type(callerOffset) == "number")

	local timestamp = logger.getCurrentDate()
	local info = debug.getinfo(3 + callerOffset, "Sl")
	return string.format("[%s] [%s:%3d]:%s", timestamp, info.short_src, info.currentline, level)
end

function logger.modApiBaseLog(callerOffset, level, ...)
	if mod_loader.logger then
		local caller = logger.buildCallerMessage(callerOffset, level)
		mod_loader.logger:log(caller, ...)
	else
		LOG(...)
	end
end

-- Debug logging with lazy evaluation - format string only constructed if logging enabled
-- Usage: logger.logDebug(SUBMODULE, "Message") or logger.logDebug(SUBMODULE, "Format %s %d", arg1, arg2)
function logger.logDebug(submodule, fmt, ...)
	if logger.isSubmoduleEnabled(submodule) then
		local message
		if select('#', ...) > 0 then
			-- Format string with arguments
			message = string.format(fmt, ...)
		else
			-- No arguments, format is the message
			message = fmt
		end
		logger.modApiBaseLog(1, "DBUG", message)
	end
end

function logger.logError(submodule, message)
	-- Space to preserve spacing
	logger.modApiBaseLog(1, " ERR", message)
end

function logger.logWarn(submodule, message)
	logger.modApiBaseLog(1, "WARN", message)
end

function logger.logInfo(submodule, message)
	logger.modApiBaseLog(1, "INFO", message)
end

return logger
