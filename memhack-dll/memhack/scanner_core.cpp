#include "stdafx.h"
#include "scanner_core.h"
#include "safememory.h"

#include <cmath>
#include <algorithm>
#include <windows.h>


Scanner::Scanner(DataType dataType, size_t maxResults, size_t alignment) :
	dataType(dataType), maxResults(maxResults), alignment(alignment), firstScanDone(false),
	maxResultsReached(false), invalidAddressCount(0), lastScanType(ScanType::EXACT), checkTiming(false)
{
	// Always allow at least one result. 0 may cause oddities
	if (maxResults == 0) {
		addError("maxResults cannot be 0, defaulting to 1");
		this->maxResults = 1;
	}

	// Default alignment to data type size if not specified
	// For sequence types, alignment defaults to 4 (32 bit aligned)
	// This is needed because getDataTypeSize will return the sequence size
	// but sequences can be aligned fairly arbitrarily for performance
	if (alignment == 0) {
		if (isSequenceType()) {
			this->alignment = 4;
		} else {
			this->alignment = getDataTypeSize();
		}
	}

	// Pre-allocate a reasonable amount
	results.reserve(std::min<size_t>(this->maxResults, 10000));
}

Scanner::~Scanner() {}

bool Scanner::isSequenceType() const {
	return dataType == DataType::STRING || dataType == DataType::BYTE_ARRAY;
}

size_t Scanner::getDataTypeSize() const {
	switch (dataType) {
		case DataType::BYTE: return 1;
		case DataType::INT: return 4;
		case DataType::FLOAT: return 4;
		case DataType::DOUBLE: return 8;
		case DataType::BOOL: return 1;
		case DataType::STRING:
		case DataType::BYTE_ARRAY: {
			size_t size = searchSequence.size();
			return size > 0 ? size : 1;
		}
		default: return 1;
	}
}

// Internal function to set search sequence for sequence types. For basic types, we do not
// need this separate because we handle the value storage and reading differently
void Scanner::setSearchSequence(const void* data, size_t size) {
	if (size == 0) {
		addError("Search sequence cannot be empty");
		return;
	}

	// Put in byte array to prepare for per byte comparison
	searchSequence.clear();
	searchSequence.reserve(size);
	const uint8_t* bytes = (const uint8_t*)data;
	for (size_t i = 0; i < size; i++) {
		searchSequence.push_back(bytes[i]);
	}
}

// ------------ comparing values in loaded memory --------------

bool Scanner::compareBasic(const void* a, const void* b) const {
	switch (dataType) {
		case DataType::BYTE:
			return *(uint8_t*)a == *(uint8_t*)b;
		case DataType::INT:
			return *(int32_t*)a == *(int32_t*)b;
		case DataType::FLOAT:
			return std::abs(*(float*)a - *(float*)b) < FLOAT_EPSILON;
		case DataType::DOUBLE:
			return std::abs(*(double*)a - *(double*)b) < DOUBLE_EPSILON;
		case DataType::BOOL:
			return *(bool*)a == *(bool*)b;
		default:
			return false;
	}
}

bool Scanner::compareSequence(uintptr_t address) const {
	if (searchSequence.empty()) {
		return false;
	}

	// do mem compare to optimize and since we have the full
	// string read in already
	const uint8_t* memBytes = (const uint8_t*)address;
	return memcmp(memBytes, searchSequence.data(), searchSequence.size()) == 0;
}

bool Scanner::compareBasicGreater(const void* a, const void* b) const {
	switch (dataType) {
		case DataType::BYTE:
			return *(uint8_t*)a > *(uint8_t*)b;
		case DataType::INT:
			return *(int32_t*)a > *(int32_t*)b;
		case DataType::FLOAT:
			return *(float*)a > *(float*)b + FLOAT_EPSILON;
		case DataType::DOUBLE:
			return *(double*)a > *(double*)b + DOUBLE_EPSILON;
		case DataType::BOOL:
			return *(bool*)a && !*(bool*)b;
		default:
			return false;
	}
}

bool Scanner::compareBasicLess(const void* a, const void* b) const {
	switch (dataType) {
		case DataType::BYTE:
			return *(uint8_t*)a < *(uint8_t*)b;
		case DataType::INT:
			return *(int32_t*)a < *(int32_t*)b;
		case DataType::FLOAT:
			return *(float*)a < *(float*)b - FLOAT_EPSILON;
		case DataType::DOUBLE:
			return *(double*)a < *(double*)b - DOUBLE_EPSILON;
		case DataType::BOOL:
			return !*(bool*)a && *(bool*)b;
		default:
			return false;
	}
}

