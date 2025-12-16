#ifndef SCANNER_LUA_H
#define SCANNER_LUA_H

#include "lua.hpp"
#include "scanner_core.h"
#include "log.h"
#include <cctype>
#include <cstring>
#include <cstdio>
#include <string>

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
bool parseScanType(const char* str, ScanType& outType);
bool parseDataType(const char* str, DataType& outType);

void logScannerErrors(lua_State* L, Scanner* scanner, const char* operation);

// Lua wrappers for Scanner
int scanner_create(lua_State* L);
int scanner_first_scan(lua_State* L);
int scanner_rescan(lua_State* L);
int scanner_get_results(lua_State* L);
int scanner_get_result_count(lua_State* L);
int scanner_reset(lua_State* L);
int scanner_destroy(lua_State* L);

// Register scanner functions with Lua
void add_scanner_functions(lua_State* L);

#endif
