#include "stdafx.h"
#include "scanner_base.h"
#include "scanner_sequence.h"
#include "scanner_basic.h"
#include "scanner_basic_avx2.h"
#include "../safememory.h"

#include <algorithm>
#include <windows.h>
#include <sysinfoapi.h>
#include <omp.h>


void* Scanner::operator new(size_t size) {
	return ScannerHeap::allocate(size);
}

void Scanner::operator delete(void* ptr) noexcept {
	if (ptr) {
		ScannerHeap::deallocate(ptr, 0);
	}
}

// Static methods for thread control
void Scanner::setNumThreads(int numThreads) {
	if (numThreads == 0) {
		// Auto mode - use all available cores
		omp_set_num_threads(omp_get_max_threads());
	} else if (numThreads > 0) {
		// Specific thread count
		omp_set_num_threads(numThreads);
	}
	// Negative values ignored
}

int Scanner::getNumThreads() {
	return omp_get_num_threads();
}

int Scanner::getMaxThreads() {
	return omp_get_max_threads();
}

// Base constructor - common initialization for all scanners
Scanner::Scanner(DataType dataType, size_t maxResults, size_t alignment) :
	dataType(dataType), maxResults(maxResults), alignment(alignment), firstScanDone(false),
	maxResultsReached(false), checkTiming(false), lastScanType(ScanType::EXACT), invalidAddressCount(0)
{
	// Always allow at least one result
	if (maxResults == 0) {
		addError("maxResults cannot be 0, defaulting to 1");
		this->maxResults = 1;
	}

	// Pre-allocate a reasonable amount
	results.reserve(std::min<size_t>(this->maxResults, 10000));
}

// Factory method to create appropriate scanner based on data type
Scanner* Scanner::create(DataType dataType, size_t maxResults, size_t alignment) {
	// Determine if this is a sequence type
	bool isSequence = (dataType == DataType::STRING || dataType == DataType::BYTE_ARRAY);

	if (isSequence) {
		return new SequenceScanner(dataType, maxResults, alignment);
	} else {
		// Check if AVX2 is available for basic types
		if (BasicScannerAVX2::isAVX2Supported()) {
			return new BasicScannerAVX2(dataType, maxResults, alignment);
		} else {
			return new BasicScanner(dataType, maxResults, alignment);
		}
	}
}

// Template method for first scan - handles common setup and timing
void Scanner::firstScan(ScanType scanType, const void* targetValue, size_t valueSize) {
	// Start timing if enabled
	ULONGLONG startTime = 0;
	if (checkTiming) {
		startTime = GetTickCount64();
	}

	// Common validation
	if (firstScanDone) {
		addError("First scan already performed - use reset() first or create new scanner");
		return;
	}

	// These types require a previous scan
	if (scanType == ScanType::INCREASED || scanType == ScanType::DECREASED ||
	    scanType == ScanType::CHANGED || scanType == ScanType::UNCHANGED) {
		addError("First scan cannot use INCREASED/DECREASED/CHANGED/UNCHANGED - these require a previous scan. Use EXACT or NOT for first scan.");
		return;
	}

	// Clear results and prepare for scan
	results.clear();
	maxResultsReached = false;
	clearErrors();
	invalidAddressCount = 0;
	lastScanType = scanType;

	// Call scanner-specific setup (e.g., store search sequence for strings)
	if (!setupScanCommon(scanType, targetValue, valueSize)) {
		return;  // Setup failed, error already logged by derived class
	}

	// Call scanner-specific implementation
	firstScanImpl(scanType, targetValue, valueSize);

	// Mark as done
	firstScanDone = true;
	reportInvalidAddressStats();

	// Report timing if enabled
	if (checkTiming) {
		ULONGLONG endTime = GetTickCount64();
		ULONGLONG elapsed = endTime - startTime;
		addError("firstScan timing: %llu ms (%zu results found)", elapsed, results.size());
	}
}