bool Scanner::checkSequenceMatch(const ScanResult& result, ScanType scanType) const {
	switch (scanType) {
		case ScanType::EXACT:
			return compareSequence(result.address);

		case ScanType::NOT:
			return !compareSequence(result.address);

		case ScanType::CHANGED:
		case ScanType::UNCHANGED:
		case ScanType::INCREASED:
		case ScanType::DECREASED:
			addError("Only EXACT and NOT scans supported for STRING/BYTE_ARRAY");
			return false;

		default:
			addError("Invalid scan type in checkSequenceMatch: %d", (int)scanType);
			return false;
	}
}

bool Scanner::checkBasicMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const {
	const void* currentValue = &result.value;
	const void* oldValue = &result.oldValue;

	switch (scanType) {
		case ScanType::EXACT:
			return compareBasic(currentValue, targetValue);

		case ScanType::NOT:
			return !compareBasic(currentValue, targetValue);

		case ScanType::INCREASED:
			if (!result.hasOldValue) return false;
			return compareBasicGreater(currentValue, oldValue);

		case ScanType::DECREASED:
			if (!result.hasOldValue) return false;
			return compareBasicLess(currentValue, oldValue);

		case ScanType::CHANGED:
			if (!result.hasOldValue) return false;
			return !compareBasic(currentValue, oldValue);

		case ScanType::UNCHANGED:
			if (!result.hasOldValue) return false;
			return compareBasic(currentValue, oldValue);

		default:
			addError("Invalid scan type in checkBasicMatch: %d", (int)scanType);
			return false;
	}
}

// Both preloaded chunks and direct reads funnel through here
// Primary access point for this grouping of functions
bool Scanner::checkMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const {
	if (isSequenceType()) {
		return checkSequenceMatch(result, scanType);
	} else {
		return checkBasicMatch(result, scanType, targetValue);
	}
}

// ------------ end of comparing values in loaded memory --------------

// ------------ validating values - read and check them --------------

// Validates the value in the buffer
// Entry point for this logic for rescan
bool Scanner::validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
                                     uintptr_t actualAddress, ScanType scanType, const void* targetValue,
                                     ScanResult& outResult) const {
	outResult.address = actualAddress;

	// For sequence types, we need to check if sequence fits in buffer first
	if (isSequenceType()) {
		if (offset + searchSequence.size() > bufferSize) {
			// Sequence crosses chunk boundary, will be caught in next chunk
			// We overlap chunks by size - 1 to ensure we catch this case
			return false;
		}
		// For sequence types, checkMatch will use compareSequence which reads directly from memory
		// So we just need to set the address
	} else {
		// For basic types, read the value from buffer into result
		if (!readValueFromBuffer(buffer, bufferSize, offset, outResult, actualAddress)) {
			return false;
		}
	}

	// Check if it matches using unified logic
	return checkMatch(outResult, scanType, targetValue);
}

// Validates sequence directly from memory with try/catch protection
// Does try/catch read and compare all in one
bool Scanner::validateSequenceDirect(uintptr_t address, uintptr_t regionEnd, ScanType scanType) const {
	size_t seqSize = searchSequence.size();

	// Check bounds first (before SEH)
	if (address + seqSize > regionEnd) {
		return false;
	}

	__try {
		// Compare directly - memcmp will read the memory
		// If memory is invalid, the __except will catch it
		bool matches = (memcmp((const uint8_t*)address, searchSequence.data(), seqSize) == 0);

		// Handle scan type
		switch (scanType) {
			case ScanType::EXACT:
				return matches;
			case ScanType::NOT:
				return !matches;
			default:
				// Sequences only support EXACT and NOT
				return false;
		}
	}
	__except (EXCEPTION_EXECUTE_HANDLER) {
		// Memory became invalid during comparison
		return false;
	}
}

// Validates the value directly from memory
// Entry point for rescanning
bool Scanner::validateValueDirect(uintptr_t address, uintptr_t regionEnd, ScanType scanType,
                                   const void* targetValue, ScanResult& outResult) const {
	outResult.address = address;

	if (isSequenceType()) {
		// For sequences everything is handled in the one call
		return validateSequenceDirect(address, regionEnd, scanType);
	} else {
		// For basic types, read value then compare
		if (!readBasicValueDirect(address, regionEnd, outResult)) {
			return false;
		}
		return checkBasicMatch(outResult, scanType, targetValue);
	}
}


