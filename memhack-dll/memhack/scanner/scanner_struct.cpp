#include "stdafx.h"
#include "scanner_struct.h"
#include "../safememory.h"

#include <cmath>
#include <algorithm>
#include <windows.h>


// StructFieldBasic implementation
void* StructScanner::StructFieldBasic::operator new(size_t size) {
	return ScannerHeap::allocate(size);
}

void StructScanner::StructFieldBasic::operator delete(void* ptr) noexcept {
	if (ptr) {
		ScannerHeap::deallocate(ptr, 0);
	}
}

StructScanner::StructFieldBasic::StructFieldBasic(int offsetFromKey, BasicScanner::DataType type, ScanValue val)
	: offsetFromKey(offsetFromKey), type(type), val(val) {
}

bool StructScanner::StructFieldBasic::compare(const uint8_t* keyAddr) const {
    return BasicScanner::compare(keyAddr + offsetFromKey, &val, type);
}

// StructFieldSequence implementation
void* StructScanner::StructFieldSequence::operator new(size_t size) {
	return ScannerHeap::allocate(size);
}

void StructScanner::StructFieldSequence::operator delete(void* ptr) noexcept {
	if (ptr) {
		ScannerHeap::deallocate(ptr, 0);
	}
}

StructScanner::StructFieldSequence::StructFieldSequence(int offsetFromKey, const uint8_t* data, size_t size)
	: offsetFromKey(offsetFromKey), val(data, data + size) {
}

bool StructScanner::StructFieldSequence::compare(const uint8_t* keyAddr) const {
    return SequenceScanner::compare(keyAddr + offsetFromKey, val.data(), val.size());
}

// StructSearch implementation
void* StructScanner::StructSearch::operator new(size_t size) {
	return ScannerHeap::allocate(size);
}

void StructScanner::StructSearch::operator delete(void* ptr) noexcept {
	if (ptr) {
		ScannerHeap::deallocate(ptr, 0);
	}
}

StructScanner::StructSearch::StructSearch(uint8_t key, int keyOffsetFromBase)
	: searchKey(key), keyOffsetFromBase(keyOffsetFromBase),
	  sizeBeforeKey(keyOffsetFromBase > 0 ? (size_t)keyOffsetFromBase : 0),
	  sizeFromKey(1) {
	// If keyOffsetFromBase is set, we need to track at least from base to key
}

// ------- end of supporting struct defs -------

void* StructScanner::operator new(size_t size) {
	return ScannerHeap::allocate(size);
}

void StructScanner::operator delete(void* ptr) noexcept {
	if (ptr) {
		ScannerHeap::deallocate(ptr, 0);
	}
}

StructScanner::StructScanner(size_t maxResults, size_t alignment) :
	Scanner(maxResults, alignment), searchStruct(0)
{
	// Just default to 1 for structs
	if (this->alignment == 0) {
		this->alignment = 1;
	}

	// todo: filter results by alignment?
}

StructScanner::~StructScanner() {}

StructScanner* StructScanner::create(size_t maxResults, size_t alignment) {
	return new StructScanner(maxResults, alignment);
}

size_t StructScanner::getDataTypeSize() const {
	return searchStruct.getSize();
}

void StructScanner::setSearchStruct(const StructSearch& targetStruct) {
    // Default copy will use the ScannerAllocator to copy the vectors
    searchStruct = targetStruct;
}

bool StructScanner::compare(const uint8_t* keyAddr) const {
    for (const StructFieldBasic& field : searchStruct.basicFields) {
        if (!field.compare(keyAddr)) {
            return false;
        }
    }
    for (const StructFieldSequence& field : searchStruct.sequenceFields) {
        if (!field.compare(keyAddr)) {
            return false;
        }
    }
    return true;
}

bool StructScanner::checkMatch(const uint8_t* dataToCompare, ScanType scanType) const {
	switch (scanType) {
		case ScanType::EXACT:
			return compare(dataToCompare);
		case ScanType::NOT:
			return !compare(dataToCompare);
		case ScanType::CHANGED:
		case ScanType::UNCHANGED:
		case ScanType::INCREASED:
		case ScanType::DECREASED:
			addError("Only EXACT and NOT scans supported for structs");
			return false;
		default:
			addError("Invalid scan type in checkMatch: %d", (int)scanType);
			return false;
	}
}

