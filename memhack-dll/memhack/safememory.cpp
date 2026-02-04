#include "stdafx.h"
#include "safememory.h"
#include <cstring>
#include <iostream>

namespace SafeMemory {
    bool is_mbi_safe(MEMORY_BASIC_INFORMATION& mbi, bool write) {
        // Early exit on most common failure cases
        if (mbi.State != MEM_COMMIT) return false;
        if (write && mbi.Type != MEM_PRIVATE) return false;
        if (mbi.Protect & (PAGE_GUARD | PAGE_NOACCESS)) return false;

        // Check access permissions (write or read-only)
        if (write) {
            return (mbi.Protect & PAGE_READWRITE) != 0;
        } else {
            return (mbi.Protect & (PAGE_READWRITE | PAGE_READONLY | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE)) != 0;
        }
    }

    bool is_access_allowed(void* addr, size_t size, bool write) {
        MEMORY_BASIC_INFORMATION mbi;
        if (VirtualQuery(addr, &mbi, sizeof(mbi)) != sizeof(mbi)) {
            return false;
        }

        if (!is_mbi_safe(mbi, write)) {
            return false;
        }

        // Ensure requested size fits inside region
        if ((BYTE*)addr + size > (BYTE*)mbi.BaseAddress + mbi.RegionSize)
            return false;

        return true;
    }

    size_t get_accessible_size(void* addr, size_t requested_size, bool write) {
        MEMORY_BASIC_INFORMATION mbi;
        if (VirtualQuery(addr, &mbi, sizeof(mbi)) != sizeof(mbi)) {
            return 0;
        }

        if (!is_mbi_safe(mbi, write)) {
            return 0;
        }

        // Calculate how many bytes are accessible from addr to end of region
        BYTE* region_end = (BYTE*)mbi.BaseAddress + mbi.RegionSize;
        BYTE* addr_bytes = (BYTE*)addr;

        // If addr is beyond region, return 0
        if (addr_bytes >= region_end) {
            return 0;
        }
        size_t available = region_end - addr_bytes;

        // Return the smaller of requested_size or available
        return (requested_size < available) ? requested_size : available;
    }

    std::vector<Region> get_heap_regions(bool write) {
        std::vector<Region> out;
        SYSTEM_INFO si;
        GetSystemInfo(&si);

        // For 32-bit Into the Breach: user space typically up to ~0x7FFE0000
        uintptr_t addr = (uintptr_t)si.lpMinimumApplicationAddress;
        uintptr_t end = (uintptr_t)si.lpMaximumApplicationAddress;

        while (addr < end) {
            MEMORY_BASIC_INFORMATION mbi{};
            SIZE_T r = VirtualQuery((LPCVOID)addr, &mbi, sizeof(mbi));
            if (r != sizeof(mbi)) break;

            if (is_mbi_safe(mbi, write)) {
                out.push_back({
                    (uintptr_t)mbi.BaseAddress,
                    (size_t)mbi.RegionSize,
                    });
            }
            addr = (uintptr_t)mbi.BaseAddress + (uintptr_t)mbi.RegionSize;
        }
        return out;
    }
}