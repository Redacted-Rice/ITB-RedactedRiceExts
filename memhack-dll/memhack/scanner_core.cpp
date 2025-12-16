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
	maxResultsReached(false), invalidAddressCount(0)
{
	// Use data type size if alignment is 0
	if (alignment == 0) {
		this->alignment = getDataTypeSize();
	}

	// Always allow at least one result. 0 may cause oddities
	if (maxResults == 0) {
		addError("maxResults cannot be 0, defaulting to 1");
		this->maxResults = 1;
	}

	// Pre-allocate a reasonable amount
	results.reserve(std::min(this->maxResults, size_t(10000)));
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

size_t Scanner::getDataTypeSize() const {
	switch (dataType) {
		case DataType::BYTE: return 1;
		case DataType::INT: return 4;
		case DataType::FLOAT: return 4;
		case DataType::DOUBLE: return 8;
		case DataType::BOOL: return 1;
		default: return 1;
	}
}

bool Scanner::compareEqual(const void* a, const void* b) const {
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

bool Scanner::compareGreater(const void* a, const void* b) const {
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

bool Scanner::compareLess(const void* a, const void* b) const {
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

bool Scanner::checkMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const {
	const void* currentValue = &result.value;
	const void* oldValue = &result.oldValue;

	switch (scanType) {
		case ScanType::EXACT:
			return compareEqual(currentValue, targetValue);

		case ScanType::NOT:
			return !compareEqual(currentValue, targetValue);

		case ScanType::INCREASED:
			if (!result.hasOldValue) return false;
			return compareGreater(currentValue, oldValue);

		case ScanType::DECREASED:
			if (!result.hasOldValue) return false;
			return compareLess(currentValue, oldValue);

		case ScanType::CHANGED:
			if (!result.hasOldValue) return false;
			return !compareEqual(currentValue, oldValue);

		case ScanType::UNCHANGED:
			if (!result.hasOldValue) return false;
			return compareEqual(currentValue, oldValue);

		default:
			addError("Invalid scan type in checkMatch: %d", (int)scanType);
			return false;
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
	uintptr_t endAddress = address + size;

	for (const auto& region : regions) {
		uintptr_t regionBase = (uintptr_t)region.base;

		// Check if entire address is within this region (size/end address will be checked later when reading)
		if (address >= regionBase && address <= regionEnd) {
			return &region;
		}
	}

	// Not found in any region
	return nullptr;
}

bool Scanner::readValueWithVerification(uintptr_t address, const std::vector<SafeMemory::Region>& regions, ScanResult& result) const {
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

void Scanner::scanRegion(void* base, size_t size, ScanType scanType, const void* targetValue) {
	if (size == 0 || alignment == 0) {
		return; // Nothing to scan
	}

	uintptr_t addr = (uintptr_t)base;

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

void Scanner::firstScan(ScanType scanType, const void* targetValue) {
	if (firstScanDone) {
		addError("First scan already performed - use reset() first");
		return;
	}

	clearErrors();
	results.clear();
	maxResultsReached = false;

	// Get heap regions
	const std::vector<SafeMemory::Region>& regions = SafeMemory::get_heap_regions(false);
	if (regions.empty()) {
		addError("No readable heap regions found");
		return;
	}

	// Scan each region
	for (const auto& region : regions) {
		scanRegion(region.base, region.size, scanType, targetValue);

		// maxResultsReached is set inside scanRegion when limit hit
		if (maxResultsReached) {
			addError("Maximum results (%zu) reached, stopping scan early", maxResults);
			break;
		}
	}

	firstScanDone = true;

	// Report statistics
	reportInvalidAddressStats();
}

void Scanner::rescan(ScanType scanType, const void* targetValue) {
	if (!firstScanDone) {
		addError("Must perform first scan before rescanning");
		return;
	}

	clearErrors();
	std::vector<ScanResult> newResults;
	newResults.reserve(results.size());
	invalidAddressCount = 0;

	// Re-get heap regions to verify addresses are still valid
	const std::vector<SafeMemory::Region>& regions = SafeMemory::get_heap_regions(false);
	if (regions.empty()) {
		addError("No readable heap regions found during rescan");
		return;
	}

	for (auto& oldResult : results) {
		ScanResult newResult;

		// Read value, verifying address+size is within current heap regions
		if (readValueWithVerification(oldResult.address, regions, newResult)) {
			// Copy old value for comparison
			newResult.oldValue = oldResult.value;
			newResult.hasOldValue = true;

			if (checkMatch(newResult, scanType, targetValue)) {
				newResults.push_back(newResult);
			}
		}
	}

	results = std::move(newResults);

	// Report statistics
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
	clearErrors();
}
