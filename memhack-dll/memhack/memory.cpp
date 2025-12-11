#include "stdafx.h"
#include "memory.h"
#include "safememory.h"
#include "lua_helpers.h"

static bool READ_ONLY = false;
static bool READ_WRITE = true;

// Read functions - return the value at the given address
int read_int(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	if (!SafeMemory::is_access_allowed(addr, sizeof(int), READ_ONLY)) {
		luaL_error(L, "read_int (or pointer) failed: read from address 0x%p not allowed", addr);
		return 0;
	}
	lua_pushinteger(L, *(int*)addr);
	return 1;
}

int read_bool(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	if (!SafeMemory::is_access_allowed(addr, sizeof(bool), READ_ONLY)) {
		luaL_error(L, "read_bool failed: read from address 0x%p not allowed", addr);
		return 0;
	}
	lua_pushboolean(L, *(bool*)addr);
	return 1;
}

int read_double(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	if (!SafeMemory::is_access_allowed(addr, sizeof(double), READ_ONLY)) {
		luaL_error(L, "read_double failed: read from address 0x%p not allowed", addr);
		return 0;
	}
	lua_pushnumber(L, *(double*)addr);
	return 1;
}

int read_float(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	if (!SafeMemory::is_access_allowed(addr, sizeof(float), READ_ONLY)) {
		luaL_error(L, "read_float failed: read from address 0x%p not allowed", addr);
		return 0;
	}
	lua_pushnumber(L, *(float*)addr);
	return 1;
}

int read_string(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	// TODO
	std::string* str = (std::string*)addr;
	lua_pushstring(L, str->c_str());
	return 1;
}

int read_pointer(lua_State* L) {
	return read_int(L);
}

int read_byte_array(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	int length = luaL_checkinteger(L, 2);

	if (length < 0) {
		luaL_error(L, "read_byte_array failed: length must be non-negative");
		return 0;
	}

	if (!SafeMemory::is_access_allowed(addr, length, READ_ONLY)) {
		luaL_error(L, "read_byte_array failed: read from address 0x%p (len %d) not allowed", addr, length);
		return 0;
	}

	unsigned char* bytes = (unsigned char*)addr;

	// Create a Lua table to hold the bytes
	lua_createtable(L, length, 0);

	for (int i = 0; i < length; i++) {
		lua_pushinteger(L, i + 1);  // Lua tables are 1-indexed
		lua_pushinteger(L, bytes[i]);
		lua_rawset(L, -3);
	}

	return 1;
}

// Write functions - write a value to the given address
int write_int(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	if (!SafeMemory::is_access_allowed(addr, sizeof(int), READ_WRITE)) {
		luaL_error(L, "write_int (or pointer) failed: write to address 0x%p not allowed", addr);
		return -1;
	}
	int value = luaL_checkinteger(L, 2);
	*(int*)addr = value;
	return 0;
}

int write_bool(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	if (!SafeMemory::is_access_allowed(addr, sizeof(bool), READ_WRITE)) {
		luaL_error(L, "write_bool failed: write to address 0x%p not allowed", addr);
		return -1;
	}
	bool value = lua_toboolean(L, 2);
	*(bool*)addr = value;
	return 0;
}

int write_double(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	if (!SafeMemory::is_access_allowed(addr, sizeof(double), READ_WRITE)) {
		luaL_error(L, "write_double failed: write to address 0x%p not allowed", addr);
		return -1;
	}
	double value = luaL_checknumber(L, 2);
	*(double*)addr = value;
	return 0;
}

int write_float(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	float value = (float)luaL_checknumber(L, 2);
	if (!SafeMemory::is_access_allowed(addr, sizeof(float), READ_WRITE)) {
		luaL_error(L, "write_float failed: write to address 0x%p not allowed", addr);
		return -1;
	}
	*(float*)addr = value;
	return 0;
}

int write_string(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	const char* value = luaL_checkstring(L, 2);
	// TODO
	std::string* str = (std::string*)addr;
	*str = std::string(value);
	return 0;
}

int write_pointer(lua_State* L) {
	return write_int(L);
}

int write_byte_array(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);

	// Get the length of the table
	int length = lua_objlen(L, 2);

	if (length < 0) {
		luaL_error(L, "write_byte_array failed: length must be non-negative");
		return -1;
	}

	if (!SafeMemory::is_access_allowed(addr, length, READ_WRITE)) {
		luaL_error(L, "write_byte_array failed: write to address 0x%p (len %d) not allowed", addr, length);
		return -1;
	}

	unsigned char* bytes = (unsigned char*)addr;

	// Write each byte from the table
	for (int i = 1; i <= length; i++) {
		lua_pushinteger(L, i);
		lua_gettable(L, 2);

		if (lua_isnumber(L, -1)) {
			int byte_value = lua_tointeger(L, -1);
			// Clamp to byte range (0-255)
			if (byte_value < 0) byte_value = 0;
			if (byte_value > 255) byte_value = 255;
			bytes[i - 1] = (unsigned char)byte_value;
		}

		lua_pop(L, 1);
	}

	return 0;
}

// Register all memory functions with Lua
void add_memory_functions(lua_State* L) {
	if (!lua_istable(L, -1)) {
		luaL_error(L, "add_memory_functions failed: parent table does not exist");
	}

	// Read functions
	lua_pushstring(L, "readInt");
	lua_pushcfunction(L, read_int);
	lua_rawset(L, -3);

	lua_pushstring(L, "readBool");
	lua_pushcfunction(L, read_bool);
	lua_rawset(L, -3);

	lua_pushstring(L, "readDouble");
	lua_pushcfunction(L, read_double);
	lua_rawset(L, -3);

	lua_pushstring(L, "readFloat");
	lua_pushcfunction(L, read_float);
	lua_rawset(L, -3);

	lua_pushstring(L, "readString");
	lua_pushcfunction(L, read_string);
	lua_rawset(L, -3);

	lua_pushstring(L, "readPointer");
	lua_pushcfunction(L, read_pointer);
	lua_rawset(L, -3);

	lua_pushstring(L, "readByteArray");
	lua_pushcfunction(L, read_byte_array);
	lua_rawset(L, -3);

	// Write functions
	lua_pushstring(L, "writeInt");
	lua_pushcfunction(L, write_int);
	lua_rawset(L, -3);

	lua_pushstring(L, "writeBool");
	lua_pushcfunction(L, write_bool);
	lua_rawset(L, -3);

	lua_pushstring(L, "writeDouble");
	lua_pushcfunction(L, write_double);
	lua_rawset(L, -3);

	lua_pushstring(L, "writeFloat");
	lua_pushcfunction(L, write_float);
	lua_rawset(L, -3);

	lua_pushstring(L, "writeString");
	lua_pushcfunction(L, write_string);
	lua_rawset(L, -3);

	lua_pushstring(L, "writePointer");
	lua_pushcfunction(L, write_pointer);
	lua_rawset(L, -3);

	lua_pushstring(L, "writeByteArray");
	lua_pushcfunction(L, write_byte_array);
	lua_rawset(L, -3);
}