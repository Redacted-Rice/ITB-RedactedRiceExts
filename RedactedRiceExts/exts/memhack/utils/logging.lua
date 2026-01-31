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
	
	SUBMODULE_INFO[id] = {
		extensionName = extensionName,
		moduleName = moduleName,
		enabled = enabled  -- Store the combined enabled flag
	}
	
	return id
end

-- Helper to get submodule info
local function getSubmoduleInfo(submodule)
	return SUBMODULE_INFO[submodule]
end

-- Base logging function
function logger.log(extensionName, moduleName, level, message)
	if level then
		LOG(string.format("%s.%s: %s - %s", extensionName, moduleName, level, message))
	else
		-- Debug log without level
		LOG(string.format("%s.%s: %s", extensionName, moduleName, message))
	end
end

-- Debug logging with lazy evaluation - format string only constructed if logging enabled
-- Usage: logger.logDebug(SUBMODULE, "Message") or logger.logDebug(SUBMODULE, "Format %s %d", arg1, arg2)
function logger.logDebug(submodule, fmt, ...)
	local info = getSubmoduleInfo(submodule)
	if info.enabled then
		local message
		if select('#', ...) > 0 then
			-- Format string with arguments
			message = string.format(fmt, ...)
		else
			-- No arguments, format is the message
			message = fmt
		end
		logger.log(info.extensionName, info.moduleName, nil, message)
	end
end

function logger.logError(submodule, message)
	local info = getSubmoduleInfo(submodule)
	logger.log(info.extensionName, info.moduleName, "ERR", message)
end

function logger.logWarn(submodule, message)
	local info = getSubmoduleInfo(submodule)
	logger.log(info.extensionName, info.moduleName, "WARN", message)
end

function logger.logInfo(submodule, message)
	local info = getSubmoduleInfo(submodule)
	logger.log(info.extensionName, info.moduleName, "INFO", message)
end

return logger
