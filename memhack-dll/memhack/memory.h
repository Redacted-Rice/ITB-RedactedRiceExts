#ifndef MEMORY_H
#define MEMORY_H

#include "lua.hpp"

/*
	Simple memory read/write API
	All functions take a memory address as the first parameter
	Write functions take the value to write as the second parameter
*/

// Read functions - return the value at the given address
int read_int(lua_State* L);
int read_bool(lua_State* L);
int read_double(lua_State* L);
int read_float(lua_State* L);
int read_string(lua_State* L);
int read_pointer(lua_State* L);
int read_byte_array(lua_State* L);

// Write functions - write a value to the given address
int write_int(lua_State* L);
int write_bool(lua_State* L);
int write_double(lua_State* L);
int write_float(lua_State* L);
int write_string(lua_State* L);
int write_pointer(lua_State* L);
int write_byte_array(lua_State* L);

// Register all memory functions with Lua
void add_memory_functions(lua_State* L);

#endif