// Base method for rescan - handles common setup and timing
void Scanner::rescan(ScanType scanType, const void* targetValue, size_t valueSize) {
	// Start timing if enabled
	ULONGLONG startTime = 0;
	if (checkTiming) {
		startTime = GetTickCount64();
	}

	// Common validation
	if (!firstScanDone) {
		addError("Must perform first scan before rescanning");
		return;
	}

	if (results.empty()) {
		addError("No previous results to rescan");
		return;
	}

	// Prepare for rescan
	clearErrors();
	invalidAddressCount = 0;
	lastScanType = scanType;

	// Call scanner-specific setup (e.g., update search sequence for strings)
	if (!setupScanCommon(scanType, targetValue, valueSize)) {
		return;  // Setup failed, error already logged by derived class
	}

	// Sort results by address for efficient processing
	std::stable_sort(results.begin(), results.end(), [](const ScanResult& a, const ScanResult& b) {
		return a.address < b.address;
	});

	// Call scanner-specific implementation
	rescanImpl(scanType, targetValue, valueSize);

	// Report stats
	reportInvalidAddressStats();

	// Report timing if enabled
	if (checkTiming) {
		ULONGLONG endTime = GetTickCount64();
		ULONGLONG elapsed = endTime - startTime;
		addError("rescan timing: %llu ms (%zu results remaining)", elapsed, results.size());
	}
}

// Enumerate all safe memory regions for parallel scanning
std::vector<MemoryRegion> Scanner::enumerateSafeRegions() {
	std::vector<MemoryRegion> regions;

	SYSTEM_INFO si;
	GetSystemInfo(&si);

	uintptr_t addr = (uintptr_t)si.lpMinimumApplicationAddress;
	uintptr_t end = (uintptr_t)si.lpMaximumApplicationAddress;

	while (addr < end) {
		MEMORY_BASIC_INFORMATION mbi{};
		SIZE_T r = VirtualQuery((LPCVOID)addr, &mbi, sizeof(mbi));
		if (r != sizeof(mbi)) break;

		// Skip scanner heap to avoid detecting scanner's own memory
		if (!ScannerHeap::isInScannerHeap(mbi.AllocationBase)) {
			// Check if region is safe for reading
			if (SafeMemory::is_mbi_safe(mbi, false)) {
				regions.emplace_back((uintptr_t)mbi.BaseAddress, (size_t)mbi.RegionSize);
			}
		}

		addr = (uintptr_t)mbi.BaseAddress + (uintptr_t)mbi.RegionSize;
	}

	return regions;
}

// Default first scan implementation - parallel region scanning
void Scanner::firstScanImpl(ScanType scanType, const void* targetValue, size_t valueSize) {
	// Call hook for scanner-specific scan type validation
	if (!validateFirstScanType(scanType)) {
		return;
	}

	// Enumerate all safe regions
	std::vector<MemoryRegion> regions = enumerateSafeRegions();

	if (regions.empty()) {
		addError("No scannable memory regions found");
		return;
	}

	// Parallel scan using OpenMP
	#pragma omp parallel
	{
		// Thread-local allocations (NOT on scanner heap - avoids contention)
		std::vector<uint8_t> localBuffer(SCAN_BUFFER_SIZE);
		std::vector<ScanResult> localResults;
		localResults.reserve(10000);

		// Process regions in parallel
		#pragma omp for schedule(dynamic, 1) nowait
		for (int i = 0; i < (int)regions.size(); i++) {
			// Check if max results already reached (reading bool is atomic on x86/x64)
			if (maxResultsReached) {
				continue;
			}

			const MemoryRegion& region = regions[i];
			size_t maxLocal = maxResults; // Each thread can collect up to max

			// Scan region into thread-local results
			scanRegion(region.base, region.size, scanType, targetValue,
			          localBuffer, localResults, maxLocal);
		}

		// Merge local results into shared results (with strict limit enforcement)
		if (!localResults.empty()) {
			#pragma omp critical
			{
				// Double-check we haven't already reached limit (another thread might have filled it)
				if (results.size() < maxResults) {
					size_t remainingSpace = maxResults - results.size();
					size_t toAdd = std::min<size_t>(remainingSpace, localResults.size());
					results.insert(results.end(), localResults.begin(), localResults.begin() + toAdd);

					if (results.size() >= maxResults) {
						maxResultsReached = true;
					}
				}
			}
		}
	}

	if (maxResultsReached) {
		addError("Maximum results (%zu) reached, stopping scan early", maxResults);
	}
}

