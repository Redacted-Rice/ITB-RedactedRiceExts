#ifndef ITB_USERDATA_H
#define ITB_USERDATA_H

#include "lua.hpp"

// Should work for more data types but so far only have had use for c strings
// 
// Owner template for single objects
template <typename T>
struct Owner {
	std::unique_ptr<T> obj;
	explicit Owner(T* p) : obj(p) {}
	T* get() const { return obj.get(); }
};

// Owner template for arrays (c strings)
template <typename T>
struct Owner<T[]> {
	std::unique_ptr<T[]> buf;
	explicit Owner(T* p) : buf(p) {}
	T* get() const { return buf.get(); }
};

// Create and push data as ItB userdata
template <typename T>
int push_itb_userdata(lua_State* L, Owner<T>* owner, const char* mtname) {
	// Mimic the structure used by ItB user data so we can handle it like other userdata
	void** inner = new void* [3];
	inner[0] = owner;
	inner[1] = nullptr;
	// Important - this is where the address lives!
	inner[2] = owner->get();

	auto** userdata = static_cast<void***>(lua_newuserdata(L, sizeof(void**)));
	*userdata = inner;

	if (luaL_newmetatable(L, mtname)) {
		// Define GC so we can clean up and avoid memory leak
		lua_pushstring(L, "__gc");
		lua_pushcfunction(L, [](lua_State* L) -> int {
			auto** userdata_ptr = static_cast<void***>(lua_touserdata(L, 1));
			if (userdata_ptr && *userdata_ptr) {
				auto* owner = static_cast<Owner<T>*>((*userdata_ptr)[0]);
				// frees buffer/object via unique_ptr
				delete owner;
				// frees triple array
				delete[] * userdata_ptr;
				*userdata_ptr = nullptr;
			}
			return 0;
			});
		lua_settable(L, -3);
	}
	lua_setmetatable(L, -2);

	return 1;
};

#endif