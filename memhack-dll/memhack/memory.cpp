#include "stdafx.h"
#include "memory.h"
#include "safememory.h"
#include "lua_helpers.h"

static bool READ_ONLY = false;
static bool READ_WRITE = true;


// Misc memory functions
int get_userdata_addr(lua_State* L) {
	luaL_checktype(L, 1, LUA_TUSERDATA);
	void*** userdata = (void***)lua_touserdata(L, 1);

	if (userdata == NULL) {
		luaL_error(L, "invalid userdata");
	}

	size_t addr = (size_t)userdata[0][2];
	lua_pushinteger(L, addr);
	return 1;
}

int alloc_cstring(lua_State* L) {
	size_t len;
	const char* src = luaL_checklstring(L, 1, &len);

	if (len + 1 > MAX_CSTRING_LENGTH) {
		luaL_error(L, "alloc_cstring failed: max_length cannot exceed %d (including null terminator), got %d", MAX_CSTRING_LENGTH, len + 1);
		return 0;
	}

	char* raw = new char[len + 1];
	std::memcpy(raw, src, len);
	raw[len] = '\0';

	auto* owner = new Owner<char[]>(raw);
	return push_itb_userdata(L, owner, "UserdataMemhackCString");
}

int alloc_byte_array(lua_State* L) {
	int length = luaL_checkinteger(L, 1);

	if (length > MAX_BYTE_ARRAY_LENGTH) {
		luaL_error(L, "alloc_byte_array failed: max_length cannot exceed %d, got %d", MAX_BYTE_ARRAY_LENGTH, length);
		return 0;
	}

	unsigned char* raw = new unsigned char[length + 1];
	std::memset(raw, 0, length);

	auto* owner = new Owner<unsigned char[]>(raw);
	return push_itb_userdata(L, owner, "UserdataMemhackByteArray");
}

// Read functions - return the value at the given address
int read_byte(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	if (!SafeMemory::is_access_allowed(addr, sizeof(unsigned char), READ_ONLY)) {
		luaL_error(L, "read_byte failed: read from address 0x%p not allowed", addr);
		return 0;
	}
	lua_pushinteger(L, *(unsigned char*)addr);
	return 1;
}

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

// Reads a null-terminated string from memory
// Handles partial memory access by reading what's available and checking for null terminator
int read_null_term_string(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	int max_length = luaL_checkinteger(L, 2);

	// Validate max_length (including null terminator)
	if (max_length <= 0) {
		luaL_error(L, "read_null_term_string failed: max_length must be positive");
		return 0;
	} else if (max_length > MAX_CSTRING_LENGTH) {
		luaL_error(L, "read_null_term_string failed: max_length cannot exceed %d (including null terminator), got %d", MAX_CSTRING_LENGTH, max_length);
		return 0;
	}

	// Get the number of bytes we can actually read up to max length
	size_t accessible_size = SafeMemory::get_accessible_size(addr, max_length, READ_ONLY);
	if (accessible_size == 0) {
		luaL_error(L, "read_null_term_string failed: read from address 0x%p not allowed", addr);
		return 0;
	}

	// Use strnlen to find the actual string length
	const char* str_ptr = (const char*)addr;
	size_t str_len = strnlen(str_ptr, accessible_size);

	// If we didn't find a null terminator within accessible memory we failed to read it
	if (str_len == accessible_size && accessible_size < (size_t)max_length) {
		luaL_error(L, "read_null_term_string failed: no null terminator found in accessible memory (0x%p, accessible: %zu, requested: %d)",
			addr, accessible_size, max_length);
		return 0;
	}

	// Return the found string
	lua_pushlstring(L, str_ptr, str_len);
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

	// Return as Lua string (can handle non-null terminated binary data)
	const char* bytes = (const char*)addr;
	lua_pushlstring(L, bytes, length);

	return 1;
}

// Write functions - write a value to the given address
int write_byte(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	int value = luaL_checkinteger(L, 2);

	// Ensure the value is good and access is allowed
	if (value < 0 || value > 255) {
		luaL_error(L, "write_byte failed: passed value is not in range 0 - 255", value);
	} else if (!SafeMemory::is_access_allowed(addr, sizeof(unsigned char), READ_WRITE)) {
		luaL_error(L, "write_byte failed: write to address 0x%p not allowed", addr);
		return -1;
	}

	*(unsigned char*)addr = (unsigned char)value;
	return 0;
}

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