// Scan a single region in buffered chunks into local results
void Scanner::scanRegion(uintptr_t base, size_t size, ScanType scanType, const void* targetValue,
                          std::vector<uint8_t>& buffer, std::vector<ScanResult>& localResults, size_t maxLocalResults) {
	if (size == 0 || alignment == 0) {
		return;
	}

	const size_t dataSize = getDataTypeSize();
	uintptr_t regionEnd = base + size;
	uintptr_t currentBase = base;

	// Scan region in buffered chunks with overlap
	while (currentBase < regionEnd && localResults.size() < maxLocalResults) {
		size_t chunkSize = std::min<size_t>(SCAN_BUFFER_SIZE, regionEnd - currentBase);

		// Copy chunk with SEH protection
		if (!safeCopyMemory(buffer.data(), (const void*)currentBase, chunkSize)) {
			currentBase += chunkSize;
			continue;
		}

		// Scan chunk into local results
		size_t remainingSpace = maxLocalResults - localResults.size();
		scanChunkInRegion(buffer.data(), chunkSize, currentBase, scanType, targetValue,
		                  localResults, remainingSpace);

		// Move to next chunk with overlap
		currentBase += chunkSize;
		if (dataSize > 1 && currentBase < regionEnd) {
			size_t overlap = std::min<size_t>(dataSize - 1, chunkSize);
			currentBase -= overlap;
		}
	}
}

// Default rescan implementation - handles common JIT region processing loop
void Scanner::rescanImpl(ScanType scanType, const void* targetValue, size_t valueSize) {
	// Allocate buffer for chunk-based reading using scanner heap
	// We use CHUNK_THRESHOLD for rescans since we only batch results within that distance
	// ALlocated it once and reuse it
	std::vector<uint8_t, ScannerAllocator<uint8_t>> buffer(CHUNK_THRESHOLD);

	std::vector<ScanResult, ScannerAllocator<ScanResult>> newResults;
	newResults.reserve(results.size());

	// Walk through results dynamically, querying regions JIT (like initial scan)
	size_t resultIdx = 0;
	while (resultIdx < results.size()) {
		ScanResult& result = results[resultIdx];

		// Query the memory region for this result address (JIT approach)
		MEMORY_BASIC_INFORMATION mbi{};
		if (VirtualQuery((LPCVOID)result.address, &mbi, sizeof(mbi)) != sizeof(mbi)) {
			// Failed to query - address invalid
			invalidAddressCount++;
			resultIdx++;
			continue;
		}

		// We don't need to check the scanners heap again as this are matches and
		// the scanner heap was excluded from the initial scan

		// Check if region is safe for reading
		if (!SafeMemory::is_mbi_safe(mbi, false)) {
			// Region not safe - skip results in this entire region
			uintptr_t regionEnd = (uintptr_t)mbi.BaseAddress + (uintptr_t)mbi.RegionSize;
			while (resultIdx < results.size() && results[resultIdx].address < regionEnd) {
				invalidAddressCount++;
				resultIdx++;
			}
			continue;
		}

		// Region is safe - call derived class to process results in this region
		processResultsInRegion(mbi, resultIdx, scanType, targetValue, newResults, buffer);
	}

	// Replace results with filtered results
	results = std::move(newResults);
}

// Process results in a single memory region for rescan
void Scanner::processResultsInRegion(MEMORY_BASIC_INFORMATION& mbi, size_t& resultIdx,
                                      ScanType scanType, const void* targetValue,
                                      std::vector<ScanResult, ScannerAllocator<ScanResult>>& newResults,
                                      std::vector<uint8_t, ScannerAllocator<uint8_t>>& buffer) {
	// Cache data type size
	const size_t dataSize = getDataTypeSize();

	uintptr_t regionBase = (uintptr_t)mbi.BaseAddress;
	uintptr_t regionEnd = regionBase + (uintptr_t)mbi.RegionSize;

	ScanResult& result = results[resultIdx];

	// Check if value fits entirely in region
	if (result.address + dataSize > regionEnd) {
		// Value spans region boundary are not legal
		invalidAddressCount++;
		resultIdx++;
		return;
	}

	// Look ahead to batch nearby results in same region
	// We will batch up to the chunk threshold
	size_t batchStart = resultIdx;
	size_t batchEnd = resultIdx + 1;
	uintptr_t chunkStart = result.address;
	uintptr_t chunkEnd = result.address + dataSize;

	while (batchEnd < results.size() && results[batchEnd].address < regionEnd) {
		uintptr_t nextResultEnd = results[batchEnd].address + dataSize;
		uintptr_t newSpan = nextResultEnd - chunkStart;
		if (newSpan > CHUNK_THRESHOLD) {
			break;
		}
		// Include this result in batch
		if (nextResultEnd > chunkEnd) {
			chunkEnd = nextResultEnd;
		}
		batchEnd++;
	}

	// Only batch if we have multiple results. Single results should be processed directly
	if (batchEnd - batchStart > 1) {
		// Read chunk covering all batched results
		// Cap by CHUNK_THRESHOLD (our buffer size) and region boundary
		size_t chunkSize = std::min<size_t>(chunkEnd - chunkStart, CHUNK_THRESHOLD);
		chunkSize = std::min<size_t>(chunkSize, regionEnd - chunkStart);

		// Copy chunk with try/catch protection
		if (!safeCopyMemory(buffer.data(), (const void*)chunkStart, chunkSize)) {
			// Memory became invalid - skip all results in batch
			invalidAddressCount += (batchEnd - batchStart);
			resultIdx = batchEnd;
			return;
		}

		// Process batch from buffer
		rescanResultBatch(results, batchStart, batchEnd, chunkStart, chunkSize,
		                  buffer.data(), scanType, targetValue, newResults);

		resultIdx = batchEnd;
	} else {
		// Process single result directly (base class now handles this)
		rescanResultDirect(result, regionEnd, scanType, targetValue, newResults);
		resultIdx++;
	}
}