// helper for reading the value from the buffer
bool Scanner::readValueFromBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset, ScanResult& result, uintptr_t actualAddress) const {
	// Validate we have enough bytes in buffer
	size_t size = getDataTypeSize();
	if (offset + size > bufferSize) {
		return false;
	}

	result.address = actualAddress;
	const uint8_t* addr = buffer + offset;

	switch (dataType) {
		case DataType::BYTE:
			result.value.byteValue = *addr;
			break;
		case DataType::INT:
			result.value.intValue = *(int32_t*)addr;
			break;
		case DataType::FLOAT:
			result.value.floatValue = *(float*)addr;
			break;
		case DataType::DOUBLE:
			result.value.doubleValue = *(double*)addr;
			break;
		case DataType::BOOL:
			result.value.boolValue = *(bool*)addr;
			break;
		case DataType::STRING:
		case DataType::BYTE_ARRAY:
			// For sequence types, we don't store value
			break;
		default:
			return false;
	}

	return true;
}

// Read basic type value directly from memory for rescans
// Sequences are handled separately by validateSequenceDirect
bool Scanner::readBasicValueDirect(uintptr_t address, uintptr_t regionEnd, ScanResult& result) const {
	// Validate end is in valid range. It should be since we already found it once
	size_t dataSize = getDataTypeSize();
	if (address + dataSize > regionEnd) {
		return false;
	}

	result.address = address;

	// Read value with try/catch protection
	__try {
		const uint8_t* addr = (const uint8_t*)address;

		switch (dataType) {
			case DataType::BYTE:
				result.value.byteValue = *(uint8_t*)addr;
				break;
			case DataType::INT:
				result.value.intValue = *(int32_t*)addr;
				break;
			case DataType::FLOAT:
				result.value.floatValue = *(float*)addr;
				break;
			case DataType::DOUBLE:
				result.value.doubleValue = *(double*)addr;
				break;
			case DataType::BOOL:
				result.value.boolValue = *(bool*)addr;
				break;
			case DataType::STRING:
			case DataType::BYTE_ARRAY:
				// This should never be called for sequences - they use validateSequenceDirect
				return false;
			default:
				return false;
		}
	}
	__except (EXCEPTION_EXECUTE_HANDLER) {
		// Memory became invalid between region check and read
		return false;
	}

	return true;
}

// ------------ end of validating values --------------


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

// Common setup shared by firstScan and rescan
// Returns false if setup failed (error already added)
bool Scanner::setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize) {
	clearErrors();
	invalidAddressCount = 0;
	lastScanType = scanType;

	// For sequence types, set the search sequence from targetValue
	if (isSequenceType()) {
		if (targetValue == nullptr || valueSize == 0) {
			addError("Sequence types require non-null targetValue with size > 0");
			return false;
		}

		if (valueSize > MAX_SEQUENCE_SIZE) {
			addError("Sequence size (%zu) exceeds maximum allowed size (%zu)", valueSize, MAX_SEQUENCE_SIZE);
			return false;
		}

		setSearchSequence(targetValue, valueSize);
	}

	return true;
}

// Scan a single chunk of memory buffer for first scan
void Scanner::scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
                                 ScanType scanType, const void* targetValue) {
	size_t dataSize = getDataTypeSize();

	// Find aligned global starting offset within this chunk
	uintptr_t firstAlignedAddr = chunkBase;
	if (firstAlignedAddr % alignment != 0) {
		firstAlignedAddr = ((firstAlignedAddr / alignment) + 1) * alignment;
	}
	size_t offset = (size_t)(firstAlignedAddr - chunkBase);

	// Scan through buffer at alignment intervals
	while (offset + dataSize <= chunkSize && results.size() < maxResults) {
		uintptr_t actualAddress = chunkBase + offset;

		// Validate value from buffer
		ScanResult result;
		if (validateValueInBuffer(buffer, chunkSize, offset, actualAddress, scanType, targetValue, result)) {
			// Match found - add to results
			results.push_back(result);

			if (results.size() >= maxResults) {
				maxResultsReached = true;
				return;
			}
		}

		offset += alignment;
	}
}

