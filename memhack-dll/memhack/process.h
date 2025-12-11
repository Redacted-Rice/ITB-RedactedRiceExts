#ifndef PROCESS_H
#define PROCESS_H

#include "lua.hpp"

// Get the base address of the executable
int get_exe_base(lua_State* L);

// Refresh cached heap regions
int refresh_heap_regions(lua_State* L);

// Get list of heap regions
int get_heap_regions(lua_State* L);

// Add process functions to Lua table
void add_process_functions(lua_State* L);

#endif