int write_null_term_string(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	const char* value = luaL_checkstring(L, 2);
	int max_length = luaL_checkinteger(L, 3);

	// Validate max_length (including null terminator)
	if (max_length <= 0) {
		luaL_error(L, "write_null_term_string failed: max_length must be positive");
		return -1;
	} else if (max_length > MAX_CSTRING_LENGTH) {
		luaL_error(L, "write_null_term_string failed: max_length cannot exceed %d (including null terminator), got %d", MAX_CSTRING_LENGTH, max_length);
		return -1;
	}

	// Get the actual length of the string (including null terminator) and ensure it's within the allowed value
	size_t length = strlen(value) + 1;
	if (length > (size_t)max_length) {
		luaL_error(L, "write_null_term_string failed: string length %zu exceeds max_length %d", length, max_length);
		return -1;
	}

	// Validate memory access
	if (!SafeMemory::is_access_allowed(addr, length, READ_WRITE)) {
		luaL_error(L, "write_null_term_string failed: write to address 0x%p (len %zu) not allowed", addr, length);
		return -1;
	}

	// Copy the data over
	unsigned char* bytes = (unsigned char*)addr;
	memcpy(bytes, value, length);

	return 0;
}

int write_pointer(lua_State* L) {
	return write_int(L);
}

int write_byte_array(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);

	// Accept string for byte array
	if (!lua_isstring(L, 2)) {
		luaL_error(L, "write_byte_array failed: expected string for byte array data");
		return -1;
	}

	size_t length;
	const char* data = lua_tolstring(L, 2, &length);

	if (length < 0) {
		luaL_error(L, "write_byte_array failed: length must be non-negative");
		return -1;
	}

	if (!SafeMemory::is_access_allowed(addr, (int)length, READ_WRITE)) {
		luaL_error(L, "write_byte_array failed: write to address 0x%p (len %zu) not allowed", addr, length);
		return -1;
	}

	// Copy the string data to memory
	memcpy(addr, data, length);

	return 0;
}

// Expose SafeMemory functions
int safe_is_access_allowed(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	int size = luaL_checkinteger(L, 2);
	bool write = lua_toboolean(L, 3);  // Optional, defaults to false (read-only)

	if (size <= 0) {
		lua_pushboolean(L, false);
		return 1;
	}

	bool allowed = SafeMemory::is_access_allowed(addr, size, write);
	lua_pushboolean(L, allowed);
	return 1;
}

int safe_get_accessible_size(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	int requested_size = luaL_checkinteger(L, 2);
	bool write = lua_toboolean(L, 3);  // Optional, defaults to false (read-only)

	if (requested_size <= 0) {
		lua_pushinteger(L, 0);
		return 1;
	}

	size_t accessible = SafeMemory::get_accessible_size(addr, requested_size, write);
	lua_pushinteger(L, (int)accessible);
	return 1;
}

// Register all memory functions with Lua
void add_memory_functions(lua_State* L) {
	if (!lua_istable(L, -1)) {
		luaL_error(L, "add_memory_functions failed: parent table does not exist");
	}

	lua_pushstring(L, "MAX_CSTRING_LENGTH");
	lua_pushinteger(L, MAX_CSTRING_LENGTH);
	lua_rawset(L, -3);

	lua_pushstring(L, "MAX_BYTE_ARRAY_LENGTH");
	lua_pushinteger(L, MAX_BYTE_ARRAY_LENGTH);
	lua_rawset(L, -3);

	lua_pushstring(L, "getUserdataAddr");
	lua_pushcfunction(L, get_userdata_addr);
	lua_rawset(L, -3);

	lua_pushstring(L, "getUserdataAddr");
	lua_pushcfunction(L, get_userdata_addr);
	lua_rawset(L, -3);

	lua_pushstring(L, "allocCString");
	lua_pushcfunction(L, alloc_cstring);
	lua_rawset(L, -3);

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

	lua_pushstring(L, "readByte");
	lua_pushcfunction(L, read_byte);
	lua_rawset(L, -3);

	lua_pushstring(L, "readNullTermString");
	lua_pushcfunction(L, read_null_term_string);
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

	lua_pushstring(L, "writeByte");
	lua_pushcfunction(L, write_byte);
	lua_rawset(L, -3);

	lua_pushstring(L, "writeNullTermString");
	lua_pushcfunction(L, write_null_term_string);
	lua_rawset(L, -3);

	lua_pushstring(L, "writePointer");
	lua_pushcfunction(L, write_pointer);
	lua_rawset(L, -3);

	lua_pushstring(L, "writeByteArray");
	lua_pushcfunction(L, write_byte_array);
	lua_rawset(L, -3);

	// Safe memory functions
	lua_pushstring(L, "isAccessAllowed");
	lua_pushcfunction(L, safe_is_access_allowed);
	lua_rawset(L, -3);

	lua_pushstring(L, "getAccessibleSize");
	lua_pushcfunction(L, safe_get_accessible_size);
	lua_rawset(L, -3);
}