// Validates the value in the buffer
// Entry point for this logic for rescan
bool StructScanner::validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
                                              uintptr_t actualAddress, ScanType scanType, const void* targetValue,
                                              ScanResult& outResult) const {
	// actualAddress is where the key byte was found in memory
	// Calculate struct base address by subtracting key's offset from base
	outResult.address = actualAddress - searchStruct.keyOffsetFromBase;

	// offset is where the key byte is in the buffer so we just need to make sure its larger than the size before
	// sizeBeforeKey includes the distance from base to key or any earlier fields
	if (offset < searchStruct.sizeBeforeKey) {
		return false;
	}
	// Check if we have enough bytes from the key position onwards
	if (offset + searchStruct.sizeFromKey > bufferSize) {
		return false;
	}

	// Compare directly from buffer (safe, already copied with SEH protection)
	// Pass the key position in buffer
	const uint8_t* keyAddr = buffer + offset;
	return checkMatch(keyAddr, scanType);
}

// Validates struct directly from memory with try/catch protection
// Does try/catch read and compare all in one
bool StructScanner::validateStructDirect(uintptr_t baseAddress, uintptr_t regionStart, uintptr_t regionEnd, ScanType scanType) const {
	// baseAddress is the struct base so we need to compute the key address since
	// our fields are all defined relative to the key
	uintptr_t keyAddress = baseAddress + searchStruct.keyOffsetFromBase;

	// Check we have enough bytes before the key
	// sizeBeforeKey includes the distance from base to key or any earlier fields
	if (keyAddress < regionStart + searchStruct.sizeBeforeKey) {
		return false;
	}
	// Check if we have enough bytes from the key position onwards
	if (keyAddress + searchStruct.sizeFromKey > regionEnd) {
		return false;
	}

	__try {
		// Compare directly with try/catch protection
		// Pass the key address
		return checkMatch((const uint8_t*)keyAddress, scanType);
	}
	__except (EXCEPTION_EXECUTE_HANDLER) {
		return false;
	}
}

bool StructScanner::setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize) {
	if (targetValue == nullptr) {
		addError("Struct types require non-null targetValue");
		return false;
	}

	const StructSearch* targetStruct = (const StructSearch*) targetValue;
	if (targetStruct->getSize() > MAX_STRUCT_SIZE) {
		addError("Struct size (%zu) exceeds maximum allowed size (%zu)", targetStruct->getSize(), MAX_STRUCT_SIZE);
		return false;
	}

	setSearchStruct(*targetStruct);
	return true;
}

bool StructScanner::validateFirstScanType(ScanType scanType) {
	// First scan for structs only supports EXACT
	if (scanType != ScanType::EXACT) {
		addError("First scan for structs only supports EXACT scan type");
		return false;
	}
	return true;
}

void StructScanner::scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
                                         ScanType scanType, const void* targetValue,
                                         std::vector<ScanResult>& localResults, size_t maxLocalResults) {
	// Optimized path using memchr to find key byte
	const uint8_t* searchStart = buffer;
	const uint8_t* bufferEnd = buffer + chunkSize;

	while (searchStart < bufferEnd && localResults.size() < maxLocalResults) {
		const uint8_t* found = (const uint8_t*)memchr(searchStart, searchStruct.searchKey, bufferEnd - searchStart);

		if (found == nullptr) {
			break;
		}

		// offset is the position of the key byte in the buffer
		size_t offset = found - buffer;

		// Calculate actual memory address where key was found
		uintptr_t actualAddress = chunkBase + offset;

		// Validate the full struct
		ScanResult result;
		if (validateValueInBuffer(buffer, chunkSize, offset, actualAddress, scanType, targetValue, result)) {
			localResults.push_back(result);
		}

		searchStart = found + 1;
	}
}

// Process a single isolated result with direct memory read for rescan
// Wrapper for validateStructDirect to match base class interface
bool StructScanner::validateValueDirect(uintptr_t address, uintptr_t regionStart, uintptr_t regionEnd,
                                           ScanType scanType, const void* targetValue, ScanResult& outResult) const {
	// Address parameter is the struct base address
	// Validate struct directly from memory with SEH protection
	if (!validateStructDirect(address, regionStart, regionEnd, scanType)) {
		return false;
	}

	// Set address in new result
	outResult.address = address;
	return true;
}

