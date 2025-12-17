#include "stdafx.h"
#include "scanner_core.h"
#include "safememory.h"

#include <cmath>
#include <algorithm>

// Float comparison epsilon
const float FLOAT_EPSILON = 0.0001f;
const double DOUBLE_EPSILON = 0.00000001;

Scanner::Scanner(DataType dataType, size_t maxResults, size_t alignment) :
	dataType(dataType), maxResults(maxResults), alignment(alignment), firstScanDone(false),
	maxResultsReached(false), invalidAddressCount(0), lastScanType(ScanType::EXACT)
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

void Scanner::addError(const char* format, ...) const {
	char buffer[512];
	va_list args;
	va_start(args, format);
	vsnprintf_s(buffer, sizeof(buffer), _TRUNCATE, format, args);
	va_end(args);
	errors.push_back(buffer);
}

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

// Reads raw bytes from memory for getting NOT match sequence results
// This does not use safe read versions because those require rechecking memory
// each time and we should have already validated the memory by this point and will
// handle the unlikely edge case where the address changes and cannot be accessed anymore
bool Scanner::readSequenceBytes(uintptr_t address, std::vector<uint8_t>& outBytes) const {
	size_t size = searchSequence.size();
	if (size == 0) {
		return false;
	}

	outBytes.clear();
	outBytes.reserve(size);

	// Try catch in case memory is no longer accessible
	__try {
		const uint8_t* memBytes = (const uint8_t*)address;
		for (size_t i = 0; i < size; i++) {
			outBytes.push_back(memBytes[i]);
		}
		return true;
	}
	__except (EXCEPTION_EXECUTE_HANDLER) {
		// Memory access violation during result value read
		addError("Failed to read sequence value at address 0x%p for results: memory access violation", (void*)address);
		return false;
	}
}

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

	// Compare bytes at memory address with stored searchSequence
	// Early exit on first mismatch for performance
	size_t size = searchSequence.size();
	__try {
		const uint8_t* memBytes = (const uint8_t*)address;
		for (size_t i = 0; i < size; i++) {
			if (memBytes[i] != searchSequence[i]) {
				return false;
			}
		}
		return true;
	}
	__except (EXCEPTION_EXECUTE_HANDLER) {
		addError("Failed to read sequence bytes at address 0x%p: memory access violation", (void*)address);
		return false;
	}
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

bool Scanner::checkMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const {
	if (isSequenceType()) {
		return checkSequenceMatch(result, scanType);
	} else {
		return checkBasicMatch(result, scanType, targetValue);
	}
}

bool Scanner::readValueInRegion(uintptr_t address, uintptr_t regionEnd, ScanResult& result) const {
	// validate end is in valid range
	size_t size = getDataTypeSize();
	if (address + size > regionEnd) {
		invalidAddressCount++;
		return false;
	}

	// This is redundant on follow up scans but its fine
	void* addr = (void*)address;
	result.address = address;

	// Use __try/__except to catch any unexpected access violations
	// This shouldn't happen as we check bounds but just to be 100% safe
	__try {
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
				// For sequence types, we don't read now and store for comparing
				// later but instead just read and compare as we go as an optimization
				// End bound already checked so nothing more to do here
				break;
			default:
				return false;
		}
	}
	__except (EXCEPTION_EXECUTE_HANDLER) {
		addError("Unexpected access violation at 0x%p", addr);
		return false;
	}

	return true;
}

// TODO: Make more effecient by scanning through at the beginning instead of for each one?
const SafeMemory::Region* Scanner::findRegionContainingAddress(uintptr_t address, const std::vector<SafeMemory::Region>& regions) const {
	// Find region that contains address + size (entire value must fit)
	size_t size = getDataTypeSize();

	for (const auto& region : regions) {
		uintptr_t regionBase = region.base;
		uintptr_t regionEnd = region.base + region.size;

		// Check if entire address is within this region (size/end address will be checked later when reading)
		if (address >= regionBase && address <= regionEnd) {
			return &region;
		}
	}

	// Not found in any region
	return nullptr;
}

bool Scanner::readValueWithVerification(uintptr_t address, const std::vector<SafeMemory::Region>& regions, ScanResult& result) const {
	// TODO: Remove re-validation and rely on try catch for memory access changing

	// Verify address is in a valid region
	const SafeMemory::Region* region = findRegionContainingAddress(address, regions);
	if (region == nullptr) {
		// Address no longer in valid regions. I don't think this should happen
		invalidAddressCount++;
		return false;
	}

	// Determine end for safety check in read
	uintptr_t regionEnd = (uintptr_t)region->base + region->size;
	return readValueInRegion(address, regionEnd, result);
}

