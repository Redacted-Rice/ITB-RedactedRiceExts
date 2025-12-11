// memhack.cpp : Defines the exported functions for the DLL application.
//

#include "stdafx.h"
#include "lua.hpp"
#include "memory.h"
#include "process.h"

#define DLLEXPORT __declspec(dllexport)

extern "C" DLLEXPORT int luaopen_memhack(lua_State* L) {
	// Create the main module table
	lua_newtable(L);

	/* ---------------- Add Memory functions ---------------- */
	lua_pushstring(L, "memory");
	lua_newtable(L);
	add_memory_functions(L);
	lua_rawset(L, -3);

	/* ---------------- Add Process functions --------------- */
	lua_pushstring(L, "process");
	lua_newtable(L);
	add_process_functions(L);
	lua_rawset(L, -3);

	/* ----------------------------------------------------- */

	// Set output to global variable
	lua_setglobal(L, "memhackdll");

	return 1;
}
