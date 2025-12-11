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

#endif
