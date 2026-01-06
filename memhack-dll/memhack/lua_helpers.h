#ifndef LUA_HELPERS_H
#define LUA_HELPERS_H

#pragma once
#include "lua.hpp"

template <typename type>
type lua_to(lua_State* L, int index);

template <typename type>
void lua_push(lua_State* L, type value);

template <typename type>
void lua_checktype(lua_State* L, int index);

// Lua 5.1 equivalent of luaL_testudata
void* lua_testudata(lua_State* L, int idx, const char* tname);

#endif