// Scan a single region in buffered chunks for first scan
void Scanner::scanRegion(uintptr_t base, size_t size, ScanType scanType, const void* targetValue) {
	if (size == 0 || alignment == 0) {
		return; // Nothing to scan
	}

	size_t dataSize = getDataTypeSize();
	uintptr_t regionEnd = base + size;

	// Allocate scan buffer
	std::vector<uint8_t> buffer(SCAN_BUFFER_SIZE);

	uintptr_t currentBase = base;

	// Scan region in buffered chunks with overlap to catch sequences at boundaries
	// We overlap chunks by (dataSize - 1) bytes to ensure that any sequence starting
	// near the end of chunk will be fully contained in the next one
	while (currentBase < regionEnd && results.size() < maxResults) {
		// Determine chunk size ensuring we don't read past the end of the region
		size_t chunkSize = std::min<size_t>(SCAN_BUFFER_SIZE, regionEnd - currentBase);

		// Copy the chunk with SEH protection in case memory becomes invalid
		if (!safeCopyMemory(buffer.data(), (const void*)currentBase, chunkSize)) {
			// Memory became invalid between VirtualQuery and memcpy
			// Skip this chunk and continue
			currentBase += chunkSize;
			continue;
		}

		// Scan this chunk buffer
		scanChunkInRegion(buffer.data(), chunkSize, currentBase, scanType, targetValue);

		// Early exit if max results reached
		if (maxResultsReached) {
			return;
		}

		// Move to next chunk with overlap as stated above
		currentBase += chunkSize;
		if (dataSize > 1 && currentBase < regionEnd) {
			// dataSize is capped by MAX_SEQUENCE_SIZE, which is guaranteed < SCAN_BUFFER_SIZE so
			// we don't need to worry about going negative
			size_t overlap = std::min<size_t>(dataSize - 1, chunkSize);
			currentBase -= overlap;
		}
	}
}

// Main entry point for performing a new scan
void Scanner::firstScan(ScanType scanType, const void* targetValue, size_t valueSize) {
	// Start timing if enabled
	ULONGLONG startTime = 0;
	if (checkTiming) {
		startTime = GetTickCount64();
	}

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

	// Common setup and validation
	if (!setupScanCommon(scanType, targetValue, valueSize)) {
		// Error already added
		return;
	}

	// Clear results to be sure of clean state
	results.clear();
	maxResultsReached = false;

	// Iterate through memory regions and scan as we go
	SYSTEM_INFO si;
	GetSystemInfo(&si);

	uintptr_t addr = (uintptr_t)si.lpMinimumApplicationAddress;
	uintptr_t end = (uintptr_t)si.lpMaximumApplicationAddress;

	// Go through each region and scan it if its safe for reading
	while (addr < end && !maxResultsReached) {
		MEMORY_BASIC_INFORMATION mbi{};
		SIZE_T r = VirtualQuery((LPCVOID)addr, &mbi, sizeof(mbi));
		if (r != sizeof(mbi)) break;
		if (SafeMemory::is_mbi_safe(mbi, false)) {
			scanRegion((uintptr_t)mbi.BaseAddress, (size_t)mbi.RegionSize, scanType, targetValue);
			if (maxResultsReached) {
				addError("Maximum results (%zu) reached, stopping scan early", maxResults);
				break;
			}
		}

		// Update address to the next region and continue
		// We do not need to worry about a sequence crossing the boundary here because we are
		// looking at regions and having a value cross regions is not legal
		addr = (uintptr_t)mbi.BaseAddress + (uintptr_t)mbi.RegionSize;
	}

	firstScanDone = true;
	reportInvalidAddressStats();

	// Report timing if enabled
	if (checkTiming) {
		ULONGLONG endTime = GetTickCount64();
		ULONGLONG elapsed = endTime - startTime;
		addError("firstScan timing: %llu ms (%zu results found)", elapsed, results.size());
	}
}

// Process a single isolated result with direct memory read for rescan
void Scanner::rescanResultDirect(const ScanResult& oldResult, uintptr_t regionEnd,
                                  ScanType scanType, const void* targetValue, std::vector<ScanResult>& newResults) {
	// Store old value for comparison
	ScanValue oldValue = oldResult.value;

	// Validate value directly from memory (with try/catch protection)
	ScanResult tempResult;
	if (!validateValueDirect(oldResult.address, regionEnd, scanType, targetValue, tempResult)) {
		invalidAddressCount++;
		return;
	}

	// Set old value for comparison (needed for CHANGED/UNCHANGED/etc scans)
	tempResult.oldValue = oldValue;
	tempResult.hasOldValue = true;

	// Add to new results
	newResults.push_back(tempResult);
}

