#include "stdafx.h"
#include "scanner_struct.h"
#include "../safememory.h"

#include <cmath>
#include <algorithm>
#include <windows.h>


void* StructScanner::StructField::operator new(size_t size) {
	return ScannerHeap::allocate(size);
}

void StructScanner::StructField::operator delete(void* ptr) noexcept {
	if (ptr) {
		ScannerHeap::deallocate(ptr, 0);
	}
}

void* StructScanner::StructFieldBasic::operator new(size_t size) {
	return ScannerHeap::allocate(size);
}

void StructScanner::StructFieldBasic::operator delete(void* ptr) noexcept {
	if (ptr) {
		ScannerHeap::deallocate(ptr, 0);
	}
}

bool StructScanner::StructFieldBasic::compare(void* memoryAddr) const {
    return BasicSequence::compare(memoryAddr, &val, type):
}

void* StructScanner::StructFieldSequence::operator new(size_t size) {
	return ScannerHeap::allocate(size);
}

void StructScanner::StructFieldSequence::operator delete(void* ptr) noexcept {
	if (ptr) {
		ScannerHeap::deallocate(ptr, 0);
	}
}
    
bool StructScanner::StructFieldSequence::compare(void* memoryAddr) const {
    return SequenceScanner::compare(memoryAddr, val.data(), val.size()):
}

void* StructScanner::StructSearch::operator new(size_t size) {
	return ScannerHeap::allocate(size);
}

void StructScanner::StructSearch::operator delete(void* ptr) noexcept {
	if (ptr) {
		ScannerHeap::deallocate(ptr, 0);
	}
}

// ------- end of supporting struct defs -------

StructScanner::StructScanner(DataType dataType, size_t maxResults, size_t alignment) :
	Scanner(dataType, maxResults, alignment)
{
	// Just default to 1 for structs
	if (this->alignment == 0) {
		this->alignment = 1;
	}
	
	// todo: filter results by alignment?
}

StructScanner::~StructScanner() {}

size_t StructScanner::getDataTypeSize() const {
	return searchStruct.getSize();
}

void StructScanner::setSearchStruct(StructScanner& struct) {
    //todo: move
    searchStruct = struct;
}

bool StructScanner::compare(const void* keyAddr) const {
    for (StructFieldBasic field : basicFields) {
        if (!field.compare(keyAddr + field.offset)) {
            return false;
        }
    }
    for (StructFieldSequence field : sequenceFields) {
        if (!field.compare(keyAddr + field.offset)) {
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
	outResult.address = actualAddress;

	// Check if sequence fits in buffer first
	if (offset + searchStruct.sizeAfterKey > bufferSize) {
		return false;
	}

	// Compare directly from buffer (safe, already copied with SEH protection)
	const uint8_t* bufferAddr = buffer + offset;
	return checkMatch(bufferAddr, scanType);
}

// Validates sequence directly from memory with try/catch protection
// Does try/catch read and compare all in one
bool StructScanner::validateStructDirect(uintptr_t address, uintptr_t regionEnd, ScanType scanType) const {
	// Check bounds first
	if (address + searchStruct.sizeAfterKey > regionEnd) {
		return false;
	}

	__try {
		// Compare directly with try/catch protection
		return checkMatch((const uint8_t*)address, scanType);
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
	
	StructSearch* targetStruct = (StructSearch*) targetValue
	if (targetStruct->getSize() > MAX_STRUCT_SIZE) {
		addError("Struct size (%zu) exceeds maximum allowed size (%zu)", targetStruct->getSize(), MAX_STRUCT_SIZE);
		return false;
	}

	setSearchStruct(*targetStruct);
	return true;
}

bool StructScanner::validateFirstScanType(ScanType scanType) {
	// First scan for sequences only supports EXACT
	if (scanType != ScanType::EXACT) {
		addError("First scan for sequences only supports EXACT scan type");
		return false;
	}
	return true;
}

void StructScanner::scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
                                         ScanType scanType, const void* targetValue,
                                         std::vector<ScanResult>& localResults, size_t maxLocalResults) {
	size_t dataSize = getDataTypeSize();
	
	// Optimized path using memchr
	const uint8_t* searchStart = buffer;
	const uint8_t* bufferEnd = buffer + chunkSize;
	
	while (searchStart < bufferEnd && localResults.size() < maxLocalResults) {
		const uint8_t* found = (const uint8_t*)memchr(searchStart, searchStruct.searchKey, bufferEnd - searchStart);
		
		if (found == nullptr) {
			break;
		}
		
		size_t offset = found - buffer;
		
		if (offset + dataSize <= chunkSize) {
			uintptr_t actualAddress = chunkBase + offset;
			
			ScanResult result;
			if (validateValueInBuffer(buffer, chunkSize, offset, actualAddress, scanType, targetValue, result)) {
				localResults.push_back(result);
			}
		}
		
		searchStart = found + 1;
	}
}

// Process a single isolated result with direct memory read for rescan
// Wrapper for validateSequenceDirect to match base class interface
bool StructScanner::validateValueDirect(uintptr_t address, uintptr_t regionEnd, const void* targetValue,
                                           ScanResult& outResult) const {
	// Validate sequence directly from memory with SEH protection
	if (!validateStructDirect(address, regionEnd) {
		return false;
	}

	// Set address in result (structs don't store value)
	outResult.address = address;
	return true;
}

