#include "stdafx.h"
#include "memory.h"
#include "safememory.h"
#include "lua_helpers.h"

static bool READ_ONLY = false;
static bool READ_WRITE = true;


int max_cstring_length(lua_State* L) {
	lua_pushinteger(L, MAX_CSTRING_LENGTH);
	return 1;
}

int max_byte_array_length(lua_State* L) {
	return 1;
}

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

int read_cstring(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	int max_length = luaL_checkinteger(L, 2);
	
	// Validate max_length (including null terminator)
	if (max_length <= 0) {
		luaL_error(L, "read_cstring failed: max_length must be positive");
		return 0;
	} else if (max_length > MAX_CSTRING_LENGTH) {
		luaL_error(L, "read_cstring failed: max_length cannot exceed %d (including null terminator), got %d", MAX_CSTRING_LENGTH, max_length);
		return 0;
	// Validate we can read the max length. Unfortunately we don't know the length
	// until we read the null term. We could check each byte as we go but for simplicity
	// and speed just assume max length
	} else if (!SafeMemory::is_access_allowed(addr, max_length, READ_ONLY)) {
		luaL_error(L, "read_cstring failed: read from address 0x%p ([max] len %d) not allowed", addr, max_length);
		return 0;
	}
	
	std::string result;
	// Pre-allocate reasonable size. Most strings should be short
	result.reserve(128);
	
	// Read until we hit null terminator or max_length
	unsigned char* bytes = (unsigned char*)addr;
	for (int i = 0; i < max_length; i++) {
		unsigned char byte = bytes[i];
		
		// If we hit null terminator, we're done
		if (byte == 0) {
			break;
		}
		result.push_back((char)byte);
	}
	
	// note - std::string doesn't need us to add null term
	lua_pushstring(L, result.c_str());
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

int write_cstring(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	const char* value = luaL_checkstring(L, 2);
	int max_length = luaL_checkinteger(L, 3);
	
	// Validate max_length (including null terminator)
	if (max_length <= 0) {
		luaL_error(L, "write_cstring failed: max_length must be positive");
		return -1;
	} else if (max_length > MAX_CSTRING_LENGTH) {
		luaL_error(L, "write_cstring failed: max_length cannot exceed %d (including null terminator), got %d", MAX_CSTRING_LENGTH, max_length);
		return -1;
	}
	
	// Get the actual length of the string (including null terminator) and ensure it's within the allowed value
	size_t length = strlen(value) + 1;
	if (length > (size_t)max_length) {
		luaL_error(L, "write_cstring failed: string length %zu exceeds max_length %d", length, max_length);
		return -1;
	}
	
	// Validate memory access
	if (!SafeMemory::is_access_allowed(addr, length, READ_WRITE)) {
		luaL_error(L, "write_cstring failed: write to address 0x%p (len %zu) not allowed", addr, length);
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

// Check if memory is readable
int is_readable(lua_State* L) {
	void* addr = (void*)luaL_checkinteger(L, 1);
	int size = luaL_checkinteger(L, 2);
	
	if (size <= 0) {
		lua_pushboolean(L, false);
		return 1;
	}
	
	bool readable = SafeMemory::is_access_allowed(addr, size, READ_ONLY);
	lua_pushboolean(L, readable);
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

	lua_pushstring(L, "readCString");
	lua_pushcfunction(L, read_cstring);
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

	lua_pushstring(L, "writeCString");
	lua_pushcfunction(L, write_cstring);
	lua_rawset(L, -3);

	lua_pushstring(L, "writePointer");
	lua_pushcfunction(L, write_pointer);
	lua_rawset(L, -3);

	lua_pushstring(L, "writeByteArray");
	lua_pushcfunction(L, write_byte_array);
	lua_rawset(L, -3);

	lua_pushstring(L, "isReadable");
	lua_pushcfunction(L, is_readable);
	lua_rawset(L, -3);
}