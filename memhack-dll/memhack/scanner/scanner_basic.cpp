#include "../stdafx.h"
#include "scanner/scanner_basic.h"
#include "../safememory.h"

#include <cmath>
#include <algorithm>
#include <windows.h>

BasicScanner::BasicScanner(DataType dataType, size_t maxResults, size_t alignment) :
	Scanner(dataType, maxResults, alignment)
{
	// Default alignment to data type size if not specified
	if (this->alignment == 0) {
		this->alignment = getDataTypeSize();
	}
}

BasicScanner::~BasicScanner() {}

size_t BasicScanner::getDataTypeSize() const {
	switch (dataType) {
		case DataType::BYTE: return 1;
		case DataType::INT: return 4;
		case DataType::FLOAT: return 4;
		case DataType::DOUBLE: return 8;
		case DataType::BOOL: return 1;
		default: return 1;
	}
}

bool BasicScanner::compare(const void* a, const void* b) const {
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

bool BasicScanner::compareGreater(const void* a, const void* b) const {
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

bool BasicScanner::compareLess(const void* a, const void* b) const {
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

bool BasicScanner::checkMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const {
	const void* currentValue = &result.value;
	const void* oldValue = &result.oldValue;

	switch (scanType) {
		case ScanType::EXACT:
			return compare(currentValue, targetValue);
		case ScanType::NOT:
			return !compare(currentValue, targetValue);
		case ScanType::INCREASED:
			return compareGreater(currentValue, oldValue);
		case ScanType::DECREASED:
			return compareLess(currentValue, oldValue);
		case ScanType::CHANGED:
			return !compare(currentValue, oldValue);
		case ScanType::UNCHANGED:
			return compare(currentValue, oldValue);
		default:
			addError("Invalid scan type in checkMatch: %d", (int)scanType);
			return false;
	}
}

// helper for reading the value from the buffer
bool BasicScanner::readValueFromBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
                                        ScanResult& result, uintptr_t actualAddress) const {
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
		default:
			return false;
	}

	return true;
}

// Read basic type value directly from memory for rescans
// Sequences are handled separately by validateSequenceDirect
bool BasicScanner::readValueDirect(uintptr_t address, uintptr_t regionEnd, ScanResult& result) const {
	// Validate end is in valid range
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

bool BasicScanner::validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
                                          uintptr_t actualAddress, ScanType scanType, const void* targetValue,
                                          ScanResult& outResult) const {
	outResult.address = actualAddress;

	// Read the value from buffer into result
	if (!readValueFromBuffer(buffer, bufferSize, offset, outResult, actualAddress)) {
		return false;
	}
	return checkMatch(outResult, scanType, targetValue);
}

bool BasicScanner::validateValueDirect(uintptr_t address, uintptr_t regionEnd,
                                        ScanType scanType, const void* targetValue,
                                        ScanResult& outResult) const {
	outResult.address = address;

	// Read value then compare
	if (!readValueDirect(address, regionEnd, outResult)) {
		return false;
	}
	return checkMatch(outResult, scanType, targetValue);
}

// Scan a single chunk of memory buffer for first scan
void BasicScanner::scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
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