#include "stdafx.h"
#include "log.h"
#include "lua_helpers.h"

// Push any type to string
template <typename type2>
int push_tostring(lua_State* L, type2 n) {
	lua_getglobal(L, "tostring");
	lua_push<type2>(L, n);
	lua_call(L, 1, 1);

	return 1;
}

// LOG
template <typename type>
int log(lua_State* L, type n) {
	lua_getglobal(L, "LOG");
	lua_push<type>(L, n);
	lua_call(L, 1, 0);

	return 0;
}

// LOGF
template <typename type>
int logf(lua_State* L, std::string s, type n) {
	lua_getglobal(L, "LOGF");
	lua_pushstring(L, s.c_str());
	push_tostring<type>(L, n);
	lua_call(L, 2, 0);

	return 0;
}

int log(lua_State* L, std::string s)                  { return log<std::string>(L, s); }
int log(lua_State* L, const char* s)                  { return log<const char*>(L, s); }
int log(lua_State* L, int n)                          { return log<int>(L, n); }
int log(lua_State* L, unsigned int n)                 { return log<unsigned int>(L, n); }
int log(lua_State* L, bool b)                         { return log<bool>(L, b); }
int log(lua_State* L, char b)                         { return log<char>(L, b); }
int log(lua_State* L, BYTE b)                         { return log<BYTE>(L, b); }
int log(lua_State* L, float f)                        { return log<float>(L, f); }

int logf(lua_State* L, std::string s, std::string c)  { return logf<std::string>(L, s, c); }
int logf(lua_State* L, std::string s, const char* c)  { return logf<const char*>(L, s, c); }
int logf(lua_State* L, std::string s, int n)          { return logf<int>(L, s, n); }
int logf(lua_State* L, std::string s, unsigned int n) { return logf<unsigned int>(L, s, n); }
int logf(lua_State* L, std::string s, bool b)         { return logf<bool>(L, s, b); }
int logf(lua_State* L, std::string s, char b)         { return logf<bool>(L, s, b); }
int logf(lua_State* L, std::string s, BYTE b)         { return logf<BYTE>(L, s, b); }
int logf(lua_State* L, std::string s, float f)        { return logf<float>(L, s, f); }