// Process a batch of results from a chunk buffer for rescan
void Scanner::rescanResultBatch(const std::vector<ScanResult, ScannerAllocator<ScanResult>>& oldResults,
                                 size_t batchStart, size_t batchEnd,
                                 uintptr_t chunkStart, size_t chunkSize, const uint8_t* buffer,
                                 ScanType scanType, const void* targetValue,
                                 std::vector<ScanResult, ScannerAllocator<ScanResult>>& newResults) {
	// Cache data type size
	const size_t dataSize = getDataTypeSize();

	// Process all results from buffer
	for (size_t j = batchStart; j < batchEnd; j++) {
		const ScanResult& batchResult = oldResults[j];
		size_t offset = batchResult.address - chunkStart;

		// Verify address is within chunk
		if (offset + dataSize > chunkSize) {
			invalidAddressCount++;
			continue;
		}

		// Store old value for comparison (needed for CHANGED/UNCHANGED/etc scans)
		ScanValue oldValue = batchResult.value;

		// Validate value from buffer
		ScanResult tempResult;
		if (!validateValueInBuffer(buffer, chunkSize, offset, batchResult.address,
		                           scanType, targetValue, tempResult)) {
			invalidAddressCount++;
			continue;
		}

		// Set old value for comparison (sequences don't use it, but minimal cost)
		tempResult.oldValue = oldValue;
		tempResult.hasOldValue = true;

		// Add to new results
		newResults.push_back(tempResult);
	}
}

// Process a single isolated result with direct memory read
void Scanner::rescanResultDirect(const ScanResult& oldResult, uintptr_t regionEnd,
                                  ScanType scanType, const void* targetValue,
                                  std::vector<ScanResult, ScannerAllocator<ScanResult>>& newResults) {
	// Store old value for comparison (needed for CHANGED/UNCHANGED/etc scans)
	ScanValue oldValue = oldResult.value;

	// Call derived class to validate value directly from memory (with SEH protection)
	ScanResult tempResult;
	if (!validateValueDirect(oldResult.address, regionEnd, scanType, targetValue, tempResult)) {
		invalidAddressCount++;
		return;
	}

	// Set old value for comparison (sequences don't use it, but minimal cost)
	tempResult.oldValue = oldValue;
	tempResult.hasOldValue = true;

	// Add to new results
	newResults.push_back(tempResult);
}

// Default reset implementation
void Scanner::reset() {
	results.clear();
	firstScanDone = false;
	maxResultsReached = false;
	invalidAddressCount = 0;
	clearErrors();
}

void Scanner::addError(const char* format, ...) const {
	char buffer[512];
	va_list args;
	va_start(args, format);
	vsnprintf_s(buffer, sizeof(buffer), _TRUNCATE, format, args);
	va_end(args);
	errors.emplace_back(buffer);
}

void Scanner::reportInvalidAddressStats() {
	if (invalidAddressCount > 0) {
		if (results.size() == 0) {
			addError("All %zu addresses became invalid (memory may have been freed)", invalidAddressCount);
		} else {
			addError("%zu addresses became invalid", invalidAddressCount);
		}
	}
}

// try catch wrapper around copying memory
bool Scanner::safeCopyMemory(void* dest, const void* src, size_t size) {
	__try {
		memcpy(dest, src, size);
		return true;
	}
	__except (EXCEPTION_EXECUTE_HANDLER) {
		return false;
	}
}