#include "stdafx.h"
#include "process.h"
#include "safememory.h"

int get_exe_base(lua_State* L) {
	HMODULE exeBase = GetModuleHandle(nullptr);
	lua_pushinteger(L, (lua_Integer)exeBase);
	return 1;
}

int get_heap_regions(lua_State* L) {
	bool write = lua_toboolean(L, 1);

	// Get the cached process heap regions from the validator
	const std::vector<SafeMemory::Region>& regions = SafeMemory::get_heap_regions(write);

	// Create a table to hold heap information
	lua_newtable(L);

	int regionIndex = 1;
	for (const auto& region : regions) {
		// Add this region to the table
		lua_pushinteger(L, regionIndex);
		lua_newtable(L);

		// base address
		lua_pushstring(L, "base");
		lua_pushinteger(L, (lua_Integer)region.base);
		lua_rawset(L, -3);

		// size
		lua_pushstring(L, "size");
		lua_pushinteger(L, (lua_Integer)region.size);
		lua_rawset(L, -3);

		// end address
		lua_pushstring(L, "end");
		lua_pushinteger(L, (lua_Integer)((char*)region.base + region.size));
		lua_rawset(L, -3);

		// Add to parent table
		lua_rawset(L, -3);
		regionIndex++;
	}

	return 1;
}

void add_process_functions(lua_State* L) {
	if (!lua_istable(L, -1)) {
		luaL_error(L, "add_process_functions failed: parent table does not exist");
	}

	lua_pushstring(L, "getExeBase");
	lua_pushcfunction(L, get_exe_base);
	lua_rawset(L, -3);

	lua_pushstring(L, "getHeapRegions");
	lua_pushcfunction(L, get_heap_regions);
	lua_rawset(L, -3);
}
