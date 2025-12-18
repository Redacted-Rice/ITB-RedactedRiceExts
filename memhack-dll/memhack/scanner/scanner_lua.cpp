#include "../stdafx.h"
#include "scanner/scanner_lua.h"
#include "scanner/scanner_base.h"

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
	} else if (lower == "string") {
		outType = DataType::STRING;
		return true;
	} else if (lower == "byte_array" || lower == "bytearray") {
		outType = DataType::BYTE_ARRAY;
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

// Parse basic type value (INT, FLOAT, BOOL, etc) from Lua
// Returns true on success, false on error (error already pushed to Lua)
bool parseBasicValue(lua_State* L, int valueIndex, DataType dataType, ScanResult& outResult) {
	if (lua_isnumber(L, valueIndex)) {
		double value = lua_tonumber(L, valueIndex);
		outResult.value.intValue = (int32_t)value;
		outResult.value.floatValue = (float)value;
		outResult.value.doubleValue = value;
		outResult.value.byteValue = (uint8_t)value;
		return true;
	} else if (lua_isboolean(L, valueIndex)) {
		outResult.value.boolValue = lua_toboolean(L, valueIndex);
		return true;
	} else {
		luaL_error(L, "Target value must be a number or boolean");
		return false;
	}
}

// Parse sequence value (STRING or BYTE_ARRAY) from Lua
// Returns true on success, false on error (error already pushed to Lua)
bool parseSequenceValue(lua_State* L, int valueIndex, DataType dataType,
                        const void*& outData, size_t& outSize, std::vector<uint8_t>& bytesBuffer) {
	if (dataType == DataType::STRING) {
		if (!lua_isstring(L, valueIndex)) {
			luaL_error(L, "Target value must be a string for STRING scanner");
			return false;
		}

		const char* str = lua_tolstring(L, valueIndex, &outSize);
		outData = str;
		return true;

	} else if (dataType == DataType::BYTE_ARRAY) {
		if (!lua_istable(L, valueIndex)) {
			luaL_error(L, "Target value must be a table of bytes for BYTE_ARRAY scanner");
			return false;
		}

		// Read bytes from table
		bytesBuffer.clear(); 
		size_t tableLen = lua_objlen(L, valueIndex);

		for (size_t i = 1; i <= tableLen; i++) {
			lua_rawgeti(L, valueIndex, (lua_Integer)i);
			if (!lua_isnumber(L, -1)) {
				luaL_error(L, "BYTE_ARRAY table must contain only numbers");
				return false;
			}
			int byte = lua_tointeger(L, -1);
			if (byte < 0 || byte > 255) {
				luaL_error(L, "BYTE_ARRAY values must be 0-255, got: %d", byte);
				return false;
			}
			bytesBuffer.push_back((uint8_t)byte);
			lua_pop(L, 1);
		}

		if (bytesBuffer.empty()) {
			luaL_error(L, "BYTE_ARRAY sequence cannot be empty");
			return false;
		}

		outData = bytesBuffer.data();
		outSize = bytesBuffer.size();
		return true;
	}

	return false;
}

// Push a basic type value to Lua stack
void pushBasicValueToLua(lua_State* L, const ScanResult& result, DataType dataType) {
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
		default:
			lua_pushnil(L);
			break;
	}
}

// Push byte sequence to Lua as string or table depending on dataType
void pushBytesToLua(lua_State* L, const std::vector<uint8_t>& bytes, DataType dataType) {
	if (dataType == DataType::STRING) {
		// Return as string
		lua_pushlstring(L, (const char*)bytes.data(), bytes.size());
	} else {
		// Return as table of bytes
		lua_newtable(L);
		for (size_t j = 0; j < bytes.size(); j++) {
			lua_pushinteger(L, j + 1);  // Lua 1-indexed
			lua_pushinteger(L, bytes[j]);
			lua_rawset(L, -3);
		}
	}
}

// Push a sequence type value to Lua stack
void pushSequenceValueToLua(lua_State* L, Scanner* scanner, const ScanResult& result,
                            DataType dataType, bool readValues) {
	if (!readValues) {
		lua_pushnil(L);
		return;
	}

	// if readValues is set we read actual bytes or return search sequence
	ScanType lastScanType = scanner->getLastScanType();

	if (lastScanType == ScanType::NOT) {
		// NOT scan - read actual bytes to see what was found
		std::vector<uint8_t> bytes;
		if (scanner->readSequenceBytes(result.address, bytes)) {
			pushBytesToLua(L, bytes, dataType);
		} else {
			// Failed to read - return nil
			lua_pushnil(L);
		}
	} else {
		// EXACT scan - return the search sequence
		const std::vector<uint8_t>& searchSeq = scanner->getSearchSequence();
		pushBytesToLua(L, searchSeq, dataType);
	}
}