// Scan a single region for a match used for initial scan only
void Scanner::scanRegion(uintptr_t base, size_t size, ScanType scanType, const void* targetValue) {
	if (size == 0 || alignment == 0) {
		return; // Nothing to scan
	}

	uintptr_t addr = base;

	// Check for overflow when calculating end address
	uintptr_t endAddr;
	if (size > (UINTPTR_MAX - addr)) {
		addError("Region size overflow: base=0x%p, size=0x%zx would exceed UINTPTR_MAX", base, size);
		endAddr = UINTPTR_MAX;
	} else {
		endAddr = addr + size;
	}

	// Calculate maximum iterations to ensure we don't get stuck looping
	// add 5 just for buffer and so we know hitting it is unexpected
	size_t maxIterations = (size / alignment) + 5;
	size_t iterations = 0;

	// Scan through the region
	while (addr < endAddr && results.size() < maxResults) {
		// Hit max iterations?
		if (++iterations > maxIterations) {
			addError("Max iterations reached in scanRegion: base=0x%p, size=0x%zx, iterations=%zu", base, size, iterations);
			break;
		}
		ScanResult result;

		// Read value, verifying address+size is within region bounds
		if (readValueInRegion(addr, endAddr, result)) {
			if (checkMatch(result, scanType, targetValue)) {
				results.push_back(result);

				if (results.size() >= maxResults) {
					maxResultsReached = true;
					return;
				}
			}
		}

		// Check for overflow before incrementing
		if (addr > UINTPTR_MAX - alignment) {
			addError("Address overflow in scanRegion: addr=0x%p, alignment=%zu", (void*)addr, alignment);
			break;
		}
		addr += alignment;
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
		if (targetValue != nullptr && valueSize > 0) {
			setSearchSequence(targetValue, valueSize);
		} else {
			addError("Sequence types require non-null targetValue with size > 0");
			return false;
		}
	}

	return true;
}

void Scanner::firstScan(ScanType scanType, const void* targetValue, size_t valueSize) {
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

	// Get heap regions
	const std::vector<SafeMemory::Region>& regions = SafeMemory::get_heap_regions(false);
	if (regions.empty()) {
		addError("No readable heap regions found");
		return;
	}

	// Clear results to be sure of clean state and scan each region
	results.clear();
	maxResultsReached = false;
	for (const auto& region : regions) {
		scanRegion(region.base, region.size, scanType, targetValue);

		// maxResultsReached is set inside scanRegion when limit hit
		if (maxResultsReached) {
			addError("Maximum results (%zu) reached, stopping scan early", maxResults);
			break;
		}
	}

	firstScanDone = true;
	reportInvalidAddressStats();
}

void Scanner::rescan(ScanType scanType, const void* targetValue, size_t valueSize) {
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

	// Re-get heap regions to verify addresses are still valid
	// TODO: as mentioned elsewhere, remove re-validation as optimization
	const std::vector<SafeMemory::Region>& regions = SafeMemory::get_heap_regions(false);
	if (regions.empty()) {
		addError("No readable heap regions found");
		return;
	}

	// Filter existing results in place to avoid reallocations
	size_t writeIndex = 0;
	for (size_t readIndex = 0; readIndex < results.size(); readIndex++) {
		ScanResult& result = results[readIndex];

		// Store old value before reading new value
		ScanValue oldValue = result.value;

		// Read value, verifying address+size is within current heap regions
		if (readValueWithVerification(result.address, regions, result)) {
			// Copy old value for comparison
			result.oldValue = oldValue;
			result.hasOldValue = true;

			if (checkMatch(result, scanType, targetValue)) {
				// Keep this result - copy to write position if different
				if (writeIndex != readIndex) {
					results[writeIndex] = result;
				}
				writeIndex++;
			}
		}
	}

	// Remove unused results at end
	results.resize(writeIndex);
	reportInvalidAddressStats();
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

void Scanner::reset() {
	results.clear();
	firstScanDone = false;
	maxResultsReached = false;
	invalidAddressCount = 0;
	searchSequence.clear();
	clearErrors();
}
