#include "stdafx.h"
#include "scanner_lua.h"
#include "log.h"

std::string toLower(const char* str) {
	std::string result(str);
	for (size_t i = 0; i < result.length(); i++) {
		result[i] = (char)std::tolower((unsigned char)result[i]);
	}
	return result;
}

bool parseScanType(const char* str, ScanType& outType) {
	std::string lower = toLower(str);

	if (lower == "exact") {
		outType = ScanType::EXACT;
		return true;
	} else if (lower == "increased") {
		outType = ScanType::INCREASED;
		return true;
	} else if (lower == "decreased") {
		outType = ScanType::DECREASED;
		return true;
	} else if (lower == "changed") {
		outType = ScanType::CHANGED;
		return true;
	} else if (lower == "unchanged") {
		outType = ScanType::UNCHANGED;
		return true;
	} else if (lower == "not") {
		outType = ScanType::NOT;
		return true;
	}

	return false;
}

bool parseDataType(const char* str, DataType& outType) {
	std::string lower = toLower(str);

	if (lower == "byte") {
		outType = DataType::BYTE;
		return true;
	} else if (lower == "int") {
		outType = DataType::INT;
		return true;
	} else if (lower == "float") {
		outType = DataType::FLOAT;
		return true;
	} else if (lower == "double") {
		outType = DataType::DOUBLE;
		return true;
	} else if (lower == "bool") {
		outType = DataType::BOOL;
		return true;
	}

	return false;
}

void logScannerErrors(lua_State* L, Scanner* scanner, const char* operation) {
	if (scanner->hasError()) {
		const std::vector<std::string>& errors = scanner->getErrors();
		for (const auto& error : errors) {
			char logMsg[512];
			sprintf_s(logMsg, sizeof(logMsg), "Scanner: ERROR during %s - %s", operation, error.c_str());
			log(L, logMsg);
		}
	}
}

int scanner_create(lua_State* L) {
	// Get data type
	const char* dataTypeStr = luaL_checkstring(L, 1);

	// Parse options table if present
	int maxResults = 100000;
	int alignment = 0;

	if (lua_istable(L, 2)) {
		lua_pushstring(L, "maxResults");
		lua_gettable(L, 2);
		if (lua_isnumber(L, -1)) {
			maxResults = lua_tointeger(L, -1);
		}
		lua_pop(L, 1);

		lua_pushstring(L, "alignment");
		lua_gettable(L, 2);
		if (lua_isnumber(L, -1)) {
			alignment = lua_tointeger(L, -1);
		}
		lua_pop(L, 1);
	}

	// Parse data type (case-insensitive)
	DataType dataType;
	if (!parseDataType(dataTypeStr, dataType)) {
		luaL_error(L, "Invalid data type: %s (valid: BYTE, INT, FLOAT, DOUBLE, BOOL)", dataTypeStr);
		return 0;
	}

	// Validate maxResults
	if (maxResults <= 0) {
		luaL_error(L, "maxResults must be positive, got: %d", maxResults);
		return 0;
	}

	// Validate alignment (0 is ok, means use data type size)
	if (alignment < 0) {
		luaL_error(L, "alignment must be non-negative, got: %d", alignment);
		return 0;
	}

	// Create scanner
	Scanner** scannerPtr = (Scanner**)lua_newuserdata(L, sizeof(Scanner*));
	// Scanner already has teardown/dealloc logic in __gc
	*scannerPtr = new Scanner(dataType, maxResults, alignment);

	// Set metatable for garbage collection
	luaL_getmetatable(L, "Scanner");
	lua_setmetatable(L, -2);
	return 1;
}

