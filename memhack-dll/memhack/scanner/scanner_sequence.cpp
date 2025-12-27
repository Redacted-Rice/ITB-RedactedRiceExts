#include "stdafx.h"
#include "scanner_sequence.h"
#include "../safememory.h"

#include <cmath>
#include <algorithm>
#include <windows.h>


SequenceScanner::SequenceScanner(DataType dataType, size_t maxResults, size_t alignment) :
	Scanner(dataType, maxResults, alignment)
{
	// Just default to 1 for sequences
	if (this->alignment == 0) {
		this->alignment = 1;
	}
	
	// todo: filter potential result by alignment?
}

SequenceScanner::~SequenceScanner() {}

size_t SequenceScanner::getDataTypeSize() const {
	size_t size = searchSequence.size();
	return size > 0 ? size : 1;
}

void SequenceScanner::setSearchSequence(const void* data, size_t size) {
	if (size == 0) {
		addError("Search sequence cannot be empty");
		return;
	}

	// Store search sequence in vector for scan lifetime
	const uint8_t* bytes = (const uint8_t*)data;
	searchSequence.assign(bytes, bytes + size);
}

bool SequenceScanner::compare(const uint8_t* a, const uint8_t* b, size_t size) const {
	// do mem compare to optimize and since we have the full
	// string read in already
	return memcmp(a, b, size) == 0;
}

bool SequenceScanner::checkMatch(const uint8_t* dataToCompare, ScanType scanType) const {
	switch (scanType) {
		case ScanType::EXACT:
			return compare(dataToCompare, searchSequence.data(), searchSequence.size());
		case ScanType::NOT:
			return !compare(dataToCompare, searchSequence.data(), searchSequence.size());
		case ScanType::CHANGED:
		case ScanType::UNCHANGED:
		case ScanType::INCREASED:
		case ScanType::DECREASED:
			addError("Only EXACT and NOT scans supported for STRING/BYTE_ARRAY");
			return false;
		default:
			addError("Invalid scan type in checkMatch: %d", (int)scanType);
			return false;
	}
}

// Validates the value in the buffer
// Entry point for this logic for rescan
bool SequenceScanner::validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
                                              uintptr_t actualAddress, ScanType scanType, const void* targetValue,
                                              ScanResult& outResult) const {
	outResult.address = actualAddress;

	// Check if sequence fits in buffer first
	if (offset + searchSequence.size() > bufferSize) {
		return false;
	}

	// Compare directly from buffer (safe, already copied with SEH protection)
	const uint8_t* bufferAddr = buffer + offset;
	return checkMatch(bufferAddr, scanType);
}

// Validates sequence directly from memory with try/catch protection
// Does try/catch read and compare all in one
bool SequenceScanner::validateSequenceDirect(uintptr_t address, uintptr_t regionEnd, ScanType scanType) const {
	size_t seqSize = searchSequence.size();

	// Check bounds first
	if (address + seqSize > regionEnd) {
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

bool SequenceScanner::setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize) {
	if (targetValue == nullptr || valueSize == 0) {
		addError("Sequence types require non-null targetValue with size > 0");
		return false;
	}

	if (valueSize > MAX_SEQUENCE_SIZE) {
		addError("Sequence size (%zu) exceeds maximum allowed size (%zu)", valueSize, MAX_SEQUENCE_SIZE);
		return false;
	}

	setSearchSequence(targetValue, valueSize);
	return true;
}

bool SequenceScanner::validateFirstScanType(ScanType scanType) {
	// First scan for sequences only supports EXACT
	if (scanType != ScanType::EXACT) {
		addError("First scan for sequences only supports EXACT scan type");
		return false;
	}
	return true;
}

void SequenceScanner::scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
                                         ScanType scanType, const void* targetValue,
                                         std::vector<ScanResult>& localResults, size_t maxLocalResults) {
	size_t dataSize = getDataTypeSize();
	
	// Optimized path using memchr
	const uint8_t firstByte = searchSequence[0];
	const uint8_t* searchStart = buffer;
	const uint8_t* bufferEnd = buffer + chunkSize;
	
	while (searchStart < bufferEnd && localResults.size() < maxLocalResults) {
		const uint8_t* found = (const uint8_t*)memchr(searchStart, firstByte, bufferEnd - searchStart);
		
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
bool SequenceScanner::validateValueDirect(uintptr_t address, uintptr_t regionEnd,
                                           ScanType scanType, const void* targetValue,
                                           ScanResult& outResult) const {
	// Validate sequence directly from memory with SEH protection
	if (!validateSequenceDirect(address, regionEnd, scanType)) {
		return false;
	}

	// Set address in result (sequences don't store value)
	outResult.address = address;
	return true;
}

bool SequenceScanner::readSequenceBytes(uintptr_t address, std::vector<uint8_t, ScannerAllocator<uint8_t>>& outBytes) const {
	size_t size = searchSequence.size();
	if (size == 0) {
		return false;
	}

	outBytes.clear();
	outBytes.reserve(size);

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

