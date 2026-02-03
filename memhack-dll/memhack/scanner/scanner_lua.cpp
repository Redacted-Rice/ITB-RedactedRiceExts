#include "stdafx.h"
#include "scanner_lua.h"
#include "scanner_base.h"
#include "scanner_basic.h"
#include "scanner_sequence.h"
#include "scanner_struct.h"
#include "../lua_helpers.h"

std::string toLower(const char* str) {
	std::string result(str);
	for (size_t i = 0; i < result.length(); i++) {
		result[i] = (char)std::tolower((unsigned char)result[i]);
	}
	return result;
}

// Parse integer from string, supporting decimal and hex with 0x prefix
bool parseInt(const char* str, int& outValue) {
	if (!str || !*str) return false;

	// Check for hex prefix
	if (str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
		char* endPtr = nullptr;
		long value = strtol(str, &endPtr, 16);
		if (endPtr && *endPtr == '\0') {
			outValue = (int)value;
			return true;
		}
	} else {
		// otherwise parse as decimal
		char* endPtr = nullptr;
		long value = strtol(str, &endPtr, 10);
		if (endPtr && *endPtr == '\0') {
			outValue = (int)value;
			return true;
		}
	}
	return false;
}

// Parse byte value from Lua. This handles numbers, single char strings, and hex strings
bool parseByte(lua_State* L, int index, uint8_t& outByte) {
	if (lua_isnumber(L, index)) {
		int value = lua_tointeger(L, index);
		if (value >= 0 && value <= 255) {
			outByte = (uint8_t)value;
			return true;
		}
	} else if (lua_isstring(L, index)) {
		const char* str = lua_tostring(L, index);
		if (str) {
			// Single character
			if (str[0] != '\0' && str[1] == '\0') {
				outByte = (uint8_t)str[0];
				return true;
			}
			// Hex string
			int value;
			if (parseInt(str, value) && value >= 0 && value <= 255) {
				outByte = (uint8_t)value;
				return true;
			}
		}
	}
	return false;
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

bool parseBasicDataType(const char* str, BasicScanner::DataType& outType) {
	std::string lower = toLower(str);

	if (lower == "byte") {
		outType = BasicScanner::DataType::BYTE;
		return true;
	} else if (lower == "int") {
		outType = BasicScanner::DataType::INT;
		return true;
	} else if (lower == "float") {
		outType = BasicScanner::DataType::FLOAT;
		return true;
	} else if (lower == "double") {
		outType = BasicScanner::DataType::DOUBLE;
		return true;
	} else if (lower == "bool") {
		outType = BasicScanner::DataType::BOOL;
		return true;
	}

	return false;
}

bool parseSequenceDataType(const char* str, SequenceScanner::DataType& outType) {
	std::string lower = toLower(str);

	if (lower == "string") {
		outType = SequenceScanner::DataType::STRING;
		return true;
	} else if (lower == "byte_array" || lower == "bytearray") {
		outType = SequenceScanner::DataType::BYTE_ARRAY;
		return true;
	}

	return false;
}

void logScannerErrors(lua_State* L, Scanner* scanner, const char* operation) {
	if (scanner->hasError()) {
		const std::vector<std::string, ScannerAllocator<std::string>>& errors = scanner->getErrors();
		for (const auto& error : errors) {
			char logMsg[512];
			sprintf_s(logMsg, sizeof(logMsg), "Scanner: ERROR during %s - %s", operation, error.c_str());
			log(L, logMsg);
		}
	}
}

// Parse basic type value (INT, FLOAT, BOOL, etc) from Lua
// Returns true on success, false on error (error already pushed to Lua)
bool parseBasicValue(lua_State* L, int valueIndex, BasicScanner::DataType dataType, ScanResult& outResult) {
	switch (dataType) {
		case BasicScanner::DataType::BYTE:
			if (!lua_isnumber(L, valueIndex)) {
				luaL_error(L, "Expected number for BYTE data type");
				return false;
			}
			outResult.value.byteValue = (uint8_t)lua_tonumber(L, valueIndex);
			return true;

		case BasicScanner::DataType::INT:
			if (!lua_isnumber(L, valueIndex)) {
				luaL_error(L, "Expected number for INT data type");
				return false;
			}
			outResult.value.intValue = (int32_t)lua_tonumber(L, valueIndex);
			return true;

		case BasicScanner::DataType::FLOAT:
			if (!lua_isnumber(L, valueIndex)) {
				luaL_error(L, "Expected number for FLOAT data type");
				return false;
			}
			outResult.value.floatValue = (float)lua_tonumber(L, valueIndex);
			return true;

		case BasicScanner::DataType::DOUBLE:
			if (!lua_isnumber(L, valueIndex)) {
				luaL_error(L, "Expected number for DOUBLE data type");
				return false;
			}
			outResult.value.doubleValue = lua_tonumber(L, valueIndex);
			return true;

		case BasicScanner::DataType::BOOL:
			if (!lua_isboolean(L, valueIndex)) {
				luaL_error(L, "Expected boolean for BOOL data type");
				return false;
			}
			outResult.value.boolValue = lua_toboolean(L, valueIndex);
			return true;

		default:
			luaL_error(L, "Unknown data type");
			return false;
	}
}

// Parse sequence value (STRING or BYTE_ARRAY) from Lua
// Returns true on success, false on error (error already pushed to Lua)
bool parseSequenceValue(lua_State* L, int valueIndex, SequenceScanner::DataType dataType,
                        const void*& outData, size_t& outSize, std::vector<uint8_t, ScannerAllocator<uint8_t>>& bytesBuffer) {
	switch (dataType) {
		case SequenceScanner::DataType::STRING:
		{
			if (!lua_isstring(L, valueIndex)) {
				luaL_error(L, "Expected string for STRING data type");
				return false;
			}
			const char* str = lua_tolstring(L, valueIndex, &outSize);
			outData = str;
			return true;
		}

		case SequenceScanner::DataType::BYTE_ARRAY:
		{
			if (!lua_isstring(L, valueIndex)) {
				luaL_error(L, "Expected string for BYTE_ARRAY data type");
				return false;
			}
			// Read bytes from string (Lua strings can contain binary data)
			const char* str = lua_tolstring(L, valueIndex, &outSize);
			
			if (outSize == 0) {
				luaL_error(L, "Sequence cannot be empty");
				return false;
			}

			// Copy to buffer to ensure persistence
			bytesBuffer.clear();
			bytesBuffer.resize(outSize);
			memcpy(bytesBuffer.data(), str, outSize);

			outData = bytesBuffer.data();
			return true;
		}
		default:
			luaL_error(L, "Unknown sequence data type");
			return false;
	}
}

// Push a basic type value to Lua stack
void pushBasicValueToLua(lua_State* L, const ScanResult& result, BasicScanner::DataType dataType) {
	switch (dataType) {
		case BasicScanner::DataType::BYTE:
			lua_pushinteger(L, result.value.byteValue);
			break;
		case BasicScanner::DataType::INT:
			lua_pushinteger(L, result.value.intValue);
			break;
		case BasicScanner::DataType::FLOAT:
			lua_pushnumber(L, result.value.floatValue);
			break;
		case BasicScanner::DataType::DOUBLE:
			lua_pushnumber(L, result.value.doubleValue);
			break;
		case BasicScanner::DataType::BOOL:
			lua_pushboolean(L, result.value.boolValue);
			break;
		default:
			lua_pushnil(L);
			break;
	}
}

// Push byte sequence to Lua as string or table based on SequenceScanner::DataType
void pushBytesToLua(lua_State* L, const std::vector<uint8_t, ScannerAllocator<uint8_t>>& bytes, SequenceScanner::DataType dataType) {
	if (dataType == SequenceScanner::DataType::STRING) {
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
void pushSequenceValueToLua(lua_State* L, Scanner* scanner, const ScanResult& result, SequenceScanner::DataType dataType, bool readValues) {
	if (!readValues) {
		lua_pushnil(L);
		return;
	}

	// Try to cast to SequenceScanner to read the sequence
	SequenceScanner* seqScanner = dynamic_cast<SequenceScanner*>(scanner);
	if (seqScanner) {
		ScanType lastScanType = scanner->getLastScanType();

		if (lastScanType == ScanType::NOT) {
			// NOT scan - read actual bytes to see what was found
			std::vector<uint8_t, ScannerAllocator<uint8_t>> bytes;
			if (seqScanner->readSequenceBytes(result.address, bytes)) {
				pushBytesToLua(L, bytes, dataType);
			} else {
				char logMsg[128];
				sprintf_s(logMsg, sizeof(logMsg), "Scanner: ERROR - Failed to read sequence bytes at address 0x%llX", (unsigned long long)result.address);
				log(L, logMsg);
				lua_pushnil(L);
			}
		} else {
			// We shouldn't be calling this on exact scans and
			// no other scan types are supported for sequences
			lua_pushnil(L);
		}
	} else {
		// Not a sequence scanner. Shouldn't have been called
		lua_pushnil(L);
	}
}

int scanner_create(lua_State* L) {
	// Get data type
	const char* dataTypeStr = luaL_checkstring(L, 1);
	std::string lower = toLower(dataTypeStr);

	// Parse options table if present
	size_t maxResults = 100000;
	size_t alignment = 0;
	bool checkTiming = false;

	if (lua_istable(L, 2)) {
		lua_pushstring(L, "maxResults");
		lua_gettable(L, 2);
		if (lua_isnumber(L, -1)) {
			lua_Integer value = lua_tointeger(L, -1);
			if (value > 0) {
				maxResults = (size_t)value;
			} else {
				luaL_error(L, "maxResults must be positive, got: %d", (int)value);
				return 0;
			}
		}
		lua_pop(L, 1);

		lua_pushstring(L, "alignment");
		lua_gettable(L, 2);
		if (lua_isnumber(L, -1)) {
			lua_Integer value = lua_tointeger(L, -1);
			if (value >= 0) {
				alignment = (size_t)value;
			} else {
				luaL_error(L, "alignment must be non-negative, got: %d", (int)value);
				return 0;
			}
		}
		lua_pop(L, 1);

		lua_pushstring(L, "checkTiming");
		lua_gettable(L, 2);
		if (lua_isboolean(L, -1)) {
			checkTiming = lua_toboolean(L, -1);
		}
		lua_pop(L, 1);
	}

	// Create appropriate scanner based on data type
	Scanner* scanner = nullptr;

	// Try basic types
	BasicScanner::DataType basicType;
	if (parseBasicDataType(dataTypeStr, basicType)) {
		scanner = BasicScanner::create(basicType, maxResults, alignment);
	}
	// Try sequence types
	else {
		SequenceScanner::DataType seqType;
		if (parseSequenceDataType(dataTypeStr, seqType)) {
			scanner = SequenceScanner::create(seqType, maxResults, alignment);
		}
		// Try struct type
		else if (lower == "struct") {
			scanner = StructScanner::create(maxResults, alignment);
		}
		else {
			luaL_error(L, "Invalid data type: %s (valid: BYTE, INT, FLOAT, DOUBLE, BOOL, STRING, BYTE_ARRAY, STRUCT)", dataTypeStr);
			return 0;
		}
	}

	// Create userdata and store scanner
	Scanner** scannerPtr = (Scanner**)lua_newuserdata(L, sizeof(Scanner*));
	*scannerPtr = scanner;

	// Set timing option
	scanner->setCheckTiming(checkTiming);

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

	// Determine scanner type and parse accordingly
	BasicScanner* basicScanner = dynamic_cast<BasicScanner*>(scanner);
	SequenceScanner* seqScanner = dynamic_cast<SequenceScanner*>(scanner);

	if (basicScanner) {
		ScanResult targetResult;
		if (!parseBasicValue(L, 3, basicScanner->getDataType(), targetResult)) {
			return 0; // Error already pushed
		}
		scanner->firstScan(scanType, &targetResult.value);
	} else if (seqScanner) {
		const void* data;
		size_t size;
		std::vector<uint8_t, ScannerAllocator<uint8_t>> bytesBuffer;

		if (!parseSequenceValue(L, 3, seqScanner->getDataType(), data, size, bytesBuffer)) {
			return 0; // Error already pushed
		}
		scanner->firstScan(scanType, data, size);
	} else if (dynamic_cast<StructScanner*>(scanner)) {
		StructScanner::StructSearch** structPtr = (StructScanner::StructSearch**)lua_testudata(L, 3, "StructSearch");
		if (!structPtr || !*structPtr) {
			luaL_error(L, "Struct scanner requires StructSearch as target value");
			return 0;
		}
		scanner->firstScan(scanType, *structPtr);
	} else {
		luaL_error(L, "Unknown scanner type");
		return 0;
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

	// Determine scanner type and parse accordingly
	BasicScanner* basicScanner = dynamic_cast<BasicScanner*>(scanner);
	SequenceScanner* seqScanner = dynamic_cast<SequenceScanner*>(scanner);

	if (basicScanner) {
		ScanResult targetResult;
		if (!parseBasicValue(L, 3, basicScanner->getDataType(), targetResult)) {
			return 0; // Error already pushed
		}
		scanner->rescan(scanType, &targetResult.value);
	} else if (seqScanner) {
		const void* data;
		size_t size;
		std::vector<uint8_t, ScannerAllocator<uint8_t>> bytesBuffer;

		if (!parseSequenceValue(L, 3, seqScanner->getDataType(), data, size, bytesBuffer)) {
			return 0; // Error already pushed
		}
		scanner->rescan(scanType, data, size);
	} else if (dynamic_cast<StructScanner*>(scanner)) {
		StructScanner::StructSearch** structPtr = (StructScanner::StructSearch**)lua_testudata(L, 3, "StructSearch");
		if (!structPtr || !*structPtr) {
			luaL_error(L, "Struct scanner requires StructSearch as target value");
			return 0;
		}
		scanner->rescan(scanType, *structPtr);
	} else {
		luaL_error(L, "Unknown scanner type");
		return 0;
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
	size_t offset = 0;
	size_t limit = 1000;
	bool readValues = false;

	if (lua_istable(L, 2)) {
		lua_pushstring(L, "offset");
		lua_gettable(L, 2);
		if (lua_isnumber(L, -1)) {
			lua_Integer value = lua_tointeger(L, -1);
			if (value >= 0) {
				offset = (size_t)value;
			} else {
				luaL_error(L, "offset must be non-negative, got: %d", (int)value);
				return 0;
			}
		}
		lua_pop(L, 1);

		lua_pushstring(L, "limit");
		lua_gettable(L, 2);
		if (lua_isnumber(L, -1)) {
			lua_Integer value = lua_tointeger(L, -1);
			if (value > 0) {
				limit = (size_t)value;
			} else {
				luaL_error(L, "limit must be positive, got: %d", (int)value);
				return 0;
			}
		}
		lua_pop(L, 1);

		lua_pushstring(L, "readValues");
		lua_gettable(L, 2);
		if (lua_isboolean(L, -1)) {
			readValues = lua_toboolean(L, -1);
		}
		lua_pop(L, 1);
	}

	const std::vector<ScanResult, ScannerAllocator<ScanResult>>& results = scanner->getResults();
	size_t totalCount = results.size();

	// Determine scanner type upfront to avoid repeated checks in loop
	BasicScanner* basicScanner = dynamic_cast<BasicScanner*>(scanner);
	SequenceScanner* seqScanner = dynamic_cast<SequenceScanner*>(scanner);
	StructScanner* structScanner = dynamic_cast<StructScanner*>(scanner);

	// Validate readValues request based on scanner type
	if (readValues) {
		if (seqScanner) {
			ScanType lastScanType = scanner->getLastScanType();
			// For sequence scanners, only NOT scans have meaningful, readable values
			if (lastScanType != ScanType::NOT) {
				luaL_error(L, "readValues not supported for scan type '%d' on sequence scanners", (int)lastScanType);
				return 0;
			}
		} else if (structScanner) {
			// Nothing makes sense for struct scanners
			luaL_error(L, "readValues not supported for struct scanners");
			return 0;
		}
		// any type of basic scan is fine
	}

	// Create results table
	lua_newtable(L);

	// Add results array
	lua_pushstring(L, "results");
	lua_newtable(L);

	size_t startIdx = offset;
	size_t endIdx = std::min<size_t>(offset + limit, totalCount);

	// Build results array
	for (size_t i = startIdx; i < endIdx; i++) {
		const ScanResult& result = results[i];

		// Lua 1-indexed
		lua_pushinteger(L, (lua_Integer)(i - startIdx + 1));
		lua_newtable(L);

		// Add address field
		lua_pushstring(L, "address");
		lua_pushinteger(L, (lua_Integer)result.address);
		lua_rawset(L, -3);

		// Add value field if we are reading the results
		if (readValues) {
			lua_pushstring(L, "value");

			if (basicScanner) {
				// Basic scanners store already in result
				pushBasicValueToLua(L, result, basicScanner->getDataType());
			} else if (seqScanner) {
				// Sequence scanner need to read from memory
				pushSequenceValueToLua(L, scanner, result, seqScanner->getDataType(), true);
			} else {
				// Other scanners (i.e. struct) don't have meaningful reads and we shouldn't have
				// gotten here but have this just in case
				lua_pushnil(L);
			}
			lua_rawset(L, -3);
		}

		lua_rawset(L, -3);
	}

	lua_rawset(L, -3);

	// Add metadata
	lua_pushstring(L, "totalCount");
	lua_pushinteger(L, (lua_Integer)totalCount);
	lua_rawset(L, -3);

	lua_pushstring(L, "offset");
	lua_pushinteger(L, (lua_Integer)offset);
	lua_rawset(L, -3);

	lua_pushstring(L, "limit");
	lua_pushinteger(L, (lua_Integer)limit);
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

// StructSearch Lua bindings
int struct_search_create(lua_State* L) {
	// Get key byte (supports number, char, or hex string)
	uint8_t keyByte;
	if (!parseByte(L, 1, keyByte)) {
		luaL_error(L, "Key byte must be a number (0-255), single character, or hex string (e.g., '0x42')");
		return 0;
	}

	// Get optional keyOffset (defaults to 0)
	int keyOffset = 0;
	if (lua_gettop(L) >= 2) {
		if (lua_isnumber(L, 2)) {
			keyOffset = lua_tointeger(L, 2);
		} else if (lua_isstring(L, 2)) {
			if (!parseInt(lua_tostring(L, 2), keyOffset)) {
				luaL_error(L, "keyOffset must be a number or hex string (e.g., '0x84')");
				return 0;
			}
		} else if (!lua_isnil(L, 2)) {
			luaL_error(L, "keyOffset must be a number or hex string");
			return 0;
		}
	}

	// Create StructSearch
	StructScanner::StructSearch** structPtr = (StructScanner::StructSearch**)lua_newuserdata(L, sizeof(StructScanner::StructSearch*));
	*structPtr = new StructScanner::StructSearch(keyByte, keyOffset);

	// Set metatable for garbage collection
	luaL_getmetatable(L, "StructSearch");
	lua_setmetatable(L, -2);
	return 1;
}

// field adding function that handles both basic and sequence types similar to how scanner creation works
int struct_search_add_field(lua_State* L) {
	// Get StructSearch
	StructScanner::StructSearch** structPtr = (StructScanner::StructSearch**)luaL_checkudata(L, 1, "StructSearch");
	if (structPtr == nullptr || *structPtr == nullptr) {
		luaL_error(L, "StructSearch is null");
		return 0;
	}

	// Get offset (supports number or hex string)
	int offset;
	if (lua_isnumber(L, 2)) {
		offset = lua_tointeger(L, 2);
	} else if (lua_isstring(L, 2)) {
		if (!parseInt(lua_tostring(L, 2), offset)) {
			luaL_error(L, "Invalid offset (must be number or hex string like '0x10')");
			return 0;
		}
	} else {
		luaL_error(L, "Offset must be a number or hex string");
		return 0;
	}

	// Get data type string (3rd parameter)
	const char* typeStr = luaL_checkstring(L, 3);

	// Get value (4th parameter)
	if (lua_isnil(L, 4)) {
		luaL_error(L, "Field value required");
		return 0;
	}

	// Try to parse as basic type
	BasicScanner::DataType basicType;
	if (parseBasicDataType(typeStr, basicType)) {
		ScanResult result;
		if (!parseBasicValue(L, 4, basicType, result)) {
			return 0; // Error already pushed
		}
		(*structPtr)->addBasicField(offset, basicType, result.value);
	}
	// Try to parse as sequence type
	else {
		SequenceScanner::DataType seqType;
		if (parseSequenceDataType(typeStr, seqType)) {
			// Sequence field
			const void* data;
			size_t size;
			std::vector<uint8_t, ScannerAllocator<uint8_t>> bytesBuffer;
			if (!parseSequenceValue(L, 4, seqType, data, size, bytesBuffer)) {
				return 0; // Error already pushed
			}
			(*structPtr)->addSequenceField(offset, (const uint8_t*)data, size);
		} else {
			// Check if it's a struct type (not supported for fields)
			std::string lowerType = toLower(typeStr);
			if (lowerType == "struct") {
				luaL_error(L, "STRUCT data type not supported for struct fields");
			} else {
				luaL_error(L, "Invalid data type: %s", typeStr);
			}
			return 0;
		}
	}

	return 0;
}

int struct_search_destroy(lua_State* L) {
	// __gc metamethod
	StructScanner::StructSearch** structPtr = (StructScanner::StructSearch**)luaL_checkudata(L, 1, "StructSearch");
	if (*structPtr != nullptr) {
		delete *structPtr;
		*structPtr = nullptr;
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

	// Create StructSearch metatable
	luaL_newmetatable(L, "StructSearch");

	// Set __gc for garbage collection
	lua_pushstring(L, "__gc");
	lua_pushcfunction(L, struct_search_destroy);
	lua_rawset(L, -3);

	// Set __index to itself for methods
	lua_pushstring(L, "__index");
	lua_newtable(L);

	lua_pushstring(L, "addField");
	lua_pushcfunction(L, struct_search_add_field);
	lua_rawset(L, -3);

	lua_rawset(L, -3);
	lua_pop(L, 1); // Pop metatable

	lua_pushstring(L, "StructSearch");
	lua_newtable(L);

	// StructSearch.new constructor
	lua_pushstring(L, "new");
	lua_pushcfunction(L, struct_search_create);
	lua_rawset(L, -3);

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
	lua_pushstring(L, "STRUCT"); lua_pushstring(L, "struct"); lua_rawset(L, -3);
	lua_rawset(L, -3);
}