// Process a batch of results from a chunk buffer for rescan
// This optimizes reads to reduce overall ready & try/catches needed which should speed things up
void Scanner::rescanResultBatch(const std::vector<ScanResult>& oldResults, size_t batchStart, size_t batchEnd,
                                 uintptr_t chunkStart, size_t chunkSize, const uint8_t* buffer,
                                 ScanType scanType, const void* targetValue, std::vector<ScanResult>& newResults) {
	size_t dataSize = getDataTypeSize();

	// Process all results from buffer
	for (size_t j = batchStart; j < batchEnd; j++) {
		const ScanResult& batchResult = oldResults[j];
		size_t offset = batchResult.address - chunkStart;

		// Verify address is within chunk
		if (offset + dataSize > chunkSize) {
			invalidAddressCount++;
			continue;
		}

		// Store old value for comparison
		ScanValue oldValue = batchResult.value;

		// Validate value from buffer
		ScanResult tempResult;
		if (!validateValueInBuffer(buffer, chunkSize, offset, batchResult.address,
		                           scanType, targetValue, tempResult)) {
			invalidAddressCount++;
			continue;
		}

		// Set old value for comparison (needed for CHANGED/UNCHANGED/etc scans)
		tempResult.oldValue = oldValue;
		tempResult.hasOldValue = true;

		// Add to new results
		newResults.push_back(tempResult);
	}
}

// Process results in a single memory region for rescan
void Scanner::rescanResultsInRegion(MEMORY_BASIC_INFORMATION& mbi, size_t& resultIdx,
                                     ScanType scanType, const void* targetValue,
                                     std::vector<ScanResult>& newResults, std::vector<uint8_t>& buffer) {
	size_t dataSize = getDataTypeSize();

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

	// Can't decide if I want to do it as a min span between values with a max cap
	// or like below with a max span from first to last

	// Look ahead to batch nearby results in same region
	// We will batch up to the chunk threshold
	size_t batchStart = resultIdx;
	size_t batchEnd = resultIdx + 1;
	uintptr_t chunkStart = result.address;
	uintptr_t chunkEnd = result.address + dataSize;

	// Find consecutive results where total span stays under CHUNK_THRESHOLD
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
		// Process single result directly
		rescanResultDirect(result, regionEnd, scanType, targetValue, newResults);
		resultIdx++;
	}
}

// Rescan existing results with new criteria (main orchestrator)
void Scanner::rescan(ScanType scanType, const void* targetValue, size_t valueSize) {
	// Start timing if enabled
	ULONGLONG startTime = 0;
	if (checkTiming) {
		startTime = GetTickCount64();
	}

	if (!firstScanDone) {
		addError("Must perform first scan before rescanning");
		return;
	}

	if (results.empty()) {
		addError("No previous results to rescan");
		return;
	}

	// Common setup and validation
	if (!setupScanCommon(scanType, targetValue, valueSize)) {
		// Error already added
		return;
	}

	// Sort results by address for efficient processing
	// Using stable_sort since results are likely already mostly sorted from previous scan
	std::stable_sort(results.begin(), results.end(), [](const ScanResult& a, const ScanResult& b) {
		return a.address < b.address;
	});

	// Allocate buffer for chunk-based reading
	// We use CHUNK_THRESHOLD for rescans since we only batch results within that distance
	std::vector<uint8_t> buffer(CHUNK_THRESHOLD);

	std::vector<ScanResult> newResults;
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

		// Region is safe - process results in this region
		rescanResultsInRegion(mbi, resultIdx, scanType, targetValue, newResults, buffer);
	}

	// Replace results with filtered results
	results = std::move(newResults);
	reportInvalidAddressStats();

	// Report timing if enabled
	if (checkTiming) {
		ULONGLONG endTime = GetTickCount64();
		ULONGLONG elapsed = endTime - startTime;
		addError("rescan timing: %llu ms (%zu results remaining)", elapsed, results.size());
	}
}

void Scanner::reset() {
	results.clear();
	firstScanDone = false;
	maxResultsReached = false;
	invalidAddressCount = 0;
	searchSequence.clear();
	clearErrors();
}

// Reads raw bytes from memory for getting NOT match sequence results
// This is only used when retrieving results (not in scan loop), so SEH is acceptable here
bool Scanner::readSequenceBytes(uintptr_t address, std::vector<uint8_t>& outBytes) const {
	size_t size = searchSequence.size();
	if (size == 0) {
		return false;
	}

	outBytes.clear();
	outBytes.reserve(size);

	// Try to read with SEH protection - simpler than pre-checking
	__try {
		const uint8_t* memBytes = (const uint8_t*)address;
		outBytes.assign(memBytes, memBytes + size);
		return true;
	}
	__except (EXCEPTION_EXECUTE_HANDLER) {
		addError("Failed to read sequence value at address 0x%p: memory access violation", (void*)address);
		return false;
	}
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

void Scanner::addError(const char* format, ...) const {
	char buffer[512];
	va_list args;
	va_start(args, format);
	vsnprintf_s(buffer, sizeof(buffer), _TRUNCATE, format, args);
	va_end(args);
	errors.push_back(buffer);
}