#include "../stdafx.h"
#include "scanner/scanner_sequence.h"
#include "../safememory.h"

#include <cmath>
#include <algorithm>
#include <windows.h>

SequenceScanner::SequenceScanner(DataType dataType, size_t maxResults, size_t alignment) :
	Scanner(dataType, maxResults, alignment)
{
	// For sequence types, use byte alignment (1) since strings can appear at any offset
	// We use memchr-based search which efficiently finds matches regardless of alignment
	if (this->alignment == 0) {
		this->alignment = 1;
	}
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

bool SequenceScanner::compare(const uint8_t* dataToCompare) const {
	// do mem compare to optimize and since we have the full
	// string read in already
	return memcmp(dataToCompare, searchSequence.data(), searchSequence.size()) == 0;
}

bool SequenceScanner::checkMatch(const uint8_t* dataToCompare, ScanType scanType) const {
	switch (scanType) {
		case ScanType::EXACT:
			return compare(dataToCompare);
		case ScanType::NOT:
			return !compare(dataToCompare);
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
                                         ScanType scanType, const void* targetValue) {
	size_t dataSize = getDataTypeSize();

	// Optimized path for sequences using memchr
	const uint8_t firstByte = searchSequence[0];
	const uint8_t* searchStart = buffer;
	const uint8_t* bufferEnd = buffer + chunkSize;

	while (searchStart < bufferEnd && results.size() < maxResults) {
		// Find next occurrence of first byte
		const uint8_t* found = (const uint8_t*)memchr(searchStart, firstByte, bufferEnd - searchStart);

		if (found == nullptr) {
			break;
		}

		size_t offset = found - buffer;

		// Check if full sequence fits in buffer
		// TODO: I think this fit check is redundant with the check in validateValueInBuffer
		if (offset + dataSize <= chunkSize) {
			uintptr_t actualAddress = chunkBase + offset;

			// Validate the full sequence (using memcmp)
			ScanResult result;
			if (validateValueInBuffer(buffer, chunkSize, offset, actualAddress, scanType, targetValue, result)) {
				results.push_back(result);

				if (results.size() >= maxResults) {
					maxResultsReached = true;
					return;
				}
			}
		}

		// Move to next byte after the match
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

// Removed - base class handles rescanResultDirect, processResultsInRegion, rescanResultBatch, and rescanImpl now

bool SequenceScanner::readSequenceBytes(uintptr_t address, std::vector<uint8_t>& outBytes) const {
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