int scanner_create(lua_State* L) {
	// Get data type
	const char* dataTypeStr = luaL_checkstring(L, 1);

	// Parse options table if present
	int maxResults = 100000;
	int alignment = 0;
	bool checkTiming = false;

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

		lua_pushstring(L, "checkTiming");
		lua_gettable(L, 2);
		if (lua_isboolean(L, -1)) {
			checkTiming = lua_toboolean(L, -1);
		}
		lua_pop(L, 1);
	}

	// Parse data type (case-insensitive)
	DataType dataType;
	if (!parseDataType(dataTypeStr, dataType)) {
		luaL_error(L, "Invalid data type: %s (valid: BYTE, INT, FLOAT, DOUBLE, BOOL, STRING, BYTE_ARRAY)", dataTypeStr);
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

	// Create scanner using factory (automatically selects SequenceScanner or BasicScanner)
	Scanner** scannerPtr = (Scanner**)lua_newuserdata(L, sizeof(Scanner*));
	// Scanner already has teardown/dealloc logic in __gc
	*scannerPtr = Scanner::create(dataType, maxResults, alignment);

	// Set timing option
	(*scannerPtr)->setCheckTiming(checkTiming);

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

	DataType dataType = scanner->getDataType();

	// Parse and execute scan based on data type
	if (dataType == DataType::STRING || dataType == DataType::BYTE_ARRAY) {
		// Sequence types
		const void* data;
		size_t size;
		std::vector<uint8_t> bytesBuffer;

		if (!parseSequenceValue(L, 3, dataType, data, size, bytesBuffer)) {
			return 0; // Error already pushed
		}

		scanner->firstScan(scanType, data, size);
	} else {
		// Basic types
		ScanResult targetResult;

		if (!parseBasicValue(L, 3, dataType, targetResult)) {
			return 0; // Error already pushed
		}

		scanner->firstScan(scanType, &targetResult.value);
	}

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

	DataType dataType = scanner->getDataType();

	// Parse and execute scan based on data type (same logic as firstScan)
	if (dataType == DataType::STRING || dataType == DataType::BYTE_ARRAY) {
		// Sequence types
		const void* data;
		size_t size;
		std::vector<uint8_t> bytesBuffer;

		if (!parseSequenceValue(L, 3, dataType, data, size, bytesBuffer)) {
			return 0; // Error already pushed
		}

		scanner->rescan(scanType, data, size);
	} else {
		// Basic types
		ScanResult targetResult;

		if (!parseBasicValue(L, 3, dataType, targetResult)) {
			return 0; // Error already pushed
		}

		scanner->rescan(scanType, &targetResult.value);
	}

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

	// Read optional offset, limit, and readValues from table or individual args
	int offset = 0;
	int limit = 100;
	bool readValues = false;

	if (lua_istable(L, 2)) {
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

		lua_pushstring(L, "readValues");
		lua_gettable(L, 2);
		if (lua_isboolean(L, -1)) {
			readValues = lua_toboolean(L, -1);
		}
		lua_pop(L, 1);
	}

	const std::vector<ScanResult>& results = scanner->getResults();
	int totalCount = (int)results.size();

	// Create results table
	lua_newtable(L);

	// Add results array
	lua_pushstring(L, "results");
	lua_newtable(L);

	int startIdx = offset;
	int endIdx = std::min<int>(offset + limit, totalCount);

	DataType dataType = scanner->getDataType();

	// Build results array
	for (int i = startIdx; i < endIdx; i++) {
		const ScanResult& result = results[i];

		// Lua 1-indexed
		lua_pushinteger(L, i - startIdx + 1);
		lua_newtable(L);

		// Add address field
		lua_pushstring(L, "address");
		lua_pushinteger(L, result.address);
		lua_rawset(L, -3);

		// Add value field
		lua_pushstring(L, "value");
		if (dataType == DataType::STRING || dataType == DataType::BYTE_ARRAY) {
			pushSequenceValueToLua(L, scanner, result, dataType, readValues);
		} else {
			pushBasicValueToLua(L, result, dataType);
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
	lua_pushstring(L, "STRING"); lua_pushstring(L, "string"); lua_rawset(L, -3);
	lua_pushstring(L, "BYTE_ARRAY"); lua_pushstring(L, "byte_array"); lua_rawset(L, -3);
	lua_rawset(L, -3);
}
