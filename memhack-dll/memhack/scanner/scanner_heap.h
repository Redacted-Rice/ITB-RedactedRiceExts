#ifndef SCANNER_HEAP_H
#define SCANNER_HEAP_H

#include <cstddef>
#include <cstdint>
#include <Windows.h>

// Scanner Heap Manager to allow separating the scanner memory from scans
// Provides a dedicated heap for scanner and all its allocations. Scanners
// can then get the heap info and skip it while scanning
namespace ScannerHeap {
	// Initialize the scanner heap
	// Returns true if successful, false if fallback to regular heap
	bool initialize();

	// Cleanup the scanner heap
	void cleanup();

	// Check if a memory region belongs to the scanner heap
	bool isInScannerHeap(void* allocationBase);

	// Memory management functions for ScannerAllocator
	void* allocate(size_t size);
	void deallocate(void* ptr, size_t size);
}

// STL-compatible allocator that uses the scanner heap
// This ensures all scanner STL containers allocate from the dedicated heap
template<typename T>
class ScannerAllocator {
public:
	using value_type = T;
	using pointer = T*;
	using const_pointer = const T*;
	using reference = T&;
	using const_reference = const T&;
	using size_type = size_t;
	using difference_type = ptrdiff_t;

	// Rebind allocator to different type (required by STL)
	template<typename U>
	struct rebind {
		using other = ScannerAllocator<U>;
	};

	// Constructors
	ScannerAllocator() noexcept {}
	ScannerAllocator(const ScannerAllocator&) noexcept {}
	template<typename U>
	ScannerAllocator(const ScannerAllocator<U>&) noexcept {}

	// Allocate n objects of type T
	T* allocate(size_t n) {
		if (n == 0) return nullptr;
		if (n > static_cast<size_t>(-1) / sizeof(T)) {
			throw std::bad_alloc();
		}
		void* ptr = ScannerHeap::allocate(n * sizeof(T));
		if (!ptr) {
			throw std::bad_alloc();
		}
		return static_cast<T*>(ptr);
	}

	// Deallocate n objects of type T
	void deallocate(T* p, size_t n) noexcept {
		if (p) {
			ScannerHeap::deallocate(p, n * sizeof(T));
		}
	}

	// Comparison operators (all allocators of same type are equal)
	template<typename U>
	bool operator==(const ScannerAllocator<U>&) const noexcept {
		return true;
	}

	template<typename U>
	bool operator!=(const ScannerAllocator<U>&) const noexcept {
		return false;
	}
};

#endif
