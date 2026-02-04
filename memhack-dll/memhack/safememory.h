#ifndef SAFE_MEMORY_H
#define SAFE_MEMORY_H

#include <windows.h>
#include <cstddef>
namespace SafeMemory {
    struct Region { uintptr_t base; size_t size; };

    bool is_mbi_safe(MEMORY_BASIC_INFORMATION& mbi, bool write = true);

    bool is_access_allowed(void* addr, size_t size, bool write = true);

    // Returns the number of bytes that can be safely accessed from addr
    // Returns 0 if addr is not accessible
    size_t get_accessible_size(void* addr, size_t requested_size, bool write = true);

    std::vector<Region> get_heap_regions(bool write = true);
}

#endif
