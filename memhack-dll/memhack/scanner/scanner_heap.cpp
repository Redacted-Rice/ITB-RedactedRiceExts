#include "stdafx.h"
#include "scanner_heap.h"
#include <cstdlib>

namespace ScannerHeap {
	// Global state vars
	static HANDLE g_scannerHeap = nullptr;
	// Heap base will be the same for all regions associated with this heap
	static uintptr_t g_heapBase = 0;
	static bool g_useCustomHeap = false;

	// Semi arbitrarily 20 MB to have space for a few scanners and their buffers
	const size_t INITIAL_HEAP_SIZE = 20 * 1024 * 1024;

	bool initialize() {
		// Create a private heap for scanner allocations
		// No serialization needed - we expect it be single threaded
		// Max size is unlimited (0)
		g_scannerHeap = HeapCreate(HEAP_NO_SERIALIZE, INITIAL_HEAP_SIZE, 0);

		if (!g_scannerHeap) {
			// Heap creation failed - fall back to regular allocator
			g_useCustomHeap = false;
			return false;
		}

		// Make a small allocation to determine the heap base address
		// The heap base will remain same for all regions associated
		// with this heap/alloc
		void* testAlloc = HeapAlloc(g_scannerHeap, 0, 16);
		if (testAlloc) {
			MEMORY_BASIC_INFORMATION mbi;
			if (VirtualQuery(testAlloc, &mbi, sizeof(mbi)) == sizeof(mbi)) {
				g_heapBase = (uintptr_t)mbi.AllocationBase;
			}
			HeapFree(g_scannerHeap, 0, testAlloc);
		}

		g_useCustomHeap = true;
		return true;
	}

	void cleanup() {
		if (g_scannerHeap) {
			HeapDestroy(g_scannerHeap);
			g_scannerHeap = nullptr;
			g_heapBase = 0;
			g_useCustomHeap = false;
		}
	}

	// Check if a memory region belongs to scanner heap
	// by checking allocation base which will be the same
	// for all regions associated with a heap
	bool isInScannerHeap(void* allocationBase) {
		if (!g_useCustomHeap || !g_scannerHeap) {
			return false;
		}
		return ((uintptr_t)allocationBase == g_heapBase);
	}

	void* allocate(size_t size) {
		if (g_useCustomHeap && g_scannerHeap) {
			// Allocate from scanner heap
			void* ptr = HeapAlloc(g_scannerHeap, 0, size);
			if (ptr) {
				return ptr;
			}
			// Fall through to malloc if HeapAlloc fails
		}

		// Fallback to regular heap allocation
		return malloc(size);
	}

	void deallocate(void* ptr, size_t size) {
		if (!ptr) return;

		if (g_useCustomHeap && g_scannerHeap) {
			// Check if this pointer came from our scanner heap
			// We can check this by querying the memory region
			MEMORY_BASIC_INFORMATION mbi;
			if (VirtualQuery(ptr, &mbi, sizeof(mbi)) == sizeof(mbi)) {
				if ((uintptr_t)mbi.AllocationBase == g_heapBase) {
					// This allocation came from our heap
					HeapFree(g_scannerHeap, 0, ptr);
					return;
				}
			}
		}

		// Fallback to free from regular heap
		free(ptr);
	}
}
