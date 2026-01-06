#include "stdafx.h"
#include "lua_helpers.h"

template <typename type>
type lua_to(lua_State* L, int index) { return lua_tointeger(L, index); }

template int lua_to<int>(lua_State* L, int index);
template unsigned int lua_to<unsigned int>(lua_State* L, int index);
template unsigned char lua_to<unsigned char>(lua_State* L, int index);

template <>
bool lua_to<bool>(lua_State* L, int index) { return lua_toboolean(L, index); }
template <>
double lua_to<double>(lua_State* L, int index) { return lua_tonumber(L, index); }
template <>
float lua_to<float>(lua_State* L, int index) { return lua_tonumber(L, index); }
template <>
const char* lua_to<const char*>(lua_State* L, int index) { return lua_tostring(L, index); }
template <>
std::string lua_to<std::string>(lua_State* L, int index) { return std::string(lua_tostring(L, index)); }

template <typename type>
void lua_push(lua_State* L, type value) { lua_pushinteger(L, value); }
template <>
void lua_push<int>(lua_State* L, int value) { lua_pushinteger(L, value); } 
template <>
void lua_push<bool>(lua_State* L, bool value) { lua_pushboolean(L, value); }
template <>
void lua_push<char>(lua_State* L, char value) { lua_pushinteger(L, value); }
template <>
void lua_push<unsigned int>(lua_State* L, unsigned int value) { lua_pushinteger(L, value); }
template <>
void lua_push<unsigned char>(lua_State* L, unsigned char value) { lua_pushinteger(L, value); }
template <>
void lua_push<double>(lua_State* L, double value) { lua_pushnumber(L, value); }
template <>
void lua_push<float>(lua_State* L, float value) { lua_pushnumber(L, value); }
template <>
void lua_push<const char*>(lua_State* L, const char* value) { lua_pushstring(L, value); }
template <>
void lua_push<std::string*>(lua_State* L, std::string* value) { lua_pushstring(L, value->c_str()); }
template <>
void lua_push<std::string>(lua_State* L, std::string value) { lua_pushstring(L, value.c_str()); }

template <typename type>
void lua_checktype(lua_State* L, int index) {
	luaL_checktype(L, index, LUA_TNUMBER);
}
template void lua_checktype<int>(lua_State* L, int index);
template void lua_checktype<unsigned char>(lua_State* L, int index);
template void lua_checktype<unsigned int>(lua_State* L, int index);
template void lua_checktype<double>(lua_State* L, int index);
template void lua_checktype<float>(lua_State* L, int index);

template <>
void lua_checktype<bool>(lua_State* L, int index) {
	luaL_checktype(L, index, LUA_TBOOLEAN);
}
template <>
void lua_checktype<const char*>(lua_State* L, int index) {
	luaL_checktype(L, index, LUA_TSTRING);
}

// Lua 5.1 equivalent of luaL_testudata
void* lua_testudata(lua_State* L, int idx, const char* tname) {
    void* p = lua_touserdata(L, idx);
    if (!p) return NULL;

    if (lua_getmetatable(L, idx)) {
        luaL_getmetatable(L, tname);
        bool equal = lua_rawequal(L, -1, -2);
        lua_pop(L, 2);
        return equal ? p : NULL;
    }
    return NULL;
}