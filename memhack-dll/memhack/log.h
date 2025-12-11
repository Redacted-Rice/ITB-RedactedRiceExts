#ifndef LOG_H
#define LOG_H

#include "lua.hpp"
#include <string>

int log(lua_State* L, std::string);
int log(lua_State* L, const char*);
int log(lua_State* L, int);
int log(lua_State* L, unsigned int);
int log(lua_State* L, bool);
int log(lua_State* L, char);
int log(lua_State* L, BYTE);
int log(lua_State* L, float);

int logf(lua_State* L, std::string, std::string);
int logf(lua_State* L, std::string, const char*);
int logf(lua_State* L, std::string, int);
int logf(lua_State* L, std::string, unsigned int);
int logf(lua_State* L, std::string, bool);
int logf(lua_State* L, std::string, char);
int logf(lua_State* L, std::string, BYTE);
int logf(lua_State* L, std::string, float);

#endif
