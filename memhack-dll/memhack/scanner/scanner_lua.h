#ifndef SCANNER_LUA_H
#define SCANNER_LUA_H

#include "lua.hpp"
#include "scanner_base.h"
#include "scanner_basic.h"
#include "scanner_sequence.h"
#include "scanner_struct.h"
#include "scanner_heap.h"
#include "../log.h"
#include <cctype>
#include <cstdio>
#include <string>
#include <vector>

// Macro to get scanner from userdata with error checking
// Defines 'scanner' variable and returns 0 from function if null
#define GET_SCANNER(L, index) \
	Scanner** scannerPtr__ = (Scanner**)luaL_checkudata(L, index, "Scanner"); \
	if (scannerPtr__ == nullptr || *scannerPtr__ == nullptr) { \
		luaL_error(L, "Scanner is null"); \
		return 0; \
	} \
	Scanner* scanner = *scannerPtr__

// Helper functions
std::string toLower(const char* str);
bool parseInt(const char* str, int& outValue);
bool parseByte(lua_State* L, int index, uint8_t& outByte);
bool parseScanType(const char* str, ScanType& outType);
bool parseBasicDataType(const char* str, BasicScanner::DataType& outType);
bool parseSequenceDataType(const char* str, SequenceScanner::DataType& outType);

void logScannerErrors(lua_State* L, Scanner* scanner, const char* operation);

// Helper to parse target value for basic types (INT, FLOAT, etc)
bool parseBasicValue(lua_State* L, int valueIndex, BasicScanner::DataType dataType, ScanResult& outResult);

// Helper to parse target value for sequence types (STRING, BYTE_ARRAY)
bool parseSequenceValue(lua_State* L, int valueIndex, SequenceScanner::DataType dataType,
                        const void*& outData, size_t& outSize, std::vector<uint8_t, ScannerAllocator<uint8_t>>& bytesBuffer);

// Helper to push a basic type value to Lua stack
void pushBasicValueToLua(lua_State* L, const ScanResult& result, BasicScanner::DataType dataType);

// Helper to push a sequence type value to Lua stack
void pushSequenceValueToLua(lua_State* L, Scanner* scanner, const ScanResult& result, SequenceScanner::DataType dataType, bool readValues);

// Push byte sequence to Lua as string or table depending on data type
void pushBytesToLua(lua_State* L, const std::vector<uint8_t, ScannerAllocator<uint8_t>>& bytes, SequenceScanner::DataType dataType);

// Lua wrappers for Scanner that are generic for all types
int scanner_create(lua_State* L);
int scanner_first_scan(lua_State* L);
int scanner_rescan(lua_State* L);
int scanner_get_results(lua_State* L);
int scanner_get_result_count(lua_State* L);
int scanner_reset(lua_State* L);
int scanner_destroy(lua_State* L);

// Lua wrappers for StructSearch
int struct_search_create(lua_State* L);
int struct_search_add_field(lua_State* L);
int struct_search_destroy(lua_State* L);

// Register scanner functions with Lua
void add_scanner_functions(lua_State* L);

#endif
