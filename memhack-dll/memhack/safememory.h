#ifndef SAFE_MEMORY_H
#define SAFE_MEMORY_H

#include <windows.h>
#include <cstddef>
namespace SafeMemory {
    struct Region { uintptr_t base; size_t size; };

    bool is_mbi_safe(MEMORY_BASIC_INFORMATION& mbi, bool write = true);

    bool is_access_allowed(void* addr, size_t size, bool write = true);

    std::vector<Region> get_heap_regions(bool write = true);
}

#endif
