#ifndef MEMORY_H
#define MEMORY_H

#include "lua.hpp"
#include "itb_userdata.h"

/*
	Simple memory read/write API
	All functions take a memory address as the first parameter
	Write functions take the value to write as the second parameter
*/

// Maximum length for C string operations (including null terminator)
const int MAX_CSTRING_LENGTH = 1024;

int get_userdata_addr(lua_State* L);
int alloc_cstring(lua_State* L);

// Read functions - return the value at the given address
int read_byte(lua_State* L);
int read_int(lua_State* L);
int read_bool(lua_State* L);
int read_double(lua_State* L);
int read_float(lua_State* L);
int read_cstring(lua_State* L);
int read_pointer(lua_State* L);
int read_byte_array(lua_State* L);

// Write functions - write a value to the given address
int write_byte(lua_State* L);
int write_int(lua_State* L);
int write_bool(lua_State* L);
int write_double(lua_State* L);
int write_float(lua_State* L);
int write_cstring(lua_State* L);
int write_pointer(lua_State* L);
int write_byte_array(lua_State* L);

// Register all memory functions with Lua
void add_memory_functions(lua_State* L);

#endif