int scanner_first_scan(lua_State* L) {
	// Creates Scanner*
	GET_SCANNER(L, 1);

	// Second arg is the scan type
	const char* scanTypeStr = luaL_checkstring(L, 2);
	ScanType scanType;
	if (!parseScanType(scanTypeStr, scanType)) {
		luaL_error(L, "Invalid scan type: %s (valid: EXACT, NOT, INCREASED, DECREASED, CHANGED, UNCHANGED)", scanTypeStr);
		return 0;
	}

	// Third arg is the target value
	if (lua_isnil(L, 3)) {
		luaL_error(L, "Target value required for scanning");
		return 0;
	}

	ScanResult targetResult;
	if (lua_isnumber(L, 3)) {
		double value = lua_tonumber(L, 3);
		targetResult.value.intValue = (int32_t)value;
		targetResult.value.floatValue = (float)value;
		targetResult.value.doubleValue = value;
		targetResult.value.byteValue = (uint8_t)value;
	} else if (lua_isboolean(L, 3)) {
		targetResult.value.boolValue = lua_toboolean(L, 3);
	} else {
		luaL_error(L, "Target value must be a number or boolean");
		return 0;
	}

	// Perform scan
	scanner->firstScan(scanType, &targetResult.value);

	// Log any errors
	logScannerErrors(L, scanner, "first scan");

	// Return results table
	lua_newtable(L);

	lua_pushstring(L, "resultCount");
	lua_pushinteger(L, scanner->getResultCount());
	lua_rawset(L, -3);

	lua_pushstring(L, "maxResultsReached");
	lua_pushboolean(L, scanner->isMaxResultsReached());
	lua_rawset(L, -3);

	return 1;
}

int scanner_rescan(lua_State* L) {
	// Creates Scanner*
	GET_SCANNER(L, 1);

	// Second arg is the scan type
	const char* scanTypeStr = luaL_checkstring(L, 2);
	ScanType scanType;
	if (!parseScanType(scanTypeStr, scanType)) {
		luaL_error(L, "Invalid scan type: %s (valid: EXACT, NOT, INCREASED, DECREASED, CHANGED, UNCHANGED)", scanTypeStr);
		return 0;
	}

	// Third arg is the target value
	if (lua_isnil(L, 3)) {
		luaL_error(L, "Target value required for scanning");
		return 0;
	}

	ScanResult targetResult;
	if (lua_isnumber(L, 3)) {
		double value = lua_tonumber(L, 3);
		targetResult.value.intValue = (int32_t)value;
		targetResult.value.floatValue = (float)value;
		targetResult.value.doubleValue = value;
		targetResult.value.byteValue = (uint8_t)value;
	} else if (lua_isboolean(L, 3)) {
		targetResult.value.boolValue = lua_toboolean(L, 3);
	} else {
		luaL_error(L, "Target value must be a number or boolean");
		return 0;
	}

	// Perform rescan
	scanner->rescan(scanType, &targetResult.value);

	// Log any errors
	logScannerErrors(L, scanner, "rescan");

	// Return results table
	lua_newtable(L);

	lua_pushstring(L, "resultCount");
	lua_pushinteger(L, scanner->getResultCount());
	lua_rawset(L, -3);

	return 1;
}

int scanner_get_results(lua_State* L) {
	// Creates Scanner*
	GET_SCANNER(L, 1);

	// Read optional offset and limit from table or individual args
	int offset = 0;
	int limit = 100;

	if (lua_istable(L, 2)) {
		// Table format: scanner:getResults({ offset = 10, limit = 50 })
		lua_pushstring(L, "offset");
		lua_gettable(L, 2);
		if (lua_isnumber(L, -1)) {
			offset = lua_tointeger(L, -1);
		}
		lua_pop(L, 1);

		lua_pushstring(L, "limit");
		lua_gettable(L, 2);
		if (lua_isnumber(L, -1)) {
			limit = lua_tointeger(L, -1);
		}
		lua_pop(L, 1);
	} else {
		// Individual args format: scanner:getResults(offset, limit)
		offset = luaL_optinteger(L, 2, 0);
		limit = luaL_optinteger(L, 3, 100);
	}

	const std::vector<ScanResult>& results = scanner->getResults();
	int totalCount = (int)results.size();

	// Create results table
	lua_newtable(L);

	// Add results array
	lua_pushstring(L, "results");
	lua_newtable(L);

	int startIdx = offset;
	int endIdx = std::min(offset + limit, totalCount);

	DataType dataType = scanner->getDataType();

	for (int i = startIdx; i < endIdx; i++) {
		const ScanResult& result = results[i];

		// Lua 1-indexed
		lua_pushinteger(L, i - startIdx + 1);
		lua_newtable(L);

		lua_pushstring(L, "address");
		lua_pushinteger(L, result.address);
		lua_rawset(L, -3);

		lua_pushstring(L, "value");
		switch (dataType) {
			case DataType::BYTE:
				lua_pushinteger(L, result.value.byteValue);
				break;
			case DataType::INT:
				lua_pushinteger(L, result.value.intValue);
				break;
			case DataType::FLOAT:
				lua_pushnumber(L, result.value.floatValue);
				break;
			case DataType::DOUBLE:
				lua_pushnumber(L, result.value.doubleValue);
				break;
			case DataType::BOOL:
				lua_pushboolean(L, result.value.boolValue);
				break;
		}
		lua_rawset(L, -3);

		lua_rawset(L, -3);
	}

	lua_rawset(L, -3);

	// Add metadata
	lua_pushstring(L, "totalCount");
	lua_pushinteger(L, totalCount);
	lua_rawset(L, -3);

	lua_pushstring(L, "offset");
	lua_pushinteger(L, offset);
	lua_rawset(L, -3);

	lua_pushstring(L, "limit");
	lua_pushinteger(L, limit);
	lua_rawset(L, -3);

	return 1;
}

int scanner_get_result_count(lua_State* L) {
	// Creates Scanner*
	GET_SCANNER(L, 1);

	lua_pushinteger(L, scanner->getResultCount());
	return 1;
}

int scanner_reset(lua_State* L) {
	// Creates Scanner*
	GET_SCANNER(L, 1);

	scanner->reset();
	return 0;
}

int scanner_destroy(lua_State* L) {
	// __gc metamethod
	Scanner** scannerPtr = (Scanner**)luaL_checkudata(L, 1, "Scanner");
	if (*scannerPtr != nullptr) {
		log(L, "Scanner: Destroyed");
		delete *scannerPtr;
		*scannerPtr = nullptr;
	}
	return 0;
}

void add_scanner_functions(lua_State* L) {
	if (!lua_istable(L, -1)) {
		luaL_error(L, "add_scanner_functions failed: parent table does not exist");
	}

	// Create Scanner metatable
	luaL_newmetatable(L, "Scanner");

	// Set __gc for garbage collection
	lua_pushstring(L, "__gc");
	lua_pushcfunction(L, scanner_destroy);
	lua_rawset(L, -3);

	// Set __index to itself for methods
	lua_pushstring(L, "__index");
	lua_newtable(L);

	lua_pushstring(L, "firstScan");
	lua_pushcfunction(L, scanner_first_scan);
	lua_rawset(L, -3);

	lua_pushstring(L, "rescan");
	lua_pushcfunction(L, scanner_rescan);
	lua_rawset(L, -3);

	lua_pushstring(L, "getResults");
	lua_pushcfunction(L, scanner_get_results);
	lua_rawset(L, -3);

	lua_pushstring(L, "getResultCount");
	lua_pushcfunction(L, scanner_get_result_count);
	lua_rawset(L, -3);

	lua_pushstring(L, "reset");
	lua_pushcfunction(L, scanner_reset);
	lua_rawset(L, -3);

	lua_rawset(L, -3);
	lua_pop(L, 1); // Pop metatable

	lua_pushstring(L, "new");
	lua_pushcfunction(L, scanner_create);
	lua_rawset(L, -3);

	// Add scan type constants
	lua_pushstring(L, "SCAN_TYPE");
	lua_newtable(L);
	lua_pushstring(L, "EXACT"); lua_pushstring(L, "exact"); lua_rawset(L, -3);
	lua_pushstring(L, "INCREASED"); lua_pushstring(L, "increased"); lua_rawset(L, -3);
	lua_pushstring(L, "DECREASED"); lua_pushstring(L, "decreased"); lua_rawset(L, -3);
	lua_pushstring(L, "CHANGED"); lua_pushstring(L, "changed"); lua_rawset(L, -3);
	lua_pushstring(L, "UNCHANGED"); lua_pushstring(L, "unchanged"); lua_rawset(L, -3);
	lua_pushstring(L, "NOT"); lua_pushstring(L, "not"); lua_rawset(L, -3);
	lua_rawset(L, -3);

	// Add data type constants
	lua_pushstring(L, "DATA_TYPE");
	lua_newtable(L);
	lua_pushstring(L, "BYTE"); lua_pushstring(L, "byte"); lua_rawset(L, -3);
	lua_pushstring(L, "INT"); lua_pushstring(L, "int"); lua_rawset(L, -3);
	lua_pushstring(L, "FLOAT"); lua_pushstring(L, "float"); lua_rawset(L, -3);
	lua_pushstring(L, "DOUBLE"); lua_pushstring(L, "double"); lua_rawset(L, -3);
	lua_pushstring(L, "BOOL"); lua_pushstring(L, "bool"); lua_rawset(L, -3);
	lua_rawset(L, -3);
}
